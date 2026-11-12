import 'package:flutter/material.dart';

import '../../../core/design_system/tokens.dart';
import '../domain/investigation.dart';

/// Shared pieces of the AI UI (incident section, chat, Copilot tab).

class ConfidencePill extends StatelessWidget {
  const ConfidencePill(this.cause, {super.key});

  final Cause cause;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final color = switch (cause.confidenceLabel) {
      'high' => p.cyan,
      'medium' => p.degraded,
      _ => p.fgSubtle,
    };
    final pct = (cause.confidence * 100).round();
    return Semantics(
      label: '${cause.confidenceLabel} confidence, $pct percent',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(DpRadius.sm),
        ),
        child: Text(
          '${cause.confidenceLabel.toUpperCase()} · $pct%',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class RiskBadge extends StatelessWidget {
  const RiskBadge(this.risk, {super.key});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final (label, color) = switch (risk) {
      'read_only' => ('Read-only', p.healthy),
      'destructive' => ('Destructive · admin approval', p.critical),
      _ => ('Changes a system · needs approval', p.degraded),
    };
    return Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    );
  }
}

/// Marks analyses from the rule-based FakeProvider so they're never mistaken for an LLM.
class DemoAnalyzerTag extends StatelessWidget {
  const DemoAnalyzerTag({super.key});

  @override
  Widget build(BuildContext context) {
    final v = context.dp.violet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: v.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
      child: Text(
        'DEMO ANALYZER · NOT AN LLM',
        style: TextStyle(color: v, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      ),
    );
  }
}

IconData evidenceIcon(String kind) => switch (kind) {
  'metric' => Icons.show_chart,
  'log' => Icons.notes,
  'deployment' => Icons.rocket_launch_outlined,
  'alert' => Icons.notifications_active_outlined,
  'incident' => Icons.history,
  _ => Icons.description_outlined,
};

/// Tappable `EV-n` reference; opens the evidence DevPulse computed.
class EvidenceChip extends StatelessWidget {
  const EvidenceChip({required this.evidenceRef, required this.evidence, this.counter = false, super.key});

  final String evidenceRef;
  final Evidence? evidence;
  final bool counter;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final e = evidence;
    return ActionChip(
      avatar: Icon(e == null ? Icons.help_outline : evidenceIcon(e.kind), size: 16),
      label: Text(counter ? '$evidenceRef (against)' : evidenceRef),
      labelStyle: TextStyle(color: counter ? p.degraded : p.fg, fontSize: 12),
      visualDensity: VisualDensity.compact,
      tooltip: e?.title,
      onPressed: e == null ? null : () => showEvidence(context, e),
    );
  }
}

Future<void> showEvidence(BuildContext context, Evidence e) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) {
    final t = Theme.of(ctx).textTheme;
    final q = e.sourceQuery;
    final window = [q['from'], q['to']].whereType<String>().map(_shortTime).join(' → ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DpSpace.lg, 0, DpSpace.lg, DpSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(evidenceIcon(e.kind), size: 20),
                const SizedBox(width: DpSpace.sm),
                Expanded(child: Text('${e.ref} · ${e.title}', style: t.titleMedium)),
              ],
            ),
            const SizedBox(height: DpSpace.md),
            SelectableText(e.text, style: t.bodyMedium),
            const SizedBox(height: DpSpace.lg),
            Text('Computed by DevPulse from stored ${e.kind} data, not by the AI.', style: t.bodySmall),
            if (q['type'] != null)
              Text(
                'Source: ${q['type']}${q['name'] != null ? ' ${q['name']}' : ''}'
                '${window.isNotEmpty ? ' · $window' : ''}',
                style: t.bodySmall,
              ),
          ],
        ),
      ),
    );
  },
);

String _shortTime(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
}
