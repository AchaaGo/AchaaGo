import hashlib
import json
import secrets
from datetime import timedelta, timezone
from fastapi import HTTPException
from sqlalchemy import select
from .config import settings
from .db import get_locked
from .models import Driver, Order, OrderEvent, Outbox, Payment, PricingSettings, Service, User, Vehicle, now, point_value
from .pricing import ACTIVE, TERMINAL, calculate_price, valid_transition
from .providers import maps_provider
from .security import decode, sign


def aware(value):
    return value.replace(tzinfo=timezone.utc) if value and value.tzinfo is None else value


def service_json(row):
    return {key: getattr(row, key) for key in ("id", "code", "name_mn", "description_mn", "icon", "base_fare", "per_km_rate", "is_active", "sort_order")}


def route_hash(data):
    normalized = {"pickup": data.pickup.model_dump(), "dropoff": data.dropoff.model_dump(), "loaders": data.loaders}
    return hashlib.sha256(json.dumps(normalized, sort_keys=True).encode()).hexdigest()


async def quote(db, data):
    route = await maps_provider().route(data.pickup, data.dropoff)
    services = (await db.scalars(select(Service).where(Service.is_active.is_(True)).order_by(Service.sort_order))).all()
    pricing = await db.get(PricingSettings, 1)
    prices = [{"service": service_json(service), "breakdown": calculate_price(service, pricing, route.distance_km, data.loaders, now())} for service in services]
    return {"distance_km": route.distance_km, "duration_minutes": route.duration_minutes, "polyline": route.polyline,
            "prices": prices, "loader_rate": pricing.loader_rate, "approximate": settings.maps_provider == "demo",
            "quote_token": sign({"kind": "quote", "route_hash": route_hash(data), "totals": {p["service"]["id"]: p["breakdown"]["total"] for p in prices}}, 300)}


def record(db, order, status, actor, reason=None):
    order.status, order.updated_at = status, now()
    db.add(OrderEvent(order_id=order.id, status=status, actor=actor, reason=reason))
    db.add(Outbox(kind="event", payload={"order_id": order.id, "type": "status", "status": status}))


async def create_order(db, data, customer, actor, key):
    request_hash = hashlib.sha256(json.dumps(data.model_dump(exclude={"quote_token", "customer_phone"}), sort_keys=True).encode()).hexdigest()
    await get_locked(db, User, customer.id)
    existing = await db.scalar(select(Order).where(Order.customer_id == customer.id, Order.idempotency_key == key))
    if existing:
        if existing.request_hash != request_hash:
            raise HTTPException(409, "IDEMPOTENCY_CONFLICT")
        return existing
    if await db.scalar(select(Order.id).where(Order.customer_id == customer.id, Order.status.in_(ACTIVE)).limit(1)):
        raise HTTPException(409, "ACTIVE_ORDER_EXISTS")
    token = decode(data.quote_token, "quote")
    if token.get("route_hash") != route_hash(data) or token.get("totals", {}).get(data.service_id) != data.expected_total:
        raise HTTPException(409, "QUOTE_CHANGED")
    fresh = await quote(db, data)
    selected = next((p for p in fresh["prices"] if p["service"]["id"] == data.service_id), None)
    if not selected or selected["breakdown"]["total"] != data.expected_total:
        raise HTTPException(409, "QUOTE_CHANGED")
    order = Order(customer_id=customer.id, service_id=data.service_id,
                  pickup_lat=data.pickup.lat, pickup_lng=data.pickup.lng, pickup_address=data.pickup.address,
                  dropoff_lat=data.dropoff.lat, dropoff_lng=data.dropoff.lng, dropoff_address=data.dropoff.address,
                  pickup_point=point_value(data.pickup.lat, data.pickup.lng), dropoff_point=point_value(data.dropoff.lat, data.dropoff.lng),
                  distance_km=fresh["distance_km"], duration_minutes=fresh["duration_minutes"], route_polyline=fresh["polyline"],
                  loaders=data.loaders, payment_method=data.payment_method, price_breakdown=selected["breakdown"],
                  total_price=selected["breakdown"]["total"], tracking_token=secrets.token_urlsafe(32),
                  idempotency_key=key, request_hash=request_hash)
    db.add(order)
    await db.flush()
    db.add(Payment(order_id=order.id, provider=data.payment_method, amount=order.total_price))
    record(db, order, "pending", actor)
    await db.commit()
    return order


async def driver_for_user(db, user, approved=True):
    driver = await db.scalar(select(Driver).where(Driver.user_id == user.id))
    if not driver or (approved and driver.status != "approved"):
        raise HTTPException(403, "DRIVER_NOT_APPROVED")
    return driver


