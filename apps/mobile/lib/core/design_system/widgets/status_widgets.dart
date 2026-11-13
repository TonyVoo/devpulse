import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../tokens.dart';

enum Health {
  healthy,
  degraded,
  critical,
  unknown;

  static Health parse(String? v) => Health.values.firstWhere((h) => h.name == v, orElse: () => Health.unknown);

  String get label => switch (this) {
    healthy => l10n.healthHealthy,
    degraded => l10n.healthDegraded,
    critical => l10n.healthCritical,
    unknown => l10n.healthUnknown,
  };
}

enum Severity {
  sev1,
  sev2,
  sev3,
  sev4;

  static Severity parse(String? v) => Severity.values.firstWhere((s) => s.name == v, orElse: () => Severity.sev4);

  String get label => 'SEV${index + 1}';
}

Color healthColor(BuildContext context, Health h) {
  final p = context.dp;
  return switch (h) {
    Health.healthy => p.healthy,
    Health.degraded => p.degraded,
    Health.critical => p.critical,
    Health.unknown => p.unknown,
  };
}

Color severityColor(BuildContext context, Severity s) {
  final p = context.dp;
  return switch (s) {
    Severity.sev1 => p.critical,
    Severity.sev2 => const Color(0xFFFB923C),
    Severity.sev3 => p.degraded,
    Severity.sev4 => p.unknown,
  };
}

/// Health is never colour-only: dot + label (colour-blind safe).
class DpHealthPill extends StatelessWidget {
  const DpHealthPill(this.health, {super.key, this.compact = false});

  final Health health;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = healthColor(context, health);
    final icon = switch (health) {
      Health.healthy => Icons.check_circle,
      Health.degraded => Icons.error,
      Health.critical => Icons.cancel,
      Health.unknown => Icons.help,
    };
    return Semantics(
      label: context.l10n.healthSemantics(health.label),
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(DpRadius.sm)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                health.label,
                style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DpSeverityChip extends StatelessWidget {
  const DpSeverityChip(this.severity, {super.key});

  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final c = severityColor(context, severity);
    return Semantics(
      label: context.l10n.severitySemantics(severity.index + 1),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: c.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(DpRadius.sm),
        ),
        child: Text(
          severity.label,
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

/// Marks data that came from the demo seed / load generator.
class DpDemoTag extends StatelessWidget {
  const DpDemoTag({super.key});

  @override
  Widget build(BuildContext context) {
    final v = context.dp.violet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: v.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
      child: Text(
        context.l10n.demo,
        style: TextStyle(color: v, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    );
  }
}

class DpMetricTile extends StatelessWidget {
  const DpMetricTile({required this.label, required this.value, this.caption, this.tone, super.key});

  final String label;
  final String value;
  final String? caption;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value${caption != null ? ', $caption' : ''}',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(DpSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.labelSmall),
              const SizedBox(height: DpSpace.xs),
              Text(
                value,
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tone,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (caption != null) Text(caption!, style: t.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Time-series line. `null` values are gaps (no data), never drawn as zero.
class DpLineChart extends StatelessWidget {
  const DpLineChart({
    required this.points,
    required this.semanticLabel,
    this.color,
    this.height = 140,
    this.threshold,
    this.formatY,
    super.key,
  });

  final List<(DateTime, double?)> points;
  final String semanticLabel;
  final Color? color;
  final double height;
  final double? threshold;
  final String Function(double)? formatY;

  @override
  Widget build(BuildContext context) {
    final p = context.dp;
    final c = color ?? p.cyan;
    if (points.every((e) => e.$2 == null)) {
      return SizedBox(
        height: height,
        child: Center(child: Text(context.l10n.noDataInRange, style: Theme.of(context).textTheme.bodySmall)),
      );
    }
    final spots = [
      for (final (t, v) in points) v == null ? FlSpot.nullSpot : FlSpot(t.millisecondsSinceEpoch.toDouble(), v),
    ];
    final values = points.map((e) => e.$2).whereType<double>();
    final isolated = <double>{
      for (var i = 0; i < points.length; i++)
        if (points[i].$2 != null &&
            (i == 0 || points[i - 1].$2 == null) &&
            (i == points.length - 1 || points[i + 1].$2 == null))
          points[i].$1.millisecondsSinceEpoch.toDouble(),
    };
    final maxY = [...values, ?threshold].reduce((a, b) => a > b ? a : b);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          duration: context.reduceMotion ? Duration.zero : DpMotion.base,
          LineChartData(
            minY: 0,
            maxY: maxY <= 0 ? 1 : maxY * 1.15,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: p.line, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  getTitlesWidget: (v, meta) {
                    // fl_chart also labels the axis max; skip it unless it sits on a grid
                    // line, otherwise it overlaps the nearest interval label.
                    final onGrid = (v / meta.appliedInterval - (v / meta.appliedInterval).round()).abs() < 1e-6;
                    if (v == meta.max && !onGrid) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        formatY?.call(v) ?? compactNumber(v),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(fontSize: 10, color: p.fgSubtle),
                      ),
                    );
                  },
                ),
              ),
            ),
            extraLinesData: threshold == null
                ? null
                : ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(y: threshold!, color: p.critical.withValues(alpha: 0.7), dashArray: [4, 4]),
                    ],
                  ),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: c,
                barWidth: 2,
                isCurved: false,
                // A point with no drawable neighbour (surrounded by gaps) would be invisible
                // as a line; draw it as a dot so isolated data is never lost.
                dotData: FlDotData(
                  checkToShowDot: (spot, _) => isolated.contains(spot.x),
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3, color: c, strokeWidth: 0),
                ),
                belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.10)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed decimals with the app language's separator (1.5 / 1,5).
String _fixed(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return l10n.localeName.startsWith('vi') ? s.replaceAll('.', ',') : s;
}

String compactNumber(double v) {
  final a = v.abs();
  if (a >= 1e9) return '${_fixed(v / 1e9, 1)}B';
  if (a >= 1e6) return '${_fixed(v / 1e6, 1)}M';
  if (a >= 1e3) return '${_fixed(v / 1e3, 1)}k';
  if (a >= 10 || v == v.roundToDouble()) return v.toStringAsFixed(0);
  return _fixed(v, 2);
}

String percent(double? v) => v == null ? '—' : '${_fixed(v * 100, v < 0.01 ? 2 : 1)}%';

String millis(double? v) => v == null ? '—' : (v >= 1000 ? '${_fixed(v / 1000, 2)} s' : '${v.round()} ms');

String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 60) return l10n.justNow;
  if (d.inMinutes < 60) return l10n.minutesAgo(d.inMinutes);
  if (d.inHours < 24) return l10n.hoursAgo(d.inHours);
  return l10n.daysAgo(d.inDays);
}

/// The API omits buckets without data. Insert explicit `null`s wherever consecutive points
/// are more than 1.5 steps apart so charts break the line instead of drawing a straight
/// segment across a period with no data.
List<(DateTime, double?)> fillGaps(List<(DateTime, double?)> points, Duration step) {
  if (points.length < 2 || step == Duration.zero) return points;
  final out = <(DateTime, double?)>[points.first];
  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1].$1;
    final cur = points[i].$1;
    if (cur.difference(prev) > step * 1.5) out.add((prev.add(step), null));
    out.add(points[i]);
  }
  return out;
}
