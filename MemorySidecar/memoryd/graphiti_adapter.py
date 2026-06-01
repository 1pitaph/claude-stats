from __future__ import annotations

import asyncio
import json
import time
from datetime import datetime, timezone
from typing import Any

from .adapter_utils import endpoint_error, protocol_label, safe_group_id
from .config import LocalAIConfig
from .graph_projection import build_graphiti_projection_payload, graphiti_projection_episode_body


class GraphitiAdapter:
    name = "graphiti"

    def __init__(self, config: LocalAIConfig):
        self.config = config
        self.last_error = ""
        try:
            from graphiti_core import Graphiti  # type: ignore
            from graphiti_core.driver.kuzu_driver import KuzuDriver  # type: ignore
            from graphiti_core.embedder.openai import OpenAIEmbedder, OpenAIEmbedderConfig  # type: ignore

            driver = KuzuDriver(db=str(config.kuzu_path))
            if not hasattr(driver, "_database"):
                setattr(driver, "_database", "")
            self.graphiti = Graphiti(
                graph_driver=driver,
                llm_client=_graphiti_llm_client(config),
                embedder=OpenAIEmbedder(
                    OpenAIEmbedderConfig(
                        api_key=config.embedding_token,
                        base_url=config.embedding_base_url,
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
            if error := endpoint_error(self.config):
                return {"graphiti": f"configured but endpoint unavailable: {error}"}
            return {"graphiti": f"enabled: local kuzu + {protocol_label(self.config.llm.protocol)} LLM + local embedding"}
        return {"graphiti": f"unavailable: {self.last_error}"}

    def project_memory_event(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]:
        if not self.available or self.graphiti is None:
            return {"graphiti": f"unavailable: {self.last_error}"}
        if error := endpoint_error(self.config):
            self.last_error = error
            return {"graphiti": f"unavailable: {error}"}
        payload = build_graphiti_projection_payload(memory, event)
        episode_name = str(payload["event"].get("id") or payload["memory"].get("id") or "memory")
        project_id = str(payload["project"].get("id") or "default")
        body = graphiti_projection_episode_body(memory, event)
        source_description = f"Claude Stats canonical memory project={project_id}"
        reference_time = datetime.fromtimestamp(float(event.get("timestamp") or time.time()), timezone.utc)
        group_id = safe_group_id(project_id)
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
        episode_uuid = str(getattr(episode, "uuid", "") or f"episode:{episode_name}")
        return {"graphiti": f"ok:{episode_uuid}"}

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        return self.project_memory_event(memory, event)

    def search_facts(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.graphiti is None or not query.strip():
            return []
        if error := endpoint_error(self.config):
            self.last_error = error
            return []
        group_ids = [safe_group_id(project_id)] if project_id else None

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
                            "relation": str(getattr(edge, "name", "") or "RELATES_TO"),
                            "source": str(getattr(edge, "source_node_uuid", "") or ""),
                            "target": str(getattr(edge, "target_node_uuid", "") or ""),
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

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        return self.search_facts(query, project_id=project_id, limit=limit)

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        if not self.available or self.graphiti is None:
            return {"nodes": [], "edges": []}
        if error := endpoint_error(self.config):
            self.last_error = error
            return {"nodes": [], "edges": []}
        group_id = safe_group_id(project_id)
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
            expired_at = getattr(edge, "expired_at", None)
            reference_time = getattr(edge, "reference_time", None)
            raw_episodes = getattr(edge, "episodes", []) or []
            episodes = [raw_episodes] if isinstance(raw_episodes, str) else list(raw_episodes)
            edges.append(
                {
                    "source": f"graphiti:entity:{source_uuid}",
                    "target": f"graphiti:entity:{target_uuid}",
                    "kind": str(getattr(edge, "name", "") or "RELATES_TO"),
                    "metadata": {
                        "adapter": "graphiti",
                        "uuid": edge_uuid,
                        "fact": str(getattr(edge, "fact", "") or ""),
                        "episodes": json.dumps(episodes, sort_keys=True, ensure_ascii=False),
                        "valid_at": valid_at.isoformat() if hasattr(valid_at, "isoformat") else str(valid_at or ""),
                        "invalid_at": invalid_at.isoformat() if hasattr(invalid_at, "isoformat") else str(invalid_at or ""),
                        "expired_at": expired_at.isoformat() if hasattr(expired_at, "isoformat") else str(expired_at or ""),
                        "reference_time": reference_time.isoformat() if hasattr(reference_time, "isoformat") else str(reference_time or ""),
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


def _graphiti_llm_client(config: LocalAIConfig):
    from graphiti_core.llm_client.config import LLMConfig  # type: ignore

    llm_config = LLMConfig(
        api_key=config.llm.token,
        base_url=config.llm.base_url,
        model=config.llm.model,
    )
    if config.llm.protocol == "openai_responses":
        from graphiti_core.llm_client.openai_client import OpenAIClient  # type: ignore

        return OpenAIClient(llm_config)
    if config.llm.protocol == "anthropic_messages":
        from graphiti_core.llm_client.anthropic_client import AnthropicClient  # type: ignore

        return AnthropicClient(llm_config)
    from graphiti_core.llm_client.openai_generic_client import OpenAIGenericClient  # type: ignore

    return OpenAIGenericClient(llm_config)
