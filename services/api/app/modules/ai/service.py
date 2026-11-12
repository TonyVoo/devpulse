"""API-facing AI operations: reads, follow-up chat, proposal decisions, settings, usage."""

import asyncio
import json
from dataclasses import replace
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import Date, and_, cast, func, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import Conflict, Forbidden, NotFound, Unprocessable
from app.core.pagination import MAX_LIMIT, Page, decode_cursor, encode_cursor
from app.core.ratelimit import enforce_rate_limit
from app.core.redis import get_redis
from app.core.tenancy import OrgContext, OrgScopedRepository
from app.modules.ai import pipeline, providers
from app.modules.ai.evidence import Redactor
from app.modules.ai.models import (
    AIActionProposal,
    AIEvidence,
    AIFeedback,
    AIInvestigation,
    AIMessage,
    AISettings,
    AIUsage,
    MessageRole,
    ProposalStatus,
    Risk,
    RunStatus,
    Trigger,
)
from app.modules.ai.output import ANSWER_SCHEMA, Analysis, InvalidOutput, validate_answer
from app.modules.ai.pipeline import (
    AIFailed,
    CallFailed,
    call_provider,
    effective,
    evidence_row,
    guard,
    incident_context,
    load_settings,
    prompt,
    registry_from_rows,
    render_context,
    repair_text,
    service_slug,
    start_investigation,
)
from app.modules.ai.providers.base import LLMRequest, Message, ToolResult
from app.modules.ai.schemas import (
    AISettingsIn,
    AISettingsOut,
    AskIn,
    AskOut,
    DecisionIn,
    EvidenceOut,
    FeedbackIn,
    InvestigationOut,
    InvestigationSummary,
    MessageOut,
    ProposalOut,
    ProviderInfo,
    RedactionSettings,
    UsageDay,
    UsageOut,
)
from app.modules.ai.tools import (
    MAX_CALLS_PER_INVESTIGATION,
    MAX_CALLS_PER_TURN,
    TOOLS,
    ToolExecutor,
)
from app.modules.ai.usage import month_start, month_to_date_cost
from app.modules.audit.service import record
from app.modules.incidents.models import ActorType, EventType, Incident
from app.modules.incidents.service import IncidentService, add_event
from app.modules.rbac.permissions import Permission

CHAT_PROMPT = "chat_v1"
MAX_TOOL_ROUNDS = 8
CHAT_MAX_OUTPUT_TOKENS = 8_000


def _evidence_out(e: AIEvidence) -> EvidenceOut:
    return EvidenceOut(
        ref=e.ref,
        kind=e.kind,
        title=e.title,
        excerpt=e.excerpt,
        source_query=e.source_query,
        observed_at=e.observed_at,
    )


def _proposal_out(p: AIActionProposal) -> ProposalOut:
    return ProposalOut(
        id=p.id,
        kind=p.kind,
        description=p.description,
        risk=p.risk,
        status=p.status,
        decided_by=p.decided_by,
        decided_at=p.decided_at,
        decision_note=p.decision_note,
    )


def _message_out(m: AIMessage) -> MessageOut:
    return MessageOut(
        id=m.id,
        role=m.role,
        content=m.content,
        evidence_refs=m.evidence_refs,
        tool_name=m.tool_name,
        author_id=m.author_id,
        client_id=m.client_id,
        created_at=m.created_at,
    )


def _summary(inv: AIInvestigation, inc: Incident) -> InvestigationSummary:
    return InvestigationSummary(
        id=inv.id,
        incident_id=inc.id,
        incident_key=inc.key,
        incident_title=inc.title,
        incident_severity=inc.severity,
        trigger=inv.trigger,
        status=inv.status,
        provider=inv.provider,
        model=inv.model,
        is_demo_provider=inv.provider == "fake",
        summary=(inv.result or {}).get("summary"),
        error_code=inv.error_code,
        created_at=inv.created_at,
        finished_at=inv.finished_at,
    )


