import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/network/org_api.dart';
import '../../offline/live_sync.dart';
import '../../shared_tiles.dart';
import '../domain/deployment.dart';

/// Recent deployments from the offline cache (last 7 days + anything synced since).
final deploymentsProvider = StreamProvider.autoDispose<Paged<Deployment>>((ref) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(const Paged([], null));
  return live.store.watchDeployments().map((items) => Paged(items, null));
});

class DeploymentsScreen extends ConsumerWidget {
  const DeploymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(deploymentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Deployments')),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(liveSyncProvider)?.refresh(),
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
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: DpSpace.xl),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) => DeploymentTile(page.items[i]),
                ),
        ),
      ),
    );
  }
}
