from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


MEMORY_TYPES = {
    "rule",
    "convention",
    "command",
    "workflow",
    "decision",
    "risk",
    "dependency",
    "ownership",
    "fact",
    "todo",
    "question",
    "deprecation",
}

MEMORY_STATUSES = {
    "active",
    "proposed",
    "superseded",
    "deprecated",
    "conflicted",
    "retracted",
}

DETERMINISTIC_SOURCE_KINDS = {
    "AGENTS.md",
    "CLAUDE.md",
    "ai_config",
    "codex_transcript",
    "claude_transcript",
    "manual",
    "repo_config",
    "script",
    "test",
    "user_instruction",
    "terminal_capture",
}


@dataclass(frozen=True)
class Scope:
    kind: str
    key: str
    title: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def id(self) -> str:
        return f"{self.kind}:{self.key}"

    @staticmethod
    def from_json(value: dict[str, Any] | None, *, project_id: str) -> "Scope":
        if not value:
            return Scope(kind="project", key=project_id, title=project_id)
        kind = str(value.get("kind") or "project")
        key = str(value.get("key") or value.get("id") or project_id)
        title = value.get("title")
        metadata = value.get("metadata")
        return Scope(kind=kind, key=key, title=title if isinstance(title, str) else None, metadata=metadata if isinstance(metadata, dict) else {})

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "key": self.key,
            "title": self.title or self.key,
            "metadata": self.metadata,
        }


@dataclass(frozen=True)
class MemoryInput:
    project_id: str
    title: str
    body: str
    type: str = "fact"
    status: str = "active"
    memory_id: str | None = None
    normalized_claim: str | None = None
    confidence: float = 0.8
    importance: float = 0.5
    scopes: list[Scope] = field(default_factory=list)
    source_refs: list[dict[str, Any]] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)
    valid_at: float | None = None
    invalid_at: float | None = None
    review_reason: str | None = None
    extracted_by: str | None = None

    @staticmethod
    def from_json(value: dict[str, Any], *, project_id: str | None = None, default_status: str = "active") -> "MemoryInput":
        resolved_project = str(value.get("project_id") or project_id or "unknown")
        raw_type = str(value.get("type") or value.get("memory_type") or "fact")
        memory_type = raw_type if raw_type in MEMORY_TYPES else "fact"
        raw_status = str(value.get("status") or default_status)
        status = raw_status if raw_status in MEMORY_STATUSES else default_status
        raw_scopes = value.get("scope") or value.get("scopes") or []
        if isinstance(raw_scopes, dict):
            raw_scopes = [raw_scopes]
        scopes = [Scope.from_json(scope, project_id=resolved_project) for scope in raw_scopes if isinstance(scope, dict)]
        if not scopes:
            scopes = [Scope(kind="project", key=resolved_project, title=resolved_project)]
        source_refs = value.get("source_refs")
        if not isinstance(source_refs, list):
            source_refs = []
        metadata = value.get("metadata")
        if not isinstance(metadata, dict):
            metadata = {}
        return MemoryInput(
            project_id=resolved_project,
            title=str(value.get("title") or value.get("body") or "Memory").strip()[:160],
            body=str(value.get("body") or value.get("text") or "").strip(),
            type=memory_type,
            status=status,
            memory_id=value.get("id") or value.get("memory_id"),
            normalized_claim=value.get("normalized_claim"),
            confidence=float(value.get("confidence") or 0.8),
            importance=float(value.get("importance") or 0.5),
            scopes=scopes,
            source_refs=[ref for ref in source_refs if isinstance(ref, dict)],
            metadata=metadata,
            valid_at=_float_or_none(value.get("valid_at")),
            invalid_at=_float_or_none(value.get("invalid_at")),
            review_reason=value.get("review_reason") if isinstance(value.get("review_reason"), str) else None,
            extracted_by=value.get("extracted_by") if isinstance(value.get("extracted_by"), str) else None,
        )


def string_map(value: dict[str, Any] | None) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    result: dict[str, str] = {}
    for key, item in value.items():
        if item is None:
            continue
        if isinstance(item, (dict, list)):
            result[str(key)] = str(item)
        else:
            result[str(key)] = str(item)
    return result


def _float_or_none(value: Any) -> float | None:
    try:
        return float(value) if value is not None and value != "" else None
    except (TypeError, ValueError):
        if isinstance(value, str):
            try:
                return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
            except ValueError:
                return None
        return None
