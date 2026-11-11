import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/result/failure.dart';
import '../data/auth_repository.dart';
import '../domain/models.dart';

/// Owns the signed-in state. The router redirects purely from this state.
class SessionController extends AsyncNotifier<SessionState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<SessionState> build() => _restore();

  /// App start: tokens in the keystore → try `/me`; if offline, fall back to the cached
  /// profile so the user can still read cached data. A rejected session signs out.
  Future<SessionState> _restore() async {
    if (!await _repo.hasSession()) return const SignedOut();
    final savedOrg = await _repo.savedOrgId();
    try {
      final me = await _repo.fetchMe();
      return SignedIn(me: me, currentOrgId: _resolveOrg(me, savedOrg));
    } on UnauthorizedFailure {
      await _repo.clearLocal();
      return const SignedOut(reason: 'Your session has ended. Sign in again.');
    } on Failure catch (f) {
      final cached = await _repo.cachedMe();
      if (f is NetworkFailure || f is ServerFailure) {
        if (cached != null) return SignedIn(me: cached, currentOrgId: _resolveOrg(cached, savedOrg), isStale: true);
      }
      rethrow; // splash shows the error with a Retry action
    }
  }

  /// Keep the saved org if still a member; auto-pick when there is exactly one.
  static String? _resolveOrg(Me me, String? saved) {
    if (saved != null && me.org(saved) != null) return saved;
    return me.memberships.length == 1 ? me.memberships.single.id : null;
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_restore);
  }

  /// Throws [Failure] so the form can show field errors; state is untouched on failure.
  Future<void> login(String email, String password) async {
    final me = await _repo.login(email: email, password: password);
    await _signedIn(me);
  }

  Future<void> register(String name, String email, String password) async {
    final me = await _repo.register(email: email, password: password, displayName: name);
    await _signedIn(me);
  }

  Future<void> _signedIn(Me me) async {
    final org = _resolveOrg(me, null);
    if (org != null) await _repo.saveOrgId(org);
    state = AsyncData(SignedIn(me: me, currentOrgId: org));
  }

  Future<void> selectOrg(String orgId) async {
    final current = state.value;
    if (current is! SignedIn || current.me.org(orgId) == null) return;
    await _repo.saveOrgId(orgId);
    state = AsyncData(current.copyWith(currentOrgId: orgId));
  }

  Future<void> createOrg(String name) async {
    final org = await _repo.createOrg(name);
    final me = await _repo.fetchMe();
    await _repo.saveOrgId(org.id);
    state = AsyncData(SignedIn(me: me, currentOrgId: org.id));
  }

  /// Pull-to-refresh / resume: refresh the profile without blanking the UI.
  Future<void> refreshProfile() async {
    final current = state.value;
    if (current is! SignedIn) return;
    try {
      final me = await _repo.fetchMe();
      state = AsyncData(SignedIn(me: me, currentOrgId: _resolveOrg(me, current.currentOrgId)));
    } on NetworkFailure {
      state = AsyncData(current.copyWith(isStale: true));
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncData(SignedOut());
  }

  /// Called by the network layer when the refresh token is rejected.
  void onSessionExpired() {
    if (state.value is SignedOut) return;
    _repo.clearLocal().ignore();
    state = const AsyncData(SignedOut(reason: 'Your session has ended. Sign in again.'));
  }
}

final sessionControllerProvider = AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
  // Retrying is a user decision (Retry button), not automatic: a failed restore may mean
  // the API is down, and silent retry loops waste battery.
  retry: (_, _) => null,
);
