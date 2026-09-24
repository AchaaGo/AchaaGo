import asyncio
import hmac
import json
import logging
import secrets
from contextlib import asynccontextmanager
from datetime import timedelta
from typing import Annotated
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
import httpx
from redis.exceptions import RedisError
from . import cache
from .config import settings
from .db import Session, engine, get_db, get_locked
from .models import Driver, Order, OrderEvent, Outbox, Payment, PricingSettings, RefreshSession, Service, User, Vehicle, IS_POSTGRES, now, point_value
from .orders import assign, aware, change_status, create_order, driver_for_user, get_order, order_json, quote, service_json
from .pricing import ACTIVE, TERMINAL, valid_transition
from .providers import distance_km, maps_provider, payment_provider
from .schemas import (AssignInput, CancelInput, DriverApproval, DriverLocation, DriverRegistration, InvoiceInput, OrderInput,
                      OTPVerify, Phone, PhoneOrder, PricingInput, PushToken, QuoteInput, RatingInput, RefreshInput, ServiceInput, StatusInput)
from .security import admin, current_user, decode, digest, find_user, issue_tokens, staff, user_json
from .workers import send_sms

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app):
    yield
    await cache.redis.aclose()
    await engine.dispose()


app = FastAPI(title=settings.brand_name + " API", lifespan=lifespan,
              docs_url="/docs" if settings.app_env != "production" else None, redoc_url=None)
DB = Annotated[object, Depends(get_db)]
Customer = Annotated[User, Depends(current_user)]
Staff = Annotated[User, Depends(staff)]
Admin = Annotated[User, Depends(admin)]


@app.middleware("http")
async def guard_origin(request: Request, call_next):
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        origin = request.headers.get("origin")
        cookie_auth = request.cookies.get("ag_access") or request.cookies.get("ag_refresh")
        if (origin and origin != settings.public_url.rstrip("/")) or (cookie_auth and not origin and not request.headers.get("authorization")):
            return JSONResponse({"detail": "ORIGIN_NOT_ALLOWED"}, status_code=403)
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.exception_handler(RequestValidationError)
async def invalid_input(request, exc):
    return JSONResponse({"detail": "INVALID_INPUT", "fields": [".".join(map(str, e["loc"][1:])) for e in exc.errors()]}, status_code=422)


@app.exception_handler(IntegrityError)
async def integrity_error(request, exc):
    return JSONResponse({"detail": "CONFLICT"}, status_code=409)


@app.exception_handler(httpx.HTTPError)
async def provider_error(request, exc):
    log.error("Provider request failed (%s)", type(exc).__name__)
    return JSONResponse({"detail": "PROVIDER_UNAVAILABLE"}, status_code=503)


@app.exception_handler(RedisError)
async def cache_error(request, exc):
    return JSONResponse({"detail": "SERVICE_UNAVAILABLE"}, status_code=503)


@app.get("/health")
async def health(db: DB):
    await db.execute(text("SELECT 1"))
    await cache.redis.ping()
    return {"status": "ok"}


@app.get("/config")
async def config():
    return {"brand_name": settings.brand_name, "demo": settings.app_env != "production",
            "maps_provider": settings.maps_provider, "qpay_provider": settings.qpay_provider,
            "customer_cancel_statuses": settings.customer_cancel_statuses.split(",")}


def client_ip(request):
    # Only the dedicated gateway writes this header; API has no published port.
    return request.headers.get("x-real-ip", request.client.host if request.client else "unknown")


@app.post("/auth/otp/request")
async def otp_request(data: Phone, request: Request):
    code = await cache.request_otp(data.phone, client_ip(request))
    message = f"{settings.brand_name}: Таны баталгаажуулах код {code}. 5 минутын дотор ашиглана уу."
    try:
        await asyncio.to_thread(send_sms.apply_async, args=[data.phone, message], expires=120)
    except Exception:
        log.error("Unable to enqueue OTP")
        raise HTTPException(503, "SMS_UNAVAILABLE") from None
    return {"sent": True, "retry_after": 60}


@app.post("/auth/otp/verify")
async def otp_verify(data: OTPVerify, request: Request, response: Response, db: DB):
    if not (settings.sms_provider == "console" and data.code == "00"):
        await cache.verify_otp(data.phone, data.code, client_ip(request))
    user = await find_user(db, data.phone)
    if not user:
        user = User(phone=data.phone)
        db.add(user)
        await db.flush()
    result = await issue_tokens(db, user, response)
    await db.commit()
    return result


