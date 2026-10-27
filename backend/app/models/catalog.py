import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import JSON, Boolean, ForeignKey, Index, Integer, String, Text, UniqueConstraint, Uuid, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models.mixins import IdMixin, TenantMixin, TimestampMixin
from app.models.types import Money, Quantity, UTCDateTime


class Category(IdMixin, TenantMixin, TimestampMixin, Base):
    __tablename__ = "categories"
    __table_args__ = (UniqueConstraint("business_id", "name"),)

    name: Mapped[str] = mapped_column(String(80), nullable=False)


class Product(IdMixin, TenantMixin, TimestampMixin, Base):
    __tablename__ = "products"
    __table_args__ = (
        # SKU and barcode are unique per business when present.
        Index(
            "uq_products_business_sku",
            "business_id",
            "sku",
            unique=True,
            postgresql_where=text("sku IS NOT NULL"),
            sqlite_where=text("sku IS NOT NULL"),
        ),
        Index(
            "uq_products_business_barcode",
            "business_id",
            "barcode",
            unique=True,
            postgresql_where=text("barcode IS NOT NULL"),
            sqlite_where=text("barcode IS NOT NULL"),
        ),
        Index("ix_products_business_active_name", "business_id", "is_active", "name"),
    )

    category_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("categories.id", ondelete="SET NULL"))
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    sku: Mapped[str | None] = mapped_column(String(64))
    barcode: Mapped[str | None] = mapped_column(String(64))
    unit: Mapped[str] = mapped_column(String(16), default="pcs", nullable=False)
    cost_price: Mapped[Decimal] = mapped_column(Money(), default=Decimal("0"), nullable=False)
    selling_price: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    track_stock: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # Denormalised running balance; every change goes through a StockMovement in the same transaction.
    quantity_on_hand: Mapped[Decimal] = mapped_column(Quantity(), default=Decimal("0"), nullable=False)
    reorder_level: Mapped[Decimal] = mapped_column(Quantity(), default=Decimal("0"), nullable=False)
    # Industry-specific attributes (brand, model, storage, colour, condition, warranty_months...).
    attributes: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # Optimistic concurrency for edits (and offline conflict detection).
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)


class StockMovement(IdMixin, TenantMixin, Base):
    """Append-only inventory ledger. quantity_on_hand == SUM(quantity_change) per product."""

    __tablename__ = "stock_movements"
    __table_args__ = (Index("ix_stock_movements_product_created", "product_id", "created_at"),)

    product_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    # opening | receipt | sale | return | adjustment | damage | count | reversal
    reason: Mapped[str] = mapped_column(String(24), nullable=False)
    quantity_change: Mapped[Decimal] = mapped_column(Quantity(), nullable=False)
    quantity_after: Mapped[Decimal] = mapped_column(Quantity(), nullable=False)
    unit_cost: Mapped[Decimal | None] = mapped_column(Money())
    reference_type: Mapped[str | None] = mapped_column(String(24))
    reference_id: Mapped[str | None] = mapped_column(String(64))
    note: Mapped[str | None] = mapped_column(String(300))
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
