from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from .adapters import MemoryAdapters, build_adapters
from .models import DETERMINISTIC_SOURCE_KINDS, MEMORY_STATUSES, MemoryInput, Scope, string_map
from .singleflight import SingleFlightGate


TRANSCRIPT_SOURCE_KINDS = {"codex_transcript", "claude_transcript"}
INSTRUCTION_SOURCE_KINDS = {"AGENTS.md", "CLAUDE.md"}
CONFIG_SOURCE_ONLY_KINDS = {"ai_config", "provider_config", "plugin_config", "plan"}
REINFER_SOURCE_KINDS = TRANSCRIPT_SOURCE_KINDS | {"terminal_capture", "manual", "user_instruction"}
MEM0_CAPTURE_SOURCE_KINDS = TRANSCRIPT_SOURCE_KINDS | INSTRUCTION_SOURCE_KINDS | {"terminal_capture", "manual", "user_instruction"}
MEM0_CAPTURE_VERSION = "mem0-direct-extract-v3"
MEMORY_VERSION_EVENT_TYPES = {
    "memory.observed",
    "memory.created",
    "memory.proposed",
    "memory.accepted",
    "memory.updated",
    "memory.deprecated",
    "memory.retracted",
    "memory.superseded",
    "memory.conflict_detected",
}
GRAPHITI_PROJECTION_ADAPTER = "graphiti"
RAW_TRANSCRIPT_REDACTION = (
    "[Legacy raw transcript excerpt redacted. Re-sync this session to store parsed "
    "user/assistant conversation text.]"
)
SENSITIVE_CONFIG_REDACTION = (
    "[Sensitive local AI configuration kept as source-only provenance. Raw "
    "settings JSON is not a canonical memory.]"
)
SOURCE_ONLY_CONFIG_REDACTION = (
    "[Configuration source kept as source-only provenance. Config, plugin, and "
    "plan files are not canonical memories.]"
)
NONCANONICAL_MEM0_REDACTION = (
    "[Non-canonical mem0 capture retracted. Re-capture this source to generate "
    "atomic reusable memories.]"
)
REPO_RULE_EXTRACTION_PROMPT = (
    "Extract reusable repository rules from this instruction file. Capture each "
    "specific build command, test command, workflow rule, architecture convention, "
    "UI standard, release rule, or provider/submodule rule as a separate self-contained "
    "memory. Keep concrete paths, commands, file names, and exceptions. Do not merge "
    "unrelated rules. Ignore headings that contain no actionable rule. Never store the "
    "source title, Markdown heading, Project/Source header, raw JSON, or an entire "
    "section as a memory; every memory must be a concise reusable claim."
)
TRANSCRIPT_EXTRACTION_PROMPT = (
    "Extract only durable project memories from this coding transcript: decisions, "
    "workflows, reusable commands, architecture facts, accepted constraints, and "
    "follow-up tasks. Skip chatter, one-off progress narration, raw logs, and secrets. "
    "Each memory must be concise, self-contained, and useful in a future coding session."
)


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


