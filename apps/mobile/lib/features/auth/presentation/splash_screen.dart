import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/result/failure.dart';
import '../../../l10n/l10n.dart';
import 'session_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(DpSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DpLogo(size: 20),
                const SizedBox(height: DpSpace.xl),
                if (session.hasError && !session.isLoading) ...[
                  Text(
                    Failure.from(session.error!).message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: DpSpace.lg),
                  DpButton(
                    label: context.l10n.tryAgain,
                    variant: DpButtonVariant.secondary,
                    onPressed: () => ref.read(sessionControllerProvider.notifier).retry(),
                  ),
                ] else
                  SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: context.l10n.restoringSession),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
