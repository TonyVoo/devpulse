// Accessibility audit of the main screens (Phase 5): Flutter's guideline checks for tap
// target size (Android 48dp, iOS 44pt), labelled tap targets and text contrast, in light and
// dark themes, plus large text (2x) without layout overflow.
import 'package:devpulse_mobile/core/design_system/theme.dart';
import 'package:devpulse_mobile/features/copilot/domain/investigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers.dart';
import '../support/fake_server.dart';
import 'widgets_test.dart' show pumpApp;

const _phone = Size(390, 844);

FakeServer _server() => FakeServer()
  ..putIncident(incidentJson('a', number: 1001, title: 'Checkout latency'))
  ..putService(serviceJson('s1', 'checkout', health: 'degraded'));

FakeOpsRepository _ops() => FakeOpsRepository(
  incidents: [incidentFixture(id: 'a', number: 1001, title: 'Checkout latency')],
);

FakeAiRepository _ai() => FakeAiRepository(
  runs: {
    'a': [Investigation.fromJson(investigationJson())],
  },
);

Future<void> _go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(NavigationBar))).go(path);
  await tester.pumpAndSettle();
}

Future<void> _guidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

const _screens = [
  '/overview',
  '/incidents',
  '/incidents/INC-1001',
  '/services',
  '/copilot',
  '/settings',
  '/incidents/INC-1001/ai/inv-1',
];

void main() {
  for (final theme in ['dark', 'light']) {
    for (final path in _screens) {
      testWidgets('$path meets accessibility guidelines ($theme)', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(
          tester,
          FakeAuthRepository(session: true, remote: me()),
          size: _phone,
          server: _server(),
          ops: _ops(),
          ai: _ai(),
          theme: theme,
        );
        await _go(tester, path);
        await _guidelines(tester);
        handle.dispose();
      });
    }
  }

  for (final path in _screens) {
    testWidgets('$path lays out at 2x text size', (tester) async {
      // Print the full report (which widget overflowed) before the test binding records it.
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester,
        FakeAuthRepository(session: true, remote: me()),
        size: _phone,
        server: _server(),
        ops: _ops(),
        ai: _ai(),
      );
      await _go(tester, path);
      expect(tester.takeException(), isNull); // RenderFlex overflow etc. would surface here
    });
  }

  testWidgets('sign-in screen meets accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, FakeAuthRepository(), size: _phone);
    await _guidelines(tester);
    handle.dispose();
  });

  testWidgets('reduce motion: page transitions are skipped, otherwise the platform one runs', (tester) async {
    const page = SizedBox(key: Key('page'));
    late Widget reduced;
    late Widget normal;
    final route = MaterialPageRoute<void>(builder: (_) => page);
    const builder = ReduceMotionTransitionsBuilder(FadeForwardsPageTransitionsBuilder());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const half = AlwaysStoppedAnimation<double>(0.5);
            normal = builder.buildTransitions(route, context, half, half, page);
            reduced = MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Builder(builder: (inner) => builder.buildTransitions(route, inner, half, half, page)),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(identical(normal, page), isFalse); // wrapped in the platform transition
    await tester.pumpWidget(MaterialApp(home: reduced));
    expect(find.byKey(const Key('page')), findsOneWidget);
    final built = tester.widget<Builder>(find.byType(Builder).last);
    expect(identical(built.builder(tester.element(find.byType(Builder).last)), page), isTrue);
  });
}
