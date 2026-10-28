"""File storage boundary and signed download links.

Only a local-disk backend is implemented. A cloud backend (S3, R2, Supabase Storage)
needs nothing more than the three methods of `Storage`; select it with STORAGE_BACKEND
once the provider and its credentials are chosen.

Files are never served by guessable path. Clients receive signed URLs that bind the file id
to an expiry time with an HMAC, so a link stops working after `file_url_ttl_seconds`.
"""

import hashlib
import hmac
import time
import uuid
from pathlib import Path
from typing import Protocol

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


_storage: Storage | None = None


def get_storage() -> Storage:
    global _storage
    if _storage is None:
        settings = get_settings()
        if settings.storage_backend != "local":
            raise RuntimeError(f"Storage backend '{settings.storage_backend}' is not configured in this build")
        _storage = LocalStorage(settings.local_storage_dir)
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
