"""Inventory ledger service shared by products, sales and returns.

Every stock change goes through `apply_stock_change` inside the caller's
transaction, with the product row locked, so the running balance and the
movement ledger can never disagree.
"""

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import utcnow
from app.core.errors import Conflict, NotFound
from app.core.money import format_qty, money, qty
from app.models import Product, StockMovement

STOCK_REASONS = ("opening", "receipt", "sale", "return", "adjustment", "damage", "count")


def lock_products(db: Session, business_id: uuid.UUID, product_ids: list[uuid.UUID]) -> dict[uuid.UUID, Product]:
    """Lock rows in a stable order (prevents deadlocks between concurrent sales)."""
    ids = sorted(set(product_ids), key=str)
    rows = db.scalars(
        select(Product)
        .where(Product.business_id == business_id, Product.id.in_(ids))
        .order_by(Product.id)
        .with_for_update()
    ).all()
    found = {p.id: p for p in rows}
    missing = [str(i) for i in ids if i not in found]
    if missing:
        raise NotFound("One or more products were not found.", details={"product_ids": missing})
    return found


def apply_stock_change(
    db: Session,
    product: Product,
    change: Decimal,
    reason: str,
    *,
    actor_id: uuid.UUID | None,
    enforce: bool,
    unit_cost: Decimal | None = None,
    reference_type: str | None = None,
    reference_id: object | None = None,
    note: str | None = None,
) -> StockMovement | None:
    """Apply a signed quantity change to a *locked* product and record the movement."""
    if reason not in STOCK_REASONS:
        raise ValueError(f"unknown stock reason {reason}")
    if not product.track_stock:
        return None
    change = qty(change)
    new_qty = qty(product.quantity_on_hand + change)
    if enforce and new_qty < 0:
        raise Conflict(
            f"Not enough stock for {product.name}. Available: {format_qty(product.quantity_on_hand)}.",
            code="insufficient_stock",
            details={"product_id": str(product.id), "available": format_qty(product.quantity_on_hand)},
        )
    product.quantity_on_hand = new_qty
    movement = StockMovement(
        business_id=product.business_id,
        product_id=product.id,
        reason=reason,
        quantity_change=change,
        quantity_after=new_qty,
        unit_cost=money(unit_cost) if unit_cost is not None else None,
        reference_type=reference_type,
        reference_id=str(reference_id) if reference_id is not None else None,
        note=note,
        created_by=actor_id,
        created_at=utcnow(),
    )
    db.add(movement)
    return movement


def weighted_average_cost(on_hand: Decimal, current_cost: Decimal, received: Decimal, unit_cost: Decimal) -> Decimal:
    """Moving weighted-average cost after a stock receipt."""
    if on_hand <= 0:
        return money(unit_cost)
    return money((on_hand * current_cost + received * unit_cost) / (on_hand + received))
