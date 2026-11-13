import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../result/failure.dart';
import '../tokens.dart';
import 'dp_widgets.dart';

/// Renders an [AsyncValue] with the design-system states:
/// first load → skeleton · error without data → error state with Retry ·
/// error WITH previous data → keep showing data plus a banner (never blank the screen).
class AsyncView<T> extends StatelessWidget {
  const AsyncView({required this.value, required this.data, required this.onRetry, this.skeleton, super.key});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    final current = value.value;
    if (current != null) {
      if (value.hasError && !value.isLoading) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DpSpace.lg, DpSpace.sm, DpSpace.lg, 0),
              child: DpBanner(
                message: Failure.from(value.error!).message,
                tone: Failure.from(value.error!) is NetworkFailure ? DpBannerTone.warning : DpBannerTone.error,
                action: TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
              ),
            ),
            Expanded(child: data(current)),
          ],
        );
      }
      return data(current);
    }
    if (value.hasError) {
      final f = Failure.from(value.error!);
      return DpEmptyState(
        icon: f is NetworkFailure ? Icons.cloud_off_outlined : Icons.error_outline,
        title: f is NetworkFailure ? context.l10n.youreOffline : context.l10n.couldNotLoadThis,
        description: f.requestId == null ? f.message : '${f.message}\n${context.l10n.requestRef(f.requestId!)}',
        action: DpButton(label: context.l10n.tryAgain, variant: DpButtonVariant.secondary, onPressed: onRetry),
      );
    }
    return skeleton ?? const SkeletonList();
  }
}

/// Placeholder rows shaped like list items (first load only). Static under reduce-motion.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 6, this.rowHeight = 64});

  final int rows;
  final double rowHeight;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    return Semantics(
      label: context.l10n.loading,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DpSpace.lg),
          itemCount: widget.rows,
          itemBuilder: (_, _) => Container(
            height: widget.rowHeight,
            margin: const EdgeInsets.only(bottom: DpSpace.sm),
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(DpRadius.md)),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(DpSpace.xs, DpSpace.lg, 0, DpSpace.sm),
    child: Row(
      children: [
        Expanded(child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
        ?action,
      ],
    ),
  );
}