@app.post("/auth/refresh")
async def refresh(data: RefreshInput, request: Request, response: Response, db: DB):
    token = data.refresh_token or request.cookies.get("ag_refresh", "")
    session = await get_locked(db, RefreshSession, digest(token)) if token else None
    if not session or aware(session.expires_at) <= now():
        raise HTTPException(401, "SESSION_EXPIRED")
    user = await db.get(User, session.user_id)
    await db.delete(session)
    result = await issue_tokens(db, user, response)
    await db.commit()
    return result


@app.post("/auth/logout")
async def logout(data: RefreshInput, request: Request, response: Response, db: DB):
    token = data.refresh_token or request.cookies.get("ag_refresh", "")
    session = await db.get(RefreshSession, digest(token)) if token else None
    if session:
        await db.delete(session)
        await db.commit()
    response.delete_cookie("ag_access", path="/")
    response.delete_cookie("ag_refresh", path="/api/auth")
    return {"ok": True}


@app.get("/auth/me")
async def me(user: Customer):
    return user_json(user)


@app.get("/services")
async def services(db: DB):
    return [service_json(row) for row in (await db.scalars(select(Service).where(Service.is_active.is_(True)).order_by(Service.sort_order))).all()]


@app.get("/places")
async def places(user: Customer, q: str = Query(default="", max_length=150)):
    await cache.limit("places:" + user.id, 120, 60)
    return await maps_provider().search(q)


@app.get("/places/{place_id}")
async def place(place_id: str, user: Customer):
    await cache.limit("place:" + user.id, 60, 60)
    return await maps_provider().place(place_id)


@app.post("/quotes")
async def quotes(data: QuoteInput, user: Customer, db: DB):
    await cache.limit("quote:" + user.id, 60, 60)
    return await quote(db, data)


@app.post("/orders", status_code=201)
async def order_create(data: OrderInput, user: Customer, db: DB,
                       idempotency_key: str = Header(min_length=8, max_length=64)):
    await cache.limit("order:" + user.id, 10, 600)
    order = await create_order(db, data, user, user.id, idempotency_key)
    return await order_json(db, order)


@app.get("/orders")
async def my_orders(user: Customer, db: DB, offset: int = Query(default=0, ge=0, le=100000)):
    orders = (await db.scalars(select(Order).where(Order.customer_id == user.id).order_by(Order.created_at.desc()).offset(offset).limit(50))).all()
    return [await order_json(db, order) for order in orders]


@app.get("/orders/{order_id}")
async def order_detail(order_id: str, user: Customer, db: DB):
    return await order_json(db, await get_order(db, order_id, user))


@app.post("/orders/{order_id}/cancel")
async def cancel(order_id: str, data: CancelInput, user: Customer, db: DB):
    order = await get_order(db, order_id, user, locked=True)
    if order.customer_id != user.id:
        raise HTTPException(403, "FORBIDDEN")
    if order.status not in settings.customer_cancel_statuses.split(",") or not valid_transition(order.status, "cancelled"):
        raise HTTPException(409, "CANCELLATION_UNAVAILABLE")
    payment = await db.scalar(select(Payment).where(Payment.order_id == order.id))
    if payment and payment.status == "paid":
        raise HTTPException(409, "REFUND_REQUIRES_DISPATCHER")
    await change_status(db, order, "cancelled", user.id, data.reason)
    await db.commit()
    return await order_json(db, order)


@app.post("/orders/{order_id}/rating")
async def rate_order(order_id: str, data: RatingInput, user: Customer, db: DB):
    order = await get_order(db, order_id, user, locked=True)
    if order.customer_id != user.id or order.status != "completed" or order.rating is not None:
        raise HTTPException(409, "RATING_UNAVAILABLE")
    driver = await get_locked(db, Driver, order.driver_id)
    order.rating = data.rating
    await db.flush()
    driver.rating = float(await db.scalar(select(func.avg(Order.rating)).where(Order.driver_id == driver.id, Order.rating.is_not(None))))
    await db.commit()
    return await order_json(db, order)


