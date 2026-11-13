import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/widgets/dp_widgets.dart';
import '../../l10n/l10n.dart';
import '../auth/domain/models.dart';
import '../auth/presentation/session_controller.dart';
import '../offline/live_sync.dart';
import '../offline/outbox.dart';
import '../push/push_routing.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String Function(AppLocalizations) label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Dest(_overview, Icons.space_dashboard_outlined, Icons.space_dashboard),
  _Dest(_services, Icons.dns_outlined, Icons.dns),
  _Dest(_incidents, Icons.warning_amber_outlined, Icons.warning_amber),
  _Dest(_copilot, Icons.auto_awesome_outlined, Icons.auto_awesome),
  _Dest(_settings, Icons.settings_outlined, Icons.settings),
];

String _overview(AppLocalizations l) => l.navOverview;
String _services(AppLocalizations l) => l.navServices;
String _incidents(AppLocalizations l) => l.navIncidents;
String _copilot(AppLocalizations l) => l.navCopilot;
String _settings(AppLocalizations l) => l.navSettings;

/// Bottom navigation on phones, navigation rail on tablets / landscape (≥ 840 dp).
/// Each branch keeps its own stack (StatefulShellRoute.indexedStack).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  StreamSubscription<OutboxNotice>? _notices;
  StreamSubscription<Map<String, dynamic>>? _pushTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attach(ref.read(liveSyncProvider));
      unawaited(_setUpPush());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notices?.cancel());
    unawaited(_pushTaps?.cancel());
    super.dispose();
  }

  /// Starts sync for the current org and surfaces outbox outcomes (conflicts, failures).
  void _attach(LiveSync? live) {
    unawaited(_notices?.cancel());
    _notices = null;
    if (live == null) return;
    live.start();
    _notices = live.outbox.notices.listen((n) {
      if (!mounted) return;
      final message = switch (n) {
        OutboxConflict(:final message) => message,
        OutboxFailed(:final message) => context.l10n.changeNotApplied(message),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  /// Push: route cold-start and background taps (switching org if needed) and register the
  /// device token. A no-op until Firebase is configured (see push_routing.dart).
  Future<void> _setUpPush() async {
    final push = ref.read(pushMessagesProvider);
    final initial = await push.initialMessage();
    if (initial != null) await _openPush(initial);
    _pushTaps = push.opened.listen((m) => unawaited(_openPush(m)));
    final token = await push.token();
    if (token != null) {
      try {
        await ref.read(dioProvider).post<void>('me/devices', data: {'platform': 'ios', 'fcm_token': token});
      } on Object {
        // Registration is retried on next launch.
      }
    }
  }

  Future<void> _openPush(Map<String, dynamic> data) async {
    final payload = PushPayload.parse(data);
    if (payload == null || !mounted) return;
    final session = ref.read(sessionControllerProvider).value;
    if (session is! SignedIn || session.me.org(payload.orgId) == null) return;
    if (session.currentOrgId != payload.orgId) {
      await ref.read(sessionControllerProvider.notifier).selectOrg(payload.orgId);
    }
    if (mounted) GoRouter.of(context).go(payload.route);
  }

  /// Lifecycle (MOBILE_ARCHITECTURE.md §7): foreground → reconnect + delta sync + flush the
  /// outbox + refresh identity; background → close the socket after a short grace period.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final live = ref.read(liveSyncProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(sessionControllerProvider.notifier).refreshProfile();
        live?.onForeground();
      case AppLifecycleState.paused:
        live?.onBackground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
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
    ref.listen(liveSyncProvider, (_, next) => _attach(next)); // org switched
    final session = ref.watch(sessionControllerProvider).value;
    final stale = session is SignedIn && session.isStale;
    final online = ref.watch(onlineProvider).value ?? true;
    final pending = ref.watch(pendingChangesProvider).value ?? 0;

    final body = Column(
      children: [
        if (stale || !online || pending > 0)
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DpSpace.lg, DpSpace.sm, DpSpace.lg, 0),
              child: DpBanner(
                message: [
                  if (stale || !online) context.l10n.offlineBanner,
                  if (pending > 0) context.l10n.pendingChanges(pending),
                ].join(' · '),
                tone: (stale || !online) ? DpBannerTone.warning : DpBannerTone.info,
                action: TextButton(
                  onPressed: () {
                    ref.read(sessionControllerProvider.notifier).refreshProfile();
                    unawaited(ref.read(liveSyncProvider)?.refresh().catchError((Object _) {}));
                  },
                  child: Text(context.l10n.retry),
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
                    label: Text(d.label(context.l10n)),
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
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label(context.l10n)),
        ],
      ),
    );
  }
}
