"""Simple in-process circuit breaker for payments-mock calls."""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from enum import Enum


class State(str, Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


@dataclass
class CircuitBreaker:
    """Fail-fast when the payment dependency is unhealthy.

    CLOSED  — calls go through
    OPEN    — short-circuit with degraded response (no dependency call)
    HALF_OPEN — allow a probe call after cooldown
    """

    failure_threshold: int = 3
    recovery_timeout_s: float = 30.0
    _failures: int = 0
    _state: State = State.CLOSED
    _opened_at: float = 0.0
    _lock: threading.Lock = threading.Lock()

    @property
    def state(self) -> State:
        with self._lock:
            self._maybe_half_open_unlocked()
            return self._state

    def allow_request(self) -> bool:
        with self._lock:
            self._maybe_half_open_unlocked()
            return self._state != State.OPEN

    def record_success(self) -> None:
        with self._lock:
            self._failures = 0
            self._state = State.CLOSED

    def record_failure(self) -> None:
        with self._lock:
            self._failures += 1
            if self._state == State.HALF_OPEN or self._failures >= self.failure_threshold:
                self._state = State.OPEN
                self._opened_at = time.monotonic()

    def snapshot(self) -> dict:
        with self._lock:
            self._maybe_half_open_unlocked()
            return {
                "state": self._state.value,
                "failures": self._failures,
                "failure_threshold": self.failure_threshold,
                "recovery_timeout_s": self.recovery_timeout_s,
            }

    def _maybe_half_open_unlocked(self) -> None:
        if self._state == State.OPEN:
            if time.monotonic() - self._opened_at >= self.recovery_timeout_s:
                self._state = State.HALF_OPEN
