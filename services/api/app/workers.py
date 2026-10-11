import asyncio
import logging
import time
from celery import Celery
from celery.signals import after_setup_logger
from sqlalchemy import select
from .config import settings
from .db import Session, engine
from .models import Order, Outbox, RefreshSession, now
from .orders import change_status
from .providers import sms_provider
from . import alerts

log = logging.getLogger(__name__)
HEARTBEAT_KEY = "worker:heartbeat"
MAX_OUTBOX_ATTEMPTS = 8
OUTBOX_KEEP_DAYS = 7

celery_app = Celery("achaago", broker=settings.celery_broker_url)
celery_app.conf.update(task_serializer="json", accept_content=["json"], broker_connection_retry_on_startup=True,
                       broker_connection_timeout=3, task_ignore_result=True,
                       # Periodic runs expire after a few intervals: while the worker is down beat keeps
                       # queueing, and without expiry a restart would replay hours of stale runs.
                       beat_schedule={"outbox": {"task": "achaago.flush_outbox", "schedule": 2.0, "options": {"expires": 10}},
                                      "pending-timeout": {"task": "achaago.expire_pending", "schedule": 60.0,
                                                          "options": {"expires": 50}},
                                      "cleanup": {"task": "achaago.cleanup", "schedule": 3600.0, "options": {"expires": 600}}})


@after_setup_logger.connect
def install_alerts(**_):
    # After Celery has (re)configured the root logger, or our handler would be dropped.
    alerts.install(settings.alert_provider, settings.telegram_bot_token, settings.telegram_chat_id,
                   f"{settings.brand_name} {settings.app_env} worker")


@celery_app.task(name="achaago.send_sms", autoretry_for=(Exception,), retry_backoff=True, max_retries=3)
def send_sms(phone, message):
    sms_provider().send(phone, message)


def send_push(payload):
    if settings.fcm_provider == "console":
        logging.getLogger(__name__).info("DEVELOPMENT push for order %s", payload["order_id"])
        return
    import firebase_admin
    from firebase_admin import messaging
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(options={"projectId": settings.fcm_project_id})
    messaging.send(messaging.Message(token=payload["token"], notification=messaging.Notification(
        title="Шинэ захиалга", body="Танд тээврийн захиалга хуваариллаа."), data={"order_id": payload["order_id"]}))


def retry_delay(attempts: int) -> int:
    """5 s, 10 s, 20 s ... capped at 10 min: about 20 minutes of retries in total."""
    return min(5 * 2 ** (attempts - 1), 600)


async def deliver(row, redis):
    import json
    if row.kind == "event":
        await redis.publish("order:" + row.payload["order_id"], json.dumps(row.payload))
    elif row.kind == "sms":
        await asyncio.to_thread(sms_provider().send, row.payload["phone"], row.payload["message"])
    elif row.kind == "push":
        await asyncio.to_thread(send_push, row.payload)


async def process_outbox(rows, redis, clock=time.time):
    """Deliver each row on its own: one failing SMS used to roll back the whole
    batch, so every later event (the customers' live updates) stalled behind it."""
    for row in rows:
        if row.payload.get("_retry_at", 0) > clock():
            continue
        try:
            await deliver(row, redis)
            row.delivered = True
        except Exception as error:
            attempts = int(row.payload.get("_attempts", 0)) + 1
            # A new dict, so SQLAlchemy sees the JSON column change.
            row.payload = {**row.payload, "_attempts": attempts, "_retry_at": clock() + retry_delay(attempts)}
            if attempts >= MAX_OUTBOX_ATTEMPTS:
                row.delivered = True  # give up, or the row retries forever
                log.error("Outbox %s message dropped after %d attempts (%s)", row.kind, attempts, type(error).__name__)
            else:
                log.warning("Outbox %s delivery failed, attempt %d (%s)", row.kind, attempts, type(error).__name__)


async def drain_outbox():
    from redis.asyncio import Redis
    redis = Redis.from_url(settings.redis_url, decode_responses=True)
    try:
        # /health/full and the API watchdog read this to tell that worker and beat are alive.
        await redis.set(HEARTBEAT_KEY, str(int(time.time())), ex=600)
        async with Session() as db:
            rows = (await db.scalars(select(Outbox).where(Outbox.delivered.is_(False)).order_by(Outbox.created_at).limit(200).with_for_update(skip_locked=True))).all()
            await process_outbox(rows, redis)
            await db.commit()
    finally:
        await redis.aclose()
        await engine.dispose()


@celery_app.task(name="achaago.flush_outbox")
def flush_outbox():
    asyncio.run(drain_outbox())


async def expire_orders():
    from datetime import timedelta
    try:
        async with Session() as db:
            orders = (await db.scalars(select(Order).where(Order.status == "pending", Order.created_at < now() - timedelta(minutes=settings.dispatch_timeout_minutes)).with_for_update(skip_locked=True))).all()
            for order in orders:
                await change_status(db, order, "no_driver_found", "system", "Dispatch timeout")
            await db.commit()
    finally:
        await engine.dispose()


@celery_app.task(name="achaago.expire_pending")
def expire_pending():
    asyncio.run(expire_orders())


async def cleanup_rows():
    """Delivered outbox rows and expired refresh sessions only grow otherwise. Order events
    stay: they are the audit trail."""
    from datetime import timedelta
    from sqlalchemy import delete
    try:
        async with Session() as db:
            await db.execute(delete(Outbox).where(Outbox.delivered.is_(True),
                                                  Outbox.created_at < now() - timedelta(days=OUTBOX_KEEP_DAYS)))
            await db.execute(delete(RefreshSession).where(RefreshSession.expires_at < now()))
            await db.commit()
    finally:
        await engine.dispose()


@celery_app.task(name="achaago.cleanup")
def cleanup():
    asyncio.run(cleanup_rows())
