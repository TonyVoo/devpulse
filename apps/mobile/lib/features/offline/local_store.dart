import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/design_system/widgets/status_widgets.dart';
import '../deployments/domain/deployment.dart';
import '../incidents/domain/incident.dart';
import '../services/domain/service.dart';

/// Typed access to the offline cache for one organization.
///
/// Write rules (what makes realtime + pagination + offline edits duplicate-free):
/// * rows are keyed by id, so the same entity arriving twice replaces itself;
/// * sync writes only win with a higher `change_seq`; command responses only with a higher
///   `version` — an older copy can never overwrite a newer one.
class LocalStore {
  LocalStore(this.db, this.orgId);

  final AppDatabase db;
  final String orgId;

  // ------------------------------------------------------------------ incidents

  static const _overlay = {
    'acknowledge': IncidentStatus.acknowledged,
    'resolve': IncidentStatus.resolved,
    'reopen': IncidentStatus.triggered,
  };

  Incident _incident(CachedIncident row) {
    final json = jsonDecode(row.json) as Map<String, dynamic>;
    final status = _overlay[row.pendingAction];
    if (status != null) json['status'] = status.name; // optimistic, until the server confirms
    return Incident.fromJson(json).withPending(row.pendingAction);
  }

  Future<void> upsertIncidentFromSync(Map<String, dynamic> json, int changeSeq) async {
    final existing = await (db.select(
      db.cachedIncidents,
    )..where((t) => t.id.equals(json['id'] as String))).getSingleOrNull();
    if (existing != null && existing.changeSeq >= changeSeq) return;
    await db.into(db.cachedIncidents).insertOnConflictUpdate(_incidentRow(json, changeSeq, existing?.pendingAction));
  }

  /// From a command response (no change_seq). Keeps the row's seq; wins only on newer version.
  Future<void> upsertIncidentFromCommand(Map<String, dynamic> json, {bool clearPending = true}) async {
    final existing = await (db.select(
      db.cachedIncidents,
    )..where((t) => t.id.equals(json['id'] as String))).getSingleOrNull();
    if (existing != null && existing.version > (json['version'] as int)) {
      if (clearPending) await setPending(existing.id, null);
      return;
    }
    await db
        .into(db.cachedIncidents)
        .insertOnConflictUpdate(
          _incidentRow(json, existing?.changeSeq ?? 0, clearPending ? null : existing?.pendingAction),
        );
  }

  CachedIncidentsCompanion _incidentRow(Map<String, dynamic> j, int changeSeq, String? pending) {
    final svc = j['service'] as Map<String, dynamic>?;
    final who = j['assignee'] as Map<String, dynamic>?;
    return CachedIncidentsCompanion.insert(
      id: j['id'] as String,
      orgId: orgId,
      key: j['key'] as String,
      status: j['status'] as String,
      severity: j['severity'] as String,
      startedAt: DateTime.parse(j['started_at'] as String).millisecondsSinceEpoch,
      serviceId: Value(svc?['id'] as String?),
      assigneeId: Value(who?['id'] as String?),
      json: jsonEncode(j),
      version: j['version'] as int,
      changeSeq: changeSeq,
      pendingAction: Value(pending),
    );
  }

  /// Caches an incident fetched outside the sync feed (older pages, deep links) without ever
  /// overwriting a synced copy. `changeSeq = 0` lets the next sync replace it.
  Future<void> cacheIfMissing(Incident incident) =>
      db.into(db.cachedIncidents).insert(_incidentRow(incident.toJson(), 0, null), mode: InsertMode.insertOrIgnore);

  Future<void> setPending(String incidentId, String? action) => (db.update(
    db.cachedIncidents,
  )..where((t) => t.id.equals(incidentId))).write(CachedIncidentsCompanion(pendingAction: Value(action)));

