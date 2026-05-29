from __future__ import annotations

import hashlib
import json
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

from .adapters import MemoryAdapters, build_adapters
from .models import DETERMINISTIC_SOURCE_KINDS, MEMORY_STATUSES, MemoryInput, Scope, string_map


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


class MemoryStore:
    schema_version = 2

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
        memories = self.conn.execute("SELECT COUNT(*) AS count FROM memories").fetchone()
        pending = self.conn.execute("SELECT COUNT(*) AS count FROM projection_jobs WHERE status = 'pending'").fetchone()
        failed = self.conn.execute("SELECT COUNT(*) AS count FROM projection_jobs WHERE status = 'failed'").fetchone()
        proposals = self.conn.execute("SELECT COUNT(*) AS count FROM memories WHERE status = 'proposed'").fetchone()
        modules = self.conn.execute("SELECT COUNT(*) AS count FROM modules").fetchone()
        return {
            "status": "ok",
            "store": str(self.db_path),
            "event_count": int(row["count"]),
            "memory_count": int(memories["count"]),
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
            self.conn.execute("UPDATE memories SET status = ?, updated_at = ? WHERE id = ?", (status, timestamp, memory_id))
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
        result["drained"] = self.drain_projection_jobs(limit=20)
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
            "title", "body", "type", "status", "normalized_claim", "confidence", "importance", "source_refs", "metadata", "scope", "scopes"
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
            SELECT m.*, COUNT(ms.memory_id) AS memory_count, MAX(mem.updated_at) AS updated_at
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

    def ingest_source(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = str(payload.get("project_id") or "unknown")
        body = str(payload.get("body") or payload.get("text") or "").strip()
        title = str(payload.get("title") or payload.get("path") or payload.get("uri") or "Source").strip()[:160]
        kind = str(payload.get("kind") or "source")
        path = str(payload.get("path") or "")
        uri = str(payload.get("uri") or path or payload.get("id") or title)
        content_hash = str(payload.get("content_hash") or hashlib.sha256(body.encode("utf-8")).hexdigest())
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
        existing = self.conn.execute("SELECT content_hash FROM sources WHERE id = ?", (source_id,)).fetchone()
        if existing and existing["content_hash"] == content_hash:
            return {"status": "skipped", "source": source, "created": [], "proposed": []}

        observed = self.append_event(
            {
                "event_id": f"event:{source_id}:observed:{content_hash[:12]}",
                "project_id": project_id,
                "event_type": "memory.source_observed",
                "actor": payload.get("actor") if isinstance(payload.get("actor"), dict) else {"kind": "sync"},
                "after": source,
                "source_refs": [{"kind": kind, "uri": uri, "path": path, "content_hash": content_hash}],
            }
        )
        created: list[dict[str, Any]] = []
        proposed: list[dict[str, Any]] = []
        if body and kind in DETERMINISTIC_SOURCE_KINDS:
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
                        "source_refs": [{"kind": kind, "uri": uri, "path": path, "content_hash": content_hash}],
                        "metadata": string_map(source["metadata"] | {"source_id": source_id, "source_hash": content_hash}),
                    },
                    "source_refs": [{"kind": kind, "uri": uri, "path": path, "content_hash": content_hash}],
                }
            )
            if "memory" in memory:
                created.append(memory["memory"])
        if bool(payload.get("infer")) and body:
            for candidate in self.adapters.infer_memories(source | {"scope": self._source_scope(project_id, path=path, uri=uri).to_json()}):
                proposed_event = self.propose_memory(candidate)
                if "memory" in proposed_event:
                    proposed.append(proposed_event["memory"])
        return {"status": "ok", "event": observed, "source": source, "created": created, "proposed": proposed}

    def reindex(self, *, project_id: str | None = None) -> dict[str, Any]:
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
        drained = self.drain_projection_jobs(limit=max(100, enqueued))
        return {"enqueued": enqueued, "drained": drained}

    def drain_projection_jobs(self, *, limit: int = 100) -> dict[str, Any]:
        rows = self.conn.execute(
            """
            SELECT * FROM projection_jobs
            WHERE status IN ('pending', 'failed')
            ORDER BY updated_at ASC
            LIMIT ?
            """,
            (limit,),
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
        return {"delivered": delivered, "failed": failed, "remaining": self._projection_count("pending") + self._projection_count("failed")}

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

    def context_pack(self, query: str, *, project_id: str | None = None, limit: int = 10) -> dict[str, Any]:
        search = self.search(query, project_id=project_id, limit=limit)
        grouped: dict[str, list[dict[str, Any]]] = {
            "rules": [],
            "facts": [],
            "risks": [],
            "commands": [],
            "decisions": [],
        }
        for result in search["results"]:
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
        return {"query": query, "trace_id": search["trace_id"], "context": grouped}

    def projects(self) -> list[dict[str, Any]]:
        rows = self.conn.execute(
            """
            SELECT project_id, COUNT(*) AS memory_count, MAX(updated_at) AS updated_at
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
                "metadata": json.loads(memory["metadata_json"] or "{}"),
            }
            for link in self.conn.execute("SELECT scope_id, primary_scope FROM memory_scopes WHERE memory_id = ?", (memory["id"],)):
                edges.append({"source": memory_node, "target": link["scope_id"], "kind": "SCOPED_TO", "primary": bool(link["primary_scope"])})

        for event in self.conn.execute("SELECT event_id, event_type, memory_id, seq FROM memory_events WHERE project_id = ? ORDER BY seq", (project_id,)):
            event_node = f"event:{event['event_id']}"
            nodes[event_node] = {"id": event_node, "kind": "event", "title": event["event_type"], "seq": event["seq"]}
            if event["memory_id"]:
                edges.append({"source": event_node, "target": f"memory:{event['memory_id']}", "kind": "AFFECTS"})

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

    def event(self, event_id: str) -> dict[str, Any]:
        row = self.conn.execute("SELECT * FROM memory_events WHERE event_id = ?", (event_id,)).fetchone()
        if row is None:
            raise KeyError(event_id)
        return self._event_row(row)

    def _projection_count(self, status: str) -> int:
        row = self.conn.execute("SELECT COUNT(*) AS count FROM projection_jobs WHERE status = ?", (status,)).fetchone()
        return int(row["count"])

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
        body = str(payload.get("body") or payload.get("text") or "")
        content_hash = str(payload.get("content_hash") or hashlib.sha256(body.encode("utf-8")).hexdigest())
        source_id = str(payload.get("id") or "src:" + hashlib.sha256(canonical_json({
            "project_id": project_id,
            "kind": payload.get("kind"),
            "uri": payload.get("uri") or payload.get("path"),
            "hash": content_hash,
        }).encode("utf-8")).hexdigest()[:24])
        self.conn.execute(
            """
            INSERT INTO sources (
                id, project_id, kind, uri, path, commit_sha, content_hash, excerpt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                uri = excluded.uri,
                path = excluded.path,
                commit_sha = excluded.commit_sha,
                content_hash = excluded.content_hash,
                excerpt = excluded.excerpt
            """,
            (
                source_id,
                project_id,
                str(payload.get("kind") or "source"),
                str(payload.get("uri") or payload.get("path") or source_id),
                payload.get("path"),
                payload.get("commit_sha"),
                content_hash,
                _excerpt(body, 800),
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
                confidence, importance, source_refs_json, metadata_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                now,
                now,
            ),
        )
        self.conn.execute("DELETE FROM memory_scopes WHERE memory_id = ?", (memory_id,))
        for index, scope in enumerate(memory.scopes):
            self._upsert_scope(memory.project_id, scope)
            self.conn.execute(
                "INSERT OR REPLACE INTO memory_scopes (memory_id, scope_id, primary_scope) VALUES (?, ?, ?)",
                (memory_id, scope.id, 1 if index == 0 else 0),
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
                uri TEXT NOT NULL,
                path TEXT,
                commit_sha TEXT,
                content_hash TEXT,
                excerpt TEXT
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
        self.conn.execute(f"PRAGMA user_version={self.schema_version}")
        self.conn.commit()


def _excerpt(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "\n..."


def _memory_type_for_source(kind: str) -> str:
    if kind in {"AGENTS.md", "CLAUDE.md", "ai_config", "repo_config"}:
        return "convention"
    if kind in {"codex_transcript", "claude_transcript", "terminal_capture"}:
        return "workflow"
    return "fact"


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
