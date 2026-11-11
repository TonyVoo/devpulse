import 'package:devpulse_mobile/app/providers.dart';
import 'package:devpulse_mobile/core/config/app_config.dart';
import 'package:devpulse_mobile/core/network/org_api.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/auth/presentation/session_controller.dart';
import 'package:devpulse_mobile/features/incidents/domain/incident.dart';
import 'package:devpulse_mobile/features/incidents/presentation/incident_detail.dart';
import 'package:devpulse_mobile/features/incidents/presentation/incidents_list.dart';
import 'package:devpulse_mobile/features/ops_repositories.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

ProviderContainer _container(FakeOpsRepository ops) {
  final c = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(session: true, remote: me())),
      opsRepositoryProvider.overrideWithValue(ops),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

List<Incident> _five() => [
  for (var i = 0; i < 5; i++)
    incidentFixture(id: 'i$i', number: 1001 + i, startedAt: DateTime.utc(2026, 11, 11, 10, i)),
];

void main() {
  group('IncidentsController', () {
    test('pages through results without duplicates', () async {
      final c = _container(FakeOpsRepository(incidents: _five()));
      final first = await c.read(incidentsProvider.future);
      expect(first.items.map((i) => i.id), ['i4', 'i3']);
      await c.read(incidentsProvider.notifier).loadMore();
      await c.read(incidentsProvider.notifier).loadMore();
      await c.read(incidentsProvider.notifier).loadMore(); // no-op at the end
      final all = c.read(incidentsProvider).value!;
      expect(all.items.map((i) => i.id), ['i4', 'i3', 'i2', 'i1', 'i0']);
      expect(all.hasMore, isFalse);
    });

    test('upsert replaces in place, ignores stale versions, drops filtered-out items', () async {
      final c = _container(FakeOpsRepository(incidents: _five()));
      await c.read(incidentsProvider.future);
      final ctl = c.read(incidentsProvider.notifier);

      ctl.upsert(incidentFixture(id: 'i3', number: 1004, status: IncidentStatus.acknowledged, version: 2));
      expect(c.read(incidentsProvider).value!.items.map((i) => i.status), [
        IncidentStatus.triggered,
        IncidentStatus.acknowledged,
      ]);

      ctl.upsert(incidentFixture(id: 'i3', number: 1004, version: 1)); // stale → ignored
      expect(c.read(incidentsProvider).value!.items[1].status, IncidentStatus.acknowledged);

      ctl.upsert(incidentFixture(id: 'i4', number: 1005, status: IncidentStatus.resolved, version: 2));
      expect(c.read(incidentsProvider).value!.items.map((i) => i.id), ['i3']); // "Open" filter

      ctl.upsert(incidentFixture(id: 'zzz', version: 9)); // not in list → never inserted
      expect(c.read(incidentsProvider).value!.items, hasLength(1));
    });

    test('filter changes reload the list', () async {
      final ops = FakeOpsRepository(
        incidents: [
          ..._five(),
          incidentFixture(id: 'r', number: 2000, status: IncidentStatus.resolved),
        ],
      );
      final c = _container(ops);
      await c.read(incidentsProvider.future);
      c.read(incidentFilterProvider.notifier).set(const IncidentFilter(statuses: {IncidentStatus.resolved}));
      final page = await c.read(incidentsProvider.future);
      expect(page.items.map((i) => i.id), ['r']);
    });
  });

  group('IncidentDetailController', () {
    test('acting updates the detail and the list', () async {
      final ops = FakeOpsRepository(incidents: _five());
      final c = _container(ops);
      await c.read(sessionControllerProvider.future);
      await c.read(incidentsProvider.future);
      final sub = c.listen(incidentDetailProvider('INC-1005'), (_, _) {});
      addTearDown(sub.close);
      await c.read(incidentDetailProvider('INC-1005').future);

      final r = await c.read(incidentDetailProvider('INC-1005').notifier).act(const Acknowledge());
      expect(r, isA<ActionOk>());
      expect(c.read(incidentDetailProvider('INC-1005')).value!.incident.status, IncidentStatus.acknowledged);
      expect(c.read(incidentsProvider).value!.byId['i4']!.status, IncidentStatus.acknowledged);
    });

    test('version conflict reloads and reports instead of failing silently', () async {
      final ops = FakeOpsRepository(incidents: _five());
      final c = _container(ops);
      final sub = c.listen(incidentDetailProvider('INC-1005'), (_, _) {});
      addTearDown(sub.close);
      await c.read(incidentDetailProvider('INC-1005').future);

      // Someone else resolves it on the server meanwhile.
      ops.serverSideUpdate(incidentFixture(id: 'i4', number: 1005, status: IncidentStatus.resolved, version: 3));
      final r = await c.read(incidentDetailProvider('INC-1005').notifier).act(const Acknowledge());
      expect(r, isA<ActionStale>());
      expect((r as ActionStale).message, contains('someone else'));
      expect(c.read(incidentDetailProvider('INC-1005')).value!.incident.status, IncidentStatus.resolved);
    });

    test('comments are optimistic and roll back on failure', () async {
      final ops = FakeOpsRepository(incidents: _five());
      final c = _container(ops);
      final sub = c.listen(incidentDetailProvider('INC-1005'), (_, _) {});
      addTearDown(sub.close);
      await c.read(incidentDetailProvider('INC-1005').future);
      final ctl = c.read(incidentDetailProvider('INC-1005').notifier);

      final pending = ctl.comment('On it');
      expect(c.read(incidentDetailProvider('INC-1005')).value!.comments.single.pending, isTrue);
      expect(await pending, isA<ActionOk>());
      final saved = c.read(incidentDetailProvider('INC-1005')).value!.comments.single;
      expect((saved.pending, saved.body), (false, 'On it'));
      expect(saved.clientId, ops.savedComments.single.clientId); // same id → safe retries

      ops.actFailure = null;
      final failing = _FailingComments(ops);
      final c2 = _container(failing);
      final sub2 = c2.listen(incidentDetailProvider('INC-1005'), (_, _) {});
      addTearDown(sub2.close);
      await c2.read(incidentDetailProvider('INC-1005').future);
      final r = await c2.read(incidentDetailProvider('INC-1005').notifier).comment('lost?');
      expect(r, isA<ActionFailed>());
      expect(c2.read(incidentDetailProvider('INC-1005')).value!.comments, isEmpty);
    });
  });

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

class _FailingComments extends FakeOpsRepository {
  _FailingComments(FakeOpsRepository base) : super(incidents: [for (var i = 0; i < 5; i++) base.stored('i$i')!]);

  @override
  Future<IncidentComment> comment(String ref, String body, String clientId) async => throw const NetworkFailure();
}
