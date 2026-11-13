import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../l10n/l10n.dart';
import '../../auth/domain/models.dart';
import '../../auth/presentation/session_controller.dart';
import '../../ops_repositories.dart';
import '../../shared_tiles.dart';
import '../domain/overview.dart';

class OverviewWindowController extends Notifier<OverviewWindow> {
  @override
  OverviewWindow build() => OverviewWindow.hour;

  void set(OverviewWindow w) => state = w;
}

final overviewWindowProvider = NotifierProvider<OverviewWindowController, OverviewWindow>(OverviewWindowController.new);

final overviewProvider = FutureProvider<Overview>(
  (ref) => ref.watch(opsRepositoryProvider).overview(ref.watch(overviewWindowProvider)),
  retry: (_, _) => null,
);

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final orgName = session is SignedIn ? session.currentOrg?.name : null;
    final value = ref.watch(overviewProvider);
    final window = ref.watch(overviewWindowProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.navOverview),
            if (orgName != null) Text(orgName, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DpSpace.md),
            child: SegmentedButton<OverviewWindow>(
              showSelectedIcon: false,
              segments: [for (final w in OverviewWindow.values) ButtonSegment(value: w, label: Text(w.label))],
              selected: {window},
              onSelectionChanged: (s) => ref.read(overviewWindowProvider.notifier).set(s.first),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(overviewProvider.future),
        child: AsyncView(value: value, onRetry: () => ref.invalidate(overviewProvider), data: _OverviewBody.new),
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody(this.o);

  final Overview o;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final l = context.l10n;
    if (o.servicesTotal == 0 && o.recentIncidents.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          DpEmptyState(icon: Icons.space_dashboard_outlined, title: l.noServicesTitle, description: l.noServicesBody),
        ],
      );
    }
    final critical = o.openBySeverity[Severity.sev1]! + o.openBySeverity[Severity.sev2]!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DpSpace.lg),
      children: [
        if (critical > 0) ...[
          DpBanner(
            message: l.criticalOpen(critical),
            tone: DpBannerTone.error,
            action: TextButton(onPressed: () => context.go('/incidents'), child: Text(l.view)),
          ),
          const SizedBox(height: DpSpace.md),
        ],
        if (o.isStale) ...[
          DpBanner(message: l.overviewStale, tone: DpBannerTone.warning),
          const SizedBox(height: DpSpace.md),
        ],
        _HealthStrip(o),
        const SizedBox(height: DpSpace.md),
        if (!o.hasTelemetry)
          Padding(
            padding: const EdgeInsets.only(bottom: DpSpace.sm, left: DpSpace.xs),
            child: Text(l.noTelemetryWindow, style: Theme.of(context).textTheme.bodySmall),
          ),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: DpSpace.sm,
          crossAxisSpacing: DpSpace.sm,
          childAspectRatio: 1.9,
          children: [
            DpMetricTile(label: l.requests, value: o.requests == null ? '—' : compactNumber(o.requests!)),
            DpMetricTile(
              label: l.errorRate,
              value: percent(o.errorRate),
              tone: (o.errorRate ?? 0) >= 0.05 ? p.critical : null,
            ),
            DpMetricTile(label: l.avgLatency, value: millis(o.latencyAvgMs)),
            DpMetricTile(label: l.p95Latency, value: millis(o.latencyP95Ms), caption: l.approx),
          ],
        ),
        if (o.hasTelemetry) ...[
          SectionHeader(l.requestVolume),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DpSpace.sm, DpSpace.md, DpSpace.md, DpSpace.sm),
              child: DpLineChart(
                points: o.requestSeries,
                semanticLabel: l.requestVolumeSemantics(compactNumber(o.requests ?? 0)),
              ),
            ),
          ),
        ],
        SectionHeader(
          l.recentIncidents,
          action: TextButton(onPressed: () => context.go('/incidents'), child: Text(l.all)),
        ),
        if (o.recentIncidents.isEmpty)
          Card(
            child: ListTile(title: Text(l.noIncidents), subtitle: Text(l.allQuiet)),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, inc) in o.recentIncidents.indexed) ...[
                  if (i > 0) const Divider(),
                  IncidentTile(inc, onTap: () => context.go('/incidents/${inc.key}')),
                ],
              ],
            ),
          ),
        SectionHeader(
          l.recentDeployments,
          action: TextButton(onPressed: () => context.push('/overview/deployments'), child: Text(l.all)),
        ),
        if (o.recentDeployments.isEmpty)
          Card(
            child: ListTile(title: Text(l.noDeploymentsYet), subtitle: Text(l.sendFromCi)),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, d) in o.recentDeployments.indexed) ...[if (i > 0) const Divider(), DeploymentTile(d)],
              ],
            ),
          ),
      ],
    );
  }
}

class _HealthStrip extends StatelessWidget {
  const _HealthStrip(this.o);

  final Overview o;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(DpRadius.lg),
        onTap: () => context.go('/services'),
        child: Padding(
          padding: const EdgeInsets.all(DpSpace.lg),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${o.servicesTotal}', style: t.headlineSmall),
                  Text(context.l10n.servicesCount(o.servicesTotal), style: t.bodySmall),
                ],
              ),
              const Spacer(),
              for (final h in [Health.critical, Health.degraded, Health.healthy, Health.unknown])
                Padding(
                  padding: const EdgeInsets.only(left: DpSpace.md),
                  child: Semantics(
                    label: context.l10n.healthCountSemantics(o.byHealth[h] ?? 0, h.label),
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(
                          '${o.byHealth[h] ?? 0}',
                          style: t.titleMedium?.copyWith(
                            color: (o.byHealth[h] ?? 0) > 0 ? healthColor(context, h) : context.dp.fgSubtle,
                          ),
                        ),
                        DpHealthPill(h, compact: true),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
