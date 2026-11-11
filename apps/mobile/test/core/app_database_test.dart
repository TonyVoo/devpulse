import 'package:devpulse_mobile/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('stores and overwrites JSON values', () async {
    await db.writeJson(KvKeys.me, {'id': 'u1'});
    await db.writeJson(KvKeys.me, {'id': 'u2'});
    expect(await db.readJson(KvKeys.me), {'id': 'u2'});
    expect(await db.readJson('missing'), isNull);
  });

  test('corrupt JSON reads as absent instead of crashing', () async {
    await db.writeString(KvKeys.me, '{not json');
    expect(await db.readJson(KvKeys.me), isNull);
  });

  test('sign-out wipes user data but keeps device preferences', () async {
    await db.writeJson(KvKeys.me, {'id': 'u1'});
    await db.writeString(KvKeys.currentOrg, 'org-a');
    await db.writeString(KvKeys.theme, 'dark');
    await db.clearUserData();
    expect(await db.readJson(KvKeys.me), isNull);
    expect(await db.readString(KvKeys.currentOrg), isNull);
    expect(await db.readString(KvKeys.theme), 'dark');
  });

  test('schema version is pinned (bump requires a migration + test)', () {
    expect(db.schemaVersion, 1);
  });
}
