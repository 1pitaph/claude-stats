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


class FakeGraphitiAdapters(FakeMem0Adapters):
    def __init__(self) -> None:
        super().__init__()
        self.projected_events: list[str] = []

    def names(self) -> list[str]:
        return ["graphiti"]

    def health(self) -> dict[str, str]:
        return {"graphiti": "enabled: fake"}

    def project_memory_event(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]:
        event_id = str(event.get("event_id") or "")
        self.projected_events.append(event_id)
        return {"graphiti": f"ok:episode:{len(self.projected_events)}"}


class UnavailableGraphitiAdapters(FakeGraphitiAdapters):
    def health(self) -> dict[str, str]:
        return {"graphiti": "unavailable: endpoint unavailable"}


class FailingGraphitiAdapters(FakeGraphitiAdapters):
    def project_memory_event(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, str]:
        raise RuntimeError("projection exploded")


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

    def test_terminal_capture_uses_mem0_managed_inference(self) -> None:
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
                self.assertTrue(adapters.captured_chunks[0]["infer"])
                self.assertIn("durable coding memories", adapters.captured_chunks[0]["prompt"])
                self.assertEqual(adapters.captured_chunks[0]["type"], "workflow")
            finally:
                store.close()

    def test_duplicate_mem0_result_refreshes_mirror_without_duplicate_memory_event(self) -> None:
        class StableMem0Adapters(FakeMem0Adapters):
            def capture_source(self, source: dict[str, Any], chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
                self.captured_chunks.extend(chunks)
                memory = {
                    "id": "mem0:stable",
                    "project_id": "/repo",
                    "type": "workflow",
                    "status": "active",
                    "title": "Run tests",
                    "body": "Run tests after code changes.",
                    "normalized_claim": "run tests after code changes",
                    "confidence": 0.82,
                    "importance": 0.6,
                    "scopes": [{"id": "project:/repo", "kind": "project", "key": "/repo", "title": "/repo", "metadata": {}}],
                    "source_refs": [{"kind": "manual", "uri": "manual://stable"}],
                    "metadata": {"adapter": "mem0", "provider": "mem0", "provider_id": "mem0:stable"},
                    "created_at": 1,
                    "updated_at": 1,
                    "extracted_by": "mem0",
                }
                self.memories["mem0:stable"] = memory
                return [memory]

        with tempfile.TemporaryDirectory() as directory:
            adapters = StableMem0Adapters()
            store = MemoryStore(Path(directory), adapters=adapters)
            try:
                for index in range(2):
                    store.ingest_source(
                        {
                            "id": f"src:manual:{index}",
                            "project_id": "/repo",
                            "title": f"Manual {index}",
                            "kind": "manual",
                            "uri": f"manual://{index}",
                            "body": "Remember to run tests after code changes.",
                            "content_hash": f"hash:{index}",
                            "metadata": {},
                        }
                    )
                    store.drain_projection_jobs(limit=5)

                rows = store.conn.execute(
                    "SELECT event_type FROM memory_events WHERE memory_id = 'mem0:stable' ORDER BY seq"
                ).fetchall()
                self.assertEqual([row["event_type"] for row in rows], ["memory.observed"])
            finally:
                store.close()

    def test_startup_does_not_auto_enqueue_legacy_memories_for_mem0(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = MemoryStore(root, adapters=FakeMem0Adapters())
            try:
                store.append_event(
                    {
                        "project_id": "/repo",
                        "event_type": "memory.observed",
                        "after": {
                            "title": "Legacy",
                            "body": "Legacy sidecar memory.",
                            "type": "fact",
                            "status": "active",
                            "extracted_by": "sidecar",
                        },
                    }
                )
            finally:
                store.close()

            reopened = MemoryStore(root, adapters=FakeMem0Adapters())
            try:
                self.assertEqual(reopened.health()["migration_pending"], 0)
            finally:
                reopened.close()

    def test_reindex_reports_blocker_when_graphiti_projector_missing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = MemoryStore(Path(directory), adapters=FakeMem0Adapters())
            try:
                result = store.reindex(project_id="/repo")

                self.assertTrue(result["skipped"])
                self.assertEqual(result["enqueued"], 0)
                self.assertIn("graphiti", result["blockers"])
                self.assertIn("unavailable", result["message"])
            finally:
                store.close()

    def test_reindex_with_drain_projects_enqueued_canonical_memories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            adapters = FakeGraphitiAdapters()
            store = MemoryStore(Path(directory), adapters=adapters)
            try:
                self._append_canonical_memory_event(store)

                result = store.reindex(project_id="/repo", drain=True, drain_limit=5)

                self.assertFalse(result["skipped"])
                self.assertEqual(result["enqueued"], 1)
                self.assertIsNotNone(result["drained"])
                self.assertEqual(result["drained"]["delivered"], 1)
                self.assertEqual(store.health()["projection_pending"], 0)
                self.assertEqual(len(adapters.projected_events), 1)
            finally:
                store.close()

    def test_projection_preflight_blocker_does_not_fail_pending_jobs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            adapters = UnavailableGraphitiAdapters()
            store = MemoryStore(Path(directory), adapters=adapters)
            try:
                self._append_canonical_memory_event(store)
                self.assertEqual(store.health()["projection_pending"], 1)

                result = store.drain_projection_jobs(limit=5)

                self.assertTrue(result["skipped"])
                self.assertEqual(result["projection"]["failed"], 0)
                self.assertEqual(store.health()["projection_pending"], 1)
                self.assertEqual(store.health()["projection_failed"], 0)
                self.assertEqual(adapters.projected_events, [])
            finally:
                store.close()

    def test_projection_call_failure_marks_job_failed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = MemoryStore(Path(directory), adapters=FailingGraphitiAdapters())
            try:
                self._append_canonical_memory_event(store)

                result = store.drain_projection_jobs(limit=5)

                self.assertFalse(result["skipped"])
                self.assertEqual(result["projection"]["failed"], 1)
                self.assertEqual(store.health()["projection_pending"], 0)
                self.assertEqual(store.health()["projection_failed"], 1)
            finally:
                store.close()

    def _append_canonical_memory_event(self, store: MemoryStore) -> dict[str, Any]:
        return store.append_event(
            {
                "project_id": "/repo",
                "event_type": "memory.observed",
                "after": {
                    "id": "memory:graphiti",
                    "project_id": "/repo",
                    "type": "fact",
                    "status": "active",
                    "title": "Use Graphiti projection",
                    "body": "Use Graphiti to project canonical memories into entity facts.",
                    "normalized_claim": "graphiti projects canonical memories",
                    "source_refs": [{"kind": "manual", "uri": "manual://graphiti"}],
                    "metadata": {"provider": "mem0"},
                    "extracted_by": "mem0",
                },
            }
        )


if __name__ == "__main__":
    unittest.main()
