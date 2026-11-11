import 'dart:async';
import 'dart:convert';

import 'package:devpulse_mobile/core/network/org_api.dart';
import 'package:dio/dio.dart';

import '../helpers.dart';

const testOrg = 'org-a';

/// In-memory DevPulse API for offline/sync tests. Mirrors the server contract that matters
/// here: the change feed (monotonic change_seq), If-Match versions, Idempotency-Key replay,
/// incident transitions, and comments idempotent on client_id. `online = false` simulates
/// airplane mode (connection errors).
class FakeServer {
  bool online = true;

  /// Process the next command but lose the response (connection drops after the server
  /// committed). The client must retry with the same Idempotency-Key.
  bool dropNextResponse = false;

  int _seq = 0;
  final Map<String, Map<String, dynamic>> incidents = {};
  final Map<String, int> _incidentSeq = {};
  final Map<String, Map<String, dynamic>> services = {};
  final Map<String, int> _serviceSeq = {};
  final Set<String> deletedServices = {};
  final Map<String, Map<String, dynamic>> _idempotent = {};
  final List<Map<String, dynamic>> comments = [];
  final List<String> appliedCommands = [];
  final List<RequestOptions> requests = [];

  int get seq => _seq;

  void putIncident(Map<String, dynamic> json) {
    incidents[json['id'] as String] = json;
    _incidentSeq[json['id'] as String] = ++_seq;
  }

  void putService(Map<String, dynamic> json) {
    services[json['id'] as String] = json;
    _serviceSeq[json['id'] as String] = ++_seq;
  }

  void deleteService(String id) {
    deletedServices.add(id);
    _serviceSeq[id] = ++_seq;
  }

  /// A server-side change by someone else.
  void changeIncident(String id, Map<String, dynamic> patch) {
    final current = incidents[id]!;
    putIncident({...current, ...patch, 'version': (current['version'] as int) + 1});
  }

  OrgApi api() => OrgApi(dio(), testOrg);

  Dio dio() => Dio(BaseOptions(baseUrl: 'http://api.test/api/v1/'))..httpClientAdapter = FakeAdapter(_handle);

  Future<ResponseBody> _handle(RequestOptions o) async {
    requests.add(o);
    if (!online) throw DioException.connectionError(requestOptions: o, reason: 'offline (test)');
    final path = o.uri.path.replaceFirst('/api/v1/', '');
    if (path == 'realtime/ticket') return problemBody(503, 'unavailable');
    final p = path.replaceFirst('orgs/$testOrg/', '');
    final segs = p.split('/');

    if (segs.first == 'sync' && o.method == 'GET') {
      return _sync(segs[1], int.parse('${o.queryParameters['cursor'] ?? 0}'));
    }
    if (segs.first == 'incidents' && segs.length == 2 && o.method == 'GET') {
      final inc = incidents[segs[1]] ?? incidents.values.where((i) => i['key'] == segs[1]).firstOrNull;
      return inc == null ? problemBody(404, 'incident.not_found') : jsonBody(inc);
    }
    if (segs.first == 'incidents' && segs.length == 3 && o.method == 'POST') {
      final key = o.headers['Idempotency-Key'] as String?;
      if (key != null && _idempotent.containsKey(key)) return jsonBody(_idempotent[key]);
      final result = segs[2] == 'comments' ? _comment(segs[1], o) : _command(segs[1], segs[2], o);
      if (result.statusCode < 300 && key != null) {
        _idempotent[key] = jsonDecode(await utf8.decodeStream(result.stream)) as Map<String, dynamic>;
        final stored = jsonBody(_idempotent[key]);
        if (dropNextResponse) {
          dropNextResponse = false;
          throw DioException.connectionError(requestOptions: o, reason: 'response lost (test)');
        }
        return stored;
      }
      return result;
    }
    return problemBody(404, 'not_found');
  }

