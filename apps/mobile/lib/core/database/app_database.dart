import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Small key/value cache (current profile, selected org, theme). Org-scoped entity tables
/// (services, incidents, deployments, outbox, sync cursors) arrive in Phase 3 as schema v2+.
class KeyValueEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [KeyValueEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'devpulse'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Future versions add `onUpgrade` steps; every step gets a migration test.
  );

  Future<Map<String, dynamic>?> readJson(String key) async {
    final row = await (select(keyValueEntries)..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    try {
      return jsonDecode(row.value) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  Future<String?> readString(String key) async {
    final row = await (select(keyValueEntries)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeString(String key, String value) => into(
    keyValueEntries,
  ).insertOnConflictUpdate(KeyValueEntriesCompanion.insert(key: key, value: value, updatedAt: Value(DateTime.now())));

  Future<void> writeJson(String key, Map<String, dynamic> value) => writeString(key, jsonEncode(value));

  Future<void> deleteKey(String key) => (delete(keyValueEntries)..where((t) => t.key.equals(key))).go();

  /// Wipes user data on sign-out. Device preferences (theme) survive.
  Future<void> clearUserData() => (delete(keyValueEntries)..where((t) => t.key.isNotIn(const [KvKeys.theme]))).go();
}

abstract final class KvKeys {
  static const me = 'me';
  static const currentOrg = 'current_org';
  static const theme = 'theme';
}
