"""Business-time helpers. Business days are defined in the business's own time zone."""

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo


def local_today(timezone: str) -> date:
    return datetime.now(ZoneInfo(timezone)).date()


def day_bounds_utc(start: date, end_inclusive: date, timezone: str) -> tuple[datetime, datetime]:
    """UTC [start, end) covering local calendar days start..end_inclusive."""
    tz = ZoneInfo(timezone)
    lo = datetime.combine(start, time.min, tzinfo=tz).astimezone(UTC)
    hi = datetime.combine(end_inclusive + timedelta(days=1), time.min, tzinfo=tz).astimezone(UTC)
    return lo, hi


def month_start_utc(timezone: str) -> datetime:
    today = local_today(timezone)
    return day_bounds_utc(today.replace(day=1), today, timezone)[0]


def to_local_date(value: datetime, timezone: str) -> date:
    return value.astimezone(ZoneInfo(timezone)).date()
