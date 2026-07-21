"""Database engine and session management."""

from collections.abc import Generator
from contextlib import contextmanager

from sqlalchemy.engine import Engine
from sqlmodel import Session, SQLModel, create_engine

from llm_cost_comparison.core.config import Settings
from llm_cost_comparison.core.exceptions import StorageError


def get_engine(database_url: str | None = None, settings: Settings | None = None) -> Engine:
    """Create a SQLAlchemy engine from a database URL or settings."""
    if database_url is None:
        if settings is None:
            settings = Settings()
        database_url = settings.database_url

    try:
        return create_engine(database_url, connect_args={"check_same_thread": False})
    except Exception as exc:
        raise StorageError(f"Could not create database engine: {exc}") from exc


def init_db(engine: Engine) -> None:
    """Create all tables if they do not exist."""
    SQLModel.metadata.create_all(engine)


@contextmanager
def get_session(engine: Engine) -> Generator[Session, None, None]:
    """Yield a SQLModel session and commit/rollback automatically."""
    session = Session(engine, expire_on_commit=False)
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
