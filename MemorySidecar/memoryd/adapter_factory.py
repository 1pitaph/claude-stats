from __future__ import annotations

from .adapter_protocols import CompositeAdapters, MemoryAdapters, NullAdapters
from .config import LocalAIConfig, load_local_ai_config
from .diagnostics import MemoryDiagnosticsLogger
from .graphiti_adapter import GraphitiAdapter
from .mem0_adapter import Mem0Adapter


def build_adapters(
    root,
    *,
    config: LocalAIConfig | None = None,
    diagnostics: MemoryDiagnosticsLogger | None = None,
) -> MemoryAdapters:
    config = config or load_local_ai_config(root)
    if not config.enabled:
        return NullAdapters(_disabled_detail(config))
    adapters: list[MemoryAdapters] = []
    if config.mem0_enabled:
        adapters.append(Mem0Adapter(config, diagnostics=diagnostics))
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
