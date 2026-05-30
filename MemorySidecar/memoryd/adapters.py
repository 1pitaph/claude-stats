from __future__ import annotations

import asyncio
import hashlib
import html
import json
import re
import socket
import time
import urllib.error
import urllib.request
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


DIRECT_EXTRACTION_SYSTEM_PROMPT = (
    "You convert coding sources into canonical mem0 memories. Return JSON only "
    "with this shape: {\"memories\":[{\"memory\":\"atomic reusable fact\","
    "\"type\":\"convention|workflow|fact|decision|risk|command\","
    "\"confidence\":0.0,\"importance\":0.0}]}. Each memory must be short, "
    "self-contained, durable, and useful in a future coding session. Do not copy "
    "raw source headers, raw JSON, Markdown headings alone, logs, secrets, or whole "
    "sections. Return {\"memories\":[]} when there is no durable memory."
)


class MemoryAdapters(Protocol):
    def names(self) -> list[str]: ...
    def health(self) -> dict[str, str]: ...
    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]: ...
    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]: ...
    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None: ...
    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]: ...
    def get_memory(self, memory_id: str) -> dict[str, Any] | None: ...
    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None: ...
    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]: ...
    def inference_errors(self) -> list[dict[str, str]]: ...
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

    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return []

    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        return None

    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]:
        return []

    def get_memory(self, memory_id: str) -> dict[str, Any] | None:
        return None

    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
        return None

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        return []

    def inference_errors(self) -> list[dict[str, str]]:
        return []

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        return []

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        return {"nodes": [], "edges": []}


