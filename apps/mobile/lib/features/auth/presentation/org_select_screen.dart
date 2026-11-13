import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/result/failure.dart';
import '../../../l10n/l10n.dart';
import '../domain/models.dart';
import 'session_controller.dart';

/// Pick or create the organization to work in. Reached after sign-in when no org is
/// selected, and from Settings → Organization to switch.
class OrgSelectScreen extends ConsumerStatefulWidget {
  const OrgSelectScreen({super.key});

  @override
  ConsumerState<OrgSelectScreen> createState() => _OrgSelectScreenState();
}

class _OrgSelectScreenState extends ConsumerState<OrgSelectScreen> {
  final _name = TextEditingController();
  bool _creating = false;
  Failure? _failure;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _select(String id) async {
    await ref.read(sessionControllerProvider.notifier).selectOrg(id);
    if (mounted) context.go('/overview');
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _failure = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).createOrg(_name.text);
      if (mounted) context.go('/overview');
    } on Failure catch (f) {
      if (mounted) setState(() => _failure = f);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).value;
    if (session is! SignedIn) return const Scaffold();
    final p = context.dp;
    final t = Theme.of(context).textTheme;
    final orgs = session.me.memberships;
    final l = context.l10n;
    final nameError = _failure is ValidationFailure ? l.orgNameLength : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.organizations),
        automaticallyImplyLeading: false,
        actions: [
          if (session.currentOrg != null) TextButton(onPressed: () => context.go('/overview'), child: Text(l.done)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DpSpace.lg),
          children: [
            if (session.isStale) ...[
              DpBanner(message: l.offlineOrgs, tone: DpBannerTone.warning),
              const SizedBox(height: DpSpace.lg),
            ],
            if (orgs.isNotEmpty) ...[
              Text(l.yourOrganizations, style: t.labelSmall),
              const SizedBox(height: DpSpace.sm),
              Card(
                child: Column(
                  children: [
                    for (final (i, org) in orgs.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        title: Text(org.name),
                        subtitle: Text(org.slug, style: t.bodySmall),
                        trailing: org.id == session.currentOrgId
                            ? Icon(Icons.check_circle, color: p.cyan, semanticLabel: l.current)
                            : Text(org.role.label, style: t.bodySmall),
                        onTap: () => _select(org.id),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: DpSpace.xl),
            ],
            Text(orgs.isEmpty ? l.createFirstOrg : l.createAnotherOrg, style: t.titleMedium),
            const SizedBox(height: DpSpace.sm),
            Text(l.orgIntro, style: t.bodySmall),
            const SizedBox(height: DpSpace.lg),
            if (_failure != null && _failure is! ValidationFailure) ...[
              DpBanner(message: _failure!.message, tone: DpBannerTone.error),
              const SizedBox(height: DpSpace.md),
            ],
            DpTextField(
              label: l.orgName,
              controller: _name,
              errorText: nameError,
              enabled: !_creating && !session.isStale,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: DpSpace.md),
            DpButton(label: l.createOrg, onPressed: session.isStale ? null : _create, loading: _creating, expand: true),
          ],
        ),
      ),
    );
  }
}
