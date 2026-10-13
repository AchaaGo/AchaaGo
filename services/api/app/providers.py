import logging
import math
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from decimal import Decimal
import httpx
from fastapi import HTTPException
from .config import settings
from .sms import fill_json, fill_url, format_phone, mask_phone

log = logging.getLogger(__name__)


class SmsProvider(ABC):
    @abstractmethod
    def send(self, phone: str, message: str): ...


class ConsoleSmsProvider(SmsProvider):
    def send(self, phone, message):
        if settings.app_env == "production":
            raise RuntimeError("Console SMS is forbidden in production")
        log.warning("DEVELOPMENT SMS to %s: %s", phone, message)


class HttpSmsProvider(SmsProvider):
    """Any HTTP SMS gateway, described entirely by the SMS_HTTP_* settings.

    Raising on failure is the contract: the Celery task and the outbox both
    retry. Errors never include the URL or body, which carry the API key and,
    for OTPs, the code itself.
    """

    def __init__(self, client: httpx.Client | None = None):
        self.client = client

    def send(self, phone, message):
        values = {"phone": format_phone(phone, settings.sms_phone_format), "message": message,
                  "sender": settings.sms_sender, "api_key": settings.sms_api_key}
        headers = {key: str(value) for key, value in fill_json(settings.sms_http_headers or "{}", values).items()}
        options = {}
        if settings.sms_http_method == "POST" and settings.sms_http_body:
            options["json" if settings.sms_http_body_format == "json" else "data"] = fill_json(settings.sms_http_body, values)
        client = self.client or httpx.Client(timeout=10)
        try:
            response = client.request(settings.sms_http_method, fill_url(settings.sms_http_url, values),
                                      headers=headers, **options)
        except httpx.HTTPError as error:
            raise RuntimeError(f"SMS gateway unreachable ({type(error).__name__})") from None
        finally:
            if self.client is None:
                client.close()
        if not 200 <= response.status_code < 300 or (
                settings.sms_http_success_text and settings.sms_http_success_text not in response.text):
            raise RuntimeError(f"SMS gateway rejected the message to {mask_phone(phone)} (HTTP {response.status_code})")
        log.info("SMS sent to %s", mask_phone(phone))


def sms_provider() -> SmsProvider:
    return HttpSmsProvider() if settings.sms_provider == "http" else ConsoleSmsProvider()


@dataclass
class Route:
    distance_km: float
    duration_minutes: int
    polyline: str | None = None


def distance_km(a_lat, a_lng, b_lat, b_lng):
    rad = math.pi / 180
    dlat, dlng = (b_lat - a_lat) * rad, (b_lng - a_lng) * rad
    value = math.sin(dlat / 2) ** 2 + math.cos(a_lat * rad) * math.cos(b_lat * rad) * math.sin(dlng / 2) ** 2
    return 6371 * 2 * math.asin(min(1, math.sqrt(value)))


LANDMARKS = [
    {"id": "sukhbaatar", "address": "Сүхбаатарын талбай", "lat": 47.9186, "lng": 106.9177},
    {"id": "zaisan", "address": "Зайсан, Хан-Уул дүүрэг", "lat": 47.8832, "lng": 106.9157},
    {"id": "dragon", "address": "Драгон төв, Сонгинохайрхан", "lat": 47.9105, "lng": 106.8225},
    {"id": "narantuul", "address": "Нарантуул зах, Баянзүрх", "lat": 47.9044, "lng": 106.9493},
    {"id": "misheel", "address": "Мишээл экспо, Хан-Уул", "lat": 47.8909, "lng": 106.8827},
    {"id": "station", "address": "Улаанбаатар төмөр замын өртөө", "lat": 47.9088, "lng": 106.8831},
]


# httpx logs every request URL at INFO, and the Geocoding API takes its key in the URL.
logging.getLogger("httpx").setLevel(logging.WARNING)

# Customers read addresses in Mongolian, as the web's own Places search (language "mn") shows them.
PLACES_LANGUAGE = "mn"


class MapsProvider(ABC):
    @abstractmethod
    async def route(self, pickup, dropoff) -> Route: ...
    @abstractmethod
    async def search(self, text: str, session: str | None = None) -> list: ...
    @abstractmethod
    async def place(self, place_id: str, session: str | None = None) -> dict: ...
    @abstractmethod
    async def reverse(self, lat: float, lng: float) -> str: ...


