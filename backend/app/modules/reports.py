"""Dashboard and reports. Every figure is aggregated in the database from real records.

Definitions (also documented in docs/REPORTING.md):
* gross_sales   = sum of line amounts before any discount (prices are tax-inclusive)
* discounts     = line + order discounts on sales in the period
* refunds       = refunds issued in the period (by refund date)
* net_sales     = gross_sales - discounts - refunds
* cogs          = cost of items sold (cost captured at time of sale) minus cost of restocked returns
* gross_profit  = net_sales - cogs   (flagged unreliable when sold items had no cost price)
* expenses      = operating expenses dated in the period
* net_profit    = gross_profit - expenses   (an operational estimate, not an accounting statement)
"""

import csv
import io
from datetime import date, timedelta
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.api.deps import DB, BusinessContext, require
from app.core.errors import AppError
from app.core.money import MoneyOut, QtyOut, money
from app.core.permissions import Permission
from app.core.plans import Feature
from app.models import Category, Expense, Payment, Product, Sale, SaleItem, SaleReturn, User
from app.modules import subscriptions
from app.modules.reports_time import day_bounds_utc, local_today, to_local_date

router = APIRouter(prefix="/businesses/{business_id}", tags=["reports"])

MAX_RANGE_DAYS = 366
ZERO = Decimal("0")


# --- Schemas ---------------------------------------------------------------------------------


class Summary(BaseModel):
    date_from: date
    date_to: date
    sales_count: int
    gross_sales: MoneyOut
    discounts: MoneyOut
    refunds: MoneyOut
    net_sales: MoneyOut
    tax_included: MoneyOut
    average_sale: MoneyOut
    cogs: MoneyOut
    gross_profit: MoneyOut
    cost_data_complete: bool
    expenses: MoneyOut
    net_profit: MoneyOut


class ProductRow(BaseModel):
    product_id: str
    name: str
    quantity: QtyOut
    revenue: MoneyOut
    gross_profit: MoneyOut | None = None


class LabelAmount(BaseModel):
    label: str
    count: int
    amount: MoneyOut


class DayRow(BaseModel):
    day: date
    sales_count: int
    net_sales: MoneyOut


class LowStockRow(BaseModel):
    product_id: str
    name: str
    quantity_on_hand: QtyOut
    reorder_level: QtyOut


class RecentSale(BaseModel):
    id: str
    receipt_number: str
    total: MoneyOut
    status: str
    created_at: str


class InventorySummary(BaseModel):
    active_products: int
    tracked_products: int
    low_stock: int
    out_of_stock: int
    units_on_hand: QtyOut
    valuation_at_cost: MoneyOut | None
    valuation_at_price: MoneyOut


class Dashboard(BaseModel):
    scope: Literal["business", "own_sales"]
    currency: str
    timezone: str
    period: str
    current: Summary | None
    previous: Summary | None
    my_sales_today: LabelAmount
    inventory: InventorySummary
    low_stock: list[LowStockRow]
    top_products: list[ProductRow]
    recent_sales: list[RecentSale]


# --- Queries ---------------------------------------------------------------------------------


def _range(ctx: BusinessContext, date_from: date | None, date_to: date | None) -> tuple[date, date]:
    today = local_today(ctx.business.timezone)
    date_to = date_to or today
    date_from = date_from or date_to.replace(day=1)
    if date_from > date_to:
        raise AppError("The start date must be before the end date.", code="invalid_range")
    if (date_to - date_from).days > MAX_RANGE_DAYS:
        raise AppError(f"Reports can cover at most {MAX_RANGE_DAYS} days.", code="range_too_large")
    return date_from, date_to


