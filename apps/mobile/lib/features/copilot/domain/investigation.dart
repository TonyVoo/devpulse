import '../../../core/design_system/widgets/status_widgets.dart';
import '../../../l10n/l10n.dart';

/// AI investigation, as returned by the API (docs/AI_ARCHITECTURE.md §4). Every cause is a
/// hypothesis; evidence excerpts were computed by DevPulse from stored telemetry, not by the
/// model, and are what the UI shows.
enum RunStatus {
  queued,
  collecting,
  analyzing,
  succeeded,
  failed,
  rejected;

  static RunStatus parse(String? v) => RunStatus.values.firstWhere((s) => s.name == v, orElse: () => failed);

  bool get isActive => this == queued || this == collecting || this == analyzing;

  String get progressLabel => switch (this) {
    queued => l10n.progressQueued,
    collecting => l10n.progressCollecting,
    analyzing => l10n.progressAnalyzing,
    _ => '',
  };
}

class InvestigationSummary {
  const InvestigationSummary({
    required this.id,
    required this.incidentId,
    required this.incidentKey,
    required this.incidentTitle,
    required this.incidentSeverity,
    required this.status,
    required this.trigger,
    required this.provider,
    required this.model,
    required this.isDemoProvider,
    required this.createdAt,
    this.summary,
    this.errorCode,
  });

  factory InvestigationSummary.fromJson(Map<String, dynamic> j) => InvestigationSummary(
    id: j['id'] as String,
    incidentId: j['incident_id'] as String,
    incidentKey: j['incident_key'] as String,
    incidentTitle: j['incident_title'] as String,
    incidentSeverity: Severity.parse(j['incident_severity'] as String?),
    status: RunStatus.parse(j['status'] as String?),
    trigger: j['trigger'] as String,
    provider: j['provider'] as String,
    model: j['model'] as String,
    isDemoProvider: j['is_demo_provider'] as bool? ?? false,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    summary: j['summary'] as String?,
    errorCode: j['error_code'] as String?,
  );

  final String id;
  final String incidentId;
  final String incidentKey;
  final String incidentTitle;
  final Severity incidentSeverity;
  final RunStatus status;
  final String trigger;
  final String provider;
  final String model;

  /// The rule-based FakeProvider produced it: shown as "Demo analyzer — not an LLM".
  final bool isDemoProvider;
  final DateTime createdAt;
  final String? summary;
  final String? errorCode;
}

class Evidence {
  const Evidence({required this.ref, required this.kind, required this.title, required this.text, required this.raw});

  factory Evidence.fromJson(Map<String, dynamic> j) {
    final excerpt = (j['excerpt'] as Map<String, dynamic>?) ?? const {};
    return Evidence(
      ref: j['ref'] as String,
      kind: j['kind'] as String,
      title: j['title'] as String,
      text: excerpt['text'] as String? ?? '',
      raw: j,
    );
  }

  final String ref;
  final String kind;
  final String title;

  /// One-line summary computed by DevPulse (never restated by the model).
  final String text;
  final Map<String, dynamic> raw;

  Map<String, dynamic> get sourceQuery => (raw['source_query'] as Map<String, dynamic>?) ?? const {};
}

class Cause {
  const Cause({
    required this.cause,
    required this.confidence,
    required this.confidenceLabel,
    required this.reasoning,
    required this.evidenceRefs,
    required this.counterEvidenceRefs,
    required this.howToVerify,
  });

  factory Cause.fromJson(Map<String, dynamic> j) => Cause(
    cause: j['cause'] as String,
    confidence: (j['confidence'] as num).toDouble(),
    confidenceLabel: j['confidence_label'] as String,
    reasoning: j['reasoning'] as String,
    evidenceRefs: [for (final r in j['evidence_refs'] as List<dynamic>) r as String],
    counterEvidenceRefs: [for (final r in (j['counter_evidence_refs'] as List<dynamic>? ?? const [])) r as String],
    howToVerify: j['how_to_verify'] as String? ?? '',
  );

  final String cause;
  final double confidence;
  final String confidenceLabel;
  final String reasoning;
  final List<String> evidenceRefs;
  final List<String> counterEvidenceRefs;
  final String howToVerify;
}

class AiAction {
  const AiAction({
    required this.action,
    required this.kind,
    required this.risk,
    required this.rationale,
    required this.requiresApproval,
    this.proposalId,
  });

  factory AiAction.fromJson(Map<String, dynamic> j) => AiAction(
    action: j['action'] as String,
    kind: j['kind'] as String,
    risk: j['risk'] as String,
    rationale: j['rationale'] as String? ?? '',
    requiresApproval: j['requires_approval'] as bool? ?? false,
    proposalId: j['proposal_id'] as String?,
  );

  final String action;
  final String kind;

