import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/result/failure.dart';
import '../../auth/domain/models.dart';
import '../../auth/presentation/session_controller.dart';
import '../../offline/live_sync.dart';
import '../../ops_repositories.dart';
import '../../shared_tiles.dart';
import '../domain/incident.dart';

class IncidentFilterController extends Notifier<IncidentFilter> {
  @override
  IncidentFilter build() => const IncidentFilter();

  void set(IncidentFilter f) => state = f;
}

/// Kept alive (not autoDispose): the filter survives opening an incident and coming back.
final incidentFilterProvider = NotifierProvider<IncidentFilterController, IncidentFilter>(IncidentFilterController.new);

/// The list is a live query on the local database (ADR-005): sync pages, realtime updates
/// and offline edits all land in the same rows, so items can never appear twice.
final incidentsProvider = StreamProvider<List<Incident>>((ref) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(const []);
  final session = ref.watch(sessionControllerProvider).value;
  final meId = session is SignedIn ? session.me.id : null;
  return live.store.watchIncidents(ref.watch(incidentFilterProvider), meId: meId);
});

/// Older incidents beyond the offline window are fetched on demand and cached.
class OlderIncidentsLoader extends Notifier<({bool loading, bool done, String? cursor, Failure? error})> {
  @override
  ({bool loading, bool done, String? cursor, Failure? error}) build() {
    ref.watch(incidentFilterProvider);
    return (loading: false, done: false, cursor: null, error: null);
  }

  Future<void> load() async {
    final live = ref.read(liveSyncProvider);
    if (state.loading || state.done || live == null) return;
    state = (loading: true, done: false, cursor: state.cursor, error: null);
    try {
      final page = await ref
          .read(opsRepositoryProvider)
          .incidents(ref.read(incidentFilterProvider), cursor: state.cursor);
      for (final i in page.items) {
        await live.store.cacheIfMissing(i);
      }
      state = (loading: false, done: page.nextCursor == null, cursor: page.nextCursor, error: null);
    } on Failure catch (f) {
      state = (loading: false, done: false, cursor: state.cursor, error: f);
    }
  }
}

final olderIncidentsProvider =
    NotifierProvider<OlderIncidentsLoader, ({bool loading, bool done, String? cursor, Failure? error})>(
      OlderIncidentsLoader.new,
    );

enum _StatusTab {
  open('Open', {IncidentStatus.triggered, IncidentStatus.acknowledged}),
  triggered('Triggered', {IncidentStatus.triggered}),
  acknowledged('Acknowledged', {IncidentStatus.acknowledged}),
  resolved('Resolved', {IncidentStatus.resolved}),
  all('All', {});

  const _StatusTab(this.label, this.statuses);
  final String label;
  final Set<IncidentStatus> statuses;
}

class IncidentsScreen extends ConsumerWidget {
  const IncidentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(incidentFilterProvider);
    final value = ref.watch(incidentsProvider);
    final older = ref.watch(olderIncidentsProvider);
    final tab = _StatusTab.values.firstWhere(
      (t) => t.statuses.length == filter.statuses.length && t.statuses.containsAll(filter.statuses),
      orElse: () => _StatusTab.all,
    );
    void setFilter(IncidentFilter f) => ref.read(incidentFilterProvider.notifier).set(f);

    return Scaffold(
      appBar: AppBar(title: const Text('Incidents')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DpSpace.lg),
              children: [
                for (final t in _StatusTab.values)
                  Padding(
                    padding: const EdgeInsets.only(right: DpSpace.sm),
                    child: ChoiceChip(
                      label: Text(t.label),
                      selected: t == tab,
                      onSelected: (_) => setFilter(filter.copyWith(statuses: t.statuses)),
                    ),
                  ),
                const VerticalDivider(),
                FilterChip(
                  label: const Text('Mine'),
                  selected: filter.mineOnly,
                  onSelected: (v) => setFilter(filter.copyWith(mineOnly: v)),
                ),
                for (final s in Severity.values)
                  Padding(
                    padding: const EdgeInsets.only(left: DpSpace.sm),
                    child: FilterChip(
                      label: Text(s.label),
                      selected: filter.severities.contains(s),
                      onSelected: (v) => setFilter(
                        filter.copyWith(
                          severities: v ? {...filter.severities, s} : ({...filter.severities}..remove(s)),
                        ),
                      ),
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
                onRetry: () => ref.invalidate(incidentsProvider),
                data: (items) => items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 60),
                          DpEmptyState(
                            icon: Icons.verified_outlined,
                            title: tab == _StatusTab.open ? 'No open incidents — all clear' : 'No incidents match',
                            description: tab == _StatusTab.open
                                ? 'Incidents opened by alert rules or by your team will appear here.'
                                : 'Try a different status or severity filter.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        key: const PageStorageKey('incidents-list'), // keeps scroll position
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: items.length + 1,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, i) {
                          if (i < items.length) {
                            final inc = items[i];
                            return IncidentTile(inc, onTap: () => context.push('/incidents/${inc.key}'));
                          }
                          if (older.done) return const SizedBox(height: DpSpace.xl);
                          return Padding(
                            padding: const EdgeInsets.all(DpSpace.md),
                            child: Center(
                              child: DpButton(
                                label: older.error != null ? "Couldn't load — retry" : 'Load older incidents',
                                variant: DpButtonVariant.ghost,
                                loading: older.loading,
                                onPressed: () => ref.read(olderIncidentsProvider.notifier).load(),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
