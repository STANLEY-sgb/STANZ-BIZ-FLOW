"""Bulk product import (CSV / Excel) and export.

Flow: the client uploads a file with ``dry_run=true`` and gets a row-by-row report
(what would be created, updated or skipped, and every validation error). It then
uploads the same file with ``dry_run=false`` to apply it. Applying is a single
transaction: either every accepted row is saved or nothing is.

Rules:
* Existing products are matched by SKU, then barcode, within the business only.
* Existing products are skipped unless ``update_existing=true``.
* Stock on an existing product is never overwritten directly. A different quantity
  is recorded as a stock-count movement with the note "Import".
* Files with errors are rejected unless ``skip_invalid=true``, which imports only
  the valid rows.
"""

import csv
import io
import re
import uuid
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from typing import Annotated, Any

from fastapi import APIRouter, File, Query, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import DB, BusinessContext, require
from app.core.errors import AppError, PaymentRequired, Unprocessable
from app.core.money import format_qty, money, qty
from app.core.permissions import Permission
from app.models import Category, Product
from app.modules import audit, subscriptions
from app.modules.inventory import apply_stock_change
from app.modules.products import SENSITIVE_ATTRIBUTES

router = APIRouter(prefix="/businesses/{business_id}/products", tags=["products"])

MAX_FILE_BYTES = 2 * 1024 * 1024
MAX_ROWS = 5000
PREVIEW_ROWS = 50

# Accepted header spellings → canonical field. Matching ignores case, spaces, underscores and punctuation.
HEADERS: dict[str, tuple[str, ...]] = {
    "name": ("name", "product", "productname", "item", "itemname", "description1"),
    "selling_price": ("sellingprice", "price", "saleprice", "unitprice", "retailprice"),
    "cost_price": ("costprice", "cost", "buyingprice", "purchaseprice", "unitcost"),
    "sku": ("sku", "code", "itemcode", "productcode"),
    "barcode": ("barcode", "ean", "upc", "gtin"),
    "category": ("category", "group", "department"),
    "quantity": ("quantity", "qty", "stock", "openingstock", "quantityonhand", "onhand"),
    "reorder_level": ("reorderlevel", "reorder", "alertlevel", "minstock", "lowstockalert", "lowstockalertlevel"),
    "unit": ("unit", "uom"),
    "description": ("description", "details", "notes"),
    "brand": ("brand", "make"),
    "model": ("model",),
    "storage": ("storage", "size", "capacity"),
    "colour": ("colour", "color"),
    "condition": ("condition",),
    "warranty_months": ("warrantymonths", "warranty"),
    "imei": ("imei", "serial", "serialnumber", "imeiserial"),
}
ATTRIBUTE_FIELDS = ("brand", "model", "storage", "colour", "condition", "warranty_months", "imei")
EXPORT_COLUMNS = (
    "name",
    "sku",
    "barcode",
    "category",
    "selling_price",
    "cost_price",
    "quantity",
    "reorder_level",
    "unit",
    "description",
    "brand",
    "model",
    "storage",
    "colour",
    "condition",
    "warranty_months",
    "imei",
)


def _key(header: str) -> str:
    return re.sub(r"[^a-z0-9]", "", header.lower())


_LOOKUP = {alias: canonical for canonical, aliases in HEADERS.items() for alias in aliases}


# --- Parsing -----------------------------------------------------------------------------------


def read_table(filename: str, content: bytes) -> list[list[str]]:
    """Return rows of cell strings from a CSV or XLSX upload."""
    name = (filename or "").lower()
    if name.endswith(".xlsx") or content[:2] == b"PK":
        try:
            from openpyxl import load_workbook

            wb = load_workbook(io.BytesIO(content), read_only=True, data_only=True)
        except Exception as exc:  # noqa: BLE001 - any parse failure is a user-facing format error
            raise AppError(
                "This Excel file could not be read. Save it as .xlsx or CSV and try again.", code="unreadable_file"
            ) from exc
        sheet = wb.worksheets[0]
        rows = [["" if v is None else _cell(v) for v in row] for row in sheet.iter_rows(values_only=True)]
        wb.close()
        return rows
    if name.endswith((".csv", ".txt")) or not name:
        for encoding in ("utf-8-sig", "cp1252"):
            try:
                text = content.decode(encoding)
                break
            except UnicodeDecodeError:
                continue
        try:
            dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t")
        except csv.Error:
            dialect = csv.excel
        return [row for row in csv.reader(io.StringIO(text), dialect)]
    raise AppError("Upload a CSV or Excel (.xlsx) file.", code="unsupported_file_type")