@app.get("/t/{token}")
async def public_tracking(token: str, request: Request, db: DB):
    await cache.limit("tracking:" + digest(client_ip(request)), 120, 60)
    order = await db.scalar(select(Order).where(Order.tracking_token == token))
    if not order or (order.status in TERMINAL and now() - aware(order.updated_at) > timedelta(days=1)):
        raise HTTPException(404, "TRACKING_EXPIRED")
    return await order_json(db, order, public=True)


@app.get("/admin/orders")
async def admin_orders(user: Staff, db: DB, status: str | None = None, offset: int = Query(default=0, ge=0, le=100000)):
    query = select(Order).order_by(Order.created_at.desc()).offset(offset).limit(100)
    if status:
        query = query.where(Order.status == status)
    return [await order_json(db, row) for row in (await db.scalars(query)).all()]


@app.get("/admin/orders/{order_id}")
async def admin_order(order_id: str, user: Staff, db: DB):
    order = await get_order(db, order_id, user)
    events = (await db.scalars(select(OrderEvent).where(OrderEvent.order_id == order.id).order_by(OrderEvent.created_at))).all()
    customer = await db.get(User, order.customer_id)
    return {**await order_json(db, order), "customer": user_json(customer), "events": [
        {"id": event.id, "status": event.status, "actor": event.actor, "reason": event.reason, "created_at": aware(event.created_at).isoformat()} for event in events]}


@app.post("/admin/orders")
async def admin_create(data: PhoneOrder, user: Staff, db: DB, idempotency_key: str = Header(min_length=8, max_length=64)):
    customer = await find_user(db, data.customer_phone)
    if not customer:
        customer = User(phone=data.customer_phone)
        db.add(customer)
        await db.flush()
    return await order_json(db, await create_order(db, data, customer, user.id, idempotency_key))


@app.post("/admin/orders/{order_id}/assign")
async def assign_order(order_id: str, data: AssignInput, user: Staff, db: DB):
    return await order_json(db, await assign(db, order_id, data.driver_id, user.id))


@app.post("/admin/orders/{order_id}/status")
async def admin_status(order_id: str, data: StatusInput, user: Staff, db: DB):
    order = await get_order(db, order_id, user, locked=True)
    if data.status == "cancelled":
        if not data.reason:
            raise HTTPException(422, "REASON_REQUIRED")
        payment = await db.scalar(select(Payment).where(Payment.order_id == order.id))
        if payment.status == "paid":
            raise HTTPException(409, "REFUND_NOT_IMPLEMENTED")
    await change_status(db, order, data.status, user.id, data.reason)
    await db.commit()
    return await order_json(db, order)


@app.get("/admin/drivers")
async def admin_drivers(user: Staff, db: DB, order_id: str | None = None):
    order = await db.get(Order, order_id) if order_id else None
    rows = (await db.execute(select(Driver, User, Vehicle).join(User, Driver.user_id == User.id).join(Vehicle, Vehicle.driver_id == Driver.id))).all()
    result = []
    for driver, person, vehicle in rows:
        recent = driver.last_seen and now() - aware(driver.last_seen) < timedelta(seconds=90)
        busy = bool(await db.scalar(select(Order.id).where(Order.driver_id == driver.id, Order.status.in_(ACTIVE)).limit(1)))
        distance = None
        if order and driver.last_lat is not None:
            if IS_POSTGRES:
                metres = await db.scalar(select(func.ST_DistanceSphere(Driver.last_point, Order.pickup_point)).where(Driver.id == driver.id, Order.id == order.id))
                distance = round(metres / 1000, 2) if metres is not None else None
            else:
                distance = round(distance_km(order.pickup_lat, order.pickup_lng, driver.last_lat, driver.last_lng), 2)
        result.append({"id": driver.id, "name": person.name, "phone": person.phone, "status": driver.status,
                       "is_online": driver.is_online, "location_fresh": bool(recent), "busy": busy,
                       "service_id": vehicle.service_id, "plate_number": vehicle.plate_number, "model": vehicle.model,
                       "capacity_kg": vehicle.capacity_kg, "distance_km": distance, "license_info": driver.license_info,
                       "location": {"lat": driver.last_lat, "lng": driver.last_lng} if recent else None,
                       "eligible": bool(driver.status == "approved" and driver.is_online and recent and not busy and (not order or order.service_id == vehicle.service_id))})
    return sorted(result, key=lambda row: (not row["eligible"], row["distance_km"] if row["distance_km"] is not None else float("inf")))


