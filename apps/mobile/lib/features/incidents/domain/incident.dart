import 'package:flutter/foundation.dart';

import '../../../core/design_system/widgets/status_widgets.dart';

enum IncidentStatus {
  triggered,
  acknowledged,
  resolved;

  static IncidentStatus parse(String v) =>
      IncidentStatus.values.firstWhere((s) => s.name == v, orElse: () => IncidentStatus.triggered);

  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
  bool get isOpen => this != IncidentStatus.resolved;
}

@immutable
class Incident {
  const Incident({
    required this.id,
    required this.key,
    required this.title,
    required this.severity,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    required this.version,
    required this.isDemo,
    required this.escalationLevel,
    required this.source,
    this.summary,
    this.serviceId,
    this.serviceName,
    this.assigneeId,
    this.assigneeName,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNote,
    this.pendingAction,
  });

  factory Incident.fromJson(Map<String, dynamic> j) {
    final svc = j['service'] as Map<String, dynamic>?;
    final who = j['assignee'] as Map<String, dynamic>?;
    DateTime? ts(String k) => j[k] == null ? null : DateTime.parse(j[k] as String).toLocal();
    return Incident(
      id: j['id'] as String,
      key: j['key'] as String,
      title: j['title'] as String,
      summary: j['summary'] as String?,
      severity: Severity.parse(j['severity'] as String),
      status: IncidentStatus.parse(j['status'] as String),
      startedAt: ts('started_at')!,
      updatedAt: ts('updated_at')!,
      acknowledgedAt: ts('acknowledged_at'),
      resolvedAt: ts('resolved_at'),
      resolutionNote: j['resolution_note'] as String?,
      version: j['version'] as int,
      isDemo: j['is_demo'] as bool? ?? false,
      escalationLevel: j['escalation_level'] as int? ?? 0,
      source: j['source'] as String,
      serviceId: svc?['id'] as String?,
      serviceName: svc?['name'] as String?,
      assigneeId: who?['id'] as String?,
      assigneeName: who?['display_name'] as String?,
    );
  }

  final String id;
  final String key;
  final String title;
  final String? summary;
  final Severity severity;
  final IncidentStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  final int version;
  final bool isDemo;
  final int escalationLevel;
  final String source;
  final String? serviceId;
  final String? serviceName;
  final String? assigneeId;
  final String? assigneeName;

  /// A local action waiting to reach the server (`acknowledge`, `resolve`, …), if any.
  final String? pendingAction;

  bool get isPending => pendingAction != null;

  /// API shape (`IncidentOut`) — used to cache incidents fetched outside the sync feed.
  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'number': int.tryParse(key.split('-').last) ?? 0,
    'title': title,
    'summary': summary,
    'severity': severity.name,
    'status': status.name,
    'started_at': startedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'acknowledged_at': acknowledgedAt?.toUtc().toIso8601String(),
    'resolved_at': resolvedAt?.toUtc().toIso8601String(),
    'resolution_note': resolutionNote,
    'version': version,
    'is_demo': isDemo,
    'escalation_level': escalationLevel,
    'source': source,
    'service': serviceId == null ? null : {'id': serviceId, 'name': serviceName ?? '', 'slug': ''},
    'assignee': assigneeId == null ? null : {'id': assigneeId, 'display_name': assigneeName ?? ''},
  };

  Incident withPending(String? action) => Incident(
    id: id,
    key: key,
    title: title,
    summary: summary,
    severity: severity,
    status: status,
    startedAt: startedAt,
    updatedAt: updatedAt,
    acknowledgedAt: acknowledgedAt,
    resolvedAt: resolvedAt,
    resolutionNote: resolutionNote,
    version: version,
    isDemo: isDemo,
    escalationLevel: escalationLevel,
    source: source,
    serviceId: serviceId,
    serviceName: serviceName,
    assigneeId: assigneeId,
    assigneeName: assigneeName,
    pendingAction: action,
  );
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.type,
    required this.actorType,
    required this.at,
    this.actorName,
    this.data = const {},
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
    id: j['id'] as String,
    type: j['type'] as String,
    actorType: j['actor_type'] as String,
    actorName: (j['actor'] as Map<String, dynamic>?)?['display_name'] as String?,
    data: (j['data'] as Map<String, dynamic>?) ?? const {},
    at: DateTime.parse(j['created_at'] as String).toLocal(),
  );

  final String id;
  final String type;
  final String actorType;
  final String? actorName;
  final Map<String, dynamic> data;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'actor_type': actorType,
    'actor': actorName == null ? null : {'id': '', 'display_name': actorName},
    'data': data,
    'created_at': at.toUtc().toIso8601String(),
  };

  /// Human sentence for the timeline.
  String describe() {
    final who = actorName ?? (actorType == 'system' ? 'DevPulse' : 'Someone');
    return switch (type) {
      'created' => data['rule'] != null ? 'Opened by alert “${data['rule']}”' : 'Opened by $who',
      'acknowledged' => '$who acknowledged',
      'resolved' => '$who resolved${data['note'] != null ? ': ${data['note']}' : ''}',
      'reopened' => '$who reopened',
      'assigned' => data['assignee_name'] == null ? '$who unassigned' : '$who assigned ${data['assignee_name']}',
      'escalated' => '$who escalated to level ${data['level']}',
      'severity_changed' => '$who changed severity to ${'${data['to']}'.toUpperCase()}',
      'comment_added' => '$who commented',
      'alert_attached' => 'Alert “${data['rule']}” fired again',
      'alert_resolved' => 'Alert “${data['rule']}” recovered',
      'deployment_correlated' => 'Deployment ${data['version']} may be related',
      'ai_analysis' when data['kind'] == 'proposal_decision' =>
        '$who ${data['decision']} the AI-proposed step “${data['description']}”',
      'ai_analysis' => switch (data['status']) {
        'succeeded' => 'AI analysis ready',
        'failed' || 'rejected' => 'AI analysis unavailable',
        _ => 'AI analysis updated',
      },
      _ => type,
    };
  }
}

