import 'package:flutter/material.dart';

/// DevPulse design tokens. Values mirror docs/DESIGN_SYSTEM.md and apps/web globals.css.
@immutable
class DpPalette extends ThemeExtension<DpPalette> {
  const DpPalette({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.line,
    required this.fg,
    required this.fgMuted,
    required this.fgSubtle,
    required this.cyan,
    required this.violet,
    required this.onAccent,
    required this.healthy,
    required this.degraded,
    required this.critical,
    required this.unknown,
  });

  static const dark = DpPalette(
    canvas: Color(0xFF0A0E1A),
    surface: Color(0xFF111726),
    raised: Color(0xFF182033),
    line: Color(0xFF232C42),
    fg: Color(0xFFE8ECF5),
    fgMuted: Color(0xFF9AA5BE),
    fgSubtle: Color(0xFF6B7691),
    cyan: Color(0xFF22D3EE),
    violet: Color(0xFF8B5CF6),
    onAccent: Color(0xFF04121A),
    healthy: Color(0xFF34D399),
    degraded: Color(0xFFFBBF24),
    critical: Color(0xFFF43F5E),
    unknown: Color(0xFF64748B),
  );

  static const light = DpPalette(
    canvas: Color(0xFFF7F8FB),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEEF1F6),
    line: Color(0xFFE3E7EF),
    fg: Color(0xFF0E1424),
    fgMuted: Color(0xFF4A5470),
    fgSubtle: Color(0xFF6B7590),
    cyan: Color(0xFF0891B2),
    violet: Color(0xFF7C3AED),
    onAccent: Color(0xFFFFFFFF),
    healthy: Color(0xFF059669),
    degraded: Color(0xFFB45309),
    critical: Color(0xFFBE123C),
    unknown: Color(0xFF64748B),
  );

  final Color canvas, surface, raised, line;
  final Color fg, fgMuted, fgSubtle;
  final Color cyan, violet, onAccent;
  final Color healthy, degraded, critical, unknown;

  @override
  DpPalette copyWith({Color? canvas, Color? surface}) => DpPalette(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    raised: raised,
    line: line,
    fg: fg,
    fgMuted: fgMuted,
    fgSubtle: fgSubtle,
    cyan: cyan,
    violet: violet,
    onAccent: onAccent,
    healthy: healthy,
    degraded: degraded,
    critical: critical,
    unknown: unknown,
  );

  @override
  DpPalette lerp(DpPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DpPalette(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      line: l(line, other.line),
      fg: l(fg, other.fg),
      fgMuted: l(fgMuted, other.fgMuted),
      fgSubtle: l(fgSubtle, other.fgSubtle),
      cyan: l(cyan, other.cyan),
      violet: l(violet, other.violet),
      onAccent: l(onAccent, other.onAccent),
      healthy: l(healthy, other.healthy),
      degraded: l(degraded, other.degraded),
      critical: l(critical, other.critical),
      unknown: l(unknown, other.unknown),
    );
  }
}

/// 4-pt spacing scale.
abstract final class DpSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class DpRadius {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

abstract final class DpMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

extension DpContext on BuildContext {
  DpPalette get dp => Theme.of(this).extension<DpPalette>()!;

  /// Honour the OS "reduce motion" setting.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