@app.patch("/admin/drivers/{driver_id}")
async def approve_driver(driver_id: str, data: DriverApproval, user: Admin, db: DB):
    driver = await get_locked(db, Driver, driver_id)
    if not driver:
        raise HTTPException(404, "DRIVER_NOT_FOUND")
    if data.status != "approved" and await db.scalar(select(Order.id).where(Order.driver_id == driver.id, Order.status.in_(ACTIVE)).limit(1)):
        raise HTTPException(409, "DRIVER_BUSY")
    driver.status = data.status
    if data.status != "approved":
        driver.is_online = False
        await cache.redis.zrem("drivers:geo", driver.id)
    await db.commit()
    return {"ok": True}


@app.get("/admin/services")
async def admin_services(user: Staff, db: DB):
    return [service_json(row) for row in (await db.scalars(select(Service).order_by(Service.sort_order))).all()]


@app.post("/admin/services", status_code=201)
async def add_service(data: ServiceInput, user: Admin, db: DB):
    service = Service(**data.model_dump())
    db.add(service)
    await db.commit()
    return service_json(service)


@app.put("/admin/services/{service_id}")
async def edit_service(service_id: str, data: ServiceInput, user: Admin, db: DB):
    service = await get_locked(db, Service, service_id)
    if not service:
        raise HTTPException(404, "SERVICE_NOT_FOUND")
    for key, value in data.model_dump().items():
        setattr(service, key, value)
    await db.commit()
    return service_json(service)


@app.delete("/admin/services/{service_id}")
async def deactivate_service(service_id: str, user: Admin, db: DB):
    service = await get_locked(db, Service, service_id)
    if not service:
        raise HTTPException(404, "SERVICE_NOT_FOUND")
    service.is_active = False
    await db.commit()
    return {"ok": True}


@app.get("/admin/pricing")
async def get_pricing(user: Staff, db: DB):
    pricing = await db.get(PricingSettings, 1)
    return {key: getattr(pricing, key) for key in PricingInput.model_fields}


@app.put("/admin/pricing")
async def edit_pricing(data: PricingInput, user: Admin, db: DB):
    pricing = await get_locked(db, PricingSettings, 1)
    for key, value in data.model_dump().items():
        setattr(pricing, key, value)
    await db.commit()
    return data


@app.post("/driver/register", status_code=201)
async def register_driver(data: DriverRegistration, user: Customer, db: DB):
    if user.role != "customer" or await db.scalar(select(Driver.id).where(Driver.user_id == user.id)):
        raise HTTPException(409, "DRIVER_ALREADY_REGISTERED")
    service = await db.get(Service, data.service_id)
    if not service or not service.is_active:
        raise HTTPException(422, "SERVICE_NOT_FOUND")
    user.name, user.role = data.name, "driver"
    driver = Driver(user_id=user.id, license_info=data.license_info)
    db.add(driver)
    await db.flush()
    db.add(Vehicle(driver_id=driver.id, service_id=data.service_id, plate_number=data.plate_number,
                   model=data.model, capacity_kg=data.capacity_kg))
    await db.commit()
    return {"status": "pending"}


@app.get("/driver/me")
async def driver_me(user: Customer, db: DB):
    driver = await driver_for_user(db, user, approved=False)
    vehicle = await db.scalar(select(Vehicle).where(Vehicle.driver_id == driver.id))
    return {"id": driver.id, "status": driver.status, "is_online": driver.is_online, "rating": driver.rating,
            "name": user.name, "plate_number": vehicle.plate_number, "service_id": vehicle.service_id}


@app.post("/driver/online")
async def online(data: DriverLocation, user: Customer, db: DB):
    driver = await driver_for_user(db, user)
    driver = await get_locked(db, Driver, driver.id)
    driver.is_online = True
    return await update_location(data, user, db)


