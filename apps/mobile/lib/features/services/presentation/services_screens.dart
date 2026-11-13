import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/network/org_api.dart';
import '../../../l10n/l10n.dart';
import '../../deployments/domain/deployment.dart';
import '../../incidents/domain/incident.dart';
import '../../offline/live_sync.dart';
import '../../ops_repositories.dart';
import '../../shared_tiles.dart';
import '../domain/service.dart';

// --------------------------------------------------------------------- list state

/// Search text + health filter. A plain (non-autoDispose) provider so the filter survives
/// navigating into a service and back.
class ServicesQuery {
  const ServicesQuery({this.text = '', this.health = const {}});
  final String text;
  final Set<Health> health;
}

class ServicesQueryController extends Notifier<ServicesQuery> {
  @override
  ServicesQuery build() => const ServicesQuery();

  void setText(String t) => state = ServicesQuery(text: t, health: state.health);

  void toggle(Health h) {
    final next = {...state.health};
    next.contains(h) ? next.remove(h) : next.add(h);
    state = ServicesQuery(text: state.text, health: next);
  }
}

final servicesQueryProvider = NotifierProvider<ServicesQueryController, ServicesQuery>(ServicesQueryController.new);

/// Live query on the offline cache; problems first, then by name.
final servicesProvider = StreamProvider<List<MonitoredService>>((ref) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(const []);
  final q = ref.watch(servicesQueryProvider);
  const rank = {Health.critical: 0, Health.degraded: 1, Health.unknown: 2, Health.healthy: 3};
  return live.store
      .watchServices(text: q.text, health: q.health)
      .map(
        (items) => [...items]
          ..sort((a, b) {
            final r = rank[a.health]!.compareTo(rank[b.health]!);
            return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }),
      );
});

class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  late final _search = TextEditingController(text: ref.read(servicesQueryProvider).text);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(servicesQueryProvider.notifier).setText(text));
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(servicesQueryProvider);
    final value = ref.watch(servicesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.navServices)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DpSpace.lg, 0, DpSpace.lg, DpSpace.sm),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.l10n.searchServices),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DpSpace.lg),
              children: [
                for (final h in [Health.critical, Health.degraded, Health.healthy, Health.unknown])
                  Padding(
                    padding: const EdgeInsets.only(right: DpSpace.sm),
                    child: FilterChip(
                      label: Text(h.label),
                      selected: query.health.contains(h),
                      onSelected: (_) => ref.read(servicesQueryProvider.notifier).toggle(h),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.read(liveSyncProvider)?.refresh(),
              child: AsyncView(
                value: value,
                onRetry: () => ref.invalidate(servicesProvider),
                data: (services) => services.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 60),
                          DpEmptyState(
                            icon: Icons.dns_outlined,
                            title: query.text.isEmpty && query.health.isEmpty
                                ? context.l10n.noServicesYet
                                : context.l10n.noMatchingServices,
                            description: query.text.isEmpty && query.health.isEmpty
                                ? context.l10n.servicesEmptyBody
                                : context.l10n.tryDifferentSearch,
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: services.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (_, i) => _ServiceTile(services[i]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile(this.s);

  final MonitoredService s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      onTap: () => context.push('/services/${s.id}'),
      title: Row(
        children: [
          Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis)),
          if (s.isDemo) ...[const SizedBox(width: DpSpace.sm), const DpDemoTag()],
        ],
      ),
      subtitle: Text(
        '${s.environment} · ${s.tier} · '
        '${s.lastSeenAt == null ? context.l10n.noDataYet : context.l10n.seenAgo(timeAgo(s.lastSeenAt!))}',
        style: t.bodySmall,
      ),
      trailing: DpHealthPill(s.health),
    );
  }
}

// --------------------------------------------------------------------- detail

class MetricRangeController extends Notifier<MetricRange> {
  @override
  MetricRange build() => MetricRange.hour;

  void set(MetricRange r) => state = r;
}

final metricRangeProvider = NotifierProvider<MetricRangeController, MetricRange>(MetricRangeController.new);

final serviceProvider = FutureProvider.autoDispose.family<MonitoredService, String>(
  (ref, id) => ref.watch(opsRepositoryProvider).service(id),
  retry: (_, _) => null,
);

const _metricNames = [
  'http.server.duration_ms:p95',
  'http.server.error_rate',
  'http.server.requests:sum',
  'process.cpu.utilization:avg',
];

final serviceMetricsProvider = FutureProvider.autoDispose.family<List<MetricSeries>, String>(
  (ref, id) => ref.watch(opsRepositoryProvider).metrics(id, _metricNames, ref.watch(metricRangeProvider)),
  retry: (_, _) => null,
);

final serviceIncidentsProvider = StreamProvider.autoDispose.family<Paged<Incident>, String>((ref, id) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(const Paged([], null));
  return live.store.watchIncidents(const IncidentFilter(), serviceId: id).map((items) => Paged(items, null));
});

final serviceDeploymentsProvider = StreamProvider.autoDispose.family<Paged<Deployment>, String>((ref, id) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(const Paged([], null));
  return live.store.watchDeployments(serviceId: id, limit: 10).map((items) => Paged(items, null));
});

