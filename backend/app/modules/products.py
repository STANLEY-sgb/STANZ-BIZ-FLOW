"""Product catalogue, categories and stock adjustments."""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import DB, BusinessContext, require
from app.api.pagination import Page, Paging, paginate
from app.core.errors import AppError, Conflict, NotFound
from app.core.money import MoneyIn, MoneyOut, QtyOut, qty
from app.core.permissions import Permission
from app.core.storage import signed_url
from app.models import Category, Product, StockMovement
from app.modules import audit, subscriptions
from app.modules.inventory import apply_stock_change, lock_products, weighted_average_cost

router = APIRouter(prefix="/businesses/{business_id}", tags=["products"])

# Attribute keys holding device identifiers. Hidden unless the role may view them.
SENSITIVE_ATTRIBUTES = frozenset({"imei", "imei2", "serial_number"})


# --- Schemas ---------------------------------------------------------------------------------


class CategoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class CategoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    product_count: int = 0


Attributes = dict[str, str | int | bool | None]


class ProductBase(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=4000)
    sku: str | None = Field(default=None, max_length=64)
    barcode: str | None = Field(default=None, max_length=64)
    unit: str = Field(default="pcs", max_length=16)
    category_id: uuid.UUID | None = None
    cost_price: MoneyIn = Decimal("0")
    selling_price: MoneyIn
    track_stock: bool = True
    reorder_level: Annotated[Decimal, Field(ge=0, max_digits=14, decimal_places=3)] = Decimal("0")
    attributes: Attributes = Field(default_factory=dict)

    @model_validator(mode="after")
    def _attrs(self) -> "ProductBase":
        if len(self.attributes) > 30 or any(len(k) > 40 for k in self.attributes):
            raise ValueError("Too many or too long attribute names.")
        for value in self.attributes.values():
            if isinstance(value, str) and len(value) > 200:
                raise ValueError("Attribute values must be 200 characters or fewer.")
        return self


class ProductCreate(ProductBase):
    opening_stock: Annotated[Decimal, Field(ge=0, max_digits=14, decimal_places=3)] = Decimal("0")


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=4000)
    sku: str | None = Field(default=None, max_length=64)
    barcode: str | None = Field(default=None, max_length=64)
    unit: str | None = Field(default=None, max_length=16)
    category_id: uuid.UUID | None = None
    cost_price: MoneyIn | None = None
    selling_price: MoneyIn | None = None
    track_stock: bool | None = None
    reorder_level: Annotated[Decimal, Field(ge=0, max_digits=14, decimal_places=3)] | None = None
    attributes: Attributes | None = None
    # Optimistic concurrency: if supplied and stale, the update is rejected with 409.
    version: int | None = None


class ProductOut(BaseModel):
    id: uuid.UUID
    name: str
    description: str | None
    sku: str | None
    barcode: str | None
    unit: str
    category_id: uuid.UUID | None
    cost_price: MoneyOut | None
    selling_price: MoneyOut
    track_stock: bool
    quantity_on_hand: QtyOut
    reorder_level: QtyOut
    stock_status: str
    attributes: dict[str, Any]
    image_url: str | None = None
    is_active: bool
    version: int
    created_at: datetime
    updated_at: datetime


class StockAdjustmentIn(BaseModel):
    type: Literal["receipt", "damage", "adjustment", "count", "return"]
    # receipt/damage/return: positive quantity. adjustment: signed. count: use counted_quantity.
    quantity: Annotated[Decimal, Field(max_digits=14, decimal_places=3)] | None = None
    counted_quantity: Annotated[Decimal, Field(ge=0, max_digits=14, decimal_places=3)] | None = None
    unit_cost: MoneyIn | None = None
    note: str | None = Field(default=None, max_length=300)

    @model_validator(mode="after")
    def _check(self) -> "StockAdjustmentIn":
        if self.type == "count":
            if self.counted_quantity is None:
                raise ValueError("counted_quantity is required for a stock count.")
        elif self.quantity is None or self.quantity == 0:
            raise ValueError("quantity is required and cannot be zero.")
        elif self.type != "adjustment" and self.quantity < 0:
            raise ValueError("quantity must be positive for this type; use 'adjustment' for corrections.")
        if self.type in ("adjustment", "damage", "count") and not (self.note and self.note.strip()):
            raise ValueError("A note explaining the reason is required.")
        return self


class StockMovementOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    product_id: uuid.UUID
    reason: str
    quantity_change: QtyOut
    quantity_after: QtyOut
    reference_type: str | None
    reference_id: str | None
    note: str | None
    created_by: uuid.UUID | None
    created_at: datetime


# --- Helpers ---------------------------------------------------------------------------------


def stock_status(p: Product) -> str:
    if not p.track_stock:
        return "untracked"
    if p.quantity_on_hand <= 0:
        return "out_of_stock"
    if p.quantity_on_hand <= p.reorder_level:
        return "low_stock"
    return "in_stock"


def product_out(p: Product, ctx: BusinessContext) -> ProductOut:
    attributes = dict(p.attributes or {})
    if not ctx.can(Permission.DEVICE_IDS_VIEW):
        attributes = {k: v for k, v in attributes.items() if k not in SENSITIVE_ATTRIBUTES}
    return ProductOut(
        id=p.id,
        name=p.name,
        description=p.description,
        sku=p.sku,
        barcode=p.barcode,
        unit=p.unit,
        category_id=p.category_id,
        cost_price=p.cost_price if ctx.can(Permission.PRODUCTS_VIEW_COST) else None,
        selling_price=p.selling_price,
        track_stock=p.track_stock,
        quantity_on_hand=p.quantity_on_hand,
        reorder_level=p.reorder_level,
        stock_status=stock_status(p),
        attributes=attributes,
        image_url=signed_url(p.image_file_id),
        is_active=p.is_active,
        version=p.version,
        created_at=p.created_at,
        updated_at=p.updated_at,
    )


def _clean(value: str | None) -> str | None:
    value = value.strip() if value else None
    return value or None


def _check_category(db: Session, business_id: uuid.UUID, category_id: uuid.UUID | None) -> None:
    if (
        category_id is not None
        and db.scalar(select(Category.id).where(Category.id == category_id, Category.business_id == business_id))
        is None
    ):
        raise AppError("Category not found.", code="category_not_found")


def _check_unique(
    db: Session, business_id: uuid.UUID, sku: str | None, barcode: str | None, exclude: uuid.UUID | None = None
) -> None:
    for field, value in (("sku", sku), ("barcode", barcode)):
        if value is None:
            continue
        stmt = select(Product.id).where(Product.business_id == business_id, getattr(Product, field) == value)
        if exclude:
            stmt = stmt.where(Product.id != exclude)
        if db.scalar(stmt):
            raise Conflict(f"Another product already uses this {field.upper()}.", code=f"duplicate_{field}")


def get_product(db: Session, business_id: uuid.UUID, product_id: uuid.UUID) -> Product:
    p = db.scalar(select(Product).where(Product.id == product_id, Product.business_id == business_id))
    if p is None:
        raise NotFound("Product not found.")
    return p


# --- Categories ------------------------------------------------------------------------------


@router.get("/categories", response_model=list[CategoryOut])
def list_categories(db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_VIEW)) -> list[CategoryOut]:
    counts = dict(
        db.execute(
            select(Product.category_id, func.count())
            .where(Product.business_id == ctx.business_id, Product.is_active)
            .group_by(Product.category_id)
        ).all()
    )
    cats = db.scalars(select(Category).where(Category.business_id == ctx.business_id).order_by(Category.name))
    return [CategoryOut(id=c.id, name=c.name, product_count=counts.get(c.id, 0)) for c in cats]


