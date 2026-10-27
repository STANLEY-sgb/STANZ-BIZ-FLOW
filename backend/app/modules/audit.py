"""Audit trail: who did what, to which record, in which business."""

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import DB, BusinessContext, require
from app.api.pagination import Page, Paging, paginate
from app.core.database import utcnow
from app.core.permissions import Permission
from app.models import AuditEvent


def record(
    db: Session,
    *,
    action: str,
    entity_type: str,
    entity_id: object | None = None,
    business_id: uuid.UUID | None = None,
    actor_id: uuid.UUID | None = None,
    summary: str | None = None,
) -> None:
    """Add an audit event to the current transaction (committed with the change it describes).

    Never pass secrets, tokens or full personal data in `summary`.
    """
    db.add(
        AuditEvent(
            business_id=business_id,
            actor_user_id=actor_id,
            action=action,
            entity_type=entity_type,
            entity_id=str(entity_id) if entity_id is not None else None,
            summary=summary[:300] if summary else None,
            created_at=utcnow(),
        )
    )


class AuditEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    actor_user_id: uuid.UUID | None
    action: str
    entity_type: str
    entity_id: str | None
    summary: str | None
    created_at: datetime


router = APIRouter(prefix="/businesses/{business_id}/audit-events", tags=["audit"])


@router.get("", response_model=Page[AuditEventOut])
def list_audit_events(
    db: DB,
    paging: Paging,
    ctx: BusinessContext = require(Permission.AUDIT_VIEW),
    entity_type: Annotated[str | None, Query(max_length=40)] = None,
) -> Page[AuditEventOut]:
    stmt = select(AuditEvent).where(AuditEvent.business_id == ctx.business_id)
    if entity_type:
        stmt = stmt.where(AuditEvent.entity_type == entity_type)
    rows, total = paginate(db, stmt.order_by(AuditEvent.created_at.desc()), paging)
    return Page(items=rows, total=total, limit=paging.limit, offset=paging.offset)
