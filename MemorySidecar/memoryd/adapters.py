from __future__ import annotations

import json
from typing import Any

from .adapter_factory import build_adapters
from .adapter_protocols import AdapterHealth, CompositeAdapters, KnowledgeGraphProjector, MemoryAdapters, MemoryProvider, NullAdapters
from .adapter_utils import compact_error as _compact_error
from .adapter_utils import endpoint_error as _endpoint_error
from .adapter_utils import endpoint_url_error as _endpoint_url_error
from .adapter_utils import protocol_label as _protocol_label
from .adapter_utils import safe_group_id as _safe_group_id
from .graphiti_adapter import GraphitiAdapter, _graphiti_llm_client, _noop_cross_encoder
from .graph_projection import GRAPHITI_PROJECTION_SCHEMA_VERSION, build_graphiti_projection_payload, graphiti_projection_episode_body
from .mem0_adapter import (
    Mem0Adapter,
    _instrument_mem0_embedding_client,
    _mem0_embedder_config,
    _mem0_llm_config,
    _set_mem0_openai_timeouts,
)
from .memory_mirror import mem0_result_items as _mem0_result_items
from .memory_mirror import mirror_from_mem0_item


DIRECT_EXTRACTION_SYSTEM_PROMPT = (
    "Deprecated compatibility constant. Source capture is now delegated to mem0.add(..., infer=True)."
)


def _parse_extracted_memories(text: str) -> list[dict[str, Any]]:
    """Compatibility parser for old tests/tools; the default path is mem0-managed."""
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return []
    raw_memories = payload.get("memories") if isinstance(payload, dict) else payload
    if not isinstance(raw_memories, list):
        return []
    memories: list[dict[str, Any]] = []
    for item in raw_memories:
        if not isinstance(item, dict):
            continue
        body = str(item.get("memory") or item.get("body") or item.get("text") or "").strip()
        if not body or _looks_like_raw_source_memory(body):
            continue
        memory = dict(item)
        memory["memory"] = body
        memories.append(memory)
    return memories


def _parse_extracted_memories_with_counts(text: str) -> tuple[list[dict[str, Any]], int]:
    memories = _parse_extracted_memories(text)
    return memories, len(memories)


def _looks_like_raw_source_memory(body: str) -> bool:
    head = body.lstrip()
    return head.startswith("Project: ") or "\nSource kind: " in head or "\nSource path: " in head


__all__ = [
    "AdapterHealth",
    "CompositeAdapters",
    "GraphitiAdapter",
    "KnowledgeGraphProjector",
    "Mem0Adapter",
    "MemoryAdapters",
    "MemoryProvider",
    "NullAdapters",
    "GRAPHITI_PROJECTION_SCHEMA_VERSION",
    "build_graphiti_projection_payload",
    "build_adapters",
    "graphiti_projection_episode_body",
    "mirror_from_mem0_item",
    "_compact_error",
    "_endpoint_error",
    "_endpoint_url_error",
    "_graphiti_llm_client",
    "_instrument_mem0_embedding_client",
    "_mem0_embedder_config",
    "_mem0_llm_config",
    "_mem0_result_items",
    "_noop_cross_encoder",
    "_parse_extracted_memories",
    "_parse_extracted_memories_with_counts",
    "_protocol_label",
    "_safe_group_id",
    "_set_mem0_openai_timeouts",
]
