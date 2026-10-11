import json
import logging
import re
import time
from datetime import timedelta
from types import SimpleNamespace
import httpx
import pytest
from fakeredis.aioredis import FakeRedis
from fastapi import HTTPException
from fastapi.testclient import TestClient
from starlette.responses import Response
from app import cache, providers, workers
from app import main as main_module
from app import orders as orders_module
from app.models import now
from app.providers import QPay, Route, token_ttl
from app.schemas import OrderInput, QuoteInput, RefreshInput
from app.security import decode, digest, sign


class FakeResult:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


# --- Refresh: rotating the token must not log out a parallel or retried refresh ---


class FakeAuthDb:
    def __init__(self, session, user):
        self.session, self.user, self.added = session, user, []

    async def execute(self, statement):
        return FakeResult(self.session)

    async def get(self, model, key):
        return self.user

    def add(self, row):
        self.added.append(row)

    async def commit(self):
        pass


async def test_refresh_keeps_the_old_token_briefly_then_retires_it():
    session = SimpleNamespace(id=digest("tok"), user_id="u-1", expires_at=now() + timedelta(days=30))
    user = SimpleNamespace(id="u-1", phone="+97699112233", name=None, role="customer")
    db = FakeAuthDb(session, user)
    request = SimpleNamespace(cookies={})

    first = await main_module.refresh(RefreshInput(refresh_token="tok"), request, Response(), db)
    assert first["refresh_token"] != "tok"
    assert session.expires_at <= now() + main_module.REFRESH_GRACE
    # A second tab, or a retry after a lost response, still gets through inside the grace period...
    await main_module.refresh(RefreshInput(refresh_token="tok"), request, Response(), db)
    assert len(db.added) == 2
    # ...but the old token is dead once it has passed.
    session.expires_at = now() - timedelta(seconds=1)
    with pytest.raises(HTTPException) as error:
        await main_module.refresh(RefreshInput(refresh_token="tok"), request, Response(), db)
    assert (error.value.status_code, error.value.detail) == (401, "SESSION_EXPIRED")


# --- Orders charge exactly the quoted price ---


SERVICE = SimpleNamespace(id="svc-1", code="porter", name_mn="Портер", description_mn="Том ачаа", icon="truck",
                          base_fare=30000, per_km_rate=2000, is_active=True, sort_order=1)
PRICING = SimpleNamespace(loader_rate=25000, floor_rate=0, night_surcharge_pct=0, night_start=22, night_end=7)
ROUTE = {"pickup": {"lat": 47.9, "lng": 106.9, "address": "Авах хаяг"},
         "dropoff": {"lat": 47.92, "lng": 106.95, "address": "Хүргэх хаяг"}, "loaders": 0}


class FakeScalars:
    def __init__(self, rows):
        self.rows = rows

    def all(self):
        return self.rows


class FakeOrderDb:
    def __init__(self, service=SERVICE):
        self.service, self.added = service, []

    async def scalars(self, statement):
        return FakeScalars([self.service] if self.service.is_active else [])

    async def get(self, model, key):
        return PRICING if model.__name__ == "PricingSettings" else self.service

    async def execute(self, statement):
        return FakeResult(SimpleNamespace(id="cust-1"))

    async def scalar(self, statement):
        return None  # no idempotent replay, no active order

    def add(self, row):
        self.added.append(row)

    async def flush(self):
        for row in self.added:
            if type(row).__name__ == "Order" and row.id is None:
                row.id = "order-1"

    async def commit(self):
        pass


class ShiftingRouter:
    """Like traffic-aware routing: a slightly different distance on every call."""

    def __init__(self, step=0.4):
        self.calls, self.step = 0, step

    async def route(self, pickup, dropoff):
        self.calls += 1
        return Route(10.0 + self.calls * self.step, 30, "encoded-polyline")


async def make_quote(monkeypatch, router):
    monkeypatch.setattr(orders_module, "maps_provider", lambda: router)
    return await orders_module.quote(FakeOrderDb(), QuoteInput(**ROUTE))


def order_input(quote, **changes):
    values = {**ROUTE, "service_id": "svc-1", "payment_method": "cash",
              "expected_total": quote["prices"][0]["breakdown"]["total"], "quote_token": quote["quote_token"], **changes}
    return OrderInput(**values)


async def place(data, db=None):
    return await orders_module.create_order(db or FakeOrderDb(), data, SimpleNamespace(id="cust-1"), "cust-1", "key-12345678")


async def test_order_charges_the_quoted_price_without_routing_again(monkeypatch):
    router = ShiftingRouter()
    quote = await make_quote(monkeypatch, router)
    order = await place(order_input(quote))
    # The second call would have returned 10.8 km and 51,500₮ instead of 51,000₮.
    assert router.calls == 1
    assert order.total_price == quote["prices"][0]["breakdown"]["total"] == 51000
    assert (order.distance_km, order.route_polyline) == (quote["distance_km"], "encoded-polyline")
    assert order.price_breakdown == quote["prices"][0]["breakdown"]


