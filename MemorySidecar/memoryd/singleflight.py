from __future__ import annotations

import time
from contextlib import contextmanager
from dataclasses import dataclass
from threading import Lock
from typing import Any, Iterator


@dataclass(frozen=True)
class SingleFlightLease:
    name: str
    run_id: int
    started_at: float

    def to_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "run_id": self.run_id,
            "started_at": self.started_at,
            "running_seconds": max(0.0, time.time() - self.started_at),
        }


class SingleFlightGate:
    def __init__(self, name: str):
        self.name = name
        self._run_lock = Lock()
        self._state_lock = Lock()
        self._active: SingleFlightLease | None = None
        self._next_run_id = 0

    @contextmanager
    def run(self) -> Iterator[SingleFlightLease | None]:
        if not self._run_lock.acquire(blocking=False):
            yield None
            return

        lease = self._start_lease()
        try:
            yield lease
        finally:
            self._finish_lease()
            self._run_lock.release()

    def snapshot(self) -> dict[str, Any]:
        with self._state_lock:
            active = self._active
        if active is None:
            return {"name": self.name, "running": False}
        return {"running": True, **active.to_json()}

    def _start_lease(self) -> SingleFlightLease:
        with self._state_lock:
            self._next_run_id += 1
            lease = SingleFlightLease(
                name=self.name,
                run_id=self._next_run_id,
                started_at=time.time(),
            )
            self._active = lease
            return lease

    def _finish_lease(self) -> None:
        with self._state_lock:
            self._active = None
