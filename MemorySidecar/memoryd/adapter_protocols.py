from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any, Protocol

from .adapter_utils import compact_error


@dataclass
class AdapterHealth:
    name: str
    status: str
    detail: str


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
            name = _adapter_name(adapter)
            if name:
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
            name = _adapter_name(adapter)
            if adapter_name is not None and name != adapter_name:
                continue
            try:
                result = adapter.index_memory(memory, event, adapter_name=adapter_name)
                statuses.update(result)
            except Exception as error:  # noqa: BLE001
                message = compact_error(error)
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", message)
                statuses[str(name or "adapter")] = f"error: {message}"
        return statuses

    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        memories: list[dict[str, Any]] = []
        self.last_inference_errors = []
        for adapter in self.adapters:
            if _adapter_name(adapter) != "mem0":
                continue
            name = _adapter_name(adapter) or "adapter"
            try:
                memories.extend(adapter.capture_source(source, chunks))
            except Exception as error:  # noqa: BLE001
                message = compact_error(error)
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", message)
                self.last_inference_errors.append({"adapter": name, "error": message})
        return memories

    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        self.last_inference_errors = []
        for adapter in self.adapters:
            if _adapter_name(adapter) != "mem0":
                continue
            try:
                return adapter.capture_memory(memory)
            except Exception as error:  # noqa: BLE001
                message = compact_error(error)
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", message)
                self.last_inference_errors.append({"adapter": "mem0", "error": message})
        return None

    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]:
        for adapter in self.adapters:
            if _adapter_name(adapter) != "mem0":
                continue
            try:
                return adapter.list_memories(project_id=project_id, status=status, memory_type=memory_type, limit=limit)
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", compact_error(error))
        return []

    def get_memory(self, memory_id: str) -> dict[str, Any] | None:
        for adapter in self.adapters:
            if _adapter_name(adapter) != "mem0":
                continue
            try:
                return adapter.get_memory(memory_id)
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", compact_error(error))
        return None

    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
        for adapter in self.adapters:
            if _adapter_name(adapter) != "mem0":
                continue
            try:
                return adapter.update_memory(memory_id, updates)
            except Exception as error:  # noqa: BLE001
                if hasattr(adapter, "last_error"):
                    setattr(adapter, "last_error", compact_error(error))
        return None

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        proposals: list[dict[str, Any]] = []
        self.last_inference_errors = []
        for adapter in self.adapters:
            name = _adapter_name(adapter) or "adapter"
            before_error = str(getattr(adapter, "last_error", "") or "")
            try:
                adapter_proposals = adapter.infer_memories(source)
                proposals.extend(adapter_proposals)
            except Exception as error:  # noqa: BLE001
                message = compact_error(error)
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
                    setattr(adapter, "last_error", compact_error(error))
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
                    setattr(adapter, "last_error", compact_error(error))
        return {"nodes": nodes, "edges": edges}


def _adapter_name(adapter: MemoryAdapters) -> str:
    name = getattr(adapter, "name", None)
    if isinstance(name, str) and name:
        return name
    names = getattr(adapter, "names", None)
    if callable(names):
        try:
            raw_names = names()
        except Exception:  # noqa: BLE001
            return ""
        if isinstance(raw_names, list) and raw_names:
            first = raw_names[0]
            return str(first) if first is not None else ""
    return ""