@pytest.mark.parametrize("change", [
    {"quote_token": sign({"kind": "quote"}, -1)},   # expired while the customer was deciding
    {"quote_token": "not-a-token"},
    {"expected_total": 1},                           # tampered price
    {"loaders": 2},                                  # route or options changed after quoting
])
async def test_a_stale_or_tampered_quote_asks_for_a_new_price(monkeypatch, change):
    quote = await make_quote(monkeypatch, ShiftingRouter())
    with pytest.raises(HTTPException) as error:
        await place(order_input(quote, **change))
    # 409 QUOTE_CHANGED makes both apps re-price; the old 401 told customers to log in again.
    assert (error.value.status_code, error.value.detail) == (409, "QUOTE_CHANGED")


async def test_a_service_switched_off_after_quoting_asks_for_a_new_price(monkeypatch):
    quote = await make_quote(monkeypatch, ShiftingRouter())
    inactive = SimpleNamespace(**{**vars(SERVICE), "is_active": False})
    with pytest.raises(HTTPException) as error:
        await place(order_input(quote), FakeOrderDb(inactive))
    assert error.value.detail == "QUOTE_CHANGED"


async def test_quotes_issued_before_route_signing_are_priced_again(monkeypatch):
    router = ShiftingRouter(step=0)
    quote = await make_quote(monkeypatch, router)
    claims = decode(quote["quote_token"], "quote")
    legacy = sign({"kind": "quote", "route_hash": claims["route_hash"], "totals": claims["totals"]}, 300)
    order = await place(order_input(quote, quote_token=legacy))
    assert router.calls == 2
    assert order.total_price == quote["prices"][0]["breakdown"]["total"]


# --- QPay: one cached login token instead of a login per call ---


@pytest.fixture
async def fake_redis(monkeypatch):
    fake = FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "redis", fake)
    yield fake
    await fake.aclose()


def qpay_gateway(calls, reject_first_token=False):
    def respond(request):
        calls.append(request.url.path)
        if request.url.path == "/v2/auth/token":
            number = calls.count("/v2/auth/token")
            return httpx.Response(200, json={"access_token": f"tok-{number}", "expires_in": int(time.time()) + 86400})
        if reject_first_token and request.headers["Authorization"] == "Bearer tok-1":
            return httpx.Response(401)
        if request.url.path == "/v2/invoice":
            return httpx.Response(200, json={"invoice_id": "inv-1"})
        return httpx.Response(200, json={"rows": [{"payment_status": "PAID", "payment_currency": "MNT", "payment_amount": 46000}]})
    return QPay(httpx.MockTransport(respond))


async def test_qpay_logs_in_once_for_many_calls(fake_redis):
    calls = []
    qpay = qpay_gateway(calls)
    order = SimpleNamespace(id="order-12345678", customer_id="cust-1", total_price=46000)
    assert (await qpay.invoice(order, "https://achaago.mn/callback"))["invoice_id"] == "inv-1"
    assert await qpay.paid("inv-1", 46000)
    assert await qpay.paid("inv-1", 46000)
    assert calls.count("/v2/auth/token") == 1
    assert 0 < await fake_redis.ttl(providers.QPAY_TOKEN_KEY) <= 12 * 3600


async def test_qpay_replaces_a_token_it_no_longer_accepts(fake_redis):
    calls = []
    assert await qpay_gateway(calls, reject_first_token=True).paid("inv-1", 46000)
    assert calls == ["/v2/auth/token", "/v2/payment/check", "/v2/auth/token", "/v2/payment/check"]


def test_qpay_token_ttl_reads_unix_times_and_durations():
    issued = 1_700_000_000
    assert token_ttl(issued + 7200, issued) == 6900      # QPay's Unix-time expires_in
    assert token_ttl(3600, issued) == 3300               # a plain duration
    assert token_ttl(issued + 100, issued) == 60         # nearly expired: shortest cache
    assert token_ttl(None, issued) == 60
    assert token_ttl(issued + 10 ** 6, issued) == 12 * 3600


# --- Background jobs ---


def test_periodic_tasks_expire_instead_of_piling_up():
    schedule = workers.celery_app.conf.beat_schedule
    assert {"outbox", "pending-timeout", "cleanup"} <= set(schedule)
    for entry in schedule.values():
        assert 0 < entry["options"]["expires"] <= max(10, entry["schedule"])
    assert "achaago.cleanup" in workers.celery_app.tasks


# --- Request tracing ---


def test_every_response_carries_a_request_id():
    client = TestClient(main_module.app)
    generated = client.get("/config").headers["x-request-id"]
    assert re.fullmatch(r"[0-9a-f]{16}", generated)
    assert client.get("/config", headers={"X-Request-ID": "gateway-1234-abcd"}).headers["x-request-id"] == "gateway-1234-abcd"
    assert client.get("/config", headers={"X-Request-ID": "has spaces in it"}).headers["x-request-id"] != "has spaces in it"


async def test_unhandled_errors_report_the_request_id(caplog):
    request = SimpleNamespace(method="GET", url=SimpleNamespace(path="/orders"), state=SimpleNamespace(request_id="req-12345678"))
    with caplog.at_level(logging.ERROR):
        response = await main_module.unexpected_error(request, RuntimeError("boom"))
    assert response.status_code == 500
    assert json.loads(response.body) == {"detail": "SERVER_ERROR", "request_id": "req-12345678"}
    assert response.headers["x-request-id"] == "req-12345678"
    assert "req-12345678" in caplog.text
