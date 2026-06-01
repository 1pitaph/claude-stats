from __future__ import annotations

import json
import time
from typing import Any

from .adapter_utils import compact_error, endpoint_error, protocol_label
from .config import LocalAIConfig
from .diagnostics import MemoryDiagnosticsLogger, input_fingerprint, text_fingerprint
from .memory_mirror import mem0_result_items, metadata_from_memory, mirror_from_mem0_item


class Mem0Adapter:
    name = "mem0"

    def __init__(self, config: LocalAIConfig, diagnostics: MemoryDiagnosticsLogger | None = None):
        self.config = config
        self.diagnostics = diagnostics
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
            _instrument_mem0_embedding_client(self.client, config, diagnostics)
            self.available = True
        except Exception as error:  # noqa: BLE001
            self.client = None
            self.available = False
            self.last_error = str(error)
            if diagnostics is not None:
                diagnostics.log("mem0.adapter.init.error", level="error", error=compact_error(error))

    def health(self) -> dict[str, str]:
        if self.available:
            if error := endpoint_error(self.config):
                return {"mem0": f"configured but endpoint unavailable: {error}"}
            return {"mem0": f"enabled: local qdrant + {protocol_label(self.config.llm.protocol)} LLM + local embedding"}
        return {"mem0": f"unavailable: {self.last_error}"}

    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not self.available or self.client is None:
            return []
        self.last_error = ""
        if error := endpoint_error(self.config):
            self.last_error = error
            return []
        captured: list[dict[str, Any]] = []
        for index, chunk in enumerate(chunks, start=1):
            body = str(chunk.get("body") or "").strip()
            if not body:
                continue
            project_id = str(chunk.get("project_id") or source.get("project_id") or "default")
            run_id = _run_id_for_source(source, chunk)
            chunk_started = time.time()
            if self.diagnostics is not None:
                self.diagnostics.log(
                    "capture.chunk.start",
                    run_id=str(chunk.get("run_id") or source.get("run_id") or ""),
                    source_id=str(source.get("id") or ""),
                    source_kind=str(source.get("kind") or ""),
                    project_id=project_id,
                    chunk_index=index,
                    **text_fingerprint(body),
                )
            fallback_metadata = self._metadata_for_source_chunk(source, chunk, project_id=project_id, chunk_index=index)
            prompt = str(chunk.get("prompt") or "").strip() or None
            raw = self._add_to_mem0(
                [{"role": "user", "content": body}],
                project_id=project_id,
                metadata=fallback_metadata,
                run_id=run_id,
                source=source,
                chunk_index=index,
                infer=True,
                prompt=prompt,
            )
            items = mem0_result_items(raw)
            for item in items:
                memory = mirror_from_mem0_item(
                    item,
                    fallback_metadata=fallback_metadata,
                    default_project_id=project_id,
                    default_source_refs=_source_refs_from_chunk(source, chunk),
                    default_scopes=_scopes_from_chunk(source, chunk, project_id),
                    default_status=str(chunk.get("status") or "active"),
                    capture_version=str(chunk.get("capture_version") or ""),
                )
                if memory is not None:
                    captured.append(memory)
            if self.diagnostics is not None:
                self.diagnostics.log(
                    "capture.chunk.end",
                    run_id=str(chunk.get("run_id") or source.get("run_id") or ""),
                    source_id=str(source.get("id") or ""),
                    source_kind=str(source.get("kind") or ""),
                    project_id=project_id,
                    chunk_index=index,
                    duration_ms=int((time.time() - chunk_started) * 1000),
                    counts={"accepted": len(items)},
                )
        return captured

    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        if not self.available or self.client is None:
            return None
        if error := endpoint_error(self.config):
            self.last_error = error
            return None
        body = str(memory.get("body") or memory.get("title") or "").strip()
        if not body:
            return None
        project_id = str(memory.get("project_id") or "default")
        metadata = metadata_from_memory(memory)
        raw = self._call_mem0_add(body, user_id=project_id, metadata=metadata, infer=False)
        for item in mem0_result_items(raw):
            mirror = mirror_from_mem0_item(item, fallback_metadata=metadata, default_project_id=project_id)
            if mirror is not None:
                return mirror
        return None

    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.client is None or not project_id:
            return []
        if error := endpoint_error(self.config):
            self.last_error = error
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
        memories = [mirror_from_mem0_item(item, default_project_id=project_id) for item in items if isinstance(item, dict)]
        return [memory for memory in memories if memory is not None]

    def get_memory(self, memory_id: str) -> dict[str, Any] | None:
        if not self.available or self.client is None:
            return None
        try:
            raw = self.client.get(memory_id)
        except Exception as error:  # noqa: BLE001
            self.last_error = compact_error(error)
            return None
        if isinstance(raw, dict):
            return mirror_from_mem0_item(raw)
        return None

    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
        if not self.available or self.client is None:
            return None
        existing = self.get_memory(memory_id)
        if existing is None:
            return None
        merged = existing | {key: value for key, value in updates.items() if value is not None}
        metadata = metadata_from_memory(merged)
        body = str(merged.get("body") or merged.get("title") or "")
        self.client.update(memory_id, body, metadata=metadata)
        return self.get_memory(memory_id) or (merged | {"id": memory_id, "metadata": metadata})

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        if not self.available or self.client is None:
            return {"mem0": f"unavailable: {self.last_error}"}
        if error := endpoint_error(self.config):
            self.last_error = error
            return {"mem0": f"unavailable: {error}"}
        metadata = metadata_from_memory(memory) | {"event_id": str(event.get("event_id") or "")}
        raw = self._call_mem0_add(
            str(memory.get("body") or memory.get("title") or ""),
            user_id=str(memory.get("project_id") or "default"),
            metadata=metadata,
            infer=False,
        )
        adapter_id = _first_id(raw) or str(memory.get("id") or "")
        return {"mem0": f"ok:{adapter_id}"}

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        if not self.available or self.client is None:
            return []
        if error := endpoint_error(self.config):
            self.last_error = error
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
            "status": "proposed",
        }
        raw = self._call_mem0_add(body, user_id=project_id, metadata=metadata, infer=True)
        proposals: list[dict[str, Any]] = []
        for item in mem0_result_items(raw):
            memory = mirror_from_mem0_item(item, fallback_metadata=metadata, default_project_id=project_id, default_status="proposed")
            if memory is not None:
                memory["status"] = "proposed"
                proposals.append(memory)
        return proposals

    def inference_errors(self) -> list[dict[str, str]]:
        return []

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        if not self.available or self.client is None or not query.strip():
            return []
        if project_id is None:
            return []
        if error := endpoint_error(self.config):
            self.last_error = error
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
            memory = mirror_from_mem0_item(item, default_project_id=project_id)
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

    def _metadata_for_source_chunk(self, source: dict[str, Any], chunk: dict[str, Any], *, project_id: str, chunk_index: int) -> dict[str, str]:
        metadata = {
            "project_id": project_id,
            "status": str(chunk.get("status") or "active"),
            "type": str(chunk.get("type") or "fact"),
            "title": str(chunk.get("title") or source.get("title") or str(chunk.get("body") or "")[:120])[:160],
            "source_kind": str(source.get("kind") or ""),
            "source_path": str(source.get("path") or ""),
            "source_uri": str(source.get("uri") or ""),
            "source_id": str(source.get("id") or ""),
            "source_hash": str(source.get("content_hash") or ""),
            "section": str(chunk.get("section") or ""),
            "chunk_index": str(chunk_index),
            "capture_version": str(chunk.get("capture_version") or ""),
            "confidence": str(chunk.get("confidence") or "0.82"),
            "importance": str(chunk.get("importance") or "0.6"),
            "source": "claude-stats-memoryd",
            "provider": "mem0",
            "source_refs_json": json.dumps(_source_refs_from_chunk(source, chunk), sort_keys=True, ensure_ascii=False),
            "scopes_json": json.dumps(_scopes_from_chunk(source, chunk, project_id), sort_keys=True, ensure_ascii=False),
        }
        extra = chunk.get("metadata")
        if isinstance(extra, dict):
            metadata.update({str(key): str(value) for key, value in extra.items() if value is not None})
        return metadata

    def _add_to_mem0(
        self,
        messages: Any,
        *,
        project_id: str,
        metadata: dict[str, str],
        run_id: str = "",
        source: dict[str, Any],
        chunk_index: int,
        infer: bool = True,
        prompt: str | None = None,
    ) -> Any:
        started = time.time()
        if self.diagnostics is not None:
            self.diagnostics.log(
                "mem0.add.start",
                run_id=run_id,
                source_id=str(source.get("id") or ""),
                source_kind=str(source.get("kind") or ""),
                project_id=project_id,
                chunk_index=chunk_index,
                infer="true" if infer else "false",
                memory_type=str(metadata.get("type") or "fact"),
                **input_fingerprint(messages),
            )
        try:
            raw = self._call_mem0_add(
                messages,
                user_id=project_id,
                run_id=run_id or None,
                metadata=metadata,
                infer=infer,
                prompt=prompt,
            )
            if self.diagnostics is not None:
                self.diagnostics.log(
                    "mem0.add.end",
                    run_id=run_id,
                    source_id=str(source.get("id") or ""),
                    source_kind=str(source.get("kind") or ""),
                    project_id=project_id,
                    chunk_index=chunk_index,
                    infer="true" if infer else "false",
                    duration_ms=int((time.time() - started) * 1000),
                    counts={"items": len(mem0_result_items(raw))},
                )
            return raw
        except Exception as error:  # noqa: BLE001
            if self.diagnostics is not None:
                self.diagnostics.log(
                    "mem0.add.error",
                    level="error",
                    run_id=run_id,
                    source_id=str(source.get("id") or ""),
                    source_kind=str(source.get("kind") or ""),
                    project_id=project_id,
                    chunk_index=chunk_index,
                    duration_ms=int((time.time() - started) * 1000),
                    error=compact_error(error),
                )
            raise

    def _call_mem0_add(
        self,
        messages: Any,
        *,
        user_id: str,
        metadata: dict[str, Any],
        infer: bool,
        run_id: str | None = None,
        prompt: str | None = None,
    ) -> Any:
        kwargs: dict[str, Any] = {"user_id": user_id, "metadata": metadata, "infer": infer}
        if run_id:
            kwargs["run_id"] = run_id
        if prompt:
            kwargs["prompt"] = prompt
        try:
            return self.client.add(messages, **kwargs)
        except TypeError:
            # Test fakes and older mem0 versions may not accept run_id/prompt.
            return self.client.add(messages, user_id=user_id, metadata=metadata, infer=infer)


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


