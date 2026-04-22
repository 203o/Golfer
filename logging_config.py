# logging_config.py
import json
import logging
import os
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path

from fastapi import FastAPI
from request_context import get_request_id


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "severity": record.levelname,
            "logger": record.name,
            "time": self.formatTime(record, datefmt="%Y-%m-%dT%H:%M:%S%z"),
            "request_id": get_request_id(),
        }
        if isinstance(record.msg, dict):
            payload.update(record.msg)
        else:
            payload["message"] = record.getMessage()
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(app: FastAPI, log_dir: str | None = None) -> None:
    """
    Configure rotating file logging for the FastAPI application.

    - Default log dir: <project_root>/logs
    - File: app.log (1 MB, 5 backups)
    """
    # Best-effort project root: directory containing this file's parent
    project_root = Path(__file__).resolve().parent
    environment = os.getenv("ENVIRONMENT", "").lower()
    in_production = environment == "production"
    enable_file_logs = os.getenv("ENABLE_FILE_LOGS", "1" if not in_production else "0") == "1"
    enable_stdout_logs = os.getenv("LOG_TO_STDOUT", "1") == "1"
    log_level = os.getenv("LOG_LEVEL", "INFO").upper()
    use_json = os.getenv("LOG_FORMAT", "json" if in_production else "text") == "json"

    formatter: logging.Formatter = (
        JsonFormatter()
        if use_json
        else logging.Formatter("%(asctime)s [%(levelname)s]: %(message)s")
    )
    handlers: list[logging.Handler] = []

    if enable_stdout_logs:
        stream_handler = logging.StreamHandler(sys.stdout)
        stream_handler.setFormatter(formatter)
        handlers.append(stream_handler)

    if enable_file_logs:
        logs_path = Path(log_dir) if log_dir else project_root / "logs"
        logs_path.mkdir(parents=True, exist_ok=True)
        log_file = logs_path / "app.log"
        file_handler = RotatingFileHandler(
            log_file,
            maxBytes=1_000_000,
            backupCount=5,
            encoding="utf-8",
        )
        file_handler.setFormatter(formatter)
        handlers.append(file_handler)
    else:
        log_file = None

    def attach_handlers(logger_name: str) -> None:
        logger = logging.getLogger(logger_name)
        logger.setLevel(log_level)
        for handler in handlers:
            if handler not in logger.handlers:
                logger.addHandler(handler)

    # Attach to key loggers
    attach_handlers("uvicorn.error")
    attach_handlers("uvicorn.access")
    attach_handlers("app")
    attach_handlers("Golfer")

    logging.getLogger("app").info(
        "Logging configured (stdout=%s, file=%s)",
        enable_stdout_logs,
        bool(log_file),
    )
