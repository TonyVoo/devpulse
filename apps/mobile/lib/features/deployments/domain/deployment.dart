import 'package:flutter/foundation.dart';

@immutable
class Deployment {
  const Deployment({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.environment,
    required this.version,
    required this.status,
    required this.startedAt,
    required this.source,
    required this.isDemo,
    this.buildStatus,
    this.commitSha,
    this.commitMessage,
    this.commitAuthor,
    this.branch,
    this.finishedAt,
  });

  factory Deployment.fromJson(Map<String, dynamic> j) => Deployment(
    id: j['id'] as String,
    serviceId: j['service_id'] as String,
    serviceName: j['service_name'] as String? ?? '',
    environment: j['environment'] as String,
    version: j['version'] as String,
    status: j['status'] as String,
    buildStatus: j['build_status'] as String?,
    startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
    finishedAt: j['finished_at'] == null ? null : DateTime.parse(j['finished_at'] as String).toLocal(),
    source: j['source'] as String,
    isDemo: j['is_demo'] as bool? ?? false,
    commitSha: j['commit_sha'] as String?,
    commitMessage: j['commit_message'] as String?,
    commitAuthor: j['commit_author'] as String?,
    branch: j['branch'] as String?,
  );

  final String id;
  final String serviceId;
  final String serviceName;
  final String environment;
  final String version;
  final String status;
  final String? buildStatus;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String source;
  final bool isDemo;
  final String? commitSha;
  final String? commitMessage;
  final String? commitAuthor;
  final String? branch;

  String? get shortSha => commitSha?.substring(0, commitSha!.length.clamp(0, 7));
}
