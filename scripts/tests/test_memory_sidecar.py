import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SIDECAR = ROOT / "MemorySidecar"


class FakeMem0Adapters:
    def __init__(self):
        self.captured_sources = []
        self.memories = {}
        self.last_inference_errors = []

    def names(self):
        return ["mem0"]

    def health(self):
        result = {"mem0": "enabled: fake"}
        if self.last_inference_errors:
            result["last_inference_errors"] = json.dumps(self.last_inference_errors)
        return result

    def index_memory(self, memory, event, *, adapter_name=None):
        return {}

    def capture_source(self, source, chunks):
        self.captured_sources.append((source, chunks))
        captured = []
        for chunk in chunks:
            memory_id = f"mem0:{len(self.memories) + 1}"
            body = str(chunk["body"]).split("\n\n", 1)[-1].strip()
            memory = {
                "id": memory_id,
                "project_id": chunk["project_id"],
                "type": chunk["type"],
                "status": chunk.get("status", "active"),
                "title": chunk["title"],
                "body": f"captured:{body}",
                "normalized_claim": memory_id,
                "confidence": 0.82,
                "importance": 0.6,
                "scopes": chunk.get("scopes", []),
                "source_refs": chunk.get("source_refs", []),
                "metadata": {"adapter": "mem0"},
                "created_at": 1,
                "updated_at": 1,
                "extracted_by": "mem0",
            }
            self.memories[memory_id] = memory
            captured.append(memory)
        return captured

    def capture_memory(self, memory):
        memory_id = f"mem0:{len(self.memories) + 1}"
        captured = dict(memory)
        captured["id"] = memory_id
        captured["metadata"] = (captured.get("metadata") or {}) | {"adapter": "mem0", "legacy_memory_id": memory.get("id", "")}
        captured["extracted_by"] = "mem0"
        self.memories[memory_id] = captured
        return captured

    def list_memories(self, *, project_id, status, memory_type, limit):
        return [
            memory
            for memory in self.memories.values()
            if (not project_id or memory["project_id"] == project_id)
            and (not status or memory["status"] == status)
            and (not memory_type or memory["type"] == memory_type)
        ][:limit]

    def get_memory(self, memory_id):
        return self.memories.get(memory_id)

    def update_memory(self, memory_id, updates):
        memory = self.memories.get(memory_id)
        if memory is None:
            return None
        memory.update({key: value for key, value in updates.items() if value is not None})
        return memory

    def infer_memories(self, source):
        return []

    def inference_errors(self):
        return self.last_inference_errors

    def search(self, query, *, project_id, limit):
        results = []
        for memory in self.list_memories(project_id=project_id, status="active", memory_type=None, limit=limit):
            if query.lower() in f"{memory['title']} {memory['body']}".lower():
                results.append({"rank": len(results) + 1, "score": 0.9, "memory": memory, "match_kind": "mem0"})
        return results

    def graph(self, project_id, *, limit=80):
        return {"nodes": [], "edges": []}


