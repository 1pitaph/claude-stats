from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Protocol

from .adapter_utils import compact_error


@dataclass
class AdapterHealth:
    name: str
    status: str
    detail: str


class MemoryProvider(Protocol):
    name: str

    def health(self) -> dict[str, str]: ...
    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]: ...
    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None: ...
    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]: ...
    def get_memory(self, memory_id: str) -> dict[str, Any] | None: ...
    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None: ...
    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]: ...
    def inference_errors(self) -> list[dict[str, str]]: ...
    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]: ...


class KnowledgeGraphProjector(Protocol):
    name: str

    def health(self) -> dict[str, str]: ...
    def project_memory_event(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]: ...
    def search_facts(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]: ...
    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]: ...


class MemoryAdapters(Protocol):
    def names(self) -> list[str]: ...
    def health(self) -> dict[str, str]: ...
    def project_memory_event(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]: ...
    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]: ...
    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]: ...
    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None: ...
    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]: ...
    def get_memory(self, memory_id: str) -> dict[str, Any] | None: ...
    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None: ...
    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]: ...
    def inference_errors(self) -> list[dict[str, str]]: ...
    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]: ...
    def search_facts(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]: ...
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

    def project_memory_event(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]:
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

    def search_facts(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        return []

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        return {"nodes": [], "edges": []}


class CompositeAdapters:
    def __init__(
        self,
        adapters: list[Any] | None = None,
        *,
        memory_provider: MemoryProvider | None = None,
        graph_projector: KnowledgeGraphProjector | None = None,
    ):
        self.memory_provider = memory_provider
        self.graph_projector = graph_projector
        self.last_inference_errors: list[dict[str, str]] = []
        self._extra_adapters: list[Any] = []
        for adapter in adapters or []:
            name = _adapter_name(adapter)
            if name == "mem0" and self.memory_provider is None:
                self.memory_provider = adapter
            elif name == "graphiti" and self.graph_projector is None:
                self.graph_projector = adapter
            else:
                self._extra_adapters.append(adapter)

    def names(self) -> list[str]:
        names: list[str] = []
        for adapter in self._ordered_adapters():
            name = _adapter_name(adapter)
            if name:
                names.append(name)
        return names

    def health(self) -> dict[str, str]:
        merged = {"graph_backend": "kuzu", "telemetry": "disabled"}
        for adapter in self._ordered_adapters():
            try:
                merged.update(adapter.health())
            except Exception as error:  # noqa: BLE001
                name = _adapter_name(adapter) or adapter.__class__.__name__
                merged[name] = f"error: {compact_error(error)}"
        if self.last_inference_errors:
            merged["last_inference_errors"] = json.dumps(self.last_inference_errors, sort_keys=True, ensure_ascii=False)
        return merged

    def project_memory_event(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]:
        if self.graph_projector is None:
            return {}
        try:
            return _project_memory_event(self.graph_projector, memory, event)
        except Exception as error:  # noqa: BLE001
            message = compact_error(error)
            if hasattr(self.graph_projector, "last_error"):
                setattr(self.graph_projector, "last_error", message)
            return {str(_adapter_name(self.graph_projector) or "graphiti"): f"error: {message}"}

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        statuses: dict[str, str] = {}
        if adapter_name in {None, "mem0"} and self.memory_provider is not None and hasattr(self.memory_provider, "index_memory"):
            statuses.update(_index_memory(self.memory_provider, memory, event, adapter_name=adapter_name))
        if adapter_name in {None, "graphiti"}:
            statuses.update(self.project_memory_event(memory, event))
        return statuses

    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        self.last_inference_errors = []
        if self.memory_provider is None:
            return []
        try:
            return self.memory_provider.capture_source(source, chunks)
        except Exception as error:  # noqa: BLE001
            message = compact_error(error)
            if hasattr(self.memory_provider, "last_error"):
                setattr(self.memory_provider, "last_error", message)
            self.last_inference_errors.append({"adapter": _adapter_name(self.memory_provider) or "mem0", "error": message})
            return []

    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        self.last_inference_errors = []
        if self.memory_provider is None:
            return None
        try:
            return self.memory_provider.capture_memory(memory)
        except Exception as error:  # noqa: BLE001
            message = compact_error(error)
            if hasattr(self.memory_provider, "last_error"):
                setattr(self.memory_provider, "last_error", message)
            self.last_inference_errors.append({"adapter": "mem0", "error": message})
        return None

    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]:
        if self.memory_provider is None:
            return []
        try:
            return self.memory_provider.list_memories(project_id=project_id, status=status, memory_type=memory_type, limit=limit)
        except Exception as error:  # noqa: BLE001
            if hasattr(self.memory_provider, "last_error"):
                setattr(self.memory_provider, "last_error", compact_error(error))
        return []

    def get_memory(self, memory_id: str) -> dict[str, Any] | None:
        if self.memory_provider is None:
            return None
        try:
            return self.memory_provider.get_memory(memory_id)
        except Exception as error:  # noqa: BLE001
            if hasattr(self.memory_provider, "last_error"):
                setattr(self.memory_provider, "last_error", compact_error(error))
        return None

    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
        if self.memory_provider is None:
            return None
        try:
            return self.memory_provider.update_memory(memory_id, updates)
        except Exception as error:  # noqa: BLE001
            if hasattr(self.memory_provider, "last_error"):
                setattr(self.memory_provider, "last_error", compact_error(error))
        return None

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        self.last_inference_errors = []
        if self.memory_provider is None:
            return []
        name = _adapter_name(self.memory_provider) or "mem0"
        before_error = str(getattr(self.memory_provider, "last_error", "") or "")
        try:
            proposals = self.memory_provider.infer_memories(source)
        except Exception as error:  # noqa: BLE001
            message = compact_error(error)
            if hasattr(self.memory_provider, "last_error"):
                setattr(self.memory_provider, "last_error", message)
            self.last_inference_errors.append({"adapter": name, "error": message})
            return []
        after_error = str(getattr(self.memory_provider, "last_error", "") or "")
        if after_error and (after_error != before_error or not proposals):
            self.last_inference_errors.append({"adapter": name, "error": after_error})
        return proposals

    def inference_errors(self) -> list[dict[str, str]]:
        return list(self.last_inference_errors)

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        if self.memory_provider is not None:
            try:
                results.extend(self.memory_provider.search(query, project_id=project_id, limit=limit))
            except Exception as error:  # noqa: BLE001
                if hasattr(self.memory_provider, "last_error"):
                    setattr(self.memory_provider, "last_error", compact_error(error))
        results.extend(self.search_facts(query, project_id=project_id, limit=limit))
        return results[:limit]

    def search_facts(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        if self.graph_projector is None:
            return []
        try:
            return _search_facts(self.graph_projector, query, project_id=project_id, limit=limit)
        except Exception as error:  # noqa: BLE001
            if hasattr(self.graph_projector, "last_error"):
                setattr(self.graph_projector, "last_error", compact_error(error))
        return []

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        if self.graph_projector is None:
            return {"nodes": [], "edges": []}
        try:
            graph = self.graph_projector.graph(project_id, limit=limit)
            return {
                "nodes": list(graph.get("nodes", [])),
                "edges": list(graph.get("edges", [])),
            }
        except Exception as error:  # noqa: BLE001
            if hasattr(self.graph_projector, "last_error"):
                setattr(self.graph_projector, "last_error", compact_error(error))
        return {"nodes": [], "edges": []}

    def _ordered_adapters(self) -> list[Any]:
        adapters: list[Any] = []
        if self.memory_provider is not None:
            adapters.append(self.memory_provider)
        if self.graph_projector is not None:
            adapters.append(self.graph_projector)
        adapters.extend(self._extra_adapters)
        return adapters


def _adapter_name(adapter: Any) -> str:
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


def _index_memory(adapter: Any, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
    index_memory = getattr(adapter, "index_memory", None)
    if not callable(index_memory):
        return {}
    try:
        return index_memory(memory, event, adapter_name=adapter_name)
    except TypeError:
        return index_memory(memory, event)


def _project_memory_event(adapter: Any, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]:
    project_memory_event = getattr(adapter, "project_memory_event", None)
    if callable(project_memory_event):
        return project_memory_event(memory, event)
    return _index_memory(adapter, memory, event, adapter_name="graphiti")


def _search_facts(adapter: Any, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
    search_facts = getattr(adapter, "search_facts", None)
    if callable(search_facts):
        return search_facts(query, project_id=project_id, limit=limit)
    search = getattr(adapter, "search", None)
    if callable(search):
        return search(query, project_id=project_id, limit=limit)
    return []
