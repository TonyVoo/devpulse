from datetime import UTC, datetime

from fastapi import APIRouter, status
from sqlalchemy import select

from app.core.deps import CurrentUserDep, SessionDep
from app.modules.organizations.service import list_user_orgs
from app.modules.users.models import Device
from app.modules.users.schemas import (
    DeviceIn,
    DeviceOut,
    MeOut,
    OrgSummary,
    UpdateMeIn,
    UserOut,
)

router = APIRouter(prefix="/me", tags=["me"])


@router.get("", response_model=MeOut)
async def get_me(current: CurrentUserDep, session: SessionDep) -> MeOut:
    orgs = await list_user_orgs(session, current.id)
    return MeOut(
        **UserOut.model_validate(current.user).model_dump(),
        memberships=[OrgSummary(id=o.id, slug=o.slug, name=o.name, role=o.role) for o in orgs],
    )


@router.patch("", response_model=UserOut)
async def update_me(body: UpdateMeIn, current: CurrentUserDep, session: SessionDep) -> UserOut:
    user = current.user
    for field, value in body.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(user, field, value)
    await session.commit()
    await session.refresh(user)
    return UserOut.model_validate(user)


@router.post("/devices", response_model=DeviceOut, status_code=status.HTTP_201_CREATED)
async def register_device(body: DeviceIn, current: CurrentUserDep, session: SessionDep) -> Device:
    """Idempotent upsert keyed by FCM token. A token moving to another user is re-assigned
    (the same physical device signed in as someone else)."""
    device = await session.scalar(select(Device).where(Device.fcm_token == body.fcm_token))
    now = datetime.now(UTC)
    if device is None:
        device = Device(user_id=current.id, **body.model_dump(), last_seen_at=now)
        session.add(device)
    else:
        device.user_id = current.id
        device.platform = body.platform
        device.app_version = body.app_version
        device.last_seen_at = now
    await session.commit()
    await session.refresh(device)
    return device
