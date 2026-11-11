import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/network/org_api.dart';
import '../../../core/result/failure.dart';
import '../../auth/domain/models.dart';
import '../../auth/presentation/session_controller.dart';
import '../../ops_repositories.dart';
import '../domain/incident.dart';
import 'incidents_list.dart';

class IncidentDetail {
  const IncidentDetail({
    required this.incident,
    required this.timeline,
    required this.comments,
    required this.deployments,
  });

  final Incident incident;
  final List<TimelineEvent> timeline;
  final List<IncidentComment> comments;
  final List<CorrelatedDeployment> deployments;

  IncidentDetail copyWith({Incident? incident, List<IncidentComment>? comments, List<TimelineEvent>? timeline}) =>
      IncidentDetail(
        incident: incident ?? this.incident,
        timeline: timeline ?? this.timeline,
        comments: comments ?? this.comments,
        deployments: deployments,
      );
}

/// Outcome of an action, for the UI to show (never throws to widgets).
sealed class ActionResult {
  const ActionResult();
}

class ActionOk extends ActionResult {
  const ActionOk();
}

class ActionStale extends ActionResult {
  const ActionStale(this.message);
  final String message;
}

class ActionFailed extends ActionResult {
  const ActionFailed(this.failure);
  final Failure failure;
}

class IncidentDetailController extends AsyncNotifier<IncidentDetail> {
  IncidentDetailController(this.incidentRef);

  /// Incident key (`INC-1024`) or UUID.
  final String incidentRef;

  OpsRepository get _repo => ref.read(opsRepositoryProvider);

  @override
  Future<IncidentDetail> build() async {
    final repo = ref.watch(opsRepositoryProvider);
    final (incident, timeline, comments, deployments) = await (
      repo.incident(incidentRef),
      repo.timeline(incidentRef),
      repo.comments(incidentRef),
      repo.correlated(incidentRef),
    ).wait;
    return IncidentDetail(incident: incident, timeline: timeline, comments: comments, deployments: deployments);
  }

  Future<ActionResult> act(IncidentAction action) async {
    final current = state.value;
    if (current == null) return const ActionFailed(UnknownFailure('Not loaded'));
    try {
      final updated = await _repo.act(current.incident, action);
      ref.read(incidentsProvider.notifier).upsert(updated);
      state = AsyncData(current.copyWith(incident: updated, timeline: await _repo.timeline(incidentRef)));
      return const ActionOk();
    } on ConflictFailure catch (f) {
      // Someone else changed it (version mismatch) or the action no longer applies
      // (e.g. already resolved). Reload and tell the user what happened.
      final fresh = await AsyncValue.guard(build);
      state = fresh;
      final now = fresh.value?.incident;
      if (now != null) ref.read(incidentsProvider.notifier).upsert(now);
      return ActionStale(
        f.code == 'conflict.version_mismatch'
            ? 'This incident was just updated by someone else. Showing the latest — check before acting again.'
            : '${f.message}. Showing the latest state.',
      );
    } on Failure catch (f) {
      return ActionFailed(f);
    }
  }

  /// Optimistic comment: shown immediately as pending; the client id makes retries safe.
  Future<ActionResult> comment(String body) async {
    final current = state.value;
    if (current == null || body.trim().isEmpty) return const ActionOk();
    final clientId = OrgApi.newClientId();
    final pending = IncidentComment(
      id: clientId,
      clientId: clientId,
      body: body.trim(),
      at: DateTime.now(),
      authorName: 'You',
      pending: true,
    );
    state = AsyncData(current.copyWith(comments: [...current.comments, pending]));
    try {
      final saved = await _repo.comment(incidentRef, body.trim(), clientId);
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(comments: [for (final c in latest.comments) c.clientId == clientId ? saved : c]),
      );
      return const ActionOk();
    } on Failure catch (f) {
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          comments: [
            for (final c in latest.comments)
              if (c.clientId != clientId) c,
          ],
        ),
      );
      return ActionFailed(f);
    }
  }
}

final incidentDetailProvider = AsyncNotifierProvider.autoDispose
    .family<IncidentDetailController, IncidentDetail, String>(IncidentDetailController.new, retry: (_, _) => null);

