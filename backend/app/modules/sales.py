"""Point-of-sale transactions, receipts and returns.

Integrity rules (all enforced here, never on the client):
* Prices come from the product record; client prices are only used to detect
  that the price changed since the cashier saw it.
* Totals, tax, discounts and change are calculated on the server with Decimal.
* `client_reference` is an idempotency key: replaying it returns the original
  sale instead of creating a duplicate.
* Product rows and the business receipt counter are locked inside the
  transaction, so concurrent sales cannot oversell stock or reuse a number.
"""

import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Response, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.api.deps import DB, BusinessContext, require
from app.api.pagination import Page, Paging, paginate
from app.core.database import utcnow
from app.core.errors import AppError, Conflict, Forbidden, NotFound
from app.core.money import MoneyIn, MoneyOut, QtyIn, QtyOut, format_qty, money, qty
from app.core.permissions import Permission
from app.core.storage import signed_url
from app.models import Business, Customer, Payment, Sale, SaleItem, SaleReturn, SaleReturnLine, User
from app.modules import audit, subscriptions
from app.modules.inventory import apply_stock_change, lock_products
from app.modules.reports_time import day_bounds_utc

router = APIRouter(prefix="/businesses/{business_id}", tags=["sales"])

PaymentMethod = Literal["cash", "mobile_money", "bank_transfer", "card", "other"]

# Offline sales keep their device time only within this window; otherwise the server time is used.
OFFLINE_MAX_AGE = timedelta(hours=72)
CLOCK_SKEW_ALLOWANCE = timedelta(minutes=5)


# --- Schemas ---------------------------------------------------------------------------------


class SaleItemIn(BaseModel):
    product_id: uuid.UUID
    quantity: QtyIn
    # The price the cashier saw. If it no longer matches, the sale is rejected (price_changed).
    expected_unit_price: MoneyIn | None = None
    discount: MoneyIn = Decimal("0")


class PaymentIn(BaseModel):
    method: PaymentMethod
    amount: Annotated[Decimal, Field(gt=0, max_digits=14, decimal_places=2)]
    reference: str | None = Field(default=None, max_length=64)


class SaleCreate(BaseModel):
    client_reference: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    items: list[SaleItemIn] = Field(min_length=1, max_length=200)
    payments: list[PaymentIn] = Field(min_length=1, max_length=5)
    order_discount: MoneyIn = Decimal("0")
    customer_id: uuid.UUID | None = None
    note: str | None = Field(default=None, max_length=300)
    device_id: str | None = Field(default=None, max_length=64)
    client_created_at: datetime | None = None

    @field_validator("client_created_at")
    @classmethod
    def _aware(cls, v: datetime | None) -> datetime | None:
        if v is not None and v.tzinfo is None:
            raise ValueError("Timestamps must include a time zone offset.")
        return v


class SaleItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    product_id: uuid.UUID
    product_name: str
    sku: str | None
    quantity: QtyOut
    unit_price: MoneyOut
    discount: MoneyOut
    line_total: MoneyOut
    quantity_returned: QtyOut


class PaymentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    kind: str
    method: str
    amount: MoneyOut
    reference: str | None
    created_at: datetime


class SaleOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    client_reference: str
    receipt_number: str
    status: str
    customer_id: uuid.UUID | None
    cashier_id: uuid.UUID
    subtotal: MoneyOut
    discount_total: MoneyOut
    tax_total: MoneyOut
    total: MoneyOut
    amount_paid: MoneyOut
    change_due: MoneyOut
    refunded_total: MoneyOut
    note: str | None
    source: str
    created_at: datetime
    client_created_at: datetime | None
    items: list[SaleItemOut]
    payments: list[PaymentOut]


class SaleSummaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    receipt_number: str
    status: str
    total: MoneyOut
    refunded_total: MoneyOut
    cashier_id: uuid.UUID
    customer_id: uuid.UUID | None
    source: str
    created_at: datetime


class ReturnLineIn(BaseModel):
    sale_item_id: uuid.UUID
    quantity: QtyIn


