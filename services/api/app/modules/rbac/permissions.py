"""Fixed roles and permissions (v1). Permission checks happen only via `require_org`."""

from enum import StrEnum


class Role(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    ENGINEER = "engineer"
    VIEWER = "viewer"


class Permission(StrEnum):
    ORG_READ = "org.read"
    ORG_MANAGE = "org.manage"
    ORG_DELETE = "org.delete"
    MEMBERS_MANAGE = "members.manage"
    INTEGRATIONS_MANAGE = "integrations.manage"
    AI_CONFIGURE = "ai.configure"
    ALERT_RULES_MANAGE = "alert_rules.manage"
    SERVICES_MANAGE = "services.manage"
    INCIDENTS_ACT = "incidents.act"
    AI_INVESTIGATE = "ai.investigate"
    AUDIT_READ = "audit.read"


_ENGINEER = {
    Permission.ORG_READ,
    Permission.SERVICES_MANAGE,
    Permission.INCIDENTS_ACT,
    Permission.AI_INVESTIGATE,
}
_ADMIN = _ENGINEER | {
    Permission.ORG_MANAGE,
    Permission.MEMBERS_MANAGE,
    Permission.INTEGRATIONS_MANAGE,
    Permission.AI_CONFIGURE,
    Permission.ALERT_RULES_MANAGE,
    Permission.AUDIT_READ,
}

ROLE_PERMISSIONS: dict[Role, frozenset[Permission]] = {
    Role.OWNER: frozenset(_ADMIN | {Permission.ORG_DELETE}),
    Role.ADMIN: frozenset(_ADMIN),
    Role.ENGINEER: frozenset(_ENGINEER),
    Role.VIEWER: frozenset({Permission.ORG_READ}),
}

# Higher number = more privilege. Used to stop admins granting roles above their own.
ROLE_RANK: dict[Role, int] = {Role.VIEWER: 0, Role.ENGINEER: 1, Role.ADMIN: 2, Role.OWNER: 3}


def has_permission(role: Role, permission: Permission) -> bool:
    return permission in ROLE_PERMISSIONS[role]
