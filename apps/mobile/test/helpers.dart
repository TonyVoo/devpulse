import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:devpulse_mobile/core/auth/token_store.dart';
import 'package:devpulse_mobile/core/design_system/widgets/status_widgets.dart';
import 'package:devpulse_mobile/core/network/org_api.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/auth/data/auth_repository.dart';
import 'package:devpulse_mobile/features/auth/domain/models.dart';
import 'package:devpulse_mobile/features/deployments/domain/deployment.dart';
import 'package:devpulse_mobile/features/incidents/domain/incident.dart';
import 'package:devpulse_mobile/features/ops_repositories.dart';
import 'package:devpulse_mobile/features/overview/domain/overview.dart';
import 'package:devpulse_mobile/features/services/domain/service.dart';
import 'package:dio/dio.dart';

typedef Handler = FutureOr<ResponseBody> Function(RequestOptions options);

/// Scriptable Dio transport for tests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Handler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? body, {int status = 200, Map<String, List<String>>? headers}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...?headers,
  },
);

ResponseBody problemBody(int status, String code, [String detail = 'error']) =>
    jsonBody({'status': status, 'code': code, 'detail': detail, 'title': detail}, status: status);

AuthTokens tokens(String access, {Duration expiresIn = const Duration(minutes: 15), String refresh = 'rt-1'}) =>
    AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      accessExpiresAt: DateTime.now().toUtc().add(expiresIn),
      sessionId: 'sess-1',
    );

const orgA = OrgMembership(id: 'org-a', slug: 'acme', name: 'Acme', role: OrgRole.owner);
const orgB = OrgMembership(id: 'org-b', slug: 'bravo', name: 'Bravo', role: OrgRole.viewer);

Me me({List<OrgMembership> orgs = const [orgA]}) =>
    Me(id: 'u1', email: 'ada@example.com', displayName: 'Ada', memberships: orgs);

/// In-memory [AuthRepository] with scriptable failures.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.session = false, this.remote, this.cached, this.fetchError, this.savedOrg});

  bool session;
  Me? remote;
  Me? cached;
  Failure? fetchError;
  Failure? loginError;
  String? savedOrg;
  int logoutCalls = 0;

  @override
  Future<bool> hasSession() async => session;

  @override
  Future<Me> fetchMe() async {
    if (fetchError != null) throw fetchError!;
    cached = remote;
    return remote!;
  }

  @override
  Future<Me?> cachedMe() async => cached;

  @override
  Future<Me> login({required String email, required String password}) async {
    if (loginError != null) throw loginError!;
    session = true;
    return fetchMe();
  }

  @override
  Future<Me> register({required String email, required String password, required String displayName}) =>
      login(email: email, password: password);

  @override
  Future<OrgMembership> createOrg(String name) async {
    final org = OrgMembership(id: 'org-new', slug: 'new', name: name, role: OrgRole.owner);
    remote = me(orgs: [...?remote?.memberships, org]);
    return org;
  }

  @override
  Future<String?> savedOrgId() async => savedOrg;

  @override
  Future<void> saveOrgId(String orgId) async => savedOrg = orgId;

  @override
  Future<void> logout() async {
    logoutCalls++;
    await clearLocal();
  }

  @override
  Future<void> clearLocal() async {
    session = false;
    cached = null;
    savedOrg = null;
  }
}

// ------------------------------------------------------------------------- phase 2

/// In-memory [OpsRepository] with call recording and scriptable failures.
class FakeOpsRepository implements OpsRepository {
  FakeOpsRepository({List<Incident>? incidents, this.overviewValue})
    : _incidents = {for (final i in incidents ?? <Incident>[]) i.id: i};

  final Map<String, Incident> _incidents;
  Overview? overviewValue;
  Failure? actFailure;
  final List<String> actions = [];
  final List<IncidentComment> savedComments = [];

  Incident? stored(String id) => _incidents[id];

  void serverSideUpdate(Incident i) => _incidents[i.id] = i;

  @override
  Future<Overview> overview(OverviewWindow window) async => overviewValue ?? emptyOverview();

  @override
  Future<Paged<MonitoredService>> services({String? query, Set<Health> health = const {}, String? cursor}) async =>
      const Paged([], null);

  @override
  Future<MonitoredService> service(String id) => throw UnimplementedError();

  @override
  Future<List<MetricSeries>> metrics(String serviceId, List<String> names, MetricRange range) async => const [];

  @override
  Future<Paged<Incident>> incidents(IncidentFilter filter, {String? cursor, String? serviceId}) async {
    final all = _incidents.values.where((i) => filter.statuses.isEmpty || filter.statuses.contains(i.status)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + 2).clamp(0, all.length); // tiny pages to exercise pagination
    return Paged(all.sublist(start, end), end < all.length ? '$end' : null);
  }

  @override
  Future<Incident> incident(String ref) async =>
      _incidents.values.firstWhere((i) => i.id == ref || i.key.toLowerCase() == ref.toLowerCase());

  @override
  Future<List<TimelineEvent>> timeline(String ref) async => [
    TimelineEvent(
      id: 'e1',
      type: 'created',
      actorType: 'system',
      at: DateTime(2026),
      data: const {'rule': 'High latency'},
    ),
  ];

  @override
  Future<List<IncidentComment>> comments(String ref) async => savedComments;

  @override
  Future<List<CorrelatedDeployment>> correlated(String ref) async => const [];

  @override
  Future<Paged<Deployment>> deployments({String? serviceId, String? cursor}) async => const Paged([], null);
}

Incident incidentFixture({
  required String id,
  int number = 1001,
  IncidentStatus status = IncidentStatus.triggered,
  int version = 1,
  Severity severity = Severity.sev2,
  DateTime? startedAt,
  String title = 'Checkout latency',
}) => Incident.fromJson({
  'id': id,
  'key': 'INC-$number',
  'title': title,
  'summary': null,
  'severity': severity.name,
  'status': status.name,
  'started_at': (startedAt ?? DateTime.utc(2026, 11, 11, 10)).toIso8601String(),
  'updated_at': DateTime.utc(2026, 11, 11, 10).toIso8601String(),
  'version': version,
  'is_demo': false,
  'escalation_level': 0,
  'source': 'alert',
  'service': {'id': 'svc-1', 'name': 'checkout', 'slug': 'checkout'},
  'assignee': null,
});

Overview emptyOverview() => Overview.fromJson({
  'services_total': 0,
  'services_by_health': {'healthy': 0, 'degraded': 0, 'critical': 0, 'unknown': 0},
  'open_incidents_by_severity': {'sev1': 0, 'sev2': 0, 'sev3': 0, 'sev4': 0},
  'totals': {'requests': null, 'errors': null, 'error_rate': null, 'latency_avg_ms': null, 'latency_p95_ms': null},
  'request_series': <dynamic>[],
  'recent_incidents': <dynamic>[],
  'recent_deployments': <dynamic>[],
  'has_telemetry': false,
});
