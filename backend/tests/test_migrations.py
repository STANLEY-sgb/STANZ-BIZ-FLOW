"""Migrations must build the exact schema the models describe, and be reversible."""

from pathlib import Path

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect

from app.core.database import Base
from tests.conftest import TEST_DATABASE_URL

BACKEND = Path(__file__).resolve().parents[1]


def _config(connection) -> Config:
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND / "alembic"))
    cfg.attributes["connection"] = connection
    return cfg


def test_upgrade_matches_models_and_downgrade_is_clean(tmp_path):
    url = TEST_DATABASE_URL or f"sqlite:///{tmp_path / 'migrations.db'}"
    engine = create_engine(url)
    Base.metadata.drop_all(engine)
    with engine.begin() as conn:
        conn.exec_driver_sql("DROP TABLE IF EXISTS alembic_version")
    with engine.begin() as conn:
        command.upgrade(_config(conn), "head")
    with engine.connect() as conn:
        ctx = MigrationContext.configure(conn, opts={"compare_type": True})
        diff = compare_metadata(ctx, Base.metadata)
        assert diff == [], diff
    with engine.begin() as conn:
        command.downgrade(_config(conn), "base")
    assert set(inspect(engine).get_table_names()) <= {"alembic_version"}
    engine.dispose()