class ReturnCreate(BaseModel):
    client_reference: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    lines: list[ReturnLineIn] = Field(min_length=1, max_length=200)
    reason: str = Field(min_length=3, max_length=300)
    restock: bool = True
    refund_method: PaymentMethod = "cash"


class ReturnOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    sale_id: uuid.UUID
    amount: MoneyOut
    reason: str
    restock: bool
    refund_method: str
    created_at: datetime


class ReceiptLine(BaseModel):
    name: str
    quantity: QtyOut
    unit_price: MoneyOut
    discount: MoneyOut
    line_total: MoneyOut


class ReceiptOut(BaseModel):
    business_name: str
    logo_url: str | None = None
    business_phone: str | None
    business_address: str | None
    currency: str
    receipt_number: str
    issued_at: datetime
    timezone: str
    cashier_name: str
    customer_name: str | None
    lines: list[ReceiptLine]
    subtotal: MoneyOut
    discount_total: MoneyOut
    tax_rate_percent: str
    tax_total: MoneyOut
    total: MoneyOut
    amount_paid: MoneyOut
    change_due: MoneyOut
    refunded_total: MoneyOut
    payments: list[PaymentOut]
    status: str
    footer: str | None


# --- Service ---------------------------------------------------------------------------------


@dataclass
class SaleResult:
    sale: Sale
    created: bool


def _existing_sale(db: Session, business_id: uuid.UUID, client_reference: str) -> Sale | None:
    return db.scalar(
        select(Sale)
        .where(Sale.business_id == business_id, Sale.client_reference == client_reference)
        .options(selectinload(Sale.items), selectinload(Sale.payments))
    )


def _occurred_at(source: str, client_time: datetime | None, now: datetime) -> datetime:
    if source != "offline" or client_time is None:
        return now
    if now - OFFLINE_MAX_AGE <= client_time <= now + CLOCK_SKEW_ALLOWANCE:
        return min(client_time, now)
    return now  # implausible device clock: fall back to server time (original kept in client_created_at)


def extract_tax(total: Decimal, rate_percent: Decimal) -> Decimal:
    """Tax contained in a tax-inclusive total."""
    if rate_percent <= 0:
        return Decimal("0.00")
    return money(total * rate_percent / (Decimal(100) + rate_percent))


