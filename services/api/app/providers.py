import logging
import math
from abc import ABC, abstractmethod
from dataclasses import dataclass
from decimal import Decimal
import httpx
from fastapi import HTTPException
from .config import settings

log = logging.getLogger(__name__)


class SmsProvider(ABC):
    @abstractmethod
    def send(self, phone: str, message: str): ...


class ConsoleSmsProvider(SmsProvider):
    def send(self, phone, message):
        if settings.app_env == "production":
            raise RuntimeError("Console SMS is forbidden in production")
        log.warning("DEVELOPMENT SMS to %s: %s", phone, message)


def sms_provider() -> SmsProvider:
    return ConsoleSmsProvider()


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


class MapsProvider(ABC):
    @abstractmethod
    async def route(self, pickup, dropoff) -> Route: ...
    @abstractmethod
    async def search(self, text: str) -> list: ...
    @abstractmethod
    async def place(self, place_id: str) -> dict: ...


class DemoMaps(MapsProvider):
    async def route(self, pickup, dropoff):
        km = round(distance_km(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng) * 1.3, 2)
        if km < 0.1:
            raise HTTPException(422, "ROUTE_TOO_SHORT")
        return Route(km, max(3, math.ceil(km * 3.5)))

    async def search(self, text):
        return [{"id": row["id"], "address": row["address"]} for row in LANDMARKS
                if text.casefold() in row["address"].casefold()][:6]

    async def place(self, place_id):
        for row in LANDMARKS:
            if row["id"] == place_id:
                return {key: row[key] for key in ("lat", "lng", "address")}
        raise HTTPException(404, "PLACE_NOT_FOUND")


class GoogleMaps(MapsProvider):
    async def route(self, pickup, dropoff):
        async with httpx.AsyncClient(timeout=15) as client:
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

    async def search(self, text):
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post("https://places.googleapis.com/v1/places:autocomplete", headers={
                "X-Goog-Api-Key": settings.google_maps_api_key}, json={"input": text,
                "includedRegionCodes": ["mn"], "locationBias": {"circle": {"center": {
                    "latitude": 47.9186, "longitude": 106.9177}, "radius": 50000}}})
            response.raise_for_status()
        return [{"id": row["placePrediction"]["placeId"], "address": row["placePrediction"]["text"]["text"]}
                for row in response.json().get("suggestions", []) if "placePrediction" in row]

    async def place(self, place_id):
        if not place_id.replace("_", "").replace("-", "").isalnum() or len(place_id) > 300:
            raise HTTPException(422, "PLACE_NOT_FOUND")
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"https://places.googleapis.com/v1/places/{place_id}", headers={
                "X-Goog-Api-Key": settings.google_maps_api_key,
                "X-Goog-FieldMask": "formattedAddress,location"})
            response.raise_for_status()
        row = response.json()
        return {"lat": row["location"]["latitude"], "lng": row["location"]["longitude"], "address": row["formattedAddress"]}


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


class QPay(PaymentProvider):
    async def token(self):
        async with httpx.AsyncClient(timeout=15) as client:
            result = await client.post(settings.qpay_base_url + "/v2/auth/token",
                                       auth=(settings.qpay_username, settings.qpay_password))
            result.raise_for_status()
        return result.json()["access_token"]

    async def invoice(self, order, callback_url):
        token = await self.token()
        async with httpx.AsyncClient(timeout=20) as client:
            result = await client.post(settings.qpay_base_url + "/v2/invoice", headers={"Authorization": f"Bearer {token}"}, json={
                "invoice_code": settings.qpay_invoice_code, "sender_invoice_no": order.id,
                "invoice_receiver_code": order.customer_id, "invoice_description": settings.brand_name + " " + order.id[:8],
                "amount": order.total_price, "callback_url": callback_url})
            result.raise_for_status()
        return result.json()

    async def paid(self, invoice_id, amount):
        token = await self.token()
        async with httpx.AsyncClient(timeout=15) as client:
            result = await client.post(settings.qpay_base_url + "/v2/payment/check", headers={"Authorization": f"Bearer {token}"},
                json={"object_type": "INVOICE", "object_id": invoice_id, "offset": {"page_number": 1, "page_limit": 100}})
            result.raise_for_status()
        rows = result.json().get("rows", [])
        confirmed = sum((Decimal(str(row.get("payment_amount", 0))) for row in rows
                         if row.get("payment_status") == "PAID" and row.get("payment_currency") == "MNT"), Decimal(0))
        return confirmed == Decimal(amount)


def payment_provider():
    return QPay() if settings.qpay_provider == "qpay" else DemoQPay()
