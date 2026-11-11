import 'dart:async';

import '../../core/network/org_api.dart';
import 'local_store.dart';

const syncCollections = ['services', 'incidents', 'deployments'];

/// Pulls the server's change feed (API.md §6) into the local cache.
///
/// Each page and its cursor are written in ONE local transaction: a crash or a lost
/// connection mid-sync can never leave the cursor ahead of the data it covers.
/// Concurrent requests for the same collection share one run (single-flight).
class SyncEngine {
  SyncEngine(this._api, this._store);

  final OrgApi _api;
  final LocalStore _store;
  final Map<String, Future<void>> _inflight = {};
  final Set<String> _rerun = {};

  Future<void> syncAll() => Future.wait([for (final c in syncCollections) sync(c)]);

  /// Single-flight per collection. A request arriving while a sync is running marks the
  /// collection dirty, and the running sync loops once more — so a change announced
  /// mid-sync (after the page was read) is never missed.
  Future<void> sync(String collection) {
    final running = _inflight[collection];
    if (running != null) {
      _rerun.add(collection);
      return running;
    }
    // Block body on purpose: `() => _inflight.remove(c)` would return the removed future —
    // this very future — and whenComplete would wait on itself forever.
    return _inflight[collection] = _loop(collection).whenComplete(() {
      _inflight.remove(collection);
    });
  }

  Future<void> _loop(String collection) async {
    do {
      _rerun.remove(collection);
      await _run(collection);
    } while (_rerun.contains(collection));
  }

  /// Called for realtime hints: skip the round-trip when we already have that change.
  Future<void> onHint(String collection, int? changeSeq) async {
    if (!syncCollections.contains(collection)) return;
    if (changeSeq != null && changeSeq <= await _store.cursor(collection)) return;
    await sync(collection);
  }

  Future<void> _run(String collection) async {
    var cursor = await _store.cursor(collection);
    while (true) {
      final page = await _api.get('sync/$collection', query: {'cursor': cursor, 'limit': 500});
      final changes = page['changes'] as List<dynamic>;
      final next = page['next_cursor'] as int;
      await _store.db.transaction(() async {
        for (final raw in changes) {
          final c = raw as Map<String, dynamic>;
          final id = c['id'] as String;
          final seq = c['change_seq'] as int;
          if (c['op'] == 'delete') {
            await _store.delete(collection, id);
            continue;
          }
          final data = c['data'] as Map<String, dynamic>;
          switch (collection) {
            case 'services':
              await _store.upsertServiceFromSync(data, seq);
            case 'incidents':
              await _store.upsertIncidentFromSync(data, seq);
            default:
              await _store.upsertDeploymentFromSync(data, seq);
          }
        }
        await _store.saveCursor(collection, next);
      });
      cursor = next;
      if (page['has_more'] != true) return;
    }
  }
}
