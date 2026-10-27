"""Customer records (minimal personal data, tenant-scoped)."""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import func, or_, select

from app.api.deps import DB, BusinessContext, require
from app.api.pagination import Page, Paging, paginate
from app.core.errors import NotFound
from app.core.money import MoneyOut
from app.core.permissions import Permission
from app.core.plans import Feature
from app.models import Customer, Sale
from app.modules import audit, subscriptions

router = APIRouter(prefix="/businesses/{business_id}/customers", tags=["customers"])


class CustomerIn(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    phone: str | None = Field(default=None, max_length=32)
    email: EmailStr | None = None
    reference: str | None = Field(default=None, max_length=64)
    notes: str | None = Field(default=None, max_length=1000)


class CustomerUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    phone: str | None = Field(default=None, max_length=32)
    email: EmailStr | None = None
    reference: str | None = Field(default=None, max_length=64)
    notes: str | None = Field(default=None, max_length=1000)


class CustomerOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    phone: str | None
    email: str | None
    reference: str | None
    notes: str | None
    created_at: datetime


class CustomerDetail(CustomerOut):
    sales_count: int
    total_spent: MoneyOut


def _get(db: DB, ctx: BusinessContext, customer_id: uuid.UUID) -> Customer:
    c = db.scalar(select(Customer).where(Customer.id == customer_id, Customer.business_id == ctx.business_id))
    if c is None:
        raise NotFound("Customer not found.")
    return c


@router.get("", response_model=Page[CustomerOut])
def list_customers(
    db: DB,
    paging: Paging,
    ctx: BusinessContext = require(Permission.CUSTOMERS_VIEW),
    q: Annotated[str | None, Query(max_length=100)] = None,
) -> Page[CustomerOut]:
    stmt = select(Customer).where(Customer.business_id == ctx.business_id)
    if q:
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(or_(func.lower(Customer.name).like(like), Customer.phone.like(f"%{q.strip()}%")))
    rows, total = paginate(db, stmt.order_by(func.lower(Customer.name), Customer.id), paging)
    return Page(items=rows, total=total, limit=paging.limit, offset=paging.offset)


@router.post("", response_model=CustomerOut, status_code=status.HTTP_201_CREATED)
def create_customer(body: CustomerIn, db: DB, ctx: BusinessContext = require(Permission.CUSTOMERS_MANAGE)) -> Customer:
    subscriptions.require_feature(db, ctx.business_id, Feature.CUSTOMERS)
    c = Customer(business_id=ctx.business_id, **body.model_dump())
    db.add(c)
    db.commit()
    return c


@router.get("/{customer_id}", response_model=CustomerDetail)
def read_customer(
    customer_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.CUSTOMERS_VIEW)
) -> CustomerDetail:
    c = _get(db, ctx, customer_id)
    count, spent = db.execute(
        select(func.count(), func.coalesce(func.sum(Sale.total - Sale.refunded_total), 0)).where(
            Sale.business_id == ctx.business_id, Sale.customer_id == c.id
        )
    ).one()
    return CustomerDetail(**CustomerOut.model_validate(c).model_dump(), sales_count=count, total_spent=Decimal(spent))


@router.patch("/{customer_id}", response_model=CustomerOut)
def update_customer(
    customer_id: uuid.UUID, body: CustomerUpdate, db: DB, ctx: BusinessContext = require(Permission.CUSTOMERS_MANAGE)
) -> Customer:
    c = _get(db, ctx, customer_id)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(c, field, value)
    db.commit()
    return c


@router.delete("/{customer_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_customer(
    customer_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.CUSTOMERS_MANAGE)
) -> None:
    """Erase personal data. Sales keep their financial record but lose the customer link (SET NULL)."""
    c = _get(db, ctx, customer_id)
    for sale in db.scalars(select(Sale).where(Sale.business_id == ctx.business_id, Sale.customer_id == c.id)):
        sale.customer_id = None
    db.delete(c)
    audit.record(
        db,
        action="customer.deleted",
        entity_type="customer",
        entity_id=customer_id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
    )
    db.commit()
