import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/models.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/auth/presentation/org_select_screen.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/placeholders.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const orgs = '/orgs';
  static const overview = '/overview';
  static const services = '/services';
  static const incidents = '/incidents';
  static const copilot = '/copilot';
  static const settings = '/settings';

  static const _public = {login, register};
}

/// Pure redirect rule (unit-tested). `location` is the full URI being navigated to.
///
/// * Restoring → splash. * Signed out → login, remembering where the user was going
///   (deep links / push taps survive sign-in). * Signed in without an org → org picker.
String? resolveRedirect(AsyncValue<SessionState> session, Uri location) {
  final path = location.path;
  final value = session.value;

  if (value == null) {
    // First restore still loading, or failed before producing a value.
    return path == Routes.splash ? null : Routes.splash;
  }

  if (value is SignedOut) {
    if (Routes._public.contains(path)) return null;
    final intended = path == Routes.splash || path == '/' ? null : location.toString();
    return intended == null ? Routes.login : '${Routes.login}?from=${Uri.encodeComponent(intended)}';
  }

  final signedIn = value as SignedIn;
  if (signedIn.currentOrg == null) return path == Routes.orgs ? null : Routes.orgs;

  if (path == Routes.splash || path == '/' || Routes._public.contains(path)) {
    final from = location.queryParameters['from'];
    return (from != null && from.startsWith('/') && !from.startsWith('//')) ? from : Routes.overview;
  }
  return null;
}

/// Bridges Riverpod session changes to GoRouter's `refreshListenable`.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionControllerProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable(ref);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) => resolveRedirect(ref.read(sessionControllerProvider), state.uri),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: Routes.login,
        builder: (_, state) => AuthScreen(mode: AuthMode.login, from: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: Routes.register,
        builder: (_, _) => const AuthScreen(mode: AuthMode.register),
      ),
      GoRoute(path: Routes.orgs, builder: (_, _) => const OrgSelectScreen()),
      // Each tab keeps its own navigation stack and scroll/filter state.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.overview, builder: (_, _) => const OverviewScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.services, builder: (_, _) => const ServicesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.incidents, builder: (_, _) => const IncidentsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.copilot, builder: (_, _) => const CopilotScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(body: Center(child: Text('Page not found: ${state.uri.path}'))),
  );
  ref.onDispose(router.dispose);
  return router;
});
