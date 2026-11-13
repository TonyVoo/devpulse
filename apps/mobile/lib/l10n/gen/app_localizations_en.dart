// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DevPulse';

  @override
  String get retry => 'Retry';

  @override
  String get tryAgain => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get done => 'Done';

  @override
  String get all => 'All';

  @override
  String get view => 'View';

  @override
  String get loading => 'Loading';

  @override
  String get loadingEllipsis => 'Loading…';

  @override
  String get couldNotLoad => 'Couldn\'t load';

  @override
  String get couldNotLoadThis => 'Couldn\'t load this';

  @override
  String get youreOffline => 'You\'re offline';

  @override
  String get unknown => 'Unknown';

  @override
  String get you => 'You';

  @override
  String get someone => 'Someone';

  @override
  String get demo => 'DEMO';

  @override
  String inProgressLabel(String label) {
    return '$label, in progress';
  }

  @override
  String requestRef(String id) {
    return 'Ref: $id';
  }

  @override
  String pageNotFound(String path) {
    return 'Page not found: $path';
  }

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(num n) {
    return '${n}m ago';
  }

  @override
  String hoursAgo(num n) {
    return '${n}h ago';
  }

  @override
  String daysAgo(num n) {
    return '${n}d ago';
  }

  @override
  String get healthHealthy => 'Healthy';

  @override
  String get healthDegraded => 'Degraded';

  @override
  String get healthCritical => 'Critical';

  @override
  String get healthUnknown => 'Unknown';

  @override
  String healthSemantics(String label) {
    return 'Health: $label';
  }

  @override
  String severitySemantics(num n) {
    return 'Severity $n';
  }

  @override
  String get statusTriggered => 'Triggered';

  @override
  String get statusAcknowledged => 'Acknowledged';

  @override
  String get statusResolved => 'Resolved';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleEngineer => 'Engineer';

  @override
  String get roleViewer => 'Viewer';

  @override
  String get noDataInRange => 'No data in this range';

  @override
  String get navOverview => 'Overview';

  @override
  String get navServices => 'Services';

  @override
  String get navIncidents => 'Incidents';

  @override
  String get navCopilot => 'Copilot';

  @override
  String get navSettings => 'Settings';

  @override
  String get offlineBanner => 'Offline · showing data saved on this device';

  @override
  String pendingChanges(num n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n changes waiting to sync',
      one: '1 change waiting to sync',
    );
    return '$_temp0';
  }

  @override
  String changeNotApplied(String message) {
    return 'A change couldn\'t be applied: $message';
  }

  @override
  String get signIn => 'Sign in';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get createAccount => 'Create account';

  @override
  String get name => 'Name';

  @override
  String get workEmail => 'Work email';

  @override
  String get password => 'Password';

  @override
  String get passwordHint => 'At least 12 characters.';

  @override
  String get passwordTooShort => 'Use at least 12 characters.';

  @override
  String get invalidEmail => 'Enter a valid email address.';

  @override
  String get checkFields => 'Check the highlighted fields.';

  @override
  String get goToRegister => 'New to DevPulse? Create an account';

  @override
  String get goToLogin => 'Already have an account? Sign in';

  @override
  String get restoringSession => 'Restoring your session';

  @override
  String get sessionEnded => 'Your session has ended. Sign in again.';

  @override
  String get errNetwork => 'Can\'t reach DevPulse. Check your connection.';

  @override
  String get errInsecure => 'Can\'t establish a secure connection.';

  @override
  String get errSlow => 'The response took too long to process.';

  @override
  String get errCancelled => 'Request cancelled';

  @override
  String get errTooMany => 'Too many attempts. Wait a few minutes and try again.';

  @override
  String get errServer => 'DevPulse is having trouble right now. Try again shortly.';

  @override
  String get errGeneric => 'Something went wrong. Try again.';

  @override
  String get errInvalidCredentials => 'Email or password is incorrect';

  @override
  String get errEmailTaken => 'An account with this email already exists';

  @override
  String get errVersionMismatch => 'This was changed by someone else. Reload and try again.';

  @override
  String get errInvalidTransition => 'This action isn\'t possible in the incident\'s current status.';

  @override
  String get errMaxEscalation => 'Already at the highest escalation level.';

  @override
  String get errSlugTaken => 'That name is already taken. Try another.';

  @override
  String get organizations => 'Organizations';

  @override
  String get offlineOrgs => 'You\'re offline. Showing your last known organizations.';

  @override
  String get yourOrganizations => 'Your organizations';

  @override
  String get current => 'Current';

  @override
  String get createFirstOrg => 'Create your first organization';

  @override
  String get createAnotherOrg => 'Create another organization';

  @override
  String get orgIntro => 'Each organization keeps its own services, incidents and members.';

  @override
  String get orgName => 'Organization name';

  @override
  String get orgNameLength => 'Use 2–120 characters.';

  @override
  String get createOrg => 'Create organization';

  @override
  String get noServicesTitle => 'No services connected yet';

  @override
  String get noServicesBody =>
      'Create a service and an ingest key on the web dashboard, then send telemetry. Health, latency and incidents will show up here.';

  @override
  String criticalOpen(num n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n critical incidents open',
      one: '1 critical incident open',
    );
    return '$_temp0';
  }

  @override
  String get overviewStale => 'Offline · showing the last overview saved on this device';

  @override
  String get noTelemetryWindow => 'No telemetry received in the selected window — try a longer one.';

  @override
  String get requests => 'Requests';

  @override
  String get errorRate => 'Error rate';

  @override
  String get avgLatency => 'Avg latency';

  @override
  String get p95Latency => 'p95 latency';

  @override
  String get approx => 'approx.';

  @override
  String get requestVolume => 'Request volume';

  @override
  String requestVolumeSemantics(String count) {
    return 'Request volume chart, $count requests in this window';
  }

  @override
  String get recentIncidents => 'Recent incidents';

  @override
  String get noIncidents => 'No incidents';

  @override
  String get allQuiet => 'All quiet.';

  @override
  String get recentDeployments => 'Recent deployments';

  @override
  String get noDeploymentsYet => 'No deployments yet';

  @override
  String get sendFromCi => 'Send them from CI or connect GitHub.';

  @override
  String servicesCount(num n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: 'services', one: 'service');
    return '$_temp0';
  }

  @override
  String healthCountSemantics(num n, String label) {
    return '$n $label';
  }

  @override
  String get deployments => 'Deployments';

  @override
  String get deploymentsEmptyBody =>
      'Send deployment events from CI with an ingest key, or connect GitHub on the web dashboard.';

  @override
  String get searchServices => 'Search services';

  @override
  String get noServicesYet => 'No services yet';

  @override
  String get noMatchingServices => 'No matching services';

  @override
  String get servicesEmptyBody =>
      'Add a service and an ingest key from the web dashboard, then its health shows up here.';

  @override
  String get tryDifferentSearch => 'Try a different search or clear the filters.';

  @override
  String get noDataYet => 'no data yet';

  @override
  String get noDataYetCap => 'No data yet';

  @override
  String seenAgo(String ago) {
    return 'seen $ago';
  }

  @override
  String seenAgoCap(String ago) {
    return 'Seen $ago';
  }

  @override
  String serviceMeta(String slug, String environment, String tier) {
    return '$slug · $environment · tier $tier';
  }

  @override
  String get service => 'Service';

  @override
  String get metricsError => 'Couldn\'t load metrics';

  @override
  String get latencyP95 => 'Latency p95';

  @override
  String get cpu => 'CPU';

  @override
  String chartSemantics(String title) {
    return '$title chart';
  }

  @override
  String get openIncidents => 'Open incidents';

  @override
  String get noOpenIncidents => 'No open incidents';

  @override
  String get noDeploymentsRecorded => 'No deployments recorded';

  @override
  String get tabOpen => 'Open';

  @override
  String get mine => 'Mine';

  @override
  String get noOpenIncidentsAllClear => 'No open incidents — all clear';

  @override
  String get noIncidentsMatch => 'No incidents match';

  @override
  String get incidentsEmptyBody => 'Incidents opened by alert rules or by your team will appear here.';

  @override
  String get tryDifferentFilter => 'Try a different status or severity filter.';

  @override
  String get loadOlderFailed => 'Couldn\'t load — retry';

  @override
  String get loadOlder => 'Load older incidents';

  @override
  String get waitingToSync => 'Waiting to sync';

  @override
  String incidentTileSemantics(String severity, String key, String title, String status, String ago) {
    return '$severity $key, $title, $status, started $ago';
  }

  @override
  String get incidentNotFound => 'Incident not found';

  @override
  String get incidentNotFoundBody => 'It may belong to another organization.';

  @override
  String get offlineSaved => 'You\'re offline. The change is saved and will be sent automatically.';

  @override
  String get resolveIncidentQ => 'Resolve incident?';

  @override
  String get resolutionNoteOptional => 'Resolution note (optional)';

  @override
  String get resolve => 'Resolve';

  @override
  String get acknowledge => 'Acknowledge';

  @override
  String get assignToMe => 'Assign to me';

  @override
  String get escalate => 'Escalate';

  @override
  String get reopen => 'Reopen';

  @override
  String escalatedTimes(num n) {
    return 'Escalated ×$n';
  }

  @override
  String pendingAction(String action) {
    return 'Your \"$action\" is waiting to be sent.';
  }

  @override
  String startedAgo(String ago) {
    return 'started $ago';
  }

  @override
  String ownerName(String name) {
    return 'owner $name';
  }

  @override
  String resolution(String note) {
    return 'Resolution: $note';
  }

  @override
  String get timelineStale => 'Showing the timeline saved on this device.';

  @override
  String get relatedDeployments => 'Possibly related deployments';

  @override
  String correlationSemantics(String pct, String kind) {
    return 'Correlation $pct percent, $kind';
  }

  @override
  String get timingOnly => 'Suspected from timing only — not a confirmed cause.';

  @override
  String get timeline => 'Timeline';

  @override
  String get timelineError => 'Couldn\'t load the timeline';

  @override
  String get comments => 'Comments';

  @override
  String get noComments => 'No comments yet.';

  @override
  String get waitingToSend => 'waiting to send';

  @override
  String get addComment => 'Add a comment';

  @override
  String get sendComment => 'Send comment';

  @override
  String get correlationSuspected => 'suspected';

  @override
  String get correlationRuledOut => 'ruled out';

  @override
  String get correlationConfirmed => 'confirmed';

  @override
  String conflictNotApplied(String action) {
    return 'Your \"$action\" was not applied: someone else changed this incident first. Showing the latest.';
  }

  @override
  String showingLatest(String message) {
    return '$message. Showing the latest.';
  }

  @override
  String evOpenedByRule(String rule) {
    return 'Opened by alert “$rule”';
  }

  @override
  String evOpenedBy(String who) {
    return 'Opened by $who';
  }

  @override
  String evAcknowledged(String who) {
    return '$who acknowledged';
  }

  @override
  String evResolved(String who) {
    return '$who resolved';
  }

  @override
  String evResolvedNote(String who, String note) {
    return '$who resolved: $note';
  }

  @override
  String evReopened(String who) {
    return '$who reopened';
  }

  @override
  String evAssigned(String who, String name) {
    return '$who assigned $name';
  }

  @override
  String evUnassigned(String who) {
    return '$who unassigned';
  }

  @override
  String evEscalated(String who, String level) {
    return '$who escalated to level $level';
  }

  @override
  String evSeverityChanged(String who, String severity) {
    return '$who changed severity to $severity';
  }

  @override
  String evCommented(String who) {
    return '$who commented';
  }

  @override
  String evAlertAttached(String rule) {
    return 'Alert “$rule” fired again';
  }

  @override
  String evAlertResolved(String rule) {
    return 'Alert “$rule” recovered';
  }

  @override
  String evDeploymentCorrelated(String version) {
    return 'Deployment $version may be related';
  }

  @override
  String evProposalApproved(String who, String description) {
    return '$who approved the AI-proposed step “$description”';
  }

  @override
  String evProposalRejected(String who, String description) {
    return '$who rejected the AI-proposed step “$description”';
  }

  @override
  String get evAiReady => 'AI analysis ready';

  @override
  String get evAiUnavailable => 'AI analysis unavailable';

  @override
  String get evAiUpdated => 'AI analysis updated';

  @override
  String get aiCopilot => 'AI Copilot';

  @override
  String get noInvestigations => 'No investigations yet';

  @override
  String get noInvestigationsBody =>
      'Open an incident and tap \"Investigate with AI\". Copilot gathers metrics, logs and deployments and suggests probable causes with the evidence behind them.';

  @override
  String get analysisReady => 'Analysis ready';

  @override
  String get triggerAuto => 'Automatic';

  @override
  String get triggerRequested => 'Requested';

  @override
  String get progressQueued => 'Waiting for a worker…';

  @override
  String get progressCollecting => 'Collecting metrics, logs and deployments…';

  @override
  String get progressAnalyzing => 'Analysing the evidence…';

  @override
  String get aiAnalysis => 'AI analysis';

  @override
  String get runAgain => 'Run again';

  @override
  String get analysisStale => 'Showing the analysis saved on this device.';

  @override
  String get aiLoadError => 'Couldn\'t load the AI analysis';

  @override
  String get aiIntro =>
      'Copilot reads this incident\'s metrics, logs, deployments and similar past incidents, then suggests probable causes, each with the evidence behind it.';

  @override
  String get investigateWithAi => 'Investigate with AI';

  @override
  String get investigateOffline => 'Investigate (needs a connection)';

  @override
  String get analysisUnavailable => 'Analysis unavailable';

  @override
  String get actionsUnaffected => 'Incident actions are not affected.';

  @override
  String hypotheses(String ago) {
    return 'Hypotheses — not confirmed · $ago';
  }

  @override
  String get probableCauses => 'Probable causes';

  @override
  String get nextSteps => 'Recommended next steps';

  @override
  String get couldNotSee => 'What DevPulse could not see';

  @override
  String adjusted(String text) {
    return 'Adjusted: $text';
  }

  @override
  String get askFollowUp => 'Ask a follow-up';

  @override
  String get helpful => 'Helpful';

  @override
  String get notHelpful => 'Not helpful';

  @override
  String get feedbackThanks => 'Thanks, your feedback helps tune the investigator.';

  @override
  String verify(String how) {
    return 'Verify: $how';
  }

  @override
  String get approvedNotRun => '· Approved (not executed by DevPulse)';

  @override
  String get rejected => '· Rejected';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get adminMustDecide => 'An admin must decide on destructive actions.';

  @override
  String get approveQ => 'Approve this action?';

  @override
  String approveBody(String description) {
    return '“$description”\n\nApproving records your decision on the incident. DevPulse does not run it: your team carries it out.';
  }

  @override
  String get confidenceHigh => 'high';

  @override
  String get confidenceMedium => 'medium';

  @override
  String get confidenceLow => 'low';

  @override
  String confidenceSemantics(String label, String pct) {
    return '$label confidence, $pct percent';
  }

  @override
  String get riskReadOnly => 'Read-only';

  @override
  String get riskDestructive => 'Destructive · admin approval';

  @override
  String get riskSensitive => 'Changes a system · needs approval';

  @override
  String get demoAnalyzer => 'DEMO ANALYZER · NOT AN LLM';

  @override
  String against(String ref) {
    return '$ref (against)';
  }

  @override
  String evidenceComputed(String kind) {
    return 'Computed by DevPulse from stored $kind data, not by the AI.';
  }

  @override
  String evidenceSource(String source) {
    return 'Source: $source';
  }

  @override
  String get askCopilot => 'Ask Copilot';

  @override
  String get askHint =>
      'Ask about this incident, e.g. \"When did errors start?\" or \"Was this seen before?\". Answers cite evidence; Copilot can only read data, never change anything.';

  @override
  String get lookingIntoIt => 'Looking into it…';

  @override
  String get questionHint => 'Ask a follow-up question';

  @override
  String get needsConnection => 'Needs a connection';

  @override
  String get sendQuestion => 'Send question';

  @override
  String lookedUp(String tool, String refs) {
    return 'Looked up $tool → $refs';
  }

  @override
  String get aiDisabled =>
      'AI analysis is turned off for this organization. An admin can enable it in Settings → AI on the web.';

  @override
  String get aiBudget => 'This month\'s AI budget is used up. An admin can raise it on the web.';

  @override
  String get aiUnconfigured => 'No AI provider is configured on this DevPulse server.';

  @override
  String get aiNoEvidence => 'DevPulse has no telemetry for this incident, so there\'s nothing to analyse.';

  @override
  String get aiInvalidOutput => 'The AI\'s answer failed validation and was discarded.';

  @override
  String get aiRefused => 'The AI model declined to analyse this incident.';

  @override
  String get aiTimeout => 'The analysis took too long.';

  @override
  String get aiUnavailable => 'The AI provider is unavailable right now. Try again in a minute.';

  @override
  String get aiStale => 'The analysis was interrupted.';

  @override
  String get aiAlreadyRunning => 'An analysis is already running for this incident.';

  @override
  String get aiFailed => 'The analysis failed.';

  @override
  String get signOutQ => 'Sign out?';

  @override
  String get signOutBody => 'Data saved on this device for your account will be removed.';

  @override
  String get signOut => 'Sign out';

  @override
  String get profile => 'Profile';

  @override
  String get organization => 'Organization';

  @override
  String get noneSelected => 'None selected';

  @override
  String yourRole(String role) {
    return 'Your role: $role';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get account => 'Account';

  @override
  String get settingsFooter =>
      'Notification preferences and security settings arrive with push notifications (Phase 3).';
}