def create_sale(db: Session, ctx: BusinessContext, body: SaleCreate, *, source: str = "online") -> SaleResult:
    existing = _existing_sale(db, ctx.business_id, body.client_reference)
    if existing is not None:
        if existing.cashier_id != ctx.user.id and not ctx.can(Permission.SALES_VIEW_ALL):
            raise Conflict("This sale reference has already been used.", code="reference_reused")
        return SaleResult(existing, created=False)

    ctx.require(Permission.SALES_CREATE)
    has_discount = body.order_discount > 0 or any(i.discount > 0 for i in body.items)
    if has_discount and not ctx.can(Permission.SALES_DISCOUNT):
        raise Forbidden("You are not allowed to give discounts.", code="discount_not_allowed")
    subscriptions.check_sales_limit(db, ctx.business_id, ctx.business.timezone)

    allowed_methods = set(ctx.business.payment_methods.split(","))
    for p in body.payments:
        if p.method not in allowed_methods:
            raise AppError(
                f"Payment method '{p.method}' is not enabled for this business.", code="payment_method_disabled"
            )
    if (
        body.customer_id is not None
        and db.scalar(
            select(Customer.id).where(Customer.id == body.customer_id, Customer.business_id == ctx.business_id)
        )
        is None
    ):
        raise AppError("Customer not found.", code="customer_not_found")

    # Lock order: business counter first, then products sorted by id — the same in every writer.
    business = db.scalar(select(Business).where(Business.id == ctx.business_id).with_for_update())
    products = lock_products(db, ctx.business_id, [i.product_id for i in body.items])

    now = utcnow()
    sale_id = uuid.uuid4()
    lines: list[SaleItem] = []
    subtotal = line_discounts = cost_total = Decimal("0")
    for position, item in enumerate(body.items):
        product = products[item.product_id]
        if not product.is_active:
            raise Conflict(
                f"{product.name} is archived and cannot be sold.",
                code="product_archived",
                details={"product_id": str(product.id)},
            )
        unit_price = money(product.selling_price)
        if item.expected_unit_price is not None and money(item.expected_unit_price) != unit_price:
            raise Conflict(
                f"The price of {product.name} has changed to {unit_price}.",
                code="price_changed",
                details={"product_id": str(product.id), "current_price": str(unit_price)},
            )
        quantity = qty(item.quantity)
        gross = money(unit_price * quantity)
        if item.discount > gross:
            raise AppError(f"Discount on {product.name} exceeds the line amount.", code="invalid_discount")
        line_total = money(gross - item.discount)
        subtotal += gross
        line_discounts += item.discount
        cost_total += money(product.cost_price * quantity)
        lines.append(
            SaleItem(
                business_id=ctx.business_id,
                sale_id=sale_id,
                product_id=product.id,
                position=position,
                product_name=product.name,
                sku=product.sku,
                quantity=quantity,
                unit_price=unit_price,
                unit_cost=product.cost_price,
                discount=money(item.discount),
                line_total=line_total,
            )
        )
        apply_stock_change(
            db,
            product,
            -quantity,
            "sale",
            actor_id=ctx.user.id,
            enforce=business.enforce_stock,
            reference_type="sale",
            reference_id=sale_id,
        )

    after_line_discounts = subtotal - line_discounts
    if body.order_discount > after_line_discounts:
        raise AppError("The discount is larger than the sale amount.", code="invalid_discount")
    discount_total = money(line_discounts + body.order_discount)
    total = money(subtotal - discount_total)

    tendered = money(sum((p.amount for p in body.payments), Decimal("0")))
    if tendered < total:
        raise AppError(
            f"Payment is short by {money(total - tendered)}.",
            code="insufficient_payment",
            details={"total": str(total), "paid": str(tendered)},
        )
    change = money(tendered - total)
    cash_paid = sum((p.amount for p in body.payments if p.method == "cash"), Decimal("0"))
    if change > 0 and change > cash_paid:
        raise AppError("Only cash payments can exceed the amount due.", code="overpayment")

    # Record net payments: change is given back out of the cash tendered.
    payments: list[Payment] = []
    remaining_change = change
    for p in body.payments:
        amount = money(p.amount)
        if p.method == "cash" and remaining_change > 0:
            used = min(amount, remaining_change)
            amount -= used
            remaining_change -= used
        if amount > 0:
            payments.append(
                Payment(
                    business_id=ctx.business_id,
                    sale_id=sale_id,
                    kind="payment",
                    method=p.method,
                    amount=amount,
                    reference=p.reference,
                    created_at=now,
                )
            )

    sequence = business.next_receipt_number
    business.next_receipt_number = sequence + 1
    sale = Sale(
        id=sale_id,
        business_id=ctx.business_id,
        client_reference=body.client_reference,
        sequence=sequence,
        receipt_number=f"{business.receipt_prefix}-{sequence:06d}",
        status="completed",
        customer_id=body.customer_id,
        cashier_id=ctx.user.id,
        subtotal=money(subtotal),
        discount_total=discount_total,
        tax_total=extract_tax(total, business.tax_rate_percent),
        total=total,
        amount_paid=tendered,
        change_due=change,
        cost_total=money(cost_total),
        refunded_total=Decimal("0"),
        note=body.note,
        source=source,
        device_id=body.device_id,
        client_created_at=body.client_created_at,
        created_at=_occurred_at(source, body.client_created_at, now),
    )
    sale.items = lines
    sale.payments = payments
    db.add(sale)
    audit.record(
        db,
        action="sale.completed",
        entity_type="sale",
        entity_id=sale.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{sale.receipt_number} total {total}",
    )
    try:
        db.commit()
    except IntegrityError:
        # A concurrent retry with the same idempotency key won the race: return that sale.
        db.rollback()
        existing = _existing_sale(db, ctx.business_id, body.client_reference)
        if existing is None:
            raise
        return SaleResult(existing, created=False)
    return SaleResult(sale, created=True)


