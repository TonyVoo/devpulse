/// Data access for the Phase 2 product screens (online). Offline caching + delta sync
/// replace the direct reads in Phase 3 behind the same interfaces.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/design_system/widgets/status_widgets.dart';
import '../core/network/org_api.dart';
import 'auth/domain/models.dart';
import 'auth/presentation/session_controller.dart';
import 'deployments/domain/deployment.dart';
import 'incidents/domain/incident.dart';
import 'overview/domain/overview.dart';
import 'services/domain/service.dart';

/// API client bound to the selected organization; rebuilds when the org changes.
final orgApiProvider = Provider<OrgApi>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  final orgId = session is SignedIn ? session.currentOrgId : null;
  if (orgId == null) throw StateError('No organization selected');
  return OrgApi(ref.watch(dioProvider), orgId);
});

abstract interface class OpsRepository {
  Future<Overview> overview(OverviewWindow window);

  Future<Paged<MonitoredService>> services({String? query, Set<Health> health, String? cursor});
  Future<MonitoredService> service(String id);
  Future<List<MetricSeries>> metrics(String serviceId, List<String> names, MetricRange range);

  Future<Paged<Incident>> incidents(IncidentFilter filter, {String? cursor, String? serviceId});
  Future<Incident> incident(String ref);
  Future<List<TimelineEvent>> timeline(String ref);
  Future<List<IncidentComment>> comments(String ref);
  Future<List<CorrelatedDeployment>> correlated(String ref);
  Future<Incident> act(Incident incident, IncidentAction action);
  Future<IncidentComment> comment(String ref, String body, String clientId);

  Future<Paged<Deployment>> deployments({String? serviceId, String? cursor});
}

sealed class IncidentAction {
  const IncidentAction();
  String get path;
  Map<String, dynamic> get body => const {};
}

class Acknowledge extends IncidentAction {
  const Acknowledge();
  @override
  String get path => 'acknowledge';
}

class Resolve extends IncidentAction {
  const Resolve({this.note});
  final String? note;
  @override
  String get path => 'resolve';
  @override
  Map<String, dynamic> get body => {'resolution_note': ?note};
}

class Reopen extends IncidentAction {
  const Reopen();
  @override
  String get path => 'reopen';
}

class Escalate extends IncidentAction {
  const Escalate();
  @override
  String get path => 'escalate';
}

class AssignTo extends IncidentAction {
  const AssignTo(this.userId);
  final String? userId;
  @override
  String get path => 'assign';
  @override
  Map<String, dynamic> get body => {'user_id': userId};
}

class ApiOpsRepository implements OpsRepository {
  ApiOpsRepository(this._api);

  final OrgApi _api;

  @override
  Future<Overview> overview(OverviewWindow window) async =>
      Overview.fromJson(await _api.get('overview', query: {'window': window.label}), step: window.step);

  @override
  Future<Paged<MonitoredService>> services({String? query, Set<Health> health = const {}, String? cursor}) => _api.page(
    'services',
    MonitoredService.fromJson,
    cursor: cursor,
    query: {
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (health.isNotEmpty) 'health': [for (final h in health) h.name],
      'limit': 100,
    },
  );

  @override
  Future<MonitoredService> service(String id) async => MonitoredService.fromJson(await _api.get('services/$id'));

  @override
  Future<List<MetricSeries>> metrics(String serviceId, List<String> names, MetricRange range) async {
    final to = DateTime.now().toUtc();
    final body = await _api.get(
      'services/$serviceId/metrics',
      query: {'names': names, 'from': to.subtract(range.span).toIso8601String(), 'to': to.toIso8601String()},
    );
    final step = Duration(seconds: body['step_s'] as int);
    return [
      for (final s in body['series'] as List<dynamic>) MetricSeries.fromJson(s as Map<String, dynamic>, step: step),
    ];
  }

  @override
  Future<Paged<Incident>> incidents(IncidentFilter filter, {String? cursor, String? serviceId}) => _api.page(
    'incidents',
    Incident.fromJson,
    cursor: cursor,
    query: {...filter.toQuery(), 'service_id': ?serviceId, 'limit': 25},
  );

  @override
  Future<Incident> incident(String ref) async => Incident.fromJson(await _api.get('incidents/$ref'));

  @override
  Future<List<TimelineEvent>> timeline(String ref) async {
    final body = await _api.get('incidents/$ref/timeline', query: {'limit': 200});
    return [for (final e in body['items'] as List<dynamic>) TimelineEvent.fromJson(e as Map<String, dynamic>)];
  }

  @override
  Future<List<IncidentComment>> comments(String ref) async {
    final body = await _api.get('incidents/$ref/comments', query: {'limit': 200});
    return [for (final c in body['items'] as List<dynamic>) IncidentComment.fromJson(c as Map<String, dynamic>)];
  }

  @override
  Future<List<CorrelatedDeployment>> correlated(String ref) async => [
    for (final d in await _api.getList('incidents/$ref/deployments'))
      CorrelatedDeployment.fromJson(d as Map<String, dynamic>),
  ];

  @override
  Future<Incident> act(Incident incident, IncidentAction action) async => Incident.fromJson(
    await _api.command('incidents/${incident.id}/${action.path}', body: action.body, ifMatchVersion: incident.version),
  );

  @override
  Future<IncidentComment> comment(String ref, String body, String clientId) async {
    final r = await _api.command('incidents/$ref/comments', body: {'body': body, 'client_id': clientId});
    return IncidentComment.fromJson(r);
  }

  @override
  Future<Paged<Deployment>> deployments({String? serviceId, String? cursor}) =>
      _api.page('deployments', Deployment.fromJson, cursor: cursor, query: {'service_id': ?serviceId, 'limit': 30});
}

final opsRepositoryProvider = Provider<OpsRepository>((ref) => ApiOpsRepository(ref.watch(orgApiProvider)));
