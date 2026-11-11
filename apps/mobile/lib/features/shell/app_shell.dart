import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/tokens.dart';
import '../../core/design_system/widgets/dp_widgets.dart';
import '../auth/domain/models.dart';
import '../auth/presentation/session_controller.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Dest('Overview', Icons.space_dashboard_outlined, Icons.space_dashboard),
  _Dest('Services', Icons.dns_outlined, Icons.dns),
  _Dest('Incidents', Icons.warning_amber_outlined, Icons.warning_amber),
  _Dest('Copilot', Icons.auto_awesome_outlined, Icons.auto_awesome),
  _Dest('Settings', Icons.settings_outlined, Icons.settings),
];

/// Bottom navigation on phones, navigation rail on tablets / landscape (≥ 840 dp).
/// Each branch keeps its own stack (StatefulShellRoute.indexedStack).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lifecycle: refresh identity when the app returns to the foreground (memberships or
  /// roles may have changed). Phase 3 adds delta sync + WebSocket reconnect here.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(sessionControllerProvider.notifier).refreshProfile();
    }
  }

  void _go(int index) {
    HapticFeedback.selectionClick();
    // Re-tapping the current tab pops it to its root.
    widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final session = ref.watch(sessionControllerProvider).value;
    final stale = session is SignedIn && session.isStale;

    final body = Column(
      children: [
        if (stale)
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DpSpace.lg, DpSpace.sm, DpSpace.lg, 0),
              child: DpBanner(
                message: 'Offline · showing data saved on this device',
                tone: DpBannerTone.warning,
                action: TextButton(
                  onPressed: () => ref.read(sessionControllerProvider.notifier).refreshProfile(),
                  child: const Text('Retry'),
                ),
              ),
            ),
          ),
        Expanded(child: widget.shell),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: widget.shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: DpSpace.lg),
                child: DpLogo(size: 11),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: context.dp.line),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
        ],
      ),
    );
  }
}