def _visible_sale(db: Session, ctx: BusinessContext, sale_id: uuid.UUID, *, for_update: bool = False) -> Sale:
    stmt = select(Sale).where(Sale.id == sale_id, Sale.business_id == ctx.business_id)
    if not ctx.can(Permission.SALES_VIEW_ALL):
        stmt = stmt.where(Sale.cashier_id == ctx.user.id)
    if for_update:
        stmt = stmt.with_for_update()
    sale = db.scalar(stmt.options(selectinload(Sale.items), selectinload(Sale.payments)))
    if sale is None:
        raise NotFound("Sale not found.")
    return sale


def create_return(db: Session, ctx: BusinessContext, sale_id: uuid.UUID, body: ReturnCreate) -> SaleReturn:
    ctx.require(Permission.SALES_REFUND)
    existing = db.scalar(
        select(SaleReturn).where(
            SaleReturn.business_id == ctx.business_id, SaleReturn.client_reference == body.client_reference
        )
    )
    if existing is not None:
        if existing.sale_id != sale_id:
            raise Conflict("This return reference was already used for another sale.", code="reference_reused")
        return existing

    sale = _visible_sale(db, ctx, sale_id, for_update=True)
    items = {i.id: i for i in sale.items}
    requested: dict[uuid.UUID, Decimal] = {}
    for line in body.lines:
        if line.sale_item_id not in items:
            raise AppError("A returned item does not belong to this sale.", code="invalid_return_line")
        requested[line.sale_item_id] = requested.get(line.sale_item_id, Decimal("0")) + qty(line.quantity)

    products = lock_products(db, ctx.business_id, [items[i].product_id for i in requested])
    lines_total = sum((i.line_total for i in sale.items), Decimal("0"))
    # Spread any order-level discount proportionally across returned lines.
    order_factor = sale.total / lines_total if lines_total > 0 else Decimal("0")

    return_id = uuid.uuid4()
    amount = cost_amount = Decimal("0")
    return_lines = []
    for item_id, quantity in requested.items():
        item = items[item_id]
        returnable = item.quantity - item.quantity_returned
        if quantity > returnable:
            raise AppError(
                f"Only {format_qty(returnable)} of {item.product_name} can still be returned.",
                code="return_exceeds_sold",
            )
        line_amount = money(item.line_total * quantity / item.quantity * order_factor)
        item.quantity_returned = qty(item.quantity_returned + quantity)
        amount += line_amount
        cost_amount += money(item.unit_cost * quantity)
        return_lines.append(SaleReturnLine(sale_item_id=item.id, quantity=quantity, amount=line_amount))
        if body.restock:
            apply_stock_change(
                db,
                products[item.product_id],
                quantity,
                "return",
                actor_id=ctx.user.id,
                enforce=False,
                reference_type="return",
                reference_id=return_id,
                note=f"Return on {sale.receipt_number}",
            )

    fully_returned = all(i.quantity_returned >= i.quantity for i in sale.items)
    if fully_returned:
        amount = sale.total - sale.refunded_total  # absorb rounding so refunds sum exactly to the total
    amount = min(money(amount), sale.total - sale.refunded_total)

    now = utcnow()
    sale_return = SaleReturn(
        id=return_id,
        business_id=ctx.business_id,
        sale_id=sale.id,
        client_reference=body.client_reference,
        amount=amount,
        cost_amount=money(cost_amount),
        reason=body.reason.strip(),
        restock=body.restock,
        refund_method=body.refund_method,
        created_by=ctx.user.id,
        created_at=now,
    )
    sale_return.lines = return_lines
    db.add(sale_return)
    db.add(
        Payment(
            business_id=ctx.business_id,
            sale_id=sale.id,
            kind="refund",
            method=body.refund_method,
            amount=amount,
            reference=f"RET-{str(return_id)[:8]}",
            created_at=now,
        )
    )
    sale.refunded_total = money(sale.refunded_total + amount)
    sale.status = "refunded" if fully_returned else "partially_refunded"
    audit.record(
        db,
        action="sale.returned",
        entity_type="sale",
        entity_id=sale.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{sale.receipt_number} refund {amount}: {body.reason[:120]}",
    )
    db.commit()
    return sale_return


