import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/auth/domain/models.dart';
import 'package:devpulse_mobile/features/copilot/domain/investigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers.dart';
import '../support/fake_server.dart';
import 'widgets_test.dart' show pumpApp;

Investigation _inv([String status = 'succeeded', String? code]) =>
    Investigation.fromJson(investigationJson(status: status, errorCode: code));

Future<void> _openIncident(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(NavigationBar))).go('/incidents/INC-1001');
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('AI ANALYSIS'), 300, scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
}

FakeServer _server() => FakeServer()..putIncident(incidentJson('a', number: 1001));

// Detail falls back to the ops repository when the incident isn't cached yet.
FakeOpsRepository _ops() => FakeOpsRepository(
  incidents: [incidentFixture(id: 'a', number: 1001, title: 'Checkout latency')],
);

void main() {
  test('parses the analysis contract and maps error codes to plain language', () {
    final inv = _inv();
    expect(inv.result!.causes.single.confidenceLabel, 'medium');
    expect(inv.evidenceFor('EV-2')!.text, contains('peak 1,400'));
    expect(inv.proposal('p-1')!.status, 'proposed');
    expect(inv.summary.isDemoProvider, isTrue);
    expect(RunStatus.parse('analyzing').isActive, isTrue);
    expect(aiErrorMessage('ai.disabled'), contains('turned off'));
    expect(aiErrorMessage('weird', detail: 'Server said no'), 'Server said no');
  });

  testWidgets('no analysis yet → explains and offers to investigate; errors are explained', (tester) async {
    final ai = FakeAiRepository(startError: const ConflictFailure('AI is disabled', code: 'ai.disabled'));
    await pumpApp(
      tester,
      FakeAuthRepository(session: true, remote: me()),
      server: _server(),
      ai: ai,
    );
    await _openIncident(tester);
    expect(find.textContaining('suggests probable causes'), findsOneWidget);
    await tester.tap(find.text('Investigate with AI'));
    await tester.pumpAndSettle();
    expect(find.textContaining('turned off for this organization'), findsOneWidget);
  });

  testWidgets('a finished analysis shows hypotheses, computed evidence, and approval', (tester) async {
    final ai = FakeAiRepository(
      runs: {
        'a': [_inv()],
      },
    );
    await pumpApp(
      tester,
      FakeAuthRepository(session: true, remote: me()),
      server: _server(),
      ai: ai,
    );
    await _openIncident(tester);

    expect(find.textContaining('Hypotheses — not confirmed'), findsOneWidget);
    expect(find.text('DEMO ANALYZER · NOT AN LLM'), findsOneWidget);
    expect(find.text('1. Regression introduced by deployment v2.14.0'), findsOneWidget);
    expect(find.text('MEDIUM · 65%'), findsOneWidget);
    expect(find.text('No traces'), findsNothing); // shown as a bullet
    expect(find.text('• No traces'), findsOneWidget);

    // Evidence chip → the excerpt DevPulse computed, not model text.
    await tester.ensureVisible(find.text('EV-2'));
    await tester.tap(find.text('EV-2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('peak 1,400'), findsOneWidget);
    expect(find.textContaining('not by the AI'), findsOneWidget);
    Navigator.of(tester.element(find.textContaining('peak 1,400'))).pop();
    await tester.pumpAndSettle();

    // Sensitive step: approval asks for confirmation and states nothing runs automatically.
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Approve'));
    await tester.tap(find.widgetWithText(TextButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DevPulse does not run it'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(ai.decisions, [('p-1', true)]);
    expect(find.textContaining('Approved (not executed by DevPulse)'), findsOneWidget);
  });

  testWidgets('viewers see the analysis but cannot approve', (tester) async {
    final ai = FakeAiRepository(
      runs: {
        'a': [_inv()],
      },
    );
    await pumpApp(
      tester,
      FakeAuthRepository(
        session: true,
        remote: me(
          orgs: const [OrgMembership(id: 'org-a', slug: 'acme', name: 'Acme', role: OrgRole.viewer)],
        ),
      ),
      server: _server(),
      ai: ai,
    );
    await _openIncident(tester);
    expect(find.text('1. Regression introduced by deployment v2.14.0'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Approve'), findsNothing);
  });

  testWidgets('progress and failure states', (tester) async {
    final ai = FakeAiRepository(
      runs: {
        'a': [_inv('analyzing')],
      },
    );
    await pumpApp(
      tester,
      FakeAuthRepository(session: true, remote: me()),
      server: _server(),
      ops: _ops(),
      ai: ai,
    );
    // A spinner animates forever while the run is active: pump fixed durations, never settle.
    GoRouter.of(tester.element(find.byType(NavigationBar))).go('/incidents/INC-1001');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.scrollUntilVisible(
      find.text('Analysing the evidence…'),
      300,
      scrollable: find.byType(Scrollable).last,
      duration: const Duration(milliseconds: 50),
    );
    expect(find.text('Analysing the evidence…'), findsOneWidget);

    ai.runs['a'] = [_inv('failed', 'ai.no_evidence')];
    await tester.pump(const Duration(seconds: 4)); // poll interval while active
    await tester.pumpAndSettle();
    expect(find.text('Analysis unavailable'), findsOneWidget);
    expect(find.textContaining('no telemetry for this incident'), findsOneWidget);
    expect(find.text('Incident actions are not affected.'), findsOneWidget);
  });

  testWidgets('follow-up chat sends a question and shows the cited answer', (tester) async {
    final ai = FakeAiRepository(
      runs: {
        'a': [_inv()],
      },
    );
    await pumpApp(
      tester,
      FakeAuthRepository(session: true, remote: me()),
      server: _server(),
      ai: ai,
    );
    await _openIncident(tester);
    await tester.scrollUntilVisible(find.text('Ask a follow-up'), 200, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200)); // clear the nav bar
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask a follow-up'));
    await tester.pumpAndSettle();
    expect(find.text('Ask Copilot'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'When did errors start?');
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    expect(ai.asked.single.$1, 'When did errors start?');
    expect(find.text('Errors began right after the deploy.'), findsOneWidget);
    expect(find.text('EV-1'), findsOneWidget);
  });

  testWidgets('a failed question keeps its client id so the retry is idempotent', (tester) async {
    final ai = FakeAiRepository(
      runs: {
        'a': [_inv()],
      },
      askError: const NetworkFailure('offline'),
    );
    await pumpApp(
      tester,
      FakeAuthRepository(session: true, remote: me()),
      server: _server(),
      ai: ai,
    );
    GoRouter.of(tester.element(find.byType(NavigationBar))).go('/incidents/INC-1001/ai/inv-1');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Why?');
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    ai.askError = null;
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    expect(ai.asked, hasLength(2));
    expect(ai.asked[0].$2, ai.asked[1].$2);
  });

  testWidgets('Copilot tab lists investigations, or explains how to start one', (tester) async {
    await pumpApp(
      tester,
      FakeAuthRepository(session: true, remote: me()),
      server: _server(),
      ops: _ops(),
    );
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Copilot')));
    await tester.pumpAndSettle();
    expect(find.text('No investigations yet'), findsOneWidget);
  });

  testWidgets('Copilot tab shows recent runs with the demo label', (tester) async {
    final ai = FakeAiRepository(
      runs: {
        'a': [_inv()],
      },
    );
    await pumpApp(
      tester,
      FakeAuthRepository(session: true, remote: me()),
      server: _server(),
      ai: ai,
    );
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Copilot')));
    await tester.pumpAndSettle();
    expect(find.text('INC-1001 · Checkout latency'), findsOneWidget);
    expect(find.text('Most likely (hypothesis): regression from v2.14.0.'), findsOneWidget);
    expect(find.text('DEMO ANALYZER · NOT AN LLM'), findsOneWidget);
  });
}
