import asyncio
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.catalog import ensure_booking_services
from app.models import Service


def test_motorcycle_is_inactive_until_configured_and_seed_preserves_prices():
    async def scenario():
        engine = create_async_engine("sqlite+aiosqlite:///:memory:")
        async with engine.begin() as connection:
            await connection.run_sync(Service.__table__.create)
        async with async_sessionmaker(engine, expire_on_commit=False)() as db:
            await ensure_booking_services(db)
            await db.commit()
            rows = (await db.scalars(select(Service).order_by(Service.sort_order))).all()
            assert [row.code for row in rows] == ["motorcycle", "amjirgaa", "porter"]
            motorcycle = rows[0]
            assert motorcycle.is_active is False
            active = (await db.scalars(select(Service).where(Service.is_active.is_(True)))).all()
            assert motorcycle not in active
            # Test-only operator values; these are not production fares.
            motorcycle.base_fare, motorcycle.per_km_rate, motorcycle.is_active = 7300, 850, True
            rows[1].base_fare = 12300
            await db.commit()
            await ensure_booking_services(db)
            await db.commit()
            assert motorcycle.base_fare == 7300
            assert motorcycle.per_km_rate == 850
            assert motorcycle.is_active is True
            assert rows[1].base_fare == 12300
            assert len((await db.scalars(select(Service))).all()) == 3
        await engine.dispose()
    asyncio.run(scenario())
