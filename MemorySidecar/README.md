# Claude Stats Memory Sidecar

`memoryd` is the local Code Agent memory sidecar used by Claude Stats. It keeps
an append-only event log as the source of truth, projects active memories into a
queryable store, and exposes REST plus MCP-compatible HTTP tools.

The implementation is deterministic and local-first. mem0 and Graphiti are
optional local projections behind feature flags; they are not required for basic
event, search, graph, or trace flows.

```bash
python3 -m memoryd serve --root "$HOME/Library/Application Support/Claude Stats/Memory"
```

Default endpoint: `http://127.0.0.1:8765`.
