import asyncio
import logging
from celery import Celery
from sqlalchemy import select
from .config import settings
from .db import Session, engine
from .models import Order, Outbox, now
from .orders import change_status
from .providers import sms_provider

celery_app = Celery("achaago", broker=settings.celery_broker_url)
celery_app.conf.update(task_serializer="json", accept_content=["json"], broker_connection_retry_on_startup=True,
                       broker_connection_timeout=3, task_ignore_result=True,
                       beat_schedule={"outbox": {"task": "achaago.flush_outbox", "schedule": 2.0},
                                      "pending-timeout": {"task": "achaago.expire_pending", "schedule": 60.0}})


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


async def drain_outbox():
    from redis.asyncio import Redis
    import json
    redis = Redis.from_url(settings.redis_url, decode_responses=True)
    try:
        async with Session() as db:
            rows = (await db.scalars(select(Outbox).where(Outbox.delivered.is_(False)).order_by(Outbox.created_at).limit(100).with_for_update(skip_locked=True))).all()
            for row in rows:
                if row.kind == "event":
                    await redis.publish("order:" + row.payload["order_id"], json.dumps(row.payload))
                elif row.kind == "sms":
                    await asyncio.to_thread(sms_provider().send, row.payload["phone"], row.payload["message"])
                elif row.kind == "push":
                    await asyncio.to_thread(send_push, row.payload)
                row.delivered = True
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