# --- Endpoints -------------------------------------------------------------------------------


@router.post("/sales", response_model=SaleOut, status_code=status.HTTP_201_CREATED)
def record_sale(
    body: SaleCreate, response: Response, db: DB, ctx: BusinessContext = require(Permission.SALES_CREATE)
) -> Sale:
    result = create_sale(db, ctx, body)
    if not result.created:
        response.status_code = status.HTTP_200_OK
        response.headers["Idempotent-Replay"] = "true"
    return result.sale


@router.get("/sales", response_model=Page[SaleSummaryOut])
def list_sales(
    db: DB,
    paging: Paging,
    ctx: BusinessContext = require(Permission.SALES_CREATE),
    date_from: date | None = None,
    date_to: date | None = None,
    sale_status: Annotated[Literal["completed", "partially_refunded", "refunded"] | None, Query(alias="status")] = None,
    q: Annotated[str | None, Query(max_length=32)] = None,
) -> Page[SaleSummaryOut]:
    stmt = select(Sale).where(Sale.business_id == ctx.business_id)
    if not ctx.can(Permission.SALES_VIEW_ALL):
        stmt = stmt.where(Sale.cashier_id == ctx.user.id)
    if date_from or date_to:
        lo, hi = day_bounds_utc(date_from or date(2000, 1, 1), date_to or date(2999, 12, 31), ctx.business.timezone)
        stmt = stmt.where(Sale.created_at >= lo, Sale.created_at < hi)
    if sale_status:
        stmt = stmt.where(Sale.status == sale_status)
    if q:
        stmt = stmt.where(Sale.receipt_number.ilike(f"%{q.strip()}%"))
    rows, total = paginate(db, stmt.order_by(Sale.created_at.desc(), Sale.sequence.desc()), paging)
    return Page(items=rows, total=total, limit=paging.limit, offset=paging.offset)


@router.get("/sales/{sale_id}", response_model=SaleOut)
def read_sale(sale_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.SALES_CREATE)) -> Sale:
    return _visible_sale(db, ctx, sale_id)


@router.get("/sales/{sale_id}/receipt", response_model=ReceiptOut)
def read_receipt(sale_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.SALES_CREATE)) -> ReceiptOut:
    sale = _visible_sale(db, ctx, sale_id)
    b = ctx.business
    cashier = db.get(User, sale.cashier_id)
    customer = db.get(Customer, sale.customer_id) if sale.customer_id else None
    return ReceiptOut(
        business_name=b.name,
        logo_url=signed_url(b.logo_file_id),
        business_phone=b.phone,
        business_address=b.address,
        currency=b.currency,
        receipt_number=sale.receipt_number,
        issued_at=sale.created_at,
        timezone=b.timezone,
        cashier_name=cashier.full_name if cashier else "",
        customer_name=customer.name if customer else None,
        lines=[
            ReceiptLine(
                name=i.product_name,
                quantity=i.quantity,
                unit_price=i.unit_price,
                discount=i.discount,
                line_total=i.line_total,
            )
            for i in sale.items
        ],
        subtotal=sale.subtotal,
        discount_total=sale.discount_total,
        tax_rate_percent=str(b.tax_rate_percent),
        tax_total=sale.tax_total,
        total=sale.total,
        amount_paid=sale.amount_paid,
        change_due=sale.change_due,
        refunded_total=sale.refunded_total,
        payments=sale.payments,
        status=sale.status,
        footer=b.receipt_footer,
    )


@router.post("/sales/{sale_id}/returns", response_model=ReturnOut, status_code=status.HTTP_201_CREATED)
def return_items(
    sale_id: uuid.UUID, body: ReturnCreate, db: DB, ctx: BusinessContext = require(Permission.SALES_REFUND)
) -> SaleReturn:
    return create_return(db, ctx, sale_id, body)