class DemoMaps(MapsProvider):
    async def route(self, pickup, dropoff):
        km = round(distance_km(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng) * 1.3, 2)
        if km < 0.1:
            raise HTTPException(422, "ROUTE_TOO_SHORT")
        return Route(km, max(3, math.ceil(km * 3.5)))

    async def search(self, text, session=None):
        return [{"id": row["id"], "address": row["address"]} for row in LANDMARKS
                if text.casefold() in row["address"].casefold()][:6]

    async def place(self, place_id, session=None):
        for row in LANDMARKS:
            if row["id"] == place_id:
                return {key: row[key] for key in ("lat", "lng", "address")}
        raise HTTPException(404, "PLACE_NOT_FOUND")

    async def reverse(self, lat, lng):
        # No address database offline: clients label the point themselves, as they do when Google has none.
        raise HTTPException(404, "PLACE_NOT_FOUND")


class GoogleMaps(MapsProvider):
    def __init__(self, transport: httpx.AsyncBaseTransport | None = None):
        self.transport = transport  # tests inject httpx.MockTransport

    def client(self, timeout):
        return httpx.AsyncClient(timeout=timeout, transport=self.transport)

    async def route(self, pickup, dropoff):
        async with self.client(15) as client:
            result = await client.post("https://routes.googleapis.com/directions/v2:computeRoutes", headers={
                "X-Goog-Api-Key": settings.google_maps_api_key,
                "X-Goog-FieldMask": "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline"}, json={
                "origin": {"location": {"latLng": {"latitude": pickup.lat, "longitude": pickup.lng}}},
                "destination": {"location": {"latLng": {"latitude": dropoff.lat, "longitude": dropoff.lng}}},
                "travelMode": "DRIVE", "routingPreference": "TRAFFIC_AWARE"})
            result.raise_for_status()
        routes = result.json().get("routes", [])
        if not routes:
            raise HTTPException(422, "ROUTE_NOT_FOUND")
        route = routes[0]
        if route["distanceMeters"] < 100:
            raise HTTPException(422, "ROUTE_TOO_SHORT")
        return Route(round(route["distanceMeters"] / 1000, 3), max(1, math.ceil(float(route["duration"][:-1]) / 60)),
                     route.get("polyline", {}).get("encodedPolyline"))

    async def search(self, text, session=None):
        # The session token makes Google bill one typing session (every keystroke's suggestions, then the
        # chosen place's details) as a single request instead of one per keystroke.
        body = {"input": text, "languageCode": PLACES_LANGUAGE,
                "includedRegionCodes": ["mn"], "locationBias": {"circle": {"center": {
                    "latitude": 47.9186, "longitude": 106.9177}, "radius": 50000}}}
        if session:
            body["sessionToken"] = session
        async with self.client(10) as client:
            response = await client.post("https://places.googleapis.com/v1/places:autocomplete", headers={
                "X-Goog-Api-Key": settings.google_maps_api_key}, json=body)
            response.raise_for_status()
        return [{"id": row["placePrediction"]["placeId"], "address": row["placePrediction"]["text"]["text"]}
                for row in response.json().get("suggestions", []) if "placePrediction" in row]

    async def place(self, place_id, session=None):
        if not place_id.replace("_", "").replace("-", "").isalnum() or len(place_id) > 300:
            raise HTTPException(422, "PLACE_NOT_FOUND")
        params = {"languageCode": PLACES_LANGUAGE}
        if session:
            params["sessionToken"] = session  # ends the billing session the searches started
        async with self.client(10) as client:
            response = await client.get(
                f"https://places.googleapis.com/v1/places/{place_id}", params=params,
                headers={"X-Goog-Api-Key": settings.google_maps_api_key,
                         "X-Goog-FieldMask": "formattedAddress,location"})
            response.raise_for_status()
        row = response.json()
        return {"lat": row["location"]["latitude"], "lng": row["location"]["longitude"], "address": row["formattedAddress"]}

    async def reverse(self, lat, lng):
        async with self.client(10) as client:
            response = await client.get("https://maps.googleapis.com/maps/api/geocode/json", params={
                "latlng": f"{lat},{lng}", "language": PLACES_LANGUAGE, "key": settings.google_maps_api_key})
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as error:
                # The error text would carry the URL, and this API takes its key in the URL.
                raise httpx.HTTPError(f"Geocoding API answered HTTP {error.response.status_code}") from None
        data = response.json()
        results = data.get("results") or []
        if data.get("status") == "OK" and results and results[0].get("formatted_address"):
            return results[0]["formatted_address"]
        if data.get("status") not in ("OK", "ZERO_RESULTS"):
            # REQUEST_DENIED and similar mean the key or the Geocoding API is not set up: tell the operator.
            log.warning("Geocoding API answered %s", data.get("status"))
        raise HTTPException(404, "PLACE_NOT_FOUND")


