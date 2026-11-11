import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/result/failure.dart';
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

class IncidentsPage {
  const IncidentsPage({required this.byId, required this.cursor, this.loadingMore = false, this.moreError});

  /// Insertion-ordered map keyed by id: a refreshed/updated incident replaces its entry
  /// instead of appearing twice when pages and live updates overlap.
  final LinkedHashMap<String, Incident> byId;
  final String? cursor;
  final bool loadingMore;
  final Failure? moreError;

  List<Incident> get items => byId.values.toList(growable: false);
  bool get hasMore => cursor != null;

  IncidentsPage copyWith({String? cursor, bool? loadingMore, Failure? moreError, bool clearCursor = false}) =>
      IncidentsPage(
        byId: byId,
        cursor: clearCursor ? null : (cursor ?? this.cursor),
        loadingMore: loadingMore ?? this.loadingMore,
        moreError: moreError,
      );
}

class IncidentsController extends AsyncNotifier<IncidentsPage> {
  @override
  Future<IncidentsPage> build() async {
    final filter = ref.watch(incidentFilterProvider);
    final page = await ref.watch(opsRepositoryProvider).incidents(filter);
    return IncidentsPage(
      byId: LinkedHashMap.fromEntries(page.items.map((i) => MapEntry(i.id, i))),
      cursor: page.nextCursor,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(opsRepositoryProvider)
          .incidents(ref.read(incidentFilterProvider), cursor: current.cursor);
      final merged = LinkedHashMap<String, Incident>.of(current.byId);
      for (final i in page.items) {
        merged[i.id] = i; // dedupe
      }
      state = AsyncData(IncidentsPage(byId: merged, cursor: page.nextCursor));
    } on Failure catch (f) {
      state = AsyncData(current.copyWith(loadingMore: false, moreError: f));
    }
  }

  /// Applies a newer version of an incident (e.g. after acting on it in the detail screen).
  /// Only replaces items already in the list (keeps their position); never inserts, so
  /// page boundaries stay consistent. Stale versions are ignored.
  void upsert(Incident updated) {
    final current = state.value;
    final existing = current?.byId[updated.id];
    if (current == null || existing == null || existing.version >= updated.version) return;
    final statuses = ref.read(incidentFilterProvider).statuses;
    final merged = LinkedHashMap<String, Incident>.of(current.byId);
    if (statuses.isEmpty || statuses.contains(updated.status)) {
      merged[updated.id] = updated;
    } else {
      merged.remove(updated.id); // e.g. resolved while viewing "Open"
    }
    state = AsyncData(IncidentsPage(byId: merged, cursor: current.cursor));
  }
}

final incidentsProvider = AsyncNotifierProvider<IncidentsController, IncidentsPage>(
  IncidentsController.new,
  retry: (_, _) => null,
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
              onRefresh: () => ref.refresh(incidentsProvider.future),
              child: AsyncView(
                value: value,
                onRetry: () => ref.invalidate(incidentsProvider),
                data: (page) => page.byId.isEmpty
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
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) {
                            ref.read(incidentsProvider.notifier).loadMore();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          key: const PageStorageKey('incidents-list'), // keeps scroll position
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: page.byId.length + 1,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (context, i) {
                            final items = page.items;
                            if (i < items.length) {
                              final inc = items[i];
                              return IncidentTile(inc, onTap: () => context.push('/incidents/${inc.key}'));
                            }
                            if (page.moreError != null) {
                              return ListTile(
                                title: Text("Couldn't load more", style: Theme.of(context).textTheme.bodySmall),
                                trailing: TextButton(
                                  onPressed: () => ref.read(incidentsProvider.notifier).loadMore(),
                                  child: const Text('Retry'),
                                ),
                              );
                            }
                            if (page.hasMore) {
                              return const Padding(
                                padding: EdgeInsets.all(DpSpace.lg),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return const SizedBox(height: DpSpace.xl);
                          },
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
