import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config/app_config.dart';
import '../../core/network/retry_policy.dart';

enum RealtimeState { disconnected, connecting, connected }

typedef WsConnector = WebSocketChannel Function(Uri uri);

/// WebSocket client (ARCHITECTURE.md §8). Messages are hints only: on connect and on every
/// `sync` hint the owner runs a delta sync, so a missed or duplicated message is harmless.
///
/// * Auth: short-lived single-use ticket from `POST /realtime/ticket` (no JWT in URLs).
/// * Reconnect: exponential backoff with full jitter (1 s → 30 s), reset after 60 s stable.
/// * Lifecycle: the owner calls [start] in the foreground and [stop] in the background.
class RealtimeClient {
  RealtimeClient({
    required this._dio,
    required this._config,
    required this._orgId,
    required this.onConnected,
    required this.onHint,
    required this.onIncidentEvent,
    WsConnector? connector,
    Random? random,
    this._policy = const RetryPolicy(base: Duration(seconds: 1), cap: Duration(seconds: 30)),
    this._stableAfter = const Duration(seconds: 60),
  }) : _connect = connector ?? WebSocketChannel.connect,
       _random = random ?? Random();

  final Dio _dio;
  final AppConfig _config;
  final String _orgId;
  final WsConnector _connect;
  final Random _random;
  final void Function() onConnected;

  /// `changeSeq == null` means "sync this collection now".
  final void Function(String collection, int? changeSeq) onHint;
  final void Function(String incidentId) onIncidentEvent;

  final RetryPolicy _policy;
  final Duration _stableAfter;

  final _state = StreamController<RealtimeState>.broadcast();
  RealtimeState _current = RealtimeState.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _stable;
  int _attempt = 0;
  bool _wanted = false;

  Stream<RealtimeState> get states => _state.stream;
  RealtimeState get state => _current;

  void _set(RealtimeState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  void start() {
    if (_wanted) return;
    _wanted = true;
    _attempt = 0;
    unawaited(_open());
  }

  /// Reconnect immediately (connectivity regained), skipping any backoff wait.
  void nudge() {
    if (!_wanted || _current != RealtimeState.disconnected) return;
    _retry?.cancel();
    unawaited(_open());
  }

  Future<void> stop() async {
    _wanted = false;
    _retry?.cancel();
    _stable?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _set(RealtimeState.disconnected);
  }

  Future<void> _open() async {
    if (!_wanted || _current != RealtimeState.disconnected) return;
    _set(RealtimeState.connecting);
    try {
      final r = await _dio.post<Map<String, dynamic>>('realtime/ticket', data: {'org_id': _orgId});
      final ticket = r.data!['ticket'] as String;
      final base = Uri.parse(_config.apiBaseUrl);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
        queryParameters: {'ticket': ticket},
      );
      final channel = _connect(uri);
      await channel.ready;
      if (!_wanted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _sub = channel.stream.listen(_onMessage, onDone: _onDropped, onError: (_) => _onDropped(), cancelOnError: true);
    } on Object {
      _onDropped();
    }
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } on Object {
      return; // ignore malformed frames
    }
    switch (msg['type']) {
      case 'hello':
        _set(RealtimeState.connected);
        _stable?.cancel();
        _stable = Timer(_stableAfter, () => _attempt = 0);
        onConnected(); // always delta-sync on (re)connect: covers anything missed
      case 'sync':
        onHint(msg['collection'] as String, msg['change_seq'] as int);
      case 'incident_event':
        // Timeline changes (e.g. a comment) don't always touch the incident row.
        onIncidentEvent(msg['incident_id'] as String);
      default:
        break; // ping and future message types
    }
  }

  void _onDropped() {
    _stable?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    _channel = null;
    _set(RealtimeState.disconnected);
    if (!_wanted) return;
    final delay = _policy.delayFor(_attempt++, random: _random);
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(_open()));
  }

  Future<void> dispose() async {
    await stop();
    await _state.close();
  }
}
