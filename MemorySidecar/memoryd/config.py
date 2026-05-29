from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class LocalAIConfig:
    base_url: str
    token: str
    llm_model: str
    embedding_model: str
    embedding_dims: int
    mem0_enabled: bool
    graphiti_enabled: bool
    qdrant_path: Path
    kuzu_path: Path

    @property
    def enabled(self) -> bool:
        return bool(self.base_url and self.token and (self.mem0_enabled or self.graphiti_enabled))


def load_local_ai_config(root: Path) -> LocalAIConfig:
    os.environ["MEM0_TELEMETRY"] = "false"
    os.environ["GRAPHITI_TELEMETRY_ENABLED"] = "false"
    return LocalAIConfig(
        base_url=os.environ.get("CLAUDE_STATS_LOCAL_AI_BASE_URL", "").rstrip("/"),
        token=os.environ.get("CLAUDE_STATS_LOCAL_AI_TOKEN", ""),
        llm_model=os.environ.get("CLAUDE_STATS_LOCAL_LLM_MODEL", ""),
        embedding_model=os.environ.get("CLAUDE_STATS_LOCAL_EMBEDDING_MODEL", ""),
        embedding_dims=_int_env("CLAUDE_STATS_LOCAL_EMBEDDING_DIMS", 0),
        mem0_enabled=_bool_env("CLAUDE_STATS_MEM0_ENABLED"),
        graphiti_enabled=_bool_env("CLAUDE_STATS_GRAPHITI_ENABLED"),
        qdrant_path=root / "mem0-qdrant",
        kuzu_path=root / "graphiti.kuzu",
    )


def _bool_env(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


def _int_env(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default

