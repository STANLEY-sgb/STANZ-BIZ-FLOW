"""Fixed-window rate limiter for authentication-sensitive endpoints.

The in-memory store is correct for a single API process. When the API runs
with multiple replicas, swap `MemoryRateLimitStore` for a Redis-backed store
implementing the same `hit` method so limits are shared.
"""

import threading
import time
from collections.abc import Callable

from fastapi import Request

from app.core.config import get_settings
from app.core.errors import TooManyRequests


class MemoryRateLimitStore:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._hits: dict[str, tuple[float, int]] = {}

    def hit(self, key: str, window_seconds: int) -> int:
        now = time.monotonic()
        with self._lock:
            start, count = self._hits.get(key, (now, 0))
            if now - start >= window_seconds:
                start, count = now, 0
            count += 1
            self._hits[key] = (start, count)
            return count

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


store = MemoryRateLimitStore()


def client_ip(request: Request) -> str:
    # Behind a trusted proxy, configure uvicorn --proxy-headers so this is the real client.
    return request.client.host if request.client else "unknown"


def rate_limit(scope: str) -> Callable[[Request], None]:
    def dependency(request: Request) -> None:
        settings = get_settings()
        key = f"{scope}:{client_ip(request)}"
        if store.hit(key, settings.auth_rate_limit_window_seconds) > settings.auth_rate_limit_attempts:
            raise TooManyRequests("Too many attempts. Please wait a few minutes and try again.")

    return dependency
