from functools import lru_cache
from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    app_env: str = "development"
    brand_name: str = "AchaaGo"
    public_url: str = "http://localhost:8187"
    database_url: str = "postgresql+asyncpg://achaago:achaago@postgres:5432/achaago"
    redis_url: str = "redis://redis:6379/0"
    celery_broker_url: str = "redis://redis:6379/1"
    jwt_secret: str
    bootstrap_admin_phone: str = ""
    seed_demo_driver: bool = False
    sms_provider: str = "console"
    maps_provider: str = "demo"
    google_maps_api_key: str = ""
    qpay_provider: str = "demo"
    qpay_base_url: str = "https://merchant.qpay.mn"
    qpay_username: str = ""
    qpay_password: str = ""
    qpay_invoice_code: str = ""
    fcm_provider: str = "console"
    fcm_project_id: str = ""
    customer_cancel_statuses: str = "pending,assigned,driver_arriving,arrived"
    dispatch_timeout_minutes: int = 30

    @model_validator(mode="after")
    def validate_configuration(self):
        if len(self.jwt_secret) < 32:
            raise ValueError("JWT_SECRET must contain at least 32 characters")
        if self.maps_provider not in {"demo", "google"} or self.qpay_provider not in {"demo", "qpay"}:
            raise ValueError("Unsupported provider")
        if self.sms_provider != "console":
            raise ValueError("Implement the selected SMS provider before enabling it")
        if self.app_env == "production":
            if not self.public_url.startswith("https://"):
                raise ValueError("Production requires HTTPS")
            if self.sms_provider == "console" or self.maps_provider != "google" or self.qpay_provider != "qpay":
                raise ValueError("Production cannot use development providers")
            if self.seed_demo_driver:
                raise ValueError("Demo seeding is forbidden in production")
        return self


@lru_cache
def get_settings():
    return Settings()


settings = get_settings()
