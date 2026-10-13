import json
import logging
import re
from types import SimpleNamespace
import httpx
import pytest
from fakeredis.aioredis import FakeRedis
from fastapi import HTTPException
from app import cache
from app import main as main_module
from app.config import settings
from app.providers import DemoMaps, GoogleMaps

SESSION = "6f1c2b9e-4d3a-4b7e-9a10-2f5c8d7e1a33"


def google(monkeypatch, respond):
    monkeypatch.setattr(settings, "google_maps_api_key", "test-key")
    return GoogleMaps(httpx.MockTransport(respond))


@pytest.fixture
async def fake_redis(monkeypatch):
    fake = FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "redis", fake)
    yield fake
    await fake.aclose()


# --- Place search: Mongolian results, one billing session per typing session ---

def suggestions(request):
    return httpx.Response(200, json={"suggestions": [
        {"placePrediction": {"placeId": "ChIJabc_-1", "text": {"text": "Сүхбаатарын талбай, Улаанбаатар"}}},
        {"queryPrediction": {"text": {"text": "not a place"}}}]})


async def test_google_search_asks_for_mongolian_in_mongolia_with_the_session(monkeypatch):
    seen = []
    maps = google(monkeypatch, lambda request: (seen.append(request), suggestions(request))[1])
    assert await maps.search("Сүх", SESSION) == [{"id": "ChIJabc_-1", "address": "Сүхбаатарын талбай, Улаанбаатар"}]
    body = json.loads(seen[0].content)
    assert body["input"] == "Сүх"
    assert body["languageCode"] == "mn"
    assert body["includedRegionCodes"] == ["mn"]
    assert body["sessionToken"] == SESSION
    assert seen[0].headers["X-Goog-Api-Key"] == "test-key"


async def test_google_search_without_a_session_sends_no_token(monkeypatch):
    seen = []
    maps = google(monkeypatch, lambda request: (seen.append(request), suggestions(request))[1])
    await maps.search("Сүх")
    assert "sessionToken" not in json.loads(seen[0].content)


async def test_google_place_lookup_ends_the_session_and_asks_for_mongolian(monkeypatch):
    seen = []

    def respond(request):
        seen.append(request)
        return httpx.Response(200, json={"formattedAddress": "Сүхбаатарын талбай", "location": {"latitude": 47.9186, "longitude": 106.9177}})

    point = await google(monkeypatch, respond).place("ChIJabc_-1", SESSION)
    assert point == {"lat": 47.9186, "lng": 106.9177, "address": "Сүхбаатарын талбай"}
    assert seen[0].url.path == "/v1/places/ChIJabc_-1"
    assert seen[0].url.params["sessionToken"] == SESSION
    assert seen[0].url.params["languageCode"] == "mn"
    assert seen[0].headers["X-Goog-FieldMask"] == "formattedAddress,location"


async def test_google_place_lookup_without_a_session_sends_no_token(monkeypatch):
    seen = []

    def respond(request):
        seen.append(request)
        return httpx.Response(200, json={"formattedAddress": "Зайсан", "location": {"latitude": 47.88, "longitude": 106.91}})

    await google(monkeypatch, respond).place("ChIJabc_-1")
    assert "sessionToken" not in seen[0].url.params


async def test_google_place_lookup_rejects_an_id_that_is_not_a_place_id(monkeypatch):
    maps = google(monkeypatch, lambda request: pytest.fail("must not call Google"))
    with pytest.raises(HTTPException) as error:
        await maps.place("../../routes", SESSION)
    assert error.value.detail == "PLACE_NOT_FOUND"


def test_session_tokens_are_uuid_sized_and_url_safe():
    ok = lambda value: re.fullmatch(main_module.PLACE_SESSION_PATTERN, value) is not None  # noqa: E731
    assert ok(SESSION)
    assert ok("a" * 8) and ok("a" * 36)
    assert not ok("short") and not ok("a" * 37)
    assert not ok("has space in it") and not ok("../escape/../x") and not ok("tok&en=1234567")


# --- Reverse geocoding: the address of a tapped or GPS point ---

async def test_google_reverse_geocode_returns_the_first_formatted_address(monkeypatch):
    seen = []

    def respond(request):
        seen.append(request)
        return httpx.Response(200, json={"status": "OK", "results": [
            {"formatted_address": "Энхтайвны өргөн чөлөө 1, Улаанбаатар"}, {"formatted_address": "Улаанбаатар"}]})

    assert await google(monkeypatch, respond).reverse(47.9186, 106.9177) == "Энхтайвны өргөн чөлөө 1, Улаанбаатар"
    assert seen[0].url.params["latlng"] == "47.9186,106.9177"
    assert seen[0].url.params["language"] == "mn"
    assert seen[0].url.params["key"] == "test-key"