def summary(db: Session, ctx: BusinessContext, date_from: date, date_to: date) -> Summary:
    bid = ctx.business_id
    lo, hi = day_bounds_utc(date_from, date_to, ctx.business.timezone)
    in_period = (Sale.business_id == bid, Sale.created_at >= lo, Sale.created_at < hi)

    count, gross, discounts, tax, cost = db.execute(
        select(
            func.count(Sale.id),
            func.coalesce(func.sum(Sale.subtotal), ZERO),
            func.coalesce(func.sum(Sale.discount_total), ZERO),
            func.coalesce(func.sum(Sale.tax_total), ZERO),
            func.coalesce(func.sum(Sale.cost_total), ZERO),
        ).where(*in_period)
    ).one()
    refunds, restocked_cost = db.execute(
        select(
            func.coalesce(func.sum(SaleReturn.amount), ZERO),
            func.coalesce(func.sum(case((SaleReturn.restock, SaleReturn.cost_amount), else_=ZERO)), ZERO),
        ).where(SaleReturn.business_id == bid, SaleReturn.created_at >= lo, SaleReturn.created_at < hi)
    ).one()
    missing_cost = db.scalar(
        select(func.count(SaleItem.id))
        .join(Sale, Sale.id == SaleItem.sale_id)
        .where(*in_period, SaleItem.unit_cost <= 0)
    )
    expenses = db.scalar(
        select(func.coalesce(func.sum(Expense.amount), ZERO)).where(
            Expense.business_id == bid,
            Expense.deleted_at.is_(None),
            Expense.expense_date >= date_from,
            Expense.expense_date <= date_to,
        )
    )
    gross, discounts, refunds = Decimal(gross), Decimal(discounts), Decimal(refunds)
    net = gross - discounts - refunds
    cogs = Decimal(cost) - Decimal(restocked_cost)
    gross_profit = net - cogs
    return Summary(
        date_from=date_from,
        date_to=date_to,
        sales_count=count,
        gross_sales=gross,
        discounts=discounts,
        refunds=refunds,
        net_sales=net,
        tax_included=Decimal(tax),
        average_sale=money((gross - discounts) / count) if count else ZERO,
        cogs=cogs,
        gross_profit=gross_profit,
        cost_data_complete=missing_cost == 0,
        expenses=Decimal(expenses),
        net_profit=gross_profit - Decimal(expenses),
    )


def top_products(
    db: Session, ctx: BusinessContext, date_from: date, date_to: date, limit: int = 10, include_profit: bool = False
) -> list[ProductRow]:
    lo, hi = day_bounds_utc(date_from, date_to, ctx.business.timezone)
    sold_qty = func.sum(SaleItem.quantity - SaleItem.quantity_returned)
    revenue = func.sum(SaleItem.line_total * (SaleItem.quantity - SaleItem.quantity_returned) / SaleItem.quantity)
    cost = func.sum(SaleItem.unit_cost * (SaleItem.quantity - SaleItem.quantity_returned))
    rows = db.execute(
        select(SaleItem.product_id, func.max(SaleItem.product_name), sold_qty, revenue, cost)
        .join(Sale, Sale.id == SaleItem.sale_id)
        .where(Sale.business_id == ctx.business_id, Sale.created_at >= lo, Sale.created_at < hi)
        .group_by(SaleItem.product_id)
        .order_by(revenue.desc())
        .limit(limit)
    ).all()
    return [
        ProductRow(
            product_id=str(pid),
            name=name,
            quantity=Decimal(q),
            revenue=money(Decimal(r)),
            gross_profit=money(Decimal(r) - Decimal(c)) if include_profit else None,
        )
        for pid, name, q, r, c in rows
    ]


def sales_by_day(db: Session, ctx: BusinessContext, date_from: date, date_to: date) -> list[DayRow]:
    tz = ctx.business.timezone
    lo, hi = day_bounds_utc(date_from, date_to, tz)
    net = Sale.total - Sale.refunded_total
    buckets: dict[date, list] = {
        date_from + timedelta(days=i): [0, ZERO] for i in range((date_to - date_from).days + 1)
    }
    if db.bind.dialect.name == "postgresql":
        local_day = func.date(func.timezone(tz, Sale.created_at))
        rows = db.execute(
            select(local_day, func.count(), func.sum(net))
            .where(Sale.business_id == ctx.business_id, Sale.created_at >= lo, Sale.created_at < hi)
            .group_by(local_day)
        ).all()
        for day, count, amount in rows:
            buckets[day] = [count, Decimal(amount)]
    else:  # portable fallback used by the SQLite test suite
        for created_at, amount in db.execute(
            select(Sale.created_at, net).where(
                Sale.business_id == ctx.business_id, Sale.created_at >= lo, Sale.created_at < hi
            )
        ):
            bucket = buckets[to_local_date(created_at, tz)]
            bucket[0] += 1
            bucket[1] += Decimal(amount)
    return [DayRow(day=d, sales_count=c, net_sales=a) for d, (c, a) in sorted(buckets.items())]


