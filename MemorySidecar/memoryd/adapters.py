from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class AdapterStatus:
    name: str
    enabled: bool
    detail: str


def mem0_status() -> AdapterStatus:
    return AdapterStatus(name="mem0", enabled=False, detail="disabled until an embedding/LLM provider is configured")


def graphiti_status() -> AdapterStatus:
    return AdapterStatus(name="graphiti", enabled=False, detail="disabled until a Graphiti provider is configured")
