import asyncio
import re
from sqlalchemy import select
from .config import settings
from .catalog import ensure_booking_services
from .db import Session, engine
from .models import Driver, PricingSettings, Service, User, Vehicle


async def seed():
    async with Session() as db:
        await ensure_booking_services(db)
        if not await db.get(PricingSettings, 1):
            db.add(PricingSettings(id=1))
        if settings.bootstrap_admin_phone:
            if not re.fullmatch(r"\+976[0-9]{8}", settings.bootstrap_admin_phone):
                raise ValueError("BOOTSTRAP_ADMIN_PHONE must be +976 and 8 digits")
            existing = await db.scalar(select(User).where(User.phone == settings.bootstrap_admin_phone))
            if not existing:
                db.add(User(phone=settings.bootstrap_admin_phone, name="Админ", role="admin"))
            elif existing.role != "admin":
                raise ValueError("Bootstrap phone already belongs to a non-admin; refusing to elevate it")
        await db.flush()
        if settings.seed_demo_driver and settings.app_env != "production":
            user = await db.scalar(select(User).where(User.phone == "+97699000002"))
            if not user:
                user = User(phone="+97699000002", name="Туршилтын жолооч", role="driver")
                db.add(user)
                await db.flush()
                driver = Driver(user_id=user.id, license_info="DEVELOPMENT ONLY", status="approved")
                db.add(driver)
                await db.flush()
                porter = await db.scalar(select(Service).where(Service.code == "porter"))
                db.add(Vehicle(driver_id=driver.id, service_id=porter.id, plate_number="ТУРШИЛТ", model="Портер", capacity_kg=1000))
        await db.commit()
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed())
