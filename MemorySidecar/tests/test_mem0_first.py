from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import Any

from memoryd.store import MemoryStore


class FakeMem0Adapters:
    def __init__(self) -> None:
        self.captured_chunks: list[dict[str, Any]] = []
        self.memories: dict[str, dict[str, Any]] = {}

    def names(self) -> list[str]:
        return ["mem0"]

    def health(self) -> dict[str, str]:
        return {"mem0": "enabled: fake"}

    def index_memory(self, memory: dict[str, Any], event: dict[str, Any], *, adapter_name: str | None = None) -> dict[str, str]:
        return {}

    def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        self.captured_chunks.extend(chunks)
        captured: list[dict[str, Any]] = []
        for index, chunk in enumerate(chunks, start=1):
            memory_id = f"mem0:{len(self.memories) + 1}"
            memory = {
                "id": memory_id,
                "project_id": chunk["project_id"],
                "type": chunk["type"],
                "status": "active",
                "title": chunk["title"],
                "body": f"captured:{chunk['section'] or chunk['title']}",
                "normalized_claim": memory_id,
                "confidence": 0.82,
                "importance": 0.6,
                "scopes": chunk["scopes"],
                "source_refs": chunk["source_refs"],
                "metadata": {"adapter": "mem0", "source_id": source["id"]},
                "created_at": 1,
                "updated_at": 1,
                "extracted_by": "mem0",
            }
            self.memories[memory_id] = memory
            captured.append(memory)
        return captured

    def capture_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        memory_id = f"mem0:{len(self.memories) + 1}"
        captured = dict(memory)
        captured["id"] = memory_id
        captured["metadata"] = (captured.get("metadata") or {}) | {"adapter": "mem0", "legacy_memory_id": memory.get("id", "")}
        captured["extracted_by"] = "mem0"
        self.memories[memory_id] = captured
        return captured

    def list_memories(self, *, project_id: str | None, status: str | None, memory_type: str | None, limit: int) -> list[dict[str, Any]]:
        return [
            memory
            for memory in self.memories.values()
            if (not project_id or memory["project_id"] == project_id)
            and (not status or memory["status"] == status)
            and (not memory_type or memory["type"] == memory_type)
        ][:limit]

    def get_memory(self, memory_id: str) -> dict[str, Any] | None:
        return self.memories.get(memory_id)

    def update_memory(self, memory_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
        memory = self.memories.get(memory_id)
        if memory is None:
            return None
        memory.update({key: value for key, value in updates.items() if value is not None})
        return memory

    def infer_memories(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        return []

    def inference_errors(self) -> list[dict[str, str]]:
        return []

    def search(self, query: str, *, project_id: str | None, limit: int) -> list[dict[str, Any]]:
        return []

    def graph(self, project_id: str, *, limit: int = 80) -> dict[str, list[dict[str, Any]]]:
        return {"nodes": [], "edges": []}


class Mem0FirstStoreTests(unittest.TestCase):
    def test_claude_md_is_chunked_and_captured_with_inference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            adapters = FakeMem0Adapters()
            store = MemoryStore(Path(directory), adapters=adapters)
            try:
                response = store.ingest_source(
                    {
                        "id": "src:claude",
                        "project_id": "/repo",
                        "title": "CLAUDE.md",
                        "kind": "CLAUDE.md",
                        "path": "/repo/CLAUDE.md",
                        "uri": "/repo/CLAUDE.md",
                        "body": "# Build\nRun tests.\n\n# Release\nTag releases.",
                        "content_hash": "hash1",
                        "metadata": {},
                    }
                )

                self.assertEqual(response["status"], "queued")
                self.assertEqual(response["queued"], 1)
                self.assertEqual(len(response["created"]), 0)
                self.assertEqual(store.health()["capture_pending"], 1)

                drained = store.drain_projection_jobs(limit=5)

                self.assertEqual(drained["delivered"], 2)
                self.assertEqual([chunk["section"] for chunk in adapters.captured_chunks], ["Build", "Release"])
                self.assertTrue(all(chunk["infer"] for chunk in adapters.captured_chunks))
                self.assertTrue(all("reusable repository rules" in chunk["prompt"] for chunk in adapters.captured_chunks))
                self.assertEqual(store.memories(project_id="/repo")["memories"][0]["extracted_by"], "mem0")
            finally:
                store.close()

    def test_same_source_hash_is_skipped_after_successful_capture(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            adapters = FakeMem0Adapters()
            store = MemoryStore(Path(directory), adapters=adapters)
            payload = {
                "id": "src:agents",
                "project_id": "/repo",
                "title": "AGENTS.md",
                "kind": "AGENTS.md",
                "path": "/repo/AGENTS.md",
                "uri": "/repo/AGENTS.md",
                "body": "# Rules\nUse apply_patch.",
                "content_hash": "hash2",
                "metadata": {},
            }
            try:
                first = store.ingest_source(payload)
                store.drain_projection_jobs(limit=5)
                second = store.ingest_source(payload)

                self.assertEqual(first["status"], "queued")
                self.assertEqual(second["status"], "skipped")
                self.assertEqual(len(adapters.captured_chunks), 1)
            finally:
                store.close()

    def test_terminal_capture_is_stored_raw_without_inference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            adapters = FakeMem0Adapters()
            store = MemoryStore(Path(directory), adapters=adapters)
            try:
                response = store.ingest_source(
                    {
                        "id": "src:terminal",
                        "project_id": "/repo",
                        "title": "/bin/echo ok",
                        "kind": "terminal_capture",
                        "path": "",
                        "uri": "terminal://1",
                        "body": "ok\n",
                        "content_hash": "hash3",
                        "metadata": {},
                    }
                )

                self.assertEqual(response["status"], "queued")
                store.drain_projection_jobs(limit=5)
                self.assertEqual(len(adapters.captured_chunks), 1)
                self.assertFalse(adapters.captured_chunks[0]["infer"])
                self.assertEqual(adapters.captured_chunks[0]["type"], "workflow")
            finally:
                store.close()


if __name__ == "__main__":
    unittest.main()
