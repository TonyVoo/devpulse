import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Small key/value cache (current profile, selected org, theme, last overview).
class KeyValueEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

// ---------------------------------------------------------------- schema v2: offline cache
// Entities are stored as the API's JSON plus the columns we filter/sort on. The local
// database is the single source of truth for list screens (ADR-005).

class CachedServices extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get name => text()();
  TextColumn get health => text()();
  TextColumn get json => text()();
  IntColumn get changeSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CachedIncidents extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get key => text()();
  TextColumn get status => text()();
  TextColumn get severity => text()();
  IntColumn get startedAt => integer()(); // epoch ms, for ordering
  TextColumn get serviceId => text().nullable()();
  TextColumn get assigneeId => text().nullable()();
  TextColumn get json => text()();
  IntColumn get version => integer()();
  IntColumn get changeSeq => integer()();

  /// Optimistic local action waiting in the outbox (`acknowledge`, `resolve`, …).
  TextColumn get pendingAction => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CachedDeployments extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get serviceId => text()();
  IntColumn get startedAt => integer()();
  TextColumn get json => text()();
  IntColumn get changeSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncCursors extends Table {
  TextColumn get orgId => text()();
  TextColumn get collection => text()();
  IntColumn get cursor => integer()();

  @override
  Set<Column<Object>> get primaryKey => {orgId, collection};
}

/// Commands made while offline (or not yet confirmed). Replayed in order with the same
/// Idempotency-Key, so a retry after a lost response can never apply twice.
class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orgId => text()();
  TextColumn get incidentId => text()();
  TextColumn get kind => text()(); // 'action' | 'comment'
  TextColumn get action => text()(); // acknowledge | resolve | … | comment
  TextColumn get path => text()();
  TextColumn get body => text()();
  TextColumn get idempotencyKey => text()();
  TextColumn get clientId => text().nullable()();
  IntColumn get baseVersion => integer().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(const Constant('pending'))(); // pending | failed
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer()();
}

@DriftDatabase(
  tables: [KeyValueEntries, CachedServices, CachedIncidents, CachedDeployments, SyncCursors, OutboxEntries],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'devpulse'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 → v2: add the offline cache. Existing key/value rows are kept.
        await m.createTable(cachedServices);
        await m.createTable(cachedIncidents);
        await m.createTable(cachedDeployments);
        await m.createTable(syncCursors);
        await m.createTable(outboxEntries);
      }
    },
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
  Future<void> clearUserData() => transaction(() async {
    await (delete(keyValueEntries)..where((t) => t.key.isNotIn(const [KvKeys.theme]))).go();
    await clearOrgCache();
  });

  /// Wipes every org-scoped cache (sign-out, or switching organizations).
  Future<void> clearOrgCache() => transaction(() async {
    await delete(cachedServices).go();
    await delete(cachedIncidents).go();
    await delete(cachedDeployments).go();
    await delete(syncCursors).go();
    await delete(outboxEntries).go();
  });
}

abstract final class KvKeys {
  static const me = 'me';
  static const currentOrg = 'current_org';
  static const theme = 'theme';
  static String overview(String orgId, String window) => 'overview:$orgId:$window';
  static String incidentExtras(String incidentId) => 'incident_extras:$incidentId';
}