  /// read_only | sensitive | destructive
  final String risk;
  final String rationale;
  final bool requiresApproval;
  final String? proposalId;
}

class Proposal {
  const Proposal({required this.id, required this.description, required this.risk, required this.status, this.note});

  factory Proposal.fromJson(Map<String, dynamic> j) => Proposal(
    id: j['id'] as String,
    description: j['description'] as String,
    risk: j['risk'] as String,
    status: j['status'] as String,
    note: j['decision_note'] as String?,
  );

  final String id;
  final String description;
  final String risk;

  /// proposed | approved | rejected — approval records a decision; DevPulse executes nothing.
  final String status;
  final String? note;
}

class Analysis {
  const Analysis({
    required this.summary,
    required this.impact,
    required this.causes,
    required this.actions,
    required this.dataGaps,
    required this.limitations,
    required this.adjustments,
  });

  factory Analysis.fromJson(Map<String, dynamic> j) => Analysis(
    summary: j['summary'] as String,
    impact: j['impact'] as String? ?? '',
    causes: [for (final c in j['probable_causes'] as List<dynamic>) Cause.fromJson(c as Map<String, dynamic>)],
    actions: [for (final a in j['recommended_actions'] as List<dynamic>) AiAction.fromJson(a as Map<String, dynamic>)],
    dataGaps: [for (final g in (j['data_gaps'] as List<dynamic>? ?? const [])) g as String],
    limitations: j['limitations'] as String? ?? '',
    adjustments: [for (final a in (j['adjustments'] as List<dynamic>? ?? const [])) a as String],
  );

  final String summary;
  final String impact;
  final List<Cause> causes;
  final List<AiAction> actions;
  final List<String> dataGaps;
  final String limitations;
  final List<String> adjustments;
}

class Investigation {
  const Investigation({
    required this.summary,
    required this.evidence,
    required this.proposals,
    required this.dataGaps,
    required this.raw,
    this.result,
    this.errorDetail,
    this.myFeedback,
  });

  factory Investigation.fromJson(Map<String, dynamic> j) => Investigation(
    summary: InvestigationSummary.fromJson(j),
    result: j['result'] == null ? null : Analysis.fromJson(j['result'] as Map<String, dynamic>),
    evidence: [
      for (final e in (j['evidence'] as List<dynamic>? ?? const [])) Evidence.fromJson(e as Map<String, dynamic>),
    ],
    proposals: [
      for (final p in (j['proposals'] as List<dynamic>? ?? const [])) Proposal.fromJson(p as Map<String, dynamic>),
    ],
    dataGaps: [for (final g in (j['data_gaps'] as List<dynamic>? ?? const [])) g as String],
    errorDetail: j['error_detail'] as String?,
    myFeedback: j['my_feedback'] as bool?,
    raw: j,
  );

  final InvestigationSummary summary;
  final Analysis? result;
  final List<Evidence> evidence;
  final List<Proposal> proposals;
  final List<String> dataGaps;
  final String? errorDetail;
  final bool? myFeedback;

  /// Original JSON, kept so the last analysis can be cached for offline reading.
  final Map<String, dynamic> raw;

  String get id => summary.id;
  RunStatus get status => summary.status;

  Evidence? evidenceFor(String ref) => evidence.where((e) => e.ref == ref).firstOrNull;
  Proposal? proposal(String? id) => id == null ? null : proposals.where((p) => p.id == id).firstOrNull;
}

class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.evidenceRefs,
    required this.at,
    this.toolName,
  });

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
    id: j['id'] as String,
    role: j['role'] as String,
    content: j['content'] as String,
    evidenceRefs: [for (final r in (j['evidence_refs'] as List<dynamic>? ?? const [])) r as String],
    toolName: j['tool_name'] as String?,
    at: DateTime.parse(j['created_at'] as String).toLocal(),
  );

  final String id;

  /// user | assistant | tool
  final String role;
  final String content;
  final List<String> evidenceRefs;
  final String? toolName;
  final DateTime at;
}

/// User-facing explanation for a stable error code (never the raw code alone).
String aiErrorMessage(String? code, {String? detail}) => switch (code) {
  'ai.disabled' => l10n.aiDisabled,
  'ai.budget_exceeded' => l10n.aiBudget,
  'ai.provider_unconfigured' => l10n.aiUnconfigured,
  'ai.no_evidence' => l10n.aiNoEvidence,
  'ai.invalid_output' => l10n.aiInvalidOutput,
  'ai.refused' => l10n.aiRefused,
  'ai.run_timeout' || 'ai.timeout' => l10n.aiTimeout,
  'ai.rate_limited' || 'ai.provider_unavailable' || 'ai.provider_unreachable' => l10n.aiUnavailable,
  'ai.stale' => l10n.aiStale,
  'ai.already_running' => l10n.aiAlreadyRunning,
  _ => detail ?? l10n.aiFailed,
};
