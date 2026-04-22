import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from settings import Settings
from logging_config import configure_logging
from routers.golf import router as golf_router
from routers.mpesa_core import router as mpesa_router
from routers.tournament import router as tournament_router

settings = Settings()
logger = logging.getLogger("golf.app")


def _cors_origins(raw: str) -> list[str]:
    values = [item.strip() for item in (raw or "").split(",")]
    return [item.rstrip("/") for item in values if item]


@asynccontextmanager
async def lifespan(_: FastAPI):
    logger.info("Starting Golf Charity API")
    yield
    logger.info("Stopping Golf Charity API")


app = FastAPI(
    title="Golf Charity Draw API",
    description="Subscription-driven golf performance + charity + draw engine",
    version="1.0.0",
    lifespan=lifespan,
)

configure_logging(app)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins(settings.CORS_ALLOW_ORIGINS),
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(golf_router)
app.include_router(mpesa_router)
app.include_router(tournament_router)


@app.get("/", tags=["Root"])
async def root() -> JSONResponse:
    return JSONResponse(
        {
            "service": "Golf Charity Draw API",
            "status": "ok",
            "modules": {
                "golf": True,
                "tournament": True,
                "mpesa": True,
            },
        }
    )


@app.get("/health", tags=["Health"])
async def health() -> JSONResponse:
    return JSONResponse({"ok": True})
