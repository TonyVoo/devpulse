import 'package:flutter/foundation.dart';

import '../../../core/design_system/widgets/status_widgets.dart';

@immutable
class MonitoredService {
  const MonitoredService({
    required this.id,
    required this.slug,
    required this.name,
    required this.environment,
    required this.tier,
    required this.health,
    required this.lastSeenAt,
    required this.isDemo,
    required this.version,
    this.description,
    this.ownerTeam,
  });

  factory MonitoredService.fromJson(Map<String, dynamic> j) => MonitoredService(
    id: j['id'] as String,
    slug: j['slug'] as String,
    name: j['name'] as String,
    environment: j['environment'] as String,
    tier: j['tier'] as String,
    health: Health.parse(j['health'] as String?),
    lastSeenAt: j['last_seen_at'] == null ? null : DateTime.parse(j['last_seen_at'] as String),
    isDemo: j['is_demo'] as bool? ?? false,
    version: j['version'] as int,
    description: j['description'] as String?,
    ownerTeam: j['owner_team'] as String?,
  );

  final String id;
  final String slug;
  final String name;
  final String environment;
  final String tier;
  final Health health;
  final DateTime? lastSeenAt;
  final bool isDemo;
  final int version;
  final String? description;
  final String? ownerTeam;
}

/// One metric series; `null` values are gaps.
class MetricSeries {
  const MetricSeries(this.name, this.aggregation, this.points);

  factory MetricSeries.fromJson(Map<String, dynamic> j, {Duration step = Duration.zero}) => MetricSeries(
    j['name'] as String,
    j['aggregation'] as String,
    fillGaps([
      for (final p in j['points'] as List<dynamic>)
        (DateTime.parse((p as List<dynamic>)[0] as String).toLocal(), (p[1] as num?)?.toDouble()),
    ], step),
  );

  final String name;
  final String aggregation;
  final List<(DateTime, double?)> points;

  double? get latest {
    for (final p in points.reversed) {
      if (p.$2 != null) return p.$2;
    }
    return null;
  }
}

enum MetricRange {
  hour('1h', Duration(hours: 1)),
  sixHours('6h', Duration(hours: 6)),
  day('24h', Duration(hours: 24)),
  week('7d', Duration(days: 7));

  const MetricRange(this.label, this.span);

  final String label;
  final Duration span;
}
