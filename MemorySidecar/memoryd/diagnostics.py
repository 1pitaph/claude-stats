from __future__ import annotations

import hashlib
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


DIAGNOSTIC_LOG_PREFIX = "memory-capture-"
DIAGNOSTIC_LOG_SUFFIX = ".jsonl"
DEFAULT_RETENTION_DAYS = 3


class MemoryDiagnosticsLogger:
    def __init__(
        self,
        root: Path,
        *,
        retention_days: int = DEFAULT_RETENTION_DAYS,
        dev_log_dir: Path | None = None,
        clock: Callable[[], float] | None = None,
    ):
        self.root = root
        self.retention_days = _bounded_retention_days(retention_days)
        self.dev_log_dir = dev_log_dir
        self.clock = clock or time.time
        self._last_hour_key = ""
        self.prune()

    @classmethod
    def from_environment(cls, root: Path, *, retention_days: int = DEFAULT_RETENTION_DAYS) -> "MemoryDiagnosticsLogger":
        raw_dev_dir = os.environ.get("CLAUDE_STATS_MEMORY_DEV_LOG_DIR", "").strip()
        dev_log_dir = Path(raw_dev_dir).expanduser() if raw_dev_dir else None
        return cls(root, retention_days=retention_days, dev_log_dir=dev_log_dir)

    @property
    def app_log_dir(self) -> Path:
        return self.root / "diagnostics"

    @property
    def log_dirs(self) -> list[Path]:
        dirs = [self.app_log_dir]
        if self.dev_log_dir is not None:
            dirs.append(self.dev_log_dir)
        return dirs

    def configure(self, *, retention_days: int) -> None:
        self.retention_days = _bounded_retention_days(retention_days)
        self.prune()
        self.log("diagnostics.retention.updated", retention_days=self.retention_days)

    def current_log_path(self, directory: Path | None = None) -> Path:
        directory = directory or self.app_log_dir
        return directory / f"{DIAGNOSTIC_LOG_PREFIX}{self._hour_key()}{DIAGNOSTIC_LOG_SUFFIX}"

    def summary(self) -> dict[str, Any]:
        app_path = self.current_log_path(self.app_log_dir)
        result: dict[str, Any] = {
            "diagnostics_log_path": str(app_path),
            "diagnostics_log_size": _file_size(app_path),
            "diagnostics_retention_days": self.retention_days,
        }
        if self.dev_log_dir is not None:
            dev_path = self.current_log_path(self.dev_log_dir)
            result["diagnostics_dev_log_path"] = str(dev_path)
            result["diagnostics_dev_log_size"] = _file_size(dev_path)
        return result

    def log(self, event: str, *, level: str = "info", **fields: Any) -> None:
        try:
            self._log(event, level=level, **fields)
        except Exception:
            return

    def prune(self) -> None:
        cutoff = self.clock() - (self.retention_days * 24 * 60 * 60)
        for directory in self.log_dirs:
            try:
                directory.mkdir(parents=True, exist_ok=True)
            except OSError:
                continue
            for path in directory.glob(f"{DIAGNOSTIC_LOG_PREFIX}*{DIAGNOSTIC_LOG_SUFFIX}"):
                timestamp = _timestamp_from_log_name(path.name)
                if timestamp is None:
                    continue
                if timestamp < cutoff:
                    try:
                        path.unlink()
                    except OSError:
                        self.log("diagnostics.prune.warning", level="warning", path=str(path))

    def _log(self, event: str, *, level: str, **fields: Any) -> None:
        now = self.clock()
        hour_key = self._hour_key(now)
        if hour_key != self._last_hour_key:
            self._last_hour_key = hour_key
            self.prune()
        record = {
            "ts": datetime.fromtimestamp(now, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "level": level,
            "event": event,
        }
        record.update(_sanitize(fields))
        data = json.dumps(record, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
        for directory in self.log_dirs:
            path = self.current_log_path(directory)
            try:
                directory.mkdir(parents=True, exist_ok=True)
                with path.open("ab") as handle:
                    handle.write(data)
            except OSError:
                continue

    def _hour_key(self, now: float | None = None) -> str:
        return datetime.fromtimestamp(now if now is not None else self.clock(), timezone.utc).strftime("%Y-%m-%d-%H")


def text_fingerprint(text: str) -> dict[str, Any]:
    raw = text or ""
    return {
        "text_hash": "sha256:" + hashlib.sha256(raw.encode("utf-8", errors="replace")).hexdigest()[:24],
        "text_chars": len(raw),
    }


def input_fingerprint(value: Any) -> dict[str, Any]:
    if isinstance(value, str):
        return text_fingerprint(value)
    if isinstance(value, list):
        parts = [item for item in value if isinstance(item, str)]
        joined = "\n".join(parts)
        return {
            **text_fingerprint(joined),
            "input_items": len(value),
        }
    return {"text_hash": "", "text_chars": 0}


def _sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            if _redacted_key(key_text):
                result[key_text] = "[redacted]"
            else:
                result[key_text] = _sanitize(item)
        return result
    if isinstance(value, list):
        return [_sanitize(item) for item in value[:50]]
    if isinstance(value, (str, int, float, bool)) or value is None:
        if isinstance(value, str) and len(value) > 600:
            return value[:597] + "..."
        return value
    return str(value)


def _redacted_key(key: str) -> bool:
    normalized = key.lower()
    return bool(
        re.search(
            r"(api[_-]?key|token|authorization|secret|password|raw|body|prompt|response|embedding|vector|messages)",
            normalized,
        )
    )


def _timestamp_from_log_name(name: str) -> float | None:
    if not name.startswith(DIAGNOSTIC_LOG_PREFIX) or not name.endswith(DIAGNOSTIC_LOG_SUFFIX):
        return None
    stamp = name[len(DIAGNOSTIC_LOG_PREFIX) : -len(DIAGNOSTIC_LOG_SUFFIX)]
    try:
        return datetime.strptime(stamp, "%Y-%m-%d-%H").replace(tzinfo=timezone.utc).timestamp()
    except ValueError:
        return None


def _file_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def _bounded_retention_days(value: int) -> int:
    try:
        parsed = int(value or DEFAULT_RETENTION_DAYS)
    except (TypeError, ValueError):
        parsed = DEFAULT_RETENTION_DAYS
    return 7 if parsed >= 7 else 3
