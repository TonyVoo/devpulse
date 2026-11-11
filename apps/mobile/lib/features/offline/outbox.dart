import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/network/org_api.dart';
import '../../core/network/retry_policy.dart';
import '../../core/result/failure.dart';
import '../incidents/domain/incident.dart';
import 'local_store.dart';

/// What the UI should tell the user about a queued change.
sealed class OutboxNotice {
  const OutboxNotice(this.incidentId);
  final String incidentId;
}

/// The server rejected the action because the incident changed meanwhile. The local copy
/// has been refreshed; nothing was applied.
class OutboxConflict extends OutboxNotice {
  const OutboxConflict(super.incidentId, this.message);
  final String message;
}

/// Permanently failed (e.g. permission removed). Kept as `failed` until retried/discarded.
class OutboxFailed extends OutboxNotice {
  const OutboxFailed(super.incidentId, this.message);
  final String message;
}

class PendingComment {
  const PendingComment({required this.clientId, required this.body, required this.createdAt, required this.failed});
  final String clientId;
  final String body;
  final DateTime createdAt;
  final bool failed;
}

/// Offline-capable command queue (MOBILE_ARCHITECTURE.md §3).
///
/// * Actions are applied optimistically to the cache (`pendingAction`) and queued with an
///   Idempotency-Key and the version the user saw (`If-Match`).
/// * `flush()` replays strictly in order. Transient failures (offline, 5xx, 429) back off
///   with full jitter and stop the run — later commands never overtake earlier ones.
/// * A 409 means the incident changed underneath us: the command is dropped, the incident
///   re-fetched, and the user told — conflicts are resolved by people, not silently merged.
class OutboxProcessor {
  OutboxProcessor(this._api, this._store, {DateTime Function()? clock, RetryPolicy? policy})
    : _clock = clock ?? DateTime.now,
      _policy =
          policy ?? const RetryPolicy(maxAttempts: 1 << 30, base: Duration(seconds: 2), cap: Duration(minutes: 2));

  final OrgApi _api;
  final LocalStore _store;
  final DateTime Function() _clock;
  final RetryPolicy _policy;
  final _notices = StreamController<OutboxNotice>.broadcast();
  Future<void>? _running;

  AppDatabase get _db => _store.db;
  Stream<OutboxNotice> get notices => _notices.stream;

  Stream<int> watchPendingCount() {
    final count = _db.outboxEntries.id.count();
    final q = _db.selectOnly(_db.outboxEntries)
      ..addColumns([count])
      ..where(_db.outboxEntries.orgId.equals(_store.orgId) & _db.outboxEntries.state.equals('pending'));
    return q.map((r) => r.read(count) ?? 0).watchSingle();
  }

