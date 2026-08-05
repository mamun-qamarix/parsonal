from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Couple Vault Backend"
    domain: str = "localhost"
    environment: str = "production"

    database_url: str = "postgresql+asyncpg://vault:vault@postgres:5432/vault"
    sync_database_url: str = "postgresql+psycopg2://vault:vault@postgres:5432/vault"

    jwt_secret: str = "change-me-in-env"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    admin_panel_secret: str = "change-me-in-env"

    minio_endpoint: str = "minio:9000"
    minio_access_key: str = "minioadmin"
    minio_secret_key: str = "minioadmin"
    minio_bucket: str = "vault-media"
    minio_secure: bool = False

    compreface_url: str = "http://compreface-api:8000"
    compreface_recognition_api_key: str = ""
    compreface_similarity_threshold: float = 0.85

    # Path (inside the backend container) to the Firebase Admin SDK service
    # account JSON used to send push notifications. Never committed to git --
    # mounted read-only from a file that lives only on the VPS. See
    # docker-compose.yml and DECISIONS.md. Empty by default: pushes are
    # simply skipped (the app still works fully over WebSocket while open).
    fcm_service_account_path: str = ""

    max_upload_mb: int = 1024
    max_chat_attachment_mb: int = 50

    setup_code_ttl_hours: int = 24
    auto_lock_minutes: int = 5

    # Empty by default -- see cors_origin_list. A literal "*" combined with
    # the admin panel's credentialed (cookie) requests would let ANY
    # website reflected as an allowed origin ride the admin's session, so
    # we never default to that; set this explicitly (comma-separated) only
    # if the admin panel is genuinely accessed from another origin.
    cors_origins: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        # A bare "*" is treated as "not set" rather than honored -- combined
        # with allow_credentials=True (needed for the admin panel's cookie
        # session) it would let any website ride an admin's session. This
        # also self-heals deployments whose .env still has the old
        # CORS_ORIGINS=* default from before this was locked down.
        explicit = [o.strip() for o in self.cors_origins.split(",") if o.strip() and o.strip() != "*"]
        if explicit:
            return explicit
        return [f"https://{self.domain}"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
