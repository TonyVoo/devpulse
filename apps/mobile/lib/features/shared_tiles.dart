import 'package:flutter/material.dart';

import '../core/design_system/tokens.dart';
import '../core/design_system/widgets/status_widgets.dart';
import 'deployments/domain/deployment.dart';
import 'incidents/domain/incident.dart';

/// Incident row: severity, key, title, service, age, assignee. Critical items get a
/// left accent bar (design system: "critical incident" state).
class IncidentTile extends StatelessWidget {
  const IncidentTile(this.incident, {required this.onTap, super.key});

  final Incident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final t = Theme.of(context).textTheme;
    final i = incident;
    final accent = i.status.isOpen && i.severity.index <= 1 ? severityColor(context, i.severity) : Colors.transparent;
    return Semantics(
      button: true,
      label: '${i.severity.label} ${i.key}, ${i.title}, ${i.status.label}, started ${timeAgo(i.startedAt)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: DpSpace.lg, vertical: DpSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DpSeverityChip(i.severity),
              const SizedBox(width: DpSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.title,
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: DpSpace.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(i.key, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
                        if (i.serviceName != null) Text(i.serviceName!, style: t.bodySmall),
                        Text(timeAgo(i.startedAt), style: t.bodySmall),
                        if (i.isDemo) const DpDemoTag(),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DpSpace.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(i.status.label, style: t.bodySmall?.copyWith(color: i.status.isOpen ? p.fg : p.fgSubtle)),
                  if (i.assigneeName != null) Text(i.assigneeName!, style: t.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeploymentTile extends StatelessWidget {
  const DeploymentTile(this.deployment, {super.key, this.showService = true});

  final Deployment deployment;
  final bool showService;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final t = Theme.of(context).textTheme;
    final d = deployment;
    final (icon, color) = switch (d.status) {
      'succeeded' => (Icons.check_circle_outline, p.healthy),
      'failed' => (Icons.highlight_off, p.critical),
      'rolled_back' => (Icons.undo, p.degraded),
      _ => (Icons.pending_outlined, p.cyan),
    };
    return ListTile(
      leading: Icon(icon, color: color, semanticLabel: d.status),
      title: Text(
        [if (showService) d.serviceName, d.version].join(' · '),
        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [?d.shortSha, if (d.commitMessage != null) d.commitMessage!.split('\n').first, ?d.commitAuthor].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeAgo(d.startedAt), style: t.bodySmall),
          if (d.isDemo) const DpDemoTag(),
        ],
      ),
    );
  }
}
