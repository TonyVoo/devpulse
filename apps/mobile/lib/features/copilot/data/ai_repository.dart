import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/org_api.dart';
import '../../../core/result/failure.dart';
import '../../offline/live_sync.dart';
import '../../ops_repositories.dart';
import '../domain/investigation.dart';

/// AI investigator API. The provider key never reaches the device: the app only talks to
/// DevPulse, which calls the model server-side.
abstract interface class AiRepository {
  Future<List<InvestigationSummary>> forIncident(String incidentRef);
  Future<Paged<InvestigationSummary>> recent({String? cursor});
  Future<Investigation> get(String id);
  Future<Investigation> start(String incidentRef);
  Future<List<AiMessage>> messages(String id);
  Future<AskResult> ask(String id, String question, String clientId);
  Future<Proposal> decide(String id, String proposalId, {required bool approve, String? note});
  Future<void> feedback(String id, {required bool helpful});
}

class AskResult {
  const AskResult(this.messages, this.newEvidence);

  final List<AiMessage> messages;
  final List<Evidence> newEvidence;
}

class ApiAiRepository implements AiRepository {
  ApiAiRepository(this._api);

  final OrgApi _api;

  @override
  Future<List<InvestigationSummary>> forIncident(String incidentRef) async => [
    for (final j in await _api.getList('incidents/$incidentRef/investigations'))
      InvestigationSummary.fromJson(j as Map<String, dynamic>),
  ];

  @override
  Future<Paged<InvestigationSummary>> recent({String? cursor}) =>
      _api.page('ai/investigations', InvestigationSummary.fromJson, cursor: cursor, query: {'limit': 30});

  @override
  Future<Investigation> get(String id) async => Investigation.fromJson(await _api.get('ai/investigations/$id'));

  @override
  Future<Investigation> start(String incidentRef) async =>
      Investigation.fromJson(await _api.command('incidents/$incidentRef/investigations'));

  @override
  Future<List<AiMessage>> messages(String id) async => [
    for (final j in await _api.getList('ai/investigations/$id/messages')) AiMessage.fromJson(j as Map<String, dynamic>),
  ];

  @override
  Future<AskResult> ask(String id, String question, String clientId) async {
    final body = await _api.command(
      'ai/investigations/$id/messages',
      body: {'question': question, 'client_id': clientId},
    );
    return AskResult(
      [for (final m in body['messages'] as List<dynamic>) AiMessage.fromJson(m as Map<String, dynamic>)],
      [for (final e in body['new_evidence'] as List<dynamic>) Evidence.fromJson(e as Map<String, dynamic>)],
    );
  }

  @override
  Future<Proposal> decide(String id, String proposalId, {required bool approve, String? note}) async =>
      Proposal.fromJson(
        await _api.command(
          'ai/investigations/$id/proposals/$proposalId/decision',
          body: {'approve': approve, 'note': ?note},
        ),
      );

  @override
  Future<void> feedback(String id, {required bool helpful}) =>
      _api.put('ai/investigations/$id/feedback', {'helpful': helpful});
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => ApiAiRepository(ref.watch(orgApiProvider)));

class IncidentAnalysis {
  const IncidentAnalysis(this.latest, {this.stale = false});

  /// Null when the incident has never been investigated.
  final Investigation? latest;

  /// Shown from the device cache because the network was unavailable.
  final bool stale;
}

/// Poll interval while a run is in progress (the realtime `ai_analysis` event also triggers
/// a refresh, so this is only a fallback).
const aiPollInterval = Duration(seconds: 3);

/// Latest investigation for an incident: network first, last copy kept on the device so an
/// analysis opened offline is still readable.
final incidentAnalysisProvider = FutureProvider.autoDispose.family<IncidentAnalysis, String>((ref, incidentId) async {
  final live = ref.watch(liveSyncProvider);
  if (live != null) {
    final sub = live.incidentEvents.where((id) => id == incidentId).listen((_) => ref.invalidateSelf());
    ref.onDispose(sub.cancel);
  }
  final repo = ref.watch(aiRepositoryProvider);
  final db = ref.watch(databaseProvider);
  try {
    final runs = await repo.forIncident(incidentId);
    if (runs.isEmpty) return const IncidentAnalysis(null);
    final inv = await repo.get(runs.first.id);
    await db.writeJson(KvKeys.investigation(incidentId), inv.raw);
    if (inv.status.isActive) {
      final timer = Timer(aiPollInterval, ref.invalidateSelf);
      ref.onDispose(timer.cancel);
    }
    return IncidentAnalysis(inv);
  } on Object catch (e) {
    final cached = await db.readJson(KvKeys.investigation(incidentId));
    if (cached == null) throw Failure.from(e);
    return IncidentAnalysis(Investigation.fromJson(cached), stale: true);
  }
}, retry: (_, _) => null);

final recentInvestigationsProvider = FutureProvider.autoDispose<Paged<InvestigationSummary>>(
  (ref) => ref.watch(aiRepositoryProvider).recent(),
  retry: (_, _) => null,
);

final investigationProvider = FutureProvider.autoDispose.family<Investigation, String>(
  (ref, id) => ref.watch(aiRepositoryProvider).get(id),
  retry: (_, _) => null,
);

final aiMessagesProvider = FutureProvider.autoDispose.family<List<AiMessage>, String>(
  (ref, id) => ref.watch(aiRepositoryProvider).messages(id),
  retry: (_, _) => null,
);
