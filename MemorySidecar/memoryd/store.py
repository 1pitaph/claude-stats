from __future__ import annotations

import hashlib
import json
import sqlite3
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from .adapters import MemoryAdapters, build_adapters
from .models import DETERMINISTIC_SOURCE_KINDS, MEMORY_STATUSES, MemoryInput, Scope, string_map


TRANSCRIPT_SOURCE_KINDS = {"codex_transcript", "claude_transcript"}
CONFIG_SOURCE_ONLY_KINDS = {"ai_config", "provider_config", "plugin_config", "plan"}
REINFER_SOURCE_KINDS = TRANSCRIPT_SOURCE_KINDS | {"terminal_capture", "manual", "user_instruction"}
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


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


class MemoryStore:
    schema_version = 9
    api_version = 11

    def __init__(self, root: Path, adapters: MemoryAdapters | None = None):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.db_path = self.root / "code-memory.sqlite3"
        self.adapters = adapters if adapters is not None else build_adapters(root)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self.conn.execute("PRAGMA busy_timeout=2500")
        self._migrate()

    def close(self) -> None:
        self.conn.close()

    def health(self) -> dict[str, Any]:
        row = self.conn.execute("SELECT COUNT(*) AS count FROM memory_events").fetchone()
        active_memories = self.conn.execute("SELECT COUNT(*) AS count FROM memories WHERE status = 'active'").fetchone()
        total_memories = self.conn.execute("SELECT COUNT(*) AS count FROM memories").fetchone()
        pending = self.conn.execute("SELECT COUNT(*) AS count FROM projection_jobs WHERE status = 'pending'").fetchone()
        failed = self.conn.execute("SELECT COUNT(*) AS count FROM projection_jobs WHERE status = 'failed'").fetchone()
        proposals = self.conn.execute("SELECT COUNT(*) AS count FROM memories WHERE status = 'proposed'").fetchone()
        modules = self.conn.execute("SELECT COUNT(*) AS count FROM modules").fetchone()
        return {
            "status": "ok",
            "api_version": self.api_version,
            "store": str(self.db_path),
            "event_count": int(row["count"]),
            "memory_count": int(active_memories["count"]),
            "total_memory_count": int(total_memories["count"]),
            "proposal_count": int(proposals["count"]),
            "module_count": int(modules["count"]),
            "projection_pending": int(pending["count"]),
            "projection_failed": int(failed["count"]),
            "adapters": self.adapters.health()
            | {
                "projection_pending": str(int(pending["count"])),
                "projection_failed": str(int(failed["count"])),
            },
        }

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
        if memory:
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
        row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
        if row is None:
            raise KeyError(memory_id)
        after = self._memory_row(row)
        after["status"] = "active"
        result = self.append_event(
            {
                "project_id": after["project_id"],
                "event_type": "memory.accepted",
                "actor": actor or {"kind": "human"},
                "memory_id": memory_id,
                "before": self._memory_row(row),
                "after": after,
                "source_refs": after.get("source_refs", []),
            }
        )
        result["drained"] = self.drain_projection_jobs(limit=5)
        return result

    def reject_memory(self, memory_id: str, actor: dict[str, Any] | None = None) -> dict[str, Any]:
        row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
        if row is None:
            raise KeyError(memory_id)
        return self.append_event(
            {
                "project_id": row["project_id"],
                "event_type": "memory.retracted",
                "actor": actor or {"kind": "human"},
                "memory_id": memory_id,
                "before": self._memory_row(row),
                "source_refs": json.loads(row["source_refs_json"] or "[]"),
            }
        )

    def deprecate_memory(self, memory_id: str, actor: dict[str, Any] | None = None) -> dict[str, Any]:
        row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
        if row is None:
            raise KeyError(memory_id)
        return self.append_event(
            {
                "project_id": row["project_id"],
                "event_type": "memory.deprecated",
                "actor": actor or {"kind": "human"},
                "memory_id": memory_id,
                "before": self._memory_row(row),
                "source_refs": json.loads(row["source_refs_json"] or "[]"),
            }
        )

    def update_memory(self, memory_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
        if row is None:
            raise KeyError(memory_id)
        before = self._memory_row(row)
        after = before | {key: value for key, value in payload.items() if key in {
            "title", "body", "type", "status", "normalized_claim", "confidence", "importance",
            "source_refs", "metadata", "scope", "scopes", "valid_at", "invalid_at",
            "review_reason", "extracted_by",
        }}
        after["id"] = memory_id
        after["project_id"] = before["project_id"]
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
        params: list[Any] = ["proposed"]
        where = ["status = ?"]
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
        return {"memories": [self._memory_row(row) for row in rows]}

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
                COUNT(CASE WHEN mem.status = 'active' THEN ms.memory_id END) AS memory_count,
                COUNT(ms.memory_id) AS total_memory_count,
                MAX(CASE WHEN mem.status = 'active' THEN mem.updated_at END) AS updated_at
            FROM modules m
            LEFT JOIN memory_scopes ms ON ms.scope_id = m.scope_id
            LEFT JOIN memories mem ON mem.id = ms.memory_id
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
        params: list[Any] = []
        where: list[str] = []
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
        return {"memories": [self._memory_row(row) for row in rows]}

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
        if existing and existing["content_hash"] == content_hash:
            return {"status": "skipped", "source": source, "created": [], "proposed": [], "inference_errors": []}

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
        if (
            body
            and kind in DETERMINISTIC_SOURCE_KINDS
            and kind not in CONFIG_SOURCE_ONLY_KINDS
            and not _looks_like_sensitive_ai_config(kind, raw_body, title=title, path=path, uri=uri)
        ):
            memory = self.append_event(
                {
                    "project_id": project_id,
                    "event_type": "memory.observed",
                    "actor": {"kind": "sync", "id": "claude-stats-memory"},
                    "after": {
                        "project_id": project_id,
                        "title": title,
                        "body": _excerpt(body, 6000),
                        "type": _memory_type_for_source(kind),
                        "status": "active",
                        "scope": self._source_scope(project_id, path=path, uri=uri).to_json(),
                        "source_refs": [{"kind": kind, "uri": uri, "path": path, "content_hash": content_hash, "source_id": source_id, "episode_id": f"episode:{source_id}"}],
                        "metadata": string_map(source["metadata"] | {"source_id": source_id, "source_hash": content_hash}),
                    },
                    "source_refs": [{"kind": kind, "uri": uri, "path": path, "content_hash": content_hash, "source_id": source_id, "episode_id": f"episode:{source_id}"}],
                }
            )
            if "memory" in memory:
                created.append(memory["memory"])
        if bool(payload.get("infer")) and body and kind not in CONFIG_SOURCE_ONLY_KINDS:
            candidates, inference_errors = self._infer_memory_candidates(
                source | {"scope": self._source_scope(project_id, path=path, uri=uri).to_json()}
            )
            for candidate in candidates:
                proposed_event = self.propose_memory(candidate | {"status": "proposed"})
                if "memory" in proposed_event:
                    proposed.append(proposed_event["memory"])
        return {"status": "ok", "event": observed, "source": source, "created": created, "proposed": proposed, "inference_errors": inference_errors}

    def reinfer_sources(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = payload.get("project_id") if isinstance(payload.get("project_id"), str) else None
        source_id = payload.get("source_id") if isinstance(payload.get("source_id"), str) else None
        limit = _bounded_int(payload.get("limit"), default=50, minimum=1, maximum=200)
        kinds = sorted(REINFER_SOURCE_KINDS)
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
        proposed = 0
        skipped = 0
        errors: list[dict[str, str]] = []
        for row in rows:
            source = self._source_row(row)
            body = self._reinfer_source_body(source)
            if not body:
                skipped += 1
                continue
            inference_source = source | {
                "body": body,
                "scope": self._source_scope(
                    str(source["project_id"]),
                    path=str(source.get("path") or ""),
                    uri=str(source.get("uri") or ""),
                ).to_json(),
            }
            attempted += 1
            candidates, inference_errors = self._infer_memory_candidates(inference_source)
            for error in inference_errors:
                errors.append(error | {"source_id": str(source["id"])})
            if not candidates:
                continue
            for candidate in candidates:
                proposed_event = self.propose_memory(candidate | {"status": "proposed"})
                if "memory" in proposed_event:
                    proposed += 1

        return {
            "status": "ok",
            "scanned": len(rows),
            "attempted": attempted,
            "proposed": proposed,
            "skipped": skipped,
            "errors": errors,
        }

    def reindex(self, *, project_id: str | None = None, drain: bool = False, drain_limit: int | None = None) -> dict[str, Any]:
        params: list[Any] = []
        where = ["status = 'active'"]
        if project_id:
            where.append("project_id = ?")
            params.append(project_id)
        rows = self.conn.execute(f"SELECT * FROM memories WHERE {' AND '.join(where)}", params).fetchall()
        enqueued = 0
        for row in rows:
            memory = self._memory_row(row)
            event_id = memory.get("metadata", {}).get("last_event_id")
            event = self.event(event_id) if event_id else {"event_id": f"reindex:{memory['id']}", "timestamp": time.time()}
            enqueued += self._enqueue_projection_jobs(memory, event, force=True)
        self.conn.commit()
        result = {"enqueued": enqueued, "remaining": self._projection_count("pending") + self._projection_count("failed")}
        if drain:
            result["drained"] = self.drain_projection_jobs(limit=drain_limit or min(max(1, enqueued), 10))
        return result

    def drain_projection_jobs(self, *, limit: int = 10, include_failed: bool = False) -> dict[str, Any]:
        blockers = self._projection_adapter_blockers()
        if blockers:
            pending_remaining = self._projection_count("pending")
            failed_total = self._projection_count("failed")
            return {
                "delivered": 0,
                "failed": 0,
                "remaining": pending_remaining + failed_total,
                "pending": pending_remaining,
                "failed_total": failed_total,
                "skipped": True,
                "message": "Projection drain skipped because adapters are unavailable.",
                "blockers": blockers,
            }

        statuses = ["pending"]
        if include_failed:
            statuses.append("failed")
        placeholders = ",".join("?" for _ in statuses)
        rows = self.conn.execute(
            f"""
            SELECT * FROM projection_jobs
            WHERE status IN ({placeholders})
            ORDER BY updated_at ASC
            LIMIT ?
            """,
            (*statuses, max(1, min(limit, 25))),
        ).fetchall()
        delivered = 0
        failed = 0
        for job in rows:
            memory_row = self.conn.execute("SELECT * FROM memories WHERE id = ?", (job["memory_id"],)).fetchone()
            event_row = self.conn.execute("SELECT * FROM memory_events WHERE event_id = ?", (job["event_id"],)).fetchone()
            if memory_row is None:
                continue
            memory = self._memory_row(memory_row)
            if memory.get("status") != "active":
                self.conn.execute(
                    "UPDATE projection_jobs SET status = 'done', last_error = NULL, updated_at = ?, attempt_count = attempt_count + 1 WHERE id = ?",
                    (time.time(), job["id"]),
                )
                continue
            event = self._event_row(event_row) if event_row is not None else {"event_id": job["event_id"], "timestamp": time.time()}
            status = self.adapters.index_memory(memory, event, adapter_name=job["adapter"])
            detail = status.get(job["adapter"], "")
            now = time.time()
            if detail.startswith("ok"):
                adapter_id = detail.split(":", 1)[1] if ":" in detail else ""
                self.conn.execute(
                    "UPDATE projection_jobs SET status = 'done', last_error = NULL, updated_at = ?, attempt_count = attempt_count + 1 WHERE id = ?",
                    (now, job["id"]),
                )
                self.conn.execute(
                    """
                    INSERT INTO adapter_mappings (memory_id, adapter, adapter_id, metadata_json, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(memory_id, adapter) DO UPDATE SET
                        adapter_id = excluded.adapter_id,
                        metadata_json = excluded.metadata_json,
                        updated_at = excluded.updated_at
                    """,
                    (memory["id"], job["adapter"], adapter_id, canonical_json({"event_id": event.get("event_id")}), now),
                )
                delivered += 1
            else:
                self.conn.execute(
                    "UPDATE projection_jobs SET status = 'failed', last_error = ?, updated_at = ?, attempt_count = attempt_count + 1 WHERE id = ?",
                    (detail or "adapter unavailable", now, job["id"]),
                )
                failed += 1
        self.conn.commit()
        pending_remaining = self._projection_count("pending")
        failed_total = self._projection_count("failed")
        return {
            "delivered": delivered,
            "failed": failed,
            "remaining": pending_remaining + failed_total,
            "pending": pending_remaining,
            "failed_total": failed_total,
            "skipped": False,
        }

    def search(self, query: str, *, project_id: str | None = None, limit: int = 20, status: str | None = "active") -> dict[str, Any]:
        like = f"%{query.lower()}%"
        params: list[Any] = [like, like]
        where = ["(lower(title) LIKE ? OR lower(body) LIKE ?)"]
        if project_id:
            where.append("project_id = ?")
            params.append(project_id)
        if status:
            where.append("status = ?")
            params.append(status)
        params.append(limit)
        rows = self.conn.execute(
            f"""
            SELECT * FROM memories
            WHERE {' AND '.join(where)}
            ORDER BY importance DESC, confidence DESC, updated_at DESC
            LIMIT ?
            """,
            params,
        ).fetchall()
        results = []
        for rank, row in enumerate(rows, start=1):
            memory = self._memory_row(row)
            score = self._lexical_score(query, memory)
            results.append(
                {
                    "rank": rank,
                    "score": score,
                    "memory": memory,
                    "match_kind": "text",
                    "evidence": [{"adapter": "sqlite", "score": score, "detail": "title/body lexical match"}],
                }
            )
        seen = {result["memory"]["id"] for result in results}
        for result in self.adapters.search(query, project_id=project_id, limit=limit):
            memory = result.get("memory") if isinstance(result, dict) else None
            if not isinstance(memory, dict):
                continue
            memory_id = memory.get("id")
            if not memory_id or memory_id in seen:
                continue
            canonical = self.conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
            if canonical is None:
                continue
            canonical_memory = self._memory_row(canonical)
            if status and canonical_memory["status"] != status:
                continue
            if project_id and canonical_memory["project_id"] != project_id:
                continue
            result = dict(result)
            result["memory"] = canonical_memory
            seen.add(memory_id)
            results.append(result)
            if len(results) >= limit:
                break
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
            GROUP BY project_id
            ORDER BY updated_at DESC
            """
        ).fetchall()
        return [dict(row) for row in rows]

    def graph(self, project_id: str) -> dict[str, Any]:
        nodes: dict[str, dict[str, Any]] = {}
        edges: list[dict[str, Any]] = []
        nodes[f"project:{project_id}"] = {"id": f"project:{project_id}", "kind": "project", "title": project_id}

        for scope in self.conn.execute("SELECT * FROM scopes WHERE project_id = ?", (project_id,)):
            nodes[scope["id"]] = {"id": scope["id"], "kind": scope["kind"], "title": scope["title"], "metadata": json.loads(scope["metadata_json"] or "{}")}
            edges.append({"source": f"project:{project_id}", "target": scope["id"], "kind": "HAS_SCOPE"})

        for memory in self.conn.execute("SELECT * FROM memories WHERE project_id = ?", (project_id,)):
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
        row = self.conn.execute("SELECT COUNT(*) AS count FROM projection_jobs WHERE status = ?", (status,)).fetchone()
        return int(row["count"])

    def _projection_adapter_blockers(self) -> dict[str, str]:
        names = set(self.adapters.names())
        if not names:
            return {}
        health = self.adapters.health()
        blockers: dict[str, str] = {}
        for name in sorted(names):
            status = str(health.get(name, "unavailable")).strip()
            normalized = status.lower()
            if (
                "endpoint unavailable" in normalized
                or normalized.startswith("unavailable")
                or normalized.startswith("disabled")
                or normalized.startswith("error")
            ):
                blockers[name] = status
        return blockers

    def _enqueue_projection_jobs(self, memory: dict[str, Any], event: dict[str, Any], *, force: bool = False) -> int:
        if memory.get("status") != "active":
            return 0
        adapters = self.adapters.names()
        now = time.time()
        count = 0
        for adapter in adapters:
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
