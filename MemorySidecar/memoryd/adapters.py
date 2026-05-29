from __future__ import annotations

import asyncio
import hashlib
import json
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Protocol

from .config import LocalAIConfig, load_local_ai_config


@dataclass
class AdapterHealth:
    name: str
    status: str
    detail: str


class MemoryAdapters(Protocol):
    def names(self) -> list[str]: ...
    def health(self) -> dict[str, str]: ...
    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]: ...
    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]: ...
    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]: ...
    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]: ...


@dataclass
class NullAdapters:
    detail: str = "local AI endpoint is not configured"

    def names(self) -> list[str]:
        return []

    def health(self) -> dict[str, str]:
        return {
            "mem0": f"disabled: {self.detail}",
            "graphiti": f"disabled: {self.detail}",
            "graph_backend": "kuzu",
            "telemetry": "disabled",
        }

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        return {}

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        return []

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        return []

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        return {"nodes": [], "edges": []}


@dataclass
class CompositeAdapters:
    adapters: list[MemoryAdapters] = field(default_factory=list)

    def names(self) -> list[str]:
        names: list[str] = []
        for adapter in self.adapters:
            name = getattr(adapter, "name", None)
            if isinstance(name, str):
                names.append(name)
        return names

    def health(self) -> dict[str, str]:
        merged = {"graph_backend": "kuzu", "telemetry": "disabled"}
        for adapter in self.adapters:
            merged.update(adapter.health())
        return merged

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        statuses: dict[str, str] = {}
        for adapter in self.adapters:
            name = getattr(adapter, "name", "")
            if adapter_name is not None and name != adapter_name:
                continue
            try:
                result = adapter.index_memory(memory, event, adapter_name=adapter_name)
                statuses.update(result)
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", str(error))
                statuses[str(name or "adapter")] = f"error: {error}"
        return statuses

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        proposals: list[dict[str, Any]] = []
        for adapter in self.adapters:
            try:
                proposals.extend(adapter.infer_memories(source))
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", str(error))
        return proposals

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for adapter in self.adapters:
            try:
                results.extend(adapter.search(query, project_id=project_id, limit=limit))
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", str(error))
        return results[:limit]

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        nodes: list[dict[str, Any]] = []
        edges: list[dict[str, Any]] = []
        for adapter in self.adapters:
            try:
                graph = adapter.graph(project_id, limit=limit)
                nodes.extend(graph.get("nodes", []))
                edges.extend(graph.get("edges", []))
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", str(error))
        return {"nodes": nodes, "edges": edges}