def _cell(value: Any) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))  # Excel stores 650000 as 650000.0
    return str(value).strip()


def _amount(raw: str) -> Decimal | None:
    cleaned = re.sub(r"(?i)ugx|ksh|kes|tzs|usd|\$|,|\s", "", raw)
    if cleaned == "":
        return None
    return Decimal(cleaned)


@dataclass
class RowResult:
    row: int
    action: str  # create | update | skip | error
    data: dict[str, Any] = field(default_factory=dict)
    errors: list[dict[str, str]] = field(default_factory=list)
    product: Product | None = None
    message: str | None = None


def _validate(row_no: int, values: dict[str, str]) -> RowResult:
    result = RowResult(row=row_no, action="create")

    def err(column: str, message: str) -> None:
        result.errors.append({"row": str(row_no), "column": column, "message": message})

    name = values.get("name", "").strip()
    if not name:
        err("name", "Name is required.")
    elif len(name) > 160:
        err("name", "Name must be 160 characters or fewer.")
    data: dict[str, Any] = {"name": name}

    for column, required in (("selling_price", True), ("cost_price", False)):
        raw = values.get(column, "")
        try:
            amount = _amount(raw)
        except InvalidOperation:
            err(column, f"'{raw}' is not a valid amount.")
            continue
        if amount is None:
            if required:
                err(column, "Selling price is required.")
            continue
        if amount < 0 or amount.as_tuple().exponent < -2 or amount >= Decimal("1e12"):
            err(column, f"'{raw}' must be a positive amount with at most 2 decimal places.")
            continue
        data[column] = money(amount)

    for column in ("quantity", "reorder_level"):
        raw = values.get(column, "").replace(",", "").strip()
        if not raw:
            continue
        try:
            value = Decimal(raw)
        except InvalidOperation:
            err(column, f"'{raw}' is not a valid number.")
            continue
        if value < 0 or value.as_tuple().exponent < -3:
            err(column, f"'{raw}' must be zero or more, with at most 3 decimal places.")
            continue
        data[column] = qty(value)

    for column, limit in (("sku", 64), ("barcode", 64), ("category", 80), ("unit", 16), ("description", 4000)):
        value = values.get(column, "").strip()
        if len(value) > limit:
            err(column, f"Must be {limit} characters or fewer.")
        elif value:
            data[column] = value

    attributes: dict[str, Any] = {}
    for column in ATTRIBUTE_FIELDS:
        value = values.get(column, "").strip()
        if not value:
            continue
        if column == "warranty_months":
            if not value.isdigit():
                err(column, "Warranty must be a whole number of months.")
                continue
            attributes[column] = int(value)
        elif len(value) > 200:
            err(column, "Must be 200 characters or fewer.")
        else:
            attributes[column] = value.lower() if column == "condition" else value
    data["attributes"] = attributes
    result.data = data
    if result.errors:
        result.action = "error"
    return result


# --- Planning and applying ---------------------------------------------------------------------


def plan_import(db: Session, ctx: BusinessContext, rows: list[list[str]], update_existing: bool) -> list[RowResult]:
    if not rows or not any(cell.strip() for cell in rows[0]):
        raise AppError("The file is empty. The first row must contain column headings.", code="empty_file")
    header = [_LOOKUP.get(_key(h)) for h in rows[0]]
    if "name" not in header or "selling_price" not in header:
        raise AppError(
            "The file needs at least a 'Name' and a 'Selling price' column.",
            code="missing_columns",
            details={"recognised": [h for h in header if h]},
        )
    body = [r for r in rows[1:] if any(c.strip() for c in r)]
    if len(body) > MAX_ROWS:
        raise AppError(f"Import at most {MAX_ROWS} products per file.", code="too_many_rows")

    existing = db.scalars(select(Product).where(Product.business_id == ctx.business_id)).all()
    by_sku = {p.sku.lower(): p for p in existing if p.sku}
    by_barcode = {p.barcode: p for p in existing if p.barcode}
    seen_sku: dict[str, int] = {}
    seen_barcode: dict[str, int] = {}
    results: list[RowResult] = []

    for index, raw in enumerate(body, start=2):  # row 1 is the header, as a spreadsheet user sees it
        values = {col: (raw[i] if i < len(raw) else "") for i, col in enumerate(header) if col}
        result = _validate(index, values)
        sku, barcode = result.data.get("sku"), result.data.get("barcode")
        for key, value, seen in (("sku", sku and sku.lower(), seen_sku), ("barcode", barcode, seen_barcode)):
            if value and value in seen:
                result.errors.append(
                    {"row": str(index), "column": key, "message": f"Same {key.upper()} as row {seen[value]}."}
                )
            elif value:
                seen[value] = index
        if result.errors:
            result.action = "error"
            results.append(result)
            continue
        match = (by_sku.get(sku.lower()) if sku else None) or (by_barcode.get(barcode) if barcode else None)
        if match is not None:
            result.product = match
            if update_existing:
                result.action = "update"
            else:
                result.action = "skip"
                result.message = "Already exists (matched by SKU or barcode)."
        results.append(result)
    return results


