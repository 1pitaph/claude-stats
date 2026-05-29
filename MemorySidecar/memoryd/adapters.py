from __future__ import annotations

import asyncio
import hashlib
import html
import json
import re
import socket
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Protocol
from urllib.parse import urlparse

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
                message = _compact_error(error)
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", message)
                statuses[str(name or "adapter")] = f"error: {message}"
        return statuses

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        proposals: list[dict[str, Any]] = []
        for adapter in self.adapters:
            try:
                proposals.extend(adapter.infer_memories(source))
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", _compact_error(error))
        return proposals

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for adapter in self.adapters:
            try:
                results.extend(adapter.search(query, project_id=project_id, limit=limit))
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", _compact_error(error))
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
                    setattr(adapter, "last_error", _compact_error(error))
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
            _set_mem0_openai_timeouts(self.client, config.adapter_timeout_seconds)
            self.available = True
        except Exception as error:  # noqa: BLE001
            self.client = None
            self.available = False
            self.last_error = str(error)

    def health(self) -> dict[str, str]:
        if self.available:
            if endpoint_error := _endpoint_error(self.config):
                return {"mem0": f"configured but endpoint unavailable: {endpoint_error}"}
            return {"mem0": "enabled: local qdrant + local OpenAI-compatible endpoint"}
        return {"mem0": f"unavailable: {self.last_error}"}

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        if not self.available or self.client is None:
            return {"mem0": f"unavailable: {self.last_error}"}
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return {"mem0": f"unavailable: {endpoint_error}"}
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
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
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
        if project_id is None:
            return []
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return []
        filters = {"user_id": project_id}
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
            memory_id = str(metadata.get("memory_id") or "")
            if not memory_id:
                continue
            if str(metadata.get("status") or "active") != "active":
                continue
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
                cross_encoder=_noop_cross_encoder(),
            )
            self.available = True
        except Exception as error:  # noqa: BLE001
            self.graphiti = None
            self.available = False
            self.last_error = str(error)

    def health(self) -> dict[str, str]:
        if self.available:
            if endpoint_error := _endpoint_error(self.config):
                return {"graphiti": f"configured but endpoint unavailable: {endpoint_error}"}
            return {"graphiti": "enabled: local kuzu + local OpenAI-compatible endpoint"}
        return {"graphiti": f"unavailable: {self.last_error}"}

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        if not self.available or self.graphiti is None:
            return {"graphiti": f"unavailable: {self.last_error}"}
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return {"graphiti": f"unavailable: {endpoint_error}"}
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
        group_id = _safe_group_id(project_id)
        from graphiti_core.nodes import EpisodeType  # type: ignore

        async def add_episode_with_timeout():
            return await asyncio.wait_for(
                self.graphiti.add_episode(
                    name=episode_name,
                    episode_body=body,
                    source_description=source_description,
                    reference_time=reference_time,
                    source=EpisodeType.json,
                    group_id=group_id,
                    saga=f"project:{project_id}",
                ),
                timeout=self.config.adapter_timeout_seconds,
            )

        try:
            result = asyncio.run(add_episode_with_timeout())
        except (TimeoutError, asyncio.TimeoutError) as error:
            raise TimeoutError(f"graphiti add_episode timed out after {self.config.adapter_timeout_seconds:.1f}s") from error
        episode = getattr(result, "episode", None)
        episode_uuid = str(getattr(episode, "uuid", "") or hashlib.sha256(str(memory.get("id") or episode_name).encode("utf-8")).hexdigest()[:32])
        return {"graphiti": f"ok:{episode_uuid}"}

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        return []

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.graphiti is None or not query.strip():
            return []
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return []
        group_ids = [_safe_group_id(project_id)] if project_id else None

        async def search_with_timeout():
            return await asyncio.wait_for(
                self.graphiti.search(query=query, group_ids=group_ids, num_results=limit),
                timeout=self.config.adapter_timeout_seconds,
            )

        try:
            edges = asyncio.run(search_with_timeout())
        except (TimeoutError, asyncio.TimeoutError) as error:
            raise TimeoutError(f"graphiti search timed out after {self.config.adapter_timeout_seconds:.1f}s") from error
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
        if not self.available or self.graphiti is None:
            return {"nodes": [], "edges": []}
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return {"nodes": [], "edges": []}
        group_id = _safe_group_id(project_id)
        from graphiti_core.edges import EntityEdge  # type: ignore
        from graphiti_core.errors import GroupsEdgesNotFoundError  # type: ignore
        from graphiti_core.nodes import EntityNode  # type: ignore

        async def graph_with_timeout():
            async def load_edges():
                try:
                    return await EntityEdge.get_by_group_ids(self.graphiti.driver, [group_id], limit=limit)
                except GroupsEdgesNotFoundError:
                    return []

            return await asyncio.wait_for(
                asyncio.gather(
                    EntityNode.get_by_group_ids(self.graphiti.driver, [group_id], limit=limit),
                    load_edges(),
                ),
                timeout=self.config.adapter_timeout_seconds,
            )

        try:
            entity_nodes, entity_edges = asyncio.run(graph_with_timeout())
        except (TimeoutError, asyncio.TimeoutError) as error:
            raise TimeoutError(f"graphiti graph timed out after {self.config.adapter_timeout_seconds:.1f}s") from error

        nodes: dict[str, dict[str, Any]] = {}
        edges: list[dict[str, Any]] = []

        for node in entity_nodes:
            node_uuid = str(getattr(node, "uuid", ""))
            if not node_uuid:
                continue
            labels = getattr(node, "labels", []) or []
            attributes = getattr(node, "attributes", {}) or {}
            nodes[f"graphiti:entity:{node_uuid}"] = {
                "id": f"graphiti:entity:{node_uuid}",
                "kind": "graphiti_entity",
                "title": str(getattr(node, "name", "") or node_uuid),
                "body": str(getattr(node, "summary", "") or ""),
                "metadata": {
                    "adapter": "graphiti",
                    "uuid": node_uuid,
                    "group_id": group_id,
                    "labels": json.dumps(labels, sort_keys=True, ensure_ascii=False),
                    "attributes": json.dumps(attributes, sort_keys=True, ensure_ascii=False),
                },
            }

        for edge in entity_edges:
            edge_uuid = str(getattr(edge, "uuid", ""))
            source_uuid = str(getattr(edge, "source_node_uuid", ""))
            target_uuid = str(getattr(edge, "target_node_uuid", ""))
            if not edge_uuid or not source_uuid or not target_uuid:
                continue
            for node_uuid in (source_uuid, target_uuid):
                node_id = f"graphiti:entity:{node_uuid}"
                if node_id not in nodes:
                    nodes[node_id] = {
                        "id": node_id,
                        "kind": "graphiti_entity",
                        "title": node_uuid,
                        "metadata": {"adapter": "graphiti", "uuid": node_uuid, "group_id": group_id},
                    }
            valid_at = getattr(edge, "valid_at", None)
            invalid_at = getattr(edge, "invalid_at", None)
            edges.append(
                {
                    "source": f"graphiti:entity:{source_uuid}",
                    "target": f"graphiti:entity:{target_uuid}",
                    "kind": str(getattr(edge, "name", "") or "RELATES_TO"),
                    "metadata": {
                        "adapter": "graphiti",
                        "uuid": edge_uuid,
                        "fact": str(getattr(edge, "fact", "") or ""),
                        "valid_at": valid_at.isoformat() if hasattr(valid_at, "isoformat") else str(valid_at or ""),
                        "invalid_at": invalid_at.isoformat() if hasattr(invalid_at, "isoformat") else str(invalid_at or ""),
                    },
                }
            )

        return {"nodes": list(nodes.values()), "edges": edges}


