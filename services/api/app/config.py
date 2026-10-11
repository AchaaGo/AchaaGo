from functools import lru_cache
from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from .sms import PHONE_FORMATS, parse_json_object


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
    # SMS_PROVIDER=http: any HTTP gateway, described by these (see app/sms.py and README "SMS").
    sms_http_url: str = ""
    sms_http_method: str = "POST"
    sms_http_headers: str = ""
    sms_http_body: str = ""
    sms_http_body_format: str = "json"
    sms_http_success_text: str = ""
    sms_api_key: str = ""
    sms_sender: str = ""
    sms_phone_format: str = "local"
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
    alert_provider: str = "console"
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""

    @model_validator(mode="after")
    def validate_configuration(self):
        if len(self.jwt_secret) < 32:
            raise ValueError("JWT_SECRET must contain at least 32 characters")
        if self.maps_provider not in {"demo", "google"} or self.qpay_provider not in {"demo", "qpay"}:
            raise ValueError("Unsupported provider")
        if self.sms_provider not in {"console", "http"}:
            raise ValueError("SMS_PROVIDER must be console or http")
        if self.sms_provider == "http":
            self.sms_http_method = self.sms_http_method.upper()
            if not self.sms_http_url.startswith(("https://", "http://")):
                raise ValueError("SMS_PROVIDER=http needs SMS_HTTP_URL")
            if self.sms_http_method not in {"GET", "POST"}:
                raise ValueError("SMS_HTTP_METHOD must be GET or POST")
            if self.sms_http_body_format not in {"json", "form"}:
                raise ValueError("SMS_HTTP_BODY_FORMAT must be json or form")
            if self.sms_phone_format not in PHONE_FORMATS:
                raise ValueError("SMS_PHONE_FORMAT must be one of " + ", ".join(sorted(PHONE_FORMATS)))
            parse_json_object(self.sms_http_headers, "SMS_HTTP_HEADERS")
            parse_json_object(self.sms_http_body, "SMS_HTTP_BODY")
        if self.alert_provider not in {"console", "telegram"}:
            raise ValueError("ALERT_PROVIDER must be console or telegram")
        if self.alert_provider == "telegram" and not (self.telegram_bot_token and self.telegram_chat_id):
            raise ValueError("ALERT_PROVIDER=telegram needs TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID")
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
