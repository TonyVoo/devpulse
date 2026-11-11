import 'dart:math';

import 'package:devpulse_mobile/core/auth/token_store.dart';
import 'package:devpulse_mobile/core/config/app_config.dart';
import 'package:devpulse_mobile/core/network/api_client.dart';
import 'package:devpulse_mobile/core/network/retry_policy.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const _config = AppConfig(apiBaseUrl: 'http://api.test');

void main() {
  group('RetryPolicy', () {
    const policy = RetryPolicy(base: Duration(milliseconds: 500), cap: Duration(seconds: 4));

    test('full jitter stays within the exponential ceiling', () {
      final rnd = Random(1);
      for (var attempt = 0; attempt < 6; attempt++) {
        final ceiling = min(4000, 500 * pow(2, attempt));
        for (var i = 0; i < 50; i++) {
          final d = policy.delayFor(attempt, random: rnd).inMilliseconds;
          expect(d, inInclusiveRange(0, ceiling));
        }
      }
    });

    test('honours Retry-After, capped', () {
      expect(policy.delayFor(0, retryAfter: const Duration(seconds: 2)), const Duration(seconds: 2));
      expect(policy.delayFor(0, retryAfter: const Duration(minutes: 5)), const Duration(seconds: 4));
    });

    DioException err(String method, DioExceptionType type, [int? status]) => DioException(
      requestOptions: RequestOptions(method: method),
      type: type,
      response: status == null ? null : Response<void>(requestOptions: RequestOptions(), statusCode: status),
    );

    test('retries only idempotent requests on transient errors', () {
      expect(policy.shouldRetry(err('GET', DioExceptionType.connectionError), 0), isTrue);
      expect(policy.shouldRetry(err('GET', DioExceptionType.badResponse, 503), 0), isTrue);
      expect(policy.shouldRetry(err('GET', DioExceptionType.badResponse, 500), 0), isFalse);
      expect(policy.shouldRetry(err('GET', DioExceptionType.badResponse, 404), 0), isFalse);
      expect(policy.shouldRetry(err('POST', DioExceptionType.connectionError), 0), isFalse);
      expect(policy.shouldRetry(err('GET', DioExceptionType.connectionError), 3), isFalse);
    });
  });

  group('Failure.from', () {
    Future<Failure> failureFor(ResponseBody body) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test/'))..httpClientAdapter = FakeAdapter((_) => body);
      try {
        await dio.get<void>('x');
      } on DioException catch (e) {
        return Failure.from(e);
      }
      fail('expected an error');
    }

    test('maps problem+json by status and keeps the code', () async {
      final f = await failureFor(problemBody(401, 'auth.invalid_credentials', 'Email or password is incorrect'));
      expect(f, isA<UnauthorizedFailure>());
      expect(f.code, 'auth.invalid_credentials');
      expect(f.message, 'Email or password is incorrect');
    });

    test('collects field errors from 422', () async {
      final f = await failureFor(
        jsonBody({
          'status': 422,
          'code': 'validation.failed',
          'detail': 'invalid',
          'errors': [
            {
              'loc': ['body', 'password'],
              'msg': 'too short',
              'type': 'x',
            },
          ],
        }, status: 422),
      );
      expect((f as ValidationFailure).fields, {'password': 'too short'});
    });

    test('hides server internals on 5xx', () async {
      final f = await failureFor(problemBody(500, 'internal', 'stack trace here'));
      expect(f, isA<ServerFailure>());
      expect(f.message, isNot(contains('stack')));
    });

    test('connection errors become NetworkFailure', () {
      final f = Failure.from(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError));
      expect(f, isA<NetworkFailure>());
    });
  });

  group('AuthInterceptor', () {
    late InMemoryTokenStore store;
    late int refreshCalls;
    late int expiredCalls;

    setUp(() {
      refreshCalls = 0;
      expiredCalls = 0;
    });

    Dio build(FakeAdapter adapter, {Future<AuthTokens?> Function(String)? refresher}) => createApiDio(
      config: _config,
      store: store,
      onSessionExpired: () => expiredCalls++,
      adapter: adapter,
      refresher:
          refresher ??
          (rt) async {
            refreshCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return tokens('fresh-$refreshCalls', refresh: 'rt-${refreshCalls + 1}');
          },
    );

    ResponseBody authed(RequestOptions o, {String valid = 'fresh-1'}) =>
        o.headers['Authorization'] == 'Bearer $valid' ? jsonBody({'ok': true}) : problemBody(401, 'auth.token_expired');

    test('attaches the bearer token', () async {
      store = InMemoryTokenStore(tokens('a1'));
      final adapter = FakeAdapter((o) => authed(o, valid: 'a1'));
      await build(adapter).get<void>('me');
      expect(adapter.requests.single.headers['Authorization'], 'Bearer a1');
    });

    test('concurrent requests with an expiring token share ONE refresh', () async {
      store = InMemoryTokenStore(tokens('old', expiresIn: const Duration(seconds: 5)));
      final dio = build(FakeAdapter(authed));
      await Future.wait([for (var i = 0; i < 5; i++) dio.get<void>('r$i')]);
      expect(refreshCalls, 1);
      expect((await store.read())!.accessToken, 'fresh-1');
    });

    test('a 401 token_expired triggers one refresh and a replay', () async {
      store = InMemoryTokenStore(tokens('revoked-server-side'));
      final dio = build(FakeAdapter(authed));
      final results = await Future.wait([for (var i = 0; i < 3; i++) dio.get<Map<String, dynamic>>('r$i')]);
      expect(results.every((r) => r.data!['ok'] == true), isTrue);
      expect(refreshCalls, 1);
    });

    test('rejected refresh clears the session and signals expiry', () async {
      store = InMemoryTokenStore(tokens('old', expiresIn: Duration.zero));
      final dio = build(FakeAdapter(authed), refresher: (_) async => null);
      await expectLater(dio.get<void>('me'), throwsA(isA<DioException>()));
      expect(await store.read(), isNull);
      expect(expiredCalls, 1);
    });

    test('offline refresh keeps the session (no sign-out while offline)', () async {
      store = InMemoryTokenStore(tokens('old', expiresIn: Duration.zero));
      final dio = build(
        FakeAdapter((o) => throw DioException.connectionError(requestOptions: o, reason: 'offline')),
        refresher: (_) async => throw DioException.connectionError(requestOptions: RequestOptions(), reason: 'offline'),
      );
      await expectLater(dio.get<void>('me'), throwsA(isA<DioException>()));
      expect(await store.read(), isNotNull);
      expect(expiredCalls, 0);
    });

    test('other 401s are not retried', () async {
      store = InMemoryTokenStore(tokens('a1'));
      final adapter = FakeAdapter((_) => problemBody(401, 'auth.invalid_credentials'));
      await expectLater(build(adapter).post<void>('auth/login'), throwsA(isA<DioException>()));
      expect(refreshCalls, 0);
      expect(adapter.requests, hasLength(1));
    });
  });

  test('AuthTokens.accessExpiringSoon uses a leeway', () {
    final now = DateTime.utc(2026);
    final t = AuthTokens(
      accessToken: 'a',
      refreshToken: 'r',
      accessExpiresAt: now.add(const Duration(seconds: 20)),
      sessionId: 's',
    );
    expect(t.accessExpiringSoon(now: now), isTrue);
    expect(t.accessExpiringSoon(now: now, leeway: const Duration(seconds: 5)), isFalse);
    expect(AuthTokens.fromJson(t.toJson()).accessExpiresAt, t.accessExpiresAt);
  });
}
