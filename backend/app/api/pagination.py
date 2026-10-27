from typing import Annotated, Generic, TypeVar

from fastapi import Depends, Query
from pydantic import BaseModel
from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from app.core.config import get_settings

T = TypeVar("T")


class PageParams(BaseModel):
    limit: int
    offset: int


def page_params(limit: Annotated[int, Query(ge=1)] = 25, offset: Annotated[int, Query(ge=0)] = 0) -> PageParams:
    return PageParams(limit=min(limit, get_settings().max_page_size), offset=offset)


Paging = Annotated[PageParams, Depends(page_params)]


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    limit: int
    offset: int


def paginate(db: Session, stmt: Select, params: PageParams) -> tuple[list, int]:
    total = db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0
    rows = list(db.scalars(stmt.limit(params.limit).offset(params.offset)))
    return rows, total