def maps_provider():
    return GoogleMaps() if settings.maps_provider == "google" else DemoMaps()


class PaymentProvider(ABC):
    @abstractmethod
    async def invoice(self, order, callback_url) -> dict: ...
    @abstractmethod
    async def paid(self, invoice_id, amount) -> bool: ...


class DemoQPay(PaymentProvider):
    async def invoice(self, order, callback_url):
        return {"invoice_id": "demo-" + order.id, "qr_image": None, "urls": [], "demo": True}

    async def paid(self, invoice_id, amount):
        return False


QPAY_TOKEN_KEY = "qpay:token"


def token_ttl(expires_in, now: float) -> int:
    """Seconds to cache a QPay token. QPay sends expires_in as a Unix time, but accept a
    plain duration too; renew 5 minutes early, and keep at least one minute."""
    expires = int(expires_in or 0)
    remaining = expires - int(now) if expires > 1_000_000_000 else expires
    return max(60, min(remaining - 300, 12 * 3600))


class QPay(PaymentProvider):
    def __init__(self, transport: httpx.AsyncBaseTransport | None = None):
        self.transport = transport  # tests inject httpx.MockTransport

    def client(self, timeout):
        return httpx.AsyncClient(timeout=timeout, transport=self.transport)

    async def token(self, fresh=False):
        # One token for all calls until shortly before it expires: logging in on every
        # invoice and payment check doubled the calls and risked QPay's rate limits.
        from . import cache
        if not fresh:
            cached = await cache.redis.get(QPAY_TOKEN_KEY)
            if cached:
                return cached
        async with self.client(15) as client:
            result = await client.post(settings.qpay_base_url + "/v2/auth/token",
                                       auth=(settings.qpay_username, settings.qpay_password))
            result.raise_for_status()
        data = result.json()
        await cache.redis.set(QPAY_TOKEN_KEY, data["access_token"], ex=token_ttl(data.get("expires_in"), time.time()))
        return data["access_token"]

    async def post(self, path, payload, timeout):
        # A cached token QPay no longer accepts gets replaced once, then the call is retried.
        for fresh in (False, True):
            token = await self.token(fresh=fresh)
            async with self.client(timeout) as client:
                result = await client.post(settings.qpay_base_url + path, headers={"Authorization": f"Bearer {token}"},
                                           json=payload)
            if result.status_code != 401 or fresh:
                result.raise_for_status()
                return result.json()

    async def invoice(self, order, callback_url):
        return await self.post("/v2/invoice", {
            "invoice_code": settings.qpay_invoice_code, "sender_invoice_no": order.id,
            "invoice_receiver_code": order.customer_id, "invoice_description": settings.brand_name + " " + order.id[:8],
            "amount": order.total_price, "callback_url": callback_url}, 20)

    async def paid(self, invoice_id, amount):
        result = await self.post("/v2/payment/check", {"object_type": "INVOICE", "object_id": invoice_id,
                                                        "offset": {"page_number": 1, "page_limit": 100}}, 15)
        rows = result.get("rows", [])
        confirmed = sum((Decimal(str(row.get("payment_amount", 0))) for row in rows
                         if row.get("payment_status") == "PAID" and row.get("payment_currency") == "MNT"), Decimal(0))
        return confirmed == Decimal(amount)


def payment_provider():
    return QPay() if settings.qpay_provider == "qpay" else DemoQPay()
