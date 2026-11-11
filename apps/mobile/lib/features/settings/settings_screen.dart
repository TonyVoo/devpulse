import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/tokens.dart';
import '../auth/domain/models.dart';
import '../auth/presentation/session_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Data saved on this device for your account will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok ?? false) await ref.read(sessionControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    if (session is! SignedIn) return const Scaffold();
    final theme = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final t = Theme.of(context).textTheme;
    final org = session.currentOrg;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: DpSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: DpSpace.xs, bottom: DpSpace.sm),
            child: Text(title.toUpperCase(), style: t.labelSmall),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(DpSpace.lg),
        children: [
          section('Profile', [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(session.me.displayName),
              subtitle: Text(session.me.email),
            ),
          ]),
          section('Organization', [
            ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: Text(org?.name ?? 'None selected'),
              subtitle: Text(org == null ? '' : 'Your role: ${org.role.label}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/orgs'),
            ),
          ]),
          section('Appearance', [
            Padding(
              padding: const EdgeInsets.all(DpSpace.md),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ],
                  selected: {theme},
                  onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                ),
              ),
            ),
          ]),
          section('Account', [
            ListTile(
              leading: Icon(Icons.logout, color: context.dp.critical),
              title: Text('Sign out', style: TextStyle(color: context.dp.critical)),
              onTap: () => _confirmSignOut(context, ref),
            ),
          ]),
          Center(
            child: Text(
              'Notification preferences and security settings arrive with push notifications (Phase 3).',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
