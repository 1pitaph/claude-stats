from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class LLMEndpointConfig:
    protocol: str
    base_url: str
    token: str
    model: str

    @property
    def enabled(self) -> bool:
        return bool(self.protocol and self.base_url and self.token and self.model)


@dataclass(frozen=True)
class EmbeddingEndpointConfig:
    base_url: str
    token: str
    model: str
    dimensions: int

    @property
    def enabled(self) -> bool:
        return bool(self.base_url and self.token and self.model and self.dimensions > 0)


@dataclass(frozen=True)
class MemoryModelConfig:
    llm: LLMEndpointConfig
    embedding: EmbeddingEndpointConfig
    mem0_enabled: bool
    graphiti_enabled: bool
    qdrant_path: Path
    kuzu_path: Path
    adapter_timeout_seconds: float
    diagnostics_retention_days: int = 3
    configuration_hash: str = ""
    source: str = "env"

    @property
    def enabled(self) -> bool:
        return bool(self.llm.enabled and self.embedding.enabled and (self.mem0_enabled or self.graphiti_enabled))

    @property
    def base_url(self) -> str:
        return self.llm.base_url

    @property
    def token(self) -> str:
        return self.llm.token

    @property
    def llm_model(self) -> str:
        return self.llm.model

    @property
    def embedding_base_url(self) -> str:
        return self.embedding.base_url

    @property
    def embedding_token(self) -> str:
        return self.embedding.token

    @property
    def embedding_model(self) -> str:
        return self.embedding.model

    @property
    def embedding_dims(self) -> int:
        return self.embedding.dimensions


LocalAIConfig = MemoryModelConfig


def load_local_ai_config(root: Path) -> MemoryModelConfig:
    os.environ["MEM0_TELEMETRY"] = "false"
    os.environ["GRAPHITI_TELEMETRY_ENABLED"] = "false"
    runtime_path = os.environ.get("CLAUDE_STATS_MEMORY_RUNTIME_CONFIG", "").strip()
    if runtime_path:
        try:
            return _load_runtime_config(Path(runtime_path), root)
        except Exception as error:  # noqa: BLE001
            return _disabled_config(root, f"runtime config failed: {error}")
    return _load_legacy_env_config(root)


def _load_runtime_config(path: Path, root: Path) -> MemoryModelConfig:
    raw = json.loads(path.read_text(encoding="utf-8"))
    llm = _dict(raw.get("llm"))
    embedding = _dict(raw.get("embedding"))
    diagnostics = _dict(raw.get("diagnostics"))
    return MemoryModelConfig(
        llm=LLMEndpointConfig(
            protocol=str(llm.get("protocol") or "").strip(),
            base_url=str(llm.get("base_url") or "").rstrip("/"),
            token=str(llm.get("api_key") or llm.get("token") or ""),
            model=str(llm.get("model") or "").strip(),
        ),
        embedding=EmbeddingEndpointConfig(
            base_url=str(embedding.get("base_url") or "").rstrip("/"),
            token=str(embedding.get("api_key") or embedding.get("token") or ""),
            model=str(embedding.get("model") or "").strip(),
            dimensions=_int_value(embedding.get("dimensions"), 0),
        ),
        mem0_enabled=_bool_value(raw.get("mem0_enabled")),
        graphiti_enabled=_bool_value(raw.get("graphiti_enabled")),
        qdrant_path=root / "mem0-qdrant",
        kuzu_path=root / "graphiti.kuzu",
        adapter_timeout_seconds=_float_env("CLAUDE_STATS_MEMORY_ADAPTER_TIMEOUT_SECONDS", 120.0),
        diagnostics_retention_days=_retention_days(diagnostics.get("retention_days")),
        configuration_hash=str(raw.get("configuration_hash") or ""),
        source="runtime_config",
    )


def _load_legacy_env_config(root: Path) -> MemoryModelConfig:
    base_url = os.environ.get("CLAUDE_STATS_LOCAL_AI_BASE_URL", "").rstrip("/")
    token = os.environ.get("CLAUDE_STATS_LOCAL_AI_TOKEN", "")
    return MemoryModelConfig(
        llm=LLMEndpointConfig(
            protocol="openai_chat_completions",
            base_url=base_url,
            token=token,
            model=os.environ.get("CLAUDE_STATS_LOCAL_LLM_MODEL", ""),
        ),
        embedding=EmbeddingEndpointConfig(
            base_url=base_url,
            token=token,
            model=os.environ.get("CLAUDE_STATS_LOCAL_EMBEDDING_MODEL", ""),
            dimensions=_int_env("CLAUDE_STATS_LOCAL_EMBEDDING_DIMS", 0),
        ),
        mem0_enabled=_bool_env("CLAUDE_STATS_MEM0_ENABLED"),
        graphiti_enabled=_bool_env("CLAUDE_STATS_GRAPHITI_ENABLED"),
        qdrant_path=root / "mem0-qdrant",
        kuzu_path=root / "graphiti.kuzu",
        adapter_timeout_seconds=_float_env("CLAUDE_STATS_MEMORY_ADAPTER_TIMEOUT_SECONDS", 120.0),
        diagnostics_retention_days=_retention_days(os.environ.get("CLAUDE_STATS_MEMORY_DIAGNOSTICS_RETENTION_DAYS")),
        configuration_hash=os.environ.get("CLAUDE_STATS_LOCAL_AI_CONFIG_HASH", ""),
        source="legacy_env",
    )


def _disabled_config(root: Path, detail: str) -> MemoryModelConfig:
    return MemoryModelConfig(
        llm=LLMEndpointConfig(protocol="", base_url="", token="", model=detail),
        embedding=EmbeddingEndpointConfig(base_url="", token="", model="", dimensions=0),
        mem0_enabled=False,
        graphiti_enabled=False,
        qdrant_path=root / "mem0-qdrant",
        kuzu_path=root / "graphiti.kuzu",
        adapter_timeout_seconds=_float_env("CLAUDE_STATS_MEMORY_ADAPTER_TIMEOUT_SECONDS", 120.0),
        diagnostics_retention_days=_retention_days(os.environ.get("CLAUDE_STATS_MEMORY_DIAGNOSTICS_RETENTION_DAYS")),
        source="disabled",
    )


def _dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _bool_env(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


def _bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _int_env(name: str, default: int) -> int:
    return _int_value(os.environ.get(name), default)


def _int_value(value: Any, default: int) -> int:
    try:
        return int(value if value is not None else default)
    except (TypeError, ValueError):
        return default


def _float_env(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, str(default)))
    except ValueError:
        return default


def _retention_days(value: Any) -> int:
    try:
        parsed = int(value if value is not None else 3)
    except (TypeError, ValueError):
        parsed = 3
    return 7 if parsed >= 7 else 3
