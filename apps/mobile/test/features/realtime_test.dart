import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:devpulse_mobile/core/config/app_config.dart';
import 'package:devpulse_mobile/core/network/retry_policy.dart';
import 'package:devpulse_mobile/features/offline/realtime_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../helpers.dart';

/// Minimal in-memory WebSocket: the test pushes server frames into [incoming].
class FakeWs with StreamChannelMixin<dynamic> implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  bool closedByClient = false;

  void send(Map<String, dynamic> frame) => incoming.add(jsonEncode(frame));
  Future<void> drop() => incoming.close();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  late final WebSocketSink sink = _FakeSink(this);

  @override
  Future<void> get ready => Future.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.ws);
  final FakeWs ws;

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    ws.closedByClient = true;
    if (!ws.incoming.isClosed) await ws.incoming.close();
  }

  @override
  Future<void> get done => Future.value();
}

class _Harness {
  _Harness({bool ticketFails = false}) {
    adapter = FakeAdapter(
      (o) => ticketFails
          ? problemBody(503, 'unavailable')
          : jsonBody({'ticket': 'tkt-${adapter.requests.length}', 'expires_in': 30}),
    );
    client = RealtimeClient(
      dio: Dio(BaseOptions(baseUrl: 'http://api.test/api/v1/'))..httpClientAdapter = adapter,
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      orgId: 'org-a',
      random: Random(1),
      // Same algorithm, milliseconds instead of seconds, so tests run in real time.
      policy: const RetryPolicy(base: Duration(milliseconds: 20), cap: Duration(milliseconds: 200)),
      connector: (uri) {
        uris.add(uri);
        final ws = FakeWs();
        sockets.add(ws);
        return ws;
      },
      onConnected: () => connected++,
      onHint: (c, seq) => hints.add('$c:$seq'),
      onIncidentEvent: events.add,
    );
  }

  late final FakeAdapter adapter;
  late final RealtimeClient client;
  final uris = <Uri>[];
  final sockets = <FakeWs>[];
  int connected = 0;
  final hints = <String>[];
  final events = <String>[];
}

Future<void> _settle([int ms = 10]) => Future<void>.delayed(Duration(milliseconds: ms));

/// Polls until [condition] holds (real async I/O inside Dio; no fixed sleeps).
Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await _settle(5);
  }
}

void main() {
  test('connects with a ticket, resyncs on hello, forwards hints', () async {
    final h = _Harness();
    h.client.start();
    await _until(() => h.uris.isNotEmpty);
    expect(h.uris.single.toString(), 'ws://api.test/ws?ticket=tkt-1'); // ticket, never the JWT
    expect(h.client.state, RealtimeState.connecting);

    h.sockets.single.send({'type': 'hello', 'org_id': 'org-a'});
    await _settle();
    expect(h.client.state, RealtimeState.connected);
    expect(h.connected, 1);

    h.sockets.single
      ..send({'type': 'sync', 'collection': 'incidents', 'change_seq': 7})
      ..send({'type': 'incident_event', 'incident_id': 'inc-1', 'event': 'comment_added'})
      ..send({'type': 'ping'})
      ..incoming.add('not json');
    await _settle();
    expect(h.hints, ['incidents:7']);
    expect(h.events, ['inc-1']);

    await h.client.dispose();
  });

  test('a dropped socket reconnects with backoff and resyncs', () async {
    final h = _Harness();
    h.client.start();
    await _until(() => h.sockets.isNotEmpty);
    h.sockets.single.send({'type': 'hello'});
    await _settle();

    await h.sockets.single.drop();
    await _settle();
    expect(h.client.state, RealtimeState.disconnected);
    expect(h.sockets, hasLength(1)); // not immediately

    await _until(() => h.sockets.length == 2); // first backoff ≤ 20 ms
    h.sockets.last.send({'type': 'hello'});
    await _settle();
    expect(h.connected, 2); // reconnect → full delta sync again, nothing missed

    await h.client.dispose();
  });

  test('stop() closes the socket and never reconnects', () async {
    final h = _Harness();
    h.client.start();
    await _until(() => h.sockets.isNotEmpty);
    h.sockets.single.send({'type': 'hello'});
    await _settle();

    await h.client.stop();
    expect(h.sockets.single.closedByClient, isTrue);
    await _settle(500);
    expect(h.sockets, hasLength(1));
    await h.client.dispose();
  });

  test('ticket failures back off exponentially (capped)', () async {
    final h = _Harness(ticketFails: true);
    h.client.start();
    await _until(() => h.adapter.requests.isNotEmpty);
    expect(h.adapter.requests, hasLength(1));
    await _settle(1000);
    final afterMinute = h.adapter.requests.length;
    expect(afterMinute, greaterThan(2)); // it keeps trying…
    expect(afterMinute, lessThan(20)); // …but backs off (capped at 200 ms here), never a tight loop
    expect(h.sockets, isEmpty);
    await h.client.dispose();
  });
}