class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({required this.incidentRef, super.key});

  final String incidentRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(incidentDetailProvider(incidentRef));
    return Scaffold(
      appBar: AppBar(title: Text(value.value?.incident.key ?? incidentRef.toUpperCase())),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(incidentDetailProvider(incidentRef).future),
        child: AsyncView(
          value: value,
          onRetry: () => ref.invalidate(incidentDetailProvider(incidentRef)),
          data: (d) => _DetailBody(detail: d, incidentRef: incidentRef),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.detail, required this.incidentRef});

  final IncidentDetail detail;
  final String incidentRef;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  final _comment = TextEditingController();
  String? _busy;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  IncidentDetailController get _ctl => ref.read(incidentDetailProvider(widget.incidentRef).notifier);

  Future<void> _run(String label, IncidentAction action) async {
    setState(() => _busy = label);
    final result = await _ctl.act(action);
    if (!mounted) return;
    setState(() => _busy = null);
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case ActionOk():
        unawaited(HapticFeedback.mediumImpact());
      case ActionStale(:final message):
        messenger.showSnackBar(SnackBar(content: Text(message)));
      case ActionFailed(:final failure):
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _resolve() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve incident?'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Resolution note (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resolve')),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok ?? false) await _run('resolve', Resolve(note: text.isEmpty ? null : text));
  }

  Future<void> _sendComment() async {
    final text = _comment.text;
    if (text.trim().isEmpty) return;
    _comment.clear();
    final r = await _ctl.comment(text);
    if (r is ActionFailed && mounted) {
      _comment.text = text; // give the text back so nothing is lost
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Comment not sent: ${r.failure.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final i = d.incident;
    final t = Theme.of(context).textTheme;
    final p = context.dp;
    final session = ref.watch(sessionControllerProvider).value;
    final me = session is SignedIn ? session.me : null;
    final canAct = session is SignedIn && session.currentOrg?.role != OrgRole.viewer;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DpSpace.lg),
      children: [
        Row(
          children: [
            DpSeverityChip(i.severity),
            const SizedBox(width: DpSpace.sm),
            Text(
              i.status.label,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: i.status.isOpen ? p.fg : p.healthy),
            ),
            if (i.escalationLevel > 0) ...[
              const SizedBox(width: DpSpace.sm),
              Text('Escalated ×${i.escalationLevel}', style: t.bodySmall?.copyWith(color: p.degraded)),
            ],
            const Spacer(),
            if (i.isDemo) const DpDemoTag(),
          ],
        ),
        const SizedBox(height: DpSpace.sm),
        Text(i.title, style: t.headlineSmall),
        const SizedBox(height: DpSpace.xs),
        Text(
          [
            ?i.serviceName,
            'started ${timeAgo(i.startedAt)}',
            if (i.assigneeName != null) 'owner ${i.assigneeName}',
          ].join(' · '),
          style: t.bodySmall,
        ),
        if (i.summary != null) ...[const SizedBox(height: DpSpace.md), Text(i.summary!, style: t.bodyMedium)],
        if (i.resolutionNote != null) ...[
          const SizedBox(height: DpSpace.md),
          DpBanner(message: 'Resolution: ${i.resolutionNote}', tone: DpBannerTone.info),
        ],
        if (canAct) ...[
          const SizedBox(height: DpSpace.lg),
          Wrap(
            spacing: DpSpace.sm,
            runSpacing: DpSpace.sm,
            children: [
              if (i.status == IncidentStatus.triggered)
                DpButton(
                  label: 'Acknowledge',
                  icon: Icons.front_hand_outlined,
                  loading: _busy == 'ack',
                  onPressed: _busy == null ? () => _run('ack', const Acknowledge()) : null,
                ),
              if (i.status.isOpen)
                DpButton(
                  label: 'Resolve',
                  icon: Icons.check,
                  variant: i.status == IncidentStatus.triggered ? DpButtonVariant.secondary : DpButtonVariant.primary,
                  loading: _busy == 'resolve',
                  onPressed: _busy == null ? _resolve : null,
                ),
              if (i.status.isOpen && me != null && i.assigneeId != me.id)
                DpButton(
                  label: 'Assign to me',
                  variant: DpButtonVariant.secondary,
                  loading: _busy == 'assign',
                  onPressed: _busy == null ? () => _run('assign', AssignTo(me.id)) : null,
                ),
              if (i.status.isOpen)
                DpButton(
                  label: 'Escalate',
                  variant: DpButtonVariant.ghost,
                  loading: _busy == 'escalate',
                  onPressed: _busy == null ? () => _run('escalate', const Escalate()) : null,
                ),
              if (!i.status.isOpen)
                DpButton(
                  label: 'Reopen',
                  variant: DpButtonVariant.secondary,
                  loading: _busy == 'reopen',
                  onPressed: _busy == null ? () => _run('reopen', const Reopen()) : null,
                ),
            ],
          ),
        ],
        if (d.deployments.isNotEmpty) ...[
          const SectionHeader('Possibly related deployments'),
          Card(
            child: Column(
              children: [
                for (final (idx, dep) in d.deployments.indexed) ...[
                  if (idx > 0) const Divider(),
                  ListTile(
                    leading: Icon(Icons.rocket_launch_outlined, color: p.violet),
                    title: Text(dep.version),
                    subtitle: Text(
                      [
                        timeAgo(dep.startedAt),
                        dep.status,
                        if (dep.commitMessage != null) dep.commitMessage!.split('\n').first,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Semantics(
                      label: 'Correlation ${(dep.score * 100).round()} percent, ${dep.correlation}',
                      excludeSemantics: true,
                      child: Text('${(dep.score * 100).round()}%', style: t.titleSmall),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(DpSpace.lg, 0, DpSpace.lg, DpSpace.md),
                  child: Text('Suspected from timing only — not a confirmed cause.', style: t.bodySmall),
                ),
              ],
            ),
          ),
        ],
        const SectionHeader('Timeline'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DpSpace.sm),
            child: Column(
              children: [
                for (final e in d.timeline)
                  ListTile(
                    dense: true,
                    leading: Icon(switch (e.actorType) {
                      'system' => Icons.memory,
                      'ai' => Icons.auto_awesome,
                      _ => Icons.person_outline,
                    }, size: 18),
                    title: Text(e.describe()),
                    trailing: Text(timeAgo(e.at), style: t.bodySmall),
                  ),
              ],
            ),
          ),
        ),
        const SectionHeader('Comments'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (d.comments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(DpSpace.lg),
                  child: Text('No comments yet.', style: t.bodySmall),
                ),
              for (final c in d.comments)
                ListTile(
                  title: Text(c.body),
                  subtitle: Text(
                    '${c.authorName ?? 'Unknown'} · ${c.pending ? 'sending…' : timeAgo(c.at)}',
                    style: t.bodySmall,
                  ),
                  trailing: c.pending
                      ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                      : null,
                ),
              if (canAct)
                Padding(
                  padding: const EdgeInsets.all(DpSpace.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _comment,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendComment(),
                          decoration: const InputDecoration(hintText: 'Add a comment'),
                        ),
                      ),
                      IconButton(onPressed: _sendComment, icon: const Icon(Icons.send), tooltip: 'Send comment'),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: DpSpace.xxl),
      ],
    );
  }
}
