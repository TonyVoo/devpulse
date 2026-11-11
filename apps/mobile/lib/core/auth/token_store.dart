import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens issued by the API. Stored only in the platform keystore (Keychain / Android
/// Keystore) — never in SQLite, logs or crash reports.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.sessionId,
  });

  factory AuthTokens.fromApi(Map<String, dynamic> json, {DateTime? now}) {
    final issued = now ?? DateTime.now().toUtc();
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      accessExpiresAt: issued.add(Duration(seconds: json['expires_in'] as int)),
      sessionId: json['session_id'] as String,
    );
  }

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['a'] as String,
    refreshToken: json['r'] as String,
    accessExpiresAt: DateTime.parse(json['e'] as String),
    sessionId: json['s'] as String,
  );

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final String sessionId;

  Map<String, dynamic> toJson() => {
    'a': accessToken,
    'r': refreshToken,
    'e': accessExpiresAt.toIso8601String(),
    's': sessionId,
  };

  /// True when the access token is expired or will be within [leeway].
  bool accessExpiringSoon({Duration leeway = const Duration(seconds: 30), DateTime? now}) =>
      !(now ?? DateTime.now().toUtc()).add(leeway).isBefore(accessExpiresAt);
}

abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  static const _key = 'dp.session.v1';
  final FlutterSecureStorage _storage;

  // In-memory copy so the network layer doesn't hit the keystore on every request.
  AuthTokens? _cache;
  bool _loaded = false;

  @override
  Future<AuthTokens?> read() async {
    if (_loaded) return _cache;
    final raw = await _storage.read(key: _key);
    try {
      _cache = raw == null ? null : AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      _cache = null; // corrupted entry → treat as signed out
    }
    _loaded = true;
    return _cache;
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    _cache = tokens;
    _loaded = true;
    await _storage.write(key: _key, value: jsonEncode(tokens.toJson()));
  }

  @override
  Future<void> clear() async {
    _cache = null;
    _loaded = true;
    await _storage.delete(key: _key);
  }
}

/// For tests and previews.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this._tokens]);

  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> read() async => _tokens;

  @override
  Future<void> write(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
