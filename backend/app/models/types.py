"""Portable column types."""

from datetime import UTC, datetime

from sqlalchemy import DateTime, Numeric
from sqlalchemy.types import TypeDecorator

from app.core.money import MONEY_PRECISION, QTY_PRECISION


class UTCDateTime(TypeDecorator):
    """Timezone-aware UTC timestamps on every backend (SQLite drops tzinfo)."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect):  # noqa: ANN001, ANN201
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("naive datetimes are not allowed")
        return value.astimezone(UTC)

    def process_result_value(self, value: datetime | None, dialect):  # noqa: ANN001, ANN201
        if value is not None and value.tzinfo is None:
            value = value.replace(tzinfo=UTC)
        return value


def Money() -> Numeric:  # noqa: N802
    return Numeric(*MONEY_PRECISION, asdecimal=True)


def Quantity() -> Numeric:  # noqa: N802
    return Numeric(*QTY_PRECISION, asdecimal=True)
