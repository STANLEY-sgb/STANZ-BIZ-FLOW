import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Boolean, Date, ForeignKey, Index, Integer, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.mixins import IdMixin, TenantMixin, TimestampMixin
from app.models.types import Money, Quantity, UTCDateTime


class Customer(IdMixin, TenantMixin, TimestampMixin, Base):
    __tablename__ = "customers"
    __table_args__ = (Index("ix_customers_business_name", "business_id", "name"),)

    name: Mapped[str] = mapped_column(String(160), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(320))
    reference: Mapped[str | None] = mapped_column(String(64))
    notes: Mapped[str | None] = mapped_column(String(1000))


class Sale(IdMixin, TenantMixin, Base):
    __tablename__ = "sales"
    __table_args__ = (
        UniqueConstraint("business_id", "client_reference"),  # idempotency key
        UniqueConstraint("business_id", "sequence"),
        Index("ix_sales_business_created", "business_id", "created_at"),
    )

    client_reference: Mapped[str] = mapped_column(String(64), nullable=False)
    sequence: Mapped[int] = mapped_column(Integer, nullable=False)
    receipt_number: Mapped[str] = mapped_column(String(32), nullable=False)
    # completed | partially_refunded | refunded
    status: Mapped[str] = mapped_column(String(24), nullable=False)
    customer_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("customers.id", ondelete="SET NULL"))
    cashier_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False)
    subtotal: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    discount_total: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    tax_total: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    total: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    amount_paid: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    change_due: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    cost_total: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    refunded_total: Mapped[Decimal] = mapped_column(Money(), default=Decimal("0"), nullable=False)
    note: Mapped[str | None] = mapped_column(String(300))
    source: Mapped[str] = mapped_column(String(16), default="online", nullable=False)  # online | offline
    device_id: Mapped[str | None] = mapped_column(String(64))
    client_created_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)

    items: Mapped[list["SaleItem"]] = relationship(
        back_populates="sale", order_by="SaleItem.position", cascade="all, delete-orphan"
    )
    payments: Mapped[list["Payment"]] = relationship(order_by="Payment.created_at", cascade="all, delete-orphan")


class SaleItem(IdMixin, TenantMixin, Base):
    """Line items snapshot name and price so later product edits never rewrite history."""

    __tablename__ = "sale_items"

    sale_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("sales.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("products.id"), index=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    product_name: Mapped[str] = mapped_column(String(160), nullable=False)
    sku: Mapped[str | None] = mapped_column(String(64))
    quantity: Mapped[Decimal] = mapped_column(Quantity(), nullable=False)
    unit_price: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    unit_cost: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    discount: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    line_total: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    quantity_returned: Mapped[Decimal] = mapped_column(Quantity(), default=Decimal("0"), nullable=False)

    sale: Mapped[Sale] = relationship(back_populates="items")


class Payment(IdMixin, TenantMixin, Base):
    """A recorded payment or refund. Recording is not processing: no provider is charged here."""

    __tablename__ = "payments"

    sale_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("sales.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(12), nullable=False)  # payment | refund
    method: Mapped[str] = mapped_column(String(24), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    reference: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)


class SaleReturn(IdMixin, TenantMixin, Base):
    __tablename__ = "sale_returns"
    __table_args__ = (UniqueConstraint("business_id", "client_reference"),)

    sale_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("sales.id", ondelete="CASCADE"), index=True)
    client_reference: Mapped[str] = mapped_column(String(64), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    cost_amount: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    reason: Mapped[str] = mapped_column(String(300), nullable=False)
    restock: Mapped[bool] = mapped_column(Boolean, nullable=False)
    refund_method: Mapped[str] = mapped_column(String(24), nullable=False)
    created_by: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, index=True)

    lines: Mapped[list["SaleReturnLine"]] = relationship(cascade="all, delete-orphan")


class SaleReturnLine(IdMixin, Base):
    __tablename__ = "sale_return_lines"

    return_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("sale_returns.id", ondelete="CASCADE"), index=True)
    sale_item_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("sale_items.id"), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Quantity(), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Money(), nullable=False)


class Expense(IdMixin, TenantMixin, TimestampMixin, Base):
    __tablename__ = "expenses"
    __table_args__ = (Index("ix_expenses_business_date", "business_id", "expense_date"),)

    category: Mapped[str] = mapped_column(String(60), nullable=False)
    description: Mapped[str | None] = mapped_column(String(300))
    amount: Mapped[Decimal] = mapped_column(Money(), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    expense_date: Mapped[date] = mapped_column(Date, nullable=False)
    payment_method: Mapped[str | None] = mapped_column(String(24))
    supplier: Mapped[str | None] = mapped_column(String(160))
    created_by: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