async def get_order(db, order_id, user, locked=False):
    order = await get_locked(db, Order, order_id) if locked else await db.get(Order, order_id)
    if not order:
        raise HTTPException(404, "ORDER_NOT_FOUND")
    if user.role in {"admin", "dispatcher"} or order.customer_id == user.id:
        return order
    driver = await db.scalar(select(Driver).where(Driver.user_id == user.id, Driver.status == "approved"))
    if driver and order.driver_id == driver.id:
        return order
    raise HTTPException(404, "ORDER_NOT_FOUND")


async def order_json(db, order, public=False):
    service = await db.get(Service, order.service_id)
    result = {"id": order.id, "status": order.status, "service_name": order.price_breakdown.get("service_name", service.name_mn),
              "pickup": {"lat": order.pickup_lat, "lng": order.pickup_lng, "address": order.pickup_address},
              "dropoff": {"lat": order.dropoff_lat, "lng": order.dropoff_lng, "address": order.dropoff_address},
              "distance_km": order.distance_km, "duration_minutes": order.duration_minutes, "polyline": order.route_polyline,
              "updated_at": aware(order.updated_at).isoformat(), "created_at": aware(order.created_at).isoformat(), "driver": None}
    if order.driver_id:
        driver = await db.get(Driver, order.driver_id)
        user = await db.get(User, driver.user_id)
        vehicle = await db.scalar(select(Vehicle).where(Vehicle.driver_id == driver.id))
        recent = driver.last_seen and now() - aware(driver.last_seen) < timedelta(seconds=90)
        result["driver"] = {"name": user.name, "rating": driver.rating, "plate_number": vehicle.plate_number if vehicle else None,
                            "location": {"lat": driver.last_lat, "lng": driver.last_lng} if recent and order.status not in TERMINAL else None,
                            "location_fresh": bool(recent), "last_seen": aware(driver.last_seen).isoformat() if driver.last_seen else None}
        if not public:
            result["driver"].update({"id": driver.id, "phone": user.phone})
    if not public:
        payment = await db.scalar(select(Payment).where(Payment.order_id == order.id))
        result.update({"service_id": order.service_id, "loaders": order.loaders, "payment_method": order.payment_method,
                       "payment_status": payment.status if payment else "pending", "price_breakdown": order.price_breakdown,
                       "total_price": order.total_price, "tracking_token": order.tracking_token, "rating": order.rating,
                       "can_cancel": order.status in settings.customer_cancel_statuses.split(",") and valid_transition(order.status, "cancelled")})
    return result


async def change_status(db, order, target, actor, reason=None):
    if not valid_transition(order.status, target):
        raise HTTPException(409, "INVALID_STATUS_TRANSITION")
    payment = await db.scalar(select(Payment).where(Payment.order_id == order.id))
    if target == "completed" and (not payment or payment.status != "paid"):
        raise HTTPException(409, "PAYMENT_REQUIRED")
    record(db, order, target, actor, reason)
    if target in {"assigned", "arrived"}:
        customer = await db.get(User, order.customer_id)
        driver = await db.get(Driver, order.driver_id)
        person = await db.get(User, driver.user_id)
        vehicle = await db.scalar(select(Vehicle).where(Vehicle.driver_id == driver.id))
        message = (f"Жолооч {person.name or ''}, {vehicle.plate_number}. " if target == "assigned" else "Жолооч ирлээ. ")
        db.add(Outbox(kind="sms", payload={"phone": customer.phone, "message": message + settings.public_url + "/t/" + order.tracking_token}))
    if target == "assigned":
        driver = await db.get(Driver, order.driver_id)
        if driver.fcm_token:
            db.add(Outbox(kind="push", payload={"token": driver.fcm_token, "order_id": order.id}))
    if target == "delivered" and payment and payment.status == "paid":
        record(db, order, "completed", actor)


async def assign(db, order_id, driver_id, actor):
    order = await get_locked(db, Order, order_id)
    if not order:
        raise HTTPException(404, "ORDER_NOT_FOUND")
    if order.status != "pending":
        raise HTTPException(409, "ORDER_ALREADY_ASSIGNED")
    driver = await get_locked(db, Driver, driver_id)
    if not driver or driver.status != "approved" or not driver.is_online or not driver.last_seen or now() - aware(driver.last_seen) > timedelta(seconds=90):
        raise HTTPException(409, "DRIVER_UNAVAILABLE")
    vehicle = await db.scalar(select(Vehicle).where(Vehicle.driver_id == driver.id))
    if not vehicle or vehicle.service_id != order.service_id:
        raise HTTPException(409, "VEHICLE_MISMATCH")
    if await db.scalar(select(Order.id).where(Order.driver_id == driver.id, Order.status.in_(ACTIVE)).limit(1)):
        raise HTTPException(409, "DRIVER_BUSY")
    order.driver_id = driver.id
    await change_status(db, order, "assigned", actor)
    await db.commit()
    return order
