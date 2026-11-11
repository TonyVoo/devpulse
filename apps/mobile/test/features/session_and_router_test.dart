import 'package:devpulse_mobile/app/providers.dart';
import 'package:devpulse_mobile/app/router.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/auth/domain/models.dart';
import 'package:devpulse_mobile/features/auth/presentation/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('resolveRedirect', () {
    String? go(AsyncValue<SessionState> s, String location) => resolveRedirect(s, Uri.parse(location));
    final signedIn = AsyncData<SessionState>(SignedIn(me: me(), currentOrgId: 'org-a'));
    final noOrg = AsyncData<SessionState>(SignedIn(me: me(orgs: [orgA, orgB]), currentOrgId: null));
    const signedOut = AsyncData<SessionState>(SignedOut());

    test('restoring shows the splash', () {
      expect(go(const AsyncLoading(), '/incidents'), Routes.splash);
      expect(go(const AsyncLoading(), Routes.splash), isNull);
      expect(go(const AsyncError(NetworkFailure(), StackTrace.empty), '/overview'), Routes.splash);
    });

    test('signed out → login, remembering the deep link', () {
      expect(go(signedOut, '/incidents?status=open'), '/login?from=%2Fincidents%3Fstatus%3Dopen');
      expect(go(signedOut, Routes.splash), Routes.login);
      expect(go(signedOut, Routes.register), isNull);
    });

    test('signed in → back to the deep link, or overview', () {
      expect(go(signedIn, '/login?from=%2Fincidents'), '/incidents');
      expect(go(signedIn, Routes.splash), Routes.overview);
      expect(go(signedIn, '/login?from=%2F%2Fevil.example'), Routes.overview);
      expect(go(signedIn, '/services'), isNull);
      expect(go(signedIn, Routes.orgs), isNull); // switching orgs is allowed
    });

    test('signed in without an org → org picker', () {
      expect(go(noOrg, '/overview'), Routes.orgs);
      expect(go(noOrg, Routes.orgs), isNull);
    });
  });

  group('SessionController', () {
    ProviderContainer containerWith(FakeAuthRepository repo) {
      final c = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      return c;
    }

    test('no stored session → signed out', () async {
      final c = containerWith(FakeAuthRepository());
      expect(await c.read(sessionControllerProvider.future), isA<SignedOut>());
    });

    test('restores online and auto-selects the only org', () async {
      final c = containerWith(FakeAuthRepository(session: true, remote: me()));
      final s = await c.read(sessionControllerProvider.future) as SignedIn;
      expect(s.currentOrgId, 'org-a');
      expect(s.isStale, isFalse);
    });

    test('keeps the previously selected org', () async {
      final repo = FakeAuthRepository(
        session: true,
        remote: me(orgs: [orgA, orgB]),
        savedOrg: 'org-b',
      );
      final s = await containerWith(repo).read(sessionControllerProvider.future) as SignedIn;
      expect(s.currentOrg, orgB);
    });

    test('offline with a cached profile → signed in, marked stale', () async {
      final repo = FakeAuthRepository(session: true, cached: me(), fetchError: const NetworkFailure());
      final s = await containerWith(repo).read(sessionControllerProvider.future) as SignedIn;
      expect(s.isStale, isTrue);
      expect(s.me.displayName, 'Ada');
    });

    test('offline without cache → error (splash offers retry)', () async {
      final repo = FakeAuthRepository(session: true, fetchError: const NetworkFailure());
      final c = containerWith(repo);
      await expectLater(c.read(sessionControllerProvider.future), throwsA(isA<NetworkFailure>()));
    });

    test('server rejects the session → signed out with a reason, local data cleared', () async {
      final repo = FakeAuthRepository(
        session: true,
        cached: me(),
        fetchError: const UnauthorizedFailure('expired', code: 'auth.invalid_token'),
      );
      final s = await containerWith(repo).read(sessionControllerProvider.future) as SignedOut;
      expect(s.reason, isNotNull);
      expect(repo.session, isFalse);
      expect(repo.cached, isNull);
    });

    test('failed login leaves state untouched and surfaces the failure', () async {
      final repo = FakeAuthRepository()..loginError = const UnauthorizedFailure('bad');
      final c = containerWith(repo);
      await c.read(sessionControllerProvider.future);
      await expectLater(
        c.read(sessionControllerProvider.notifier).login('a@b.co', 'x'),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(c.read(sessionControllerProvider).value, isA<SignedOut>());
    });

    test('create org selects it; logout signs out', () async {
      final repo = FakeAuthRepository(remote: me(orgs: []));
      final c = containerWith(repo);
      await c.read(sessionControllerProvider.future);
      await c.read(sessionControllerProvider.notifier).login('a@b.co', 'pw');
      expect((c.read(sessionControllerProvider).value! as SignedIn).currentOrgId, isNull);

      await c.read(sessionControllerProvider.notifier).createOrg('New Org');
      final s = c.read(sessionControllerProvider).value! as SignedIn;
      expect(s.currentOrg?.name, 'New Org');
      expect(repo.savedOrg, 'org-new');

      await c.read(sessionControllerProvider.notifier).logout();
      expect(c.read(sessionControllerProvider).value, isA<SignedOut>());
      expect(repo.logoutCalls, 1);
    });

    test('network-layer expiry signs out', () async {
      final c = containerWith(FakeAuthRepository(session: true, remote: me()));
      await c.read(sessionControllerProvider.future);
      c.read(sessionControllerProvider.notifier).onSessionExpired();
      expect(c.read(sessionControllerProvider).value, isA<SignedOut>());
    });
  });
}
