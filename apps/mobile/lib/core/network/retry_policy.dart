import 'dart:math';

import 'package:dio/dio.dart';

/// Exponential backoff with full jitter (AWS architecture blog): delay is uniformly random
/// in `[0, min(cap, base * 2^attempt)]`. Spreads retries so clients don't stampede a
/// recovering server.
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.base = const Duration(milliseconds: 500),
    this.cap = const Duration(seconds: 30),
  });

  final int maxAttempts;
  final Duration base;
  final Duration cap;

  Duration delayFor(int attempt, {Random? random, Duration? retryAfter}) {
    if (retryAfter != null) return retryAfter > cap ? cap : retryAfter;
    final exp = base.inMilliseconds * pow(2, attempt);
    final ceiling = min(cap.inMilliseconds.toDouble(), exp.toDouble());
    return Duration(milliseconds: ((random ?? Random()).nextDouble() * ceiling).round());
  }

  /// Only idempotent requests are retried automatically, and only for transient errors.
  /// Mutations go through the offline outbox (Phase 3), which uses idempotency keys.
  bool shouldRetry(DioException e, int attempt) {
    if (attempt >= maxAttempts) return false;
    final method = e.requestOptions.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') return false;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.transformTimeout:
        return false;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        return status == 429 || status == 502 || status == 503 || status == 504;
      case DioExceptionType.sendTimeout:
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }

  static Duration? parseRetryAfter(Response<dynamic>? response) {
    final value = response?.headers.value('retry-after');
    final seconds = value == null ? null : int.tryParse(value);
    return seconds == null ? null : Duration(seconds: seconds);
  }
}

/// Dio interceptor applying [RetryPolicy]. Install before the auth interceptor's retry so
/// that a refreshed request is not double-retried.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.policy = const RetryPolicy(), Future<void> Function(Duration)? sleep})
    : _sleep = sleep ?? Future<void>.delayed;

  final Dio _dio;
  final RetryPolicy policy;
  final Future<void> Function(Duration) _sleep;

  static const _attemptKey = 'dp_retry_attempt';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (!policy.shouldRetry(err, attempt)) return handler.next(err);
    await _sleep(policy.delayFor(attempt, retryAfter: RetryPolicy.parseRetryAfter(err.response)));
    final options = err.requestOptions..extra[_attemptKey] = attempt + 1;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
