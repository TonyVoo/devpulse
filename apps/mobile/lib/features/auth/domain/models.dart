import 'package:flutter/foundation.dart';

enum OrgRole {
  owner,
  admin,
  engineer,
  viewer;

  static OrgRole parse(String value) => OrgRole.values.firstWhere((r) => r.name == value, orElse: () => OrgRole.viewer);

  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

@immutable
class OrgMembership {
  const OrgMembership({required this.id, required this.slug, required this.name, required this.role});

  factory OrgMembership.fromJson(Map<String, dynamic> j) => OrgMembership(
    id: j['id'] as String,
    slug: j['slug'] as String,
    name: j['name'] as String,
    role: OrgRole.parse(j['role'] as String),
  );

  final String id;
  final String slug;
  final String name;
  final OrgRole role;

  Map<String, dynamic> toJson() => {'id': id, 'slug': slug, 'name': name, 'role': role.name};

  @override
  bool operator ==(Object other) =>
      other is OrgMembership && other.id == id && other.name == name && other.role == role;

  @override
  int get hashCode => Object.hash(id, name, role);
}

/// The signed-in user and their organizations (`GET /me`).
@immutable
class Me {
  const Me({required this.id, required this.email, required this.displayName, required this.memberships});

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    email: j['email'] as String,
    displayName: j['display_name'] as String,
    memberships: [
      for (final m in (j['memberships'] as List<dynamic>? ?? const []))
        OrgMembership.fromJson(m as Map<String, dynamic>),
    ],
  );

  final String id;
  final String email;
  final String displayName;
  final List<OrgMembership> memberships;

  OrgMembership? org(String? id) {
    for (final m in memberships) {
      if (m.id == id) return m;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'memberships': [for (final m in memberships) m.toJson()],
  };
}

sealed class SessionState {
  const SessionState();
}

final class SignedOut extends SessionState {
  const SignedOut({this.reason});

  /// Shown on the login screen, e.g. "Your session has ended".
  final String? reason;
}

final class SignedIn extends SessionState {
  const SignedIn({required this.me, required this.currentOrgId, this.isStale = false});

  final Me me;

  /// Null until the user has picked (or created) an organization.
  final String? currentOrgId;

  /// True when restored from the local cache because the API was unreachable.
  final bool isStale;

  OrgMembership? get currentOrg => me.org(currentOrgId);

  SignedIn copyWith({Me? me, String? currentOrgId, bool? isStale}) =>
      SignedIn(me: me ?? this.me, currentOrgId: currentOrgId ?? this.currentOrgId, isStale: isStale ?? this.isStale);
}
