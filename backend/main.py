import asyncio
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@db:5432/app_db",
)

engine = create_async_engine(DATABASE_URL)


async def wait_for_db(max_attempts: int = 30, delay: float = 2.0) -> None:
    """PostgreSQL may be up but not ready yet — retry the connection."""
    for attempt in range(1, max_attempts + 1):
        try:
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            return
        except Exception:
            if attempt == max_attempts:
                raise
            await asyncio.sleep(delay)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: verify PostgreSQL connectivity (async).
    await wait_for_db()
    yield
    await engine.dispose()


app = FastAPI(title="FastAPI dev boilerplate", lifespan=lifespan)


@app.get("/api/v1/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}