  Stream<List<PendingComment>> watchPendingComments(String incidentId) {
    final q = _db.select(_db.outboxEntries)
      ..where((t) => t.incidentId.equals(incidentId) & t.kind.equals('comment'))
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          PendingComment(
            clientId: r.clientId!,
            body: (jsonDecode(r.body) as Map<String, dynamic>)['body'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            failed: r.state == 'failed',
          ),
      ],
    );
  }

  Future<void> enqueueAction(Incident incident, String action, Map<String, dynamic> body) async {
    await _db.transaction(() async {
      await _db
          .into(_db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              orgId: _store.orgId,
              incidentId: incident.id,
              kind: 'action',
              action: action,
              path: 'incidents/${incident.id}/$action',
              body: jsonEncode(body),
              idempotencyKey: OrgApi.newClientId(),
              baseVersion: Value(incident.version),
              createdAt: _clock().millisecondsSinceEpoch,
            ),
          );
      await _store.setPending(incident.id, action);
    });
    unawaited(flush());
  }

  Future<String> enqueueComment(String incidentId, String body) async {
    final clientId = OrgApi.newClientId();
    await _db
        .into(_db.outboxEntries)
        .insert(
          OutboxEntriesCompanion.insert(
            orgId: _store.orgId,
            incidentId: incidentId,
            kind: 'comment',
            action: 'comment',
            path: 'incidents/$incidentId/comments',
            body: jsonEncode({'body': body, 'client_id': clientId}),
            idempotencyKey: clientId,
            clientId: Value(clientId),
            createdAt: _clock().millisecondsSinceEpoch,
          ),
        );
    unawaited(flush());
    return clientId;
  }

  /// Retry a failed entry now / discard it (UI actions on a failed item).
  Future<void> retry(int id) async {
    await (_db.update(_db.outboxEntries)..where((t) => t.id.equals(id))).write(
      const OutboxEntriesCompanion(state: Value('pending'), nextAttemptAt: Value(0)),
    );
    unawaited(flush());
  }

  Future<void> discard(int id) => (_db.delete(_db.outboxEntries)..where((t) => t.id.equals(id))).go();

  /// Replays due entries in order. Safe to call often; concurrent calls share one run.
  Future<void> flush({bool ignoreBackoff = false}) => _running ??= _flush(ignoreBackoff).whenComplete(() {
    _running = null;
  });

  Future<void> _flush(bool ignoreBackoff) async {
    while (true) {
      final next =
          await (_db.select(_db.outboxEntries)
                ..where((t) => t.orgId.equals(_store.orgId) & t.state.equals('pending'))
                ..orderBy([(t) => OrderingTerm.asc(t.id)])
                ..limit(1))
              .getSingleOrNull();
      if (next == null) return;
      if (!ignoreBackoff && next.nextAttemptAt > _clock().millisecondsSinceEpoch) return;
      if (!await _send(next)) return; // transient failure: keep order, try later
    }
  }

  /// Returns false when the queue should pause (transient failure).
  Future<bool> _send(OutboxEntry e) async {
    try {
      final result = await _api.command(
        e.path,
        body: jsonDecode(e.body),
        ifMatchVersion: e.baseVersion,
        idempotencyKey: e.idempotencyKey,
      );
      await _db.transaction(() async {
        if (e.kind == 'action') await _store.upsertIncidentFromCommand(result);
        await (_db.delete(_db.outboxEntries)..where((t) => t.id.equals(e.id))).go();
      });
      return true;
    } on ConflictFailure catch (f) {
      await _dropAndRefresh(e);
      _notices.add(
        OutboxConflict(
          e.incidentId,
          f.code == 'conflict.version_mismatch'
              ? 'Your "${e.action}" was not applied: someone else changed this incident first. Showing the latest.'
              : '${f.message}. Showing the latest.',
        ),
      );
      return true;
    } on Failure catch (f) {
      if (f is NetworkFailure || f is RateLimitedFailure || (f is ServerFailure && f.status >= 500)) {
        final attempts = e.attempts + 1;
        await (_db.update(_db.outboxEntries)..where((t) => t.id.equals(e.id))).write(
          OutboxEntriesCompanion(
            attempts: Value(attempts),
            nextAttemptAt: Value(_clock().add(_policy.delayFor(attempts)).millisecondsSinceEpoch),
            lastError: Value(f.message),
          ),
        );
        return false;
      }
      await _db.transaction(() async {
        await (_db.update(_db.outboxEntries)..where((t) => t.id.equals(e.id))).write(
          OutboxEntriesCompanion(state: const Value('failed'), lastError: Value(f.message)),
        );
        if (e.kind == 'action') await _store.setPending(e.incidentId, null);
      });
      _notices.add(OutboxFailed(e.incidentId, f.message));
      return true;
    }
  }

  Future<void> _dropAndRefresh(OutboxEntry e) async {
    await (_db.delete(_db.outboxEntries)..where((t) => t.id.equals(e.id))).go();
    try {
      final fresh = await _api.get('incidents/${e.incidentId}');
      await _store.upsertIncidentFromCommand(fresh);
    } on Failure {
      await _store.setPending(e.incidentId, null);
    }
  }

  Future<void> dispose() => _notices.close();
}