class AIService(OrgScopedRepository):
    def __init__(self, session: AsyncSession, ctx: OrgContext) -> None:
        super().__init__(session, ctx)

    # --------------------------------------------------------------------- reads

    async def _inv(self, inv_id: UUID, *, lock: bool = False) -> tuple[AIInvestigation, Incident]:
        stmt = (
            select(AIInvestigation, Incident)
            .join(Incident, Incident.id == AIInvestigation.incident_id)
            .where(AIInvestigation.org_id == self.ctx.org_id, AIInvestigation.id == inv_id)
        )
        if lock:
            stmt = stmt.with_for_update(of=AIInvestigation)
        row = (await self.session.execute(stmt)).first()
        if row is None:
            raise NotFound("Investigation not found", code="ai.investigation_not_found")
        return row[0], row[1]

    async def get(self, inv_id: UUID) -> InvestigationOut:
        inv, inc = await self._inv(inv_id)
        return await self._out(inv, inc)

    async def _out(self, inv: AIInvestigation, inc: Incident) -> InvestigationOut:
        evidence = (
            await self.session.scalars(
                self.select(AIEvidence).where(AIEvidence.investigation_id == inv.id)
            )
        ).all()
        proposals = (
            await self.session.scalars(
                self.select(AIActionProposal)
                .where(AIActionProposal.investigation_id == inv.id)
                .order_by(AIActionProposal.created_at)
            )
        ).all()
        mine = (
            await self.session.scalar(
                select(AIFeedback.helpful).where(
                    AIFeedback.investigation_id == inv.id, AIFeedback.user_id == self.ctx.user_id
                )
            )
            if self.ctx.user_id
            else None
        )
        return InvestigationOut(
            **_summary(inv, inc).model_dump(),
            prompt_version=inv.prompt_version,
            result=Analysis.model_validate(inv.result) if inv.result else None,
            data_gaps=inv.data_gaps,
            error_detail=inv.error_detail,
            evidence=[_evidence_out(e) for e in sorted(evidence, key=lambda e: int(e.ref[3:]))],
            proposals=[_proposal_out(p) for p in proposals],
            tool_calls_used=inv.tool_calls_used,
            tokens_used=inv.tokens_used,
            started_at=inv.started_at,
            requested_by=inv.requested_by,
            my_feedback=mine,
        )

    async def for_incident(self, ref: str) -> list[InvestigationSummary]:
        inc = await IncidentService(self.session, self.ctx)._load(ref)
        rows = (
            await self.session.scalars(
                self.select(AIInvestigation)
                .where(AIInvestigation.incident_id == inc.id)
                .order_by(AIInvestigation.created_at.desc())
                .limit(20)
            )
        ).all()
        return [_summary(r, inc) for r in rows]

    async def page(self, *, limit: int, cursor: str | None) -> Page[InvestigationSummary]:
        limit = max(1, min(limit, MAX_LIMIT))
        stmt = (
            select(AIInvestigation, Incident)
            .join(Incident, Incident.id == AIInvestigation.incident_id)
            .where(AIInvestigation.org_id == self.ctx.org_id)
        )
        if cursor:
            ts, last = decode_cursor(cursor)
            stmt = stmt.where(
                or_(
                    AIInvestigation.created_at < ts,
                    and_(AIInvestigation.created_at == ts, AIInvestigation.id < last),
                )
            )
        rows = (
            await self.session.execute(
                stmt.order_by(AIInvestigation.created_at.desc(), AIInvestigation.id.desc()).limit(
                    limit + 1
                )
            )
        ).all()
        items = [_summary(i, inc) for i, inc in rows[:limit]]
        nxt = encode_cursor(items[-1].created_at, items[-1].id) if len(rows) > limit else None
        return Page(items=items, next_cursor=nxt)

    async def messages(self, inv_id: UUID) -> list[MessageOut]:
        inv, _ = await self._inv(inv_id)
        rows = (
            await self.session.scalars(
                self.select(AIMessage)
                .where(AIMessage.investigation_id == inv.id)
                .order_by(AIMessage.created_at, AIMessage.id)
            )
        ).all()
        return [_message_out(m) for m in rows]

    # ---------------------------------------------------------------------- start

    async def _spend_limit(self, scope: str, limit: int) -> None:
        """AI calls cost money: cap them per user (in addition to the org's budget)."""
        await enforce_rate_limit(
            get_redis(),
            scope=scope,
            key=str(self.ctx.user_id),
            limit=limit,
            window_s=600,
            message="Too many AI requests, try again in a few minutes",
        )

    async def start(self, ref: str) -> InvestigationOut:
        await self._spend_limit("ai_start", get_settings().ai_start_rate_limit)
        inc = await IncidentService(self.session, self.ctx)._load(ref)
        inv = await start_investigation(
            self.session, inc, trigger=Trigger.MANUAL, requested_by=self.ctx.user_id
        )
        if inv is None:  # manual triggers raise instead; defensive
            raise Conflict("Could not start the investigation", code="ai.not_started")
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="ai.investigation_started",
            target_type="incident",
            target_id=inc.id,
            after={"investigation_id": str(inv.id), "provider": inv.provider, "model": inv.model},
        )
        await self.session.commit()
        pipeline.enqueue(inv.id)
        return await self._out(inv, inc)

    # ----------------------------------------------------------------------- chat

    async def ask(self, inv_id: UUID, body: AskIn) -> AskOut:
        inv, inc = await self._inv(inv_id, lock=True)
        replay = await self._replay(inv, body.client_id)
        if replay is not None:
            return replay  # retries of an answered question are free
        await self._spend_limit("ai_ask", get_settings().ai_ask_rate_limit)
        if inv.status != RunStatus.SUCCEEDED:
            raise Conflict("Follow-up questions need a finished analysis", code="ai.not_ready")
        st = await load_settings(self.session, inv.org_id)
        await guard(self.session, inv.org_id, st)
        # Follow-ups use the run's own provider/model, even if settings changed since.

        rows = list(
            (
                await self.session.scalars(
                    self.select(AIEvidence).where(AIEvidence.investigation_id == inv.id)
                )
            ).all()
        )
        reg = registry_from_rows(rows)
        known_before = reg.next_index
        redact = Redactor.from_settings(st.data_redaction)
        slug = await service_slug(self.session, inc)
        context = incident_context(inc, slug, redact, reg.items, inv.data_gaps)
        history = (
            await self.session.scalars(
                self.select(AIMessage)
                .where(
                    AIMessage.investigation_id == inv.id,
                    AIMessage.role.in_([MessageRole.USER, MessageRole.ASSISTANT]),
                )
                .order_by(AIMessage.created_at, AIMessage.id)
            )
        ).all()
        messages = [
            Message("user", text=render_context(context)),
            Message("assistant", text=json.dumps(inv.result)),
        ]
        for m in history:
            messages.append(
                Message("user" if m.role == MessageRole.USER else "assistant", text=m.content)
            )
        messages.append(Message("user", text=body.question))

        provider = providers.get_provider(inv.provider)
        executor = ToolExecutor(self.session, inv.org_id, reg, redact, datetime.now(UTC))
        request = LLMRequest(
            model=inv.model,
            system=prompt(CHAT_PROMPT),
            messages=messages,
            tools=TOOLS,
            response_schema=ANSWER_SCHEMA,
            max_output_tokens=CHAT_MAX_OUTPUT_TOKENS,
            context={**context, "question": body.question},
            purpose="chat",
        )
        usage_rows: list[AIUsage] = []
        tool_msgs: list[AIMessage] = []
        turn_left = MAX_CALLS_PER_TURN
        total_left = MAX_CALLS_PER_INVESTIGATION - inv.tool_calls_used
        tool_calls_used = inv.tool_calls_used
        tokens_before = inv.tokens_used
        answer = None
        try:
            async with asyncio.timeout(get_settings().ai_run_timeout_s):
                repaired = False
                for attempt in range(1, MAX_TOOL_ROUNDS + 1):
                    result, row = await call_provider(provider, request, inv=inv, attempt=attempt)
                    usage_rows.append(row)
                    if not result.tool_calls:
                        try:
                            answer = validate_answer(result.text, known_refs=reg.refs)
                            break
                        except InvalidOutput as e:
                            row.outcome = "invalid_output"
                            if repaired:
                                raise AIFailed(
                                    "The answer failed validation", code="ai.invalid_output"
                                ) from e
                            repaired = True
                            messages = [
                                *messages,
                                Message("assistant", text=result.text, raw=result.raw),
                                Message("user", text=repair_text(e.errors)),
                            ]
                            request = replace(request, messages=messages)
                            continue
                    results: list[ToolResult] = []
                    for call in result.tool_calls:
                        if turn_left <= 0 or total_left <= 0:
                            results.append(
                                ToolResult(
                                    call.id,
                                    json.dumps(
                                        {
                                            "error": "Tool budget exhausted; answer with the "
                                            "evidence you have."
                                        }
                                    ),
                                    is_error=True,
                                )
                            )
                            continue
                        turn_left -= 1
                        total_left -= 1
                        tool_calls_used += 1
                        start_idx = reg.next_index
                        r = await executor.run(call)
                        results.append(r)
                        tool_msgs.append(
                            AIMessage(
                                org_id=inv.org_id,
                                investigation_id=inv.id,
                                role=MessageRole.TOOL,
                                tool_name=call.name,
                                content=json.dumps(
                                    {"input": call.input, "error": r.is_error}, default=str
                                ),
                                evidence_refs=[
                                    e.ref for e in reg.items if int(e.ref[3:]) >= start_idx
                                ],
                            )
                        )
                    messages = [
                        *messages,
                        Message(
                            "assistant",
                            text=result.text,
                            tool_calls=result.tool_calls,
                            raw=result.raw,
                        ),
                        Message("user", tool_results=results),
                    ]
                    request = replace(
                        request,
                        messages=messages,
                        context={
                            **context,
                            "question": body.question,
                            "evidence": [e.for_model() for e in reg.items],
                        },
                    )
                if answer is None:
                    raise AIFailed("The model did not finish answering", code="ai.tool_loop")
        except TimeoutError as e:
            await self._keep_usage(usage_rows, inv.id, tokens_before)
            raise AIFailed("The answer took too long", code="ai.run_timeout") from e
        except CallFailed as e:
            await self._keep_usage([*usage_rows, e.row], inv.id, tokens_before)
            raise AIFailed(e.error.detail, code=e.error.code) from e
        except AIFailed:
            await self._keep_usage(usage_rows, inv.id, tokens_before)
            raise

        new_ev = [e for e in reg.items if int(e.ref[3:]) >= known_before]
        for ev in new_ev:
            self.session.add(evidence_row(inv, ev))
        user_msg = AIMessage(
            org_id=inv.org_id,
            investigation_id=inv.id,
            role=MessageRole.USER,
            content=body.question,
            author_id=self.ctx.user_id,
            client_id=body.client_id,
        )
        answer_msg = AIMessage(
            org_id=inv.org_id,
            investigation_id=inv.id,
            role=MessageRole.ASSISTANT,
            content=answer.answer,
            evidence_refs=answer.evidence_refs,
        )
        # Insert in conversation order (created_at uses clock_timestamp()).
        for m in [user_msg, *tool_msgs, answer_msg]:
            self.session.add(m)
            await self.session.flush()
        self.session.add_all(usage_rows)
        inv.tool_calls_used = tool_calls_used
        await self.session.commit()
        stored = (
            await self.session.scalars(
                select(AIEvidence).where(
                    AIEvidence.investigation_id == inv.id,
                    AIEvidence.ref.in_([e.ref for e in new_ev]),
                )
            )
        ).all()
        return AskOut(
            messages=[_message_out(m) for m in [user_msg, *tool_msgs, answer_msg]],
            new_evidence=[_evidence_out(e) for e in sorted(stored, key=lambda e: int(e.ref[3:]))],
        )

    async def _keep_usage(self, rows: list[AIUsage], inv_id: UUID, tokens_before: int) -> None:
        """A failed ask is rolled back, but tokens spent are real: keep the usage rows."""
        tokens = sum(
            r.input_tokens + r.output_tokens + r.cached_tokens + r.cache_write_tokens for r in rows
        )
        await self.session.rollback()
        for r in rows:
            self.session.add(
                AIUsage(
                    **{
                        c: getattr(r, c)
                        for c in (
                            "org_id",
                            "investigation_id",
                            "purpose",
                            "provider",
                            "model",
                            "input_tokens",
                            "output_tokens",
                            "cached_tokens",
                            "cache_write_tokens",
                            "cost_micros",
                            "latency_ms",
                            "attempt",
                            "outcome",
                            "request_id",
                        )
                    }
                )
            )
        inv = await self.session.get(AIInvestigation, inv_id)
        if inv is not None:
            inv.tokens_used = tokens_before + tokens
        await self.session.commit()

    async def _replay(self, inv: AIInvestigation, client_id: UUID) -> AskOut | None:
        """Same client_id again (a retry after a lost response): return the stored turn."""
        first = await self.session.scalar(select(AIMessage).where(AIMessage.client_id == client_id))
        if first is None:
            return None
        if first.investigation_id != inv.id or first.org_id != self.ctx.org_id:
            raise Conflict("client_id was already used", code="ai.client_id_reused")
        after = (
            await self.session.scalars(
                self.select(AIMessage)
                .where(
                    AIMessage.investigation_id == inv.id,
                    or_(
                        AIMessage.created_at > first.created_at,
                        and_(AIMessage.created_at == first.created_at, AIMessage.id > first.id),
                    ),
                )
                .order_by(AIMessage.created_at, AIMessage.id)
            )
        ).all()
        turn = [first]
        for m in after:
            if m.role == MessageRole.USER:
                break
            turn.append(m)
        refs = {r for m in turn for r in m.evidence_refs if m.role == MessageRole.TOOL}
        ev = (
            await self.session.scalars(
                select(AIEvidence).where(
                    AIEvidence.investigation_id == inv.id, AIEvidence.ref.in_(refs)
                )
            )
        ).all()
        return AskOut(
            messages=[_message_out(m) for m in turn],
            new_evidence=[_evidence_out(e) for e in sorted(ev, key=lambda e: int(e.ref[3:]))],
        )

    # ------------------------------------------------------------------ proposals

    async def decide(self, inv_id: UUID, proposal_id: UUID, body: DecisionIn) -> ProposalOut:
        inv, inc = await self._inv(inv_id)
        p = await self.session.scalar(
            self.select(AIActionProposal)
            .where(AIActionProposal.investigation_id == inv.id, AIActionProposal.id == proposal_id)
            .with_for_update()
        )
        if p is None:
            raise NotFound("Proposal not found", code="ai.proposal_not_found")
        if p.risk == Risk.DESTRUCTIVE and not self.ctx.can(Permission.ORG_MANAGE):
            raise Forbidden(
                "Destructive actions need an admin's decision",
                code="ai.destructive_requires_admin",
            )
        if p.status != ProposalStatus.PROPOSED:
            raise Conflict(
                f"This proposal was already {p.status.value}",
                code="ai.proposal_decided",
                extra={"status": p.status.value},
            )
        p.status = ProposalStatus.APPROVED if body.approve else ProposalStatus.REJECTED
        p.decided_by = self.ctx.user_id
        p.decided_at = datetime.now(UTC)
        p.decision_note = body.note
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action=f"ai.proposal_{p.status.value}",
            target_type="ai_action_proposal",
            target_id=p.id,
            after={"description": p.description, "risk": p.risk.value, "note": body.note},
        )
        add_event(
            self.session,
            inc,
            EventType.AI_ANALYSIS,
            actor_type=ActorType.USER,
            actor_id=self.ctx.user_id,
            data={
                "kind": "proposal_decision",
                "investigation_id": str(inv.id),
                "proposal_id": str(p.id),
                "decision": p.status.value,
                "description": p.description,
                "risk": p.risk.value,
            },
        )
        await self.session.commit()
        return _proposal_out(p)

    async def feedback(self, inv_id: UUID, body: FeedbackIn) -> None:
        inv, _ = await self._inv(inv_id)
        if self.ctx.user_id is None:
            raise Forbidden("Feedback needs a user", code="ai.feedback_needs_user")
        await self.session.execute(
            insert(AIFeedback)
            .values(
                org_id=inv.org_id,
                investigation_id=inv.id,
                user_id=self.ctx.user_id,
                helpful=body.helpful,
                note=body.note,
            )
            .on_conflict_do_update(
                index_elements=["investigation_id", "user_id"],
                set_={"helpful": body.helpful, "note": body.note, "created_at": func.now()},
            )
        )
        await self.session.commit()

    # ------------------------------------------------------------------- settings

    async def settings(self) -> AISettingsOut:
        st = await load_settings(self.session, self.ctx.org_id)
        return await self._settings_out(st)

    async def _settings_out(self, st: AISettings) -> AISettingsOut:
        provider, model = effective(st)
        avail = providers.available()
        return AISettingsOut(
            enabled=st.enabled,
            provider=st.provider,
            model=st.model,
            monthly_budget_micros=st.monthly_budget_micros,
            max_tokens_per_run=st.max_tokens_per_run,
            auto_investigate_min_severity=st.auto_investigate_min_severity,
            data_redaction=RedactionSettings.model_validate(st.data_redaction),
            effective_provider=provider,
            effective_model=model,
            providers=[
                ProviderInfo(name=n, configured=avail.get(n, False), is_demo=n == "fake")
                for n in providers.PROVIDERS
            ],
            month_to_date_cost_micros=await month_to_date_cost(self.session, self.ctx.org_id),
            version=st.version,
        )

    async def update_settings(self, body: AISettingsIn) -> AISettingsOut:
        if body.provider is not None and body.provider not in providers.PROVIDERS:
            raise Unprocessable(f"Unknown provider '{body.provider}'", code="ai.unknown_provider")
        row = await self.session.get(AISettings, self.ctx.org_id, with_for_update=True)
        before = None
        if row is None:
            row = await load_settings(self.session, self.ctx.org_id)
            self.session.add(row)
        else:
            before = (await self._settings_out(row)).model_dump(
                mode="json",
                include={
                    "enabled",
                    "provider",
                    "model",
                    "monthly_budget_micros",
                    "auto_investigate_min_severity",
                },
            )
        row.enabled = body.enabled
        row.provider = body.provider
        row.model = body.model
        row.monthly_budget_micros = body.monthly_budget_micros
        row.max_tokens_per_run = body.max_tokens_per_run
        row.auto_investigate_min_severity = body.auto_investigate_min_severity
        row.data_redaction = body.data_redaction.model_dump()
        row.updated_by = self.ctx.user_id
        row.version = (row.version or 0) + 1
        provider, _ = effective(row)
        if body.enabled and not providers.available().get(provider):
            raise Unprocessable(
                f"AI provider '{provider}' is not configured on this server",
                code="ai.provider_unconfigured",
            )
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="ai.settings_updated",
            target_type="ai_settings",
            target_id=self.ctx.org_id,
            before=before,
            after=body.model_dump(mode="json"),
        )
        await self.session.commit()
        return await self._settings_out(row)

    # ---------------------------------------------------------------------- usage

    async def usage(self, start: datetime | None, end: datetime | None) -> UsageOut:
        end = end or datetime.now(UTC)
        start = start or month_start(end)
        if start >= end:
            raise Unprocessable("'from' must be before 'to'", code="ai.bad_range")
        day = cast(func.date_trunc("day", AIUsage.created_at), Date)
        rows = (
            await self.session.execute(
                select(
                    day,
                    AIUsage.provider,
                    AIUsage.model,
                    func.count(),
                    func.sum(AIUsage.input_tokens),
                    func.sum(AIUsage.output_tokens),
                    func.sum(AIUsage.cached_tokens),
                    func.sum(AIUsage.cost_micros),
                )
                .where(
                    AIUsage.org_id == self.ctx.org_id,
                    AIUsage.created_at >= start,
                    AIUsage.created_at < end,
                )
                .group_by(day, AIUsage.provider, AIUsage.model)
                .order_by(day, AIUsage.model)
            )
        ).all()
        days = [
            UsageDay(
                day=d,
                provider=p,
                model=m,
                calls=n,
                input_tokens=int(i or 0),
                output_tokens=int(o or 0),
                cached_tokens=int(c or 0),
                cost_micros=int(cost or 0),
            )
            for d, p, m, n, i, o, c, cost in rows
        ]
        st = await load_settings(self.session, self.ctx.org_id)
        return UsageOut(
            from_=start,
            to=end,
            total_cost_micros=sum(d.cost_micros for d in days),
            month_to_date_cost_micros=await month_to_date_cost(self.session, self.ctx.org_id),
            monthly_budget_micros=st.monthly_budget_micros,
            days=days,
        )
