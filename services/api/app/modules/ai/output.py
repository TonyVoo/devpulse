"""The investigation output contract (AI_ARCHITECTURE.md §4) and its validation.

Two layers:
* `ANALYSIS_SCHEMA` is the JSON Schema sent to the provider as structured output. It is
  deliberately simple (types, enums, required fields) so every provider can honour it.
* `validate_analysis` re-parses the text with Pydantic and enforces the rules a schema
  can't: grounding (every cited ref must exist), 1-5 causes, confidence range and caps.
  Fields that express *policy* (status, confidence label, requires_approval) are set
  here, never trusted from the model.
"""

import json
from typing import Any, Literal

from pydantic import BaseModel, Field, ValidationError

MAX_CAUSES = 5
MAX_ACTIONS = 8
SINGLE_EVIDENCE_CAP = 0.75

ActionKind = Literal["investigate", "mitigate", "remediate", "communicate"]
RiskLevel = Literal["read_only", "sensitive", "destructive"]


def _str_array() -> dict[str, Any]:
    return {"type": "array", "items": {"type": "string"}}


ANALYSIS_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "summary",
        "impact",
        "probable_causes",
        "recommended_actions",
        "data_gaps",
        "limitations",
    ],
    "properties": {
        "summary": {"type": "string"},
        "impact": {"type": "string"},
        "probable_causes": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": [
                    "cause",
                    "confidence",
                    "reasoning",
                    "evidence_refs",
                    "counter_evidence_refs",
                    "how_to_verify",
                ],
                "properties": {
                    "cause": {"type": "string"},
                    "confidence": {"type": "number"},
                    "reasoning": {"type": "string"},
                    "evidence_refs": _str_array(),
                    "counter_evidence_refs": _str_array(),
                    "how_to_verify": {"type": "string"},
                },
            },
        },
        "recommended_actions": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["action", "kind", "risk", "rationale"],
                "properties": {
                    "action": {"type": "string"},
                    "kind": {
                        "type": "string",
                        "enum": ["investigate", "mitigate", "remediate", "communicate"],
                    },
                    "risk": {"type": "string", "enum": ["read_only", "sensitive", "destructive"]},
                    "rationale": {"type": "string"},
                },
            },
        },
        "data_gaps": _str_array(),
        "limitations": {"type": "string"},
    },
}

ANSWER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["answer", "evidence_refs"],
    "properties": {"answer": {"type": "string"}, "evidence_refs": _str_array()},
}


# ----------------------------------------------------------------- model-facing (lenient)


class _CauseIn(BaseModel):
    cause: str = Field(min_length=1, max_length=300)
    confidence: float
    reasoning: str = Field(min_length=1, max_length=2000)
    evidence_refs: list[str]
    counter_evidence_refs: list[str] = []
    how_to_verify: str = Field(max_length=1000)


class _ActionIn(BaseModel):
    action: str = Field(min_length=1, max_length=300)
    kind: ActionKind
    risk: RiskLevel
    rationale: str = Field(default="", max_length=1000)


class _AnalysisIn(BaseModel):
    summary: str = Field(min_length=1, max_length=600)
    impact: str = Field(max_length=1000)
    probable_causes: list[_CauseIn]
    recommended_actions: list[_ActionIn]
    data_gaps: list[str] = []
    limitations: str = Field(max_length=1500)


class _AnswerIn(BaseModel):
    answer: str = Field(min_length=1, max_length=6000)
    evidence_refs: list[str] = []


# ------------------------------------------------------------------- stored / API (strict)


class Cause(BaseModel):
    cause: str
    status: Literal["hypothesis"] = "hypothesis"  # only a human confirms a root cause
    confidence: float
    confidence_label: Literal["low", "medium", "high"]
    reasoning: str
    evidence_refs: list[str]
    counter_evidence_refs: list[str]
    how_to_verify: str


class Action(BaseModel):
    action: str
    kind: ActionKind
    risk: RiskLevel
    rationale: str
    requires_approval: bool
    proposal_id: str | None = None


class Analysis(BaseModel):
    incident_id: str  # the incident key, e.g. INC-1024
    summary: str
    impact: str
    probable_causes: list[Cause]
    recommended_actions: list[Action]
    data_gaps: list[str]
    limitations: str
    # Server-side corrections applied to the model output (shown, never hidden).
    adjustments: list[str] = []


