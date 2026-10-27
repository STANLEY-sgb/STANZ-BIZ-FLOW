"""Offline synchronisation.

Devices queue sales locally with a unique `client_reference` and push them
here in batches. Each operation is validated exactly like an online sale
(authentication, active membership, permissions, current prices, stock) and
committed independently, so one rejected operation never blocks the rest.

Outcomes per operation:
* accepted  — recorded now; receipt number assigned by the server
* duplicate — already recorded earlier (safe retry after a timeout or app kill)
* rejected  — not recorded; `error.code` explains why (e.g. insufficient_stock,
              price_changed, product_archived). The device keeps it for review.
"""

from datetime import datetime
from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.api.deps import DB, BusinessContext, Ctx
from app.core.database import utcnow
from app.core.errors import AppError
from app.modules.sales import SaleCreate, create_sale

router = APIRouter(prefix="/businesses/{business_id}/sync", tags=["sync"])


class SyncBatchIn(BaseModel):
    device_id: str = Field(min_length=4, max_length=64)
    sales: list[SaleCreate] = Field(default_factory=list, max_length=100)


class SyncError(BaseModel):
    code: str
    message: str
    details: dict = Field(default_factory=dict)


class SyncResult(BaseModel):
    client_reference: str
    status: Literal["accepted", "duplicate", "rejected"]
    sale_id: str | None = None
    receipt_number: str | None = None
    error: SyncError | None = None


class SyncBatchOut(BaseModel):
    server_time: datetime
    results: list[SyncResult]


@router.post("/sales", response_model=SyncBatchOut)
def push_sales(body: SyncBatchIn, db: DB, ctx: Ctx) -> SyncBatchOut:
    results: list[SyncResult] = []
    for op in body.sales:
        op.device_id = op.device_id or body.device_id
        try:
            result = _push_one(db, ctx, op)
        except AppError as exc:
            db.rollback()
            result = SyncResult(
                client_reference=op.client_reference,
                status="rejected",
                error=SyncError(code=exc.code, message=exc.message, details=exc.details),
            )
        results.append(result)
    return SyncBatchOut(server_time=utcnow(), results=results)


def _push_one(db: DB, ctx: BusinessContext, op: SaleCreate) -> SyncResult:
    outcome = create_sale(db, ctx, op, source="offline")
    return SyncResult(
        client_reference=op.client_reference,
        status="accepted" if outcome.created else "duplicate",
        sale_id=str(outcome.sale.id),
        receipt_number=outcome.sale.receipt_number,
    )


@router.get("/status")
def sync_status(ctx: Ctx) -> dict:
    """Lightweight check a device runs before syncing: confirms membership is still active."""
    return {
        "server_time": utcnow(),
        "role": ctx.role,
        "permissions": sorted(ctx.permissions),
        "business_updated_at": ctx.business.updated_at,
    }