def _category_id(db: Session, ctx: BusinessContext, name: str | None, cache: dict[str, uuid.UUID]) -> uuid.UUID | None:
    if not name:
        return None
    key = name.strip().lower()
    if key not in cache:
        cat = db.scalar(
            select(Category).where(Category.business_id == ctx.business_id, func.lower(Category.name) == key)
        )
        if cat is None:
            cat = Category(business_id=ctx.business_id, name=name.strip())
            db.add(cat)
            db.flush()
        cache[key] = cat.id
    return cache[key]


def apply_import(db: Session, ctx: BusinessContext, results: list[RowResult]) -> tuple[int, int]:
    can_cost = ctx.can(Permission.PRODUCTS_VIEW_COST)
    can_devices = ctx.can(Permission.DEVICE_IDS_VIEW)
    can_adjust = ctx.can(Permission.INVENTORY_ADJUST)
    categories: dict[str, uuid.UUID] = {}
    created = updated = 0
    for r in results:
        d = r.data
        attrs = {k: v for k, v in d.get("attributes", {}).items() if can_devices or k not in SENSITIVE_ATTRIBUTES}
        if r.action == "create":
            cost = d.get("cost_price", Decimal("0")) if can_cost else Decimal("0")
            p = Product(
                business_id=ctx.business_id,
                name=d["name"],
                description=d.get("description"),
                sku=d.get("sku"),
                barcode=d.get("barcode"),
                unit=d.get("unit", "pcs"),
                category_id=_category_id(db, ctx, d.get("category"), categories),
                cost_price=cost,
                selling_price=d["selling_price"],
                reorder_level=d.get("reorder_level", Decimal("0")),
                attributes=attrs,
                quantity_on_hand=Decimal("0"),
            )
            db.add(p)
            db.flush()
            opening = d.get("quantity", Decimal("0"))
            if opening > 0:
                apply_stock_change(
                    db, p, opening, "opening", actor_id=ctx.user.id, enforce=False, unit_cost=cost, note="Import"
                )
            created += 1
        elif r.action == "update":
            p = r.product
            p.name = d["name"]
            p.selling_price = d["selling_price"]
            if can_cost and "cost_price" in d:
                p.cost_price = d["cost_price"]
            for column in ("description", "unit", "reorder_level", "barcode"):
                if column in d:
                    setattr(p, column, d[column])
            if d.get("category"):
                p.category_id = _category_id(db, ctx, d["category"], categories)
            kept = {k: v for k, v in (p.attributes or {}).items() if not can_devices and k in SENSITIVE_ATTRIBUTES}
            p.attributes = {**(p.attributes or {}), **attrs, **kept}
            target = d.get("quantity")
            if target is not None and can_adjust and p.track_stock and target != p.quantity_on_hand:
                apply_stock_change(
                    db, p, target - p.quantity_on_hand, "count", actor_id=ctx.user.id, enforce=False, note="Import"
                )
            p.version += 1
            updated += 1
    return created, updated


# --- API ---------------------------------------------------------------------------------------


class ImportRow(BaseModel):
    row: int
    action: str
    name: str | None
    sku: str | None
    selling_price: str | None
    quantity: str | None
    message: str | None = None


class ImportReport(BaseModel):
    dry_run: bool
    total_rows: int
    to_create: int
    to_update: int
    skipped: int
    invalid: int
    errors: list[dict[str, str]]
    preview: list[ImportRow]
    created: int = 0
    updated: int = 0
    plan_limit_exceeded: bool = False