async def test_google_reverse_geocode_without_a_result_is_place_not_found(monkeypatch, caplog):
    maps = google(monkeypatch, lambda request: httpx.Response(200, json={"status": "ZERO_RESULTS", "results": []}))
    with caplog.at_level(logging.WARNING), pytest.raises(HTTPException) as error:
        await maps.reverse(48.5, 107.5)
    assert (error.value.status_code, error.value.detail) == (404, "PLACE_NOT_FOUND")
    assert "Geocoding API answered" not in caplog.text  # an empty steppe is normal, not a misconfiguration


async def test_google_reverse_geocode_with_a_refused_key_warns_the_operator(monkeypatch, caplog):
    maps = google(monkeypatch, lambda request: httpx.Response(200, json={"status": "REQUEST_DENIED", "results": []}))
    with caplog.at_level(logging.WARNING), pytest.raises(HTTPException) as error:
        await maps.reverse(47.9186, 106.9177)
    assert error.value.detail == "PLACE_NOT_FOUND"
    assert "Geocoding API answered REQUEST_DENIED" in caplog.text
    assert "test-key" not in caplog.text


async def test_google_reverse_geocode_http_failure_surfaces_as_a_provider_error_without_the_key(monkeypatch):
    maps = google(monkeypatch, lambda request: httpx.Response(500))
    with pytest.raises(httpx.HTTPError) as error:  # main.provider_error turns this into 503 PROVIDER_UNAVAILABLE
        await maps.reverse(47.9186, 106.9177)
    assert "500" in str(error.value)
    assert "test-key" not in str(error.value)  # the Geocoding API takes its key in the URL
    assert error.value.__cause__ is None and error.value.__suppress_context__


async def test_demo_maps_have_no_addresses_to_reverse():
    with pytest.raises(HTTPException) as error:
        await DemoMaps().reverse(47.9186, 106.9177)
    assert (error.value.status_code, error.value.detail) == (404, "PLACE_NOT_FOUND")


# --- Endpoints pass the session and the point through to the provider ---

class RecordingMaps:
    def __init__(self):
        self.calls = []

    async def search(self, text, session=None):
        self.calls.append(("search", text, session))
        return [{"id": "x", "address": "Сүхбаатарын талбай"}]

    async def place(self, place_id, session=None):
        self.calls.append(("place", place_id, session))
        return {"lat": 47.9, "lng": 106.9, "address": "Зайсан"}

    async def reverse(self, lat, lng):
        self.calls.append(("reverse", lat, lng))
        return "Зайсан, Хан-Уул дүүрэг"


async def test_place_endpoints_hand_the_session_to_the_provider(monkeypatch, fake_redis):
    maps = RecordingMaps()
    monkeypatch.setattr(main_module, "maps_provider", lambda: maps)
    user = SimpleNamespace(id="cust-1")
    assert await main_module.places(user, q="Сүх", session=SESSION) == [{"id": "x", "address": "Сүхбаатарын талбай"}]
    await main_module.place("ChIJabc", user, session=SESSION)
    await main_module.places(user, q="Сүх", session=None)
    assert maps.calls == [("search", "Сүх", SESSION), ("place", "ChIJabc", SESSION), ("search", "Сүх", None)]


async def test_geocode_endpoint_returns_the_address(monkeypatch, fake_redis):
    maps = RecordingMaps()
    monkeypatch.setattr(main_module, "maps_provider", lambda: maps)
    result = await main_module.reverse_geocode(SimpleNamespace(id="cust-1"), lat=47.9, lng=106.9)
    assert result == {"address": "Зайсан, Хан-Уул дүүрэг"}
    assert maps.calls == [("reverse", 47.9, 106.9)]


async def test_geocode_endpoint_is_rate_limited_per_customer(monkeypatch, fake_redis):
    monkeypatch.setattr(main_module, "maps_provider", lambda: RecordingMaps())
    user = SimpleNamespace(id="cust-1")
    for _ in range(60):
        await main_module.reverse_geocode(user, lat=47.9, lng=106.9)
    with pytest.raises(HTTPException) as error:
        await main_module.reverse_geocode(user, lat=47.9, lng=106.9)
    assert error.value.status_code == 429
    await main_module.reverse_geocode(SimpleNamespace(id="cust-2"), lat=47.9, lng=106.9)
