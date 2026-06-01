from __future__ import annotations

import hashlib
import json
import time
from typing import Any

from .adapter_utils import float_value, timestamp, timestamp_or_none


VOLATILE_METADATA_KEYS = {
    "last_synced_at",
    "last_event_id",
    "cache_source",
}


def mem0_result_items(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, dict):
        items = raw.get("results")
        if isinstance(items, list):
            return [item for item in items if isinstance(item, dict)]
        return [raw]
    if isinstance(raw, list):
        return [item for item in raw if isinstance(item, dict)]
    return []


def metadata_from_memory(memory: dict[str, Any]) -> dict[str, str]:
    source_refs = memory.get("source_refs") if isinstance(memory.get("source_refs"), list) else []
    scopes = memory.get("scopes") if isinstance(memory.get("scopes"), list) else []
    metadata = memory.get("metadata") if isinstance(memory.get("metadata"), dict) else {}
    project_id = str(memory.get("project_id") or metadata.get("project_id") or "default")
    return {
        **{str(key): str(value) for key, value in metadata.items() if value is not None},
        "project_id": project_id,
        "status": str(memory.get("status") or metadata.get("status") or "active"),
        "type": str(memory.get("type") or metadata.get("type") or "fact"),
        "title": str(memory.get("title") or metadata.get("title") or memory.get("body") or "Memory")[:160],
        "confidence": str(memory.get("confidence") or metadata.get("confidence") or "0.8"),
        "importance": str(memory.get("importance") or metadata.get("importance") or "0.5"),
        "source": "claude-stats-memoryd",
        "provider": "mem0",
        "source_refs_json": json.dumps(source_refs, sort_keys=True, ensure_ascii=False),
        "scopes_json": json.dumps(scopes, sort_keys=True, ensure_ascii=False),
        "legacy_memory_id": str(memory.get("id") or metadata.get("legacy_memory_id") or ""),
    }


def mirror_from_mem0_item(
    item: dict[str, Any],
    *,
    fallback_metadata: dict[str, Any] | None = None,
    default_project_id: str | None = None,
    default_source_refs: list[dict[str, Any]] | None = None,
    default_scopes: list[dict[str, Any]] | None = None,
    default_status: str = "active",
    capture_version: str | None = None,
    now: float | None = None,
) -> dict[str, Any] | None:
    text = str(item.get("memory") or item.get("text") or item.get("body") or "").strip()
    if not text:
        return None
    metadata = item.get("metadata") if isinstance(item.get("metadata"), dict) else {}
    merged_metadata = {str(key): str(value) for key, value in (fallback_metadata or {}).items() if value is not None}
    merged_metadata.update({str(key): str(value) for key, value in metadata.items() if value is not None})
    memory_id = str(item.get("id") or merged_metadata.get("legacy_memory_id") or hashlib.sha256(text.encode("utf-8")).hexdigest()[:24])
    project_id = str(item.get("user_id") or merged_metadata.get("project_id") or merged_metadata.get("user_id") or default_project_id or "default")
    source_refs = json_dict_list(merged_metadata.get("source_refs_json")) or list(default_source_refs or [])
    scopes = json_dict_list(merged_metadata.get("scopes_json")) or list(default_scopes or []) or [
        {"id": f"project:{project_id}", "kind": "project", "key": project_id, "title": project_id, "metadata": {}, "primary": True}
    ]
    synced_at = now if now is not None else time.time()
    mirror_metadata = merged_metadata | {
        "adapter": "mem0",
        "provider": "mem0",
        "provider_id": memory_id,
        "mem0_id": memory_id,
        "cache_source": "mem0",
        "last_synced_at": str(synced_at),
    }
    if capture_version:
        mirror_metadata["capture_version"] = capture_version
    if not any(isinstance(ref, dict) and ref.get("kind") == "mem0" for ref in source_refs):
        source_refs.append({"kind": "mem0", "uri": memory_id})
    return {
        "id": memory_id,
        "project_id": project_id,
        "type": str(merged_metadata.get("type") or "fact"),
        "status": str(merged_metadata.get("status") or default_status or "active"),
        "title": str(merged_metadata.get("title") or text[:120] or "mem0 memory")[:160],
        "body": text,
        "normalized_claim": str(item.get("hash") or merged_metadata.get("hash") or hashlib.sha256(text.lower().encode("utf-8")).hexdigest()),
        "confidence": float_value(merged_metadata.get("confidence"), 0.82),
        "importance": float_value(merged_metadata.get("importance"), 0.6),
        "source_refs": source_refs,
        "metadata": mirror_metadata,
        "scopes": scopes,
        "valid_at": timestamp_or_none(merged_metadata.get("valid_at")),
        "invalid_at": timestamp_or_none(merged_metadata.get("invalid_at")),
        "review_reason": merged_metadata.get("review_reason") or None,
        "extracted_by": merged_metadata.get("extracted_by") or "mem0",
        "created_at": timestamp(item.get("created_at") or merged_metadata.get("created_at")),
        "updated_at": timestamp(item.get("updated_at") or merged_metadata.get("updated_at")),
    }


def memory_content_changed(before: dict[str, Any] | None, after: dict[str, Any]) -> bool:
    if before is None:
        return True
    return comparable_memory(before) != comparable_memory(after)


def comparable_memory(memory: dict[str, Any]) -> dict[str, Any]:
    metadata = memory.get("metadata") if isinstance(memory.get("metadata"), dict) else {}
    stable_metadata = {
        str(key): str(value)
        for key, value in metadata.items()
        if key not in VOLATILE_METADATA_KEYS and value is not None
    }
    return {
        "id": str(memory.get("id") or ""),
        "project_id": str(memory.get("project_id") or ""),
        "type": str(memory.get("type") or ""),
        "status": str(memory.get("status") or ""),
        "title": str(memory.get("title") or ""),
        "body": str(memory.get("body") or ""),
        "normalized_claim": str(memory.get("normalized_claim") or ""),
        "confidence": float_value(memory.get("confidence"), 0.0),
        "importance": float_value(memory.get("importance"), 0.0),
        "source_refs": _stable_json(memory.get("source_refs") if isinstance(memory.get("source_refs"), list) else []),
        "scopes": _stable_json(memory.get("scopes") if isinstance(memory.get("scopes"), list) else []),
        "valid_at": memory.get("valid_at"),
        "invalid_at": memory.get("invalid_at"),
        "review_reason": str(memory.get("review_reason") or ""),
        "extracted_by": str(memory.get("extracted_by") or ""),
        "metadata": _stable_json(stable_metadata),
    }


def json_dict_list(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, str) or not value:
        return []
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return []
    if not isinstance(decoded, list):
        return []
    return [item for item in decoded if isinstance(item, dict)]


def _stable_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
