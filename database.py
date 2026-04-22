# database.py - Fixed version with robust URL parsing
from fastapi import Request
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy import text
from sqlalchemy import event
from settings import Settings
from urllib.parse import urlparse, urlunparse, parse_qsl, urlencode
from collections import defaultdict
from time import perf_counter
import logging
import re
from request_context import get_request_id
from services.read_routing import (
    should_use_read_replica,
    record_read_error,
    record_read_success,
)

settings = Settings()
logger = logging.getLogger("Golfer.db")


def get_clean_database_url(raw_url: str):
    """Normalize DB URL while preserving required query params like sslmode."""
    if not raw_url:
        raise ValueError("DATABASE_URL is not set")

    # Guard against malformed values accidentally prefixed like "://?postgresql+asyncpg://..."
    normalized = str(raw_url).strip()
    if normalized.startswith("://?"):
        normalized = normalized[len("://?") :]

    parsed = urlparse(normalized)
    if not parsed.scheme or not parsed.netloc:
        raise ValueError(f"Invalid DATABASE_URL format: {normalized}")

    query = dict(parse_qsl(parsed.query, keep_blank_values=True))

    # asyncpg does not accept libpq params like `sslmode` / `channel_binding`
    # as direct connect() kwargs. Normalize psql-style URLs for async engine use.
    if parsed.scheme.startswith("postgresql+asyncpg"):
        if "sslmode" in query and "ssl" not in query:
            sslmode = (query.pop("sslmode") or "").strip().lower()
            # For Neon, any strict libpq sslmode should map to required TLS.
            if sslmode in {"require", "verify-ca", "verify-full"}:
                query["ssl"] = "require"
            elif sslmode in {"disable", "allow"}:
                query["ssl"] = "disable"
            else:
                query["ssl"] = "require"
        # Not supported by asyncpg connect kwargs.
        query.pop("channel_binding", None)

    return urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parsed.params,
            urlencode(query),
            parsed.fragment,
        )
    )


# Get clean URL
DATABASE_URL = get_clean_database_url(settings.DATABASE_URL or "")
DATABASE_URL_WRITE = get_clean_database_url(
    settings.DATABASE_URL_WRITE or settings.DATABASE_URL or ""
)
DATABASE_URL_READ = (
    get_clean_database_url(settings.DATABASE_URL_READ)
    if (settings.DATABASE_URL_READ or "").strip()
    else ""
)

# Create engines with clean URL
write_async_engine = create_async_engine(
    DATABASE_URL_WRITE,
    echo=False,  # Set to True to debug SQL
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_timeout=settings.DB_POOL_TIMEOUT,
    pool_recycle=settings.DB_POOL_RECYCLE,
    pool_pre_ping=settings.DB_POOL_PRE_PING,
)

read_async_engine = (
    create_async_engine(
        DATABASE_URL_READ,
        echo=False,
        pool_size=settings.DB_POOL_SIZE,
        max_overflow=settings.DB_MAX_OVERFLOW,
        pool_timeout=settings.DB_POOL_TIMEOUT,
        pool_recycle=settings.DB_POOL_RECYCLE,
        pool_pre_ping=settings.DB_POOL_PRE_PING,
    )
    if DATABASE_URL_READ
    else write_async_engine
)

# Backward compatibility alias
async_engine = write_async_engine

DB_METRICS = {
    "reads": 0,
    "writes": 0,
    "others": 0,
    "slow_queries": 0,
    "read_replica_routed": 0,
    "writer_forced": 0,
    "by_type": defaultdict(int),
}

_SQL_PREFIX_RE = re.compile(r"^\s*([A-Za-z]+)")


def _classify_sql(statement: str) -> str:
    match = _SQL_PREFIX_RE.match(statement or "")
    if not match:
        return "OTHER"
    verb = match.group(1).upper()
    if verb == "SELECT":
        return "READ"
    if verb in {"INSERT", "UPDATE", "DELETE", "MERGE"}:
        return "WRITE"
    return "OTHER"


