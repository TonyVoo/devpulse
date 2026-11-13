import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/tokens.dart';
import '../../l10n/l10n.dart';
import '../auth/domain/models.dart';
import '../auth/presentation/session_controller.dart';

final _segmentStyle = SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6));

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.signOutQ),
        content: Text(ctx.l10n.signOutBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.signOut)),
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
    final language = ref.watch(localeProvider).value?.languageCode ?? '';
    final t = Theme.of(context).textTheme;
    final l = context.l10n;
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
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        padding: const EdgeInsets.all(DpSpace.lg),
        children: [
          section(l.profile, [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(session.me.displayName),
              subtitle: Text(session.me.email),
            ),
          ]),
          section(l.organization, [
            ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: Text(org?.name ?? l.noneSelected),
              subtitle: Text(org == null ? '' : l.yourRole(org.role.label)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/orgs'),
            ),
          ]),
          section(l.appearance, [
            Padding(
              padding: const EdgeInsets.all(DpSpace.md),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  // Text-only, like the language row, so longer labels ("Hệ thống") fit on phones.
                  style: _segmentStyle,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem)),
                    ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark)),
                    ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight)),
                  ],
                  selected: {theme},
                  onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                ),
              ),
            ),
          ]),
          section(l.language, [
            Padding(
              padding: const EdgeInsets.all(DpSpace.md),
              child: SizedBox(
                width: double.infinity,
                // Each language is named in itself, so it can be found whatever the current one.
                child: SegmentedButton<String>(
                  style: _segmentStyle,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: '', label: Text(l.languageSystem)),
                    const ButtonSegment(value: 'en', label: Text('English')),
                    const ButtonSegment(value: 'vi', label: Text('Tiếng Việt')),
                  ],
                  selected: {language},
                  onSelectionChanged: (s) =>
                      ref.read(localeProvider.notifier).set(s.first.isEmpty ? null : Locale(s.first)),
                ),
              ),
            ),
          ]),
          section(l.account, [
            ListTile(
              leading: Icon(Icons.logout, color: context.dp.critical),
              title: Text(l.signOut, style: TextStyle(color: context.dp.critical)),
              onTap: () => _confirmSignOut(context, ref),
            ),
          ]),
          Center(
            child: Text(l.settingsFooter, style: t.bodySmall, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
