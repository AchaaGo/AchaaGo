import json
import logging
from types import SimpleNamespace
import httpx
import pytest
from fakeredis.aioredis import FakeRedis
from app import cache, workers
from app import main as main_module
from app.config import Settings, settings
from app.providers import HttpSmsProvider, sms_provider

SECRET = "test-secret-that-is-at-least-thirty-two-characters"


# --- HTTP SMS provider: one implementation configurable for any gateway ---


@pytest.fixture
def http_sms(monkeypatch):
    for name, value in {"sms_provider": "http", "sms_http_url": "https://sms.example.mn/send",
                        "sms_http_method": "POST", "sms_http_headers": '{"Authorization": "Bearer {api_key}"}',
                        "sms_http_body": '{"from": "{sender}", "to": "{phone}", "text": "{message}"}',
                        "sms_http_body_format": "json", "sms_http_success_text": "", "sms_api_key": "key-123",
                        "sms_sender": "AchaaGo", "sms_phone_format": "local"}.items():
        monkeypatch.setattr(settings, name, value)
    sent = []

    def gateway(handler):
        def respond(request):
            sent.append(request)
            return handler(request)
        return HttpSmsProvider(httpx.Client(transport=httpx.MockTransport(respond)))
    return gateway, sent


def test_http_sms_posts_json_with_substituted_fields(http_sms):
    gateway, sent = http_sms
    gateway(lambda request: httpx.Response(200, json={"ok": True})).send("+97699112233", 'Код 1234 "ok"')
    request = sent[0]
    assert (request.method, str(request.url)) == ("POST", "https://sms.example.mn/send")
    assert request.headers["Authorization"] == "Bearer key-123"
    assert json.loads(request.content) == {"from": "AchaaGo", "to": "99112233", "text": 'Код 1234 "ok"'}


def test_http_sms_get_url_encodes_every_value(http_sms, monkeypatch):
    gateway, sent = http_sms
    monkeypatch.setattr(settings, "sms_http_method", "GET")
    monkeypatch.setattr(settings, "sms_http_url", "https://sms.example.mn/send?to={phone}&text={message}&key={api_key}")
    gateway(lambda request: httpx.Response(200)).send("+97699112233", "a & b")
    assert sent[0].url.params["text"] == "a & b"
    assert sent[0].url.params["to"] == "99112233"
    assert sent[0].content == b""


def test_http_sms_rejection_raises_without_leaking_the_key(http_sms):
    gateway, _ = http_sms
    with pytest.raises(RuntimeError) as error:
        gateway(lambda request: httpx.Response(401, text="bad key")).send("+97699112233", "Код 1234")
    assert "HTTP 401" in str(error.value)
    assert "key-123" not in str(error.value) and "1234" not in str(error.value)


def test_http_sms_requires_the_success_text_when_configured(http_sms, monkeypatch):
    gateway, _ = http_sms
    monkeypatch.setattr(settings, "sms_http_success_text", '"status":"SENT"')
    with pytest.raises(RuntimeError):
        gateway(lambda request: httpx.Response(200, text='{"status":"FAILED"}')).send("+97699112233", "hi")
    gateway(lambda request: httpx.Response(200, text='{"status":"SENT"}')).send("+97699112233", "hi")


def test_http_sms_network_failure_raises_a_retryable_error(http_sms):
    gateway, _ = http_sms

    def unreachable(request):
        raise httpx.ConnectError("boom", request=request)
    with pytest.raises(RuntimeError) as error:
        gateway(unreachable).send("+97699112233", "hi")
    assert "ConnectError" in str(error.value)


def test_sms_provider_selection(monkeypatch):
    monkeypatch.setattr(settings, "sms_provider", "http")
    assert isinstance(sms_provider(), HttpSmsProvider)
    monkeypatch.setattr(settings, "sms_provider", "console")
    assert not isinstance(sms_provider(), HttpSmsProvider)


# --- Settings: a broken provider config must fail at startup, not at first login ---


