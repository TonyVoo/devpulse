import 'dart:io';

import 'package:devpulse_mobile/core/database/app_database.dart';
import 'package:devpulse_mobile/features/incidents/domain/incident.dart';
import 'package:devpulse_mobile/features/offline/local_store.dart';
import 'package:devpulse_mobile/features/offline/outbox.dart';
import 'package:devpulse_mobile/features/offline/sync_engine.dart';
import 'package:devpulse_mobile/features/push/push_routing.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/fake_server.dart';

class _Rig {
  _Rig()
    : server = FakeServer(),
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)) {
    store = LocalStore(db, testOrg);
    final api = server.api();
    engine = SyncEngine(api, store);
    outbox = OutboxProcessor(api, store);
  }

  final FakeServer server;
  final AppDatabase db;
  late final LocalStore store;
  late final SyncEngine engine;
  late final OutboxProcessor outbox;

  Future<List<Incident>> incidents([IncidentFilter filter = const IncidentFilter(statuses: {})]) =>
      store.watchIncidents(filter).first;

  Future<int> outboxSize() async => (await db.select(db.outboxEntries).get()).length;

  Future<void> dispose() async {
    await outbox.dispose();
    await db.close();
  }
}

void main() {
  late _Rig rig;
  setUp(() => rig = _Rig());
  tearDown(() => rig.dispose());

  group('sync engine', () {
    test('initial + delta sync, cursor persisted, no duplicates', () async {
      rig.server
        ..putIncident(incidentJson('a', number: 1001, minute: 1))
        ..putIncident(incidentJson('b', number: 1002, minute: 2));
      await rig.engine.sync('incidents');
      expect((await rig.incidents()).map((i) => i.key), ['INC-1002', 'INC-1001']);
      expect(await rig.store.cursor('incidents'), rig.server.seq);

      rig.server.changeIncident('a', {'status': 'acknowledged'});
      final before = rig.server.requests.length;
      await rig.engine.sync('incidents');
      expect(rig.server.requests.length, before + 1);
      final all = await rig.incidents();
      expect(all, hasLength(2)); // updated in place, not appended
      expect(all.firstWhere((i) => i.id == 'a').status, IncidentStatus.acknowledged);
    });

    test('hints at or below the cursor cost no request', () async {
      rig.server.putIncident(incidentJson('a'));
      await rig.engine.sync('incidents');
      final before = rig.server.requests.length;
      await rig.engine.onHint('incidents', rig.server.seq);
      expect(rig.server.requests.length, before);
      rig.server.changeIncident('a', {'title': 'Renamed'});
      await rig.engine.onHint('incidents', rig.server.seq);
      expect((await rig.incidents()).single.title, 'Renamed');
    });

    test('an older copy never overwrites a newer one', () async {
      rig.server.putIncident(incidentJson('a', version: 3, title: 'New'));
      await rig.engine.sync('incidents');
      await rig.store.upsertIncidentFromSync(incidentJson('a', version: 1, title: 'Old'), 0);
      await rig.store.upsertIncidentFromCommand(incidentJson('a', version: 2, title: 'Older command'));
      expect((await rig.incidents()).single.title, 'New');
    });

    test('tombstones remove deleted services', () async {
      rig.server
        ..putService(serviceJson('s1', 'api'))
        ..putService(serviceJson('s2', 'web'));
      await rig.engine.sync('services');
      expect((await rig.store.watchServices().first).map((s) => s.name), ['api', 'web']);
      rig.server.deleteService('s1');
      await rig.engine.sync('services');
      expect((await rig.store.watchServices().first).map((s) => s.name), ['web']);
    });

    test('a failed sync leaves the cursor unchanged', () async {
      rig.server.putIncident(incidentJson('a'));
      rig.server.online = false;
      await expectLater(rig.engine.sync('incidents'), throwsA(anything));
      expect(await rig.store.cursor('incidents'), 0);
      rig.server.online = true;
      await rig.engine.sync('incidents');
      expect(await rig.incidents(), hasLength(1));
    });
  });

  group('outbox (offline commands)', () {
    Future<Incident> synced(String id) async {
      rig.server.putIncident(incidentJson(id));
      await rig.engine.sync('incidents');
      return (await rig.store.incident(id))!;
    }

    test('airplane mode: acknowledge applies locally, replays once when back online', () async {
      final inc = await synced('a');
      rig.server.online = false;
      await rig.outbox.enqueueAction(inc, 'acknowledge', const {});
      await rig.outbox.flush();

      final local = (await rig.store.incident('a'))!;
      expect(local.status, IncidentStatus.acknowledged); // optimistic
      expect(local.isPending, isTrue);
      expect(await rig.outboxSize(), 1);
      expect(rig.server.incidents['a']!['status'], 'triggered');

      // Open list drops nothing; "Triggered" view no longer shows it.
      final triggered = await rig.store
          .watchIncidents(const IncidentFilter(statuses: {IncidentStatus.triggered}))
          .first;
      expect(triggered, isEmpty);

      rig.server.online = true;
      await rig.outbox.flush(ignoreBackoff: true);
      expect(rig.server.appliedCommands, ['acknowledge:a']);
      expect(rig.server.incidents['a']!['status'], 'acknowledged');
      final confirmed = (await rig.store.incident('a'))!;
      expect((confirmed.isPending, confirmed.version), (false, 2));
      expect(await rig.outboxSize(), 0);
    });

    test('transient failures back off instead of hammering the server', () async {
      final inc = await synced('a');
      rig.server.online = false;
      await rig.outbox.enqueueAction(inc, 'acknowledge', const {});
      await rig.outbox.flush();
      final attemptsAfterFirst = rig.server.requests.length;
      await rig.outbox.flush(); // still inside the backoff window → no request
      expect(rig.server.requests.length, attemptsAfterFirst);
      final row = (await rig.db.select(rig.db.outboxEntries).get()).single;
      expect(row.attempts, 1);
      expect(row.lastError, contains("Can't reach"));
    });

    test('a lost response is retried with the same key and applied exactly once', () async {
      final inc = await synced('a');
      rig.server.dropNextResponse = true;
      await rig.outbox.enqueueAction(inc, 'acknowledge', const {});
      await rig.outbox.flush();
      expect(rig.server.appliedCommands, ['acknowledge:a']); // server committed
      expect(await rig.outboxSize(), 1); // client didn't get the answer

      await rig.outbox.flush(ignoreBackoff: true);
      expect(rig.server.appliedCommands, ['acknowledge:a']); // NOT applied twice
      expect(await rig.outboxSize(), 0);
      expect((await rig.store.incident('a'))!.status, IncidentStatus.acknowledged);
    });

    test('conflict: someone else changed it → dropped, refreshed, user told', () async {
      final inc = await synced('a');
      rig.server.online = false;
      await rig.outbox.enqueueAction(inc, 'acknowledge', const {});
      rig.server
        ..online = true
        ..changeIncident('a', {'status': 'resolved', 'title': 'Resolved by Sam'});
      final notices = <OutboxNotice>[];
      final sub = rig.outbox.notices.listen(notices.add);

      await rig.outbox.flush(ignoreBackoff: true);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(rig.server.appliedCommands, isEmpty);
      expect(notices.single, isA<OutboxConflict>());
      expect((notices.single as OutboxConflict).message, contains('someone else'));
      final local = (await rig.store.incident('a'))!;
      expect((local.status, local.isPending, local.title), (IncidentStatus.resolved, false, 'Resolved by Sam'));
      expect(await rig.outboxSize(), 0);
    });

    test('queued commands replay in order', () async {
      final inc = await synced('a');
      rig.server.online = false;
      await rig.outbox.enqueueAction(inc, 'acknowledge', const {});
      // The user resolves on top of the pending acknowledge (version the user saw).
      await rig.outbox.enqueueAction(inc, 'resolve', const {'resolution_note': 'done'});
      rig.server.online = true;
      await rig.outbox.flush(ignoreBackoff: true);
      expect(rig.server.appliedCommands.first, 'acknowledge:a');
    });

    test('offline comments are shown as pending and sent idempotently', () async {
      await synced('a');
      rig.server.online = false;
      final clientId = await rig.outbox.enqueueComment('a', 'Looking into it');
      final pending = await rig.outbox.watchPendingComments('a').first;
      expect(pending.single.body, 'Looking into it');

      rig.server
        ..online = true
        ..dropNextResponse = true;
      await rig.outbox.flush(ignoreBackoff: true); // response lost
      await rig.outbox.flush(ignoreBackoff: true); // retried
      expect(rig.server.comments.single['client_id'], clientId);
      expect(await rig.outbox.watchPendingComments('a').first, isEmpty);
    });

    test('permanent failures are kept as failed and the optimistic state is undone', () async {
      final inc = await synced('a');
      rig.server.incidents.remove('a'); // server says 404 (e.g. access removed)
      final notices = <OutboxNotice>[];
      final sub = rig.outbox.notices.listen(notices.add);
      await rig.outbox.enqueueAction(inc, 'acknowledge', const {});
      await rig.outbox.flush(ignoreBackoff: true);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(notices.single, isA<OutboxFailed>());
      expect((await rig.store.incident('a'))!.isPending, isFalse);
      expect((await rig.db.select(rig.db.outboxEntries).get()).single.state, 'failed');
    });
  });

  group('database migration', () {
    test('v1 → v2 keeps existing data and adds the offline cache', () async {
      final dir = await Directory.systemTemp.createTemp('dp-migration');
      final file = File('${dir.path}/db.sqlite');
      final raw = sqlite.sqlite3.open(file.path)
        ..execute(
          'CREATE TABLE key_value_entries (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
        )
        ..execute("INSERT INTO key_value_entries VALUES ('theme', 'dark', 0)")
        ..execute('PRAGMA user_version = 1');
      raw.close();

      final db = AppDatabase(NativeDatabase(file));
      expect(await db.readString(KvKeys.theme), 'dark');
      await LocalStore(db, testOrg).upsertIncidentFromSync(incidentJson('a'), 1);
      expect(await db.select(db.cachedIncidents).get(), hasLength(1));
      await db.close();
      await dir.delete(recursive: true);
    });
  });

  group('push routing', () {
    test('accepts only in-app incident routes', () {
      expect(PushPayload.parse({'route': '/incidents/INC-1042', 'org_id': 'o'})?.route, '/incidents/INC-1042');
      expect(PushPayload.parse({'route': 'https://evil.example', 'org_id': 'o'}), isNull);
      expect(PushPayload.parse({'route': '/settings/../../x', 'org_id': 'o'}), isNull);
      expect(PushPayload.parse({'route': '/incidents/INC-1'}), isNull);
    });
  });

  test('sign-out wipes the offline cache and the queue', () async {
    rig.server.putIncident(incidentJson('a'));
    await rig.engine.sync('incidents');
    rig.server.online = false;
    await rig.outbox.enqueueComment('a', 'x');
    await rig.db.clearUserData();
    expect(await rig.incidents(), isEmpty);
    expect(await rig.outboxSize(), 0);
    expect(await rig.store.cursor('incidents'), 0);
  });
}