  ResponseBody _sync(String collection, int cursor) {
    final changes = <Map<String, dynamic>>[];
    if (collection == 'incidents') {
      for (final e in _incidentSeq.entries.where((e) => e.value > cursor)) {
        changes.add({'op': 'upsert', 'id': e.key, 'change_seq': e.value, 'data': incidents[e.key]});
      }
    } else if (collection == 'services') {
      for (final e in _serviceSeq.entries.where((e) => e.value > cursor)) {
        final deleted = deletedServices.contains(e.key);
        changes.add({
          'op': deleted ? 'delete' : 'upsert',
          'id': e.key,
          'change_seq': e.value,
          'data': deleted ? null : services[e.key],
        });
      }
    }
    changes.sort((a, b) => (a['change_seq'] as int).compareTo(b['change_seq'] as int));
    return jsonBody({
      'collection': collection,
      'changes': changes,
      'next_cursor': _seq > cursor ? _seq : cursor,
      'has_more': false,
    });
  }

  ResponseBody _command(String id, String action, RequestOptions o) {
    final inc = incidents[id];
    if (inc == null) return problemBody(404, 'incident.not_found');
    final ifMatch = (o.headers['If-Match'] as String?)?.replaceAll('"', '');
    if (ifMatch != null && int.parse(ifMatch) != inc['version']) {
      return jsonBody({
        'status': 409,
        'code': 'conflict.version_mismatch',
        'detail': 'changed',
        'title': 'Conflict',
        'current_version': inc['version'],
      }, status: 409);
    }
    final status = inc['status'] as String;
    String? next;
    switch (action) {
      case 'acknowledge':
        if (status != 'triggered') return problemBody(409, 'incident.invalid_transition', "Can't acknowledge");
        next = 'acknowledged';
      case 'resolve':
        if (status == 'resolved') return problemBody(409, 'incident.invalid_transition', "Can't resolve");
        next = 'resolved';
      case 'reopen':
        next = 'triggered';
      default:
        next = status;
    }
    appliedCommands.add('$action:$id');
    changeIncident(id, {'status': next});
    return jsonBody(incidents[id]);
  }

  ResponseBody _comment(String id, RequestOptions o) {
    final body = o.data as Map<String, dynamic>;
    final existing = comments.where((c) => c['client_id'] == body['client_id']).firstOrNull;
    if (existing != null) return jsonBody(existing);
    final c = {
      'id': 'c${comments.length + 1}',
      'client_id': body['client_id'],
      'body': body['body'],
      'author': {'id': 'u1', 'display_name': 'Ada'},
      'created_at': DateTime.utc(2026, 11, 11, 12).toIso8601String(),
      'incident_id': id,
    };
    comments.add(c);
    return jsonBody(c, status: 201);
  }
}

Map<String, dynamic> incidentJson(
  String id, {
  int number = 1001,
  String status = 'triggered',
  int version = 1,
  String title = 'Checkout latency',
  String severity = 'sev2',
  int minute = 0,
}) => {
  'id': id,
  'number': number,
  'key': 'INC-$number',
  'title': title,
  'summary': null,
  'severity': severity,
  'status': status,
  'service': {'id': 'svc-1', 'name': 'checkout', 'slug': 'checkout'},
  'assignee': null,
  'escalation_level': 0,
  'source': 'alert',
  'started_at': DateTime.utc(2026, 11, 11, 10, minute).toIso8601String(),
  'acknowledged_at': null,
  'resolved_at': null,
  'resolution_note': null,
  'root_cause_confirmed': null,
  'is_demo': false,
  'version': version,
  'updated_at': DateTime.utc(2026, 11, 11, 10).toIso8601String(),
};

Map<String, dynamic> serviceJson(String id, String name, {String health = 'healthy'}) => {
  'id': id,
  'slug': name,
  'name': name,
  'description': null,
  'environment': 'production',
  'tier': 'high',
  'owner_team': null,
  'repo_url': null,
  'health': health,
  'health_changed_at': null,
  'last_seen_at': null,
  'tags': <String, dynamic>{},
  'is_demo': false,
  'version': 1,
  'created_at': DateTime.utc(2026).toIso8601String(),
  'updated_at': DateTime.utc(2026).toIso8601String(),
};