def inventory_summary(db: Session, ctx: BusinessContext) -> InventorySummary:
    bid = ctx.business_id
    positive = case((Product.quantity_on_hand > 0, Product.quantity_on_hand), else_=ZERO)
    active, tracked, low, out, units, at_cost, at_price = db.execute(
        select(
            func.count(Product.id),
            func.coalesce(func.sum(case((Product.track_stock, 1), else_=0)), 0),
            func.coalesce(
                func.sum(
                    case(
                        (
                            Product.track_stock
                            & (Product.quantity_on_hand > 0)
                            & (Product.quantity_on_hand <= Product.reorder_level),
                            1,
                        ),
                        else_=0,
                    )
                ),
                0,
            ),
            func.coalesce(func.sum(case((Product.track_stock & (Product.quantity_on_hand <= 0), 1), else_=0)), 0),
            func.coalesce(func.sum(case((Product.track_stock, positive), else_=ZERO)), ZERO),
            func.coalesce(func.sum(case((Product.track_stock, positive * Product.cost_price), else_=ZERO)), ZERO),
            func.coalesce(func.sum(case((Product.track_stock, positive * Product.selling_price), else_=ZERO)), ZERO),
        ).where(Product.business_id == bid, Product.is_active)
    ).one()
    return InventorySummary(
        active_products=active,
        tracked_products=tracked,
        low_stock=low,
        out_of_stock=out,
        units_on_hand=Decimal(units),
        valuation_at_cost=money(Decimal(at_cost)) if ctx.can(Permission.PRODUCTS_VIEW_COST) else None,
        valuation_at_price=money(Decimal(at_price)),
    )


def low_stock(db: Session, ctx: BusinessContext, limit: int = 20) -> list[LowStockRow]:
    rows = db.scalars(
        select(Product)
        .where(
            Product.business_id == ctx.business_id,
            Product.is_active,
            Product.track_stock,
            Product.quantity_on_hand <= Product.reorder_level,
        )
        .order_by(Product.quantity_on_hand, Product.name)
        .limit(limit)
    )
    return [
        LowStockRow(
            product_id=str(p.id), name=p.name, quantity_on_hand=p.quantity_on_hand, reorder_level=p.reorder_level
        )
        for p in rows
    ]


# --- Endpoints -------------------------------------------------------------------------------

Period = Literal["today", "7d", "30d", "month"]


def _period_range(period: Period, today: date) -> tuple[date, date, date, date]:
    if period == "today":
        return today, today, today - timedelta(days=1), today - timedelta(days=1)
    if period == "month":
        start = today.replace(day=1)
        prev_end = start - timedelta(days=1)
        # Compare month-to-date with the same number of days of the previous month.
        prev_start = prev_end.replace(day=1)
        prev_to = min(prev_start + (today - start), prev_end)
        return start, today, prev_start, prev_to
    days = 7 if period == "7d" else 30
    start = today - timedelta(days=days - 1)
    return start, today, start - timedelta(days=days), start - timedelta(days=1)


