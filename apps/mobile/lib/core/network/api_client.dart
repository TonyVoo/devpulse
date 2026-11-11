import 'package:dio/dio.dart';

import '../auth/token_store.dart';
import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'retry_policy.dart';

BaseOptions _options(AppConfig config) => BaseOptions(
  baseUrl: '${config.apiV1}/',
  connectTimeout: const Duration(seconds: 10),
  sendTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 20),
  headers: {'Accept': 'application/json'},
  contentType: Headers.jsonContentType,
);

/// Bare client for token refresh: no auth interceptor (avoids recursion), no retries.
Dio createRefreshDio(AppConfig config) => Dio(_options(config));

Future<AuthTokens?> refreshWith(Dio bare, String refreshToken) async {
  try {
    final r = await bare.post<Map<String, dynamic>>(
      'auth/refresh',
      data: {'refresh_token': refreshToken},
      options: Options(extra: {skipAuthExtra: true}),
    );
    return AuthTokens.fromApi(r.data!);
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 422) return null; // refresh token is dead
    rethrow; // offline / 5xx: keep the session, try later
  }
}

/// The app's API client. Interceptor order matters: auth first (so retries carry a token),
/// then transient-error retries.
Dio createApiDio({
  required AppConfig config,
  required TokenStore store,
  required void Function() onSessionExpired,
  TokenRefresher? refresher,
  HttpClientAdapter? adapter,
}) {
  final dio = Dio(_options(config));
  if (adapter != null) dio.httpClientAdapter = adapter;
  final bare = createRefreshDio(config);
  if (adapter != null) bare.httpClientAdapter = adapter;
  final auth = AuthInterceptor(
    store: store,
    refresher: refresher ?? (rt) => refreshWith(bare, rt),
    onSessionExpired: onSessionExpired,
  )..dio = dio;
  dio.interceptors
    ..add(auth)
    ..add(RetryInterceptor(dio));
  return dio;
}
