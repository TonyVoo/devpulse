import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/async_view.dart';
import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../core/network/org_api.dart';
import '../../../core/result/failure.dart';
import '../../../l10n/l10n.dart';
import '../../offline/live_sync.dart';
import '../data/ai_repository.dart';
import '../domain/investigation.dart';
import 'ai_widgets.dart';

/// Follow-up questions about one investigation. The model may look things up with read-only
/// tools; whatever it finds becomes new evidence (EV-n) that answers cite.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({required this.incidentRef, required this.investigationId, super.key});

  final String incidentRef;
  final String investigationId;

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _pendingQuestion;
  String? _pendingClientId;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _pendingQuestion != null) return;
    // Same client id on retry → the server returns the stored answer instead of re-asking.
    final clientId = _pendingClientId ?? OrgApi.newClientId();
    setState(() {
      _pendingQuestion = q;
      _pendingClientId = clientId;
      _error = null;
    });
    try {
      await ref.read(aiRepositoryProvider).ask(widget.investigationId, q, clientId);
      _input.clear();
      _pendingClientId = null;
      ref
        ..invalidate(aiMessagesProvider(widget.investigationId))
        ..invalidate(investigationProvider(widget.investigationId));
    } on Failure catch (f) {
      setState(() => _error = aiErrorMessage(f.code, detail: f.message));
      if (f.code != null) _pendingClientId = null; // the server answered: a new id next time
    } finally {
      if (mounted) setState(() => _pendingQuestion = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(investigationProvider(widget.investigationId));
    final messages = ref.watch(aiMessagesProvider(widget.investigationId));
    final online = ref.watch(onlineProvider).value ?? true;
    final t = Theme.of(context).textTheme;
    final p = context.dp;
    final evidence = inv.value;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.askCopilot),
            Text(widget.incidentRef.toUpperCase(), style: t.bodySmall),
          ],
        ),
      ),
      body: Column(
        children: [
          if (evidence?.summary.isDemoProvider ?? false)
            const Padding(
              padding: EdgeInsets.only(top: DpSpace.sm),
              child: DemoAnalyzerTag(),
            ),
          Expanded(
            child: AsyncView<List<AiMessage>>(
              value: messages,
              onRetry: () => ref.invalidate(aiMessagesProvider(widget.investigationId)),
              data: (list) {
                final visible = [
                  for (final m in list)
                    if (m.role != 'tool' || m.evidenceRefs.isNotEmpty) m,
                ];
                if (visible.isEmpty && _pendingQuestion == null) {
                  return ListView(
                    padding: const EdgeInsets.all(DpSpace.xl),
                    children: [
                      Text(
                        context.l10n.askHint,
                        style: t.bodyMedium?.copyWith(color: p.fgMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                }
                return ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(DpSpace.lg),
                  children: [
                    for (final m in visible) _bubble(m, evidence, t),
                    if (_pendingQuestion != null) ...[
                      _userBubble(_pendingQuestion!, t),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: DpSpace.md),
                        child: Row(
                          children: [
                            const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: DpSpace.sm),
                            Text(context.l10n.lookingIntoIt, style: t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DpSpace.lg),
              child: Text(_error!, style: t.bodySmall?.copyWith(color: p.critical)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(DpSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: online,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: online ? context.l10n.questionHint : context.l10n.needsConnection,
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: online && _pendingQuestion == null ? _send : null,
                    icon: const Icon(Icons.send),
                    tooltip: context.l10n.sendQuestion,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userBubble(String text, TextTheme t) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: DpSpace.xs),
      padding: const EdgeInsets.all(DpSpace.md),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: context.dp.cyan.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DpRadius.md),
      ),
      child: Text(text, style: t.bodyMedium),
    ),
  );

  Widget _bubble(AiMessage m, Investigation? inv, TextTheme t) {
    if (m.role == 'user') return _userBubble(m.content, t);
    if (m.role == 'tool') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DpSpace.xs),
        child: Text(
          context.l10n.lookedUp(m.toolName?.replaceAll('_', ' ') ?? '', m.evidenceRefs.join(', ')),
          style: t.bodySmall,
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: DpSpace.xs),
      padding: const EdgeInsets.all(DpSpace.md),
      decoration: BoxDecoration(color: context.dp.raised, borderRadius: BorderRadius.circular(DpRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(m.content, style: t.bodyMedium),
          if (m.evidenceRefs.isNotEmpty)
            Wrap(
              spacing: DpSpace.xs,
              children: [for (final r in m.evidenceRefs) EvidenceChip(evidenceRef: r, evidence: inv?.evidenceFor(r))],
            ),
          Text(timeAgo(m.at), style: t.bodySmall),
        ],
      ),
    );
  }
}