def _instrument_mem0_embedding_client(
    client: Any,
    config: LocalAIConfig,
    diagnostics: MemoryDiagnosticsLogger | None,
) -> None:
    if diagnostics is None:
        return
    target = getattr(getattr(client, "embedding_model", None), "client", None)
    embeddings = getattr(target, "embeddings", None)
    create = getattr(embeddings, "create", None)
    if target is None or embeddings is None or not callable(create):
        diagnostics.log(
            "embedding.instrumentation_unavailable",
            level="warning",
            model=config.embedding_model,
            reason="mem0 embedding client shape was not recognized",
        )
        return

    def create_wrapper(*args: Any, **kwargs: Any) -> Any:
        input_value = kwargs.get("input")
        if input_value is None and args:
            input_value = args[0]
        started = time.time()
        diagnostics.log(
            "embedding.request.start",
            model=str(kwargs.get("model") or config.embedding_model),
            dimensions=config.embedding_dims,
            **input_fingerprint(input_value),
        )
        try:
            result = create(*args, **kwargs)
            diagnostics.log(
                "embedding.request.end",
                model=str(kwargs.get("model") or config.embedding_model),
                dimensions=config.embedding_dims,
                duration_ms=int((time.time() - started) * 1000),
            )
            return result
        except Exception as error:  # noqa: BLE001
            diagnostics.log(
                "embedding.request.error",
                level="error",
                model=str(kwargs.get("model") or config.embedding_model),
                dimensions=config.embedding_dims,
                duration_ms=int((time.time() - started) * 1000),
                error=compact_error(error),
            )
            raise

    try:
        setattr(embeddings, "create", create_wrapper)
        diagnostics.log("embedding.instrumentation.enabled", model=config.embedding_model, dimensions=config.embedding_dims)
    except Exception as error:  # noqa: BLE001
        diagnostics.log(
            "embedding.instrumentation_unavailable",
            level="warning",
            model=config.embedding_model,
            reason=compact_error(error),
        )


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


