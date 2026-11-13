import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'core/design_system/theme.dart';
import 'core/observability/sentry.dart';
import 'l10n/l10n.dart';

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
      locale: ref.watch(localeProvider).value,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Strings used outside widgets (failures, labels) follow the resolved locale.
      builder: (context, child) {
        syncL10nLocale(Localizations.localeOf(context));
        return child!;
      },
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // Dark-first: dark until the user's saved preference loads.
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
