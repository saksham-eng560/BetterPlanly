import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import text

from app.db import make_engine, make_sessionmaker

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL", "postgresql://planly:planly@localhost:5432/planly_test"
)
SQLALCHEMY_URL = TEST_DATABASE_URL.replace("postgresql://", "postgresql+psycopg://", 1)
BACKEND_DIR = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).parent / "fixtures"
REPO_ROOT = BACKEND_DIR.parent

APP_TABLES = "events, change_sets, checklist_items, resources, tasks, plans, preferences"


@pytest.fixture(scope="session")
def migrated() -> None:
    cfg = Config(str(BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    cfg.attributes["sqlalchemy_url"] = SQLALCHEMY_URL
    command.upgrade(cfg, "head")


@pytest.fixture(scope="session")
async def engine(migrated):
    engine = make_engine(SQLALCHEMY_URL)
    yield engine
    await engine.dispose()


@pytest.fixture
async def sessionmaker(engine):
    async with engine.begin() as conn:
        await conn.execute(text(f"TRUNCATE {APP_TABLES} RESTART IDENTITY CASCADE"))
    return make_sessionmaker(engine)


@pytest.fixture
async def session(sessionmaker):
    async with sessionmaker() as session:
        yield session
