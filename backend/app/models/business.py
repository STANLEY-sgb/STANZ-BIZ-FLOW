import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import Boolean, ForeignKey, Integer, Numeric, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models.mixins import IdMixin, TenantMixin, TimestampMixin
from app.models.types import UTCDateTime


class Business(IdMixin, TimestampMixin, Base):
    """A tenant workspace."""

    __tablename__ = "businesses"

    name: Mapped[str] = mapped_column(String(160), nullable=False)
    category: Mapped[str] = mapped_column(String(40), nullable=False)
    country_code: Mapped[str] = mapped_column(String(2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(320))
    address: Mapped[str | None] = mapped_column(String(300))
    receipt_footer: Mapped[str | None] = mapped_column(String(300))
    # References stored_files.id (no FK constraint: stored_files already references businesses).
    logo_file_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    # Prices are tax-inclusive; the tax shown on receipts is extracted at this rate.
    tax_rate_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), default=Decimal("0"), nullable=False)
    enforce_stock: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    payment_methods: Mapped[str] = mapped_column(String(200), default="cash,mobile_money", nullable=False)
    receipt_prefix: Mapped[str] = mapped_column(String(8), default="R", nullable=False)
    next_receipt_number: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    onboarding_step: Mapped[str] = mapped_column(String(32), default="first_product", nullable=False)
    onboarding_completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_by: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False)


class Membership(IdMixin, TenantMixin, TimestampMixin, Base):
    __tablename__ = "memberships"
    __table_args__ = (UniqueConstraint("business_id", "user_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="active", nullable=False)  # active | revoked


class Invitation(IdMixin, TenantMixin, Base):
    __tablename__ = "invitations"

    email: Mapped[str] = mapped_column(String(320), nullable=False, index=True)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    invited_by: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    accepted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    revoked_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class BusinessSubscription(IdMixin, TimestampMixin, Base):
    __tablename__ = "business_subscriptions"

    business_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    plan_code: Mapped[str] = mapped_column(String(32), nullable=False)
    # trialing | active | past_due | canceled | expired
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    trial_ends_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    current_period_end: Mapped[datetime | None] = mapped_column(UTCDateTime)
    provider: Mapped[str | None] = mapped_column(String(32))
    provider_reference: Mapped[str | None] = mapped_column(String(128))


class AuditEvent(IdMixin, Base):
    __tablename__ = "audit_events"

    business_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("businesses.id", ondelete="CASCADE"), index=True
    )
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    entity_type: Mapped[str] = mapped_column(String(40), nullable=False)
    entity_id: Mapped[str | None] = mapped_column(String(64))
    summary: Mapped[str | None] = mapped_column(String(300))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, index=True)