@dataclass
class CompositeAdapters:
    adapters: list[MemoryAdapters] = field(default_factory=list)
    last_inference_errors: list[dict[str, str]] = field(default_factory=list)

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
        if self.last_inference_errors:
            merged["last_inference_errors"] = json.dumps(self.last_inference_errors, sort_keys=True, ensure_ascii=False)
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

    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        memories: list[dict[str, Any]] = []
        self.last_inference_errors = []
        for adapter in self.adapters:
            if getattr(adapter, "name", "") != "mem0":
                continue
            name = str(getattr(adapter, "name", "") or "adapter")
            try:
                memories.extend(adapter.capture_source(source, chunks))
            except Exception as error:  # noqa: BLE001
                message = _compact_error(error)
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", message)
                self.last_inference_errors.append({"adapter": name, "error": message})
        return memories

    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        self.last_inference_errors = []
        for adapter in self.adapters:
            if getattr(adapter, "name", "") != "mem0":
                continue
            try:
                return adapter.capture_memory(memory)
            except Exception as error:  # noqa: BLE001
                message = _compact_error(error)
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", message)
                self.last_inference_errors.append({"adapter": "mem0", "error": message})
        return None

    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]:
        for adapter in self.adapters:
            if getattr(adapter, "name", "") != "mem0":
                continue
            try:
                return adapter.list_memories(project_id=project_id, status=status, memory_type=memory_type, limit=limit)
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", _compact_error(error))
        return []

    def get_memory(self, memory_id: str) -> dict[str, Any] | None:
        for adapter in self.adapters:
            if getattr(adapter, "name", "") != "mem0":
                continue
            try:
                return adapter.get_memory(memory_id)
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", _compact_error(error))
        return None

    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
        for adapter in self.adapters:
            if getattr(adapter, "name", "") != "mem0":
                continue
            try:
                return adapter.update_memory(memory_id, updates)
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", _compact_error(error))
        return None

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        proposals: list[dict[str, Any]] = []
        self.last_inference_errors = []
        for adapter in self.adapters:
            name = str(getattr(adapter, "name", "") or "adapter")
            before_error = str(getattr(adapter, "last_error", "") or "")
            try:
                adapter_proposals = adapter.infer_memories(source)
                proposals.extend(adapter_proposals)
            except Exception as error:  # noqa: BLE001
                message = _compact_error(error)
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", message)
                self.last_inference_errors.append({"adapter": name, "error": message})
                continue
            after_error = str(getattr(adapter, "last_error", "") or "")
            if after_error and (after_error != before_error or not adapter_proposals):
                self.last_inference_errors.append({"adapter": name, "error": after_error})
        return proposals

    def inference_errors(self) -> list[dict[str, str]]:
        return list(self.last_inference_errors)

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

            llm_provider, llm_config = _mem0_llm_config(config)
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
                        "provider": llm_provider,
                        "config": llm_config,
                    },
                    "embedder": {
                        "provider": "openai",
                        "config": _mem0_embedder_config(config),
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
            return {"mem0": f"enabled: local qdrant + {_protocol_label(self.config.llm.protocol)} LLM + local embedding"}
        return {"mem0": f"unavailable: {self.last_error}"}

    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not self.available or self.client is None:
            return []
        self.last_error = ""
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return []
        captured: list[dict[str, Any]] = []
        for index, chunk in enumerate(chunks, start=1):
            body = str(chunk.get("body") or "").strip()
            if not body:
                continue
            project_id = str(chunk.get("project_id") or source.get("project_id") or "default")
            source_refs = chunk.get("source_refs") if isinstance(chunk.get("source_refs"), list) else source.get("source_refs")
            if not isinstance(source_refs, list):
                source_refs = [
                    {
                        "kind": str(source.get("kind") or "source"),
                        "uri": str(source.get("uri") or ""),
                        "path": str(source.get("path") or ""),
                        "content_hash": str(source.get("content_hash") or ""),
                        "source_id": str(source.get("id") or ""),
                        "episode_id": f"episode:{source.get('id')}",
                    }
                ]
            scopes = chunk.get("scopes") if isinstance(chunk.get("scopes"), list) else []
            metadata = {
                "project_id": project_id,
                "status": str(chunk.get("status") or "active"),
                "type": str(chunk.get("type") or "fact"),
                "title": str(chunk.get("title") or source.get("title") or body[:120])[:160],
                "source_kind": str(source.get("kind") or ""),
                "source_path": str(source.get("path") or ""),
                "source_uri": str(source.get("uri") or ""),
                "source_id": str(source.get("id") or ""),
                "source_hash": str(source.get("content_hash") or ""),
                "section": str(chunk.get("section") or ""),
                "chunk_index": str(index),
                "capture_version": str(chunk.get("capture_version") or ""),
                "confidence": str(chunk.get("confidence") or "0.82"),
                "importance": str(chunk.get("importance") or "0.6"),
                "source": "claude-stats-memoryd",
                "source_refs_json": json.dumps(source_refs, sort_keys=True, ensure_ascii=False),
                "scopes_json": json.dumps(scopes, sort_keys=True, ensure_ascii=False),
            }
            extra = chunk.get("metadata")
            if isinstance(extra, dict):
                metadata.update({str(key): str(value) for key, value in extra.items() if value is not None})
            if bool(chunk.get("infer", True)):
                candidates = self._extract_chunk_memories(body, chunk=chunk, source=source)
                for candidate in candidates:
                    candidate_body = str(candidate.get("memory") or "").strip()
                    if not candidate_body:
                        continue
                    candidate_metadata = dict(metadata)
                    candidate_metadata.update(
                        {
                            "title": str(candidate.get("title") or candidate_body[:120])[:160],
                            "type": str(candidate.get("type") or metadata.get("type") or "fact"),
                            "confidence": str(candidate.get("confidence") or metadata.get("confidence") or "0.82"),
                            "importance": str(candidate.get("importance") or metadata.get("importance") or "0.6"),
                            "extracted_by": "llm_direct_mem0",
                        }
                    )
                    raw = self.client.add(
                        candidate_body,
                        user_id=project_id,
                        metadata=candidate_metadata,
                        infer=False,
                    )
                    for item in _mem0_result_items(raw):
                        memory = self._memory_from_mem0_item(item, fallback_metadata=candidate_metadata)
                        if memory is not None:
                            captured.append(memory)
                continue

            raw = self.client.add(
                body,
                user_id=project_id,
                metadata=metadata,
                infer=False,
            )
            for item in _mem0_result_items(raw):
                memory = self._memory_from_mem0_item(item, fallback_metadata=metadata)
                if memory is not None:
                    captured.append(memory)
        return captured

    def _extract_chunk_memories(self, body: str, *, chunk: dict[str, Any], source: dict[str, Any]) -> list[dict[str, Any]]:
        prompt = str(chunk.get("prompt") or "").strip()
        source_kind = str(source.get("kind") or chunk.get("type") or "source")
        user_prompt = (
            f"{prompt}\n\n" if prompt else ""
        ) + (
            f"Source kind: {source_kind}\n"
            f"Project: {chunk.get('project_id') or source.get('project_id') or 'default'}\n"
            f"Section: {chunk.get('section') or chunk.get('title') or ''}\n\n"
            "Extract at most 8 memories from this chunk. Return JSON only.\n\n"
            f"{body}"
        )
        text = self._call_extraction_llm(user_prompt)
        memories = _parse_extracted_memories(text)
        return memories[:8]

    def _call_extraction_llm(self, prompt: str) -> str:
        protocol = str(self.config.llm.protocol or "openai_chat_completions")
        if protocol == "openai_responses":
            payload = {
                "model": self.config.llm.model,
                "input": [
                    {"role": "system", "content": DIRECT_EXTRACTION_SYSTEM_PROMPT},
                    {"role": "user", "content": prompt},
                ],
                "max_output_tokens": 1400,
                "temperature": 0,
                "text": {"format": {"type": "json_object"}},
            }
            raw = _post_json(
                _endpoint_url(self.config.llm.base_url, "responses"),
                payload,
                token=self.config.llm.token,
                timeout_seconds=self.config.adapter_timeout_seconds,
            )
            return _responses_text(raw)
        if protocol == "anthropic_messages":
            raise RuntimeError("Direct memory extraction does not support Anthropic Messages yet; use OpenAI-compatible chat or Responses for mem0 capture.")

        payload = {
            "model": self.config.llm.model,
            "messages": [
                {"role": "system", "content": DIRECT_EXTRACTION_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            "max_tokens": 1400,
            "temperature": 0,
            "response_format": {"type": "json_object"},
        }
        raw = _post_json(
            _endpoint_url(self.config.llm.base_url, "chat/completions"),
            payload,
            token=self.config.llm.token,
            timeout_seconds=self.config.adapter_timeout_seconds,
        )
        return _chat_completion_text(raw)

    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        if not self.available or self.client is None:
            return None
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return None
        body = str(memory.get("body") or memory.get("title") or "").strip()
        if not body:
            return None
        project_id = str(memory.get("project_id") or "default")
        metadata = self._metadata_from_memory(memory)
        raw = self.client.add(body, user_id=project_id, metadata=metadata, infer=False)
        items = raw.get("results", raw) if isinstance(raw, dict) else raw
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict):
                    return self._memory_from_mem0_item(item, fallback_metadata=metadata)
        if isinstance(raw, dict):
            return self._memory_from_mem0_item(raw, fallback_metadata=metadata)
        return None

    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.client is None or not project_id:
            return []
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return []
        filters: dict[str, Any] = {"user_id": project_id}
        if status:
            filters["status"] = status
        if memory_type:
            filters["type"] = memory_type
        raw = self.client.get_all(filters=filters, top_k=limit)
        items = raw.get("results", raw) if isinstance(raw, dict) else raw
        if not isinstance(items, list):
            return []
        memories = [self._memory_from_mem0_item(item) for item in items if isinstance(item, dict)]
        return [memory for memory in memories if memory is not None]

    def get_memory(self, memory_id: str) -> dict[str, Any] | None:
        if not self.available or self.client is None:
            return None
        try:
            raw = self.client.get(memory_id)
        except Exception as error:  # noqa: BLE001
            self.last_error = _compact_error(error)
            return None
        if isinstance(raw, dict):
            return self._memory_from_mem0_item(raw)
        return None

    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
        if not self.available or self.client is None:
            return None
        existing = self.get_memory(memory_id)
        if existing is None:
            return None
        merged = existing | {key: value for key, value in updates.items() if value is not None}
        metadata = self._metadata_from_memory(merged)
        body = str(merged.get("body") or merged.get("title") or "")
        self.client.update(memory_id, body, metadata=metadata)
        return self.get_memory(memory_id) or (merged | {"id": memory_id, "metadata": metadata})

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

    def inference_errors(self) -> list[dict[str, str]]:
        return []

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.client is None or not query.strip():
            return []
        if project_id is None:
            return []
        if endpoint_error := _endpoint_error(self.config):
            self.last_error = endpoint_error
            return []
        filters = {"user_id": project_id, "status": "active"}
        raw = self.client.search(query, filters=filters, top_k=limit)
        items = raw.get("results", raw) if isinstance(raw, dict) else raw
        if not isinstance(items, list):
            return []
        results: list[dict[str, Any]] = []
        for rank, item in enumerate(items, start=1):
            if not isinstance(item, dict):
                continue
            memory = self._memory_from_mem0_item(item)
            if memory is None:
                continue
            score = float(item.get("score") or item.get("distance") or 0.0)
            results.append(
                {
                    "rank": rank,
                    "score": score,
                    "memory": memory,
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

    def _metadata_from_memory(self, memory: dict[str, Any]) -> dict[str, str]:
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
            "source_refs_json": json.dumps(source_refs, sort_keys=True, ensure_ascii=False),
            "scopes_json": json.dumps(scopes, sort_keys=True, ensure_ascii=False),
            "legacy_memory_id": str(memory.get("id") or metadata.get("legacy_memory_id") or ""),
        }

    def _memory_from_mem0_item(self, item: dict[str, Any], *, fallback_metadata: dict[str, Any] | None = None) -> dict[str, Any] | None:
        text = str(item.get("memory") or item.get("text") or item.get("body") or "").strip()
        if not text:
            return None
        metadata = item.get("metadata") if isinstance(item.get("metadata"), dict) else {}
        merged_metadata = {str(key): str(value) for key, value in (fallback_metadata or {}).items() if value is not None}
        merged_metadata.update({str(key): str(value) for key, value in metadata.items() if value is not None})
        memory_id = str(item.get("id") or merged_metadata.get("legacy_memory_id") or hashlib.sha256(text.encode("utf-8")).hexdigest()[:24])
        project_id = str(item.get("user_id") or merged_metadata.get("project_id") or merged_metadata.get("user_id") or "default")
        source_refs = _json_list(merged_metadata.get("source_refs_json"))
        scopes = _json_list(merged_metadata.get("scopes_json")) or [
            {"id": f"project:{project_id}", "kind": "project", "key": project_id, "title": project_id, "metadata": {}, "primary": True}
        ]
        return {
            "id": memory_id,
            "project_id": project_id,
            "type": str(merged_metadata.get("type") or "fact"),
            "status": str(merged_metadata.get("status") or "active"),
            "title": str(merged_metadata.get("title") or text[:120] or "mem0 memory")[:160],
            "body": text,
            "normalized_claim": str(item.get("hash") or merged_metadata.get("hash") or hashlib.sha256(text.lower().encode("utf-8")).hexdigest()),
            "confidence": _float(merged_metadata.get("confidence"), 0.82),
            "importance": _float(merged_metadata.get("importance"), 0.6),
            "source_refs": source_refs + ([{"kind": "mem0", "uri": memory_id}] if not any(ref.get("kind") == "mem0" for ref in source_refs) else []),
            "metadata": merged_metadata | {"adapter": "mem0", "mem0_id": memory_id},
            "scopes": scopes,
            "valid_at": _timestamp_or_none(merged_metadata.get("valid_at")),
            "invalid_at": _timestamp_or_none(merged_metadata.get("invalid_at")),
            "review_reason": merged_metadata.get("review_reason") or None,
            "extracted_by": merged_metadata.get("extracted_by") or "mem0",
            "created_at": _timestamp(item.get("created_at") or merged_metadata.get("created_at")),
            "updated_at": _timestamp(item.get("updated_at") or merged_metadata.get("updated_at")),
        }


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
            if endpoint_error := _endpoint_error(self.config):
                return {"graphiti": f"configured but endpoint unavailable: {endpoint_error}"}
            return {"graphiti": f"enabled: local kuzu + {_protocol_label(self.config.llm.protocol)} LLM + local embedding"}
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

    def inference_errors(self) -> list[dict[str, str]]:
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


def _mem0_result_items(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, dict):
        items = raw.get("results")
        if isinstance(items, list):
            return [item for item in items if isinstance(item, dict)]
        return [raw]
    if isinstance(raw, list):
        return [item for item in raw if isinstance(item, dict)]
    return []


def _endpoint_url(base_url: str, endpoint: str) -> str:
    return f"{base_url.rstrip('/')}/{endpoint.lstrip('/')}"


def _post_json(url: str, payload: dict[str, Any], *, token: str, timeout_seconds: float) -> dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=max(1.0, float(timeout_seconds))) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace") if error.fp else str(error)
        raise RuntimeError(f"LLM extraction HTTP {error.code}: {_compact_error(Exception(detail))}") from error
    except TimeoutError as error:
        raise TimeoutError(f"LLM extraction timed out after {timeout_seconds:.0f}s") from error
    except OSError as error:
        raise RuntimeError(f"LLM extraction network error: {_compact_error(error)}") from error
    try:
        decoded = json.loads(data.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise RuntimeError("LLM extraction returned non-JSON HTTP response") from error
    if not isinstance(decoded, dict):
        raise RuntimeError("LLM extraction returned unexpected JSON response")
    return decoded


def _chat_completion_text(raw: dict[str, Any]) -> str:
    choices = raw.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0] if isinstance(choices[0], dict) else {}
    message = first.get("message") if isinstance(first.get("message"), dict) else {}
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(str(part.get("text") or "") for part in content if isinstance(part, dict))
    return ""


def _responses_text(raw: dict[str, Any]) -> str:
    text = raw.get("output_text")
    if isinstance(text, str) and text.strip():
        return text
    parts: list[str] = []
    for item in raw.get("output") or []:
        if not isinstance(item, dict):
            continue
        for content in item.get("content") or []:
            if isinstance(content, dict) and isinstance(content.get("text"), str):
                parts.append(content["text"])
    return "".join(parts)


def _parse_extracted_memories(text: str) -> list[dict[str, Any]]:
    payload = _json_payload_from_text(text)
    if payload is None:
        raise RuntimeError("LLM extraction did not return the required JSON memory payload")
    raw_items: Any
    if isinstance(payload, dict):
        raw_items = payload.get("memories", [])
    else:
        raw_items = payload
    if isinstance(raw_items, dict):
        raw_items = [raw_items]
    if not isinstance(raw_items, list):
        return []
    memories: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw_items:
        memory = _normalise_extracted_memory(item)
        if memory is None:
            continue
        key = str(memory["memory"]).strip().lower()
        if key in seen:
            continue
        seen.add(key)
        memories.append(memory)
    return memories


def _json_payload_from_text(text: str) -> Any | None:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = re.sub(r"^```(?:json)?\s*", "", stripped, flags=re.IGNORECASE)
        stripped = re.sub(r"\s*```$", "", stripped).strip()
    for candidate in (stripped, _balanced_json_slice(stripped, "{", "}"), _balanced_json_slice(stripped, "[", "]")):
        if not candidate:
            continue
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    return None


def _balanced_json_slice(text: str, opener: str, closer: str) -> str:
    start = text.find(opener)
    end = text.rfind(closer)
    if start == -1 or end == -1 or end <= start:
        return ""
    return text[start : end + 1]


def _normalise_extracted_memory(item: Any) -> dict[str, Any] | None:
    if isinstance(item, str):
        text = item.strip()
        raw: dict[str, Any] = {}
    elif isinstance(item, dict):
        raw = item
        text = str(item.get("memory") or item.get("body") or item.get("text") or item.get("claim") or "").strip()
    else:
        return None
    if not text or _looks_like_non_memory_text(text):
        return None
    memory_type = str(raw.get("type") or "fact").strip().lower()
    if memory_type not in {"convention", "workflow", "fact", "decision", "risk", "command"}:
        memory_type = "fact"
    return {
        "memory": text,
        "title": str(raw.get("title") or text[:120]).strip()[:160],
        "type": memory_type,
        "confidence": _bounded_float(raw.get("confidence"), 0.82),
        "importance": _bounded_float(raw.get("importance"), 0.6),
    }


def _looks_like_non_memory_text(text: str) -> bool:
    head = "\n".join(text.lstrip().splitlines()[:8])
    if "Project:" in head and "Source kind:" in head and "Source path:" in head:
        return True
    stripped = text.lstrip()
    if stripped.startswith(("{", "[")) and any(marker in stripped[:1200] for marker in ('"permissions"', '"env"', '"session_meta"')):
        return True
    return len(text) > 2400


def _bounded_float(value: Any, default: float) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return max(0.0, min(1.0, number))


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


def _timestamp_or_none(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return _timestamp(value)
    except Exception:  # noqa: BLE001
        return None


def _safe_group_id(value: str | None) -> str:
    raw = value or "default"
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in raw)
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]
    return f"p_{safe[:48]}_{digest}"


def _mem0_llm_config(config: LocalAIConfig) -> tuple[str, dict[str, Any]]:
    protocol = config.llm.protocol
    if protocol == "openai_responses":
        _register_mem0_custom_providers_if_available()
        return (
            "claude_stats_openai_responses",
            {
                "model": config.llm.model,
                "api_key": config.llm.token,
                "openai_base_url": config.llm.base_url,
            },
        )
    if protocol == "anthropic_messages":
        _register_mem0_custom_providers_if_available()
        return (
            "claude_stats_anthropic_messages",
            {
                "model": config.llm.model,
                "api_key": config.llm.token,
                "anthropic_base_url": config.llm.base_url,
            },
        )
    return (
        "openai",
        {
            "model": config.llm.model,
            "api_key": config.llm.token,
            "openai_base_url": config.llm.base_url,
        },
    )


def _register_mem0_custom_providers_if_available() -> None:
    try:
        from .llm_providers import register_mem0_llm_providers

        register_mem0_llm_providers()
    except ImportError:
        return


def _mem0_embedder_config(config: LocalAIConfig) -> dict[str, Any]:
    return {
        "model": config.embedding_model,
        "api_key": config.embedding_token,
        "openai_base_url": config.embedding_base_url,
        "embedding_dims": config.embedding_dims,
    }


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


def _protocol_label(protocol: str) -> str:
    return {
        "openai_chat_completions": "OpenAI Chat",
        "openai_responses": "OpenAI Responses",
        "anthropic_messages": "Anthropic Messages",
    }.get(protocol, protocol or "unknown")


def _endpoint_error(config: LocalAIConfig) -> str:
    llm_error = _endpoint_url_error(config.llm.base_url, label="LLM")
    if llm_error:
        return llm_error
    embedding_error = _endpoint_url_error(config.embedding.base_url, label="embedding")
    if embedding_error:
        return embedding_error
    return ""


def _endpoint_url_error(base_url: str, *, label: str) -> str:
    parsed = urlparse(base_url)
    host = parsed.hostname
    if not host:
        return f"{label} base URL is not configured"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        with socket.create_connection((host, port), timeout=0.25):
            return ""
    except OSError as error:
        detail = error.strerror or str(error)
        if host in {"127.0.0.1", "localhost", "::1"} and port == 18765:
            return f"{label} local AI helper stopped or unreachable at {host}:{port} ({detail})"
        return f"{label} endpoint {host}:{port} is unreachable ({detail})"


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
        return NullAdapters(_disabled_detail(config))
    adapters: list[MemoryAdapters] = []
    if config.mem0_enabled:
        adapters.append(Mem0Adapter(config))
    if config.graphiti_enabled:
        adapters.append(GraphitiAdapter(config))
    if not adapters:
        return NullAdapters("mem0 and Graphiti are disabled")
    return CompositeAdapters(adapters)


def _disabled_detail(config: LocalAIConfig) -> str:
    if config.source == "disabled" and config.llm.model:
        return config.llm.model
    if not config.mem0_enabled and not config.graphiti_enabled:
        return "memory model adapters are disabled"
    if not config.llm.enabled:
        return "LLM endpoint is not configured"
    if not config.embedding.enabled:
        return "local embedding endpoint is not configured"
    return "memory model runtime is not configured"
