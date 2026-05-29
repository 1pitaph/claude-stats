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
            self.assertTrue(adapters.indexed)

            modules = store.modules(project_id="claude-stats")["modules"]
            self.assertEqual(modules[0]["title"], "ClaudeStats")

            proposals = store.proposals(project_id="claude-stats")["memories"]
            self.assertEqual(proposals[0]["status"], "proposed")

            reindex = store.reindex(project_id="claude-stats")
            self.assertGreaterEqual(reindex["enqueued"], 1)
            self.assertGreaterEqual(reindex["drained"]["delivered"], 1)


if __name__ == "__main__":
    unittest.main()