class IncidentComment {
  const IncidentComment({
    required this.id,
    required this.clientId,
    required this.body,
    required this.at,
    this.authorName,
    this.pending = false,
  });

  factory IncidentComment.fromJson(Map<String, dynamic> j) => IncidentComment(
    id: j['id'] as String,
    clientId: j['client_id'] as String,
    body: j['body'] as String,
    authorName: (j['author'] as Map<String, dynamic>?)?['display_name'] as String?,
    at: DateTime.parse(j['created_at'] as String).toLocal(),
  );

  final String id;
  final String clientId;
  final String body;
  final String? authorName;
  final DateTime at;
  final bool pending;

  Map<String, dynamic> toJson() => {
    'id': id,
    'client_id': clientId,
    'body': body,
    'author': authorName == null ? null : {'id': '', 'display_name': authorName},
    'created_at': at.toUtc().toIso8601String(),
  };
}

class CorrelatedDeployment {
  const CorrelatedDeployment({
    required this.deploymentId,
    required this.version,
    required this.status,
    required this.startedAt,
    required this.score,
    required this.correlation,
    this.commitSha,
    this.commitMessage,
  });

  factory CorrelatedDeployment.fromJson(Map<String, dynamic> j) => CorrelatedDeployment(
    deploymentId: j['deployment_id'] as String,
    version: j['version'] as String,
    status: j['status'] as String,
    startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
    score: (j['score'] as num).toDouble(),
    correlation: j['correlation'] as String,
    commitSha: j['commit_sha'] as String?,
    commitMessage: j['commit_message'] as String?,
  );

  final String deploymentId;
  final String version;
  final String status;
  final DateTime startedAt;
  final double score;
  final String correlation;
  final String? commitSha;
  final String? commitMessage;

  Map<String, dynamic> toJson() => {
    'deployment_id': deploymentId,
    'version': version,
    'status': status,
    'started_at': startedAt.toUtc().toIso8601String(),
    'score': score,
    'correlation': correlation,
    'commit_sha': commitSha,
    'commit_message': commitMessage,
  };
}

/// Incident list filter. Persisted in a provider so it survives navigating to detail and back.
@immutable
class IncidentFilter {
  const IncidentFilter({
    this.statuses = const {IncidentStatus.triggered, IncidentStatus.acknowledged},
    this.severities = const {},
    this.mineOnly = false,
  });

  final Set<IncidentStatus> statuses;
  final Set<Severity> severities;
  final bool mineOnly;

  Map<String, dynamic> toQuery() => {
    if (statuses.isNotEmpty) 'status': [for (final s in statuses) s.name],
    if (severities.isNotEmpty) 'severity': [for (final s in severities) s.name],
    if (mineOnly) 'assignee': 'me',
  };

  IncidentFilter copyWith({Set<IncidentStatus>? statuses, Set<Severity>? severities, bool? mineOnly}) => IncidentFilter(
    statuses: statuses ?? this.statuses,
    severities: severities ?? this.severities,
    mineOnly: mineOnly ?? this.mineOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is IncidentFilter &&
      setEquals(other.statuses, statuses) &&
      setEquals(other.severities, severities) &&
      other.mineOnly == mineOnly;

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(statuses), Object.hashAllUnordered(severities), mineOnly);
}
