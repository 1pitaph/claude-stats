import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SIDECAR = ROOT / "MemorySidecar"


class MemorySidecarTests(unittest.TestCase):
    def setUp(self):
        import sys

        sys.path.insert(0, str(SIDECAR))
        self.addCleanup(lambda: sys.path.remove(str(SIDECAR)) if str(SIDECAR) in sys.path else None)

    def test_event_hash_chain_search_and_graph(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            first = store.append_event(
                {
                    "project_id": "claude-stats",
                    "event_type": "memory.observed",
                    "actor": {"kind": "tool", "id": "scan"},
                    "after": {
                        "title": "Use run-debug",
                        "body": "After changing code, run bash scripts/run-debug.sh.",
                        "type": "command",
                        "scope": {"kind": "project", "key": "claude-stats"},
                    },
                    "source_refs": [{"kind": "AGENTS.md", "path": "AGENTS.md"}],
                }
            )
            second = store.propose_memory(
                {
                    "project_id": "claude-stats",
                    "title": "Candidate convention",
                    "body": "Prefer small focused memory records.",
                    "type": "convention",
                }
            )

            self.assertIsNone(first["prev_hash"])
            self.assertEqual(second["prev_hash"], first["hash"])
            self.assertEqual(store.health()["api_version"], 4)

            hits = store.search("run-debug", project_id="claude-stats")
            self.assertEqual(len(hits["results"]), 1)
            self.assertEqual(hits["results"][0]["memory"]["type"], "command")

            graph = store.graph("claude-stats")
            node_kinds = {node["kind"] for node in graph["nodes"]}
            edge_kinds = {edge["kind"] for edge in graph["edges"]}
            self.assertIn("memory", node_kinds)
            self.assertIn("event", node_kinds)
            self.assertIn("SCOPED_TO", edge_kinds)

    def test_accept_marks_proposed_memory_active(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            proposed = store.propose_memory(
                {
                    "project_id": "p",
                    "title": "Review me",
                    "body": "Agent inferred memory should be proposed.",
                }
            )
            memory_id = proposed["memory"]["id"]
            store.accept_memory(memory_id)
            active = store.search("review", project_id="p")
            self.assertEqual(active["results"][0]["memory"]["status"], "active")

    def test_source_ingest_modules_and_projection_jobs(self):
        from memoryd.store import MemoryStore

        class FakeAdapters:
            def __init__(self):
                self.indexed = []

            def names(self):
                return ["fake"]

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                self.indexed.append((memory["id"], event["event_id"], adapter_name))
                return {"fake": "ok:fake-id"}

            def infer_memories(self, source):
                return [
                    {
                        "project_id": source["project_id"],
                        "title": "Inferred fact",
                        "body": "mem0-style inferred facts stay proposed.",
                        "type": "fact",
                        "status": "proposed",
                        "source_refs": [{"kind": "fake", "uri": source["id"]}],
                    }
                ]

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            adapters = FakeAdapters()
            store = MemoryStore(Path(tmp), adapters=adapters)
            result = store.ingest_source(
                {
                    "project_id": "claude-stats",
                    "title": "AGENTS.md",
                    "body": "After code changes run tests.",
                    "kind": "AGENTS.md",
                    "path": "/repo/claude-stats/ClaudeStats/MemoryCore/AGENTS.md",
                    "infer": True,
                }
            )

            self.assertEqual(result["status"], "ok")
            self.assertEqual(len(result["created"]), 1)
            self.assertEqual(len(result["proposed"]), 1)
            self.assertFalse(adapters.indexed)

            drained = store.drain_projection_jobs()
            self.assertEqual(drained["delivered"], 1)
            self.assertEqual(len(adapters.indexed), 1)
            self.assertEqual(adapters.indexed[0][0], result["created"][0]["id"])
            self.assertEqual(adapters.indexed[0][2], "fake")

            modules = store.modules(project_id="claude-stats")["modules"]
            self.assertEqual(modules[0]["title"], "ClaudeStats")

            proposals = store.proposals(project_id="claude-stats")["memories"]
            self.assertEqual(proposals[0]["status"], "proposed")
            proposed_id = proposals[0]["id"]
            self.assertNotIn(proposed_id, [item[0] for item in adapters.indexed])

            accepted = store.accept_memory(proposed_id)
            self.assertEqual(accepted["drained"]["delivered"], 1)
            self.assertIn(proposed_id, [item[0] for item in adapters.indexed])

            reindex = store.reindex(project_id="claude-stats")
            self.assertGreaterEqual(reindex["enqueued"], 1)
            self.assertNotIn("drained", reindex)
            self.assertGreaterEqual(reindex["remaining"], 1)
            self.assertEqual(len(adapters.indexed), 2)

            drained_after_reindex = store.drain_projection_jobs()
            self.assertGreaterEqual(drained_after_reindex["delivered"], 1)
            self.assertGreaterEqual(len(adapters.indexed), 3)

    def test_projection_drain_skips_failed_jobs_by_default(self):
        from memoryd.store import MemoryStore

        class FlakyAdapters:
            def __init__(self):
                self.fail = True
                self.indexed = []

            def names(self):
                return ["fake"]

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                if self.fail:
                    return {"fake": "error: offline"}
                self.indexed.append(memory["id"])
                return {"fake": "ok:fake-id"}

            def infer_memories(self, source):
                return []

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            adapters = FlakyAdapters()
            store = MemoryStore(Path(tmp), adapters=adapters)
            first = store.append_event(
                {
                    "project_id": "claude-stats",
                    "event_type": "memory.observed",
                    "after": {"title": "First", "body": "First memory.", "type": "fact"},
                    "source_refs": [{"kind": "manual", "uri": "first"}],
                }
            )
            second = store.append_event(
                {
                    "project_id": "claude-stats",
                    "event_type": "memory.observed",
                    "after": {"title": "Second", "body": "Second memory.", "type": "fact"},
                    "source_refs": [{"kind": "manual", "uri": "second"}],
                }
            )

            failed = store.drain_projection_jobs(limit=1)
            self.assertEqual(failed["failed"], 1)
            adapters.fail = False

            pending_only = store.drain_projection_jobs(limit=10)
            self.assertEqual(pending_only["delivered"], 1)
            self.assertEqual(adapters.indexed, [second["memory"]["id"]])
            self.assertGreaterEqual(pending_only["failed_total"], 1)

            retried = store.drain_projection_jobs(limit=10, include_failed=True)
            self.assertEqual(retried["delivered"], 1)
            self.assertIn(first["memory"]["id"], adapters.indexed)

    def test_projection_drain_skips_when_adapter_endpoint_is_unavailable(self):
        from memoryd.store import MemoryStore

        class UnavailableAdapters:
            def names(self):
                return ["mem0", "graphiti"]

            def health(self):
                return {
                    "mem0": "configured but endpoint unavailable: 127.0.0.1:18765 is unreachable",
                    "graphiti": "configured but endpoint unavailable: 127.0.0.1:18765 is unreachable",
                }

            def index_memory(self, memory, event, *, adapter_name=None):
                raise AssertionError("drain should not call unavailable adapters")

            def infer_memories(self, source):
                return []

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=UnavailableAdapters())
            store.append_event(
                {
                    "project_id": "claude-stats",
                    "event_type": "memory.observed",
                    "after": {"title": "Queued", "body": "Queued memory.", "type": "fact"},
                    "source_refs": [{"kind": "manual", "uri": "queued"}],
                }
            )

            skipped = store.drain_projection_jobs(limit=10)
            self.assertTrue(skipped["skipped"])
            self.assertEqual(skipped["delivered"], 0)
            self.assertEqual(skipped["failed"], 0)
            self.assertEqual(skipped["pending"], 2)
            self.assertEqual(set(skipped["blockers"]), {"mem0", "graphiti"})

    def test_adapter_search_must_resolve_to_canonical_memory(self):
        from memoryd.store import MemoryStore

        class FakeAdapters:
            def names(self):
                return []

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {}

            def infer_memories(self, source):
                return []

            def search(self, query, *, project_id, limit):
                return [
                    {
                        "rank": 1,
                        "score": 0.99,
                        "memory": {
                            "id": "mem:missing",
                            "project_id": project_id or "p",
                            "type": "fact",
                            "status": "active",
                            "title": "Adapter-only memory",
                            "body": "This should not bypass canonical review.",
                            "normalized_claim": "adapter-only",
                            "confidence": 1,
                            "importance": 1,
                            "source_refs": [],
                            "metadata": {"adapter": "fake"},
                            "scopes": [],
                            "created_at": 0,
                            "updated_at": 0,
                        },
                        "match_kind": "fake",
                    }
                ]

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=FakeAdapters())
            hits = store.search("adapter-only", project_id="p")
            self.assertEqual(hits["results"], [])

    def test_adapter_graph_is_merged_into_project_graph(self):
        from memoryd.store import MemoryStore

        class FakeAdapters:
            def names(self):
                return []

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {}

            def infer_memories(self, source):
                return []

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {
                    "nodes": [{"id": "graphiti:entity:one", "kind": "graphiti_entity", "title": "One"}],
                    "edges": [{"source": "project:p", "target": "graphiti:entity:one", "kind": "HAS_GRAPHITI_ENTITY"}],
                }

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=FakeAdapters())
            graph = store.graph("p")
            self.assertIn("graphiti:entity:one", {node["id"] for node in graph["nodes"]})
            self.assertIn("HAS_GRAPHITI_ENTITY", {edge["kind"] for edge in graph["edges"]})


if __name__ == "__main__":
    unittest.main()
