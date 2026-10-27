"""Password hashing, access tokens and opaque one-time tokens."""

import hashlib
import secrets
import uuid
from datetime import timedelta

import jwt
from pwdlib import PasswordHash

from app.core.config import get_settings
from app.core.database import utcnow

_password_hash = PasswordHash.recommended()  # Argon2id

# Used to equalise timing when a login targets a non-existent account.
_DUMMY_HASH = _password_hash.hash("timing-equaliser-not-a-real-password")


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    if password_hash is None:
        _password_hash.verify(password, _DUMMY_HASH)
        return False
    return _password_hash.verify(password, password_hash)


def create_access_token(user_id: uuid.UUID, session_id: uuid.UUID) -> tuple[str, int]:
    settings = get_settings()
    expires_in = settings.access_token_minutes * 60
    now = utcnow()
    payload = {
        "sub": str(user_id),
        "sid": str(session_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=expires_in)).timestamp()),
        "typ": "access",
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm), expires_in


def decode_access_token(token: str) -> dict:
    settings = get_settings()
    payload = jwt.decode(
        token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        options={"require": ["exp", "sub", "sid"]},
    )
    if payload.get("typ") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return payload


def new_opaque_token() -> str:
    """A high-entropy token for refresh, reset and invitation flows."""
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    """Only SHA-256 digests of opaque tokens are stored, never the tokens themselves."""
    return hashlib.sha256(token.encode()).hexdigest()
