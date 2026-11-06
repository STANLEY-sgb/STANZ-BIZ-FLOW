"""Application configuration loaded from environment variables.

Secrets are never hard-coded; see `.env.example` for the full list.
"""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "STANZ BizFlow API"
    app_env: str = "development"
    api_prefix: str = "/api/v1"

    database_url: str = "postgresql+psycopg://bizflow:bizflow@localhost:5432/bizflow"
    db_pool_size: int = 10
    db_max_overflow: int = 10
    # Serverless hosts (Vercel) start many short-lived instances: no client-side pool, and no prepared
    # statements (required by Supabase's transaction pooler).
    db_serverless: bool = False

    jwt_secret: str = Field(default="", min_length=0)
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    password_reset_minutes: int = 30
    invitation_days: int = 7

    cors_origins: list[str] = []

    email_backend: str = "log"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from: str = "no-reply@example.com"
    public_app_url: str = "https://app.example.com"

    # Rate limiting for authentication-sensitive endpoints (per client key).
    auth_rate_limit_attempts: int = 10
    auth_rate_limit_window_seconds: int = 300

    max_page_size: int = 100

    # File storage. "local" writes under local_storage_dir (mount a persistent volume in production).
    # An S3-compatible backend (AWS S3, Cloudflare R2, Supabase Storage) plugs in behind app/core/storage.py.
    storage_backend: str = "local"
    local_storage_dir: str = "./data/uploads"
    # STORAGE_BACKEND=supabase: private bucket accessed with the service-role key (server-side only).
    supabase_url: str = ""
    supabase_service_key: str = ""
    supabase_bucket: str = "bizflow-files"
    # Signed file links expire after this many seconds.
    file_url_ttl_seconds: int = 3600

    @field_validator("database_url")
    @classmethod
    def _psycopg_driver(cls, value: str) -> str:
        # Hosts such as Render/Heroku hand out "postgres://" or "postgresql://"; we use the psycopg 3 driver.
        for prefix in ("postgres://", "postgresql://"):
            if value.startswith(prefix):
                return "postgresql+psycopg://" + value[len(prefix) :]
        return value

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    def validate_for_runtime(self) -> None:
        """Refuse to start in production with unsafe configuration."""
        if self.is_production:
            if len(self.jwt_secret) < 32:
                raise RuntimeError("JWT_SECRET must be set to at least 32 characters in production")
            if self.email_backend == "log":
                raise RuntimeError("EMAIL_BACKEND=log is not permitted in production")


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    if not settings.jwt_secret:
        if settings.is_production:
            raise RuntimeError("JWT_SECRET is required in production")
        # Development convenience only: a per-process random secret means tokens
        # do not survive restarts, which is acceptable outside production.
        import secrets

        settings.jwt_secret = secrets.token_urlsafe(64)
    settings.validate_for_runtime()
    return settings