class Mem0Adapter:
    name = "mem0"

    def __init__(self, config: LocalAIConfig):
        self.config = config
        self.last_error = ""
        try:
            from mem0 import Memory  # type: ignore

            self.client = Memory.from_config(
                {
                    "vector_store": {
                        "provider": "qdrant",
                        "config": {
                            "path": str(config.qdrant_path),
                            "collection_name": "claude_stats_memories",
                            "embedding_model_dims": config.embedding_dims,
                            "on_disk": True,
                        },
                    },
                    "llm": {
                        "provider": "openai",
                        "config": {
                            "model": config.llm_model,
                            "api_key": config.token,
                            "openai_base_url": config.base_url,
                        },
                    },
                    "embedder": {
                        "provider": "openai",
                        "config": {
                            "model": config.embedding_model,
                            "api_key": config.token,
                            "openai_base_url": config.base_url,
                            "embedding_dims": config.embedding_dims,
                        },
                    },
                    "history_db_path": str(config.qdrant_path.parent / "mem0-history.sqlite3"),
                }
            )
            self.available = True
        except Exception as error:  # noqa: BLE001
            self.client = None
            self.available = False
            self.last_error = str(error)

    def health(self) -> dict[str, str]:
        if self.available:
            return {"mem0": "enabled: local qdrant + local OpenAI-compatible endpoint"}
        return {"mem0": f"unavailable: {self.last_error}"}

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        if not self.available or self.client is None:
            return {"mem0": f"unavailable: {self.last_error}"}
        metadata = {
            "memory_id": str(memory.get("id") or ""),
            "project_id": str(memory.get("project_id") or ""),
            "type": str(memory.get("type") or "fact"),
            "status": str(memory.get("status") or "active"),
            "title": str(memory.get("title") or ""),
            "scopes_json": json.dumps(memory.get("scopes") or [], sort_keys=True, ensure_ascii=False),
            "source_refs_json": json.dumps(memory.get("source_refs") or [], sort_keys=True, ensure_ascii=False),
            "confidence": str(memory.get("confidence") or ""),
            "importance": str(memory.get("importance") or ""),
            "event_id": str(event.get("event_id") or ""),
            "source": "claude-stats-memoryd",
        }
        raw = self.client.add(
            str(memory.get("body") or memory.get("title") or ""),
            user_id=str(memory.get("project_id") or "default"),
            metadata=metadata,
            infer=False,
        )
        adapter_id = self._first_id(raw) or hashlib.sha256(metadata["memory_id"].encode("utf-8")).hexdigest()[:24]
        return {"mem0": f"ok:{adapter_id}"}

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        if not self.available or self.client is None:
            return []
        body = str(source.get("body") or source.get("text") or "").strip()
        if not body:
            return []
        project_id = str(source.get("project_id") or "default")
        metadata = {
            "source_id": str(source.get("id") or ""),
            "source_kind": str(source.get("kind") or ""),
            "source_path": str(source.get("path") or ""),
            "project_id": project_id,
            "source": "claude-stats-memoryd",
            "proposal": "true",
        }
        raw = self.client.add(
            body,
            user_id=project_id,
            metadata=metadata,
            infer=True,
        )
        items = raw.get("results", raw) if isinstance(raw, dict) else raw
        if not isinstance(items, list):
            return []
        proposals: list[dict[str, Any]] = []
        for index, item in enumerate(items, start=1):
            if not isinstance(item, dict):
                continue
            text = str(item.get("memory") or item.get("text") or item.get("body") or "").strip()
            if not text:
                continue
            proposals.append(
                {
                    "project_id": project_id,
                    "title": text[:120],
                    "body": text,
                    "type": "fact",
                    "status": "proposed",
                    "scope": source.get("scope") or {"kind": "project", "key": project_id, "title": project_id},
                    "source_refs": [
                        {
                            "kind": "mem0",
                            "uri": str(item.get("id") or f"infer:{index}"),
                        },
                        {
                            "kind": str(source.get("kind") or "source"),
                            "uri": str(source.get("uri") or source.get("path") or source.get("id") or ""),
                        },
                    ],
                    "metadata": {
                        "adapter": "mem0",
                        "source_id": str(source.get("id") or ""),
                        "source_hash": str(source.get("content_hash") or ""),
                    },
                }
            )
        return proposals

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.client is None or not query.strip():
            return []
        filters = {"user_id": project_id or "default"}
        raw = self.client.search(query, filters=filters, top_k=limit)
        items = raw.get("results", raw) if isinstance(raw, dict) else raw
        if not isinstance(items, list):
            return []
        results: list[dict[str, Any]] = []
        for rank, item in enumerate(items, start=1):
            if not isinstance(item, dict):
                continue
            text = str(item.get("memory") or item.get("text") or item.get("body") or "")
            metadata = item.get("metadata") if isinstance(item.get("metadata"), dict) else {}
            memory_id = str(metadata.get("memory_id") or item.get("id") or f"mem0:{rank}")
            resolved_project = str(metadata.get("project_id") or project_id or "default")
            score = float(item.get("score") or item.get("distance") or 0.0)
            source_refs = _json_list(metadata.get("source_refs_json"))
            results.append(
                {
                    "rank": rank,
                    "score": score,
                    "memory": {
                        "id": memory_id,
                        "project_id": resolved_project,
                        "type": str(metadata.get("type") or "fact"),
                        "status": str(metadata.get("status") or "active"),
                        "title": str(metadata.get("title") or text[:120] or "mem0 memory"),
                        "body": text,
                        "normalized_claim": memory_id,
                        "confidence": _float(metadata.get("confidence"), 0.7),
                        "importance": _float(metadata.get("importance"), 0.5),
                        "source_refs": source_refs + [{"kind": "mem0", "uri": str(item.get("id") or memory_id)}],
                        "metadata": {"adapter": "mem0", "mem0_id": str(item.get("id") or "")},
                        "scopes": _json_list(metadata.get("scopes_json")) or [{"id": f"project:{resolved_project}", "kind": "project", "key": resolved_project, "title": resolved_project, "metadata": {}, "primary": True}],
                        "created_at": _timestamp(item.get("created_at")),
                        "updated_at": _timestamp(item.get("updated_at")),
                    },
                    "match_kind": "mem0",
                    "evidence": [{"adapter": "mem0", "score": score, "detail": "semantic vector search"}],
                }
            )
        return results

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        return {"nodes": [], "edges": []}

    def _first_id(self, raw: Any) -> str | None:
        items = raw.get("results", raw) if isinstance(raw, dict) else raw
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict) and item.get("id"):
                    return str(item["id"])
        if isinstance(raw, dict) and raw.get("id"):
            return str(raw["id"])
        return None


