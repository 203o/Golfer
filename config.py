from functools import lru_cache
from fastapi import Depends, Request, APIRouter
from settings import Settings  # Assuming settings.py is in the same directory

# --- 1. A Robust Settings Dependency ---


@lru_cache()
def _get_cached_settings() -> Settings:
    """
    Private function that loads and caches the Settings instance.
    The @lru_cache decorator ensures this is only called once per application run.
    """
    return Settings()


def get_settings() -> Settings:
    """
    FastAPI dependency function to provide the Settings instance.
    This is the standard way to access configuration in FastAPI.
    """
    return _get_cached_settings()


# --- 2. A More Useful /config Endpoint ---

config_router = APIRouter(prefix="/config", tags=["Configuration"])


@config_router.get("")
async def get_backend_config(
    request: Request, settings: Settings = Depends(get_settings)
):
    """
    Provides dynamic configuration to the frontend.
    """
    # Dynamically construct the base URL from the incoming request.
    # This works for any domain (localhost, ngrok, Cloud Run, etc.).
    base_url = f"{request.url.scheme}://{request.url.netloc}"

    return {
        "api_base_url": base_url,
        "is_Payment_live": settings.DARAJA_LIVE,
        # You can add other non-sensitive configuration here if needed
        # "feature_x_enabled": settings.FEATURE_X_ENABLED,
    }
