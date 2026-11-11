import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../result/failure.dart';

/// A page from a cursor-paginated endpoint.
class Paged<T> {
  const Paged(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;
}

/// Thin typed wrapper for org-scoped endpoints. Maps every error to a [Failure].
class OrgApi {
  OrgApi(this._dio, this.orgId);

  final Dio _dio;
  final String orgId;
  static const _uuid = Uuid();

  String _p(String path) => 'orgs/$orgId/$path';

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object catch (e) {
      throw Failure.from(e);
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) => _guard(() async {
    final r = await _dio.get<Map<String, dynamic>>(_p(path), queryParameters: query);
    return r.data!;
  });

  Future<List<dynamic>> getList(String path, {Map<String, dynamic>? query}) => _guard(() async {
    final r = await _dio.get<List<dynamic>>(_p(path), queryParameters: query);
    return r.data!;
  });

  Future<Paged<T>> page<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, dynamic>? query,
    String? cursor,
  }) async {
    final body = await get(path, query: {...?query, 'cursor': ?cursor});
    return Paged([
      for (final i in body['items'] as List<dynamic>) parse(i as Map<String, dynamic>),
    ], body['next_cursor'] as String?);
  }

  /// State-changing command. Always sends an Idempotency-Key (safe to retry) and, when
  /// known, the version the user was looking at (`If-Match`) so stale actions are rejected.
  Future<Map<String, dynamic>> command(String path, {Object? body, int? ifMatchVersion, String? idempotencyKey}) =>
      _guard(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          _p(path),
          data: body ?? const <String, dynamic>{},
          options: Options(
            headers: {
              'Idempotency-Key': idempotencyKey ?? _uuid.v4(),
              'If-Match': ?(ifMatchVersion == null ? null : '"$ifMatchVersion"'),
            },
          ),
        );
        return r.data!;
      });

  static String newClientId() => _uuid.v4();
}