@router.get("/dashboard", response_model=Dashboard)
def dashboard(db: DB, ctx: BusinessContext = require(Permission.BUSINESS_VIEW), period: Period = "today") -> Dashboard:
    tz = ctx.business.timezone
    today = local_today(tz)
    lo, hi = day_bounds_utc(today, today, tz)
    mine = db.execute(
        select(func.count(Sale.id), func.coalesce(func.sum(Sale.total - Sale.refunded_total), ZERO)).where(
            Sale.business_id == ctx.business_id,
            Sale.cashier_id == ctx.user.id,
            Sale.created_at >= lo,
            Sale.created_at < hi,
        )
    ).one()
    full = ctx.can(Permission.REPORTS_VIEW)
    current = previous = None
    tops: list[ProductRow] = []
    recent: list[RecentSale] = []
    if full:
        start, end, prev_start, prev_end = _period_range(period, today)
        current = summary(db, ctx, start, end)
        previous = summary(db, ctx, prev_start, prev_end)
        tops = top_products(db, ctx, start, end, limit=5)
    recent_stmt = select(Sale).where(Sale.business_id == ctx.business_id)
    if not ctx.can(Permission.SALES_VIEW_ALL):
        recent_stmt = recent_stmt.where(Sale.cashier_id == ctx.user.id)
    recent = [
        RecentSale(
            id=str(s.id),
            receipt_number=s.receipt_number,
            total=s.total,
            status=s.status,
            created_at=s.created_at.isoformat(),
        )
        for s in db.scalars(recent_stmt.order_by(Sale.created_at.desc()).limit(5))
    ]
    return Dashboard(
        scope="business" if full else "own_sales",
        currency=ctx.business.currency,
        timezone=tz,
        period=period,
        current=current,
        previous=previous,
        my_sales_today=LabelAmount(label="my_sales_today", count=mine[0], amount=Decimal(mine[1])),
        inventory=inventory_summary(db, ctx),
        low_stock=low_stock(db, ctx, limit=5),
        top_products=tops,
        recent_sales=recent,
    )


DateFrom = Annotated[date | None, Query()]


