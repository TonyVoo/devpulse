import 'package:devpulse_mobile/core/config/app_config.dart';
import 'package:devpulse_mobile/core/network/org_api.dart';
import 'package:devpulse_mobile/features/incidents/domain/incident.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('OrgApi', () {
    test('commands carry an Idempotency-Key and If-Match; list filters repeat params', () async {
      final adapter = FakeAdapter(
        (o) => o.method == 'GET' ? jsonBody({'items': <dynamic>[], 'next_cursor': null}) : jsonBody({'ok': true}),
      );
      final dio = Dio(BaseOptions(baseUrl: '${const AppConfig(apiBaseUrl: 'http://api.test').apiV1}/'))
        ..httpClientAdapter = adapter;
      final api = OrgApi(dio, 'org-1');

      await api.command('incidents/x/acknowledge', ifMatchVersion: 4);
      final cmd = adapter.requests.single;
      expect(cmd.uri.path, '/api/v1/orgs/org-1/incidents/x/acknowledge');
      expect(cmd.headers['If-Match'], '"4"');
      expect(cmd.headers['Idempotency-Key'], matches(RegExp(r'^[0-9a-f-]{36}$')));

      await api.page('incidents', (j) => j, query: const IncidentFilter().toQuery());
      expect(adapter.requests.last.uri.query, contains('status=triggered&status=acknowledged'));
    });
  });
}
