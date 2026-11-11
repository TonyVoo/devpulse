// Phase 3 exit criteria against a REAL DevPulse stack (`make up`, including the relay):
//  * a change made by someone else appears via realtime (WebSocket hint → delta sync),
//  * an acknowledge made offline is kept locally, then replayed exactly once when back online.
//
//   flutter test integration_test/offline_realtime_test.dart -d <simulator-id> \
//     --dart-define=API_BASE_URL=http://localhost:8000
import 'dart:async';

import 'package:devpulse_mobile/app/providers.dart';
import 'package:devpulse_mobile/core/network/api_client.dart';
import 'package:devpulse_mobile/features/auth/domain/models.dart';
import 'package:devpulse_mobile/features/auth/presentation/session_controller.dart';
import 'package:devpulse_mobile/features/offline/live_sync.dart';
import 'package:devpulse_mobile/main.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _password = 'devpulse-e2e-password'; // test-only credential for a throwaway account

/// Simulated airplane mode for the app's HTTP client.
class NetworkSwitch extends Interceptor {
  bool offline = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) => offline
      ? handler.reject(DioException.connectionError(requestOptions: options, reason: 'airplane mode (test)'))
      : handler.next(options);
}

Future<void> _waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $finder');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _waitUntil(WidgetTester tester, Future<bool> Function() check, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 25));
  while (!await check()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('realtime delivery + offline acknowledge replay on the real API', (tester) async {
    final network = NetworkSwitch();
    final connectivity = StreamController<bool>.broadcast();
    late ProviderContainer container;
    container = ProviderContainer(
      overrides: [
        connectivityProvider.overrideWithValue(connectivity.stream),
        dioProvider.overrideWith((ref) {
          final dio = createApiDio(
            config: ref.watch(appConfigProvider),
            store: ref.watch(tokenStoreProvider),
            onSessionExpired: () => container.read(sessionControllerProvider.notifier).onSessionExpired(),
          );
          dio.interceptors.insert(0, network);
          return dio;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(tokenStoreProvider).clear();
    await container.read(databaseProvider).clearUserData();

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DevPulseApp()));
    await _waitFor(tester, find.text('Work email'));

    // --- account + org through the UI
    final email = 'p3-${DateTime.now().millisecondsSinceEpoch}@example.com';
    await tester.tap(find.text('New to DevPulse? Create an account'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Phase Three');
    await tester.enterText(find.widgetWithText(TextField, 'Work email'), email);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), _password);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await _waitFor(tester, find.text('Create your first organization'));
    await tester.enterText(find.widgetWithText(TextField, 'Organization name'), 'Realtime Org');
    await tester.tap(find.widgetWithText(FilledButton, 'Create organization'));
    await _waitFor(tester, find.byType(NavigationBar));

    final session = container.read(sessionControllerProvider).value! as SignedIn;
    final orgId = session.currentOrgId!;
    final token = (await container.read(tokenStoreProvider).read())!.accessToken;
    final other = Dio(
      BaseOptions(
        baseUrl: '${container.read(appConfigProvider).apiV1}/orgs/$orgId/',
        headers: {'Authorization': 'Bearer $token'},
      ),
    );

    // Open the Incidents tab first, then create the incident "elsewhere".
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Incidents')));
    await _waitFor(tester, find.text('No open incidents — all clear'));
    await _waitUntil(
      tester,
      () async => container.read(liveSyncProvider)!.realtime.state.name == 'connected',
      'realtime connection',
    );
    final created = await other.post<Map<String, dynamic>>(
      'incidents',
      data: {'title': 'Created by another engineer', 'severity': 'sev2'},
    );
    final id = created.data!['id'] as String;

    // No refresh, no navigation: it must arrive via the WebSocket hint + delta sync.
    await _waitFor(tester, find.text('Created by another engineer'));

    // --- offline acknowledge
    await tester.tap(find.text('Created by another engineer'));
    await _waitFor(tester, find.widgetWithText(FilledButton, 'Acknowledge'));
    network.offline = true;
    connectivity.add(false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Acknowledge'));
    await _waitFor(tester, find.textContaining('waiting to be sent'));
    expect(find.textContaining('Offline'), findsWidgets);
    final whileOffline = await other.get<Map<String, dynamic>>('incidents/$id');
    expect(whileOffline.data!['status'], 'triggered'); // nothing reached the server

    // --- back online: the outbox replays on its own
    network.offline = false;
    connectivity.add(true);
    await _waitUntil(tester, () async {
      final r = await other.get<Map<String, dynamic>>('incidents/$id');
      return r.data!['status'] == 'acknowledged';
    }, 'server-side acknowledge');
    await _waitUntil(
      tester,
      () async => find.textContaining('waiting to be sent').evaluate().isEmpty,
      'pending banner to clear',
    );

    final timeline = await other.get<Map<String, dynamic>>('incidents/$id/timeline');
    final acks = (timeline.data!['items'] as List<dynamic>).where((e) => (e as Map)['type'] == 'acknowledged');
    expect(acks, hasLength(1)); // replayed exactly once

    await connectivity.close();
  });
}