class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({required this.serviceId, super.key});

  final String serviceId;

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(serviceMetricsProvider(serviceId))
      ..invalidate(serviceIncidentsProvider(serviceId))
      ..invalidate(serviceDeploymentsProvider(serviceId))
      ..invalidate(serviceProvider(serviceId));
    await ref.read(serviceProvider(serviceId).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(serviceProvider(serviceId));
    return Scaffold(
      appBar: AppBar(title: Text(svc.value?.name ?? context.l10n.service)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: AsyncView(
          value: svc,
          onRetry: () => ref.invalidate(serviceProvider(serviceId)),
          data: _ServiceDetailBody.new,
        ),
      ),
    );
  }
}

class _ServiceDetailBody extends ConsumerWidget {
  const _ServiceDetailBody(this.s);

  final MonitoredService s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = context.dp;
    final l = context.l10n;
    final range = ref.watch(metricRangeProvider);
    final metrics = ref.watch(serviceMetricsProvider(s.id));
    final incidents = ref.watch(serviceIncidentsProvider(s.id));
    final deployments = ref.watch(serviceDeploymentsProvider(s.id));

    MetricSeries? series(String spec) {
      final [name, ...rest] = spec.split(':');
      final agg = rest.isEmpty ? null : rest.first;
      return metrics.value?.where((m) => m.name == name && (agg == null || m.aggregation == agg)).firstOrNull;
    }

    Widget chart(
      String title,
      String spec, {
      String Function(double)? fmt,
      Color? color,
      String Function(double?)? latest,
    }) {
      final m = series(spec);
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DpSpace.md, DpSpace.md, DpSpace.md, DpSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: t.labelSmall)),
                  if (m != null)
                    Text((latest ?? (v) => v == null ? '—' : compactNumber(v))(m.latest), style: t.titleSmall),
                ],
              ),
              const SizedBox(height: DpSpace.sm),
              if (metrics.isLoading && m == null)
                const SizedBox(height: 140, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else
                DpLineChart(
                  points: m?.points ?? const [],
                  semanticLabel: l.chartSemantics(title),
                  formatY: fmt,
                  color: color,
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DpSpace.lg),
      children: [
        Row(
          children: [
            DpHealthPill(s.health),
            const SizedBox(width: DpSpace.sm),
            if (s.isDemo) const DpDemoTag(),
            const Spacer(),
            Text(s.lastSeenAt == null ? l.noDataYetCap : l.seenAgoCap(timeAgo(s.lastSeenAt!)), style: t.bodySmall),
          ],
        ),
        const SizedBox(height: DpSpace.sm),
        Text(
          '${l.serviceMeta(s.slug, s.environment, s.tier)}${s.ownerTeam != null ? ' · ${s.ownerTeam}' : ''}',
          style: t.bodySmall,
        ),
        if (s.description != null) ...[const SizedBox(height: DpSpace.sm), Text(s.description!, style: t.bodyMedium)],
        const SizedBox(height: DpSpace.lg),
        SegmentedButton<MetricRange>(
          showSelectedIcon: false,
          segments: [for (final r in MetricRange.values) ButtonSegment(value: r, label: Text(r.label))],
          selected: {range},
          onSelectionChanged: (v) => ref.read(metricRangeProvider.notifier).set(v.first),
        ),
        if (metrics.hasError)
          Padding(
            padding: const EdgeInsets.only(top: DpSpace.md),
            child: DpBanner(
              message: l.metricsError,
              tone: DpBannerTone.error,
              action: TextButton(onPressed: () => ref.invalidate(serviceMetricsProvider(s.id)), child: Text(l.retry)),
            ),
          ),
        const SizedBox(height: DpSpace.md),
        chart(l.latencyP95, 'http.server.duration_ms:p95', fmt: millis, latest: millis),
        const SizedBox(height: DpSpace.sm),
        chart(l.errorRate, 'http.server.error_rate', fmt: percent, color: p.critical, latest: percent),
        const SizedBox(height: DpSpace.sm),
        chart(l.requests, 'http.server.requests:sum'),
        const SizedBox(height: DpSpace.sm),
        chart(l.cpu, 'process.cpu.utilization:avg', fmt: percent, color: p.violet, latest: percent),
        SectionHeader(l.openIncidents),
        _AsyncSection(
          value: incidents,
          empty: l.noOpenIncidents,
          builder: (page) => [
            for (final i in page.items) IncidentTile(i, onTap: () => context.go('/incidents/${i.key}')),
          ],
        ),
        SectionHeader(l.recentDeployments),
        _AsyncSection(
          value: deployments,
          empty: l.noDeploymentsRecorded,
          builder: (page) => [for (final d in page.items.take(10)) DeploymentTile(d, showService: false)],
        ),
      ],
    );
  }
}

class _AsyncSection<T> extends StatelessWidget {
  const _AsyncSection({required this.value, required this.builder, required this.empty});

  final AsyncValue<Paged<T>> value;
  final List<Widget> Function(Paged<T>) builder;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final v = value.value;
    if (v == null) {
      return Card(
        child: ListTile(
          title: Text(
            value.hasError ? context.l10n.couldNotLoad : context.l10n.loadingEllipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final children = builder(v);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: children.isEmpty
          ? ListTile(title: Text(empty, style: Theme.of(context).textTheme.bodySmall))
          : Column(
              children: [
                for (final (i, c) in children.indexed) ...[if (i > 0) const Divider(), c],
              ],
            ),
    );
  }
}