def _first_id(raw: Any) -> str | None:
    for item in mem0_result_items(raw):
        if item.get("id"):
            return str(item["id"])
    return None


def _run_id_for_source(source: dict[str, Any], chunk: dict[str, Any]) -> str:
    return str(source.get("id") or chunk.get("run_id") or "")


def _source_refs_from_chunk(source: dict[str, Any], chunk: dict[str, Any]) -> list[dict[str, Any]]:
    refs = chunk.get("source_refs")
    if isinstance(refs, list):
        return [ref for ref in refs if isinstance(ref, dict)]
    return [
        {
            "kind": str(source.get("kind") or "source"),
            "uri": str(source.get("uri") or ""),
            "path": str(source.get("path") or ""),
            "content_hash": str(source.get("content_hash") or ""),
            "source_id": str(source.get("id") or ""),
            "episode_id": f"episode:{source.get('id')}",
        }
    ]


def _scopes_from_chunk(source: dict[str, Any], chunk: dict[str, Any], project_id: str) -> list[dict[str, Any]]:
    scopes = chunk.get("scopes")
    if isinstance(scopes, list):
        return [scope for scope in scopes if isinstance(scope, dict)]
    scope = source.get("scope")
    if isinstance(scope, dict):
        return [scope]
    return [{"id": f"project:{project_id}", "kind": "project", "key": project_id, "title": project_id, "metadata": {}, "primary": True}]
