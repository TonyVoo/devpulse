import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/result/failure.dart';
import '../../auth/domain/models.dart';
import '../../auth/presentation/session_controller.dart';
import '../../offline/live_sync.dart';
import '../../offline/outbox.dart';
import '../../ops_repositories.dart';
import '../domain/incident.dart';

/// The incident itself comes from the local cache (works offline, updates live). If it isn't
/// cached yet (deep link to an old incident), it is fetched once and cached.
final incidentStreamProvider = StreamProvider.autoDispose.family<Incident?, String>((ref, incidentRef) {
  final live = ref.watch(liveSyncProvider);
  if (live == null) return Stream.value(null);
  final repo = ref.watch(opsRepositoryProvider);
  return live.store.watchIncident(incidentRef).asyncMap((cached) async {
    if (cached != null) return cached;
    final fetched = await repo.incident(incidentRef); // not cached yet: fetch once…
    await live.store.cacheIfMissing(fetched); // …the cache stream then takes over
    return fetched;
  });
});

class IncidentExtras {
  const IncidentExtras({required this.timeline, required this.comments, required this.deployments, this.stale = false});

  final List<TimelineEvent> timeline;
  final List<IncidentComment> comments;
  final List<CorrelatedDeployment> deployments;
  final bool stale;
}

/// Timeline, comments and suspected deployments: network first, with the last copy kept on
/// the device so an incident opened offline still shows its history. Refreshed when the
/// realtime channel reports a new timeline event for this incident.
final incidentExtrasProvider = FutureProvider.autoDispose.family<IncidentExtras, String>((ref, incidentId) async {
  final live = ref.watch(liveSyncProvider);
  if (live != null) {
    final sub = live.incidentEvents.where((id) => id == incidentId).listen((_) => ref.invalidateSelf());
    ref.onDispose(sub.cancel);
  }
  final repo = ref.watch(opsRepositoryProvider);
  final db = ref.watch(databaseProvider);
  try {
    final results = await Future.wait<Object>([
      repo.timeline(incidentId),
      repo.comments(incidentId),
      repo.correlated(incidentId),
    ], eagerError: true);
    final t = results[0] as List<TimelineEvent>;
    final c = results[1] as List<IncidentComment>;
    final d = results[2] as List<CorrelatedDeployment>;
    await db.writeJson(KvKeys.incidentExtras(incidentId), {
      'timeline': [for (final e in t) e.toJson()],
      'comments': [for (final x in c) x.toJson()],
      'deployments': [for (final x in d) x.toJson()],
    });
    return IncidentExtras(timeline: t, comments: c, deployments: d);
  } on Object catch (e) {
    final cached = await db.readJson(KvKeys.incidentExtras(incidentId));
    if (cached == null) throw Failure.from(e);
    return IncidentExtras(
      stale: true,
      timeline: [
        for (final j in cached['timeline'] as List<dynamic>) TimelineEvent.fromJson(j as Map<String, dynamic>),
      ],
      comments: [
        for (final j in cached['comments'] as List<dynamic>) IncidentComment.fromJson(j as Map<String, dynamic>),
      ],
      deployments: [
        for (final j in cached['deployments'] as List<dynamic>)
          CorrelatedDeployment.fromJson(j as Map<String, dynamic>),
      ],
    );
  }
}, retry: (_, _) => null);

final pendingCommentsProvider = StreamProvider.autoDispose.family<List<PendingComment>, String>((ref, incidentId) {
  final live = ref.watch(liveSyncProvider);
  return live == null ? Stream.value(const []) : live.outbox.watchPendingComments(incidentId);
});

