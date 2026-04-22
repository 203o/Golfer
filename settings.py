from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"
    CORS_ALLOW_ORIGINS: str = "http://localhost,http://127.0.0.1"

    DATABASE_URL: str = ""
    DATABASE_URL_WRITE: str = ""
    DATABASE_URL_READ: str = ""

    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20
    DB_POOL_TIMEOUT: int = 30
    DB_POOL_RECYCLE: int = 1800
    DB_POOL_PRE_PING: bool = True

    SYNC_DB_POOL_SIZE: int = 5
    SYNC_DB_MAX_OVERFLOW: int = 10
    SYNC_DB_POOL_TIMEOUT: int = 30
    SYNC_DB_POOL_RECYCLE: int = 1800
    SYNC_DB_POOL_PRE_PING: bool = True

    DB_SLOW_QUERY_MS: int = 250
    DB_STATEMENT_TIMEOUT_MS: int = 15000

    READ_REPLICA_ENABLED: bool = False
    READ_REPLICA_CANARY_PERCENT: int = 0
    READ_AFTER_WRITE_SECONDS: int = 8
    READ_REPLICA_ERROR_THRESHOLD: int = 3
    READ_REPLICA_ERROR_WINDOW_SECONDS: int = 45

    DARAJA_LIVE: bool = False
    DARAJA_CONSUMER_KEY: str = ""
    DARAJA_CONSUMER_SECRET: str = ""
    DARAJA_SHORTCODE: str = ""
    DARAJA_PASSKEY: str = ""
    DARAJA_CALLBACK_URL: str = ""

    MIN_API_VERSION: int = 1

    @property
    def daraja_base_url(self) -> str:
        return (
            "https://api.safaricom.co.ke"
            if self.DARAJA_LIVE
            else "https://sandbox.safaricom.co.ke"
        )
