import '../../../core/design_system/widgets/status_widgets.dart';
import '../../deployments/domain/deployment.dart';
import '../../incidents/domain/incident.dart';

enum OverviewWindow {
  // Steps match the API's request-series buckets for each window.
  hour('1h', Duration(minutes: 1)),
  day('24h', Duration(minutes: 30)),
  week('7d', Duration(hours: 6));

  const OverviewWindow(this.label, this.step);
  final String label;
  final Duration step;
}

class Overview {
  const Overview({
    required this.servicesTotal,
    required this.byHealth,
    required this.openBySeverity,
    required this.requests,
    required this.errorRate,
    required this.latencyAvgMs,
    required this.latencyP95Ms,
    required this.requestSeries,
    required this.recentIncidents,
    required this.recentDeployments,
    required this.hasTelemetry,
  });

  factory Overview.fromJson(Map<String, dynamic> j, {Duration step = Duration.zero}) {
    final totals = j['totals'] as Map<String, dynamic>;
    double? n(Object? v) => (v as num?)?.toDouble();
    return Overview(
      servicesTotal: j['services_total'] as int,
      byHealth: {
        for (final e in (j['services_by_health'] as Map<String, dynamic>).entries) Health.parse(e.key): e.value as int,
      },
      openBySeverity: {
        for (final e in (j['open_incidents_by_severity'] as Map<String, dynamic>).entries)
          Severity.parse(e.key): e.value as int,
      },
      requests: n(totals['requests']),
      errorRate: n(totals['error_rate']),
      latencyAvgMs: n(totals['latency_avg_ms']),
      latencyP95Ms: n(totals['latency_p95_ms']),
      requestSeries: fillGaps([
        for (final p in j['request_series'] as List<dynamic>)
          (DateTime.parse((p as List<dynamic>)[0] as String).toLocal(), n(p[1])),
      ], step),
      recentIncidents: [
        for (final i in j['recent_incidents'] as List<dynamic>) Incident.fromJson(i as Map<String, dynamic>),
      ],
      recentDeployments: [
        for (final d in j['recent_deployments'] as List<dynamic>) Deployment.fromJson(d as Map<String, dynamic>),
      ],
      hasTelemetry: j['has_telemetry'] as bool,
    );
  }

  final int servicesTotal;
  final Map<Health, int> byHealth;
  final Map<Severity, int> openBySeverity;
  final double? requests;
  final double? errorRate;
  final double? latencyAvgMs;
  final double? latencyP95Ms;
  final List<(DateTime, double?)> requestSeries;
  final List<Incident> recentIncidents;
  final List<Deployment> recentDeployments;
  final bool hasTelemetry;

  int get openIncidents => openBySeverity.values.fold(0, (a, b) => a + b);
}
