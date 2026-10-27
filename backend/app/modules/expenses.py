"""Operational expense tracking (not a full accounting ledger)."""

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select

from app.api.deps import DB, BusinessContext, require
from app.api.pagination import Page, Paging, paginate
from app.core.database import utcnow
from app.core.errors import NotFound
from app.core.money import MoneyOut
from app.core.permissions import Permission
from app.core.plans import Feature
from app.models import Expense
from app.modules import audit, subscriptions

router = APIRouter(prefix="/businesses/{business_id}/expenses", tags=["expenses"])

EXPENSE_CATEGORIES = (
    "rent",
    "salaries",
    "utilities",
    "transport",
    "stock_purchase",
    "marketing",
    "airtime_data",
    "repairs",
    "taxes_fees",
    "supplies",
    "other",
)

Amount = Annotated[Decimal, Field(gt=0, max_digits=14, decimal_places=2)]


class ExpenseIn(BaseModel):
    category: Literal[EXPENSE_CATEGORIES]  # type: ignore[valid-type]
    amount: Amount
    expense_date: date
    description: str | None = Field(default=None, max_length=300)
    payment_method: Literal["cash", "mobile_money", "bank_transfer", "card", "other"] | None = None
    supplier: str | None = Field(default=None, max_length=160)


class ExpenseUpdate(BaseModel):
    category: Literal[EXPENSE_CATEGORIES] | None = None  # type: ignore[valid-type]
    amount: Amount | None = None
    expense_date: date | None = None
    description: str | None = Field(default=None, max_length=300)
    payment_method: Literal["cash", "mobile_money", "bank_transfer", "card", "other"] | None = None
    supplier: str | None = Field(default=None, max_length=160)


class ExpenseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    category: str
    amount: MoneyOut
    currency: str
    expense_date: date
    description: str | None
    payment_method: str | None
    supplier: str | None
    created_by: uuid.UUID
    created_at: datetime
    updated_at: datetime


def _get(db: DB, ctx: BusinessContext, expense_id: uuid.UUID) -> Expense:
    e = db.scalar(
        select(Expense).where(
            Expense.id == expense_id, Expense.business_id == ctx.business_id, Expense.deleted_at.is_(None)
        )
    )
    if e is None:
        raise NotFound("Expense not found.")
    return e


@router.get("/categories", response_model=list[str])
def expense_categories(ctx: BusinessContext = require(Permission.EXPENSES_VIEW)) -> list[str]:
    return list(EXPENSE_CATEGORIES)


@router.get("", response_model=Page[ExpenseOut])
def list_expenses(
    db: DB,
    paging: Paging,
    ctx: BusinessContext = require(Permission.EXPENSES_VIEW),
    date_from: date | None = None,
    date_to: date | None = None,
    category: Annotated[str | None, Query(max_length=60)] = None,
) -> Page[ExpenseOut]:
    stmt = select(Expense).where(Expense.business_id == ctx.business_id, Expense.deleted_at.is_(None))
    if date_from:
        stmt = stmt.where(Expense.expense_date >= date_from)
    if date_to:
        stmt = stmt.where(Expense.expense_date <= date_to)
    if category:
        stmt = stmt.where(Expense.category == category)
    rows, total = paginate(db, stmt.order_by(Expense.expense_date.desc(), Expense.created_at.desc()), paging)
    return Page(items=rows, total=total, limit=paging.limit, offset=paging.offset)


@router.post("", response_model=ExpenseOut, status_code=status.HTTP_201_CREATED)
def create_expense(body: ExpenseIn, db: DB, ctx: BusinessContext = require(Permission.EXPENSES_MANAGE)) -> Expense:
    subscriptions.require_feature(db, ctx.business_id, Feature.EXPENSES)
    e = Expense(
        business_id=ctx.business_id, currency=ctx.business.currency, created_by=ctx.user.id, **body.model_dump()
    )
    db.add(e)
    db.flush()
    audit.record(
        db,
        action="expense.created",
        entity_type="expense",
        entity_id=e.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{e.category} {e.amount}",
    )
    db.commit()
    return e


@router.patch("/{expense_id}", response_model=ExpenseOut)
def update_expense(
    expense_id: uuid.UUID, body: ExpenseUpdate, db: DB, ctx: BusinessContext = require(Permission.EXPENSES_MANAGE)
) -> Expense:
    e = _get(db, ctx, expense_id)
    changes = body.model_dump(exclude_unset=True)
    before = f"{e.category} {e.amount} {e.expense_date}"
    for field, value in changes.items():
        setattr(e, field, value)
    audit.record(
        db,
        action="expense.updated",
        entity_type="expense",
        entity_id=e.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"was {before}; changed {', '.join(sorted(changes))}",
    )
    db.commit()
    return e


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense(expense_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.EXPENSES_MANAGE)) -> None:
    e = _get(db, ctx, expense_id)
    e.deleted_at = utcnow()  # soft delete keeps the financial audit trail intact
    audit.record(
        db,
        action="expense.deleted",
        entity_type="expense",
        entity_id=e.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{e.category} {e.amount} {e.expense_date}",
    )
    db.commit()
