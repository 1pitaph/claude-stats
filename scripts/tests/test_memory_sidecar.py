import importlib.util
import json
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
            self.assertEqual(store.health()["api_version"], 11)

            hits = store.search("run-debug", project_id="claude-stats")
            self.assertEqual(len(hits["results"]), 1)
            self.assertEqual(hits["results"][0]["memory"]["type"], "command")

            graph = store.graph("claude-stats")
            node_kinds = {node["kind"] for node in graph["nodes"]}
            edge_kinds = {edge["kind"] for edge in graph["edges"]}
            self.assertIn("memory", node_kinds)
            self.assertIn("event", node_kinds)
            self.assertIn("SCOPED_TO", edge_kinds)

    def test_projects_modules_and_health_count_active_only(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            store.append_event(
                {
                    "project_id": "p",
                    "event_type": "memory.observed",
                    "after": {
                        "title": "Active",
                        "body": "Active memory.",
                        "type": "fact",
                        "scope": {"kind": "module", "key": "p:Core", "title": "Core"},
                    },
                    "source_refs": [{"kind": "manual", "uri": "active"}],
                }
            )
            store.propose_memory(
                {
                    "project_id": "p",
                    "title": "Proposal",
                    "body": "Proposed memory.",
                    "scope": {"kind": "module", "key": "p:Core", "title": "Core"},
                }
            )

            self.assertEqual(store.health()["memory_count"], 1)
            self.assertEqual(store.health()["total_memory_count"], 2)
            project = store.projects()[0]
            self.assertEqual(project["memory_count"], 1)
            self.assertEqual(project["total_memory_count"], 2)
            self.assertEqual(project["proposal_count"], 1)
            module = store.modules(project_id="p")["modules"][0]
            self.assertEqual(module["memory_count"], 1)
            self.assertEqual(module["total_memory_count"], 2)

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

    def test_config_sources_are_source_only_even_when_infer_is_requested(self):
        from memoryd.store import MemoryStore

        class FakeAdapters:
            def __init__(self):
                self.inferred = []

            def names(self):
                return ["fake"]

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {"fake": "ok:fake-id"}

            def infer_memories(self, source):
                self.inferred.append(source)
                return [
                    {
                        "project_id": source["project_id"],
                        "title": "Should not appear",
                        "body": "Config files must not become inferred memories.",
                        "type": "fact",
                        "status": "active",
                    }
                ]

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            adapters = FakeAdapters()
            store = MemoryStore(Path(tmp), adapters=adapters)
            for kind in ["ai_config", "provider_config", "plugin_config", "plan"]:
                result = store.ingest_source(
                    {
                        "id": f"src:{kind}",
                        "project_id": "p",
                        "title": f"{kind}.txt",
                        "body": f"{kind} body",
                        "kind": kind,
                        "path": f"/repo/{kind}.txt",
                        "infer": True,
                    }
                )
                self.assertEqual(result["created"], [])
                self.assertEqual(result["proposed"], [])

            self.assertEqual(adapters.inferred, [])
            self.assertEqual(store.memories(project_id="p", status="active")["memories"], [])

    def test_transcript_ingest_is_source_only_and_inferred_memories_stay_proposed(self):
        from memoryd.store import MemoryStore

        class FakeAdapters:
            def __init__(self):
                self.sources = []

            def names(self):
                return ["fake"]

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {"fake": "ok:fake-id"}

            def infer_memories(self, source):
                self.sources.append(source)
                return [
                    {
                        "project_id": source["project_id"],
                        "title": "Run debug after code changes",
                        "body": "After code changes, run bash scripts/run-debug.sh.",
                        "type": "workflow",
                        "status": "proposed",
                        "source_refs": [{"kind": source["kind"], "uri": source["id"]}],
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
                    "title": "Codex session",
                    "body": '{"timestamp":"2026-05-29T00:00:00Z","type":"session_meta","payload":{"base_instructions":{"text":"raw"}}}\n{"type":"event_msg","payload":{"type":"user_message","message":"run tests"}}',
                    "kind": "codex_transcript",
                    "path": "/sessions/rollout.jsonl",
                    "infer": True,
                }
            )

            self.assertEqual(result["created"], [])
            self.assertEqual(len(result["proposed"]), 1)
            self.assertIn("Session: Codex session", result["source"]["body"])
            self.assertIn("User: run tests", result["source"]["body"])
            self.assertNotIn("session_meta", result["source"]["body"])
            self.assertNotIn("base_instructions", result["source"]["body"])
            self.assertNotIn("raw", result["source"]["body"])
            self.assertEqual(len(adapters.sources), 1)
            self.assertNotIn("session_meta", adapters.sources[0]["body"])
            source_row = store.conn.execute("SELECT excerpt FROM sources WHERE kind = 'codex_transcript'").fetchone()
            episode_row = store.conn.execute("SELECT body_excerpt FROM episodes WHERE kind = 'codex_transcript'").fetchone()
            self.assertIsNotNone(source_row)
            self.assertIsNotNone(episode_row)
            self.assertNotIn("session_meta", source_row["excerpt"])
            self.assertNotIn("session_meta", episode_row["body_excerpt"])
            self.assertEqual(store.memories(project_id="claude-stats", status="active")["memories"], [])
            proposals = store.proposals(project_id="claude-stats")["memories"]
            self.assertEqual(len(proposals), 1)
            self.assertEqual(proposals[0]["status"], "proposed")

    def test_inferred_active_candidates_are_forced_to_proposed(self):
        from memoryd.store import MemoryStore

        class ActiveCandidateAdapters:
            def names(self):
                return ["fake"]

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {"fake": "ok:fake-id"}

            def infer_memories(self, source):
                return [
                    {
                        "project_id": source["project_id"],
                        "title": "Do not auto-activate",
                        "body": "Adapter candidates must go through review.",
                        "type": "fact",
                        "status": "active",
                    }
                ]

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=ActiveCandidateAdapters())
            result = store.ingest_source(
                {
                    "project_id": "p",
                    "title": "Session",
                    "body": "User: remember review gate",
                    "kind": "manual",
                    "infer": True,
                }
            )

            self.assertEqual(result["created"][0]["status"], "active")
            self.assertEqual(result["proposed"][0]["status"], "proposed")

    def test_reinfer_sources_bypasses_content_hash_skip_and_excludes_configs(self):
        from memoryd.store import MemoryStore

        class FakeAdapters:
            def __init__(self):
                self.sources = []

            def names(self):
                return ["fake"]

            def health(self):
                return {"fake": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {"fake": "ok:fake-id"}

            def infer_memories(self, source):
                self.sources.append(source)
                return [
                    {
                        "project_id": source["project_id"],
                        "title": "Reinferred",
                        "body": "Force reinfer should propose this memory.",
                        "type": "fact",
                        "status": "active",
                        "source_refs": [{"kind": source["kind"], "uri": source["id"]}],
                    }
                ]

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            adapters = FakeAdapters()
            store = MemoryStore(Path(tmp), adapters=adapters)
            payload = {
                "id": "src:transcript",
                "project_id": "p",
                "title": "Transcript",
                "body": "User: keep force reinfer working",
                "kind": "manual",
                "path": "/missing/transcript.txt",
                "content_hash": "same-hash",
                "infer": False,
            }
            store.ingest_source(payload)
            skipped = store.ingest_source(payload | {"infer": True})
            self.assertEqual(skipped["status"], "skipped")
            self.assertEqual(adapters.sources, [])

            reinferred = store.reinfer_sources({"source_id": "src:transcript"})
            self.assertEqual(reinferred["scanned"], 1)
            self.assertEqual(reinferred["attempted"], 1)
            self.assertEqual(reinferred["proposed"], 1)
            self.assertEqual(len(adapters.sources), 1)
            proposal = store.proposals(project_id="p")["memories"][0]
            self.assertEqual(proposal["status"], "proposed")

            store.ingest_source(
                {
                    "id": "src:config",
                    "project_id": "p",
                    "title": "config.toml",
                    "body": 'model = "gpt-5"',
                    "kind": "provider_config",
                    "path": "/repo/config.toml",
                    "infer": False,
                }
            )
            excluded = store.reinfer_sources({"source_id": "src:config"})
            self.assertEqual(excluded["scanned"], 0)
            self.assertEqual(excluded["attempted"], 0)

    def test_inference_errors_are_returned_and_exposed_in_health(self):
        from memoryd.adapters import CompositeAdapters
        from memoryd.store import MemoryStore

        class ExplodingAdapter:
            name = "exploding"

            def __init__(self):
                self.last_error = ""

            def names(self):
                return [self.name]

            def health(self):
                return {self.name: "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {self.name: "ok:fake-id"}

            def infer_memories(self, source):
                raise RuntimeError("llm inference failed with compact detail")

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        class EndpointErrorAdapter(ExplodingAdapter):
            name = "endpoint"

            def __init__(self):
                self.last_error = "local endpoint unavailable"

            def infer_memories(self, source):
                return []

        with tempfile.TemporaryDirectory() as tmp:
            adapters = CompositeAdapters([ExplodingAdapter(), EndpointErrorAdapter()])
            store = MemoryStore(Path(tmp), adapters=adapters)
            result = store.ingest_source(
                {
                    "id": "src:error",
                    "project_id": "p",
                    "title": "Transcript",
                    "body": "User: extract something",
                    "kind": "manual",
                    "infer": True,
                }
            )

            self.assertEqual(result["proposed"], [])
            self.assertEqual({error["adapter"] for error in result["inference_errors"]}, {"exploding", "endpoint"})
            self.assertIn("llm inference failed", result["inference_errors"][0]["error"])
            health_errors = json.loads(store.health()["adapters"]["last_inference_errors"])
            self.assertEqual({error["adapter"] for error in health_errors}, {"exploding", "endpoint"})

            reinferred = store.reinfer_sources({"source_id": "src:error"})
            self.assertEqual(reinferred["attempted"], 1)
            self.assertEqual({error["adapter"] for error in reinferred["errors"]}, {"exploding", "endpoint"})
            self.assertTrue(all(error["source_id"] == "src:error" for error in reinferred["errors"]))

    def test_legacy_raw_transcript_source_excerpts_are_redacted(self):
        from memoryd.store import MemoryStore, RAW_TRANSCRIPT_REDACTION

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            raw = '{"timestamp":"2026-05-29T00:00:00Z","type":"session_meta","payload":{"base_instructions":{"text":"secret"}}}'
            store.conn.execute(
                """
                INSERT INTO sources (
                    id, project_id, kind, title, uri, path, commit_sha, content_hash,
                    excerpt, metadata_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                ("src:legacy", "claude-stats", "codex_transcript", "Legacy", "legacy.jsonl", None, None, "hash", raw, "{}", 0),
            )
            store.conn.execute(
                """
                INSERT INTO episodes (
                    id, source_id, project_id, kind, title, body_excerpt,
                    reference_time, metadata_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                ("episode:src:legacy", "src:legacy", "claude-stats", "codex_transcript", "Legacy", raw, 0, "{}", 0, 0),
            )
            store.conn.execute(
                """
                INSERT INTO memories (
                    id, project_id, type, status, title, body, normalized_claim,
                    confidence, importance, source_refs_json, metadata_json, valid_at,
                    invalid_at, review_reason, extracted_by, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "mem:legacy",
                    "claude-stats",
                    "workflow",
                    "active",
                    "Legacy transcript",
                    raw,
                    "raw",
                    1,
                    1,
                    '[{"kind":"codex_transcript","uri":"legacy.jsonl"}]',
                    "{}",
                    None,
                    None,
                    None,
                    None,
                    0,
                    0,
                ),
            )
            store.conn.commit()
            store.close()

            migrated = MemoryStore(Path(tmp))
            source = migrated.conn.execute("SELECT excerpt FROM sources WHERE id = 'src:legacy'").fetchone()
            episode = migrated.conn.execute("SELECT body_excerpt FROM episodes WHERE id = 'episode:src:legacy'").fetchone()
            memory = migrated.conn.execute("SELECT status, body FROM memories WHERE id = 'mem:legacy'").fetchone()
            self.assertEqual(source["excerpt"], RAW_TRANSCRIPT_REDACTION)
            self.assertEqual(episode["body_excerpt"], RAW_TRANSCRIPT_REDACTION)
            self.assertEqual(memory["status"], "retracted")
            self.assertEqual(memory["body"], RAW_TRANSCRIPT_REDACTION)

    def test_permission_config_ingest_is_source_only_and_summarized(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            body = json.dumps(
                {
                    "permissions": {
                        "allow": [
                            "Bash(cat)",
                            "Bash(xcodebuild -project app.xcodeproj build)",
                            "Read(//Users/example/Library/Developer/Xcode/**)",
                        ]
                    }
                }
            )
            result = store.ingest_source(
                {
                    "project_id": "reelo",
                    "title": "Project settings.local.json",
                    "body": body,
                    "kind": "ai_config",
                    "path": "/repo/reelo/.claude/settings.local.json",
                    "infer": False,
                }
            )

            self.assertEqual(result["created"], [])
            self.assertIn("Sensitive local AI configuration", result["source"]["body"])
            self.assertIn("Allowed permission entries: 3", result["source"]["body"])
            self.assertIn("Permission families: Bash, Read", result["source"]["body"])
            self.assertNotIn('"permissions"', result["source"]["body"])
            self.assertNotIn("Bash(", result["source"]["body"])
            self.assertEqual(store.memories(project_id="reelo", status="active")["memories"], [])
            source_row = store.conn.execute("SELECT excerpt FROM sources WHERE kind = 'ai_config'").fetchone()
            episode_row = store.conn.execute("SELECT body_excerpt FROM episodes WHERE kind = 'ai_config'").fetchone()
            self.assertIsNotNone(source_row)
            self.assertIsNotNone(episode_row)
            self.assertNotIn('"permissions"', source_row["excerpt"])
            self.assertNotIn("Bash(", source_row["excerpt"])
            self.assertNotIn('"permissions"', episode_row["body_excerpt"])
            self.assertNotIn("Bash(", episode_row["body_excerpt"])

    def test_global_ai_config_ingest_is_source_only_and_redacts_secrets(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            body = json.dumps(
                {
                    "activeProvider": "claude",
                    "enabledPlugins": {
                        "figma@claude-plugins-official": True,
                        "disabled@example": False,
                    },
                    "env": {
                        "ANTHROPIC_AUTH_TOKEN": "sk-secret-token",
                        "ANTHROPIC_BASE_URL": "https://api.example.invalid/",
                    },
                }
            )
            result = store.ingest_source(
                {
                    "project_id": "global",
                    "title": "settings.json",
                    "body": body,
                    "kind": "ai_config",
                    "path": "/Users/example/.claude/settings.json",
                    "infer": False,
                }
            )

            self.assertEqual(result["created"], [])
            self.assertIn("Sensitive local AI configuration", result["source"]["body"])
            self.assertIn("Environment entries: 2", result["source"]["body"])
            self.assertIn("Environment families: ANTHROPIC", result["source"]["body"])
            self.assertIn("Enabled plugin entries: 1", result["source"]["body"])
            self.assertNotIn("sk-secret-token", result["source"]["body"])
            self.assertNotIn("ANTHROPIC_AUTH_TOKEN", result["source"]["body"])
            self.assertNotIn("api.example.invalid", result["source"]["body"])
            self.assertEqual(store.memories(project_id="global", status="active")["memories"], [])

    def test_legacy_permission_config_memories_are_retracted(self):
        from memoryd.store import MemoryStore, SENSITIVE_CONFIG_REDACTION

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            raw = json.dumps(
                {
                    "permissions": {
                        "allow": [
                            "Bash(cat)",
                            "Bash(bash /tmp/check_imports.sh)",
                        ]
                    }
                }
            )
            store.conn.execute(
                """
                INSERT INTO sources (
                    id, project_id, kind, title, uri, path, commit_sha, content_hash,
                    excerpt, metadata_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "src:permissions",
                    "reelo",
                    "ai_config",
                    "Project settings.local.json",
                    "/repo/reelo/.claude/settings.local.json",
                    "/repo/reelo/.claude/settings.local.json",
                    None,
                    "hash",
                    raw,
                    "{}",
                    0,
                ),
            )
            store.conn.execute(
                """
                INSERT INTO episodes (
                    id, source_id, project_id, kind, title, body_excerpt,
                    reference_time, metadata_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "episode:src:permissions",
                    "src:permissions",
                    "reelo",
                    "ai_config",
                    "Project settings.local.json",
                    raw,
                    0,
                    "{}",
                    0,
                    0,
                ),
            )
            store.conn.execute(
                """
                INSERT INTO memories (
                    id, project_id, type, status, title, body, normalized_claim,
                    confidence, importance, source_refs_json, metadata_json, valid_at,
                    invalid_at, review_reason, extracted_by, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "mem:permissions",
                    "reelo",
                    "convention",
                    "active",
                    "Project settings.local.json",
                    raw,
                    "raw permissions",
                    1,
                    1,
                    '[{"kind":"ai_config","uri":"/repo/reelo/.claude/settings.local.json","path":"/repo/reelo/.claude/settings.local.json"}]',
                    "{}",
                    None,
                    None,
                    None,
                    None,
                    0,
                    0,
                ),
            )
            store.conn.commit()
            store.close()

            migrated = MemoryStore(Path(tmp))
            source = migrated.conn.execute("SELECT excerpt FROM sources WHERE id = 'src:permissions'").fetchone()
            episode = migrated.conn.execute("SELECT body_excerpt FROM episodes WHERE id = 'episode:src:permissions'").fetchone()
            memory = migrated.conn.execute("SELECT status, body FROM memories WHERE id = 'mem:permissions'").fetchone()
            self.assertIn("Sensitive local AI configuration", source["excerpt"])
            self.assertIn("Sensitive local AI configuration", episode["body_excerpt"])
            self.assertNotIn('"permissions"', source["excerpt"])
            self.assertNotIn("Bash(", source["excerpt"])
            self.assertNotIn('"permissions"', episode["body_excerpt"])
            self.assertNotIn("Bash(", episode["body_excerpt"])
            self.assertEqual(memory["status"], "retracted")
            self.assertEqual(memory["body"], SENSITIVE_CONFIG_REDACTION)

    def test_legacy_source_only_config_memories_are_retracted_and_jobs_done(self):
        from memoryd.store import MemoryStore, SOURCE_ONLY_CONFIG_REDACTION

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            kinds = ["ai_config", "provider_config", "plugin_config", "plan"]
            for index, kind in enumerate(kinds):
                memory_id = f"mem:{kind}"
                refs = json.dumps(
                    [{"kind": kind, "uri": f"/repo/{kind}.txt", "path": f"/repo/{kind}.txt"}],
                    indent=2 if kind == "ai_config" else None,
                )
                store.conn.execute(
                    """
                    INSERT INTO memories (
                        id, project_id, type, status, title, body, normalized_claim,
                        confidence, importance, source_refs_json, metadata_json, valid_at,
                        invalid_at, review_reason, extracted_by, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        memory_id,
                        "p",
                        "convention",
                        "active",
                        f"{kind}.txt",
                        f"{kind} raw body",
                        f"{kind} raw",
                        1,
                        1,
                        refs,
                        "{}",
                        None,
                        None,
                        None,
                        None,
                        0,
                        0,
                    ),
                )
                store.conn.execute(
                    """
                    INSERT INTO projection_jobs (
                        id, adapter, memory_id, event_id, status, attempt_count,
                        last_error, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        f"job:{kind}",
                        "fake",
                        memory_id,
                        f"event:{kind}",
                        "failed" if index % 2 else "pending",
                        1,
                        "old error",
                        0,
                        0,
                    ),
                )
            store.conn.execute(
                """
                INSERT INTO memories (
                    id, project_id, type, status, title, body, normalized_claim,
                    confidence, importance, source_refs_json, metadata_json, valid_at,
                    invalid_at, review_reason, extracted_by, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "mem:agents",
                    "p",
                    "convention",
                    "active",
                    "AGENTS.md",
                    "Still active.",
                    "agents",
                    1,
                    1,
                    '[{"kind":"AGENTS.md","path":"AGENTS.md"}]',
                    "{}",
                    None,
                    None,
                    None,
                    None,
                    0,
                    0,
                ),
            )
            store.conn.commit()
            store.close()

            migrated = MemoryStore(Path(tmp))
            rows = migrated.conn.execute(
                "SELECT id, status, body, invalid_at, review_reason, extracted_by FROM memories ORDER BY id"
            ).fetchall()
            by_id = {row["id"]: row for row in rows}
            for kind in kinds:
                row = by_id[f"mem:{kind}"]
                self.assertEqual(row["status"], "retracted")
                self.assertEqual(row["body"], SOURCE_ONLY_CONFIG_REDACTION)
                self.assertIsNotNone(row["invalid_at"])
                self.assertEqual(row["review_reason"], "source_only_config_ingest")
                self.assertEqual(row["extracted_by"], "source_only_config_ingest")
            self.assertEqual(by_id["mem:agents"]["status"], "active")
            jobs = migrated.conn.execute("SELECT status, last_error FROM projection_jobs ORDER BY id").fetchall()
            self.assertTrue(jobs)
            self.assertTrue(all(job["status"] == "done" for job in jobs))
            self.assertTrue(all(job["last_error"] is None for job in jobs))

    def test_legacy_global_ai_config_memories_are_retracted_and_redacted(self):
        from memoryd.store import MemoryStore, SENSITIVE_CONFIG_REDACTION

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            raw = json.dumps(
                {
                    "activeProvider": "claude",
                    "env": {"ANTHROPIC_AUTH_TOKEN": "sk-legacy-secret"},
                    "enabledPlugins": {"figma@claude-plugins-official": True},
                }
            )
            store.conn.execute(
                """
                INSERT INTO sources (
                    id, project_id, kind, title, uri, path, commit_sha, content_hash,
                    excerpt, metadata_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "src:global-settings",
                    "global",
                    "ai_config",
                    "settings.json",
                    "/Users/example/.claude/settings.json",
                    "/Users/example/.claude/settings.json",
                    None,
                    "hash",
                    raw,
                    "{}",
                    0,
                ),
            )
            store.conn.execute(
                """
                INSERT INTO episodes (
                    id, source_id, project_id, kind, title, body_excerpt,
                    reference_time, metadata_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "episode:src:global-settings",
                    "src:global-settings",
                    "global",
                    "ai_config",
                    "settings.json",
                    raw,
                    0,
                    "{}",
                    0,
                    0,
                ),
            )
            store.conn.execute(
                """
                INSERT INTO memories (
                    id, project_id, type, status, title, body, normalized_claim,
                    confidence, importance, source_refs_json, metadata_json, valid_at,
                    invalid_at, review_reason, extracted_by, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "mem:global-settings",
                    "global",
                    "convention",
                    "active",
                    "settings.json",
                    raw,
                    "raw global settings",
                    1,
                    1,
                    '[{"kind":"ai_config","uri":"/Users/example/.claude/settings.json","path":"/Users/example/.claude/settings.json"}]',
                    "{}",
                    None,
                    None,
                    None,
                    None,
                    0,
                    0,
                ),
            )
            store.conn.commit()
            store.close()

            migrated = MemoryStore(Path(tmp))
            source = migrated.conn.execute("SELECT excerpt FROM sources WHERE id = 'src:global-settings'").fetchone()
            episode = migrated.conn.execute("SELECT body_excerpt FROM episodes WHERE id = 'episode:src:global-settings'").fetchone()
            memory = migrated.conn.execute("SELECT status, body FROM memories WHERE id = 'mem:global-settings'").fetchone()
            self.assertIn("Sensitive local AI configuration", source["excerpt"])
            self.assertIn("Environment entries: 1", source["excerpt"])
            self.assertNotIn("sk-legacy-secret", source["excerpt"])
            self.assertNotIn("ANTHROPIC_AUTH_TOKEN", source["excerpt"])
            self.assertNotIn("sk-legacy-secret", episode["body_excerpt"])
            self.assertEqual(memory["status"], "retracted")
            self.assertEqual(memory["body"], SENSITIVE_CONFIG_REDACTION)

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

    def test_graphiti_adapter_only_results_are_graph_facts(self):
        from memoryd.store import MemoryStore

        class FakeAdapters:
            def names(self):
                return []

            def health(self):
                return {"graphiti": "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {}

            def infer_memories(self, source):
                return []

            def search(self, query, *, project_id, limit):
                return [
                    {
                        "rank": 1,
                        "score": 0.74,
                        "memory": {
                            "id": "graphiti:edge-1",
                            "project_id": project_id or "p",
                            "type": "fact",
                            "status": "active",
                            "title": "Graph fact",
                            "body": "Module A depends on Module B.",
                            "normalized_claim": "edge-1",
                            "confidence": 0.74,
                            "importance": 0.5,
                            "source_refs": [{"kind": "graphiti", "uri": "edge-1"}],
                            "metadata": {
                                "adapter": "graphiti",
                                "edge_uuid": "edge-1",
                                "relation": "DEPENDS_ON",
                                "source": "A",
                                "target": "B",
                                "valid_at": "2026-05-01T00:00:00+00:00",
                            },
                            "scopes": [],
                            "created_at": 0,
                            "updated_at": 0,
                        },
                        "match_kind": "graphiti",
                    }
                ]

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=FakeAdapters())
            canonical = store.search("depends", project_id="p")
            unified = store.unified_search({"query": "depends", "filters": {"project_id": "p"}})

            self.assertEqual(canonical["results"], [])
            self.assertEqual(unified["memory_results"], [])
            self.assertEqual(len(unified["graph_results"]), 1)
            self.assertEqual(unified["graph_results"][0]["relation"], "DEPENDS_ON")

            promoted = store.promote_graph_fact(unified["graph_results"][0])
            self.assertEqual(promoted["memory"]["status"], "proposed")
            self.assertEqual(promoted["memory"]["review_reason"], "graph_fact_promotion")

    def test_context_pack_and_provenance_episode_persistence(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp))
            result = store.ingest_source(
                {
                    "project_id": "p",
                    "title": "AGENTS.md",
                    "body": "Always run bash scripts/run-debug.sh after changing code.",
                    "kind": "AGENTS.md",
                    "path": "/repo/AGENTS.md",
                    "infer": False,
                }
            )
            memory = result["created"][0]
            pack = store.context_pack("run-debug", project_id="p")
            graph = store.graph("p")

            self.assertEqual(pack["context"]["rules"][0]["id"], memory["id"])
            self.assertEqual(len(pack["sources"]), 1)
            self.assertIn("source_id", memory["source_refs"][0])
            self.assertIn("episode_id", memory["source_refs"][0])
            episode_ids = {node["id"] for node in graph["nodes"] if node["kind"] == "episode"}
            self.assertIn(memory["source_refs"][0]["episode_id"], episode_ids)
            self.assertIn("HAS_PROVENANCE", {edge["kind"] for edge in graph["edges"]})

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
