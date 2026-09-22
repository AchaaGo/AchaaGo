"""Initial AchaaGo schema.

Revision ID: 0001
"""
from alembic import op
import sqlalchemy as sa
from geoalchemy2 import Geometry
from sqlalchemy.dialects.postgresql import JSONB

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

JSON = sa.JSON().with_variant(JSONB(), "postgresql")


def upgrade():
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    op.create_table("users",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("phone", sa.String(12), nullable=False, unique=True),
        sa.Column("name", sa.String(100)), sa.Column("role", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_table("refresh_sessions",
        sa.Column("id", sa.String(64), primary_key=True), sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False))
    op.create_index("ix_refresh_sessions_user_id", "refresh_sessions", ["user_id"])
    op.create_table("services",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("code", sa.String(30), nullable=False, unique=True),
        sa.Column("name_mn", sa.String(80), nullable=False), sa.Column("description_mn", sa.String(200), nullable=False),
        sa.Column("icon", sa.String(30), nullable=False), sa.Column("base_fare", sa.Integer, nullable=False),
        sa.Column("per_km_rate", sa.Integer, nullable=False), sa.Column("is_active", sa.Boolean, nullable=False),
        sa.Column("sort_order", sa.Integer, nullable=False))
    op.create_table("pricing_settings",
        sa.Column("id", sa.Integer, primary_key=True), sa.Column("loader_rate", sa.Integer, nullable=False),
        sa.Column("floor_rate", sa.Integer, nullable=False), sa.Column("night_surcharge_pct", sa.Integer, nullable=False),
        sa.Column("night_start", sa.Integer, nullable=False), sa.Column("night_end", sa.Integer, nullable=False))
    op.create_table("drivers",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False, unique=True),
        sa.Column("license_info", sa.String(100), nullable=False), sa.Column("status", sa.String(20), nullable=False),
        sa.Column("rating", sa.Float), sa.Column("is_online", sa.Boolean, nullable=False), sa.Column("fcm_token", sa.Text),
        sa.Column("last_lat", sa.Float), sa.Column("last_lng", sa.Float), sa.Column("last_seen", sa.DateTime(timezone=True)),
        sa.Column("last_point", Geometry("POINT", srid=4326)))
    op.create_table("vehicles",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("driver_id", sa.String(36), sa.ForeignKey("drivers.id"), nullable=False, unique=True),
        sa.Column("service_id", sa.String(36), sa.ForeignKey("services.id"), nullable=False),
        sa.Column("plate_number", sa.String(20), nullable=False, unique=True), sa.Column("model", sa.String(100), nullable=False),
        sa.Column("capacity_kg", sa.Integer, nullable=False))
    op.create_table("orders",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("customer_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("service_id", sa.String(36), sa.ForeignKey("services.id"), nullable=False),
        sa.Column("driver_id", sa.String(36), sa.ForeignKey("drivers.id")), sa.Column("status", sa.String(30), nullable=False),
        sa.Column("pickup_lat", sa.Float, nullable=False), sa.Column("pickup_lng", sa.Float, nullable=False),
        sa.Column("dropoff_lat", sa.Float, nullable=False), sa.Column("dropoff_lng", sa.Float, nullable=False),
        sa.Column("pickup_point", Geometry("POINT", srid=4326)), sa.Column("dropoff_point", Geometry("POINT", srid=4326)),
        sa.Column("pickup_address", sa.String(300), nullable=False), sa.Column("dropoff_address", sa.String(300), nullable=False),
        sa.Column("distance_km", sa.Float, nullable=False), sa.Column("duration_minutes", sa.Integer, nullable=False),
        sa.Column("route_polyline", sa.Text), sa.Column("loaders", sa.Integer, nullable=False),
        sa.Column("payment_method", sa.String(10), nullable=False), sa.Column("price_breakdown", JSON, nullable=False),
        sa.Column("total_price", sa.Integer, nullable=False), sa.Column("tracking_token", sa.String(64), nullable=False, unique=True),
        sa.Column("idempotency_key", sa.String(64), nullable=False), sa.Column("request_hash", sa.String(64), nullable=False),
        sa.Column("scheduled_for", sa.DateTime(timezone=True)), sa.Column("rating", sa.Integer),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("customer_id", "idempotency_key"))
    op.create_index("ix_orders_customer_id", "orders", ["customer_id"])
    op.create_index("ix_orders_driver_id", "orders", ["driver_id"])
    op.create_index("ix_orders_status", "orders", ["status"])
    op.create_index("ix_orders_created_at", "orders", ["created_at"])
    op.create_table("order_events",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("order_id", sa.String(36), sa.ForeignKey("orders.id"), nullable=False),
        sa.Column("status", sa.String(30), nullable=False), sa.Column("actor", sa.String(36), nullable=False),
        sa.Column("reason", sa.String(300)), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_index("ix_order_events_order_id", "order_events", ["order_id"])
    op.create_table("payments",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("order_id", sa.String(36), sa.ForeignKey("orders.id"), nullable=False, unique=True),
        sa.Column("provider", sa.String(10), nullable=False), sa.Column("amount", sa.Integer, nullable=False),
        sa.Column("status", sa.String(20), nullable=False), sa.Column("provider_invoice_id", sa.String(100), unique=True),
        sa.Column("invoice_data", JSON), sa.Column("callback_secret", sa.String(64)), sa.Column("raw_webhook", JSON))
    op.create_table("outbox",
        sa.Column("id", sa.String(36), primary_key=True), sa.Column("kind", sa.String(30), nullable=False),
        sa.Column("payload", JSON, nullable=False), sa.Column("delivered", sa.Boolean, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_index("ix_outbox_delivered", "outbox", ["delivered"])


def downgrade():
    for table in ("outbox", "payments", "order_events", "orders", "vehicles", "drivers", "pricing_settings", "services", "refresh_sessions", "users"):
        op.drop_table(table)
