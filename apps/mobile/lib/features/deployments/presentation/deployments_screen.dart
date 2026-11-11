import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/network/org_api.dart';
import '../../ops_repositories.dart';
import '../../shared_tiles.dart';
import '../domain/deployment.dart';

class DeploymentsController extends AsyncNotifier<Paged<Deployment>> {
  bool _loadingMore = false;

  @override
  Future<Paged<Deployment>> build() => ref.watch(opsRepositoryProvider).deployments();

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.nextCursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await ref.read(opsRepositoryProvider).deployments(cursor: current.nextCursor);
      final seen = {for (final d in current.items) d.id};
      state = AsyncData(Paged([...current.items, ...next.items.where((d) => !seen.contains(d.id))], next.nextCursor));
    } finally {
      _loadingMore = false;
    }
  }
}

final deploymentsProvider = AsyncNotifierProvider.autoDispose<DeploymentsController, Paged<Deployment>>(
  DeploymentsController.new,
  retry: (_, _) => null,
);

class DeploymentsScreen extends ConsumerWidget {
  const DeploymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(deploymentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Deployments')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(deploymentsProvider.future),
        child: AsyncView(
          value: value,
          onRetry: () => ref.invalidate(deploymentsProvider),
          data: (page) => page.items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 60),
                    DpEmptyState(
                      icon: Icons.rocket_launch_outlined,
                      title: 'No deployments yet',
                      description:
                          'Send deployment events from CI with an ingest key, or connect GitHub on the web dashboard.',
                    ),
                  ],
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                      ref.read(deploymentsProvider.notifier).loadMore();
                    }
                    return false;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: DpSpace.xl),
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => DeploymentTile(page.items[i]),
                  ),
                ),
        ),
      ),
    );
  }
}
