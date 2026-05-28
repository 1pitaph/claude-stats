from __future__ import annotations

import argparse
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from .store import MemoryStore


class MemoryHTTPRequestHandler(BaseHTTPRequestHandler):
    store: MemoryStore

    server_version = "ClaudeStatsMemoryD/0.1"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        try:
            if parsed.path == "/health":
                self._json(self.store.health())
            elif parsed.path == "/v1/projects":
                self._json({"projects": self.store.projects()})
            elif parsed.path == "/v1/memories/search":
                text = query.get("query", [""])[0]
                project_id = query.get("project_id", [None])[0]
                limit = int(query.get("limit", ["20"])[0])
                self._json(self.store.search(text, project_id=project_id, limit=limit))
            elif parsed.path.startswith("/v1/projects/") and parsed.path.endswith("/graph"):
                project_id = parsed.path.split("/")[3]
                self._json(self.store.graph(project_id))
            elif parsed.path.startswith("/v1/runs/") and parsed.path.endswith("/trace"):
                run_id = parsed.path.split("/")[3]
                self._json(self.store.trace(run_id))
            else:
                self._json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
        except Exception as error:  # noqa: BLE001
            self._json({"error": str(error)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        try:
            body = self._body()
            if parsed.path == "/v1/events":
                self._json(self.store.append_event(body))
            elif parsed.path == "/v1/memories/propose":
                self._json(self.store.propose_memory(body))
            elif parsed.path.startswith("/v1/memories/") and parsed.path.endswith("/accept"):
                memory_id = parsed.path.split("/")[3]
                self._json(self.store.accept_memory(memory_id, actor=body.get("actor") if isinstance(body, dict) else None))
            elif parsed.path == "/v1/context":
                self._json(
                    self.store.context_pack(
                        str(body.get("query") or ""),
                        project_id=body.get("project_id"),
                        limit=int(body.get("limit") or 10),
                    )
                )
            elif parsed.path == "/v1/legacy/import":
                self._json(self.store.legacy_import(body))
            elif parsed.path == "/mcp/":
                self._json(self._mcp(body))
            else:
                self._json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
        except KeyError as error:
            self._json({"error": f"not found: {error}"}, status=HTTPStatus.NOT_FOUND)
        except Exception as error:  # noqa: BLE001
            self._json({"error": str(error)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        return

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        data = self.rfile.read(length)
        return json.loads(data.decode("utf-8"))

    def _json(self, value: object, *, status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(value, sort_keys=True, ensure_ascii=False).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _mcp(self, payload: dict) -> dict:
        method = payload.get("method")
        request_id = payload.get("id")
        params = payload.get("params") if isinstance(payload.get("params"), dict) else {}
        if method == "tools/list":
            result = {
                "tools": [
                    {"name": "code_memory.search", "description": "Search Code Agent memories."},
                    {"name": "code_memory.context_pack", "description": "Build a compact memory context pack."},
                    {"name": "code_memory.propose_memory", "description": "Propose a memory for review."},
                    {"name": "code_memory.record_event", "description": "Record a memory event."},
                    {"name": "code_memory.get_trace", "description": "Fetch a memory retrieval trace."},
                ]
            }
        elif method == "tools/call":
            name = params.get("name")
            arguments = params.get("arguments") if isinstance(params.get("arguments"), dict) else {}
            if name == "code_memory.search":
                result = self.store.search(str(arguments.get("query") or ""), project_id=arguments.get("project_id"), limit=int(arguments.get("limit") or 20))
            elif name == "code_memory.context_pack":
                result = self.store.context_pack(str(arguments.get("query") or ""), project_id=arguments.get("project_id"), limit=int(arguments.get("limit") or 10))
            elif name == "code_memory.propose_memory":
                result = self.store.propose_memory(arguments)
            elif name == "code_memory.record_event":
                result = self.store.append_event(arguments)
            elif name == "code_memory.get_trace":
                result = self.store.trace(str(arguments.get("run_id") or ""))
            else:
                raise ValueError(f"unknown tool: {name}")
        else:
            raise ValueError(f"unknown MCP method: {method}")
        return {"jsonrpc": "2.0", "id": request_id, "result": result}


def serve(root: Path, host: str, port: int) -> None:
    store = MemoryStore(root)
    MemoryHTTPRequestHandler.store = store
    server = HTTPServer((host, port), MemoryHTTPRequestHandler)
    try:
        server.serve_forever()
    finally:
        store.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="memoryd")
    subparsers = parser.add_subparsers(dest="command", required=True)
    serve_parser = subparsers.add_parser("serve")
    serve_parser.add_argument("--root", default=str(Path.home() / "Library/Application Support/Claude Stats/Memory"))
    serve_parser.add_argument("--host", default="127.0.0.1")
    serve_parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args(argv)
    if args.command == "serve":
        serve(Path(args.root).expanduser(), args.host, args.port)
        return 0
    return 2