class MemorySidecarTests(unittest.TestCase):
    def setUp(self):
        import sys

        sys.path.insert(0, str(SIDECAR))
        self.addCleanup(lambda: sys.path.remove(str(SIDECAR)) if str(SIDECAR) in sys.path else None)

    def test_runtime_config_file_splits_llm_and_embedding_endpoints(self):
        from memoryd.config import load_local_ai_config

        with tempfile.TemporaryDirectory() as tmp:
            runtime = Path(tmp) / "runtime.json"
            runtime.write_text(
                json.dumps(
                    {
                        "llm": {
                            "protocol": "openai_responses",
                            "base_url": "https://api.openai.com/v1",
                            "api_key": "online-key",
                            "model": "gpt-5-mini",
                        },
                        "embedding": {
                            "base_url": "http://127.0.0.1:18765/v1",
                            "api_key": "local-key",
                            "model": "embedding-model",
                            "dimensions": 384,
                        },
                        "mem0_enabled": True,
                        "graphiti_enabled": True,
                        "configuration_hash": "hash",
                    }
                ),
                encoding="utf-8",
            )

            with patch.dict(os.environ, {"CLAUDE_STATS_MEMORY_RUNTIME_CONFIG": str(runtime)}, clear=True):
                config = load_local_ai_config(Path(tmp))

            self.assertTrue(config.enabled)
            self.assertEqual(config.llm.protocol, "openai_responses")
            self.assertEqual(config.llm.token, "online-key")
            self.assertEqual(config.embedding.token, "local-key")
            self.assertEqual(config.embedding_dims, 384)

    def test_legacy_local_ai_env_still_parses_as_openai_chat(self):
        from memoryd.config import load_local_ai_config

        env = {
            "CLAUDE_STATS_LOCAL_AI_BASE_URL": "http://127.0.0.1:18765/v1",
            "CLAUDE_STATS_LOCAL_AI_TOKEN": "local-token",
            "CLAUDE_STATS_LOCAL_LLM_MODEL": "local-llm",
            "CLAUDE_STATS_LOCAL_EMBEDDING_MODEL": "local-embedding",
            "CLAUDE_STATS_LOCAL_EMBEDDING_DIMS": "384",
            "CLAUDE_STATS_MEM0_ENABLED": "1",
            "CLAUDE_STATS_GRAPHITI_ENABLED": "1",
        }
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, env, clear=True):
            config = load_local_ai_config(Path(tmp))

        self.assertTrue(config.enabled)
        self.assertEqual(config.source, "legacy_env")
        self.assertEqual(config.llm.protocol, "openai_chat_completions")
        self.assertEqual(config.llm.token, config.embedding.token)

    def test_adapter_config_builders_select_requested_llm_protocol(self):
        from memoryd.adapters import _mem0_embedder_config, _mem0_llm_config
        from memoryd.config import EmbeddingEndpointConfig, LLMEndpointConfig, MemoryModelConfig

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = MemoryModelConfig(
                llm=LLMEndpointConfig("anthropic_messages", "https://api.anthropic.com", "anthropic-key", "claude-haiku-4-5-latest"),
                embedding=EmbeddingEndpointConfig("http://127.0.0.1:18765/v1", "local-key", "embedding-model", 384),
                mem0_enabled=True,
                graphiti_enabled=True,
                qdrant_path=root / "qdrant",
                kuzu_path=root / "graphiti.kuzu",
                adapter_timeout_seconds=20,
            )

            llm_provider, llm_config = _mem0_llm_config(config)
            embedder_config = _mem0_embedder_config(config)

        self.assertEqual(llm_provider, "claude_stats_anthropic_messages")
        self.assertEqual(llm_config["anthropic_base_url"], "https://api.anthropic.com")
        self.assertEqual(embedder_config["api_key"], "local-key")
        self.assertEqual(embedder_config["openai_base_url"], "http://127.0.0.1:18765/v1")

    def test_direct_extraction_payload_parser_accepts_json_object(self):
        from memoryd.adapters import _parse_extracted_memories

        memories = _parse_extracted_memories(
            '{"memories":[{"memory":"Run bash scripts/run-tests.sh after code changes.","type":"workflow","confidence":0.9}]}'
        )

        self.assertEqual(len(memories), 1)
        self.assertEqual(memories[0]["memory"], "Run bash scripts/run-tests.sh after code changes.")
        self.assertEqual(memories[0]["type"], "workflow")

    def test_direct_extraction_payload_parser_rejects_raw_source(self):
        from memoryd.adapters import _parse_extracted_memories

        memories = _parse_extracted_memories(
            '{"memories":[{"memory":"Project: /tmp/app\\nSource kind: CLAUDE.md\\nSource path: CLAUDE.md\\n\\n# Build"}]}'
        )

        self.assertEqual(memories, [])

    def test_openai_responses_parser_extracts_text_and_function_calls(self):
        from memoryd.llm_providers import _parse_responses_output

        response = {
            "output_text": "summary",
            "output": [
                {"type": "message", "content": [{"type": "output_text", "text": " body"}]},
                {"type": "function_call", "name": "save_memory", "arguments": '{"title":"Run tests"}'},
            ],
        }

        parsed = _parse_responses_output(response, tools=[{"type": "function"}])

        self.assertEqual(parsed["content"], "summary body")
        self.assertEqual(parsed["tool_calls"][0]["name"], "save_memory")
        self.assertEqual(parsed["tool_calls"][0]["arguments"], {"title": "Run tests"})

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
            self.assertEqual(store.health()["api_version"], 15)

            hits = store.search("run-debug", project_id="claude-stats")
            self.assertEqual(hits["results"], [])

            graph = store.graph("claude-stats")
            node_kinds = {node["kind"] for node in graph["nodes"]}
            edge_kinds = {edge["kind"] for edge in graph["edges"]}
            self.assertIn("event", node_kinds)

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
                        "extracted_by": "mem0",
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
                    "extracted_by": "mem0",
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
                    "extracted_by": "mem0",
                }
            )
            memory_id = proposed["memory"]["id"]
            store.accept_memory(memory_id)
            active = store.search("review", project_id="p")
            self.assertEqual(active["results"][0]["memory"]["status"], "active")

    def test_source_ingest_modules_and_projection_jobs(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            adapters = FakeMem0Adapters()
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

            self.assertEqual(result["status"], "queued")
            self.assertEqual(len(result["created"]), 0)
            self.assertEqual(result["proposed"], [])
            drained = store.drain_projection_jobs(limit=5)
            self.assertEqual(drained["delivered"], 1)
            self.assertEqual(adapters.captured_sources[0][1][0]["infer"], True)

            modules = store.modules(project_id="claude-stats")["modules"]
            self.assertEqual(modules[0]["title"], "ClaudeStats")

            proposals = store.proposals(project_id="claude-stats")["memories"]
            self.assertEqual(proposals, [])

            reindex = store.reindex(project_id="claude-stats")
            self.assertEqual(reindex["enqueued"], 0)
            self.assertEqual(reindex["remaining"], 0)

            drained_after_reindex = store.drain_projection_jobs()
            self.assertEqual(drained_after_reindex["delivered"], 0)

    def test_adapter_source_only_config_memories_are_filtered(self):
        from memoryd.store import MemoryStore

        class ConfigMemoryAdapters(FakeMem0Adapters):
            def __init__(self):
                super().__init__()
                self.memories["mem0:config"] = {
                    "id": "mem0:config",
                    "project_id": "p",
                    "type": "convention",
                    "status": "active",
                    "title": "Project settings.local.json",
                    "body": '{"permissions":{"allow":["Bash(*)"]}}',
                    "normalized_claim": "raw config",
                    "confidence": 1,
                    "importance": 1,
                    "scopes": [{"id": "project:p", "kind": "project", "key": "p", "title": "p", "metadata": {}}],
                    "source_refs": [
                        {
                            "kind": "ai_config",
                            "uri": "/repo/.claude/settings.local.json",
                            "path": "/repo/.claude/settings.local.json",
                        },
                        {"kind": "mem0", "uri": "mem0:config"},
                    ],
                    "metadata": {"adapter": "mem0", "source_kind": "ai_config"},
                    "created_at": 1,
                    "updated_at": 1,
                    "extracted_by": "mem0",
                }

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=ConfigMemoryAdapters())
            memories = store.memories(project_id="p", status="active")["memories"]
            cached = store.conn.execute("SELECT COUNT(*) AS count FROM memories WHERE id = 'mem0:config'").fetchone()

            self.assertEqual(memories, [])
            self.assertEqual(cached["count"], 0)

    def test_raw_instruction_chunk_is_not_cached_as_memory(self):
        from memoryd.store import MemoryStore

        class RawChunkAdapters(FakeMem0Adapters):
            def capture_source(self, source, chunks):
                self.captured_sources.append((source, chunks))
                chunk = chunks[0]
                return [
                    {
                        "id": "mem0:raw",
                        "project_id": chunk["project_id"],
                        "type": chunk["type"],
                        "status": "active",
                        "title": chunk["title"],
                        "body": chunk["body"],
                        "normalized_claim": "raw chunk",
                        "confidence": 0.82,
                        "importance": 0.6,
                        "scopes": chunk["scopes"],
                        "source_refs": chunk["source_refs"],
                        "metadata": {"adapter": "mem0", "infer": "true"},
                        "created_at": 1,
                        "updated_at": 1,
                        "extracted_by": "mem0",
                    }
                ]

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=RawChunkAdapters())
            store.ingest_source(
                {
                    "id": "src:agents",
                    "project_id": "p",
                    "title": "AGENTS.md",
                    "body": "# Build\nRun tests after code changes.",
                    "kind": "AGENTS.md",
                    "path": "/repo/AGENTS.md",
                    "content_hash": "hash",
                }
            )

            drained = store.drain_projection_jobs(limit=5)
            memories = store.memories(project_id="p", status="active")["memories"]
            capture = store.conn.execute("SELECT status, last_error FROM source_captures WHERE source_id = 'src:agents'").fetchone()

            self.assertEqual(drained["delivered"], 0)
            self.assertEqual(drained["failed"], 1)
            self.assertEqual(memories, [])
            self.assertEqual(capture["status"], "failed")
            self.assertIn("non-canonical", capture["last_error"])

    def test_markdown_sections_are_fence_aware_and_keep_heading_path(self):
        from memoryd.store import _markdown_sections

        sections = _markdown_sections(
            "# Root\nIntro\n\n```swift\n# Not a heading\n```\n\n## Build\nRun tests.\n\n## Release\nTag releases.",
            limit=120,
        )

        self.assertEqual([section["title"] for section in sections], ["Root", "Root > Build", "Root > Release"])

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

        with tempfile.TemporaryDirectory() as tmp:
            adapters = FakeMem0Adapters()
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

            self.assertEqual(result["status"], "queued")
            self.assertEqual(len(result["created"]), 0)
            self.assertEqual(result["proposed"], [])
            self.assertIn("Session: Codex session", result["source"]["body"])
            self.assertIn("User: run tests", result["source"]["body"])
            self.assertNotIn("session_meta", result["source"]["body"])
            self.assertNotIn("base_instructions", result["source"]["body"])
            self.assertNotIn("raw", result["source"]["body"])
            drained = store.drain_projection_jobs(limit=5)
            self.assertEqual(drained["delivered"], 1)
            self.assertEqual(len(adapters.captured_sources), 1)
            self.assertNotIn("session_meta", adapters.captured_sources[0][0]["body"])
            source_row = store.conn.execute("SELECT excerpt FROM sources WHERE kind = 'codex_transcript'").fetchone()
            episode_row = store.conn.execute("SELECT body_excerpt FROM episodes WHERE kind = 'codex_transcript'").fetchone()
            self.assertIsNotNone(source_row)
            self.assertIsNotNone(episode_row)
            self.assertNotIn("session_meta", source_row["excerpt"])
            self.assertNotIn("session_meta", episode_row["body_excerpt"])
            self.assertEqual(len(store.memories(project_id="claude-stats", status="active")["memories"]), 1)
            proposals = store.proposals(project_id="claude-stats")["memories"]
            self.assertEqual(proposals, [])

    def test_inferred_active_candidates_are_forced_to_proposed(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp), adapters=FakeMem0Adapters())
            result = store.ingest_source(
                {
                    "project_id": "p",
                    "title": "Session",
                    "body": "User: remember review gate",
                    "kind": "manual",
                    "infer": True,
                }
            )

            drained = store.drain_projection_jobs(limit=5)
            self.assertEqual(drained["delivered"], 1)
            self.assertEqual(store.memories(project_id="p")["memories"][0]["status"], "active")
            self.assertEqual(result["proposed"], [])

    def test_reinfer_sources_bypasses_content_hash_skip_and_excludes_configs(self):
        from memoryd.store import MemoryStore

        with tempfile.TemporaryDirectory() as tmp:
            adapters = FakeMem0Adapters()
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
            store.drain_projection_jobs(limit=5)
            skipped = store.ingest_source(payload | {"infer": True})
            self.assertEqual(skipped["status"], "skipped")
            self.assertEqual(len(adapters.captured_sources), 1)

            reinferred = store.reinfer_sources({"source_id": "src:transcript"})
            self.assertEqual(reinferred["scanned"], 1)
            self.assertEqual(reinferred["attempted"], 1)
            self.assertEqual(reinferred["created"], 0)
            drained = store.drain_projection_jobs(limit=5)
            self.assertEqual(drained["delivered"], 1)
            self.assertEqual(len(adapters.captured_sources), 2)
            self.assertEqual(store.proposals(project_id="p")["memories"], [])

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

        class ExplodingMem0Adapter:
            name = "mem0"

            def __init__(self):
                self.last_error = ""

            def names(self):
                return [self.name]

            def health(self):
                return {self.name: "enabled"}

            def index_memory(self, memory, event, *, adapter_name=None):
                return {self.name: "ok:fake-id"}

            def capture_source(self, source, chunks):
                raise RuntimeError("llm inference failed with compact detail")

            def infer_memories(self, source):
                raise RuntimeError("llm inference failed with compact detail")

            def search(self, query, *, project_id, limit):
                return []

            def graph(self, project_id, *, limit=80):
                return {"nodes": [], "edges": []}

        with tempfile.TemporaryDirectory() as tmp:
            adapters = CompositeAdapters([ExplodingMem0Adapter()])
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
            self.assertEqual(result["inference_errors"], [])
            drained = store.drain_projection_jobs(limit=5)
            self.assertEqual(drained["failed"], 1)
            health_errors = json.loads(store.health()["adapters"]["last_inference_errors"])
            self.assertEqual({error["adapter"] for error in health_errors}, {"mem0"})

            reinferred = store.reinfer_sources({"source_id": "src:error"})
            self.assertEqual(reinferred["attempted"], 1)
            self.assertEqual(reinferred["errors"], [])
            retried = store.drain_projection_jobs(limit=5)
            self.assertEqual(retried["failed"], 1)

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
            self.assertEqual(failed["failed"], 0)
            self.assertEqual(failed["remaining"], 0)
            adapters.fail = False

            pending_only = store.drain_projection_jobs(limit=10)
            self.assertEqual(pending_only["delivered"], 0)
            self.assertEqual(adapters.indexed, [])
            self.assertEqual(pending_only["failed_total"], 0)

            retried = store.drain_projection_jobs(limit=10, include_failed=True)
            self.assertEqual(retried["delivered"], 0)
            self.assertIn("capture queue is empty", retried["message"])

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
            self.assertFalse(skipped["skipped"])
            self.assertEqual(skipped["delivered"], 0)
            self.assertEqual(skipped["failed"], 0)
            self.assertEqual(skipped["pending"], 0)
            self.assertIn("capture queue is empty", skipped["message"])

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
            store = MemoryStore(Path(tmp), adapters=FakeMem0Adapters())
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
            self.assertEqual(result["status"], "queued")
            store.drain_projection_jobs(limit=5)
            memory = store.memories(project_id="p")["memories"][0]
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