@pytest.mark.parametrize("overrides, message", [
    ({"sms_provider": "carrier-pigeon"}, "SMS_PROVIDER"),
    ({"sms_provider": "http"}, "SMS_HTTP_URL"),
    ({"sms_provider": "http", "sms_http_url": "https://x.mn", "sms_http_method": "PUT"}, "SMS_HTTP_METHOD"),
    ({"sms_provider": "http", "sms_http_url": "https://x.mn", "sms_http_body": "[1]"}, "SMS_HTTP_BODY"),
    ({"sms_provider": "http", "sms_http_url": "https://x.mn", "sms_http_headers": "{oops"}, "SMS_HTTP_HEADERS"),
    ({"sms_provider": "http", "sms_http_url": "https://x.mn", "sms_phone_format": "dots"}, "SMS_PHONE_FORMAT"),
    ({"alert_provider": "telegram"}, "TELEGRAM_BOT_TOKEN"),
])
def test_invalid_production_settings_are_rejected(overrides, message):
    with pytest.raises(ValueError) as error:
        Settings(jwt_secret=SECRET, **overrides)
    assert message in str(error.value)


def test_valid_http_sms_settings_are_accepted():
    value = Settings(jwt_secret=SECRET, sms_provider="http", sms_http_url="https://x.mn/send", sms_http_method="get",
                     sms_http_body='{"to": "{phone}"}')
    assert value.sms_http_method == "GET"


# --- Outbox: one failing message must not block the others ---


class FakePublisher:
    def __init__(self):
        self.published = []

    async def publish(self, channel, message):
        self.published.append(channel)


def row(kind, payload):
    return SimpleNamespace(kind=kind, payload=payload, delivered=False)


class FailingSms:
    def send(self, phone, message):
        raise RuntimeError("gateway down")


async def test_failing_sms_does_not_block_order_events(monkeypatch):
    monkeypatch.setattr(workers, "sms_provider", lambda: FailingSms())
    redis = FakePublisher()
    sms, event = row("sms", {"phone": "+97699112233", "message": "hi"}), row("event", {"order_id": "o-1", "status": "assigned"})
    await workers.process_outbox([sms, event], redis, clock=lambda: 1000)
    assert event.delivered and redis.published == ["order:o-1"]
    assert not sms.delivered
    assert sms.payload["_attempts"] == 1 and sms.payload["_retry_at"] == 1005
    assert sms.payload["phone"] == "+97699112233"


async def test_failed_messages_back_off_then_give_up(monkeypatch, caplog):
    monkeypatch.setattr(workers, "sms_provider", lambda: FailingSms())
    sms = row("sms", {"phone": "+97699112233", "message": "hi"})
    await workers.process_outbox([sms], FakePublisher(), clock=lambda: 1000)
    await workers.process_outbox([sms], FakePublisher(), clock=lambda: 1001)  # still backing off: not retried
    assert sms.payload["_attempts"] == 1
    clock = 1000.0
    with caplog.at_level(logging.WARNING):
        while not sms.delivered:
            clock = sms.payload["_retry_at"]
            await workers.process_outbox([sms], FakePublisher(), clock=lambda: clock)
    assert sms.payload["_attempts"] == workers.MAX_OUTBOX_ATTEMPTS
    assert any(record.levelno == logging.ERROR and "dropped" in record.getMessage() for record in caplog.records)


def test_retry_delay_is_capped():
    assert [workers.retry_delay(n) for n in (1, 2, 3)] == [5, 10, 20]
    assert workers.retry_delay(20) == 600


# --- Health and config ---


class FakeDb:
    def __init__(self, fail=False):
        self.fail = fail

    async def execute(self, statement):
        if self.fail:
            raise ConnectionError("db down")


async def test_full_health_reports_a_stale_worker(monkeypatch):
    fake = FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "redis", fake)
    response = await main_module.health_full(FakeDb())
    assert response.status_code == 503
    assert json.loads(response.body)["checks"] == {"database": "ok", "redis": "ok", "worker": "stale"}
    await fake.set(workers.HEARTBEAT_KEY, str(int(main_module.now().timestamp())))
    response = await main_module.health_full(FakeDb())
    assert response.status_code == 200 and json.loads(response.body)["status"] == "ok"
    response = await main_module.health_full(FakeDb(fail=True))
    assert json.loads(response.body)["checks"]["database"] == "down: ConnectionError"
    await fake.aclose()


async def test_config_tells_clients_whether_the_dev_login_code_works(monkeypatch):
    monkeypatch.setattr(settings, "sms_provider", "console")
    assert (await main_module.config())["dev_otp"] is True
    monkeypatch.setattr(settings, "sms_provider", "http")
    assert (await main_module.config())["dev_otp"] is False