@router.get("/reports/summary", response_model=Summary)
def report_summary(
    db: DB,
    ctx: BusinessContext = require(Permission.REPORTS_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
) -> Summary:
    return summary(db, ctx, *_range(ctx, date_from, date_to))


@router.get("/reports/sales-by-day", response_model=list[DayRow])
def report_sales_by_day(
    db: DB,
    ctx: BusinessContext = require(Permission.REPORTS_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
) -> list[DayRow]:
    return sales_by_day(db, ctx, *_range(ctx, date_from, date_to))


@router.get("/reports/sales-by-product", response_model=list[ProductRow])
def report_sales_by_product(
    db: DB,
    ctx: BusinessContext = require(Permission.REPORTS_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
    limit: Annotated[int, Query(ge=1, le=500)] = 50,
) -> list[ProductRow]:
    return top_products(
        db, ctx, *_range(ctx, date_from, date_to), limit=limit, include_profit=ctx.can(Permission.PRODUCTS_VIEW_COST)
    )


@router.get("/reports/sales-by-category", response_model=list[LabelAmount])
def report_sales_by_category(
    db: DB,
    ctx: BusinessContext = require(Permission.REPORTS_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
) -> list[LabelAmount]:
    lo, hi = day_bounds_utc(*_range(ctx, date_from, date_to), ctx.business.timezone)
    revenue = func.sum(SaleItem.line_total * (SaleItem.quantity - SaleItem.quantity_returned) / SaleItem.quantity)
    rows = db.execute(
        select(func.coalesce(Category.name, "Uncategorised"), func.count(SaleItem.id), revenue)
        .join(Sale, Sale.id == SaleItem.sale_id)
        .join(Product, Product.id == SaleItem.product_id)
        .outerjoin(Category, Category.id == Product.category_id)
        .where(Sale.business_id == ctx.business_id, Sale.created_at >= lo, Sale.created_at < hi)
        .group_by(Category.name)
        .order_by(revenue.desc())
    ).all()
    return [LabelAmount(label=n, count=c, amount=money(Decimal(a))) for n, c, a in rows]


@router.get("/reports/sales-by-cashier", response_model=list[LabelAmount])
def report_sales_by_cashier(
    db: DB,
    ctx: BusinessContext = require(Permission.REPORTS_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
) -> list[LabelAmount]:
    lo, hi = day_bounds_utc(*_range(ctx, date_from, date_to), ctx.business.timezone)
    amount = func.sum(Sale.total - Sale.refunded_total)
    rows = db.execute(
        select(User.full_name, func.count(Sale.id), amount)
        .join(User, User.id == Sale.cashier_id)
        .where(Sale.business_id == ctx.business_id, Sale.created_at >= lo, Sale.created_at < hi)
        .group_by(User.id, User.full_name)
        .order_by(amount.desc())
    ).all()
    return [LabelAmount(label=n, count=c, amount=Decimal(a)) for n, c, a in rows]


@router.get("/reports/payment-methods", response_model=list[LabelAmount])
def report_payment_methods(
    db: DB,
    ctx: BusinessContext = require(Permission.REPORTS_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
) -> list[LabelAmount]:
    """Net money received per method: payments minus refunds paid out in the period."""
    lo, hi = day_bounds_utc(*_range(ctx, date_from, date_to), ctx.business.timezone)
    signed = case((Payment.kind == "refund", -Payment.amount), else_=Payment.amount)
    rows = db.execute(
        select(Payment.method, func.sum(case((Payment.kind == "payment", 1), else_=0)), func.sum(signed))
        .where(Payment.business_id == ctx.business_id, Payment.created_at >= lo, Payment.created_at < hi)
        .group_by(Payment.method)
        .order_by(func.sum(signed).desc())
    ).all()
    return [LabelAmount(label=m, count=c, amount=Decimal(a)) for m, c, a in rows]


@router.get("/reports/expenses-by-category", response_model=list[LabelAmount])
def report_expenses_by_category(
    db: DB,
    ctx: BusinessContext = require(Permission.EXPENSES_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
) -> list[LabelAmount]:
    start, end = _range(ctx, date_from, date_to)
    rows = db.execute(
        select(Expense.category, func.count(Expense.id), func.sum(Expense.amount))
        .where(
            Expense.business_id == ctx.business_id,
            Expense.deleted_at.is_(None),
            Expense.expense_date >= start,
            Expense.expense_date <= end,
        )
        .group_by(Expense.category)
        .order_by(func.sum(Expense.amount).desc())
    ).all()
    return [LabelAmount(label=c, count=n, amount=Decimal(a)) for c, n, a in rows]


@router.get("/reports/inventory", response_model=InventorySummary)
def report_inventory(db: DB, ctx: BusinessContext = require(Permission.INVENTORY_VIEW)) -> InventorySummary:
    return inventory_summary(db, ctx)


@router.get("/reports/low-stock", response_model=list[LowStockRow])
def report_low_stock(
    db: DB, ctx: BusinessContext = require(Permission.INVENTORY_VIEW), limit: Annotated[int, Query(ge=1, le=500)] = 100
) -> list[LowStockRow]:
    return low_stock(db, ctx, limit)


@router.get("/reports/sales-by-product.csv")
def export_sales_by_product(
    db: DB,
    ctx: BusinessContext = require(Permission.REPORTS_VIEW),
    date_from: DateFrom = None,
    date_to: DateFrom = None,
) -> StreamingResponse:
    subscriptions.require_feature(db, ctx.business_id, Feature.EXPORTS)
    start, end = _range(ctx, date_from, date_to)
    rows = top_products(db, ctx, start, end, limit=10_000, include_profit=ctx.can(Permission.PRODUCTS_VIEW_COST))
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["product", "quantity", f"revenue_{ctx.business.currency}", "gross_profit"])
    for r in rows:
        # Prefix formula-like cells to prevent CSV injection when opened in spreadsheets.
        name = f"'{r.name}" if r.name[:1] in ("=", "+", "-", "@") else r.name
        writer.writerow([name, str(r.quantity), str(r.revenue), "" if r.gross_profit is None else str(r.gross_profit)])
    filename = f"sales-by-product_{start}_{end}.csv"
    return StreamingResponse(
        iter([buf.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