class Answer(BaseModel):
    answer: str
    evidence_refs: list[str]


class InvalidOutput(Exception):
    def __init__(self, errors: list[str]) -> None:
        super().__init__("; ".join(errors))
        self.errors = errors


def confidence_label(c: float) -> Literal["low", "medium", "high"]:
    if c < 0.4:
        return "low"
    if c < 0.75:
        return "medium"
    return "high"


def _parse_json(text: str | None) -> Any:
    if not text:
        raise InvalidOutput(["The response was empty; return the JSON object."])
    stripped = text.strip()
    if stripped.startswith("```"):  # some models wrap JSON in a code fence
        stripped = stripped.split("\n", 1)[-1].rsplit("```", 1)[0]
    try:
        return json.loads(stripped)
    except json.JSONDecodeError as e:
        raise InvalidOutput([f"The response is not valid JSON ({e.msg})."]) from e


def _pydantic_errors(e: ValidationError) -> list[str]:
    return [f"{'.'.join(str(p) for p in err['loc'])}: {err['msg']}" for err in e.errors()]


def validate_analysis(text: str | None, *, known_refs: set[str], incident_key: str) -> Analysis:
    data = _parse_json(text)
    try:
        raw = _AnalysisIn.model_validate(data)
    except ValidationError as e:
        raise InvalidOutput(_pydantic_errors(e)) from e

    errors: list[str] = []
    adjustments: list[str] = []
    if not 1 <= len(raw.probable_causes) <= MAX_CAUSES:
        errors.append(f"probable_causes must contain 1 to {MAX_CAUSES} items.")
    if len(raw.recommended_actions) > MAX_ACTIONS:
        errors.append(f"recommended_actions must contain at most {MAX_ACTIONS} items.")

    causes: list[Cause] = []
    for i, c in enumerate(raw.probable_causes):
        refs = list(dict.fromkeys(c.evidence_refs))
        counter = list(dict.fromkeys(c.counter_evidence_refs))
        if not refs:
            errors.append(f"probable_causes[{i}] cites no evidence; cite at least one EV ref.")
        unknown = [r for r in refs + counter if r not in known_refs]
        if unknown:
            errors.append(
                f"probable_causes[{i}] cites unknown evidence {unknown}; "
                "only refs from the evidence list may be cited."
            )
        if not 0.0 <= c.confidence <= 1.0:
            errors.append(f"probable_causes[{i}].confidence must be between 0 and 1.")
        confidence = c.confidence
        if len(refs) == 1 and confidence > SINGLE_EVIDENCE_CAP:
            confidence = SINGLE_EVIDENCE_CAP
            adjustments.append(
                f"Confidence for '{c.cause}' capped at {SINGLE_EVIDENCE_CAP}: "
                "a single piece of evidence."
            )
        causes.append(
            Cause(
                cause=c.cause,
                confidence=round(confidence, 2),
                confidence_label=confidence_label(confidence),
                reasoning=c.reasoning,
                evidence_refs=refs,
                counter_evidence_refs=counter,
                how_to_verify=c.how_to_verify,
            )
        )
    if errors:
        raise InvalidOutput(errors)

    causes.sort(key=lambda c: c.confidence, reverse=True)
    actions = [
        Action(
            action=a.action,
            kind=a.kind,
            risk=a.risk,
            rationale=a.rationale,
            # Policy, not model choice: anything that changes a system needs a human.
            requires_approval=a.risk != "read_only",
        )
        for a in raw.recommended_actions
    ]
    return Analysis(
        incident_id=incident_key,
        summary=raw.summary,
        impact=raw.impact,
        probable_causes=causes,
        recommended_actions=actions,
        data_gaps=raw.data_gaps,
        limitations=raw.limitations,
        adjustments=adjustments,
    )


def validate_answer(text: str | None, *, known_refs: set[str]) -> Answer:
    data = _parse_json(text)
    try:
        raw = _AnswerIn.model_validate(data)
    except ValidationError as e:
        raise InvalidOutput(_pydantic_errors(e)) from e
    unknown = [r for r in raw.evidence_refs if r not in known_refs]
    if unknown:
        raise InvalidOutput([f"evidence_refs cites unknown evidence {unknown}."])
    return Answer(answer=raw.answer, evidence_refs=list(dict.fromkeys(raw.evidence_refs)))
