import 'package:flutter/material.dart';

import '../tokens.dart';

enum DpButtonVariant { primary, secondary, ghost }

/// Button with a built-in loading state. Keeps its size while loading to avoid layout jumps.
class DpButton extends StatelessWidget {
  const DpButton({
    required this.label,
    required this.onPressed,
    this.variant = DpButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final DpButtonVariant variant;
  final bool loading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final onTap = loading ? null : onPressed;
    final child = loading
        ? Semantics(
            label: '$label, in progress',
            child: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: DpSpace.sm)],
              Text(label),
            ],
          );
    final button = switch (variant) {
      DpButtonVariant.primary => FilledButton(onPressed: onTap, child: child),
      DpButtonVariant.secondary => OutlinedButton(onPressed: onTap, child: child),
      DpButtonVariant.ghost => TextButton(onPressed: onTap, child: child),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Labelled text field. Field errors come from the API's validation response.
class DpTextField extends StatelessWidget {
  const DpTextField({
    required this.label,
    required this.controller,
    this.errorText,
    this.helperText,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? helperText;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: !obscure,
      enableSuggestions: !obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(labelText: label, errorText: errorText, helperText: helperText),
    );
  }
}

enum DpBannerTone { info, warning, error }

/// Inline status banner (offline, stale data, errors). Announced politely to screen readers.
class DpBanner extends StatelessWidget {
  const DpBanner({required this.message, this.tone = DpBannerTone.info, this.action, super.key});

  final String message;
  final DpBannerTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final (color, icon) = switch (tone) {
      DpBannerTone.info => (p.cyan, Icons.info_outline),
      DpBannerTone.warning => (p.degraded, Icons.cloud_off_outlined),
      DpBannerTone.error => (p.critical, Icons.error_outline),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: DpSpace.md, vertical: DpSpace.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.40)),
          borderRadius: BorderRadius.circular(DpRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: DpSpace.sm),
            Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.fg)),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Specific, actionable empty state (never a bare "No data").
class DpEmptyState extends StatelessWidget {
  const DpEmptyState({required this.icon, required this.title, required this.description, this.action, super.key});

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DpSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(DpSpace.lg),
                decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle),
                child: Icon(icon, size: 28, color: p.fgMuted),
              ),
              const SizedBox(height: DpSpace.lg),
              Text(title, style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: DpSpace.sm),
              Text(description, style: t.bodySmall, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: DpSpace.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Wordmark used on auth and splash screens.
class DpLogo extends StatelessWidget {
  const DpLogo({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final style = TextStyle(fontSize: size, letterSpacing: size * 0.3, fontWeight: FontWeight.w600, color: p.fgMuted);
    return Semantics(
      label: 'DevPulse',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: 'DEV',
          style: style,
          children: [
            TextSpan(
              text: 'PULSE',
              style: style.copyWith(color: p.cyan),
            ),
          ],
        ),
      ),
    );
  }
}