def _attach_query_events(engine, engine_role: str) -> None:
    @event.listens_for(engine.sync_engine, "before_cursor_execute")
    def _before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        conn.info.setdefault("query_start_time", []).append(perf_counter())

    @event.listens_for(engine.sync_engine, "after_cursor_execute")
    def _after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        start_time = conn.info.get("query_start_time", [])
        started = start_time.pop() if start_time else perf_counter()
        elapsed_ms = (perf_counter() - started) * 1000

        query_type = _classify_sql(statement)
        DB_METRICS["by_type"][query_type] += 1
        if query_type == "READ":
            DB_METRICS["reads"] += 1
        elif query_type == "WRITE":
            DB_METRICS["writes"] += 1
        else:
            DB_METRICS["others"] += 1

        if elapsed_ms >= settings.DB_SLOW_QUERY_MS:
            DB_METRICS["slow_queries"] += 1
            normalized_sql = " ".join((statement or "").split())
            logger.warning(
                {
                    "event": "db_slow_query",
                    "engine_role": engine_role,
                    "query_type": query_type,
                    "duration_ms": round(elapsed_ms, 2),
                    "request_id": get_request_id(),
                    "sql_preview": normalized_sql[:240],
                }
            )


_attach_query_events(write_async_engine, "write")
if read_async_engine is not write_async_engine:
    _attach_query_events(read_async_engine, "read")

AsyncSessionWriteLocal = async_sessionmaker(
    write_async_engine,
    expire_on_commit=False,
    autoflush=False,
)
AsyncSessionReadLocal = async_sessionmaker(
    read_async_engine,
    expire_on_commit=False,
    autoflush=False,
)

# Backward compatibility for modules importing AsyncSessionLocal
AsyncSessionLocal = AsyncSessionWriteLocal

# Sync engine for cleanup jobs
def _build_sync_database_url(async_url: str) -> str:
    """
    Convert asyncpg URL to psycopg2 URL, translating query params where needed.
    asyncpg: ?ssl=require
    psycopg2: ?sslmode=require
    """
    sync_url = async_url.replace("postgresql+asyncpg://", "postgresql://", 1)
    parsed = urlparse(sync_url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    if "ssl" in query and "sslmode" not in query:
        query["sslmode"] = query.pop("ssl")
    return urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parsed.params,
            urlencode(query),
            parsed.fragment,
        )
    )


sync_database_url = _build_sync_database_url(DATABASE_URL_WRITE)
sync_engine = create_engine(
    sync_database_url,
    echo=False,
    pool_size=settings.SYNC_DB_POOL_SIZE,
    max_overflow=settings.SYNC_DB_MAX_OVERFLOW,
    pool_timeout=settings.SYNC_DB_POOL_TIMEOUT,
    pool_recycle=settings.SYNC_DB_POOL_RECYCLE,
    pool_pre_ping=settings.SYNC_DB_POOL_PRE_PING,
)

SessionLocal = sessionmaker(sync_engine)

Base = declarative_base()


# Session providers
async def get_async_db() -> AsyncSession:
    async with AsyncSessionWriteLocal() as session:
        await session.execute(
            text(f"SET statement_timeout = {settings.DB_STATEMENT_TIMEOUT_MS}")
        )
        yield session


async def get_read_db(request: Request) -> AsyncSession:
    use_read, reason = should_use_read_replica(request)
    request.state.query_intent = "read"
    request.state.db_route = "read" if use_read else "write"
    request.state.db_route_reason = reason

    if use_read:
        DB_METRICS["read_replica_routed"] += 1
        try:
            async with AsyncSessionReadLocal() as session:
                await session.execute(
                    text(f"SET statement_timeout = {settings.DB_STATEMENT_TIMEOUT_MS}")
                )
                record_read_success()
                yield session
                return
        except Exception as exc:
            record_read_error(type(exc).__name__)
            logger.warning(
                {
                    "event": "read_replica_fallback_to_writer",
                    "reason": reason,
                    "error_type": type(exc).__name__,
                }
            )

    DB_METRICS["writer_forced"] += 1
    async with AsyncSessionWriteLocal() as session:
        await session.execute(
            text(f"SET statement_timeout = {settings.DB_STATEMENT_TIMEOUT_MS}")
        )
        yield session


def get_sync_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Optional alias for backward compatibility
get_db = get_async_db
