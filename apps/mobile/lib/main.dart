import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'core/design_system/theme.dart';
import 'core/observability/sentry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  void run() => runApp(const ProviderScope(child: DevPulseApp()));
  if (sentryDsn.isEmpty) return run();
  await SentryFlutter.init(configureSentry, appRunner: run);
}

class DevPulseApp extends ConsumerWidget {
  const DevPulseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'DevPulse',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // Dark-first: dark until the user's saved preference loads.
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
