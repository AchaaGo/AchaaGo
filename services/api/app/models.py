from datetime import datetime, timezone
import uuid
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from geoalchemy2 import Geometry, WKTElement
from .config import settings
from .db import Base

IS_POSTGRES = settings.database_url.startswith("postgresql")
json_type = JSON().with_variant(JSONB, "postgresql")


def now():
    return datetime.now(timezone.utc)


def uid():
    return str(uuid.uuid4())


def point_column():
    return mapped_column(Geometry("POINT", srid=4326) if IS_POSTGRES else JSON, nullable=True)


def point_value(lat, lng):
    return WKTElement(f"POINT({lng} {lat})", srid=4326) if IS_POSTGRES else {"lat": lat, "lng": lng}


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    phone: Mapped[str] = mapped_column(String(12), unique=True)
    name: Mapped[str | None] = mapped_column(String(100))
    role: Mapped[str] = mapped_column(String(20), default="customer")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class RefreshSession(Base):
    __tablename__ = "refresh_sessions"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Service(Base):
    __tablename__ = "services"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    code: Mapped[str] = mapped_column(String(30), unique=True)
    name_mn: Mapped[str] = mapped_column(String(80))
    description_mn: Mapped[str] = mapped_column(String(200))
    icon: Mapped[str] = mapped_column(String(30), default="truck")
    base_fare: Mapped[int] = mapped_column(Integer)
    per_km_rate: Mapped[int] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)


class PricingSettings(Base):
    __tablename__ = "pricing_settings"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    loader_rate: Mapped[int] = mapped_column(Integer, default=25000)
    floor_rate: Mapped[int] = mapped_column(Integer, default=0)
    night_surcharge_pct: Mapped[int] = mapped_column(Integer, default=20)
    night_start: Mapped[int] = mapped_column(Integer, default=22)
    night_end: Mapped[int] = mapped_column(Integer, default=7)


class Driver(Base):
    __tablename__ = "drivers"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), unique=True)
    license_info: Mapped[str] = mapped_column(String(100))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    rating: Mapped[float | None] = mapped_column(Float, nullable=True)
    is_online: Mapped[bool] = mapped_column(Boolean, default=False)
    fcm_token: Mapped[str | None] = mapped_column(Text)
    last_lat: Mapped[float | None] = mapped_column(Float)
    last_lng: Mapped[float | None] = mapped_column(Float)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_point: Mapped[object | None] = point_column()


class Vehicle(Base):
    __tablename__ = "vehicles"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    driver_id: Mapped[str] = mapped_column(ForeignKey("drivers.id"), unique=True)
    service_id: Mapped[str] = mapped_column(ForeignKey("services.id"))
    plate_number: Mapped[str] = mapped_column(String(20), unique=True)
    model: Mapped[str] = mapped_column(String(100))
    capacity_kg: Mapped[int] = mapped_column(Integer)


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (UniqueConstraint("customer_id", "idempotency_key"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    customer_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    service_id: Mapped[str] = mapped_column(ForeignKey("services.id"))
    driver_id: Mapped[str | None] = mapped_column(ForeignKey("drivers.id"), index=True)
    status: Mapped[str] = mapped_column(String(30), default="pending", index=True)
    pickup_lat: Mapped[float] = mapped_column(Float)
    pickup_lng: Mapped[float] = mapped_column(Float)
    dropoff_lat: Mapped[float] = mapped_column(Float)
    dropoff_lng: Mapped[float] = mapped_column(Float)
    pickup_point: Mapped[object] = point_column()
    dropoff_point: Mapped[object] = point_column()
    pickup_address: Mapped[str] = mapped_column(String(300))
    dropoff_address: Mapped[str] = mapped_column(String(300))
    distance_km: Mapped[float] = mapped_column(Float)
    duration_minutes: Mapped[int] = mapped_column(Integer)
    route_polyline: Mapped[str | None] = mapped_column(Text)
    loaders: Mapped[int] = mapped_column(Integer, default=0)
    payment_method: Mapped[str] = mapped_column(String(10))
    price_breakdown: Mapped[dict] = mapped_column(json_type)
    total_price: Mapped[int] = mapped_column(Integer)
    tracking_token: Mapped[str] = mapped_column(String(64), unique=True)
    idempotency_key: Mapped[str] = mapped_column(String(64))
    request_hash: Mapped[str] = mapped_column(String(64))
    scheduled_for: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rating: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class OrderEvent(Base):
    __tablename__ = "order_events"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"), index=True)
    status: Mapped[str] = mapped_column(String(30))
    actor: Mapped[str] = mapped_column(String(36))
    reason: Mapped[str | None] = mapped_column(String(300))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Payment(Base):
    __tablename__ = "payments"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"), unique=True)
    provider: Mapped[str] = mapped_column(String(10))
    amount: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    provider_invoice_id: Mapped[str | None] = mapped_column(String(100), unique=True)
    invoice_data: Mapped[dict | None] = mapped_column(json_type)
    callback_secret: Mapped[str | None] = mapped_column(String(64))
    raw_webhook: Mapped[dict | None] = mapped_column(json_type)


class Outbox(Base):
    __tablename__ = "outbox"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    kind: Mapped[str] = mapped_column(String(30))
    payload: Mapped[dict] = mapped_column(json_type)
    delivered: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
