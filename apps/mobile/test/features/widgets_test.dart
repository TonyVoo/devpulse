import 'package:devpulse_mobile/app/providers.dart';
import 'package:devpulse_mobile/core/database/app_database.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/ops_repositories.dart';
import 'package:devpulse_mobile/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<FakeAuthRepository> pumpApp(
  WidgetTester tester,
  FakeAuthRepository repo, {
  Size? size,
  FakeOpsRepository? ops,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        databaseProvider.overrideWithValue(db),
        opsRepositoryProvider.overrideWithValue(ops ?? FakeOpsRepository()),
      ],
      child: const DevPulseApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('signed out users land on sign-in', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Work email'), findsOneWidget);
  });

  testWidgets('login error is shown and the user stays on the form', (tester) async {
    final repo = FakeAuthRepository()..loginError = const UnauthorizedFailure('Email or password is incorrect');
    await pumpApp(tester, repo);
    await tester.enterText(find.widgetWithText(TextField, 'Work email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect'), findsOneWidget);
    expect(find.text('Work email'), findsOneWidget);
  });

  testWidgets('register shows field-level validation errors', (tester) async {
    final repo = FakeAuthRepository()
      ..loginError = const ValidationFailure(
        'invalid',
        fields: {'password': 'String should have at least 12 characters'},
      );
    await pumpApp(tester, repo);
    await tester.tap(find.text('New to DevPulse? Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ada');
    await tester.enterText(find.widgetWithText(TextField, 'Work email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(find.text('Check the highlighted fields.'), findsOneWidget);
  });

  testWidgets('successful login with one org opens the 5-tab shell', (tester) async {
    await pumpApp(tester, FakeAuthRepository(remote: me()));
    await tester.enterText(find.widgetWithText(TextField, 'Work email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct-horse-battery');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Overview', 'Services', 'Incidents', 'Copilot', 'Settings']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsOneWidget);
    }
    expect(find.text('No services connected yet'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('Your role: Owner'), findsOneWidget);
  });

  testWidgets('multiple orgs → picker first', (tester) async {
    await pumpApp(tester, FakeAuthRepository(session: true, remote: me(orgs: [orgA, orgB])));
    expect(find.text('Your organizations'), findsOneWidget);
    await tester.tap(find.text('Bravo'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Bravo'), findsWidgets); // org name in the app bar
  });

  testWidgets('offline restore shows the stale-data banner', (tester) async {
    await pumpApp(tester, FakeAuthRepository(session: true, cached: me(), fetchError: const NetworkFailure()));
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('tablets get a navigation rail', (tester) async {
    await pumpApp(tester, FakeAuthRepository(session: true, remote: me()), size: const Size(1100, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('sign out asks for confirmation', (tester) async {
    final repo = await pumpApp(tester, FakeAuthRepository(session: true, remote: me()));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(repo.logoutCalls, 1);
    expect(find.text('Work email'), findsOneWidget);
  });
}
