from __future__ import annotations

import hashlib
import json
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

from .models import DETERMINISTIC_SOURCE_KINDS, MEMORY_STATUSES, MemoryInput, Scope


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


class MemoryStore:
    schema_version = 1

    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.db_path = self.root / "code-memory.sqlite3"
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
        return {
            "status": "ok",
            "store": str(self.db_path),
            "event_count": int(row["count"]),
            "memory_count": int(memories["count"]),
            "adapters": {
                "mem0": "disabled",
                "graphiti": "disabled",
                "graph_backend": "kuzu",
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
                memory = self._upsert_memory(MemoryInput.from_json(memory_payload, project_id=project_id, default_status=default_status), event_id=event_id)
        elif event_type in {"memory.deprecated", "memory.retracted", "memory.superseded", "memory.conflict_detected"} and memory_id:
            status = {
                "memory.deprecated": "deprecated",
                "memory.retracted": "retracted",
                "memory.superseded": "superseded",
                "memory.conflict_detected": "conflicted",
            }[event_type]
            self.conn.execute("UPDATE memories SET status = ?, updated_at = ? WHERE id = ?", (status, timestamp, memory_id))

        self.conn.commit()
        return self.event(event_id) | ({"memory": memory} if memory else {})

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
        return self.append_event(
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
            results.append({"rank": rank, "score": score, "memory": memory, "match_kind": "text"})
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
            nodes[memory_node] = {"id": memory_node, "kind": "memory", "title": memory["title"], "type": memory["type"], "status": memory["status"]}
            for link in self.conn.execute("SELECT scope_id, primary_scope FROM memory_scopes WHERE memory_id = ?", (memory["id"],)):
                edges.append({"source": memory_node, "target": link["scope_id"], "kind": "SCOPED_TO", "primary": bool(link["primary_scope"])})

        for event in self.conn.execute("SELECT event_id, event_type, memory_id, seq FROM memory_events WHERE project_id = ? ORDER BY seq", (project_id,)):
            event_node = f"event:{event['event_id']}"
            nodes[event_node] = {"id": event_node, "kind": "event", "title": event["event_type"], "seq": event["seq"]}
            if event["memory_id"]:
                edges.append({"source": event_node, "target": f"memory:{event['memory_id']}", "kind": "AFFECTS"})

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

    def legacy_import(self, payload: dict[str, Any]) -> dict[str, Any]:
        project_id = str(payload.get("project_id") or "legacy")
        records = payload.get("records") if isinstance(payload.get("records"), list) else []
        imported = 0
        skipped = 0
        for record in records:
            if not isinstance(record, dict):
                continue
            source_ref = str(record.get("ref") or record.get("id") or uuid.uuid4())
            exists = self.conn.execute("SELECT 1 FROM legacy_imports WHERE source_ref = ?", (source_ref,)).fetchone()
            if exists:
                skipped += 1
                continue
            body = str(record.get("body") or record.get("text") or "")
            title = str(record.get("title") or source_ref)
            event = self.append_event(
                {
                    "project_id": project_id,
                    "event_type": "memory.observed",
                    "actor": {"kind": "tool", "id": "legacy-import"},
                    "after": {
                        "project_id": project_id,
                        "title": title,
                        "body": body,
                        "type": record.get("type") or "fact",
                        "scope": record.get("scope") or {"kind": "project", "key": project_id},
                        "source_refs": [{"kind": "legacy_import", "uri": source_ref}],
                    },
                    "source_refs": [{"kind": "legacy_import", "uri": source_ref}],
                }
            )
            self.conn.execute(
                "INSERT INTO legacy_imports (source_ref, event_id, imported_at) VALUES (?, ?, ?)",
                (source_ref, event["event_id"], time.time()),
            )
            imported += 1
        self.conn.commit()
        return {"imported": imported, "skipped": skipped}

    def event(self, event_id: str) -> dict[str, Any]:
        row = self.conn.execute("SELECT * FROM memory_events WHERE event_id = ?", (event_id,)).fetchone()
        if row is None:
            raise KeyError(event_id)
        return self._event_row(row)

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
                    canonical_json({"match_kind": result["match_kind"]}),
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
            "metadata": json.loads(row["metadata_json"] or "{}"),
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
            "metadata": json.loads(row["metadata_json"] or "{}"),
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

            CREATE TABLE IF NOT EXISTS legacy_imports (
                source_ref TEXT PRIMARY KEY,
                event_id TEXT NOT NULL,
                imported_at REAL NOT NULL
            );
            """
        )
        self.conn.execute(f"PRAGMA user_version={self.schema_version}")
        self.conn.commit()
