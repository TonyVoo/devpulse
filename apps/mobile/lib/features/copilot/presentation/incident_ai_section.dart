import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/result/failure.dart';
import '../../incidents/domain/incident.dart';
import '../../offline/live_sync.dart';
import '../data/ai_repository.dart';
import '../domain/investigation.dart';
import 'ai_widgets.dart';

/// "AI analysis" block on the incident screen: start an investigation, follow its progress,
/// read hypotheses with their evidence, decide on proposed actions, ask follow-ups.
class IncidentAiSection extends ConsumerStatefulWidget {
  const IncidentAiSection({required this.incident, required this.canAct, required this.isAdmin, super.key});

  final Incident incident;
  final bool canAct;
  final bool isAdmin;

  @override
  ConsumerState<IncidentAiSection> createState() => _IncidentAiSectionState();
}

class _IncidentAiSectionState extends ConsumerState<IncidentAiSection> {
  bool _starting = false;
  final Set<String> _deciding = {};

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(aiRepositoryProvider).start(widget.incident.key);
      ref.invalidate(incidentAnalysisProvider(widget.incident.id));
    } on Failure catch (f) {
      _snack(aiErrorMessage(f.code, detail: f.message));
      if (f.code == 'ai.already_running') ref.invalidate(incidentAnalysisProvider(widget.incident.id));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _decide(Investigation inv, Proposal p, {required bool approve}) async {
    if (approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Approve this action?'),
          content: Text(
            '“${p.description}”\n\nApproving records your decision on the incident. '
            'DevPulse does not run it: your team carries it out.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
          ],
        ),
      );
      if (!(ok ?? false)) return;
    }
    setState(() => _deciding.add(p.id));
    try {
      await ref.read(aiRepositoryProvider).decide(inv.id, p.id, approve: approve);
      ref.invalidate(incidentAnalysisProvider(widget.incident.id));
    } on Failure catch (f) {
      _snack(f.message);
    } finally {
      if (mounted) setState(() => _deciding.remove(p.id));
    }
  }

  Future<void> _feedback(Investigation inv, bool helpful) async {
    try {
      await ref.read(aiRepositoryProvider).feedback(inv.id, helpful: helpful);
      ref.invalidate(incidentAnalysisProvider(widget.incident.id));
      _snack('Thanks, your feedback helps tune the investigator.');
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(incidentAnalysisProvider(widget.incident.id));
    final online = ref.watch(onlineProvider).value ?? true;
    final t = Theme.of(context).textTheme;
    final analysis = value.value;
    final inv = analysis?.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'AI analysis',
          action: inv != null && !inv.status.isActive && widget.canAct && online
              ? TextButton(onPressed: _starting ? null : _start, child: const Text('Run again'))
              : null,
        ),
        if (analysis?.stale ?? false)
          const Padding(
            padding: EdgeInsets.only(bottom: DpSpace.sm),
            child: DpBanner(message: 'Showing the analysis saved on this device.', tone: DpBannerTone.warning),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(DpSpace.lg),
            child: value.isLoading && analysis == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : value.hasError && analysis == null
                ? Row(
                    children: [
                      Expanded(child: Text("Couldn't load the AI analysis", style: t.bodySmall)),
                      TextButton(
                        onPressed: () => ref.invalidate(incidentAnalysisProvider(widget.incident.id)),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : inv == null
                ? _empty(t, online)
                : inv.status.isActive
                ? _progress(inv, t)
                : inv.status == RunStatus.succeeded && inv.result != null
                ? _result(inv, inv.result!, t, online)
                : _failed(inv, t, online),
          ),
        ),
      ],
    );
  }

  Widget _empty(TextTheme t, bool online) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Copilot reads this incident\'s metrics, logs, deployments and similar past incidents, '
        'then suggests probable causes, each with the evidence behind it.',
        style: t.bodyMedium,
      ),
      if (widget.canAct) ...[
        const SizedBox(height: DpSpace.md),
        DpButton(
          label: online ? 'Investigate with AI' : 'Investigate (needs a connection)',
          icon: Icons.auto_awesome,
          loading: _starting,
          onPressed: online ? _start : null,
        ),
      ],
    ],
  );

  Widget _progress(Investigation inv, TextTheme t) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: DpSpace.md),
        Expanded(child: Text(inv.status.progressLabel, style: t.bodyMedium)),
      ],
    ),
  );

  Widget _failed(Investigation inv, TextTheme t, bool online) {
    final p = context.dp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, color: p.critical, size: 18),
            const SizedBox(width: DpSpace.sm),
            Text('Analysis unavailable', style: t.titleSmall),
          ],
        ),
        const SizedBox(height: DpSpace.sm),
        Text(aiErrorMessage(inv.summary.errorCode, detail: inv.errorDetail), style: t.bodyMedium),
        Text('Incident actions are not affected.', style: t.bodySmall),
        if (widget.canAct && online && inv.summary.errorCode != 'ai.disabled') ...[
          const SizedBox(height: DpSpace.md),
          DpButton(label: 'Try again', variant: DpButtonVariant.secondary, loading: _starting, onPressed: _start),
        ],
      ],
    );
  }

  Widget _result(Investigation inv, Analysis a, TextTheme t, bool online) {
    final p = context.dp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: DpSpace.sm,
          runSpacing: DpSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Hypotheses — not confirmed · ${timeAgo(inv.summary.createdAt)}', style: t.bodySmall),
            if (inv.summary.isDemoProvider) const DemoAnalyzerTag(),
          ],
        ),
        const SizedBox(height: DpSpace.sm),
        Text(a.summary, style: t.titleMedium),
        if (a.impact.isNotEmpty) ...[
          const SizedBox(height: DpSpace.xs),
          Text(a.impact, style: t.bodyMedium?.copyWith(color: p.fgMuted)),
        ],
        const SizedBox(height: DpSpace.lg),
        Text('Probable causes', style: t.labelLarge),
        for (final (i, c) in a.causes.indexed) _cause(inv, c, i + 1, t),
        if (a.actions.isNotEmpty) ...[
          const SizedBox(height: DpSpace.lg),
          Text('Recommended next steps', style: t.labelLarge),
          for (final action in a.actions) _action(inv, action, t),
        ],
        if (a.dataGaps.isNotEmpty) ...[
          const SizedBox(height: DpSpace.lg),
          Text('What DevPulse could not see', style: t.labelLarge),
          for (final g in a.dataGaps)
            Padding(
              padding: const EdgeInsets.only(top: DpSpace.xs),
              child: Text('• $g', style: t.bodySmall),
            ),
        ],
        if (a.adjustments.isNotEmpty) ...[
          const SizedBox(height: DpSpace.sm),
          for (final adj in a.adjustments) Text('Adjusted: $adj', style: t.bodySmall),
        ],
        if (a.limitations.isNotEmpty) ...[
          const SizedBox(height: DpSpace.md),
          Text(a.limitations, style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
        ],
        const Divider(height: DpSpace.xl),
        Row(
          children: [
            Expanded(
              child: DpButton(
                label: 'Ask a follow-up',
                icon: Icons.chat_bubble_outline,
                variant: DpButtonVariant.secondary,
                onPressed: () => context.push('${Routes.incidents}/${widget.incident.key}/ai/${inv.id}'),
              ),
            ),
            const SizedBox(width: DpSpace.sm),
            IconButton(
              tooltip: 'Helpful',
              isSelected: inv.myFeedback ?? false,
              icon: const Icon(Icons.thumb_up_outlined),
              selectedIcon: Icon(Icons.thumb_up, color: p.cyan),
              onPressed: online ? () => _feedback(inv, true) : null,
            ),
            IconButton(
              tooltip: 'Not helpful',
              isSelected: inv.myFeedback == false,
              icon: const Icon(Icons.thumb_down_outlined),
              selectedIcon: Icon(Icons.thumb_down, color: p.degraded),
              onPressed: online ? () => _feedback(inv, false) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _cause(Investigation inv, Cause c, int rank, TextTheme t) => Padding(
    padding: const EdgeInsets.only(top: DpSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text('$rank. ${c.cause}', style: t.titleSmall)),
            const SizedBox(width: DpSpace.sm),
            ConfidencePill(c),
          ],
        ),
        const SizedBox(height: DpSpace.xs),
        Text(c.reasoning, style: t.bodySmall),
        Wrap(
          spacing: DpSpace.xs,
          children: [
            for (final r in c.evidenceRefs) EvidenceChip(evidenceRef: r, evidence: inv.evidenceFor(r)),
            for (final r in c.counterEvidenceRefs)
              EvidenceChip(evidenceRef: r, evidence: inv.evidenceFor(r), counter: true),
          ],
        ),
        if (c.howToVerify.isNotEmpty) Text('Verify: ${c.howToVerify}', style: t.bodySmall),
      ],
    ),
  );

  Widget _action(Investigation inv, AiAction a, TextTheme t) {
    final proposal = inv.proposal(a.proposalId);
    final canDecide =
        widget.canAct &&
        proposal != null &&
        proposal.status == 'proposed' &&
        (a.risk != 'destructive' || widget.isAdmin);
    final busy = proposal != null && _deciding.contains(proposal.id);
    return Padding(
      padding: const EdgeInsets.only(top: DpSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.action, style: t.bodyMedium),
          Wrap(
            spacing: DpSpace.sm,
            children: [
              RiskBadge(a.risk),
              if (proposal != null && proposal.status != 'proposed') ...[
                Text(
                  proposal.status == 'approved' ? '· Approved (not executed by DevPulse)' : '· Rejected',
                  style: t.bodySmall,
                ),
              ],
            ],
          ),
          if (canDecide)
            Wrap(
              spacing: DpSpace.sm,
              children: [
                TextButton(
                  onPressed: busy ? null : () => _decide(inv, proposal, approve: true),
                  child: const Text('Approve'),
                ),
                TextButton(
                  onPressed: busy ? null : () => _decide(inv, proposal, approve: false),
                  child: const Text('Reject'),
                ),
              ],
            )
          else if (proposal != null && proposal.status == 'proposed' && a.risk == 'destructive')
            Text('An admin must decide on destructive actions.', style: t.bodySmall),
        ],
      ),
    );
  }
}
