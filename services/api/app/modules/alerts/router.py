from datetime import UTC, datetime, timedelta
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, status
from sqlalchemy import select

from app.core.deps import RequestMetaDep, SessionDep
from app.core.errors import NotFound
from app.core.tenancy import OrgContext, OrgScopedRepository, require_org
from app.modules.alerts.evaluator import breached, compute_value
from app.modules.alerts.models import AlertInstance, AlertRule, AlertState
from app.modules.alerts.schemas import (
    AlertRuleIn,
    AlertRuleOut,
    AlertRuleUpdateIn,
    PreviewOut,
    PreviewPoint,
    _check_metric,
)
from app.modules.audit.service import record
from app.modules.rbac.permissions import Permission
from app.modules.services.service import ServiceCatalog, check_version

router = APIRouter(prefix="/orgs/{org_id}/alert-rules", tags=["alerts"])

Read = Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))]
Manage = Annotated[OrgContext, Depends(require_org(Permission.ALERT_RULES_MANAGE))]


class AlertRules(OrgScopedRepository):
    async def get(self, rule_id: UUID) -> AlertRule:
        rule = await self.session.scalar(self.select(AlertRule).where(AlertRule.id == rule_id))
        if rule is None:
            raise NotFound("Alert rule not found", code="alert_rule.not_found")
        return rule

    async def with_state(self, rules: list[AlertRule]) -> list[AlertRuleOut]:
        ids = [r.id for r in rules]
        open_states = (
            {
                i.rule_id: i
                for i in (
                    await self.session.scalars(
                        select(AlertInstance).where(
                            AlertInstance.rule_id.in_(ids),
                            AlertInstance.state != AlertState.RESOLVED,
                        )
                    )
                ).all()
            }
            if ids
            else {}
        )
        out = []
        for r in rules:
            o = AlertRuleOut.model_validate(r)
            inst = open_states.get(r.id)
            if inst is not None:
                o.state, o.last_value = inst.state, inst.last_value
            out.append(o)
        return out


@router.get("", response_model=list[AlertRuleOut])
async def list_rules(
    ctx: Read, session: SessionDep, service_id: UUID | None = None
) -> list[AlertRuleOut]:
    repo = AlertRules(session, ctx)
    stmt = repo.select(AlertRule).order_by(AlertRule.name)
    if service_id:
        stmt = stmt.where(AlertRule.service_id == service_id)
    return await repo.with_state(list((await session.scalars(stmt)).all()))


@router.post("", response_model=AlertRuleOut, status_code=status.HTTP_201_CREATED)
async def create_rule(
    body: AlertRuleIn, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> AlertRuleOut:
    await ServiceCatalog(session, ctx).get(body.service_id)
    rule = AlertRule(org_id=ctx.org_id, created_by=ctx.user_id, **body.model_dump())
    session.add(rule)
    await session.flush()
    record(
        session,
        org_id=ctx.org_id,
        actor_id=ctx.user_id,
        action="alert_rule.created",
        target_type="alert_rule",
        target_id=rule.id,
        after=body.model_dump(mode="json"),
        meta=meta,
    )
    await session.commit()
    await session.refresh(rule)
    return AlertRuleOut.model_validate(rule)


@router.get("/{rule_id}", response_model=AlertRuleOut)
async def get_rule(rule_id: UUID, ctx: Read, session: SessionDep) -> AlertRuleOut:
    repo = AlertRules(session, ctx)
    return (await repo.with_state([await repo.get(rule_id)]))[0]


@router.patch("/{rule_id}", response_model=AlertRuleOut)
async def update_rule(
    rule_id: UUID,
    body: AlertRuleUpdateIn,
    ctx: Manage,
    session: SessionDep,
    meta: RequestMetaDep,
    if_match: Annotated[str | None, Header()] = None,
) -> AlertRuleOut:
    repo = AlertRules(session, ctx)
    rule = await repo.get(rule_id)
    check_version(rule.version, if_match)
    changes: dict[str, Any] = body.model_dump(exclude_unset=True)
    _check_metric(changes.get("metric", rule.metric), changes.get("aggregation", rule.aggregation))
    for k, v in changes.items():
        setattr(rule, k, v)
    if changes:
        rule.version += 1
        record(
            session,
            org_id=ctx.org_id,
            actor_id=ctx.user_id,
            action="alert_rule.updated",
            target_type="alert_rule",
            target_id=rule.id,
            after=AlertRuleUpdateIn(**changes).model_dump(mode="json", exclude_unset=True),
            meta=meta,
        )
        await session.commit()
        await session.refresh(rule)
    return (await repo.with_state([rule]))[0]


@router.delete("/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_rule(
    rule_id: UUID, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> None:
    rule = await AlertRules(session, ctx).get(rule_id)
    await session.delete(rule)
    record(
        session,
        org_id=ctx.org_id,
        actor_id=ctx.user_id,
        action="alert_rule.deleted",
        target_type="alert_rule",
        target_id=rule_id,
        meta=meta,
    )
    await session.commit()


async def _replay(session: SessionDep, rule: AlertRule, hours: int) -> PreviewOut:
    """Replays a rule over recent raw data (every 5 minutes) without changing any state."""
    now = datetime.now(UTC).replace(second=0, microsecond=0)
    points = []
    for i in range(hours * 12, -1, -1):
        at = now - timedelta(minutes=5 * i)
        value = await compute_value(session, rule, end=at)
        points.append(
            PreviewPoint(
                at=at,
                value=value,
                breached=value is not None and breached(value, rule.comparator, rule.threshold),
            )
        )
    windows = sum(
        1
        for prev, cur in zip([None, *points], points, strict=False)
        if cur.breached and not (prev and prev.breached)
    )
    return PreviewOut(points=points, breach_windows=windows)


@router.post("/preview", response_model=PreviewOut)
async def preview_draft(
    body: AlertRuleIn,
    ctx: Read,
    session: SessionDep,
    hours: Annotated[int, Query(ge=1, le=24)] = 6,
) -> PreviewOut:
    """Preview an unsaved rule (rule builder). Read-only; nothing is stored."""
    await ServiceCatalog(session, ctx).get(body.service_id)  # 404 for other orgs' services
    draft = AlertRule(org_id=ctx.org_id, **body.model_dump())
    return await _replay(session, draft, hours)


@router.post("/{rule_id}/preview", response_model=PreviewOut)
async def preview_rule(
    rule_id: UUID,
    ctx: Read,
    session: SessionDep,
    hours: Annotated[int, Query(ge=1, le=24)] = 24,
) -> PreviewOut:
    """Would this saved rule have fired recently?"""
    rule = await AlertRules(session, ctx).get(rule_id)
    return await _replay(session, rule, hours)
