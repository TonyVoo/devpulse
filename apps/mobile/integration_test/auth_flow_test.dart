// End-to-end flow against a REAL DevPulse API (start it with `make up`).
//
//   flutter test integration_test -d <simulator-id> \
//     --dart-define=API_BASE_URL=http://localhost:8000
//
// Creates a throwaway account with a unique email on every run.
import 'package:devpulse_mobile/app/providers.dart';
import 'package:devpulse_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _password = 'devpulse-e2e-password'; // test-only credential for a throwaway account

Future<void> _settle(WidgetTester tester, {Duration timeout = const Duration(seconds: 15)}) async {
  // Network calls are real here, so pump until animations finish and requests complete.
  final end = DateTime.now().add(timeout);
  do {
    await tester.pump(const Duration(milliseconds: 100));
  } while (tester.binding.hasScheduledFrame && DateTime.now().isBefore(end));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, timeout);
}

Future<void> _waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $finder');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('register → create org → tabs → sign out → sign in', (tester) async {
    final email = 'mobile-e2e-${DateTime.now().millisecondsSinceEpoch}@example.com';
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(tokenStoreProvider).clear(); // start signed out on a reused simulator
    await container.read(databaseProvider).clearUserData();

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DevPulseApp()));
    await _waitFor(tester, find.text('Work email'));

    // Register.
    await tester.tap(find.text('New to DevPulse? Create an account'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mobile E2E');
    await tester.enterText(find.widgetWithText(TextField, 'Work email'), email);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), _password);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));

    // New account has no org → picker → create one.
    await _waitFor(tester, find.text('Create your first organization'));
    await tester.enterText(find.widgetWithText(TextField, 'Organization name'), 'Mobile E2E Org');
    await tester.tap(find.widgetWithText(FilledButton, 'Create organization'));

    // Shell with five tabs and the honest empty state.
    await _waitFor(tester, find.byType(NavigationBar));
    expect(find.text('No services connected yet'), findsOneWidget);
    expect(find.text('Mobile E2E Org'), findsWidgets);

    for (final tab in ['Services', 'Incidents', 'Copilot']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await _settle(tester);
    }
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await _settle(tester);
    expect(find.text(email), findsOneWidget);
    expect(find.text('Your role: Owner'), findsOneWidget);

    // Sign out (with confirmation).
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await _waitFor(tester, find.text('Work email'));
    expect(await container.read(tokenStoreProvider).read(), isNull);

    // Sign back in: the single org is selected automatically.
    await tester.enterText(find.widgetWithText(TextField, 'Work email'), email);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), _password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await _waitFor(tester, find.byType(NavigationBar));
    expect(find.text('Mobile E2E Org'), findsWidgets);
    expect(await container.read(tokenStoreProvider).read(), isNotNull);
  });
}
