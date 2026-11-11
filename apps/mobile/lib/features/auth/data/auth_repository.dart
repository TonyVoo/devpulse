import 'package:dio/dio.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../../core/result/failure.dart';
import '../domain/models.dart';

/// Authentication and identity data access. Throws [Failure]s only.
abstract interface class AuthRepository {
  Future<bool> hasSession();
  Future<Me> login({required String email, required String password});
  Future<Me> register({required String email, required String password, required String displayName});
  Future<Me> fetchMe();
  Future<Me?> cachedMe();
  Future<OrgMembership> createOrg(String name);
  Future<String?> savedOrgId();
  Future<void> saveOrgId(String orgId);
  Future<void> logout();

  /// Clears local session data without calling the API (server already ended it).
  Future<void> clearLocal();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({required this._dio, required this._tokens, required this._db});

  final Dio _dio;
  final TokenStore _tokens;
  final AppDatabase _db;

  static final _anon = Options(extra: {skipAuthExtra: true});

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object catch (e) {
      throw Failure.from(e);
    }
  }

  @override
  Future<bool> hasSession() async => (await _tokens.read()) != null;

  Future<Me> _signIn(String path, Map<String, dynamic> body) => _guard(() async {
    final r = await _dio.post<Map<String, dynamic>>(path, data: body, options: _anon);
    await _db.clearUserData(); // never mix a previous user's cache with this one
    await _tokens.write(AuthTokens.fromApi(r.data!));
    return fetchMe();
  });

  @override
  Future<Me> login({required String email, required String password}) =>
      _signIn('auth/login', {'email': email.trim(), 'password': password});

  @override
  Future<Me> register({required String email, required String password, required String displayName}) =>
      _signIn('auth/register', {'email': email.trim(), 'password': password, 'display_name': displayName.trim()});

  @override
  Future<Me> fetchMe() => _guard(() async {
    final r = await _dio.get<Map<String, dynamic>>('me');
    final me = Me.fromJson(r.data!);
    await _db.writeJson(KvKeys.me, me.toJson());
    return me;
  });

  @override
  Future<Me?> cachedMe() async {
    final json = await _db.readJson(KvKeys.me);
    return json == null ? null : Me.fromJson(json);
  }

  @override
  Future<OrgMembership> createOrg(String name) => _guard(() async {
    final r = await _dio.post<Map<String, dynamic>>('orgs', data: {'name': name.trim()});
    return OrgMembership.fromJson(r.data!);
  });

  @override
  Future<String?> savedOrgId() => _db.readString(KvKeys.currentOrg);

  @override
  Future<void> saveOrgId(String orgId) => _db.writeString(KvKeys.currentOrg, orgId);

  @override
  Future<void> logout() async {
    try {
      await _dio.post<void>('auth/logout');
    } on Object {
      // Best effort: the local session is cleared regardless (e.g. while offline).
    }
    await clearLocal();
  }

  @override
  Future<void> clearLocal() async {
    await _tokens.clear();
    await _db.clearUserData();
  }
}