class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({required this.incidentRef, super.key});

  final String incidentRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(incidentStreamProvider(incidentRef));
    final incident = value.value;
    return Scaffold(
      appBar: AppBar(title: Text(incident?.key ?? incidentRef.toUpperCase())),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(liveSyncProvider)?.refresh();
          if (incident != null) ref.invalidate(incidentExtrasProvider(incident.id));
        },
        child: AsyncView<Incident?>(
          value: value,
          onRetry: () => ref.invalidate(incidentStreamProvider(incidentRef)),
          data: (i) => i == null
              ? const DpEmptyState(
                  icon: Icons.search_off,
                  title: 'Incident not found',
                  description: 'It may belong to another organization.',
                )
              : _DetailBody(incident: i),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.incident});

  final Incident incident;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Queued in the outbox: applied on screen immediately, sent now or when back online.
  Future<void> _act(IncidentAction action) async {
    final live = ref.read(liveSyncProvider);
    if (live == null) return;
    await live.outbox.enqueueAction(widget.incident, action.path, action.body);
    unawaited(HapticFeedback.mediumImpact());
    if (!live.isOnline && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're offline. The change is saved and will be sent automatically.")),
      );
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
    if (ok ?? false) await _act(Resolve(note: text.isEmpty ? null : text));
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    final live = ref.read(liveSyncProvider);
    if (text.isEmpty || live == null) return;
    _comment.clear();
    await live.outbox.enqueueComment(widget.incident.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incident;
    final t = Theme.of(context).textTheme;
    final p = context.dp;
    final session = ref.watch(sessionControllerProvider).value;
    final me = session is SignedIn ? session.me : null;
    final canAct = session is SignedIn && session.currentOrg?.role != OrgRole.viewer;
    final extras = ref.watch(incidentExtrasProvider(i.id));
    final pending = ref.watch(pendingCommentsProvider(i.id)).value ?? const [];
    final busy = i.isPending;

    final serverComments = extras.value?.comments ?? const <IncidentComment>[];
    final serverIds = {for (final c in serverComments) c.clientId};
    final comments = [
      ...serverComments,
      for (final c in pending)
        if (!serverIds.contains(c.clientId))
          IncidentComment(
            id: c.clientId,
            clientId: c.clientId,
            body: c.body,
            at: c.createdAt,
            authorName: 'You',
            pending: true,
          ),
    ];

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
        if (busy) ...[
          const SizedBox(height: DpSpace.sm),
          DpBanner(message: 'Your "${i.pendingAction}" is waiting to be sent.', tone: DpBannerTone.warning),
        ],
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
                  onPressed: busy ? null : () => _act(const Acknowledge()),
                ),
              if (i.status.isOpen)
                DpButton(
                  label: 'Resolve',
                  icon: Icons.check,
                  variant: i.status == IncidentStatus.triggered ? DpButtonVariant.secondary : DpButtonVariant.primary,
                  onPressed: busy ? null : _resolve,
                ),
              if (i.status.isOpen && me != null && i.assigneeId != me.id)
                DpButton(
                  label: 'Assign to me',
                  variant: DpButtonVariant.secondary,
                  onPressed: busy ? null : () => _act(AssignTo(me.id)),
                ),
              if (i.status.isOpen)
                DpButton(
                  label: 'Escalate',
                  variant: DpButtonVariant.ghost,
                  onPressed: busy ? null : () => _act(const Escalate()),
                ),
              if (!i.status.isOpen)
                DpButton(
                  label: 'Reopen',
                  variant: DpButtonVariant.secondary,
                  onPressed: busy ? null : () => _act(const Reopen()),
                ),
            ],
          ),
        ],
        if (extras.value?.stale ?? false) ...[
          const SizedBox(height: DpSpace.md),
          const DpBanner(message: 'Showing the timeline saved on this device.', tone: DpBannerTone.warning),
        ],
        if ((extras.value?.deployments ?? const []).isNotEmpty) ...[
          const SectionHeader('Possibly related deployments'),
          Card(
            child: Column(
              children: [
                for (final (idx, dep) in extras.value!.deployments.indexed) ...[
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
            child: extras.isLoading && extras.value == null
                ? const Padding(
                    padding: EdgeInsets.all(DpSpace.lg),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : extras.hasError && extras.value == null
                ? ListTile(
                    title: Text("Couldn't load the timeline", style: t.bodySmall),
                    trailing: TextButton(
                      onPressed: () => ref.invalidate(incidentExtrasProvider(i.id)),
                      child: const Text('Retry'),
                    ),
                  )
                : Column(
                    children: [
                      for (final e in extras.value?.timeline ?? const <TimelineEvent>[])
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
              if (comments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(DpSpace.lg),
                  child: Text('No comments yet.', style: t.bodySmall),
                ),
              for (final c in comments)
                ListTile(
                  title: Text(c.body),
                  subtitle: Text(
                    '${c.authorName ?? 'Unknown'} · ${c.pending ? 'waiting to send' : timeAgo(c.at)}',
                    style: t.bodySmall,
                  ),
                  trailing: c.pending ? Icon(Icons.schedule, size: 16, color: p.degraded) : null,
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
