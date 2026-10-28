"""STANZ BizFlow API — a product of STANZ DIGITAL CONNECT."""

import logging
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.core.log_config import configure_logging
from app.modules import (
    audit,
    auth,
    businesses,
    customers,
    expenses,
    files,
    health,
    product_import,
    products,
    reports,
    sales,
    subscriptions,
    sync,
)

request_logger = logging.getLogger("bizflow.request")


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging()
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_production else "/openapi.json",
    )
    register_error_handlers(app)

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
        )

    @app.middleware("http")
    async def request_context(request: Request, call_next):  # noqa: ANN001, ANN202
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        start = time.perf_counter()
        response = await call_next(request)
        duration_ms = round((time.perf_counter() - start) * 1000, 1)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers.setdefault("Cache-Control", "no-store")
        # Path only (never query strings, which may contain tokens).
        request_logger.info(
            "request",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": duration_ms,
            },
        )
        return response

    app.include_router(health.router)
    # product_import before products so /products/export.csv is not captured by /products/{product_id}.
    for module in (
        auth,
        businesses,
        subscriptions,
        product_import,
        products,
        files,
        sales,
        customers,
        expenses,
        reports,
        sync,
        audit,
    ):
        app.include_router(module.router, prefix=settings.api_prefix)
    return app


app = create_app()