@router.post("/categories", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(
    body: CategoryIn, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> CategoryOut:
    name = body.name.strip()
    if db.scalar(
        select(Category.id).where(Category.business_id == ctx.business_id, func.lower(Category.name) == name.lower())
    ):
        raise Conflict("A category with this name already exists.", code="duplicate_category")
    cat = Category(business_id=ctx.business_id, name=name)
    db.add(cat)
    db.commit()
    return CategoryOut(id=cat.id, name=cat.name)


@router.patch("/categories/{category_id}", response_model=CategoryOut)
def rename_category(
    category_id: uuid.UUID, body: CategoryIn, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> CategoryOut:
    cat = db.scalar(select(Category).where(Category.id == category_id, Category.business_id == ctx.business_id))
    if cat is None:
        raise NotFound("Category not found.")
    cat.name = body.name.strip()
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise Conflict("A category with this name already exists.", code="duplicate_category") from exc
    return CategoryOut(id=cat.id, name=cat.name)


@router.delete("/categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(category_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)) -> None:
    cat = db.scalar(select(Category).where(Category.id == category_id, Category.business_id == ctx.business_id))
    if cat is None:
        raise NotFound("Category not found.")
    # Products keep existing and become uncategorised (FK is ON DELETE SET NULL).
    for p in db.scalars(select(Product).where(Product.category_id == cat.id, Product.business_id == ctx.business_id)):
        p.category_id = None
    db.delete(cat)
    db.commit()


# --- Products --------------------------------------------------------------------------------


@router.get("/products", response_model=Page[ProductOut])
def list_products(
    db: DB,
    paging: Paging,
    ctx: BusinessContext = require(Permission.PRODUCTS_VIEW),
    q: Annotated[str | None, Query(max_length=100)] = None,
    category_id: uuid.UUID | None = None,
    stock: Literal["in_stock", "low_stock", "out_of_stock"] | None = None,
    include_archived: bool = False,
    updated_since: datetime | None = None,
) -> Page[ProductOut]:
    stmt = select(Product).where(Product.business_id == ctx.business_id)
    if not include_archived:
        stmt = stmt.where(Product.is_active)
    if q:
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(
            or_(func.lower(Product.name).like(like), func.lower(Product.sku).like(like), Product.barcode == q.strip())
        )
    if category_id:
        stmt = stmt.where(Product.category_id == category_id)
    if stock == "out_of_stock":
        stmt = stmt.where(Product.track_stock, Product.quantity_on_hand <= 0)
    elif stock == "low_stock":
        stmt = stmt.where(
            Product.track_stock, Product.quantity_on_hand > 0, Product.quantity_on_hand <= Product.reorder_level
        )
    elif stock == "in_stock":
        stmt = stmt.where(or_(~Product.track_stock, Product.quantity_on_hand > 0))
    if updated_since:
        stmt = stmt.where(Product.updated_at > updated_since)
    order = Product.updated_at if updated_since else func.lower(Product.name)
    rows, total = paginate(db, stmt.order_by(order, Product.id), paging)
    return Page(items=[product_out(p, ctx) for p in rows], total=total, limit=paging.limit, offset=paging.offset)


@router.get("/products/lookup", response_model=ProductOut)
def lookup_by_code(
    code: Annotated[str, Query(min_length=1, max_length=64)],
    db: DB,
    ctx: BusinessContext = require(Permission.PRODUCTS_VIEW),
) -> ProductOut:
    """Exact barcode or SKU match — used by the scanner on the POS screen."""
    p = db.scalar(
        select(Product).where(
            Product.business_id == ctx.business_id, Product.is_active, or_(Product.barcode == code, Product.sku == code)
        )
    )
    if p is None:
        raise NotFound("No product matches this code.")
    return product_out(p, ctx)


@router.post("/products", response_model=ProductOut, status_code=status.HTTP_201_CREATED)
def create_product(
    body: ProductCreate, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> ProductOut:
    subscriptions.check_product_limit(db, ctx.business_id)
    sku, barcode = _clean(body.sku), _clean(body.barcode)
    _check_category(db, ctx.business_id, body.category_id)
    _check_unique(db, ctx.business_id, sku, barcode)
    p = Product(
        business_id=ctx.business_id,
        **body.model_dump(exclude={"opening_stock", "sku", "barcode"}),
        sku=sku,
        barcode=barcode,
        quantity_on_hand=Decimal("0"),
    )
    p.name = p.name.strip()
    db.add(p)
    db.flush()
    if body.opening_stock > 0 and p.track_stock:
        apply_stock_change(
            db,
            p,
            body.opening_stock,
            "opening",
            actor_id=ctx.user.id,
            enforce=False,
            unit_cost=body.cost_price,
            note="Opening stock",
        )
    audit.record(
        db,
        action="product.created",
        entity_type="product",
        entity_id=p.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=p.name,
    )
    db.commit()
    return product_out(p, ctx)


@router.get("/products/{product_id}", response_model=ProductOut)
def read_product(product_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_VIEW)) -> ProductOut:
    return product_out(get_product(db, ctx.business_id, product_id), ctx)


@router.patch("/products/{product_id}", response_model=ProductOut)
def update_product(
    product_id: uuid.UUID, body: ProductUpdate, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> ProductOut:
    p = lock_products(db, ctx.business_id, [product_id])[product_id]
    if body.version is not None and body.version != p.version:
        raise Conflict(
            "This product was changed by someone else. Reload and try again.",
            code="version_conflict",
            details={"current_version": p.version},
        )
    changes = body.model_dump(exclude_unset=True, exclude={"version"})
    if "sku" in changes:
        changes["sku"] = _clean(changes["sku"])
    if "barcode" in changes:
        changes["barcode"] = _clean(changes["barcode"])
    if "category_id" in changes:
        _check_category(db, ctx.business_id, changes["category_id"])
    if "cost_price" in changes and not ctx.can(Permission.PRODUCTS_VIEW_COST):
        changes.pop("cost_price")
    if "attributes" in changes and not ctx.can(Permission.DEVICE_IDS_VIEW):
        # Users who cannot see device identifiers must not overwrite them either.
        kept = {k: v for k, v in (p.attributes or {}).items() if k in SENSITIVE_ATTRIBUTES}
        changes["attributes"] = {k: v for k, v in changes["attributes"].items() if k not in SENSITIVE_ATTRIBUTES} | kept
    _check_unique(db, ctx.business_id, changes.get("sku", p.sku), changes.get("barcode", p.barcode), exclude=p.id)
    # Note: price edits only affect future sales; sale_items keep their own price snapshot.
    for field, value in changes.items():
        setattr(p, field, value.strip() if field == "name" else value)
    p.version += 1
    audit.record(
        db,
        action="product.updated",
        entity_type="product",
        entity_id=p.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=", ".join(sorted(changes)),
    )
    db.commit()
    return product_out(p, ctx)


def _set_active(db: Session, ctx: BusinessContext, product_id: uuid.UUID, active: bool) -> ProductOut:
    p = get_product(db, ctx.business_id, product_id)
    if active and not p.is_active:
        subscriptions.check_product_limit(db, ctx.business_id)
    p.is_active = active
    p.version += 1
    audit.record(
        db,
        action="product.restored" if active else "product.archived",
        entity_type="product",
        entity_id=p.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=p.name,
    )
    db.commit()
    return product_out(p, ctx)


@router.post("/products/{product_id}/archive", response_model=ProductOut)
def archive_product(
    product_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> ProductOut:
    return _set_active(db, ctx, product_id, False)


@router.post("/products/{product_id}/restore", response_model=ProductOut)
def restore_product(
    product_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> ProductOut:
    return _set_active(db, ctx, product_id, True)


# --- Stock -----------------------------------------------------------------------------------


@router.post(
    "/products/{product_id}/stock-movements", response_model=StockMovementOut, status_code=status.HTTP_201_CREATED
)
def adjust_stock(
    product_id: uuid.UUID, body: StockAdjustmentIn, db: DB, ctx: BusinessContext = require(Permission.INVENTORY_ADJUST)
) -> StockMovement:
    p = lock_products(db, ctx.business_id, [product_id])[product_id]
    if not p.track_stock:
        raise AppError("Stock is not tracked for this product.", code="stock_not_tracked")
    if body.type == "count":
        change = qty(body.counted_quantity - p.quantity_on_hand)
        if change == 0:
            raise AppError("The counted quantity matches the current stock; nothing to record.", code="no_change")
    elif body.type == "damage":
        change = -body.quantity
    else:
        change = body.quantity
    if body.type == "receipt" and body.unit_cost is not None:
        p.cost_price = weighted_average_cost(p.quantity_on_hand, p.cost_price, body.quantity, body.unit_cost)
    # Damage and negative adjustments cannot take stock below zero.
    movement = apply_stock_change(
        db,
        p,
        change,
        body.type,
        actor_id=ctx.user.id,
        enforce=change < 0,
        unit_cost=body.unit_cost if body.type == "receipt" else None,
        note=_clean(body.note),
    )
    p.version += 1
    audit.record(
        db,
        action=f"stock.{body.type}",
        entity_type="product",
        entity_id=p.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{change:+} {p.unit}",
    )
    db.commit()
    return movement


@router.get("/stock-movements", response_model=Page[StockMovementOut])
def list_stock_movements(
    db: DB,
    paging: Paging,
    ctx: BusinessContext = require(Permission.INVENTORY_VIEW),
    product_id: uuid.UUID | None = None,
    reason: str | None = None,
) -> Page[StockMovementOut]:
    stmt = select(StockMovement).where(StockMovement.business_id == ctx.business_id)
    if product_id:
        stmt = stmt.where(StockMovement.product_id == product_id)
    if reason:
        stmt = stmt.where(StockMovement.reason == reason)
    rows, total = paginate(db, stmt.order_by(StockMovement.created_at.desc(), StockMovement.id), paging)
    return Page(items=rows, total=total, limit=paging.limit, offset=paging.offset)
