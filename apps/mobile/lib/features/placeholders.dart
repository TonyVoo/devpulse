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