def _noop_cross_encoder():
    from graphiti_core.cross_encoder.client import CrossEncoderClient  # type: ignore

    class NoopCrossEncoder(CrossEncoderClient):
        async def rank(self, query: str, passages: list[str]) -> list[tuple[str, float]]:
            return [(passage, 1.0 / (index + 1)) for index, passage in enumerate(passages)]

    return NoopCrossEncoder()


def _set_mem0_openai_timeouts(client: Any, timeout_seconds: float) -> None:
    timeout = max(1.0, float(timeout_seconds))
    for attr_path in (("llm", "client"), ("embedding_model", "client")):
        target = client
        for attr in attr_path:
            target = getattr(target, attr, None)
            if target is None:
                break
        if target is None or not hasattr(target, "with_options"):
            continue
        try:
            replacement = target.with_options(timeout=timeout)
        except Exception:  # noqa: BLE001
            continue
        owner = getattr(client, attr_path[0], None)
        if owner is not None:
            setattr(owner, attr_path[1], replacement)


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


def _endpoint_error(config: LocalAIConfig) -> str:
    parsed = urlparse(config.base_url)
    host = parsed.hostname
    if not host:
        return "local AI base URL is not configured"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        with socket.create_connection((host, port), timeout=0.25):
            return ""
    except OSError as error:
        detail = error.strerror or str(error)
        if host in {"127.0.0.1", "localhost", "::1"} and port == 18765:
            return f"local AI helper stopped or unreachable at {host}:{port} ({detail})"
        return f"{host}:{port} is unreachable ({detail})"


def _compact_error(error: Exception) -> str:
    text = html.unescape(str(error))
    text = re.sub(r"(?is)<script.*?</script>|<style.*?</style>", " ", text)
    text = re.sub(r"(?is)<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > 320:
        text = text[:317].rstrip() + "..."
    return text or error.__class__.__name__


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