@router.post("/import", response_model=ImportReport)
async def import_products(
    db: DB,
    file: Annotated[UploadFile, File(description="CSV or .xlsx file")],
    ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE),
    dry_run: Annotated[bool, Query()] = True,
    update_existing: Annotated[bool, Query()] = False,
    skip_invalid: Annotated[bool, Query()] = False,
) -> ImportReport:
    content = await file.read(MAX_FILE_BYTES + 1)
    if len(content) > MAX_FILE_BYTES:
        raise AppError("The file is larger than 2 MB. Split it into smaller files.", code="file_too_large")
    results = plan_import(db, ctx, read_table(file.filename or "", content), update_existing)

    counts = {a: sum(1 for r in results if r.action == a) for a in ("create", "update", "skip", "error")}
    errors = [e for r in results for e in r.errors]
    plan = subscriptions.effective_plan(db, ctx.business_id)
    active = db.scalar(
        select(func.count()).select_from(Product).where(Product.business_id == ctx.business_id, Product.is_active)
    )
    over_limit = plan.max_products is not None and active + counts["create"] > plan.max_products
    report = ImportReport(
        dry_run=dry_run,
        total_rows=len(results),
        to_create=counts["create"],
        to_update=counts["update"],
        skipped=counts["skip"],
        invalid=counts["error"],
        errors=errors[:500],
        plan_limit_exceeded=over_limit,
        preview=[
            ImportRow(
                row=r.row,
                action=r.action,
                name=r.data.get("name") or None,
                sku=r.data.get("sku"),
                selling_price=str(r.data["selling_price"]) if "selling_price" in r.data else None,
                quantity=format_qty(r.data["quantity"]) if "quantity" in r.data else None,
                message=r.message or (r.errors[0]["message"] if r.errors else None),
            )
            for r in results[:PREVIEW_ROWS]
        ],
    )
    if dry_run:
        return report

    if counts["error"] and not skip_invalid:
        raise Unprocessable(
            f"{counts['error']} rows have errors. Fix them, or choose to import only the valid rows.",
            code="import_has_errors",
            details={"errors": errors[:100]},
        )
    if over_limit:
        raise PaymentRequired(
            f"The {plan.name} plan allows up to {plan.max_products} active products; "
            f"this import would bring you to {active + counts['create']}.",
            details={"limit": plan.max_products, "plan": plan.code},
        )
    created, updated = apply_import(db, ctx, results)
    audit.record(
        db,
        action="product.imported",
        entity_type="product",
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{file.filename}: {created} created, {updated} updated",
    )
    db.commit()
    report.created, report.updated = created, updated
    return report


@router.get("/export.csv")
def export_products(db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_VIEW)) -> StreamingResponse:
    """All active products in the same column layout the importer accepts (round-trip safe)."""
    categories = dict(
        db.execute(select(Category.id, Category.name).where(Category.business_id == ctx.business_id)).all()
    )
    products = db.scalars(
        select(Product)
        .where(Product.business_id == ctx.business_id, Product.is_active)
        .order_by(func.lower(Product.name))
    )
    columns = [
        c
        for c in EXPORT_COLUMNS
        if (c != "cost_price" or ctx.can(Permission.PRODUCTS_VIEW_COST))
        and (c != "imei" or ctx.can(Permission.DEVICE_IDS_VIEW))
    ]
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(columns)

    def safe(value: Any) -> str:
        text = "" if value is None else str(value)
        # Neutralise spreadsheet formulas (CSV injection).
        return f"'{text}" if text[:1] in ("=", "+", "-", "@") else text

    for p in products:
        attrs = p.attributes or {}
        row = {
            "name": p.name,
            "sku": p.sku,
            "barcode": p.barcode,
            "category": categories.get(p.category_id),
            "selling_price": money(p.selling_price),
            "cost_price": money(p.cost_price),
            "quantity": format_qty(p.quantity_on_hand) if p.track_stock else "",
            "reorder_level": format_qty(p.reorder_level),
            "unit": p.unit,
            "description": p.description,
            **{k: attrs.get(k) for k in ATTRIBUTE_FIELDS},
        }
        writer.writerow([safe(row[c]) for c in columns])
    return StreamingResponse(
        iter([buf.getvalue().encode("utf-8-sig")]),  # BOM so Excel opens UTF-8 correctly
        media_type="text/csv",
        headers={"Content-Disposition": 'attachment; filename="products.csv"'},
    )
