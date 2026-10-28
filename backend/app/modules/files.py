"""Image uploads (product photos, business logo) and signed file downloads.

Every upload is decoded and re-encoded by Pillow:
* only real JPEG / PNG / WebP images are accepted (detected from content, not the filename);
* decompression bombs are refused (pixel cap);
* camera orientation is applied, then all metadata (EXIF, GPS location) is dropped;
* images are downscaled and stored as WebP.
Re-encoding also means no uploaded byte is ever served back verbatim.
"""

import hashlib
import io
import uuid
from typing import Annotated

from fastapi import APIRouter, File, Query, Response, UploadFile, status
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import DB, BusinessContext, require
from app.core.database import utcnow
from app.core.errors import AppError, Forbidden, NotFound
from app.core.permissions import Permission
from app.core.storage import get_storage, signed_url, verify_signature
from app.models import StoredFile
from app.modules import audit
from app.modules.products import ProductOut, get_product, product_out

router = APIRouter(tags=["files"])

MAX_UPLOAD_BYTES = 5 * 1024 * 1024
MAX_PIXELS = 40_000_000  # ~40 MP: any real phone photo, but not a decompression bomb
ACCEPTED_FORMATS = {"JPEG", "PNG", "WEBP"}
MAX_EDGE = {"product_image": 1024, "business_logo": 512}


def process_image(data: bytes, kind: str) -> tuple[bytes, int, int]:
    """Validate and normalise an uploaded image. Returns (webp_bytes, width, height)."""
    if len(data) > MAX_UPLOAD_BYTES:
        raise AppError("Images must be 5 MB or smaller.", code="file_too_large")
    try:
        with Image.open(io.BytesIO(data)) as probe:
            if probe.format not in ACCEPTED_FORMATS:
                raise AppError("Upload a JPEG, PNG or WebP image.", code="unsupported_file_type")
            if probe.width * probe.height > MAX_PIXELS:
                raise AppError("This image is too large in resolution.", code="image_too_large")
            probe.verify()  # structural check; the image must be reopened afterwards
        with Image.open(io.BytesIO(data)) as img:
            img = ImageOps.exif_transpose(img)  # apply rotation before metadata is discarded
            img = img.convert("RGBA" if img.mode in ("RGBA", "LA", "P") else "RGB")
            img.thumbnail((MAX_EDGE[kind], MAX_EDGE[kind]))
            out = io.BytesIO()
            img.save(out, format="WEBP", quality=82, method=4)  # no exif/icc passed => metadata stripped
            return out.getvalue(), img.width, img.height
    except AppError:
        raise
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise AppError("This file is not a valid image.", code="invalid_image") from exc


def store_image(db: Session, ctx: BusinessContext, kind: str, data: bytes) -> StoredFile:
    processed, width, height = process_image(data, kind)
    file_id = uuid.uuid4()
    key = f"{ctx.business_id}/{kind}/{file_id}.webp"
    get_storage().put(key, processed)
    record = StoredFile(
        id=file_id,
        business_id=ctx.business_id,
        kind=kind,
        content_type="image/webp",
        size_bytes=len(processed),
        width=width,
        height=height,
        sha256=hashlib.sha256(processed).hexdigest(),
        storage_key=key,
        created_by=ctx.user.id,
        created_at=utcnow(),
    )
    db.add(record)
    db.flush()
    return record


def remove_file(db: Session, business_id: uuid.UUID, file_id: uuid.UUID | None) -> None:
    if file_id is None:
        return
    record = db.scalar(select(StoredFile).where(StoredFile.id == file_id, StoredFile.business_id == business_id))
    if record is not None:
        get_storage().delete(record.storage_key)
        db.delete(record)


async def _read(upload: UploadFile) -> bytes:
    data = await upload.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise AppError("Images must be 5 MB or smaller.", code="file_too_large")
    return data


ImageUpload = Annotated[UploadFile, File(description="JPEG, PNG or WebP, up to 5 MB")]


@router.post("/businesses/{business_id}/products/{product_id}/image", response_model=ProductOut)
async def upload_product_image(
    product_id: uuid.UUID, file: ImageUpload, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> ProductOut:
    product = get_product(db, ctx.business_id, product_id)
    record = store_image(db, ctx, "product_image", await _read(file))
    old = product.image_file_id
    product.image_file_id = record.id
    product.version += 1
    db.flush()
    remove_file(db, ctx.business_id, old)
    audit.record(
        db,
        action="product.image_set",
        entity_type="product",
        entity_id=product.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
    )
    db.commit()
    return product_out(product, ctx)


@router.delete("/businesses/{business_id}/products/{product_id}/image", response_model=ProductOut)
def delete_product_image(
    product_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.PRODUCTS_MANAGE)
) -> ProductOut:
    product = get_product(db, ctx.business_id, product_id)
    old, product.image_file_id = product.image_file_id, None
    product.version += 1
    db.flush()
    remove_file(db, ctx.business_id, old)
    db.commit()
    return product_out(product, ctx)


@router.post("/businesses/{business_id}/logo", status_code=status.HTTP_200_OK)
async def upload_logo(file: ImageUpload, db: DB, ctx: BusinessContext = require(Permission.BUSINESS_MANAGE)) -> dict:
    record = store_image(db, ctx, "business_logo", await _read(file))
    old = ctx.business.logo_file_id
    ctx.business.logo_file_id = record.id
    db.flush()
    remove_file(db, ctx.business_id, old)
    audit.record(
        db,
        action="business.logo_set",
        entity_type="business",
        entity_id=ctx.business_id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
    )
    db.commit()
    return {"logo_url": signed_url(record.id)}


@router.delete("/businesses/{business_id}/logo", status_code=status.HTTP_204_NO_CONTENT)
def delete_logo(db: DB, ctx: BusinessContext = require(Permission.BUSINESS_MANAGE)) -> None:
    old, ctx.business.logo_file_id = ctx.business.logo_file_id, None
    db.flush()
    remove_file(db, ctx.business_id, old)
    db.commit()


@router.get("/files/{file_id}")
def download_file(
    file_id: uuid.UUID,
    db: DB,
    exp: Annotated[int, Query()],
    sig: Annotated[str, Query(max_length=64)],
) -> Response:
    """Serve a file via a signed, expiring link (no bearer token needed, so <img> tags work)."""
    if not verify_signature(file_id, exp, sig):
        raise Forbidden("This link has expired or is invalid.", code="invalid_file_link")
    record = db.get(StoredFile, file_id)
    data = get_storage().get(record.storage_key) if record else None
    if data is None:
        raise NotFound("File not found.")
    return Response(
        content=data,
        media_type=record.content_type,
        headers={"Cache-Control": "private, max-age=3600", "X-Content-Type-Options": "nosniff"},
    )