class MemoryStore:
    schema_version = 11
    api_version = 16

    def __init__(self, root: Path, adapters: MemoryAdapters | None = None):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.db_path = self.root / "code-memory.sqlite3"
        self.adapters = adapters if adapters is not None else build_adapters(root)
        self._capture_drain_gate = SingleFlightGate("mem0_capture_drain")
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self.conn.execute("PRAGMA busy_timeout=2500")
        self._migrate()
        self._enqueue_legacy_memories_for_mem0()

    def close(self) -> None:
        self.conn.close()

    def health(self) -> dict[str, Any]:
        counts = self._health_counts()
        pending = counts["capture_pending"]
        failed = counts["capture_failed"]
        capture_gate = self._capture_drain_gate.snapshot()
        return {
            "status": "ok",
            "api_version": self.api_version,
            "store": str(self.db_path),
            "event_count": counts["event_count"],
            "memory_count": counts["memory_count"],
            "total_memory_count": counts["total_memory_count"],
            "proposal_count": counts["proposal_count"],
            "module_count": counts["module_count"],
            "projection_pending": counts["projection_pending"],
            "projection_failed": counts["projection_failed"],
            "capture_pending": pending,
            "capture_failed": failed,
            "capture_running": bool(capture_gate.get("running")),
            "migration_pending": counts["migration_pending"],
            "adapters": self.adapters.health()
            | {
                "projection_pending": str(counts["projection_pending"]),
                "projection_failed": str(counts["projection_failed"]),
                "capture_pending": str(pending),
                "capture_failed": str(failed),
                "capture_running": "1" if capture_gate.get("running") else "0",
                "migration_pending": str(counts["migration_pending"]),
            },
        }

    def _health_counts(self) -> dict[str, int]:
        conn = sqlite3.connect(self.db_path)
        try:
            queries = {
                "event_count": ("SELECT COUNT(*) FROM memory_events", ()),
                "memory_count": ("SELECT COUNT(*) FROM memories WHERE status = 'active' AND extracted_by = 'mem0'", ()),
                "total_memory_count": ("SELECT COUNT(*) FROM memories WHERE extracted_by = 'mem0'", ()),
                "proposal_count": ("SELECT COUNT(*) FROM memories WHERE status = 'proposed' AND extracted_by = 'mem0'", ()),
                "module_count": ("SELECT COUNT(*) FROM modules", ()),
                "capture_pending": ("SELECT COUNT(*) FROM source_captures WHERE status = 'pending' AND capture_version = ?", (MEM0_CAPTURE_VERSION,)),
                "capture_failed": ("SELECT COUNT(*) FROM source_captures WHERE status = 'failed' AND capture_version = ?", (MEM0_CAPTURE_VERSION,)),
                "projection_pending": ("SELECT COUNT(*) FROM projection_jobs WHERE adapter = ? AND status = 'pending'", (GRAPHITI_PROJECTION_ADAPTER,)),
                "projection_failed": ("SELECT COUNT(*) FROM projection_jobs WHERE adapter = ? AND status = 'failed'", (GRAPHITI_PROJECTION_ADAPTER,)),
                "migration_pending": ("SELECT COUNT(*) FROM legacy_memory_migrations WHERE status = 'pending'", ()),
                "migration_failed": ("SELECT COUNT(*) FROM legacy_memory_migrations WHERE status = 'failed'", ()),
            }
            return {key: int(conn.execute(sql, params).fetchone()[0]) for key, (sql, params) in queries.items()}
        finally:
            conn.close()

    def append_event(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = str(payload.get("project_id") or "unknown")
        event_type = str(payload.get("event_type") or "memory.observed")
        actor = payload.get("actor") if isinstance(payload.get("actor"), dict) else {"kind": "agent"}
        before = payload.get("before") if isinstance(payload.get("before"), dict) else None
        after = payload.get("after") if isinstance(payload.get("after"), dict) else None
        delta = payload.get("delta") if isinstance(payload.get("delta"), dict) else None
        source_refs = payload.get("source_refs") if isinstance(payload.get("source_refs"), list) else []
        memory_id = payload.get("memory_id")

        previous = self.conn.execute(
            "SELECT seq, hash FROM memory_events ORDER BY seq DESC LIMIT 1"
        ).fetchone()
        seq = int(previous["seq"]) + 1 if previous else 1
        prev_hash = previous["hash"] if previous else None
        event_id = str(payload.get("event_id") or f"event:{uuid.uuid4()}")
        timestamp = float(payload.get("timestamp") or time.time())

        event_hash = hashlib.sha256(
            canonical_json(
                {
                    "event_id": event_id,
                    "seq": seq,
                    "timestamp": timestamp,
                    "project_id": project_id,
                    "actor": actor,
                    "event_type": event_type,
                    "memory_id": memory_id,
                    "before": before,
                    "after": after,
                    "delta": delta,
                    "source_refs": source_refs,
                    "prev_hash": prev_hash,
                }
            ).encode("utf-8")
        ).hexdigest()

        self.conn.execute(
            """
            INSERT INTO memory_events (
                event_id, seq, timestamp, project_id, actor_json, event_type,
                memory_id, before_json, after_json, delta_json, source_refs_json,
                reasoning_trace_id, request_id, hash, prev_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                event_id,
                seq,
                timestamp,
                project_id,
                canonical_json(actor),
                event_type,
                memory_id,
                canonical_json(before) if before is not None else None,
                canonical_json(after) if after is not None else None,
                canonical_json(delta) if delta is not None else None,
                canonical_json(source_refs),
                payload.get("reasoning_trace_id"),
                payload.get("request_id"),
                event_hash,
                prev_hash,
            ),
        )

        memory = None
        if event_type in {"memory.observed", "memory.created", "memory.proposed", "memory.accepted", "memory.updated"}:
            memory_payload = after or delta or payload
            if isinstance(memory_payload, dict):
                if source_refs and "source_refs" not in memory_payload:
                    memory_payload = dict(memory_payload)
                    memory_payload["source_refs"] = source_refs
                default_status = self._default_status(source_refs, event_type)
                memory_input = MemoryInput.from_json(memory_payload, project_id=project_id, default_status=default_status)
                memory = self._upsert_memory(self._with_module_scope(memory_input), event_id=event_id)
        elif event_type in {"memory.deprecated", "memory.retracted", "memory.superseded", "memory.conflict_detected"} and memory_id:
            status = {
                "memory.deprecated": "deprecated",
                "memory.retracted": "retracted",
                "memory.superseded": "superseded",
                "memory.conflict_detected": "conflicted",
            }[event_type]
            self.conn.execute(
                "UPDATE memories SET status = ?, invalid_at = COALESCE(invalid_at, ?), updated_at = ? WHERE id = ?",
                (status, timestamp, timestamp, memory_id),
            )
        elif event_type in {"memory.source_observed", "memory.extraction_requested"}:
            source_payload = after or delta or payload
            if isinstance(source_payload, dict):
                self._upsert_source(project_id, source_payload)

        self.conn.commit()
        event = self.event(event_id)
        if event_type in MEMORY_VERSION_EVENT_TYPES:
            memory_id = str(event.get("memory_id") or memory_id or "")
            if memory_id:
                row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
                if row is not None:
                    memory = self._memory_row(row)
                    self._record_memory_version(memory, event)
                    self._enqueue_projection_jobs(memory, event)
                    self.conn.commit()
        return event | ({"memory": memory} if memory else {})

    def propose_memory(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = str(payload.get("project_id") or "unknown")
        memory = MemoryInput.from_json(payload, project_id=project_id, default_status="proposed")
        return self.append_event(
            {
                "project_id": project_id,
                "event_type": "memory.proposed",
                "actor": payload.get("actor") or {"kind": "agent"},
                "after": self._memory_input_json(memory),
                "source_refs": memory.source_refs,
            }
        )

    def accept_memory(self, memory_id: str, actor: dict[str, Any] | None = None) -> dict[str, Any]:
        before = self._lookup_memory(memory_id)
        if before is None:
            raise KeyError(memory_id)
        after = self.adapters.update_memory(memory_id, {"status": "active"}) or (before | {"status": "active"})
        self._cache_mem0_memory(after)
        result = self.append_event(
            {
                "project_id": after.get("project_id") or before.get("project_id") or "unknown",
                "event_type": "memory.accepted",
                "actor": actor or {"kind": "human"},
                "memory_id": memory_id,
                "before": before,
                "after": after,
                "source_refs": after.get("source_refs", []),
            }
        )
        return result

    def reject_memory(self, memory_id: str, actor: dict[str, Any] | None = None) -> dict[str, Any]:
        before = self._lookup_memory(memory_id)
        if before is None:
            raise KeyError(memory_id)
        after = self.adapters.update_memory(memory_id, {"status": "retracted", "invalid_at": time.time()}) or (before | {"status": "retracted", "invalid_at": time.time()})
        self._cache_mem0_memory(after)
        return self.append_event(
            {
                "project_id": before["project_id"],
                "event_type": "memory.retracted",
                "actor": actor or {"kind": "human"},
                "memory_id": memory_id,
                "before": before,
                "after": after,
                "source_refs": before.get("source_refs", []),
            }
        )

    def deprecate_memory(self, memory_id: str, actor: dict[str, Any] | None = None) -> dict[str, Any]:
        before = self._lookup_memory(memory_id)
        if before is None:
            raise KeyError(memory_id)
        after = self.adapters.update_memory(memory_id, {"status": "deprecated", "invalid_at": time.time()}) or (before | {"status": "deprecated", "invalid_at": time.time()})
        self._cache_mem0_memory(after)
        return self.append_event(
            {
                "project_id": before["project_id"],
                "event_type": "memory.deprecated",
                "actor": actor or {"kind": "human"},
                "memory_id": memory_id,
                "before": before,
                "after": after,
                "source_refs": before.get("source_refs", []),
            }
        )

    def update_memory(self, memory_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        before = self._lookup_memory(memory_id)
        if before is None:
            raise KeyError(memory_id)
        after = before | {key: value for key, value in payload.items() if key in {
            "title", "body", "type", "status", "normalized_claim", "confidence", "importance",
            "source_refs", "metadata", "scope", "scopes", "valid_at", "invalid_at",
            "review_reason", "extracted_by",
        }}
        after["id"] = memory_id
        after["project_id"] = before["project_id"]
        after = self.adapters.update_memory(memory_id, after) or after
        self._cache_mem0_memory(after)
        return self.append_event(
            {
                "project_id": before["project_id"],
                "event_type": "memory.updated",
                "actor": payload.get("actor") if isinstance(payload.get("actor"), dict) else {"kind": "human"},
                "memory_id": memory_id,
                "before": before,
                "after": after,
                "source_refs": after.get("source_refs", []),
            }
        )

    def proposals(self, *, project_id: str | None = None, limit: int = 100) -> dict[str, Any]:
        list_memories = getattr(self.adapters, "list_memories", None)
        if callable(list_memories):
            memories = list_memories(project_id=project_id, status="proposed", memory_type=None, limit=max(1, min(limit, 500)))
            memories = [memory for memory in memories if _canonical_memory_rejection_reason(memory) is None]
            if memories:
                for memory in memories:
                    self._cache_mem0_memory(memory)
                return {"memories": memories}
        params: list[Any] = ["proposed"]
        where = ["status = ?", "extracted_by = 'mem0'"]
        if project_id:
            where.append("project_id = ?")
            params.append(project_id)
        params.append(limit)
        rows = self.conn.execute(
            f"""
            SELECT * FROM memories
            WHERE {' AND '.join(where)}
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            params,
        ).fetchall()
        memories = [self._memory_row(row) for row in rows]
        return {"memories": [memory for memory in memories if _canonical_memory_rejection_reason(memory) is None]}

    def events(self, *, project_id: str | None = None, after_seq: int | None = None, limit: int = 100) -> dict[str, Any]:
        params: list[Any] = []
        where = []
        if project_id:
            where.append("project_id = ?")
            params.append(project_id)
        if after_seq is not None:
            where.append("seq > ?")
            params.append(after_seq)
        sql_where = f"WHERE {' AND '.join(where)}" if where else ""
        params.append(limit)
        rows = self.conn.execute(
            f"SELECT * FROM memory_events {sql_where} ORDER BY seq DESC LIMIT ?",
            params,
        ).fetchall()
        return {"events": [self._event_row(row) for row in rows]}

    def memory_history(self, memory_id: str, *, limit: int = 200) -> dict[str, Any]:
        bounded_limit = max(1, min(limit, 500))
        version_rows = self.conn.execute(
            """
            SELECT *
            FROM memory_versions
            WHERE memory_id = ?
            ORDER BY version DESC
            LIMIT ?
            """,
            (memory_id, bounded_limit),
        ).fetchall()
        event_rows = self.conn.execute(
            """
            SELECT *
            FROM memory_events
            WHERE memory_id = ?
            ORDER BY seq DESC
            LIMIT ?
            """,
            (memory_id, bounded_limit),
        ).fetchall()
        return {
            "memory_id": memory_id,
            "versions": [self._version_row(row) for row in version_rows],
            "events": [self._event_row(row) for row in event_rows],
        }

    def modules(self, *, project_id: str | None = None) -> dict[str, Any]:
        params: list[Any] = []
        where = []
        if project_id:
            where.append("m.project_id = ?")
            params.append(project_id)
        sql_where = f"WHERE {' AND '.join(where)}" if where else ""
        rows = self.conn.execute(
            f"""
            SELECT
                m.*,
                COUNT(CASE WHEN mem.status = 'active' AND mem.extracted_by = 'mem0' THEN ms.memory_id END) AS memory_count,
                COUNT(ms.memory_id) AS total_memory_count,
                MAX(CASE WHEN mem.status = 'active' AND mem.extracted_by = 'mem0' THEN mem.updated_at END) AS updated_at
            FROM modules m
            LEFT JOIN memory_scopes ms ON ms.scope_id = m.scope_id
            LEFT JOIN memories mem ON mem.id = ms.memory_id AND mem.extracted_by = 'mem0'
            {sql_where}
            GROUP BY m.id
            ORDER BY memory_count DESC, m.title ASC
            """,
            params,
        ).fetchall()
        return {"modules": [dict(row) for row in rows]}

    def memories(
        self,
        *,
        project_id: str | None = None,
        module_id: str | None = None,
        status: str | None = "active",
        memory_type: str | None = None,
        limit: int = 100,
    ) -> dict[str, Any]:
        if project_id:
            list_memories = getattr(self.adapters, "list_memories", None)
            adapter_memories = (
                list_memories(
                    project_id=project_id,
                    status=status,
                    memory_type=memory_type,
                    limit=max(1, min(limit, 500)),
                )
                if callable(list_memories)
                else []
            )
            if module_id:
                adapter_memories = [
                    memory for memory in adapter_memories
                    if any(scope.get("id") == module_id for scope in memory.get("scopes", []) if isinstance(scope, dict))
                ]
            adapter_memories = [memory for memory in adapter_memories if _canonical_memory_rejection_reason(memory) is None]
            if adapter_memories:
                for memory in adapter_memories:
                    self._cache_mem0_memory(memory)
                return {"memories": adapter_memories}
        params: list[Any] = []
        where: list[str] = ["mem.extracted_by = 'mem0'"]
        joins = ""
        if module_id:
            joins = "JOIN memory_scopes ms ON ms.memory_id = mem.id"
            where.append("ms.scope_id = ?")
            params.append(module_id)
        if project_id:
            where.append("mem.project_id = ?")
            params.append(project_id)
        if status:
            where.append("mem.status = ?")
            params.append(status)
        if memory_type:
            where.append("mem.type = ?")
            params.append(memory_type)
        sql_where = f"WHERE {' AND '.join(where)}" if where else ""
        params.append(max(1, min(limit, 500)))
        rows = self.conn.execute(
            f"""
            SELECT mem.*
            FROM memories mem
            {joins}
            {sql_where}
            ORDER BY mem.importance DESC, mem.confidence DESC, mem.updated_at DESC
            LIMIT ?
            """,
            params,
        ).fetchall()
        memories = [self._memory_row(row) for row in rows]
        return {"memories": [memory for memory in memories if _canonical_memory_rejection_reason(memory) is None]}

    def ingest_source(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = str(payload.get("project_id") or "unknown")
        raw_body = str(payload.get("body") or payload.get("text") or "").strip()
        title = str(payload.get("title") or payload.get("path") or payload.get("uri") or "Source").strip()[:160]
        kind = str(payload.get("kind") or "source")
        path = str(payload.get("path") or "")
        uri = str(payload.get("uri") or path or payload.get("id") or title)
        content_hash = str(payload.get("content_hash") or hashlib.sha256(raw_body.encode("utf-8")).hexdigest())
        body = _normalized_source_body(kind, raw_body, project_id=project_id, title=title, path=path, uri=uri)
        source_id = str(payload.get("id") or "src:" + hashlib.sha256(canonical_json({
            "project_id": project_id,
            "kind": kind,
            "uri": uri,
            "hash": content_hash,
        }).encode("utf-8")).hexdigest()[:24])
        source = {
            "id": source_id,
            "project_id": project_id,
            "kind": kind,
            "title": title,
            "body": body,
            "uri": uri,
            "path": path,
            "content_hash": content_hash,
            "metadata": payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {},
        }
        self._upsert_episode(source)
        existing = self.conn.execute("SELECT content_hash FROM sources WHERE id = ?", (source_id,)).fetchone()
        if existing and existing["content_hash"] == content_hash and (
            not self._should_capture_source(kind, raw_body, title=title, path=path, uri=uri)
            or self._source_capture_succeeded(source_id, content_hash)
        ):
            return {"status": "skipped", "source": source, "created": [], "proposed": [], "inference_errors": []}

        observed: dict[str, Any] = {"status": "already_observed", "source_id": source_id}
        if not (existing and existing["content_hash"] == content_hash):
            observed = self.append_event(
                {
                    "event_id": f"event:{source_id}:observed:{content_hash[:12]}",
                    "project_id": project_id,
                    "event_type": "memory.source_observed",
                    "actor": payload.get("actor") if isinstance(payload.get("actor"), dict) else {"kind": "sync"},
                    "after": source,
                    "source_refs": [{"kind": kind, "uri": uri, "path": path, "content_hash": content_hash, "source_id": source_id, "episode_id": f"episode:{source_id}"}],
                }
            )
        created: list[dict[str, Any]] = []
        proposed: list[dict[str, Any]] = []
        inference_errors: list[dict[str, str]] = []
        queued = 0
        if self._should_capture_source(kind, raw_body, title=title, path=path, uri=uri):
            if self._source_capture_succeeded(source_id, content_hash):
                return {"status": "skipped", "source": source, "created": [], "proposed": [], "inference_errors": []}
            self._mark_source_capture(source_id, project_id, kind, content_hash, "pending")
            queued = 1
        return {
            "status": "queued" if queued else "ok",
            "event": observed,
            "source": source,
            "created": created,
            "proposed": proposed,
            "queued": queued,
            "inference_errors": inference_errors,
        }

    def reinfer_sources(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = payload.get("project_id") if isinstance(payload.get("project_id"), str) else None
        source_id = payload.get("source_id") if isinstance(payload.get("source_id"), str) else None
        limit = _bounded_int(payload.get("limit"), default=50, minimum=1, maximum=200)
        kinds = sorted(MEM0_CAPTURE_SOURCE_KINDS)
        placeholders = ",".join("?" for _ in kinds)
        params: list[Any] = list(kinds)
        where = [f"kind IN ({placeholders})"]
        if project_id:
            where.append("project_id = ?")
            params.append(project_id)
        if source_id:
            where.append("id = ?")
            params.append(source_id)
        params.append(limit)
        rows = self.conn.execute(
            f"""
            SELECT id, project_id, kind, title, uri, path, content_hash, excerpt, metadata_json, updated_at
            FROM sources
            WHERE {' AND '.join(where)}
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            params,
        ).fetchall()

        attempted = 0
        created = 0
        skipped = 0
        errors: list[dict[str, str]] = []
        for row in rows:
            source = self._source_row(row)
            body = self._reinfer_source_body(source)
            if not body:
                skipped += 1
                continue
            title = str(source.get("title") or "")
            path = str(source.get("path") or "")
            uri = str(source.get("uri") or "")
            kind = str(source.get("kind") or "")
            if not self._should_capture_source(kind, body, title=title, path=path, uri=uri):
                skipped += 1
                continue
            attempted += 1
            self._mark_source_capture(
                str(source["id"]),
                str(source["project_id"]),
                kind,
                str(source.get("content_hash") or ""),
                "pending",
            )

        return {
            "status": "ok",
            "scanned": len(rows),
            "attempted": attempted,
            "created": created,
            "proposed": 0,
            "skipped": skipped,
            "errors": errors,
        }

    def reindex(self, *, project_id: str | None = None, drain: bool = False, drain_limit: int | None = None) -> dict[str, Any]:
        event_types = sorted(MEMORY_VERSION_EVENT_TYPES)
        params: list[Any] = list(event_types)
        placeholders = ",".join("?" for _ in event_types)
        where = [f"event_type IN ({placeholders})", "memory_id IS NOT NULL"]
        if project_id:
            where.append("project_id = ?")
            params.append(project_id)
        rows = self.conn.execute(
            f"""
            SELECT *
            FROM memory_events
            WHERE {' AND '.join(where)}
            ORDER BY seq ASC
            LIMIT 1000
            """,
            params,
        ).fetchall()
        enqueued = 0
        for row in rows:
            event = self._event_row(row)
            memory_id = str(event.get("memory_id") or "")
            memory_row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
            if memory_row is None:
                continue
            enqueued += self._enqueue_projection_jobs(self._memory_row(memory_row), event, force=True)
        self.conn.commit()
        drained = None
        if drain:
            drained = self._drain_graphiti_projection_jobs(limit=drain_limit or 10, include_failed=False)
        pending = self._projection_count("pending")
        failed_total = self._projection_count("failed")
        return {
            "enqueued": enqueued,
            "remaining": pending + failed_total,
            "pending": pending,
            "failed_total": failed_total,
            "skipped": False,
            "message": f"Graphiti reindex enqueued {enqueued} projection job(s).",
            "drained": drained,
        }

    def drain_projection_jobs(self, *, limit: int = 10, include_failed: bool = False) -> dict[str, Any]:
        capture = self._drain_capture_jobs(limit=limit, include_failed=include_failed)
        projection = self._drain_graphiti_projection_jobs(limit=limit, include_failed=include_failed)
        delivered = int(capture.get("delivered") or 0) + int(projection.get("delivered") or 0)
        failed = int(capture.get("failed") or 0) + int(projection.get("failed") or 0)
        pending = int(capture.get("pending") or 0) + int(projection.get("pending") or 0)
        failed_total = int(capture.get("failed_total") or 0) + int(projection.get("failed_total") or 0)
        skipped_messages = [
            str(result.get("message") or "")
            for result in (capture, projection)
            if result.get("skipped") and result.get("message")
        ]
        message = (
            " ".join(skipped_messages)
            if skipped_messages
            else (
                f"Mem0 capture: {capture.get('delivered', 0)} captured, {capture.get('failed', 0)} failed. "
                f"Graphiti projection: {projection.get('delivered', 0)} delivered, {projection.get('failed', 0)} failed."
            )
        )
        return {
            "delivered": delivered,
            "failed": failed,
            "remaining": pending + failed_total,
            "pending": pending,
            "failed_total": failed_total,
            "skipped": bool(capture.get("skipped")) or bool(projection.get("skipped")),
            "message": message,
            "blockers": (capture.get("blockers") or {}) | (projection.get("blockers") or {}),
            "capture": capture,
            "projection": projection,
        }

    def _drain_capture_jobs(self, *, limit: int = 10, include_failed: bool = False) -> dict[str, Any]:
        with self._capture_drain_gate.run() as lease:
            if lease is None:
                return self._capture_drain_busy_response()
            result = self._drain_capture_jobs_locked(limit=limit, include_failed=include_failed)
            result["single_flight"] = lease.to_json()
            return result

    def _capture_drain_busy_response(self) -> dict[str, Any]:
        counts = self._health_counts()
        pending = counts["capture_pending"] + counts["migration_pending"]
        failed_total = counts["capture_failed"] + counts.get("migration_failed", 0)
        return {
            "delivered": 0,
            "failed": 0,
            "remaining": pending + failed_total,
            "pending": pending,
            "failed_total": failed_total,
            "skipped": True,
            "message": "Mem0 capture drain skipped because another capture drain is already running.",
            "blockers": {"capture": "already_running"},
            "single_flight": self._capture_drain_gate.snapshot(),
        }

    def _drain_capture_jobs_locked(self, *, limit: int = 10, include_failed: bool = False) -> dict[str, Any]:
        bounded_limit = max(1, min(limit, 25))
        pending_before = self._source_capture_count("pending") + self._legacy_migration_count("pending")
        failed_before = self._source_capture_count("failed") + self._legacy_migration_count("failed")
        if pending_before == 0 and (not include_failed or failed_before == 0):
            return {
                "delivered": 0,
                "failed": 0,
                "remaining": pending_before + failed_before,
                "pending": pending_before,
                "failed_total": failed_before,
                "skipped": False,
                "message": "Mem0 capture queue is empty.",
            }

        blockers = self._capture_adapter_blockers()
        if blockers:
            return {
                "delivered": 0,
                "failed": 0,
                "remaining": pending_before + failed_before,
                "pending": pending_before,
                "failed_total": failed_before,
                "skipped": True,
                "message": "Mem0 capture drain skipped because mem0 is unavailable.",
                "blockers": blockers,
            }

        delivered = 0
        failed = 0
        source_stats = self._drain_source_captures(limit=bounded_limit, include_failed=include_failed)
        delivered += source_stats["delivered"]
        failed += source_stats["failed"]
        remaining_limit = bounded_limit - source_stats["attempted"]
        if remaining_limit > 0:
            migration_stats = self._drain_legacy_migrations(limit=remaining_limit, include_failed=include_failed)
            delivered += migration_stats["delivered"]
            failed += migration_stats["failed"]

        pending_remaining = self._source_capture_count("pending") + self._legacy_migration_count("pending")
        failed_total = self._source_capture_count("failed") + self._legacy_migration_count("failed")
        return {
            "delivered": delivered,
            "failed": failed,
            "remaining": pending_remaining + failed_total,
            "pending": pending_remaining,
            "failed_total": failed_total,
            "skipped": False,
            "message": (
                f"Mem0 capture: {delivered} memories captured, "
                f"{failed} source/migration job(s) failed, "
                f"{pending_remaining + failed_total} remaining."
            ),
        }

    def search(self, query: str, *, project_id: str | None = None, limit: int = 20, status: str | None = "active") -> dict[str, Any]:
        results: list[dict[str, Any]] = []
        seen: set[str] = set()
        for result in self.adapters.search(query, project_id=project_id, limit=limit):
            memory = result.get("memory") if isinstance(result, dict) else None
            if not isinstance(memory, dict):
                continue
            if _canonical_memory_rejection_reason(memory) is not None:
                continue
            memory_id = memory.get("id")
            if not memory_id or memory_id in seen:
                continue
            metadata = memory.get("metadata") if isinstance(memory.get("metadata"), dict) else {}
            adapter_name = str(metadata.get("adapter") or result.get("match_kind") or "")
            if adapter_name and adapter_name != "mem0":
                continue
            if status and str(memory.get("status") or "active") != status:
                continue
            if project_id and memory.get("project_id") != project_id:
                continue
            result = dict(result)
            self._cache_mem0_memory(memory)
            seen.add(memory_id)
            results.append(result)
            if len(results) >= limit:
                break
        if not results and query.strip():
            results = self._cached_memory_search(query, project_id=project_id, limit=limit, status=status)
        for rank, result in enumerate(results, start=1):
            result["rank"] = rank
        trace_id = self._record_retrieval_trace(query=query, project_id=project_id, results=results)
        return {"query": query, "trace_id": trace_id, "results": results}

    def unified_search(self, payload: dict[str, Any]) -> dict[str, Any]:
        query = str(payload.get("query") or "").strip()
        filters = payload.get("filters") if isinstance(payload.get("filters"), dict) else {}
        project_id = filters.get("project_id") or payload.get("project_id")
        module_id = filters.get("module_id")
        limit = _bounded_int(payload.get("limit") or filters.get("limit"), default=20, minimum=1, maximum=100)
        statuses = filters.get("statuses") if isinstance(filters.get("statuses"), list) else None
        status = str(statuses[0]) if statuses else str(filters.get("status") or "active")
        include_graph_facts = _bool_value(filters.get("include_graph_facts", payload.get("include_graph_facts", True)))
        as_of = _float_or_none(filters.get("as_of"))

        canonical = self.search(query, project_id=project_id, limit=limit, status=status or None)
        memory_results = canonical["results"]
        graph_results: list[dict[str, Any]] = []
        if include_graph_facts:
            for result in self.adapters.search(query, project_id=project_id, limit=limit):
                fact = self._graph_fact_from_adapter_result(result, project_id=project_id)
                if fact is None:
                    continue
                if module_id and fact.get("module_id") != module_id:
                    continue
                if not _is_valid_at(fact.get("valid_at"), fact.get("invalid_at"), as_of):
                    continue
                graph_results.append(fact)
        return {
            "query": query,
            "trace_id": canonical["trace_id"],
            "memory_results": memory_results,
            "graph_results": graph_results[:limit],
            "source_results": self._source_results(project_id=project_id, query=query, limit=min(limit, 20)),
        }

    def context_pack(self, query: str, *, project_id: str | None = None, limit: int = 10) -> dict[str, Any]:
        unified = self.unified_search(
            {
                "query": query,
                "project_id": project_id,
                "limit": limit,
                "filters": {"project_id": project_id, "include_graph_facts": True},
            }
        )
        grouped: dict[str, list[dict[str, Any]]] = {
            "rules": [],
            "facts": [],
            "risks": [],
            "commands": [],
            "decisions": [],
        }
        for result in unified["memory_results"]:
            memory = result["memory"]
            key = {
                "rule": "rules",
                "convention": "rules",
                "fact": "facts",
                "risk": "risks",
                "command": "commands",
                "workflow": "commands",
                "decision": "decisions",
            }.get(memory["type"], "facts")
            grouped[key].append(memory)
        return {
            "query": query,
            "trace_id": unified["trace_id"],
            "context": grouped,
            "graph_facts": unified["graph_results"],
            "sources": unified["source_results"],
        }

    def projects(self) -> list[dict[str, Any]]:
        rows = self.conn.execute(
            """
            SELECT
                project_id,
                COUNT(CASE WHEN status = 'active' THEN 1 END) AS memory_count,
                COUNT(*) AS total_memory_count,
                SUM(CASE WHEN status = 'proposed' THEN 1 ELSE 0 END) AS proposal_count,
                MAX(CASE WHEN status = 'active' THEN updated_at END) AS updated_at
            FROM memories
            WHERE extracted_by = 'mem0'
            GROUP BY project_id
            ORDER BY updated_at DESC
            """
        ).fetchall()
        projects = {str(row["project_id"]): dict(row) for row in rows}
        for row in self.conn.execute("SELECT project_id, MAX(updated_at) AS updated_at FROM sources GROUP BY project_id"):
            project_id = str(row["project_id"])
            projects.setdefault(
                project_id,
                {
                    "project_id": project_id,
                    "memory_count": 0,
                    "total_memory_count": 0,
                    "proposal_count": 0,
                    "updated_at": row["updated_at"],
                },
            )
        return sorted(projects.values(), key=lambda item: float(item.get("updated_at") or 0), reverse=True)

    def graph(self, project_id: str) -> dict[str, Any]:
        nodes: dict[str, dict[str, Any]] = {}
        edges: list[dict[str, Any]] = []
        nodes[f"project:{project_id}"] = {"id": f"project:{project_id}", "kind": "project", "title": project_id}

        for scope in self.conn.execute("SELECT * FROM scopes WHERE project_id = ?", (project_id,)):
            nodes[scope["id"]] = {"id": scope["id"], "kind": scope["kind"], "title": scope["title"], "metadata": json.loads(scope["metadata_json"] or "{}")}
            edges.append({"source": f"project:{project_id}", "target": scope["id"], "kind": "HAS_SCOPE"})

        for memory in self.conn.execute("SELECT * FROM memories WHERE project_id = ? AND extracted_by = 'mem0'", (project_id,)):
            memory_node = f"memory:{memory['id']}"
            nodes[memory_node] = {
                "id": memory_node,
                "kind": "memory",
                "title": memory["title"],
                "type": memory["type"],
                "status": memory["status"],
                "body": memory["body"],
                "source_refs": json.loads(memory["source_refs_json"] or "[]"),
                "metadata": string_map(
                    json.loads(memory["metadata_json"] or "{}")
                    | {
                        "valid_at": memory["valid_at"],
                        "invalid_at": memory["invalid_at"],
                        "confidence": memory["confidence"],
                        "importance": memory["importance"],
                        "review_reason": memory["review_reason"],
                        "extracted_by": memory["extracted_by"],
                    }
                ),
            }
            for link in self.conn.execute("SELECT scope_id, primary_scope FROM memory_scopes WHERE memory_id = ?", (memory["id"],)):
                edges.append({"source": memory_node, "target": link["scope_id"], "kind": "SCOPED_TO", "primary": bool(link["primary_scope"])})

        for event in self.conn.execute("SELECT event_id, event_type, memory_id, seq FROM memory_events WHERE project_id = ? ORDER BY seq", (project_id,)):
            event_node = f"event:{event['event_id']}"
            nodes[event_node] = {"id": event_node, "kind": "event", "title": event["event_type"], "seq": event["seq"]}
            if event["memory_id"]:
                edges.append({"source": event_node, "target": f"memory:{event['memory_id']}", "kind": "AFFECTS"})

        for source in self.conn.execute("SELECT * FROM sources WHERE project_id = ?", (project_id,)):
            source_node = f"source:{source['id']}"
            nodes[source_node] = {
                "id": source_node,
                "kind": "source",
                "title": source["title"],
                "body": source["excerpt"],
                "metadata": string_map(json.loads(source["metadata_json"] or "{}")),
            }

        for episode in self.conn.execute("SELECT * FROM episodes WHERE project_id = ?", (project_id,)):
            episode_node = episode["id"] if str(episode["id"]).startswith("episode:") else f"episode:{episode['id']}"
            source_node = f"source:{episode['source_id']}"
            nodes[episode_node] = {
                "id": episode_node,
                "kind": "episode",
                "title": episode["title"],
                "body": episode["body_excerpt"],
                "metadata": string_map(json.loads(episode["metadata_json"] or "{}")),
            }
            edges.append({"source": source_node, "target": episode_node, "kind": "HAS_EPISODE"})

        for link in self.conn.execute("SELECT memory_id, episode_id, relation FROM memory_episode_links"):
            memory_node = f"memory:{link['memory_id']}"
            episode_node = link["episode_id"] if str(link["episode_id"]).startswith("episode:") else f"episode:{link['episode_id']}"
            if memory_node in nodes and episode_node in nodes:
                edges.append({"source": memory_node, "target": episode_node, "kind": "HAS_PROVENANCE", "metadata": {"relation": link["relation"]}})

        adapter_graph = self.adapters.graph(project_id)
        for node in adapter_graph.get("nodes", []):
            if isinstance(node, dict) and node.get("id"):
                nodes[str(node["id"])] = node
        for edge in adapter_graph.get("edges", []):
            if isinstance(edge, dict) and edge.get("source") and edge.get("target"):
                edges.append(edge)

        return {"project_id": project_id, "nodes": list(nodes.values()), "edges": edges}

    def trace(self, run_id: str) -> dict[str, Any]:
        row = self.conn.execute("SELECT * FROM run_traces WHERE run_id = ?", (run_id,)).fetchone()
        if row is None:
            return {"run_id": run_id, "request": None, "repo_state": {}, "memory_usage": []}
        usage = [
            dict(item)
            for item in self.conn.execute(
                "SELECT * FROM run_memory_usage WHERE run_id = ? ORDER BY rank ASC",
                (run_id,),
            )
        ]
        return {
            "run_id": run_id,
            "project_id": row["project_id"],
            "timestamp": row["timestamp"],
            "request": json.loads(row["request_json"] or "{}"),
            "repo_state": json.loads(row["repo_state_json"] or "{}"),
            "memory_usage": usage,
        }

    def review_items(self, *, project_id: str | None = None, limit: int = 100) -> dict[str, Any]:
        proposals = self.proposals(project_id=project_id, limit=limit)["memories"]
        conflicted = self.memories(project_id=project_id, status="conflicted", limit=limit)["memories"]
        low_confidence = [
            self._memory_row(row)
            for row in self.conn.execute(
                """
                SELECT * FROM memories
                WHERE status = 'active'
                  AND extracted_by = 'mem0'
                  AND confidence < 0.6
                  AND (? IS NULL OR project_id = ?)
                ORDER BY confidence ASC, updated_at DESC
                LIMIT ?
                """,
                (project_id, project_id, max(1, min(limit, 100))),
            )
        ]
        return {
            "proposals": proposals,
            "conflicts": conflicted,
            "low_confidence": low_confidence,
            "graph_facts": [],
        }

    def promote_graph_fact(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = str(payload.get("project_id") or "graphiti")
        fact = str(payload.get("fact") or payload.get("body") or payload.get("title") or "").strip()
        if not fact:
            raise ValueError("graph fact body is required")
        return self.propose_memory(
            {
                "project_id": project_id,
                "title": str(payload.get("title") or fact[:120]),
                "body": fact,
                "type": str(payload.get("type") or "fact"),
                "status": "proposed",
                "source_refs": payload.get("source_refs") if isinstance(payload.get("source_refs"), list) else [{"kind": "graphiti", "uri": str(payload.get("id") or "")}],
                "metadata": string_map(payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {}) | {
                    "promoted_from": "graphiti",
                    "graph_fact_id": str(payload.get("id") or ""),
                },
                "review_reason": "graph_fact_promotion",
                "extracted_by": "graphiti",
                "valid_at": payload.get("valid_at"),
                "invalid_at": payload.get("invalid_at"),
            }
        )

    def event(self, event_id: str) -> dict[str, Any]:
        row = self.conn.execute("SELECT * FROM memory_events WHERE event_id = ?", (event_id,)).fetchone()
        if row is None:
            raise KeyError(event_id)
        return self._event_row(row)

    def _graph_fact_from_adapter_result(self, result: dict[str, Any], *, project_id: str | None) -> dict[str, Any] | None:
        if not isinstance(result, dict):
            return None
        memory = result.get("memory") if isinstance(result.get("memory"), dict) else {}
        metadata = memory.get("metadata") if isinstance(memory.get("metadata"), dict) else {}
        adapter = str(metadata.get("adapter") or result.get("match_kind") or "")
        memory_id = str(memory.get("id") or "")
        if adapter != "graphiti" and not memory_id.startswith("graphiti:"):
            return None
        edge_uuid = str(metadata.get("edge_uuid") or memory_id.removeprefix("graphiti:"))
        fact = str(memory.get("body") or memory.get("title") or metadata.get("fact") or "")
        if not fact:
            return None
        resolved_project = str(memory.get("project_id") or project_id or "graphiti")
        valid_at = metadata.get("valid_at") or memory.get("valid_at")
        invalid_at = metadata.get("invalid_at") or memory.get("invalid_at")
        return {
            "id": memory_id or f"graphiti:{edge_uuid}",
            "project_id": resolved_project,
            "title": str(memory.get("title") or fact[:120]),
            "fact": fact,
            "relation": str(metadata.get("relation") or result.get("match_kind") or "RELATED_TO"),
            "source": str(metadata.get("source") or ""),
            "target": str(metadata.get("target") or ""),
            "valid_at": valid_at,
            "invalid_at": invalid_at,
            "score": float(result.get("score") or 0.0),
            "source_refs": memory.get("source_refs") if isinstance(memory.get("source_refs"), list) else [{"kind": "graphiti", "uri": edge_uuid}],
            "metadata": string_map(metadata | {"edge_uuid": edge_uuid}),
            "evidence": result.get("evidence") if isinstance(result.get("evidence"), list) else [{"adapter": "graphiti", "score": float(result.get("score") or 0.0), "detail": "temporal graph fact"}],
        }

    def _source_results(self, *, project_id: str | None, query: str, limit: int) -> list[dict[str, Any]]:
        params: list[Any] = []
        where: list[str] = []
        if project_id:
            where.append("project_id = ?")
            params.append(project_id)
        if query:
            like = f"%{query.lower()}%"
            where.append("(lower(title) LIKE ? OR lower(excerpt) LIKE ? OR lower(uri) LIKE ?)")
            params.extend([like, like, like])
        sql_where = f"WHERE {' AND '.join(where)}" if where else ""
        params.append(max(1, min(limit, 100)))
        rows = self.conn.execute(
            f"""
            SELECT id, project_id, kind, title, uri, path, content_hash, excerpt, metadata_json, updated_at
            FROM sources
            {sql_where}
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            params,
        ).fetchall()
        return [self._source_row(row) for row in rows]

    def _should_capture_source(self, kind: str, raw_body: str, *, title: str, path: str, uri: str) -> bool:
        if not raw_body.strip() or kind not in MEM0_CAPTURE_SOURCE_KINDS:
            return False
        if kind in CONFIG_SOURCE_ONLY_KINDS:
            return False
        return not _looks_like_sensitive_ai_config(kind, raw_body, title=title, path=path, uri=uri)

    def _capture_chunks_for_source(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        kind = str(source.get("kind") or "source")
        body = str(source.get("body") or "").strip()
        project_id = str(source.get("project_id") or "unknown")
        source_ref = {
            "kind": kind,
            "uri": str(source.get("uri") or ""),
            "path": str(source.get("path") or ""),
            "content_hash": str(source.get("content_hash") or ""),
            "source_id": str(source.get("id") or ""),
            "episode_id": f"episode:{source.get('id')}",
        }
        scope = source.get("scope") if isinstance(source.get("scope"), dict) else self._source_scope(
            project_id,
            path=str(source.get("path") or ""),
            uri=str(source.get("uri") or ""),
        ).to_json()
        scopes = [scope]

        def base_chunk(chunk_body: str, *, title: str, section: str = "", infer: bool = True, memory_type: str | None = None, prompt: str | None = None, line_start: int | None = None, line_end: int | None = None) -> dict[str, Any]:
            ref = dict(source_ref)
            if line_start is not None:
                ref["line_start"] = line_start
            if line_end is not None:
                ref["line_end"] = line_end
            return {
                "project_id": project_id,
                "title": title,
                "body": chunk_body,
                "type": memory_type or _memory_type_for_source(kind),
                "status": "active",
                "infer": infer,
                "prompt": prompt,
                "section": section,
                "capture_version": MEM0_CAPTURE_VERSION,
                "source_refs": [ref],
                "scopes": scopes,
                "metadata": string_map(source.get("metadata") if isinstance(source.get("metadata"), dict) else {}) | {
                    "infer": "true" if infer else "false",
                    "source_kind": kind,
                },
            }

        if kind in INSTRUCTION_SOURCE_KINDS:
            chunks: list[dict[str, Any]] = []
            for section in _markdown_sections(body):
                section_title = str(section.get("title") or source.get("title") or kind)
                chunks.append(
                    base_chunk(
                        _source_chunk_header(source, section_title) + "\n\n" + str(section["body"]),
                        title=section_title[:160],
                        section=section_title,
                        infer=True,
                        memory_type="convention",
                        prompt=REPO_RULE_EXTRACTION_PROMPT,
                        line_start=section.get("line_start"),
                        line_end=section.get("line_end"),
                    )
                )
            return chunks

        if kind in TRANSCRIPT_SOURCE_KINDS:
            return [
                base_chunk(
                    _source_chunk_header(source, str(source.get("title") or "Transcript")) + "\n\n" + chunk,
                    title=str(source.get("title") or "Transcript")[:160],
                    infer=True,
                    memory_type="workflow",
                    prompt=TRANSCRIPT_EXTRACTION_PROMPT,
                )
                for chunk in _paragraph_chunks(body, limit=14_000)
            ]

        return [
            base_chunk(
                body,
                title=str(source.get("title") or "Memory")[:160],
                infer=False,
                memory_type=_memory_type_for_source(kind),
            )
        ]

    def _source_capture_succeeded(self, source_id: str, content_hash: str) -> bool:
        row = self.conn.execute(
            """
            SELECT status FROM source_captures
            WHERE source_id = ? AND content_hash = ? AND capture_version = ?
            """,
            (source_id, content_hash, MEM0_CAPTURE_VERSION),
        ).fetchone()
        return row is not None and row["status"] == "succeeded"

    def _source_capture_count(self, status: str) -> int:
        row = self.conn.execute(
            "SELECT COUNT(*) AS count FROM source_captures WHERE status = ? AND capture_version = ?",
            (status, MEM0_CAPTURE_VERSION),
        ).fetchone()
        return int(row["count"])

    def _legacy_migration_count(self, status: str) -> int:
        row = self.conn.execute(
            "SELECT COUNT(*) AS count FROM legacy_memory_migrations WHERE status = ?",
            (status,),
        ).fetchone()
        return int(row["count"])

    def _capture_adapter_blockers(self) -> dict[str, str]:
        health = self.adapters.health()
        mem0 = str(health.get("mem0") or "").strip()
        if "enabled" in mem0.lower():
            return {}
        return {"mem0": mem0 or "mem0 unavailable"}

    def _drain_source_captures(self, *, limit: int, include_failed: bool) -> dict[str, int]:
        statuses = ["pending"]
        if include_failed:
            statuses.append("failed")
        placeholders = ",".join("?" for _ in statuses)
        rows = self.conn.execute(
            f"""
            SELECT
                cap.source_id,
                cap.project_id,
                cap.kind,
                cap.content_hash,
                src.title,
                src.uri,
                src.path,
                src.excerpt,
                src.metadata_json
            FROM source_captures cap
            LEFT JOIN sources src ON src.id = cap.source_id
            WHERE cap.capture_version = ?
              AND cap.status IN ({placeholders})
            ORDER BY
                CASE
                    WHEN cap.kind IN ('AGENTS.md', 'CLAUDE.md') THEN 0
                    WHEN cap.kind IN ('manual', 'user_instruction', 'terminal_capture') THEN 1
                    ELSE 2
                END,
                cap.updated_at ASC
            LIMIT ?
            """,
            (MEM0_CAPTURE_VERSION, *statuses, max(1, min(limit, 25))),
        ).fetchall()
        delivered = 0
        failed = 0
        attempted = 0
        for row in rows:
            attempted += 1
            source_id = str(row["source_id"])
            project_id = str(row["project_id"])
            kind = str(row["kind"])
            content_hash = str(row["content_hash"] or "")
            if row["title"] is None:
                self._mark_source_capture(source_id, project_id, kind, content_hash, "failed", error="source row missing")
                failed += 1
                continue
            source = {
                "id": source_id,
                "project_id": project_id,
                "kind": kind,
                "title": str(row["title"] or ""),
                "uri": str(row["uri"] or ""),
                "path": str(row["path"] or ""),
                "content_hash": content_hash,
                "excerpt": row["excerpt"],
                "metadata": string_map(json.loads(row["metadata_json"] or "{}")),
            }
            body = self._reinfer_source_body(source)
            if not body:
                self._mark_source_capture(source_id, project_id, kind, content_hash, "succeeded", created_count=0)
                continue
            if not self._should_capture_source(
                kind,
                body,
                title=str(source.get("title") or ""),
                path=str(source.get("path") or ""),
                uri=str(source.get("uri") or ""),
            ):
                self._mark_source_capture(source_id, project_id, kind, content_hash, "succeeded", created_count=0)
                continue
            inference_source = source | {
                "body": body,
                "scope": self._source_scope(
                    project_id,
                    path=str(source.get("path") or ""),
                    uri=str(source.get("uri") or ""),
                ).to_json(),
            }
            try:
                chunks = self._capture_chunks_for_source(inference_source)
                memories = self.adapters.capture_source(inference_source, chunks)
                accepted_memories: list[dict[str, Any]] = []
                for memory in memories:
                    cached = self._cache_mem0_memory(memory)
                    if cached is None:
                        continue
                    accepted_memories.append(cached)
                    self.append_event(
                        {
                            "project_id": cached.get("project_id") or project_id,
                            "event_type": "memory.observed",
                            "actor": {"kind": "background", "id": "mem0"},
                            "memory_id": cached.get("id"),
                            "after": cached,
                            "source_refs": cached.get("source_refs", []),
                        }
                    )
                inference_errors = self._adapter_inference_errors()
                if not memories and chunks:
                    mem0_health = self.adapters.health().get("mem0", "mem0 unavailable")
                    if "enabled" not in str(mem0_health).lower():
                        inference_errors = [{"adapter": "mem0", "error": str(mem0_health)}]
                elif memories and not accepted_memories:
                    inference_errors = [
                        {
                            "adapter": "mem0",
                            "error": "mem0 returned only non-canonical source/config payloads; no usable memory was stored",
                        }
                    ]
                if not accepted_memories and chunks and kind in INSTRUCTION_SOURCE_KINDS and not inference_errors:
                    inference_errors = [
                        {
                            "adapter": "mem0",
                            "error": "mem0 returned no usable repository-rule memories for this Markdown source",
                        }
                    ]
                if inference_errors:
                    self._mark_source_capture(
                        source_id,
                        project_id,
                        kind,
                        content_hash,
                        "failed",
                        error=inference_errors[0].get("error", ""),
                        created_count=len(accepted_memories),
                    )
                    failed += 1
                else:
                    self._mark_source_capture(source_id, project_id, kind, content_hash, "succeeded", created_count=len(accepted_memories))
                    delivered += len(accepted_memories)
            except Exception as error:  # noqa: BLE001
                self._mark_source_capture(source_id, project_id, kind, content_hash, "failed", error=_compact_exception(error))
                failed += 1
        return {"attempted": attempted, "delivered": delivered, "failed": failed}

    def _drain_legacy_migrations(self, *, limit: int, include_failed: bool) -> dict[str, int]:
        statuses = ["pending"]
        if include_failed:
            statuses.append("failed")
        placeholders = ",".join("?" for _ in statuses)
        rows = self.conn.execute(
            f"""
            SELECT mem.*
            FROM legacy_memory_migrations mig
            JOIN memories mem ON mem.id = mig.legacy_memory_id
            WHERE mig.status IN ({placeholders})
            ORDER BY mig.updated_at ASC
            LIMIT ?
            """,
            (*statuses, max(1, min(limit, 25))),
        ).fetchall()
        delivered = 0
        failed = 0
        for row in rows:
            legacy = self._memory_row(row)
            legacy_id = str(legacy["id"])
            source_kinds = {str(ref.get("kind") or "") for ref in legacy.get("source_refs", []) if isinstance(ref, dict)}
            if source_kinds & INSTRUCTION_SOURCE_KINDS:
                self._mark_legacy_migration(legacy_id, "skipped_instruction_source", None, "")
                continue
            try:
                migrated = self.adapters.capture_memory(
                    legacy | {"metadata": (legacy.get("metadata") or {}) | {"legacy_memory_id": legacy_id}}
                )
                inference_errors = self._adapter_inference_errors()
                if migrated is None:
                    message = inference_errors[0].get("error", "") if inference_errors else "mem0 returned no migrated memory"
                    self._mark_legacy_migration(legacy_id, "failed", None, message)
                    failed += 1
                    continue
                self._cache_mem0_memory(migrated)
                self._mark_legacy_migration(legacy_id, "succeeded", str(migrated.get("id") or ""), "")
                delivered += 1
            except Exception as error:  # noqa: BLE001
                self._mark_legacy_migration(legacy_id, "failed", None, _compact_exception(error))
                failed += 1
        return {"delivered": delivered, "failed": failed}

    def _mark_source_capture(
        self,
        source_id: str,
        project_id: str,
        kind: str,
        content_hash: str,
        status: str,
        *,
        error: str = "",
        created_count: int = 0,
    ) -> None:
        now = time.time()
        self.conn.execute(
            """
            INSERT INTO source_captures (
                source_id, project_id, kind, content_hash, capture_version,
                status, created_count, last_error, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_id, content_hash, capture_version) DO UPDATE SET
                status = excluded.status,
                created_count = excluded.created_count,
                last_error = excluded.last_error,
                updated_at = excluded.updated_at
            """,
            (source_id, project_id, kind, content_hash, MEM0_CAPTURE_VERSION, status, created_count, error or None, now, now),
        )
        self.conn.commit()

    def _cache_mem0_memory(self, memory: dict[str, Any]) -> dict[str, Any] | None:
        if not isinstance(memory, dict) or not str(memory.get("id") or "").strip():
            return None
        if _canonical_memory_rejection_reason(memory) is not None:
            return None
        payload = dict(memory)
        metadata = payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {}
        payload["metadata"] = metadata | {"adapter": "mem0", "cache_source": "mem0"}
        payload["extracted_by"] = "mem0"
        memory_input = MemoryInput.from_json(payload, project_id=payload.get("project_id"), default_status=str(payload.get("status") or "active"))
        cached = self._upsert_memory(self._with_module_scope(memory_input), event_id=str(metadata.get("last_event_id") or f"cache:{payload['id']}"))
        self.conn.commit()
        return cached

    def _lookup_memory(self, memory_id: str) -> dict[str, Any] | None:
        memory = self.adapters.get_memory(memory_id)
        if memory is not None:
            self._cache_mem0_memory(memory)
            return memory
        row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
        return self._memory_row(row) if row is not None else None

    def _cached_memory_search(self, query: str, *, project_id: str | None, limit: int, status: str | None) -> list[dict[str, Any]]:
        like = f"%{query.lower()}%"
        params: list[Any] = [like, like]
        where = ["mem.extracted_by = 'mem0'", "(lower(mem.title) LIKE ? OR lower(mem.body) LIKE ?)"]
        if project_id:
            where.append("mem.project_id = ?")
            params.append(project_id)
        if status:
            where.append("mem.status = ?")
            params.append(status)
        params.append(max(1, min(limit, 100)))
        rows = self.conn.execute(
            f"""
            SELECT mem.*
            FROM memories mem
            WHERE {' AND '.join(where)}
            ORDER BY mem.importance DESC, mem.confidence DESC, mem.updated_at DESC
            LIMIT ?
            """,
            params,
        ).fetchall()
        results: list[dict[str, Any]] = []
        for rank, row in enumerate(rows, start=1):
            memory = self._memory_row(row)
            if _canonical_memory_rejection_reason(memory) is not None:
                continue
            score = self._lexical_score(query, memory)
            results.append(
                {
                    "rank": rank,
                    "score": score,
                    "memory": memory,
                    "match_kind": "cache",
                    "evidence": [{"adapter": "sqlite-cache", "score": score, "detail": "mem0 cache lexical fallback"}],
                }
            )
        return results

    def _enqueue_legacy_memories_for_mem0(self, *, limit: int = 200) -> None:
        rows = self.conn.execute(
            """
            SELECT mem.*
            FROM memories mem
            LEFT JOIN legacy_memory_migrations mig ON mig.legacy_memory_id = mem.id
            WHERE mem.status IN ('active', 'proposed')
              AND COALESCE(mem.extracted_by, '') != 'mem0'
              AND mig.legacy_memory_id IS NULL
            ORDER BY mem.updated_at DESC
            LIMIT ?
            """,
            (max(1, min(limit, 500)),),
        ).fetchall()
        for row in rows:
            legacy = self._memory_row(row)
            source_kinds = {str(ref.get("kind") or "") for ref in legacy.get("source_refs", []) if isinstance(ref, dict)}
            if source_kinds & INSTRUCTION_SOURCE_KINDS:
                self._mark_legacy_migration(str(legacy["id"]), "skipped_instruction_source", None, "")
                continue
            self._mark_legacy_migration(str(legacy["id"]), "pending", None, "")

    def _migrate_legacy_memories_to_mem0(self, *, limit: int = 200) -> None:
        self._enqueue_legacy_memories_for_mem0(limit=limit)

    def _mark_legacy_migration(self, legacy_memory_id: str, status: str, mem0_id: str | None, error: str) -> None:
        now = time.time()
        self.conn.execute(
            """
            INSERT INTO legacy_memory_migrations (
                legacy_memory_id, status, mem0_id, last_error, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(legacy_memory_id) DO UPDATE SET
                status = excluded.status,
                mem0_id = excluded.mem0_id,
                last_error = excluded.last_error,
                updated_at = excluded.updated_at
            """,
            (legacy_memory_id, status, mem0_id, error or None, now, now),
        )
        self.conn.commit()

    def _infer_memory_candidates(self, source: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
        try:
            candidates = self.adapters.infer_memories(source)
        except Exception as error:  # noqa: BLE001
            adapter_name = str(getattr(self.adapters, "name", "") or self.adapters.__class__.__name__)
            return [], [{"adapter": adapter_name, "error": _compact_exception(error)}]
        return candidates, self._adapter_inference_errors()

    def _adapter_inference_errors(self) -> list[dict[str, str]]:
        getter = getattr(self.adapters, "inference_errors", None)
        if not callable(getter):
            return []
        raw_errors = getter()
        if not isinstance(raw_errors, list):
            return []
        errors: list[dict[str, str]] = []
        for item in raw_errors:
            if not isinstance(item, dict):
                continue
            message = str(item.get("error") or item.get("message") or "").strip()
            if not message:
                continue
            errors.append(
                {
                    "adapter": str(item.get("adapter") or "adapter"),
                    "error": _excerpt(message, 320),
                }
            )
        return errors

    def _reinfer_source_body(self, source: dict[str, Any]) -> str:
        kind = str(source.get("kind") or "")
        title = str(source.get("title") or "")
        path = str(source.get("path") or "")
        uri = str(source.get("uri") or "")
        project_id = str(source.get("project_id") or "")
        path_value = Path(path).expanduser() if path else None
        if path_value and path_value.is_file():
            try:
                if path_value.stat().st_size <= 2 * 1024 * 1024:
                    raw = path_value.read_text(encoding="utf-8", errors="replace")
                    body = _normalized_source_body(kind, raw, project_id=project_id, title=title, path=path, uri=uri).strip()
                    if body and body != RAW_TRANSCRIPT_REDACTION:
                        return body
            except OSError:
                pass
        episode = self.conn.execute(
            """
            SELECT body_excerpt
            FROM episodes
            WHERE source_id = ?
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (source.get("id"),),
        ).fetchone()
        for candidate in (episode["body_excerpt"] if episode is not None else None, source.get("excerpt")):
            body = str(candidate or "").strip()
            if body and body != RAW_TRANSCRIPT_REDACTION:
                return body
        return ""

    def _projection_count(self, status: str) -> int:
        row = self.conn.execute(
            "SELECT COUNT(*) AS count FROM projection_jobs WHERE adapter = ? AND status = ?",
            (GRAPHITI_PROJECTION_ADAPTER, status),
        ).fetchone()
        return int(row["count"])

    def _projection_adapter_blockers(self) -> dict[str, str]:
        names = set(self.adapters.names())
        if GRAPHITI_PROJECTION_ADAPTER not in names:
            return {GRAPHITI_PROJECTION_ADAPTER: "graphiti adapter is not configured"}
        health = self.adapters.health()
        blockers: dict[str, str] = {}
        status = str(health.get(GRAPHITI_PROJECTION_ADAPTER, "unavailable")).strip()
        normalized = status.lower()
        if (
            "endpoint unavailable" in normalized
            or normalized.startswith("unavailable")
            or normalized.startswith("disabled")
            or normalized.startswith("error")
        ):
            blockers[GRAPHITI_PROJECTION_ADAPTER] = status
        return blockers

    def _enqueue_projection_jobs(self, memory: dict[str, Any], event: dict[str, Any], *, force: bool = False) -> int:
        if GRAPHITI_PROJECTION_ADAPTER not in set(self.adapters.names()):
            return 0
        now = time.time()
        count = 0
        adapter = GRAPHITI_PROJECTION_ADAPTER
        job_id = "job:" + hashlib.sha256(canonical_json({
            "adapter": adapter,
            "memory_id": memory["id"],
            "event_id": event.get("event_id"),
        }).encode("utf-8")).hexdigest()[:24]
        if force:
            self.conn.execute("DELETE FROM projection_jobs WHERE id = ?", (job_id,))
        cursor = self.conn.execute(
            """
            INSERT OR IGNORE INTO projection_jobs (
                id, adapter, memory_id, event_id, status, attempt_count,
                last_error, created_at, updated_at
            ) VALUES (?, ?, ?, ?, 'pending', 0, NULL, ?, ?)
            """,
            (job_id, adapter, memory["id"], event.get("event_id") or "", now, now),
        )
        count += max(0, cursor.rowcount)
        return count

    def _drain_graphiti_projection_jobs(self, *, limit: int = 10, include_failed: bool = False) -> dict[str, Any]:
        bounded_limit = max(1, min(limit, 25))
        pending_before = self._projection_count("pending")
        failed_before = self._projection_count("failed")
        if pending_before == 0 and (not include_failed or failed_before == 0):
            return {
                "delivered": 0,
                "failed": 0,
                "remaining": pending_before + failed_before,
                "pending": pending_before,
                "failed_total": failed_before,
                "skipped": False,
                "message": "Graphiti projection queue is empty.",
            }

        statuses = ["pending"]
        if include_failed:
            statuses.append("failed")
        placeholders = ",".join("?" for _ in statuses)
        rows = self.conn.execute(
            f"""
            SELECT *
            FROM projection_jobs
            WHERE adapter = ?
              AND status IN ({placeholders})
            ORDER BY updated_at ASC
            LIMIT ?
            """,
            (GRAPHITI_PROJECTION_ADAPTER, *statuses, bounded_limit),
        ).fetchall()
        blockers = self._projection_adapter_blockers()
        if blockers:
            now = time.time()
            failed_ids = [str(row["id"]) for row in rows if row["status"] == "pending"]
            if failed_ids:
                placeholders = ",".join("?" for _ in failed_ids)
                self.conn.execute(
                    f"""
                    UPDATE projection_jobs
                    SET status = 'failed',
                        attempt_count = attempt_count + 1,
                        last_error = ?,
                        updated_at = ?
                    WHERE id IN ({placeholders})
                    """,
                    (next(iter(blockers.values())), now, *failed_ids),
                )
                self.conn.commit()
            pending_after = self._projection_count("pending")
            failed_after = self._projection_count("failed")
            return {
                "delivered": 0,
                "failed": len(failed_ids),
                "remaining": pending_after + failed_after,
                "pending": pending_after,
                "failed_total": failed_after,
                "skipped": True,
                "message": "Graphiti projection skipped because graphiti is unavailable.",
                "blockers": blockers,
            }

        delivered = 0
        failed = 0
        now = time.time()
        for row in rows:
            job_id = str(row["id"])
            try:
                event = self.event(str(row["event_id"]))
                memory_id = str(row["memory_id"])
                memory_row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
                memory = self._memory_row(memory_row) if memory_row is not None else event.get("after")
                if not isinstance(memory, dict):
                    raise KeyError(memory_id)
                result = self.adapters.index_memory(memory, event, adapter_name=GRAPHITI_PROJECTION_ADAPTER)
                status = str(result.get(GRAPHITI_PROJECTION_ADAPTER) or "")
                if not status.startswith("ok:"):
                    raise RuntimeError(status or "graphiti projection returned no adapter status")
                adapter_id = status.removeprefix("ok:")
                self.conn.execute(
                    """
                    INSERT OR REPLACE INTO adapter_mappings (
                        memory_id, adapter, adapter_id, metadata_json, updated_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        memory_id,
                        GRAPHITI_PROJECTION_ADAPTER,
                        adapter_id,
                        canonical_json({"event_id": event.get("event_id"), "job_id": job_id}),
                        now,
                    ),
                )
                self.conn.execute(
                    """
                    UPDATE projection_jobs
                    SET status = 'done',
                        attempt_count = attempt_count + 1,
                        last_error = NULL,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (now, job_id),
                )
                delivered += 1
            except Exception as error:  # noqa: BLE001
                self.conn.execute(
                    """
                    UPDATE projection_jobs
                    SET status = 'failed',
                        attempt_count = attempt_count + 1,
                        last_error = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (_compact_exception(error), now, job_id),
                )
                failed += 1
        self.conn.commit()
        pending_after = self._projection_count("pending")
        failed_after = self._projection_count("failed")
        return {
            "delivered": delivered,
            "failed": failed,
            "remaining": pending_after + failed_after,
            "pending": pending_after,
            "failed_total": failed_after,
            "skipped": False,
            "message": (
                f"Graphiti projection: {delivered} event(s) delivered, "
                f"{failed} job(s) failed, {pending_after + failed_after} remaining."
            ),
        }

    def _upsert_source(self, project_id: str, payload: dict[str, Any]) -> None:
        kind = str(payload.get("kind") or "source")
        body = str(payload.get("body") or payload.get("text") or "")
        content_hash = str(payload.get("content_hash") or hashlib.sha256(body.encode("utf-8")).hexdigest())
        uri = str(payload.get("uri") or payload.get("path") or "")
        title = str(payload.get("title") or uri or "").strip()[:160]
        display_body = _normalized_source_body(
            kind,
            body,
            project_id=project_id,
            title=title or "Source",
            path=str(payload.get("path") or ""),
            uri=uri,
        )
        source_id = str(payload.get("id") or "src:" + hashlib.sha256(canonical_json({
            "project_id": project_id,
            "kind": kind,
            "uri": uri,
            "hash": content_hash,
        }).encode("utf-8")).hexdigest()[:24])
        if not title:
            title = source_id
        if not uri:
            uri = source_id
        self.conn.execute(
            """
            INSERT INTO sources (
                id, project_id, kind, title, uri, path, commit_sha, content_hash, excerpt, metadata_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                title = excluded.title,
                uri = excluded.uri,
                path = excluded.path,
                commit_sha = excluded.commit_sha,
                content_hash = excluded.content_hash,
                excerpt = excluded.excerpt,
                metadata_json = excluded.metadata_json,
                updated_at = excluded.updated_at
            """,
            (
                source_id,
                project_id,
                kind,
                title,
                uri,
                payload.get("path"),
                payload.get("commit_sha"),
                content_hash,
                _excerpt(display_body, 800),
                canonical_json(payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {}),
                time.time(),
            ),
        )

    def _upsert_episode(self, source: dict[str, Any]) -> None:
        episode_id = str(source.get("episode_id") or f"episode:{source['id']}")
        body = _normalized_source_body(
            str(source["kind"]),
            str(source.get("body") or ""),
            project_id=str(source["project_id"]),
            title=str(source["title"]),
            path=str(source.get("path") or ""),
            uri=str(source.get("uri") or ""),
        )
        now = time.time()
        self.conn.execute(
            """
            INSERT INTO episodes (
                id, source_id, project_id, kind, title, body_excerpt, reference_time, metadata_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                body_excerpt = excluded.body_excerpt,
                reference_time = excluded.reference_time,
                metadata_json = excluded.metadata_json,
                updated_at = excluded.updated_at
            """,
            (
                episode_id,
                source["id"],
                source["project_id"],
                source["kind"],
                source["title"],
                _excerpt(body, 1200),
                float(source.get("reference_time") or now),
                canonical_json(source.get("metadata") if isinstance(source.get("metadata"), dict) else {}),
                now,
                now,
            ),
        )

    def _source_scope(self, project_id: str, *, path: str = "", uri: str = "") -> Scope:
        module = self._infer_module(project_id, [{"path": path, "uri": uri}])
        if module:
            return module
        return Scope(kind="project", key=project_id, title=project_id)

    def _with_module_scope(self, memory: MemoryInput) -> MemoryInput:
        if any(scope.kind == "module" for scope in memory.scopes):
            self._upsert_modules(memory.project_id, memory.scopes)
            return memory
        module = self._infer_module(memory.project_id, memory.source_refs)
        if module is None:
            self._upsert_modules(memory.project_id, memory.scopes)
            return memory
        next_scopes = list(memory.scopes)
        if not any(scope.id == module.id for scope in next_scopes):
            next_scopes.append(module)
        self._upsert_modules(memory.project_id, next_scopes)
        return MemoryInput(
            project_id=memory.project_id,
            title=memory.title,
            body=memory.body,
            type=memory.type,
            status=memory.status,
            memory_id=memory.memory_id,
            normalized_claim=memory.normalized_claim,
            confidence=memory.confidence,
            importance=memory.importance,
            scopes=next_scopes,
            source_refs=memory.source_refs,
            metadata=memory.metadata,
            valid_at=memory.valid_at,
            invalid_at=memory.invalid_at,
            review_reason=memory.review_reason,
            extracted_by=memory.extracted_by,
        )

    def _infer_module(self, project_id: str, source_refs: list[dict[str, Any]]) -> Scope | None:
        for ref in source_refs:
            raw_path = str(ref.get("path") or ref.get("uri") or "")
            if not raw_path:
                continue
            normalized = raw_path.replace("\\", "/")
            parts = [part for part in normalized.split("/") if part and part not in {".", "~"}]
            if not parts:
                continue
            module = _module_name(parts, project_id)
            if module:
                return Scope(kind="module", key=f"{project_id}:{module}", title=module, metadata={"classifier": "path"})
        return None

    def _upsert_modules(self, project_id: str, scopes: list[Scope]) -> None:
        for scope in scopes:
            if scope.kind != "module":
                continue
            self.conn.execute(
                """
                INSERT INTO modules (id, project_id, scope_id, title, classifier, metadata_json, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    classifier = excluded.classifier,
                    metadata_json = excluded.metadata_json,
                    updated_at = excluded.updated_at
                """,
                (
                    scope.id,
                    project_id,
                    scope.id,
                    scope.title or scope.key,
                    str(scope.metadata.get("classifier") or "path"),
                    canonical_json(scope.metadata),
                    time.time(),
                    time.time(),
                ),
            )

    def _default_status(self, source_refs: list[Any], event_type: str) -> str:
        if event_type == "memory.proposed":
            return "proposed"
        for ref in source_refs:
            if isinstance(ref, dict) and ref.get("kind") in DETERMINISTIC_SOURCE_KINDS:
                return "active"
        return "proposed" if event_type == "memory.observed" else "active"

    def _upsert_memory(self, memory: MemoryInput, *, event_id: str) -> dict[str, Any]:
        if not memory.body:
            raise ValueError("memory body is required")
        now = time.time()
        memory_id = memory.memory_id or self._stable_memory_id(memory)
        claim = memory.normalized_claim or self._default_claim(memory)
        self.conn.execute(
            """
            INSERT INTO memories (
                id, project_id, type, status, title, body, normalized_claim,
                confidence, importance, source_refs_json, metadata_json, valid_at,
                invalid_at, review_reason, extracted_by, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type = excluded.type,
                status = excluded.status,
                title = excluded.title,
                body = excluded.body,
                normalized_claim = excluded.normalized_claim,
                confidence = excluded.confidence,
                importance = excluded.importance,
                source_refs_json = excluded.source_refs_json,
                metadata_json = excluded.metadata_json,
                valid_at = excluded.valid_at,
                invalid_at = excluded.invalid_at,
                review_reason = excluded.review_reason,
                extracted_by = excluded.extracted_by,
                updated_at = excluded.updated_at
            """,
            (
                memory_id,
                memory.project_id,
                memory.type,
                memory.status,
                memory.title,
                memory.body,
                claim,
                memory.confidence,
                memory.importance,
                canonical_json(memory.source_refs),
                canonical_json(memory.metadata | {"last_event_id": event_id}),
                memory.valid_at,
                memory.invalid_at,
                memory.review_reason,
                memory.extracted_by,
                now,
                now,
            ),
        )
        self.conn.execute("DELETE FROM memory_scopes WHERE memory_id = ?", (memory_id,))
        self.conn.execute("DELETE FROM memory_episode_links WHERE memory_id = ?", (memory_id,))
        for index, scope in enumerate(memory.scopes):
            self._upsert_scope(memory.project_id, scope)
            self.conn.execute(
                "INSERT OR REPLACE INTO memory_scopes (memory_id, scope_id, primary_scope) VALUES (?, ?, ?)",
                (memory_id, scope.id, 1 if index == 0 else 0),
            )
        for ref in memory.source_refs:
            episode_id = ref.get("episode_id")
            if not episode_id and ref.get("source_id"):
                episode_id = f"episode:{ref['source_id']}"
            if episode_id:
                self.conn.execute(
                    "INSERT OR IGNORE INTO memory_episode_links (memory_id, episode_id, relation) VALUES (?, ?, ?)",
                    (memory_id, str(episode_id), "evidence"),
                )
        self.conn.execute("UPDATE memory_events SET memory_id = ? WHERE event_id = ?", (memory_id, event_id))
        row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
        return self._memory_row(row)

    def _upsert_scope(self, project_id: str, scope: Scope) -> None:
        self.conn.execute(
            """
            INSERT INTO scopes (id, project_id, kind, key, title, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                metadata_json = excluded.metadata_json
            """,
            (scope.id, project_id, scope.kind, scope.key, scope.title or scope.key, canonical_json(scope.metadata)),
        )

    def _record_retrieval_trace(self, *, query: str, project_id: str | None, results: list[dict[str, Any]]) -> str:
        run_id = f"run:{uuid.uuid4()}"
        self.conn.execute(
            "INSERT INTO run_traces (run_id, project_id, timestamp, request_json, repo_state_json) VALUES (?, ?, ?, ?, ?)",
            (run_id, project_id, time.time(), canonical_json({"query": query}), canonical_json({})),
        )
        for result in results:
            self.conn.execute(
                """
                INSERT INTO run_memory_usage (run_id, memory_id, usage_kind, rank, score, features_json)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    run_id,
                    result["memory"]["id"],
                    "retrieved",
                    result["rank"],
                    result["score"],
                    canonical_json({"match_kind": result["match_kind"], "evidence": result.get("evidence", [])}),
                ),
            )
        self.conn.commit()
        return run_id

    def _stable_memory_id(self, memory: MemoryInput) -> str:
        raw = canonical_json(
            {
                "project_id": memory.project_id,
                "type": memory.type,
                "claim": memory.normalized_claim or memory.body,
                "scopes": [scope.id for scope in memory.scopes],
                "sources": [ref.get("content_hash") or ref.get("uri") or ref.get("path") for ref in memory.source_refs],
            }
        )
        return "mem:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]

    def _default_claim(self, memory: MemoryInput) -> str:
        return hashlib.sha256(memory.body.strip().lower().encode("utf-8")).hexdigest()

    def _lexical_score(self, query: str, memory: dict[str, Any]) -> float:
        terms = {term for term in query.lower().split() if term}
        if not terms:
            return 0.0
        haystack = f"{memory['title']} {memory['body']}".lower()
        hits = sum(1 for term in terms if term in haystack)
        return hits / len(terms)

    def _memory_input_json(self, memory: MemoryInput) -> dict[str, Any]:
        return {
            "id": memory.memory_id,
            "project_id": memory.project_id,
            "title": memory.title,
            "body": memory.body,
            "type": memory.type,
            "status": memory.status,
            "normalized_claim": memory.normalized_claim,
            "confidence": memory.confidence,
            "importance": memory.importance,
            "scope": [scope.to_json() for scope in memory.scopes],
            "source_refs": memory.source_refs,
            "metadata": memory.metadata,
            "valid_at": memory.valid_at,
            "invalid_at": memory.invalid_at,
            "review_reason": memory.review_reason,
            "extracted_by": memory.extracted_by,
        }

    def _memory_row(self, row: sqlite3.Row) -> dict[str, Any]:
        scopes = [
            self._scope_row(scope)
            for scope in self.conn.execute(
                """
                SELECT s.*, ms.primary_scope
                FROM memory_scopes ms
                JOIN scopes s ON s.id = ms.scope_id
                WHERE ms.memory_id = ?
                ORDER BY ms.primary_scope DESC, s.kind, s.key
                """,
                (row["id"],),
            )
        ]
        return {
            "id": row["id"],
            "project_id": row["project_id"],
            "type": row["type"],
            "status": row["status"],
            "title": row["title"],
            "body": row["body"],
            "normalized_claim": row["normalized_claim"],
            "confidence": row["confidence"],
            "importance": row["importance"],
            "source_refs": json.loads(row["source_refs_json"] or "[]"),
            "metadata": string_map(json.loads(row["metadata_json"] or "{}")),
            "scopes": scopes,
            "valid_at": row["valid_at"],
            "invalid_at": row["invalid_at"],
            "review_reason": row["review_reason"],
            "extracted_by": row["extracted_by"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def _record_memory_version(self, memory: dict[str, Any], event: dict[str, Any]) -> dict[str, Any]:
        memory_id = str(memory.get("id") or event.get("memory_id") or "")
        if not memory_id:
            raise ValueError("memory version requires memory_id")
        row = self.conn.execute(
            "SELECT COALESCE(MAX(version), 0) AS version FROM memory_versions WHERE memory_id = ?",
            (memory_id,),
        ).fetchone()
        version = int(row["version"] or 0) + 1
        timestamp = float(event.get("timestamp") or time.time())
        self.conn.execute(
            """
            INSERT OR REPLACE INTO memory_versions (
                memory_id, version, event_id, event_type, project_id, timestamp,
                title, body, type, status, normalized_claim, confidence,
                importance, source_refs_json, metadata_json, valid_at,
                invalid_at, review_reason, extracted_by, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                memory_id,
                version,
                event.get("event_id"),
                event.get("event_type"),
                memory.get("project_id") or event.get("project_id"),
                timestamp,
                memory.get("title") or "",
                memory.get("body") or "",
                memory.get("type") or "fact",
                memory.get("status") or "active",
                memory.get("normalized_claim") or "",
                float(memory.get("confidence") or 0),
                float(memory.get("importance") or 0),
                canonical_json(memory.get("source_refs") if isinstance(memory.get("source_refs"), list) else []),
                canonical_json(memory.get("metadata") if isinstance(memory.get("metadata"), dict) else {}),
                memory.get("valid_at"),
                memory.get("invalid_at"),
                memory.get("review_reason"),
                memory.get("extracted_by"),
                memory.get("created_at") or timestamp,
                memory.get("updated_at") or timestamp,
            ),
        )
        return {"memory_id": memory_id, "version": version, "event_id": event.get("event_id")}

    def _version_row(self, row: sqlite3.Row) -> dict[str, Any]:
        return {
            "memory_id": row["memory_id"],
            "version": row["version"],
            "event_id": row["event_id"],
            "event_type": row["event_type"],
            "project_id": row["project_id"],
            "timestamp": row["timestamp"],
            "title": row["title"],
            "body": row["body"],
            "type": row["type"],
            "status": row["status"],
            "normalized_claim": row["normalized_claim"],
            "confidence": row["confidence"],
            "importance": row["importance"],
            "source_refs": json.loads(row["source_refs_json"] or "[]"),
            "metadata": string_map(json.loads(row["metadata_json"] or "{}")),
            "valid_at": row["valid_at"],
            "invalid_at": row["invalid_at"],
            "review_reason": row["review_reason"],
            "extracted_by": row["extracted_by"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def _scope_row(self, row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"],
            "kind": row["kind"],
            "key": row["key"],
            "title": row["title"],
            "metadata": string_map(json.loads(row["metadata_json"] or "{}")),
            "primary": bool(row["primary_scope"]) if "primary_scope" in row.keys() else False,
        }

    def _event_row(self, row: sqlite3.Row) -> dict[str, Any]:
        return {
            "event_id": row["event_id"],
            "seq": row["seq"],
            "timestamp": row["timestamp"],
            "project_id": row["project_id"],
            "actor": json.loads(row["actor_json"] or "{}"),
            "event_type": row["event_type"],
            "memory_id": row["memory_id"],
            "before": json.loads(row["before_json"]) if row["before_json"] else None,
            "after": json.loads(row["after_json"]) if row["after_json"] else None,
            "delta": json.loads(row["delta_json"]) if row["delta_json"] else None,
            "source_refs": json.loads(row["source_refs_json"] or "[]"),
            "hash": row["hash"],
            "prev_hash": row["prev_hash"],
        }

    def _source_row(self, row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"],
            "project_id": row["project_id"],
            "kind": row["kind"],
            "title": row["title"],
            "uri": row["uri"],
            "path": row["path"],
            "content_hash": row["content_hash"],
            "excerpt": row["excerpt"],
            "metadata": string_map(json.loads(row["metadata_json"] or "{}")),
            "updated_at": row["updated_at"],
        }

    def _migrate(self) -> None:
        self.conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS memory_events (
                event_id TEXT PRIMARY KEY,
                seq INTEGER NOT NULL UNIQUE,
                timestamp REAL NOT NULL,
                project_id TEXT NOT NULL,
                actor_json TEXT NOT NULL,
                event_type TEXT NOT NULL,
                memory_id TEXT,
                before_json TEXT,
                after_json TEXT,
                delta_json TEXT,
                source_refs_json TEXT NOT NULL,
                reasoning_trace_id TEXT,
                request_id TEXT,
                hash TEXT NOT NULL,
                prev_hash TEXT
            );

            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                type TEXT NOT NULL,
                status TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                normalized_claim TEXT NOT NULL,
                confidence REAL NOT NULL,
                importance REAL NOT NULL,
                source_refs_json TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                valid_at REAL,
                invalid_at REAL,
                review_reason TEXT,
                extracted_by TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS memory_versions (
                memory_id TEXT NOT NULL,
                version INTEGER NOT NULL,
                event_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                project_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                type TEXT NOT NULL,
                status TEXT NOT NULL,
                normalized_claim TEXT NOT NULL,
                confidence REAL NOT NULL,
                importance REAL NOT NULL,
                source_refs_json TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                valid_at REAL,
                invalid_at REAL,
                review_reason TEXT,
                extracted_by TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY(memory_id, version)
            );

            CREATE TABLE IF NOT EXISTS scopes (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                key TEXT NOT NULL,
                title TEXT NOT NULL,
                metadata_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS memory_scopes (
                memory_id TEXT NOT NULL,
                scope_id TEXT NOT NULL,
                primary_scope INTEGER NOT NULL,
                PRIMARY KEY(memory_id, scope_id)
            );

            CREATE TABLE IF NOT EXISTS graph_edges (
                src_id TEXT NOT NULL,
                edge_type TEXT NOT NULL,
                dst_id TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                PRIMARY KEY(src_id, edge_type, dst_id)
            );

            CREATE TABLE IF NOT EXISTS sources (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                uri TEXT NOT NULL,
                path TEXT,
                commit_sha TEXT,
                content_hash TEXT,
                excerpt TEXT,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                updated_at REAL NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS episodes (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                body_excerpt TEXT NOT NULL,
                reference_time REAL,
                metadata_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS memory_episode_links (
                memory_id TEXT NOT NULL,
                episode_id TEXT NOT NULL,
                relation TEXT NOT NULL,
                PRIMARY KEY(memory_id, episode_id, relation)
            );

            CREATE TABLE IF NOT EXISTS modules (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                scope_id TEXT NOT NULL,
                title TEXT NOT NULL,
                classifier TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS projection_jobs (
                id TEXT PRIMARY KEY,
                adapter TEXT NOT NULL,
                memory_id TEXT NOT NULL,
                event_id TEXT NOT NULL,
                status TEXT NOT NULL,
                attempt_count INTEGER NOT NULL,
                last_error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS adapter_mappings (
                memory_id TEXT NOT NULL,
                adapter TEXT NOT NULL,
                adapter_id TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY(memory_id, adapter)
            );

            CREATE TABLE IF NOT EXISTS source_captures (
                source_id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                capture_version TEXT NOT NULL,
                status TEXT NOT NULL,
                created_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY(source_id, content_hash, capture_version)
            );

            CREATE TABLE IF NOT EXISTS legacy_memory_migrations (
                legacy_memory_id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                mem0_id TEXT,
                last_error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sync_cursors (
                source_id TEXT PRIMARY KEY,
                source_kind TEXT NOT NULL,
                cursor_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS run_traces (
                run_id TEXT PRIMARY KEY,
                project_id TEXT,
                timestamp REAL NOT NULL,
                request_json TEXT NOT NULL,
                repo_state_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS run_memory_usage (
                run_id TEXT NOT NULL,
                memory_id TEXT NOT NULL,
                usage_kind TEXT NOT NULL,
                rank INTEGER NOT NULL,
                score REAL NOT NULL,
                features_json TEXT NOT NULL
            );

            """
        )
        self._ensure_column("memories", "valid_at", "REAL")
        self._ensure_column("memories", "invalid_at", "REAL")
        self._ensure_column("memories", "review_reason", "TEXT")
        self._ensure_column("memories", "extracted_by", "TEXT")
        self._ensure_column("sources", "title", "TEXT NOT NULL DEFAULT ''")
        self._ensure_column("sources", "metadata_json", "TEXT NOT NULL DEFAULT '{}'")
        self._ensure_column("sources", "updated_at", "REAL NOT NULL DEFAULT 0")
        self.conn.execute("UPDATE sources SET title = COALESCE(NULLIF(title, ''), uri), updated_at = CASE WHEN updated_at = 0 THEN strftime('%s','now') ELSE updated_at END")
        self._retract_legacy_raw_transcript_memories()
        self._redact_legacy_raw_transcript_source_excerpts()
        self._retract_legacy_source_only_config_memories()
        self._retract_legacy_sensitive_config_memories()
        self._retract_legacy_noncanonical_mem0_memories()
        self._redact_legacy_sensitive_config_source_excerpts()
        self.conn.execute(f"PRAGMA user_version={self.schema_version}")
        self.conn.commit()

    def _retract_legacy_raw_transcript_memories(self) -> None:
        now = time.time()
        self.conn.execute(
            """
            UPDATE memories
            SET status = 'retracted',
                body = ?,
                invalid_at = COALESCE(invalid_at, ?),
                review_reason = COALESCE(review_reason, 'legacy_raw_transcript_ingest'),
                extracted_by = COALESCE(extracted_by, 'legacy_raw_transcript_ingest'),
                updated_at = ?
            WHERE (
                  source_refs_json LIKE '%"kind":"codex_transcript"%'
                  OR source_refs_json LIKE '%"kind":"claude_transcript"%'
              )
              AND (
                  body LIKE '{"timestamp":%'
                  OR body LIKE '%"type":"session_meta"%'
              )
            """,
            (RAW_TRANSCRIPT_REDACTION, now, now),
        )

    def _redact_legacy_raw_transcript_source_excerpts(self) -> None:
        now = time.time()
        self.conn.execute(
            """
            UPDATE sources
            SET excerpt = ?, updated_at = ?
            WHERE kind IN ('codex_transcript', 'claude_transcript')
              AND (
                  excerpt LIKE '{"timestamp":%'
                  OR excerpt LIKE '%"type":"session_meta"%'
                  OR excerpt LIKE '%"session_meta"%'
              )
            """,
            (RAW_TRANSCRIPT_REDACTION, now),
        )
        self.conn.execute(
            """
            UPDATE episodes
            SET body_excerpt = ?, updated_at = ?
            WHERE kind IN ('codex_transcript', 'claude_transcript')
              AND (
                  body_excerpt LIKE '{"timestamp":%'
                  OR body_excerpt LIKE '%"type":"session_meta"%'
                  OR body_excerpt LIKE '%"session_meta"%'
              )
            """,
            (RAW_TRANSCRIPT_REDACTION, now),
        )

    def _retract_legacy_source_only_config_memories(self) -> None:
        rows = self.conn.execute(
            """
            SELECT id, source_refs_json
            FROM memories
            WHERE status = 'active'
            """
        ).fetchall()
        memory_ids: list[str] = []
        for row in rows:
            try:
                refs = json.loads(row["source_refs_json"] or "[]")
            except json.JSONDecodeError:
                refs = []
            if any(isinstance(ref, dict) and ref.get("kind") in CONFIG_SOURCE_ONLY_KINDS for ref in refs):
                memory_ids.append(str(row["id"]))
        if not memory_ids:
            return
        now = time.time()
        placeholders = ",".join("?" for _ in memory_ids)
        self.conn.execute(
            f"""
            UPDATE memories
            SET status = 'retracted',
                body = ?,
                invalid_at = COALESCE(invalid_at, ?),
                review_reason = COALESCE(review_reason, 'source_only_config_ingest'),
                extracted_by = COALESCE(extracted_by, 'source_only_config_ingest'),
                updated_at = ?
            WHERE id IN ({placeholders})
            """,
            (SOURCE_ONLY_CONFIG_REDACTION, now, now, *memory_ids),
        )
        self.conn.execute(
            f"""
            UPDATE projection_jobs
            SET status = 'done',
                last_error = NULL,
                updated_at = ?
            WHERE status IN ('pending', 'failed')
              AND memory_id IN ({placeholders})
            """,
            (now, *memory_ids),
        )

    def _retract_legacy_sensitive_config_memories(self) -> None:
        rows = self.conn.execute(
            """
            SELECT id, title, source_refs_json
            FROM memories
            """
        ).fetchall()
        memory_ids: list[str] = []
        for row in rows:
            title = str(row["title"] or "")
            try:
                refs = json.loads(row["source_refs_json"] or "[]")
            except json.JSONDecodeError:
                refs = []
            if not any(isinstance(ref, dict) and ref.get("kind") in {"ai_config", "provider_config"} for ref in refs):
                continue
            locators = [title]
            for ref in refs:
                if not isinstance(ref, dict):
                    continue
                locators.extend(str(ref.get(key) or "") for key in ("uri", "path"))
            locator = "/".join(item.replace("\\", "/") for item in locators if item)
            if "settings.local.json" in locator or ".claude/settings.json" in locator or locator.endswith("settings.json"):
                memory_ids.append(str(row["id"]))
        if not memory_ids:
            return
        now = time.time()
        placeholders = ",".join("?" for _ in memory_ids)
        self.conn.execute(
            f"""
            UPDATE memories
            SET status = 'retracted',
                body = ?,
                invalid_at = COALESCE(invalid_at, ?),
                review_reason = COALESCE(review_reason, 'legacy_sensitive_config_ingest'),
                extracted_by = COALESCE(extracted_by, 'legacy_sensitive_config_ingest'),
                updated_at = ?
            WHERE id IN ({placeholders})
            """,
            (SENSITIVE_CONFIG_REDACTION, now, now, *memory_ids),
        )

    def _retract_legacy_noncanonical_mem0_memories(self) -> None:
        rows = self.conn.execute(
            """
            SELECT *
            FROM memories
            WHERE status = 'active'
              AND COALESCE(extracted_by, '') = 'mem0'
            """
        ).fetchall()
        memory_ids: list[str] = []
        for row in rows:
            memory = self._memory_row(row)
            if _canonical_memory_rejection_reason(memory) is not None:
                memory_ids.append(str(memory["id"]))
        if not memory_ids:
            return
        now = time.time()
        placeholders = ",".join("?" for _ in memory_ids)
        self.conn.execute(
            f"""
            UPDATE memories
            SET status = 'retracted',
                body = ?,
                invalid_at = COALESCE(invalid_at, ?),
                review_reason = COALESCE(review_reason, 'noncanonical_mem0_capture'),
                extracted_by = 'noncanonical_mem0_capture',
                updated_at = ?
            WHERE id IN ({placeholders})
            """,
            (NONCANONICAL_MEM0_REDACTION, now, now, *memory_ids),
        )

    def _redact_legacy_sensitive_config_source_excerpts(self) -> None:
        now = time.time()
        for row in self.conn.execute(
            """
            SELECT id, project_id, kind, title, uri, path, excerpt
            FROM sources
            WHERE kind IN ('ai_config', 'provider_config')
              AND (
                  title LIKE '%settings.local.json%'
                  OR title LIKE '%settings.json%'
                  OR uri LIKE '%.claude/settings.local.json%'
                  OR uri LIKE '%.claude/settings.json%'
                  OR path LIKE '%.claude/settings.local.json%'
                  OR path LIKE '%.claude/settings.json%'
              )
            """
        ).fetchall():
            summary = _sensitive_ai_config_summary(
                str(row["kind"]),
                str(row["excerpt"] or ""),
                project_id=str(row["project_id"] or ""),
                title=str(row["title"] or ""),
                path=str(row["path"] or ""),
                uri=str(row["uri"] or ""),
            ) or SENSITIVE_CONFIG_REDACTION
            self.conn.execute(
                "UPDATE sources SET excerpt = ?, updated_at = ? WHERE id = ?",
                (_excerpt(summary, 800), now, row["id"]),
            )
        for row in self.conn.execute(
            """
            SELECT episodes.id, episodes.project_id, episodes.kind, episodes.title,
                   episodes.body_excerpt, sources.path AS source_path, sources.uri AS source_uri
            FROM episodes
            LEFT JOIN sources ON sources.id = episodes.source_id
            WHERE episodes.kind IN ('ai_config', 'provider_config')
              AND (
                  episodes.title LIKE '%settings.local.json%'
                  OR episodes.title LIKE '%settings.json%'
                  OR sources.uri LIKE '%.claude/settings.local.json%'
                  OR sources.uri LIKE '%.claude/settings.json%'
                  OR sources.path LIKE '%.claude/settings.local.json%'
                  OR sources.path LIKE '%.claude/settings.json%'
              )
            """
        ).fetchall():
            summary = _sensitive_ai_config_summary(
                str(row["kind"]),
                str(row["body_excerpt"] or ""),
                project_id=str(row["project_id"] or ""),
                title=str(row["title"] or ""),
                path=str(row["source_path"] or ""),
                uri=str(row["source_uri"] or ""),
            ) or SENSITIVE_CONFIG_REDACTION
            self.conn.execute(
                "UPDATE episodes SET body_excerpt = ?, updated_at = ? WHERE id = ?",
                (_excerpt(summary, 1200), now, row["id"]),
            )

    def _ensure_column(self, table: str, column: str, definition: str) -> None:
        rows = self.conn.execute(f"PRAGMA table_info({table})").fetchall()
        if column not in {row["name"] for row in rows}:
            self.conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def _excerpt(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "\n..."


def _compact_exception(error: Exception) -> str:
    text = " ".join(str(error).split())
    return _excerpt(text or error.__class__.__name__, 320)


def _normalized_source_body(kind: str, body: str, *, project_id: str, title: str, path: str = "", uri: str = "") -> str:
    config_summary = _sensitive_ai_config_summary(kind, body, project_id=project_id, title=title, path=path, uri=uri)
    if config_summary is not None:
        return config_summary
    if kind not in TRANSCRIPT_SOURCE_KINDS or not _looks_like_raw_transcript(body):
        return body
    conversation = _conversation_from_transcript_jsonl(body)
    if not conversation:
        return RAW_TRANSCRIPT_REDACTION
    header = "\n".join(
        part
        for part in [
            f"Session: {title}" if title else "",
            f"Project: {project_id}" if project_id else "",
        ]
        if part
    )
    return f"{header}\n\n{conversation}" if header else conversation


def _sensitive_ai_config_summary(
    kind: str,
    body: str,
    *,
    project_id: str,
    title: str,
    path: str = "",
    uri: str = "",
) -> str | None:
    if not _looks_like_sensitive_ai_config(kind, body, title=title, path=path, uri=uri):
        return None
    allow: list[str] = []
    deny: list[str] = []
    env_keys: list[str] = []
    enabled_plugins = 0
    top_level_groups: list[str] = []
    try:
        decoded = json.loads(body)
    except json.JSONDecodeError:
        decoded = None
    if isinstance(decoded, dict):
        top_level_groups = sorted(
            str(key)
            for key in decoded.keys()
            if isinstance(key, str) and key not in {"env", "permissions"}
        )
        permissions = decoded.get("permissions")
        if isinstance(permissions, dict):
            allow = [str(item) for item in permissions.get("allow", []) if isinstance(item, str)]
            deny = [str(item) for item in permissions.get("deny", []) if isinstance(item, str)]
        env = decoded.get("env")
        if isinstance(env, dict):
            env_keys = [str(key) for key in env.keys() if isinstance(key, str)]
        plugins = decoded.get("enabledPlugins")
        if isinstance(plugins, dict):
            enabled_plugins = sum(1 for value in plugins.values() if bool(value))
    families = _permission_families(allow + deny)
    env_families = _env_families(env_keys)
    lines = [
        "Sensitive local AI configuration.",
        f"Configuration: {title or uri or path or 'settings'}",
    ]
    if project_id:
        lines.append(f"Project: {project_id}")
    if top_level_groups:
        lines.append(f"Setting groups: {', '.join(top_level_groups[:12])}")
    if enabled_plugins:
        lines.append(f"Enabled plugin entries: {enabled_plugins}")
    if env_keys:
        lines.append(f"Environment entries: {len(env_keys)}")
    if env_families:
        lines.append(f"Environment families: {', '.join(env_families)}")
    if allow:
        lines.append(f"Allowed permission entries: {len(allow)}")
    if deny:
        lines.append(f"Denied permission entries: {len(deny)}")
    if families:
        lines.append(f"Permission families: {', '.join(families)}")
    lines.append("Exact command patterns, environment values, and secret material are kept out of canonical memory surfaces.")
    return "\n".join(lines)


def _looks_like_sensitive_ai_config(kind: str, body: str, *, title: str = "", path: str = "", uri: str = "") -> bool:
    if kind not in {"ai_config", "provider_config"}:
        return False
    locator = "/".join(part.replace("\\", "/") for part in [title, path, uri] if part)
    if "settings.local.json" not in locator and ".claude/settings.json" not in locator and not locator.endswith("settings.json"):
        return False
    head = body.lstrip()[:4000]
    markers = [
        '"permissions"',
        '"allow"',
        '"deny"',
        '"env"',
        '"activeProvider"',
        '"enabledPlugins"',
        "ANTHROPIC_",
        "OPENAI_",
        "API_KEY",
        "AUTH_TOKEN",
        "BASE_URL",
    ]
    return any(marker in head for marker in markers)


def _permission_families(entries: list[str]) -> list[str]:
    families: set[str] = set()
    for entry in entries:
        token = entry.split("(", 1)[0].strip()
        if token:
            families.add(token)
    return sorted(families)


def _env_families(keys: list[str]) -> list[str]:
    families: set[str] = set()
    for key in keys:
        token = key.split("_", 1)[0].strip()
        if token:
            families.add(token)
    return sorted(families)


def _looks_like_raw_transcript(text: str) -> bool:
    head = text.lstrip()[:8000]
    return (
        head.startswith('{"timestamp":')
        or '"session_meta"' in head
        or '"type":"session_meta"' in head
        or '"type":"event_msg"' in head
        or ('"payload"' in head and ('"user_message"' in head or '"agent_message"' in head))
    )


def _conversation_from_transcript_jsonl(text: str) -> str:
    messages: list[str] = []
    for line in text.splitlines():
        if len(messages) >= 120:
            break
        stripped = line.strip()
        if not stripped:
            continue
        try:
            item = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        parsed = _message_from_transcript_line(item)
        if parsed is None:
            continue
        role, message = parsed
        messages.append(f"{role}: {_excerpt(message, 4000)}")
    return "\n\n".join(messages).strip()


def _message_from_transcript_line(item: Any) -> tuple[str, str] | None:
    if not isinstance(item, dict):
        return None
    payload = item.get("payload") if isinstance(item.get("payload"), dict) else {}
    line_type = str(item.get("type") or "")
    payload_type = str(payload.get("type") or "")
    message_obj = payload.get("message") if "message" in payload else item.get("message")

    role = _transcript_role(line_type, payload_type, payload, message_obj, item)
    if role is None:
        return None

    text = (
        _text_from_value(message_obj)
        or _text_from_value(payload.get("content"))
        or _text_from_value(payload.get("text"))
        or _text_from_value(item.get("content"))
        or _text_from_value(item.get("text"))
    ).strip()
    if not text:
        return None
    return role, text


def _transcript_role(
    line_type: str,
    payload_type: str,
    payload: dict[str, Any],
    message_obj: Any,
    item: dict[str, Any],
) -> str | None:
    candidates: list[str] = []
    if line_type == "event_msg":
        candidates.append(payload_type)
    else:
        candidates.append(line_type)
    if isinstance(message_obj, dict):
        candidates.extend(str(message_obj.get(key) or "") for key in ("role", "type"))
    candidates.extend(str(payload.get(key) or "") for key in ("role", "author"))
    candidates.extend(str(item.get(key) or "") for key in ("role", "author"))

    for candidate in candidates:
        normalized = candidate.strip().lower()
        if normalized in {"user", "human", "user_message"}:
            return "User"
        if normalized in {"assistant", "agent", "agent_message"}:
            return "Assistant"
    return None


def _text_from_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        parts = [_text_from_value(item) for item in value]
        return "\n".join(part for part in parts if part).strip()
    if isinstance(value, dict):
        value_type = str(value.get("type") or "").lower()
        if value_type and value_type not in {"text", "input_text", "output_text", "message"}:
            return ""
        for key in ("text", "content", "message"):
            text = _text_from_value(value.get(key))
            if text:
                return text
        return ""
    return str(value).strip()


def _canonical_memory_rejection_reason(memory: dict[str, Any]) -> str | None:
    if _source_only_config_memory(memory):
        return "source-only configuration is not a canonical memory"
    text = str(memory.get("body") or memory.get("memory") or memory.get("text") or "").strip()
    if not text:
        return "memory body is empty"
    metadata = _memory_metadata(memory)
    inferred = str(metadata.get("infer") or "").strip().lower() in {"1", "true", "yes", "on"}
    if _looks_like_raw_source_chunk(text):
        return "raw source chunk was returned instead of an extracted memory"
    if _looks_like_raw_json_payload(text):
        return "raw JSON/config payload was returned instead of an extracted memory"
    if inferred and len(text) > 2400:
        return "inferred memory is too large to be canonical"
    return None


def _source_only_config_memory(memory: dict[str, Any]) -> bool:
    refs = _memory_source_refs(memory)
    if any(str(ref.get("kind") or "") in CONFIG_SOURCE_ONLY_KINDS for ref in refs if isinstance(ref, dict)):
        return True
    metadata = _memory_metadata(memory)
    source_kind = str(metadata.get("source_kind") or metadata.get("kind") or "").strip()
    if source_kind in CONFIG_SOURCE_ONLY_KINDS:
        return True
    title = str(memory.get("title") or metadata.get("title") or "")
    locator_parts = [
        title,
        str(metadata.get("source_path") or ""),
        str(metadata.get("source_uri") or ""),
    ]
    for ref in refs:
        if isinstance(ref, dict):
            locator_parts.extend(str(ref.get(key) or "") for key in ("uri", "path"))
    locator = "/".join(part.replace("\\", "/") for part in locator_parts if part)
    if source_kind in {"ai_config", "provider_config"} and (
        "settings.local.json" in locator
        or ".claude/settings.json" in locator
        or locator.endswith("settings.json")
    ):
        return True
    return False


def _memory_source_refs(memory: dict[str, Any]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    raw_refs = memory.get("source_refs")
    if isinstance(raw_refs, list):
        refs.extend(ref for ref in raw_refs if isinstance(ref, dict))
    metadata_refs = _json_dict_list(_memory_metadata(memory).get("source_refs_json"))
    refs.extend(metadata_refs)
    return refs


def _memory_metadata(memory: dict[str, Any]) -> dict[str, Any]:
    metadata = memory.get("metadata")
    return metadata if isinstance(metadata, dict) else {}


def _json_dict_list(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if not isinstance(value, str) or not value.strip():
        return []
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return []
    return [item for item in decoded if isinstance(item, dict)] if isinstance(decoded, list) else []


def _looks_like_raw_source_chunk(text: str) -> bool:
    head = "\n".join(text.lstrip().splitlines()[:8])
    return "Project:" in head and "Source kind:" in head and "Source path:" in head


def _looks_like_raw_json_payload(text: str) -> bool:
    stripped = text.lstrip()
    if not stripped.startswith(("{", "[")):
        return False
    head = stripped[:4000]
    markers = [
        '"permissions"',
        '"allow"',
        '"deny"',
        '"env"',
        '"session_meta"',
        '"base_instructions"',
        '"activeProvider"',
        '"enabledPlugins"',
    ]
    return any(marker in head for marker in markers)


def _source_chunk_header(source: dict[str, Any], section: str) -> str:
    lines = [
        f"Project: {source.get('project_id') or 'unknown'}",
        f"Source kind: {source.get('kind') or 'source'}",
        f"Source path: {source.get('path') or source.get('uri') or ''}",
    ]
    if section:
        lines.append(f"Section: {section}")
    return "\n".join(lines)


def _markdown_sections(text: str, *, limit: int = 8_000) -> list[dict[str, Any]]:
    lines = text.splitlines()
    sections: list[dict[str, Any]] = []
    current_title = "Document"
    current_start = 1
    current_lines: list[str] = []
    heading_stack: list[tuple[int, str]] = []
    in_fence = False

    def flush(end_line: int) -> None:
        body = "\n".join(current_lines).strip()
        if not body:
            return
        for index, chunk in enumerate(_paragraph_chunks(body, limit=limit), start=1):
            sections.append(
                {
                    "title": current_title if index == 1 else f"{current_title} (part {index})",
                    "body": chunk,
                    "line_start": current_start,
                    "line_end": end_line,
                }
            )

    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
        heading_match = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", stripped) if not in_fence else None
        if heading_match is not None:
            level = len(heading_match.group(1))
            heading = heading_match.group(2).strip()
            if heading:
                flush(line_number - 1)
                while heading_stack and heading_stack[-1][0] >= level:
                    heading_stack.pop()
                heading_stack.append((level, heading))
                current_title = " > ".join(title for _, title in heading_stack) or heading
                current_start = line_number
                current_lines = [line]
                continue
        current_lines.append(line)
    flush(len(lines))
    if sections:
        return sections
    body = text.strip()
    return [
        {
            "title": "Document" if index == 1 else f"Document ({index})",
            "body": chunk,
            "line_start": 1,
            "line_end": len(lines),
        }
        for index, chunk in enumerate(_paragraph_chunks(body, limit=limit), start=1)
    ]


def _paragraph_chunks(text: str, *, limit: int) -> list[str]:
    paragraphs = [part.strip() for part in text.split("\n\n") if part.strip()]
    if not paragraphs:
        return []
    chunks: list[str] = []
    current = ""
    for paragraph in paragraphs:
        if len(paragraph) > limit:
            if current:
                chunks.append(current.strip())
                current = ""
            for start in range(0, len(paragraph), limit):
                chunks.append(paragraph[start : start + limit].strip())
            continue
        candidate = f"{current}\n\n{paragraph}".strip() if current else paragraph
        if len(candidate) > limit and current:
            chunks.append(current.strip())
            current = paragraph
        else:
            current = candidate
    if current:
        chunks.append(current.strip())
    return chunks


def _memory_type_for_source(kind: str) -> str:
    if kind in {"AGENTS.md", "CLAUDE.md", "repo_config"}:
        return "convention"
    if kind in {"codex_transcript", "claude_transcript", "terminal_capture"}:
        return "workflow"
    return "fact"


def _bounded_int(value: object, *, default: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(minimum, min(parsed, maximum))


def _bool_value(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _float_or_none(value: object) -> float | None:
    try:
        return float(value) if value is not None and value != "" else None
    except (TypeError, ValueError):
        if isinstance(value, str):
            try:
                return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
            except ValueError:
                return None
        return None


def _is_valid_at(valid_at: object, invalid_at: object, as_of: float | None) -> bool:
    if as_of is None:
        return True
    start = _float_or_none(valid_at)
    end = _float_or_none(invalid_at)
    if start is not None and start > as_of:
        return False
    if end is not None and end <= as_of:
        return False
    return True


def _module_name(parts: list[str], project_id: str) -> str | None:
    ignored = {
        "Users",
        "private",
        "tmp",
        "var",
        "folders",
        "Library",
        "Application Support",
        "Claude Stats",
        "Memory",
    }
    preferred = {"ClaudeStats", "MemorySidecar", "ClaudeStatsMemoryCLI", "ClaudeStatsTests", "scripts", "ThirdParty"}
    for part in parts:
        if part in preferred:
            return part
    project_leaf = Path(project_id).name if "/" in project_id else project_id
    for index, part in enumerate(parts):
        if part == project_leaf and index + 1 < len(parts):
            return parts[index + 1]
    for part in parts:
        if part not in ignored and not part.startswith(".") and not part.endswith(".jsonl"):
            return part
    return None