  Stream<List<Incident>> watchIncidents(IncidentFilter filter, {String? meId, String? serviceId}) {
    final q = db.select(db.cachedIncidents)..where((t) => t.orgId.equals(orgId));
    if (filter.severities.isNotEmpty) q.where((t) => t.severity.isIn([for (final s in filter.severities) s.name]));
    if (filter.mineOnly && meId != null) q.where((t) => t.assigneeId.equals(meId));
    if (serviceId != null) q.where((t) => t.serviceId.equals(serviceId));
    q.orderBy([(t) => OrderingTerm.desc(t.startedAt), (t) => OrderingTerm.desc(t.id)]);
    // Status filter is applied after the optimistic overlay so a pending "resolve" leaves
    // the "Open" list immediately.
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          if (filter.statuses.isEmpty || filter.statuses.contains(_incident(r).status)) _incident(r),
      ],
    );
  }

  Stream<Incident?> watchIncident(String ref) {
    final q = db.select(db.cachedIncidents)
      ..where((t) => t.orgId.equals(orgId) & (t.id.equals(ref) | t.key.lower().equals(ref.toLowerCase())));
    return q.watchSingleOrNull().map((r) => r == null ? null : _incident(r));
  }

  Future<Incident?> incident(String ref) => watchIncident(ref).first;

  // ------------------------------------------------------------------ services

  Future<void> upsertServiceFromSync(Map<String, dynamic> json, int changeSeq) async {
    final existing = await (db.select(
      db.cachedServices,
    )..where((t) => t.id.equals(json['id'] as String))).getSingleOrNull();
    if (existing != null && existing.changeSeq >= changeSeq) return;
    await db
        .into(db.cachedServices)
        .insertOnConflictUpdate(
          CachedServicesCompanion.insert(
            id: json['id'] as String,
            orgId: orgId,
            name: json['name'] as String,
            health: json['health'] as String,
            json: jsonEncode(json),
            changeSeq: changeSeq,
          ),
        );
  }

  Stream<List<MonitoredService>> watchServices({String text = '', Set<Health> health = const {}}) {
    final q = db.select(db.cachedServices)..where((t) => t.orgId.equals(orgId));
    if (health.isNotEmpty) q.where((t) => t.health.isIn([for (final h in health) h.name]));
    if (text.trim().isNotEmpty) q.where((t) => t.name.lower().contains(text.trim().toLowerCase()));
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch().map(
      (rows) => [for (final r in rows) MonitoredService.fromJson(jsonDecode(r.json) as Map<String, dynamic>)],
    );
  }

  // ------------------------------------------------------------------ deployments

  Future<void> upsertDeploymentFromSync(Map<String, dynamic> json, int changeSeq) async {
    final existing = await (db.select(
      db.cachedDeployments,
    )..where((t) => t.id.equals(json['id'] as String))).getSingleOrNull();
    if (existing != null && existing.changeSeq >= changeSeq) return;
    await db
        .into(db.cachedDeployments)
        .insertOnConflictUpdate(
          CachedDeploymentsCompanion.insert(
            id: json['id'] as String,
            orgId: orgId,
            serviceId: json['service_id'] as String,
            startedAt: DateTime.parse(json['started_at'] as String).millisecondsSinceEpoch,
            json: jsonEncode(json),
            changeSeq: changeSeq,
          ),
        );
  }

  Stream<List<Deployment>> watchDeployments({String? serviceId, int limit = 200}) {
    final q = db.select(db.cachedDeployments)..where((t) => t.orgId.equals(orgId));
    if (serviceId != null) q.where((t) => t.serviceId.equals(serviceId));
    q
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
      ..limit(limit);
    return q.watch().map(
      (rows) => [for (final r in rows) Deployment.fromJson(jsonDecode(r.json) as Map<String, dynamic>)],
    );
  }

  // ------------------------------------------------------------------ deletes + cursors

  Future<void> delete(String collection, String id) => switch (collection) {
    'services' => (db.delete(db.cachedServices)..where((t) => t.id.equals(id))).go(),
    'incidents' => (db.delete(db.cachedIncidents)..where((t) => t.id.equals(id))).go(),
    _ => (db.delete(db.cachedDeployments)..where((t) => t.id.equals(id))).go(),
  };

  Future<int> cursor(String collection) async {
    final row = await (db.select(
      db.syncCursors,
    )..where((t) => t.orgId.equals(orgId) & t.collection.equals(collection))).getSingleOrNull();
    return row?.cursor ?? 0;
  }

  Future<void> saveCursor(String collection, int cursor) => db
      .into(db.syncCursors)
      .insertOnConflictUpdate(SyncCursorsCompanion.insert(orgId: orgId, collection: collection, cursor: cursor));
}
