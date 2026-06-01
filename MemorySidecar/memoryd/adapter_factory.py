from __future__ import annotations

from .adapter_protocols import CompositeAdapters, KnowledgeGraphProjector, MemoryAdapters, MemoryProvider, NullAdapters
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
    memory_provider: MemoryProvider | None = None
    graph_projector: KnowledgeGraphProjector | None = None
    if config.mem0_enabled:
        memory_provider = Mem0Adapter(config, diagnostics=diagnostics)
    if config.graphiti_enabled:
        graph_projector = GraphitiAdapter(config)
    if memory_provider is None and graph_projector is None:
        return NullAdapters("mem0 and Graphiti are disabled")
    return CompositeAdapters(memory_provider=memory_provider, graph_projector=graph_projector)


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
