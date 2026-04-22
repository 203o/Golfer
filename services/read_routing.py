from __future__ import annotations

import hashlib
import logging
import threading
import time
from collections.abc import Iterable
from fastapi import Request

from settings import Settings


logger = logging.getLogger("Golfer.db.routing")
settings = Settings()
_lock = threading.Lock()
_recent_writes: dict[str, float] = {}
_error_count = 0
_circuit_open_until = 0.0


def _now() -> float:
    return time.time()


def _token_fingerprint(auth_header: str) -> str:
    digest = hashlib.sha1(auth_header.encode("utf-8")).hexdigest()
    return digest[:16]


def _subject_keys(request: Request | None) -> list[str]:
    if request is None:
        return ["unknown"]

    keys: list[str] = []
    auth_header = (request.headers.get("Authorization") or "").strip()
    if auth_header:
        keys.append(f"auth:{_token_fingerprint(auth_header)}")

    client_ip = request.client.host if request and request.client else ""
    if client_ip:
        keys.append(f"ip:{client_ip}")

    if not keys:
        keys.append("unknown")
    return keys


def mark_recent_write(request: Request) -> None:
    keys = _subject_keys(request)
    now = _now()
    max_age = max(30, int(settings.READ_AFTER_WRITE_SECONDS) * 6)
    with _lock:
        for key in keys:
            _recent_writes[key] = now
        stale = [k for k, ts in _recent_writes.items() if now - ts > max_age]
        for key in stale:
            _recent_writes.pop(key, None)


def _has_recent_write(subject_keys: Iterable[str]) -> bool:
    window = max(0, int(settings.READ_AFTER_WRITE_SECONDS))
    if window == 0:
        return False
    now = _now()
    with _lock:
        for key in subject_keys:
            ts = _recent_writes.get(key)
            if ts is not None and now - ts <= window:
                return True
    return False


def _is_circuit_open() -> bool:
    with _lock:
        return _now() < _circuit_open_until


def record_read_error(reason: str) -> None:
    global _error_count, _circuit_open_until
    threshold = max(1, int(settings.READ_REPLICA_ERROR_THRESHOLD))
    window = max(5, int(settings.READ_REPLICA_ERROR_WINDOW_SECONDS))
    with _lock:
        _error_count += 1
        if _error_count >= threshold:
            _circuit_open_until = _now() + window
            _error_count = 0
    logger.warning(
        {
            "event": "read_replica_error",
            "reason": reason,
            "circuit_open_until": _circuit_open_until,
        }
    )


def record_read_success() -> None:
    global _error_count
    with _lock:
        _error_count = 0


def should_use_read_replica(request: Request) -> tuple[bool, str]:
    if not settings.READ_REPLICA_ENABLED:
        return False, "feature_disabled"

    if not settings.DATABASE_URL_READ:
        return False, "missing_read_url"

    if _is_circuit_open():
        return False, "circuit_open"

    keys = _subject_keys(request)
    if _has_recent_write(keys):
        return False, "read_after_write"

    canary_percent = max(0, min(100, int(settings.READ_REPLICA_CANARY_PERCENT)))
    if canary_percent <= 0:
        return False, "canary_zero"
    if canary_percent >= 100:
        return True, "canary_full"

    # Stable bucketing using the first subject key.
    bucket = int(hashlib.md5(keys[0].encode("utf-8")).hexdigest(), 16) % 100
    use_read = bucket < canary_percent
    return use_read, f"canary_{canary_percent}"

