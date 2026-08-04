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

    fcm_server_key: str = ""
    fcm_project_id: str = ""

    max_upload_mb: int = 200
    max_chat_attachment_mb: int = 50

    setup_code_ttl_hours: int = 24
    auto_lock_minutes: int = 5

    cors_origins: str = "*"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
