from __future__ import annotations

import json
from typing import Any


GRAPHITI_PROJECTION_SCHEMA_VERSION = "canonical_memory_event.v1"


def build_graphiti_projection_payload(memory: dict[str, Any], event: dict[str, Any]) -> dict[str, Any]:
    metadata = memory.get("metadata") if isinstance(memory.get("metadata"), dict) else {}
    project_id = str(memory.get("project_id") or event.get("project_id") or "default")
    provider = str(memory.get("extracted_by") or metadata.get("provider") or metadata.get("adapter") or "mem0")
    return {
        "schema_version": GRAPHITI_PROJECTION_SCHEMA_VERSION,
        "kind": "canonical_memory_event",
        "memory_provider": provider,
        "project": {
            "id": project_id,
        },
        "memory": {
            "id": memory.get("id") or event.get("memory_id"),
            "provider": provider,
            "title": memory.get("title"),
            "body": memory.get("body"),
            "type": memory.get("type"),
            "status": memory.get("status"),
            "normalized_claim": memory.get("normalized_claim"),
            "confidence": memory.get("confidence"),
            "importance": memory.get("importance"),
            "valid_at": memory.get("valid_at"),
            "invalid_at": memory.get("invalid_at"),
            "scopes": memory.get("scopes") or [],
            "source_refs": memory.get("source_refs") or [],
            "metadata": metadata,
        },
        "event": {
            "id": event.get("event_id") or event.get("id"),
            "seq": event.get("seq"),
            "type": event.get("event_type"),
            "timestamp": event.get("timestamp"),
            "actor": event.get("actor") if isinstance(event.get("actor"), dict) else {},
            "memory_id": event.get("memory_id") or memory.get("id"),
            "source_refs": event.get("source_refs") if isinstance(event.get("source_refs"), list) else [],
        },
    }


def graphiti_projection_episode_body(memory: dict[str, Any], event: dict[str, Any]) -> str:
    return json.dumps(
        build_graphiti_projection_payload(memory, event),
        sort_keys=True,
        ensure_ascii=False,
    )

