import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/token_store.dart';
import '../core/config/app_config.dart';
import '../core/database/app_database.dart';
import '../core/network/api_client.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/session_controller.dart';

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final dioProvider = Provider<Dio>((ref) {
  return createApiDio(
    config: ref.watch(appConfigProvider),
    store: ref.watch(tokenStoreProvider),
    // Read lazily: the session controller depends on this client too.
    onSessionExpired: () => ref.read(sessionControllerProvider.notifier).onSessionExpired(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ApiAuthRepository(
    dio: ref.watch(dioProvider),
    tokens: ref.watch(tokenStoreProvider),
    db: ref.watch(databaseProvider),
  ),
);

/// User-chosen theme, persisted on device (survives sign-out).
class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final saved = await ref.watch(databaseProvider).readString(KvKeys.theme);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  Future<void> set(ThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(databaseProvider).writeString(KvKeys.theme, mode.name);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// User-chosen language, persisted on device (survives sign-out). `null` follows the
/// phone's language (Vietnamese phones get Vietnamese, everything else English).
class LocaleController extends AsyncNotifier<Locale?> {
  @override
  Future<Locale?> build() async {
    final saved = await ref.watch(databaseProvider).readString(KvKeys.locale);
    return saved == null || saved.isEmpty ? null : Locale(saved);
  }

  Future<void> set(Locale? locale) async {
    state = AsyncData(locale);
    await ref.read(databaseProvider).writeString(KvKeys.locale, locale?.languageCode ?? '');
  }
}

final localeProvider = AsyncNotifierProvider<LocaleController, Locale?>(LocaleController.new);
