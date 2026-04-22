import logging
from typing import Any


SENSITIVE_KEYS = {
    "password",
    "passkey",
    "token",
    "access_token",
    "refresh_token",
    "authorization",
    "bearer",
    "secret",
    "api_key",
    "checkout_id",
    "checkoutrequestid",
    "mpesareceiptnumber",
    "receipt",
    "receipt_number",
    "phone",
    "phonenumber",
    "party_a",
    "partya",
    "email",
}


def _redact_phone(value: str) -> str:
    digits = "".join(ch for ch in value if ch.isdigit())
    if len(digits) < 4:
        return "***"
    return f"{digits[:2]}***{digits[-2:]}"


def _redact_email(value: str) -> str:
    if "@" not in value:
        return "***"
    name, domain = value.split("@", 1)
    if len(name) <= 2:
        return f"**@{domain}"
    return f"{name[:2]}***@{domain}"


def _redact_value(key: str, value: Any) -> Any:
    if value is None:
        return value
    key_lower = key.lower()
    if key_lower in {"phone", "phonenumber", "party_a", "partya"}:
        return _redact_phone(str(value))
    if key_lower == "email":
        return _redact_email(str(value))
    if key_lower in SENSITIVE_KEYS:
        return "***"
    return value


def redact_fields(fields: dict[str, Any]) -> dict[str, Any]:
    return {k: _redact_value(k, v) for k, v in fields.items()}


def log_event(logger: logging.Logger, level: int, event: str, **fields: Any) -> None:
    payload = {"event": event, **redact_fields(fields)}
    logger.log(level, payload)
