import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/network/org_api.dart';
import '../../auth/domain/models.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/ai_repository.dart';
import '../domain/investigation.dart';
import 'ai_widgets.dart';

/// Copilot tab: recent AI investigations across the organization.
class CopilotScreen extends ConsumerWidget {
  const CopilotScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final org = session is SignedIn ? session.currentOrg?.name : null;
    final value = ref.watch(recentInvestigationsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Copilot'),
            if (org != null) Text(org, style: t.bodySmall),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(recentInvestigationsProvider.future),
        child: AsyncView<Paged<InvestigationSummary>>(
          value: value,
          onRetry: () => ref.invalidate(recentInvestigationsProvider),
          data: (page) => page.items.isEmpty
              ? LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: const DpEmptyState(
                        icon: Icons.auto_awesome_outlined,
                        title: 'No investigations yet',
                        description:
                            'Open an incident and tap "Investigate with AI". Copilot gathers metrics, '
                            'logs and deployments and suggests probable causes with the evidence behind them.',
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: DpSpace.sm),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _Tile(page.items[i]),
                ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.s);

  final InvestigationSummary s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.dp;
    final subtitle = switch (s.status) {
      RunStatus.succeeded => s.summary ?? 'Analysis ready',
      RunStatus.failed || RunStatus.rejected => aiErrorMessage(s.errorCode),
      _ => s.status.progressLabel,
    };
    return ListTile(
      onTap: () => context.go('${Routes.incidents}/${s.incidentKey}'),
      leading: Icon(switch (s.status) {
        RunStatus.succeeded => Icons.auto_awesome,
        RunStatus.failed || RunStatus.rejected => Icons.error_outline,
        _ => Icons.hourglass_top,
      }, color: s.status == RunStatus.succeeded ? p.cyan : (s.status.isActive ? p.fgMuted : p.critical)),
      title: Row(
        children: [
          DpSeverityChip(s.incidentSeverity),
          const SizedBox(width: DpSpace.sm),
          Expanded(child: Text('${s.incidentKey} · ${s.incidentTitle}', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: DpSpace.xs),
          Wrap(
            spacing: DpSpace.sm,
            runSpacing: DpSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${s.trigger == 'auto' ? 'Automatic' : 'Requested'} · ${timeAgo(s.createdAt)}', style: t.bodySmall),
              if (s.isDemoProvider) const DemoAnalyzerTag(),
            ],
          ),
        ],
      ),
    );
  }
}
