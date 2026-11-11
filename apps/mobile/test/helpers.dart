import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:devpulse_mobile/core/auth/token_store.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/auth/data/auth_repository.dart';
import 'package:devpulse_mobile/features/auth/domain/models.dart';
import 'package:dio/dio.dart';

typedef Handler = FutureOr<ResponseBody> Function(RequestOptions options);

/// Scriptable Dio transport for tests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Handler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? body, {int status = 200, Map<String, List<String>>? headers}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...?headers,
  },
);

ResponseBody problemBody(int status, String code, [String detail = 'error']) =>
    jsonBody({'status': status, 'code': code, 'detail': detail, 'title': detail}, status: status);

AuthTokens tokens(String access, {Duration expiresIn = const Duration(minutes: 15), String refresh = 'rt-1'}) =>
    AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      accessExpiresAt: DateTime.now().toUtc().add(expiresIn),
      sessionId: 'sess-1',
    );

const orgA = OrgMembership(id: 'org-a', slug: 'acme', name: 'Acme', role: OrgRole.owner);
const orgB = OrgMembership(id: 'org-b', slug: 'bravo', name: 'Bravo', role: OrgRole.viewer);

Me me({List<OrgMembership> orgs = const [orgA]}) =>
    Me(id: 'u1', email: 'ada@example.com', displayName: 'Ada', memberships: orgs);

/// In-memory [AuthRepository] with scriptable failures.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.session = false, this.remote, this.cached, this.fetchError, this.savedOrg});

  bool session;
  Me? remote;
  Me? cached;
  Failure? fetchError;
  Failure? loginError;
  String? savedOrg;
  int logoutCalls = 0;

  @override
  Future<bool> hasSession() async => session;

  @override
  Future<Me> fetchMe() async {
    if (fetchError != null) throw fetchError!;
    cached = remote;
    return remote!;
  }

  @override
  Future<Me?> cachedMe() async => cached;

  @override
  Future<Me> login({required String email, required String password}) async {
    if (loginError != null) throw loginError!;
    session = true;
    return fetchMe();
  }

  @override
  Future<Me> register({required String email, required String password, required String displayName}) =>
      login(email: email, password: password);

  @override
  Future<OrgMembership> createOrg(String name) async {
    final org = OrgMembership(id: 'org-new', slug: 'new', name: name, role: OrgRole.owner);
    remote = me(orgs: [...?remote?.memberships, org]);
    return org;
  }

  @override
  Future<String?> savedOrgId() async => savedOrg;

  @override
  Future<void> saveOrgId(String orgId) async => savedOrg = orgId;

  @override
  Future<void> logout() async {
    logoutCalls++;
    await clearLocal();
  }

  @override
  Future<void> clearLocal() async {
    session = false;
    cached = null;
    savedOrg = null;
  }
}
