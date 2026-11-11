import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/token_store.dart';
import '../result/failure.dart';

/// Returns new tokens, `null` when the refresh token is rejected (session over), or throws
/// on transient errors (offline) — which must NOT sign the user out.
typedef TokenRefresher = Future<AuthTokens?> Function(String refreshToken);

/// Mark a request as unauthenticated (login, register, refresh).
const skipAuthExtra = 'dp_skip_auth';

/// Attaches the bearer token and keeps it fresh.
///
/// * Proactive: refreshes before sending when the token expires within 30s.
/// * Reactive: on `401 auth.token_expired` refreshes and replays once.
/// * Single-flight: concurrent requests share one refresh call. The API rotates refresh
///   tokens and treats reuse outside a short grace window as theft, so parallel refreshes
///   must be avoided.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({required this._store, required this._refresher, required this._onSessionExpired});

  final TokenStore _store;
  final TokenRefresher _refresher;
  final void Function() _onSessionExpired;

  /// The Dio instance used to replay requests. Set by the owner after construction.
  late Dio dio;

  Future<AuthTokens?>? _inflight;

  static const _retriedExtra = 'dp_auth_retried';
  static const _refreshableCodes = {'auth.token_expired', 'auth.session_revoked'};

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[skipAuthExtra] == true) return handler.next(options);
    var tokens = await _store.read();
    if (tokens == null) return handler.next(options);
    if (tokens.accessExpiringSoon()) {
      try {
        tokens = await _refreshOnce(tokens);
      } on Object catch (e) {
        // Offline: send with the current token and let the request fail/succeed on its own;
        // repositories fall back to the local cache. Anything else rejects this request.
        if (Failure.from(e) is! NetworkFailure) {
          return handler.reject(DioException(requestOptions: options, error: Failure.from(e)));
        }
      }
      if (tokens == null) {
        return handler.reject(
          DioException(
            requestOptions: options,
            error: const UnauthorizedFailure('Your session has ended. Sign in again.', code: 'auth.session_ended'),
          ),
        );
      }
    }
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final data = err.response?.data;
    final code = data is Map<String, dynamic> ? data['code'] : null;
    if (err.response?.statusCode != 401 ||
        !_refreshableCodes.contains(code) ||
        options.extra[skipAuthExtra] == true ||
        options.extra[_retriedExtra] == true) {
      return handler.next(err);
    }

    final current = await _store.read();
    if (current == null) return handler.next(err);

    AuthTokens? fresh;
    final usedHeader = options.headers['Authorization'];
    if (usedHeader != 'Bearer ${current.accessToken}') {
      fresh = current; // another request already refreshed while this one was in flight
    } else {
      try {
        fresh = await _refreshOnce(current);
      } on Object {
        return handler.next(err);
      }
    }
    if (fresh == null) return handler.next(err);

    options
      ..extra[_retriedExtra] = true
      ..headers['Authorization'] = 'Bearer ${fresh.accessToken}';
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<AuthTokens?> _refreshOnce(AuthTokens current) {
    return _inflight ??= _doRefresh(current).whenComplete(() {
      _inflight = null;
    });
  }

  Future<AuthTokens?> _doRefresh(AuthTokens current) async {
    final fresh = await _refresher(current.refreshToken);
    if (fresh == null) {
      await _store.clear();
      _onSessionExpired();
      return null;
    }
    await _store.write(fresh);
    return fresh;
  }
}
