import 'package:devpulse_mobile/features/incidents/domain/incident.dart';
import 'package:devpulse_mobile/features/overview/domain/overview.dart';
import 'package:devpulse_mobile/features/shared_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers.dart';
import 'widgets_test.dart' show pumpApp;

Overview _busyOverview(List<Incident> incidents) => Overview.fromJson({
  'services_total': 4,
  'services_by_health': {'healthy': 3, 'degraded': 0, 'critical': 1, 'unknown': 0},
  'open_incidents_by_severity': {'sev1': 1, 'sev2': 1, 'sev3': 0, 'sev4': 0},
  'totals': {'requests': 125000, 'errors': 2500, 'error_rate': 0.02, 'latency_avg_ms': 180, 'latency_p95_ms': 1420},
  'request_series': [
    ['2026-11-11T10:00:00Z', 1000],
    ['2026-11-11T10:01:00Z', null],
    ['2026-11-11T10:02:00Z', 1200],
  ],
  'recent_incidents': <dynamic>[],
  'recent_deployments': <dynamic>[],
  'has_telemetry': true,
});

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('overview shows KPIs, health and a critical banner', (tester) async {
    final ops = FakeOpsRepository()..overviewValue = _busyOverview(const []);
    await pumpApp(tester, FakeAuthRepository(session: true, remote: me()), ops: ops);
    expect(find.text('2 critical incidents open'), findsOneWidget);
    expect(find.text('125.0k'), findsOneWidget);
    expect(find.text('2.0%'), findsOneWidget);
    expect(find.text('1.42 s'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Request volume chart')), findsOneWidget);
  });

  testWidgets('incident list → detail → acknowledge → back keeps the filter', (tester) async {
    final ops = FakeOpsRepository(
      incidents: [
        incidentFixture(id: 'a', number: 1001, title: 'Checkout latency'),
        incidentFixture(id: 'b', number: 1002, title: 'Search errors', status: IncidentStatus.resolved),
      ],
    );
    await pumpApp(tester, FakeAuthRepository(session: true, remote: me()), ops: ops);
    await _tapTab(tester, 'Incidents');

    expect(find.text('Checkout latency'), findsOneWidget);
    expect(find.text('Search errors'), findsNothing); // default filter: open

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mine')); // toggle back off
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Search errors'), findsOneWidget);

    await tester.tap(find.text('Checkout latency'));
    await tester.pumpAndSettle();
    expect(find.text('INC-1001'), findsWidgets);
    expect(find.text('Opened by alert “High latency”'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Acknowledge'));
    await tester.pumpAndSettle();
    expect(ops.actions, ['acknowledge']);
    expect(find.widgetWithText(FilledButton, 'Acknowledge'), findsNothing);
    expect(find.text('Acknowledged'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    // Back on the list: the "All" filter is still applied and the row shows the new status.
    expect(find.text('Search errors'), findsOneWidget);
    final row = find.ancestor(of: find.text('Checkout latency'), matching: find.byType(IncidentTile));
    expect(find.descendant(of: row, matching: find.text('Acknowledged')), findsOneWidget);
  });

  testWidgets('deep link opens an incident directly', (tester) async {
    final ops = FakeOpsRepository(
      incidents: [incidentFixture(id: 'a', number: 1042, title: 'Deep linked')],
    );
    await pumpApp(tester, FakeAuthRepository(session: true, remote: me()), ops: ops);
    GoRouter.of(tester.element(find.byType(NavigationBar))).go('/incidents/INC-1042');
    await tester.pumpAndSettle();
    expect(find.text('Deep linked'), findsOneWidget);
  });
}
