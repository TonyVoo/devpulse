import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/widgets/dp_widgets.dart';
import 'auth/domain/models.dart';
import 'auth/presentation/session_controller.dart';

/// Tabs whose features land in later phases. They show honest empty states — never
/// fabricated metrics or demo data presented as real.
class _TabScaffold extends ConsumerWidget {
  const _TabScaffold({required this.title, required this.empty});

  final String title;
  final DpEmptyState empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final org = session is SignedIn ? session.currentOrg?.name : null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (org != null) Text(org, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sessionControllerProvider.notifier).refreshProfile(),
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: empty,
            ),
          ),
        ),
      ),
    );
  }
}

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => const _TabScaffold(
    title: 'Overview',
    empty: DpEmptyState(
      icon: Icons.space_dashboard_outlined,
      title: 'No services connected yet',
      description:
          'Service health, error rate, latency and recent incidents will appear here once services send telemetry.',
    ),
  );
}

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) => const _TabScaffold(
    title: 'Services',
    empty: DpEmptyState(
      icon: Icons.dns_outlined,
      title: 'No services yet',
      description: 'Add a service and an ingest key from the web dashboard, then its health shows up here.',
    ),
  );
}

class IncidentsScreen extends StatelessWidget {
  const IncidentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _TabScaffold(
    title: 'Incidents',
    empty: DpEmptyState(
      icon: Icons.verified_outlined,
      title: 'No incidents',
      description: 'Incidents opened by alert rules or by your team will be listed here, newest first.',
    ),
  );
}

class CopilotScreen extends StatelessWidget {
  const CopilotScreen({super.key});

  @override
  Widget build(BuildContext context) => const _TabScaffold(
    title: 'AI Copilot',
    empty: DpEmptyState(
      icon: Icons.auto_awesome_outlined,
      title: 'Nothing to investigate yet',
      description: 'When an incident opens, Copilot gathers metrics, logs and deployments and suggests probable causes with the evidence behind them.',
    ),
  );
}
