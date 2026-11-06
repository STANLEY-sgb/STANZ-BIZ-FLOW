"""File storage boundary and signed download links.

Backends: local disk (development) and Supabase Storage (STORAGE_BACKEND=supabase, for serverless hosts
such as Vercel where the disk is read-only/ephemeral). Another provider needs only the three methods of `Storage`.

Files are never served by guessable path. Clients receive signed URLs that bind the file id
to an expiry time with an HMAC, so a link stops working after `file_url_ttl_seconds`.
"""

import hashlib
import hmac
import time
import uuid
from pathlib import Path
from typing import Protocol

import httpx

from app.core.config import get_settings


class Storage(Protocol):
    def put(self, key: str, data: bytes) -> None: ...
    def get(self, key: str) -> bytes | None: ...
    def delete(self, key: str) -> None: ...


class LocalStorage:
    def __init__(self, base_dir: str) -> None:
        self.base = Path(base_dir).resolve()

    def _path(self, key: str) -> Path:
        path = (self.base / key).resolve()
        if not path.is_relative_to(self.base):  # defence in depth: keys are server-generated anyway
            raise ValueError("invalid storage key")
        return path

    def put(self, key: str, data: bytes) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_bytes(data)
        tmp.replace(path)  # atomic on the same filesystem

    def get(self, key: str) -> bytes | None:
        path = self._path(key)
        return path.read_bytes() if path.exists() else None

    def delete(self, key: str) -> None:
        self._path(key).unlink(missing_ok=True)


class SupabaseStorage:
    """Private Supabase Storage bucket over its REST API; files are served only via signed API URLs."""

    def __init__(self, url: str, service_key: str, bucket: str) -> None:
        self.base = f"{url.rstrip('/')}/storage/v1/object"
        self.bucket = bucket
        self.headers = {"Authorization": f"Bearer {service_key}", "apikey": service_key}

    def _url(self, key: str) -> str:
        return f"{self.base}/{self.bucket}/{key}"

    def put(self, key: str, data: bytes) -> None:
        res = httpx.post(
            self._url(key),
            content=data,
            timeout=20,
            headers=self.headers | {"x-upsert": "true", "content-type": "application/octet-stream"},
        )
        res.raise_for_status()

    def get(self, key: str) -> bytes | None:
        res = httpx.get(self._url(key), headers=self.headers, timeout=20)
        if res.status_code in (400, 404):
            return None
        res.raise_for_status()
        return res.content

    def delete(self, key: str) -> None:
        res = httpx.delete(self._url(key), headers=self.headers, timeout=20)
        if res.status_code not in (200, 204, 400, 404):
            res.raise_for_status()


_storage: Storage | None = None


def get_storage() -> Storage:
    global _storage
    if _storage is None:
        settings = get_settings()
        if settings.storage_backend == "supabase":
            if not (settings.supabase_url and settings.supabase_service_key):
                raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY are required for STORAGE_BACKEND=supabase")
            _storage = SupabaseStorage(settings.supabase_url, settings.supabase_service_key, settings.supabase_bucket)
        elif settings.storage_backend == "local":
            _storage = LocalStorage(settings.local_storage_dir)
        else:
            raise RuntimeError(f"Unknown storage backend '{settings.storage_backend}'")
    return _storage


def set_storage(storage: Storage | None) -> None:
    """Test hook."""
    global _storage
    _storage = storage


def _signature(file_id: uuid.UUID, expires: int) -> str:
    key = get_settings().jwt_secret.encode()
    return hmac.new(key, f"file:{file_id}:{expires}".encode(), hashlib.sha256).hexdigest()[:40]


def signed_url(file_id: uuid.UUID | None) -> str | None:
    if file_id is None:
        return None
    settings = get_settings()
    expires = int(time.time()) + settings.file_url_ttl_seconds
    # Round the expiry so the URL stays stable for a while and image caches stay warm.
    expires -= expires % 300
    expires += 300
    return f"{settings.api_prefix}/files/{file_id}?exp={expires}&sig={_signature(file_id, expires)}"


def verify_signature(file_id: uuid.UUID, expires: int, signature: str) -> bool:
    if expires < int(time.time()):
        return False
    return hmac.compare_digest(_signature(file_id, expires), signature)