class GraphitiAdapter:
    name = "graphiti"

    def __init__(self, config: LocalAIConfig):
        self.config = config
        self.last_error = ""
        try:
            from graphiti_core import Graphiti  # type: ignore
            from graphiti_core.driver.kuzu_driver import KuzuDriver  # type: ignore
            from graphiti_core.embedder.openai import OpenAIEmbedder, OpenAIEmbedderConfig  # type: ignore
            from graphiti_core.llm_client.config import LLMConfig  # type: ignore
            from graphiti_core.llm_client.openai_generic_client import OpenAIGenericClient  # type: ignore

            driver = KuzuDriver(db=str(config.kuzu_path))
            if not hasattr(driver, "_database"):
                setattr(driver, "_database", "")
            self.graphiti = Graphiti(
                graph_driver=driver,
                llm_client=OpenAIGenericClient(
                    LLMConfig(api_key=config.token, base_url=config.base_url, model=config.llm_model)
                ),
                embedder=OpenAIEmbedder(
                    OpenAIEmbedderConfig(
                        api_key=config.token,
                        base_url=config.base_url,
                        embedding_model=config.embedding_model,
                        embedding_dim=config.embedding_dims,
                    )
                ),
                cross_encoder=_NoopCrossEncoder(),
            )
            self.available = True
        except Exception as error:  # noqa: BLE001
            self.graphiti = None
            self.available = False
            self.last_error = str(error)

    def health(self) -> dict[str, str]:
        if self.available:
            return {"graphiti": "enabled: local kuzu + local OpenAI-compatible endpoint"}
        return {"graphiti": f"unavailable: {self.last_error}"}

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        if not self.available or self.graphiti is None:
            return {"graphiti": f"unavailable: {self.last_error}"}
        episode_name = str(event.get("event_id") or memory.get("id") or "memory")
        project_id = str(memory.get("project_id") or "default")
        body = json.dumps(
            {
                "memory_id": memory.get("id"),
                "project_id": project_id,
                "type": memory.get("type"),
                "status": memory.get("status"),
                "title": memory.get("title"),
                "body": memory.get("body"),
                "scopes": memory.get("scopes") or [],
                "source_refs": memory.get("source_refs") or [],
                "event": event,
            },
            sort_keys=True,
            ensure_ascii=False,
        )
        source_description = f"Claude Stats memory project={project_id}"
        reference_time = datetime.fromtimestamp(float(event.get("timestamp") or time.time()), timezone.utc)
        episode_uuid = "graphiti-" + hashlib.sha256(str(memory.get("id") or episode_name).encode("utf-8")).hexdigest()[:32]
        group_id = _safe_group_id(project_id)
        from graphiti_core.nodes import EpisodeType  # type: ignore

        asyncio.run(
            self.graphiti.add_episode(
                name=episode_name,
                episode_body=body,
                source_description=source_description,
                reference_time=reference_time,
                source=EpisodeType.json,
                group_id=group_id,
                uuid=episode_uuid,
                saga=f"project:{project_id}",
            )
        )
        return {"graphiti": f"ok:{episode_uuid}"}

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        return []

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.graphiti is None or not query.strip():
            return []
        group_ids = [_safe_group_id(project_id)] if project_id else None
        edges = asyncio.run(self.graphiti.search(query=query, group_ids=group_ids, num_results=limit))
        results: list[dict[str, Any]] = []
        now = time.time()
        for rank, edge in enumerate(edges, start=1):
            fact = str(getattr(edge, "fact", "") or getattr(edge, "name", "") or "")
            if not fact:
                continue
            edge_uuid = str(getattr(edge, "uuid", "") or f"edge:{rank}")
            resolved_project = project_id or str(getattr(edge, "group_id", "") or "graphiti")
            valid_at = getattr(edge, "valid_at", None)
            results.append(
                {
                    "rank": rank,
                    "score": 0.65,
                    "memory": {
                        "id": f"graphiti:{edge_uuid}",
                        "project_id": resolved_project,
                        "type": "fact",
                        "status": "active",
                        "title": fact[:120] or "Graphiti fact",
                        "body": fact,
                        "normalized_claim": edge_uuid,
                        "confidence": 0.65,
                        "importance": 0.55,
                        "source_refs": [{"kind": "graphiti", "uri": edge_uuid}],
                        "metadata": {
                            "adapter": "graphiti",
                            "edge_uuid": edge_uuid,
                            "valid_at": valid_at.isoformat() if hasattr(valid_at, "isoformat") else str(valid_at or ""),
                        },
                        "scopes": [{"id": f"project:{resolved_project}", "kind": "project", "key": resolved_project, "title": resolved_project, "metadata": {}, "primary": True}],
                        "created_at": now,
                        "updated_at": now,
                    },
                    "match_kind": "graphiti",
                    "evidence": [{"adapter": "graphiti", "score": 0.65, "detail": "temporal graph fact"}],
                }
            )
        return results

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        return {"nodes": [], "edges": []}


class _NoopCrossEncoder:
    async def rank(self, query: str, passages: list[str]) -> list[tuple[str, float]]:
        return [(passage, 1.0 / (index + 1)) for index, passage in enumerate(passages)]


def _json_list(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, str) or not value:
        return []
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return []
    if not isinstance(decoded, list):
        return []
    return [item for item in decoded if isinstance(item, dict)]


def _float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _timestamp(value: Any) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and value:
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return time.time()
    return time.time()


def _safe_group_id(value: str | None) -> str:
    raw = value or "default"
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in raw)
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]
    return f"p_{safe[:48]}_{digest}"


def build_adapters(root) -> MemoryAdapters:
    config = load_local_ai_config(root)
    if not config.enabled:
        return NullAdapters()
    adapters: list[MemoryAdapters] = []
    if config.mem0_enabled:
        adapters.append(Mem0Adapter(config))
    if config.graphiti_enabled:
        adapters.append(GraphitiAdapter(config))
    if not adapters:
        return NullAdapters("mem0 and Graphiti are disabled")
    return CompositeAdapters(adapters)
