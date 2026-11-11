import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/database/app_database.dart';
import '../../core/network/org_api.dart';
import '../auth/domain/models.dart';
import '../auth/presentation/session_controller.dart';
import '../ops_repositories.dart';
import 'local_store.dart';
import 'outbox.dart';
import 'realtime_client.dart';
import 'sync_engine.dart';

/// Owns offline sync for the selected organization: delta sync, the command outbox, the
/// realtime connection, connectivity and app lifecycle (MOBILE_ARCHITECTURE.md §3, §7).
class LiveSync {
  LiveSync({
    required AppDatabase db,
    required OrgApi api,
    required Dio dio,
    required AppConfig config,
    required this.orgId,
    required Stream<bool> connectivity,
    WsConnector? wsConnector,
  }) : store = LocalStore(db, orgId) {
    engine = SyncEngine(api, store);
    outbox = OutboxProcessor(api, store);
    realtime = RealtimeClient(
      dio: dio,
      config: config,
      orgId: orgId,
      connector: wsConnector,
      onConnected: () {
        unawaited(_safely(engine.syncAll));
        unawaited(outbox.flush(ignoreBackoff: true));
      },
      onHint: (c, seq) => unawaited(_safely(() => engine.onHint(c, seq))),
      onIncidentEvent: (id) {
        _incidentEvents.add(id);
        unawaited(_safely(() => engine.sync('incidents')));
      },
    );
    _connectivity = connectivity.listen(_onConnectivity);
  }

  final String orgId;
  final LocalStore store;
  late final SyncEngine engine;
  late final OutboxProcessor outbox;
  late final RealtimeClient realtime;

  late final StreamSubscription<bool> _connectivity;
  final _online = StreamController<bool>.broadcast();
  final _incidentEvents = StreamController<String>.broadcast();
  final _syncErrors = StreamController<Object>.broadcast();
  Timer? _backgroundGrace;
  Timer? _outboxTick;
  bool _isOnline = true;
  bool _started = false;

  static const backgroundGrace = Duration(seconds: 30);

  bool get isOnline => _isOnline;
  Stream<bool> get online => _online.stream;

  /// Incident ids whose timeline changed on the server (for open detail screens).
  Stream<String> get incidentEvents => _incidentEvents.stream;
  Stream<Object> get syncErrors => _syncErrors.stream;

  Future<void> _safely(Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (e) {
      if (!_syncErrors.isClosed) _syncErrors.add(e); // offline etc.; cached data stays visible
    }
  }

  void start() {
    if (_started) return;
    _started = true;
    realtime.start();
    unawaited(_safely(engine.syncAll));
    unawaited(outbox.flush());
    // Backoff timers live in the database (nextAttemptAt); this tick makes them fire.
    _outboxTick = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(outbox.flush()));
  }

  /// Pull-to-refresh / explicit refresh.
  Future<void> refresh() async {
    await outbox.flush(ignoreBackoff: true);
    await engine.syncAll();
  }

  /// App went to background: keep the socket for a short grace period (quick app switches),
  /// then close it. Push notifications cover the background (Phase 3 push design).
  void onBackground() {
    _backgroundGrace?.cancel();
    _backgroundGrace = Timer(backgroundGrace, () => unawaited(realtime.stop()));
  }

  void onForeground() {
    _backgroundGrace?.cancel();
    realtime.start(); // no-op if still connected; reconnect → hello → delta sync
    unawaited(_safely(engine.syncAll));
    unawaited(outbox.flush(ignoreBackoff: true));
  }

  void _onConnectivity(bool online) {
    if (online == _isOnline) return;
    _isOnline = online;
    if (!_online.isClosed) _online.add(online);
    if (online) {
      realtime.nudge();
      unawaited(outbox.flush(ignoreBackoff: true));
      unawaited(_safely(engine.syncAll));
    }
  }

  Future<void> dispose() async {
    // Cancel every timer synchronously before the first await: a disposed org must not
    // reconnect or retry in the background (and tests verify no timer outlives a screen).
    _backgroundGrace?.cancel();
    _outboxTick?.cancel();
    final realtimeClosed = realtime.dispose();
    await _connectivity.cancel();
    await realtimeClosed;
    await outbox.dispose();
    await _online.close();
    await _incidentEvents.close();
    await _syncErrors.close();
  }
}

/// OS connectivity as "probably online" booleans. A false positive (captive portal) is
/// harmless: requests fail and the outbox backs off.
final connectivityProvider = Provider<Stream<bool>>(
  (ref) => Connectivity().onConnectivityChanged.map((r) => r.any((c) => c != ConnectivityResult.none)),
);

/// Rebuilt when the organization changes (old instance disposed: socket closed, timers off).
final liveSyncProvider = Provider<LiveSync?>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  final orgId = session is SignedIn ? session.currentOrgId : null;
  if (orgId == null) return null;
  final live = LiveSync(
    db: ref.watch(databaseProvider),
    api: ref.watch(orgApiProvider),
    dio: ref.watch(dioProvider),
    config: ref.watch(appConfigProvider),
    orgId: orgId,
    connectivity: ref.watch(connectivityProvider),
  );
  ref.onDispose(live.dispose);
  return live;
});

final pendingChangesProvider = StreamProvider<int>((ref) {
  final live = ref.watch(liveSyncProvider);
  return live == null ? Stream.value(0) : live.outbox.watchPendingCount();
});

final onlineProvider = StreamProvider<bool>((ref) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(true);
  return Stream<bool>.multi((c) {
    c.add(live.isOnline);
    final sub = live.online.listen(c.add);
    c.onCancel = sub.cancel;
  });
});

final realtimeStateProvider = StreamProvider<RealtimeState>((ref) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(RealtimeState.disconnected);
  return Stream<RealtimeState>.multi((c) {
    c.add(live.realtime.state);
    final sub = live.realtime.states.listen(c.add);
    c.onCancel = sub.cancel;
  });
});
