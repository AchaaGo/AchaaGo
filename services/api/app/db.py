from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from .config import settings

engine = create_async_engine(settings.database_url, pool_pre_ping=True)
Session = async_sessionmaker(engine, expire_on_commit=False)


if settings.database_url.startswith("sqlite"):
    @event.listens_for(engine.sync_engine, "connect")
    def sqlite_foreign_keys(connection, _):
        connection.execute("PRAGMA foreign_keys=ON")


class Base(DeclarativeBase):
    pass


async def get_db():
    async with Session() as session:
        yield session


async def get_locked(db: AsyncSession, model, key):
    from sqlalchemy import select
    return (await db.execute(select(model).where(model.id == key).with_for_update())).scalar_one_or_none()