@app.post("/driver/offline")
async def offline(user: Customer, db: DB):
    driver = await driver_for_user(db, user, approved=False)
    driver = await get_locked(db, Driver, driver.id)
    if await db.scalar(select(Order.id).where(Order.driver_id == driver.id, Order.status.in_(ACTIVE)).limit(1)):
        raise HTTPException(409, "ACTIVE_ORDER_EXISTS")
    driver.is_online = False
    await cache.redis.zrem("drivers:geo", driver.id)
    await db.commit()
    return {"ok": True}


@app.post("/driver/location")
async def update_location(data: DriverLocation, user: Customer, db: DB):
    driver = await driver_for_user(db, user)
    if not driver.is_online:
        raise HTTPException(409, "DRIVER_OFFLINE")
    await cache.limit("location:" + driver.id, 40, 60)
    driver.last_lat, driver.last_lng, driver.last_seen = data.lat, data.lng, now()
    driver.last_point = point_value(data.lat, data.lng)
    await db.commit()
    await cache.redis.geoadd("drivers:geo", [data.lng, data.lat, driver.id])
    await cache.redis.set("driver:seen:" + driver.id, "1", ex=90)
    order_ids = (await db.scalars(select(Order.id).where(Order.driver_id == driver.id, Order.status.in_(ACTIVE)))).all()
    for order_id in order_ids:
        await cache.redis.publish("order:" + order_id, json.dumps({"type": "location", "order_id": order_id}))
    return {"ok": True}


@app.post("/driver/push-token")
async def push_token(data: PushToken, user: Customer, db: DB):
    driver = await driver_for_user(db, user)
    driver.fcm_token = data.token
    await db.commit()
    return {"ok": True}


@app.get("/driver/offers")
async def driver_offers(user: Customer, db: DB):
    driver = await driver_for_user(db, user)
    rows = (await db.scalars(select(Order).where(Order.driver_id == driver.id, Order.status.in_(ACTIVE)).order_by(Order.created_at))).all()
    return [await order_json(db, order) for order in rows]


@app.post("/driver/orders/{order_id}/accept")
async def accept(order_id: str, user: Customer, db: DB):
    return await driver_status(order_id, StatusInput(status="driver_arriving"), user, db)


@app.post("/driver/orders/{order_id}/status")
async def driver_status(order_id: str, data: StatusInput, user: Customer, db: DB):
    driver = await driver_for_user(db, user)
    order = await get_order(db, order_id, user, locked=True)
    if order.driver_id != driver.id or data.status not in {"driver_arriving", "arrived", "picked_up", "delivered", "completed"}:
        raise HTTPException(403, "FORBIDDEN")
    await change_status(db, order, data.status, user.id)
    await db.commit()
    return await order_json(db, order)


@app.post("/orders/{order_id}/cash-received")
async def cash_received(order_id: str, user: Customer, db: DB):
    order = await get_order(db, order_id, user, locked=True)
    driver = await db.scalar(select(Driver).where(Driver.user_id == user.id, Driver.status == "approved"))
    if user.role not in {"admin", "dispatcher"} and (not driver or order.driver_id != driver.id):
        raise HTTPException(403, "FORBIDDEN")
    if order.payment_method != "cash" or order.status not in {"delivered", "completed"}:
        raise HTTPException(409, "CASH_CONFIRMATION_UNAVAILABLE")
    payment = await db.scalar(select(Payment).where(Payment.order_id == order.id).with_for_update())
    payment.status = "paid"
    if order.status == "delivered":
        await change_status(db, order, "completed", user.id)
    await db.commit()
    return await order_json(db, order)


@app.post("/payments/qpay/invoice")
async def invoice(data: InvoiceInput, user: Customer, db: DB):
    return await ensure_invoice(data.order_id, user, db)


async def ensure_invoice(order_id, user, db):
    order = await get_order(db, order_id, user, locked=True)
    if order.customer_id != user.id or order.payment_method != "qpay" or order.status in {"cancelled", "no_driver_found"}:
        raise HTTPException(409, "PAYMENT_UNAVAILABLE")
    payment = await db.scalar(select(Payment).where(Payment.order_id == order.id).with_for_update())
    if not payment.provider_invoice_id:
        payment.callback_secret = secrets.token_urlsafe(32)
        callback = settings.public_url + "/api/payments/qpay/webhook?payment_id=" + payment.id + "&token=" + payment.callback_secret
        data = await payment_provider().invoice(order, callback)
        payment.provider_invoice_id, payment.invoice_data = data["invoice_id"], data
        await db.commit()
    return {"status": payment.status, "amount": payment.amount, **payment.invoice_data}


