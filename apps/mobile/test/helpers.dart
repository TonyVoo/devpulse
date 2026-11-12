import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:devpulse_mobile/core/auth/token_store.dart';
import 'package:devpulse_mobile/core/design_system/widgets/status_widgets.dart';
import 'package:devpulse_mobile/core/network/org_api.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/auth/data/auth_repository.dart';
import 'package:devpulse_mobile/features/auth/domain/models.dart';
import 'package:devpulse_mobile/features/copilot/data/ai_repository.dart';
import 'package:devpulse_mobile/features/copilot/domain/investigation.dart';
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

/// In-memory AI API. `runs` maps incident id → investigations (latest first).
class FakeAiRepository implements AiRepository {
  FakeAiRepository({Map<String, List<Investigation>>? runs, this.startError, this.askError}) : runs = runs ?? {};

  final Map<String, List<Investigation>> runs;
  Failure? startError;
  Failure? askError;
  final List<String> started = [];
  final List<(String, bool)> decisions = [];
  final List<(String, String)> asked = [];
  final Map<String, List<AiMessage>> messagesById = {};

  Investigation _byId(String id) => runs.values.expand((l) => l).firstWhere((i) => i.id == id);

  @override
  Future<List<InvestigationSummary>> forIncident(String incidentRef) async => [
    for (final i in runs.values.expand((l) => l))
      if (i.summary.incidentId == incidentRef || i.summary.incidentKey == incidentRef) i.summary,
  ];

  @override
  Future<Paged<InvestigationSummary>> recent({String? cursor}) async =>
      Paged([for (final i in runs.values.expand((l) => l)) i.summary], null);

  @override
  Future<Investigation> get(String id) async => _byId(id);

  @override
  Future<Investigation> start(String incidentRef) async {
    if (startError != null) throw startError!;
    started.add(incidentRef);
    throw const UnknownFailure('not scripted');
  }

  @override
  Future<List<AiMessage>> messages(String id) async => messagesById[id] ?? const [];

  @override
  Future<AskResult> ask(String id, String question, String clientId) async {
    asked.add((question, clientId));
    if (askError != null) throw askError!;
    final now = DateTime.now().toUtc().toIso8601String();
    final turn = [
      AiMessage.fromJson({'id': 'u$clientId', 'role': 'user', 'content': question, 'created_at': now}),
      AiMessage.fromJson({
        'id': 'a$clientId',
        'role': 'assistant',
        'content': 'Errors began right after the deploy.',
        'evidence_refs': ['EV-1'],
        'created_at': now,
      }),
    ];
    messagesById.putIfAbsent(id, () => []).addAll(turn);
    return AskResult(turn, const []);
  }

  @override
  Future<Proposal> decide(String id, String proposalId, {required bool approve, String? note}) async {
    decisions.add((proposalId, approve));
    final inv = _byId(id);
    final raw = Map<String, dynamic>.from(inv.raw);
    raw['proposals'] = [
      for (final p in (raw['proposals'] as List<dynamic>).cast<Map<String, dynamic>>())
        p['id'] == proposalId ? <String, dynamic>{...p, 'status': approve ? 'approved' : 'rejected'} : p,
    ];
    final updated = Investigation.fromJson(raw);
    for (final list in runs.values) {
      final idx = list.indexWhere((i) => i.id == id);
      if (idx >= 0) list[idx] = updated;
    }
    return updated.proposal(proposalId)!;
  }

  @override
  Future<void> feedback(String id, {required bool helpful}) async {}
}

/// API-shaped investigation JSON (see services/api AI schemas).
Map<String, dynamic> investigationJson({
  String id = 'inv-1',
  String incidentId = 'a',
  String incidentKey = 'INC-1001',
  String status = 'succeeded',
  String provider = 'fake',
  String? errorCode,
}) => {
  'id': id,
  'incident_id': incidentId,
  'incident_key': incidentKey,
  'incident_title': 'Checkout latency',
  'incident_severity': 'sev2',
  'trigger': 'manual',
  'status': status,
  'provider': provider,
  'model': provider == 'fake' ? 'fake-rules-v1' : 'claude-opus-5-5',
  'is_demo_provider': provider == 'fake',
  'summary': status == 'succeeded' ? 'Most likely (hypothesis): regression from v2.14.0.' : null,
  'error_code': errorCode,
  'error_detail': null,
  'created_at': DateTime.utc(2026, 11, 11, 10).toIso8601String(),
  'finished_at': null,
  'prompt_version': 'investigate_v1',
  'data_gaps': ['No traces'],
  'tool_calls_used': 0,
  'tokens_used': 0,
  'started_at': null,
  'requested_by': null,
  'my_feedback': null,
  'evidence': [
    {
      'ref': 'EV-1',
      'kind': 'deployment',
      'title': 'checkout deploy v2.14.0',
      'excerpt': {'text': 'checkout v2.14.0 deployed 12 min before the incident'},
      'source_query': {'type': 'deployment'},
      'observed_at': null,
    },
    {
      'ref': 'EV-2',
      'kind': 'metric',
      'title': 'checkout · p95 latency',
      'excerpt': {'text': 'baseline 180 → peak 1,400 at 10:02 UTC (+678%)'},
      'source_query': {'type': 'metric', 'name': 'http.server.duration_ms'},
      'observed_at': null,
    },
  ],
  'proposals': [
    {
      'id': 'p-1',
      'kind': 'remediate',
      'description': 'Roll back checkout to v2.13.2',
      'risk': 'sensitive',
      'status': 'proposed',
      'decided_by': null,
      'decided_at': null,
      'decision_note': null,
      'executes_automatically': false,
    },
  ],
  'result': status != 'succeeded'
      ? null
      : {
          'incident_id': incidentKey,
          'summary': 'Most likely (hypothesis): regression from v2.14.0.',
          'impact': 'Checkout p95 is 8x baseline',
          'probable_causes': [
            {
              'cause': 'Regression introduced by deployment v2.14.0',
              'status': 'hypothesis',
              'confidence': 0.65,
              'confidence_label': 'medium',
              'reasoning': 'Latency rose 4 minutes after the deploy.',
              'evidence_refs': ['EV-1', 'EV-2'],
              'counter_evidence_refs': <String>[],
              'how_to_verify': 'Compare latency before and after.',
            },
          ],
          'recommended_actions': [
            {
              'action': 'Diff v2.14.0 against v2.13.2',
              'kind': 'investigate',
              'risk': 'read_only',
              'rationale': '',
              'requires_approval': false,
              'proposal_id': null,
            },
            {
              'action': 'Roll back checkout to v2.13.2',
              'kind': 'remediate',
              'risk': 'sensitive',
              'rationale': '',
              'requires_approval': true,
              'proposal_id': 'p-1',
            },
          ],
          'data_gaps': ['No traces'],
          'limitations': 'Generated by the demo analyzer, not a language model.',
          'adjustments': <String>[],
        },
};
