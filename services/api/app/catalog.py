"""Register booking services without overwriting operator-configured fares."""
import asyncio
from sqlalchemy import select
from .models import Service


async def ensure_booking_services(db):
    defaults = [
        # Zero is a storage placeholder, not an offered fare. Activate only after
        # the operator supplies base_fare and per_km_rate through service settings.
        dict(code="motorcycle", name_mn="Мотоцикл", description_mn="Бичиг баримт, жижиг хайрцаг, хувцас, цэцэг, жижиг сэлбэг, жижиг бараа", icon="package", base_fare=0, per_km_rate=0, is_active=False),
        dict(code="amjirgaa", name_mn="Амжиргаа", description_mn="[ТАЙЛБАР]", icon="package", base_fare=10000, per_km_rate=1500, is_active=True),
        dict(code="porter", name_mn="Портер", description_mn="Ачааны машин · 1 тн хүртэл", icon="truck", base_fare=30000, per_km_rate=2000, is_active=True),
    ]
    for position, data in enumerate(defaults):
        existing = await db.scalar(select(Service).where(Service.code == data["code"]))
        if existing is None:
            db.add(Service(**data, sort_order=position))
        else:
            existing.sort_order = position


async def main():
    # Scoped catalog registration; does not seed users, drivers or other settings.
    from .db import Session, engine
    async with Session() as db:
        await ensure_booking_services(db)
        await db.commit()
        rows = (await db.scalars(select(Service).order_by(Service.sort_order))).all()
        for row in rows:
            print(f"{row.code}: active={row.is_active}, order={row.sort_order}")
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