@app.post("/orders/{order_id}/qpay-invoice")
async def order_invoice(order_id: str, user: Customer, db: DB):
    return await ensure_invoice(order_id, user, db)


async def verify_payment(db, payment, raw):
    if payment.status == "paid":
        return {"paid": True}
    if not payment.provider_invoice_id or not await payment_provider().paid(payment.provider_invoice_id, payment.amount):
        return {"paid": False}
    payment.status, payment.raw_webhook = "paid", raw
    order = await get_locked(db, Order, payment.order_id)
    if order.status == "delivered":
        await change_status(db, order, "completed", "qpay")
    else:
        db.add(Outbox(kind="event", payload={"order_id": order.id, "type": "payment"}))
    await db.commit()
    return {"paid": True}


@app.post("/orders/{order_id}/check-payment")
async def check_payment(order_id: str, user: Customer, db: DB):
    order = await get_order(db, order_id, user, locked=True)
    await cache.limit("payment:" + user.id, 10, 60)
    payment = await db.scalar(select(Payment).where(Payment.order_id == order.id).with_for_update())
    return await verify_payment(db, payment, {"source": "customer_check"})


@app.api_route("/payments/qpay/webhook", methods=["POST", "GET"])
async def qpay_webhook(request: Request, db: DB, payment_id: str, token: str):
    payment = await db.get(Payment, payment_id)
    if not payment or not payment.callback_secret or not hmac.compare_digest(token, payment.callback_secret):
        raise HTTPException(403, "INVALID_CALLBACK")
    await cache.limit("callback:" + payment_id, 30, 60)
    await get_locked(db, Order, payment.order_id)
    payment = await get_locked(db, Payment, payment_id)
    # Callback is only a signal. Fetch the amount and status directly from QPay.
    return await verify_payment(db, payment, {"source": "qpay_callback", "method": request.method})


async def websocket_order(websocket, order_id=None, tracking_token=None):
    if websocket.headers.get("origin") not in {None, settings.public_url.rstrip("/")}:
        await websocket.close(code=4403)
        return
    await websocket.accept()
    pubsub = None
    try:
        user_id, expires = None, now().timestamp() + 900
        if not tracking_token:
            token = websocket.cookies.get("ag_access")
            if not token:
                auth = await asyncio.wait_for(websocket.receive_json(), timeout=10)
                token = auth.get("token", "")
            claims = decode(token)
            user_id, expires = claims["sub"], claims["exp"]
        async with Session() as db:
            if tracking_token:
                order = await db.scalar(select(Order).where(Order.tracking_token == tracking_token))
                if not order or (order.status in TERMINAL and now() - aware(order.updated_at) > timedelta(days=1)):
                    raise HTTPException(404, "TRACKING_EXPIRED")
                order_id = order.id
            else:
                user = await db.get(User, user_id)
                if not user:
                    raise HTTPException(401, "LOGIN_REQUIRED")
                order = await get_order(db, order_id, user)
        pubsub = cache.redis.pubsub()
        await pubsub.subscribe("order:" + order_id)
        last_sent = 0.0
        while now().timestamp() < expires:
            event = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1)
            if event or now().timestamp() - last_sent >= 20:
                async with Session() as db:
                    if user_id:
                        user = await db.get(User, user_id)
                        order = await get_order(db, order_id, user)
                    else:
                        order = await db.get(Order, order_id)
                    await websocket.send_json({"type": "snapshot", "order": await order_json(db, order, public=bool(tracking_token))})
                last_sent = now().timestamp()
            await asyncio.sleep(0.1)
        await websocket.close(code=4401)
    except (WebSocketDisconnect, RuntimeError):
        pass
    except (HTTPException, asyncio.TimeoutError, ValueError, KeyError):
        await websocket.close(code=4401)
    finally:
        if pubsub:
            await pubsub.aclose()


@app.websocket("/ws/orders/{order_id}")
async def order_socket(websocket: WebSocket, order_id: str):
    await websocket_order(websocket, order_id=order_id)


@app.websocket("/ws/tracking/{token}")
async def tracking_socket(websocket: WebSocket, token: str):
    await websocket_order(websocket, tracking_token=token)
