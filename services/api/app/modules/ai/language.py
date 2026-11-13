"""Language the AI investigator writes in (the person's UI language).

Evidence stays as DevPulse computed it (English); only the model's own prose — summary,
causes, reasoning, actions, answers — follows the language. Identifiers never change.
"""

from typing import Literal, get_args

Language = Literal["en", "vi"]
LANGUAGES: tuple[str, ...] = get_args(Language)
DEFAULT_LANGUAGE: Language = "en"

_NAMES = {"vi": "Vietnamese (tiếng Việt)"}


def normalize(value: str | None) -> Language | None:
    """`vi`, `vi-VN`, `VI` → "vi"; anything unsupported → None."""
    if not value:
        return None
    code = value.strip().lower().replace("_", "-").split("-")[0]
    return code if code in LANGUAGES else None  # type: ignore[return-value]


def from_accept_language(header: str | None) -> Language:
    """Highest-ranked supported language in an Accept-Language header, else English."""
    ranked: list[tuple[float, str]] = []
    for part in (header or "").split(","):
        tag, *params = part.strip().split(";")
        q = 1.0
        for p in params:
            k, _, v = p.strip().partition("=")
            if k == "q":
                try:
                    q = float(v)
                except ValueError:
                    q = 0.0
        ranked.append((q, tag))
    for _, tag in sorted(ranked, key=lambda x: -x[0]):
        lang = normalize(tag)
        if lang:
            return lang
    return DEFAULT_LANGUAGE


def instruction(language: str) -> str:
    """Appended to the system prompt; empty for English (the prompts' own language)."""
    name = _NAMES.get(language)
    if name is None:
        return ""
    return (
        f"\n\nLanguage: the engineers reading this work in {name}. Write every natural-language "
        f"value in {name}: summary, impact, cause, reasoning, how_to_verify, action, rationale, "
        "data_gaps, limitations and chat answers. Keep these exactly as given: evidence refs "
        "(EV-1, …), JSON keys, enum values (read_only, sensitive, investigate, …), metric, "
        "service and host names, versions, commit hashes, log messages and code. Use the terms "
        "Vietnamese engineers use (sự cố, triển khai, độ trễ, tỷ lệ lỗi); keep common English "
        "terms such as rollback, deploy or connection pool where they are the usual word."
    )
