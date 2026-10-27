import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Uuid
from sqlalchemy.orm import Mapped, declared_attr, mapped_column

from app.core.database import utcnow
from app.models.types import UTCDateTime


class IdMixin:
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow, nullable=False)


class TenantMixin:
    """Every tenant-owned row carries its business_id directly so scoping is a single predicate."""

    @declared_attr
    def business_id(cls) -> Mapped[uuid.UUID]:  # noqa: N805
        return mapped_column(Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
