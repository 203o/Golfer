from __future__ import annotations

from contextvars import ContextVar


_request_id_var: ContextVar[str] = ContextVar("request_id", default="unknown")


def set_request_id(request_id: str):
    return _request_id_var.set(request_id or "unknown")


def reset_request_id(token) -> None:
    _request_id_var.reset(token)


def get_request_id() -> str:
    return _request_id_var.get()

