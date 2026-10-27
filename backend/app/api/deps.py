"""Request dependencies: authentication and tenant (business) context.

Every business-scoped route resolves `BusinessContext` from the path. The
business id from the client is never trusted on its own: the authenticated
user must hold an active membership, and permissions come from that
membership's role on the server.
"""

import uuid
from dataclasses import dataclass
from typing import Annotated

import jwt
from fastapi import Depends, Path
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db, utcnow
from app.core.errors import Forbidden, NotFound, Unauthorized
from app.core.permissions import Permission, Role, permissions_for
from app.core.security import decode_access_token
from app.models import AuthSession, Business, Membership, User

DB = Annotated[Session, Depends(get_db)]

_bearer = HTTPBearer(auto_error=False)


@dataclass
class AuthContext:
    user: User
    session_id: uuid.UUID


def get_auth(db: DB, credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)]) -> AuthContext:
    if credentials is None:
        raise Unauthorized("Authentication required.")
    try:
        payload = decode_access_token(credentials.credentials)
        user_id = uuid.UUID(payload["sub"])
        session_id = uuid.UUID(payload["sid"])
    except (jwt.PyJWTError, ValueError, KeyError) as exc:
        raise Unauthorized("Your session has expired. Please sign in again.", code="token_invalid") from exc

    session = db.get(AuthSession, session_id)
    if (
        session is None
        or session.user_id != user_id
        or session.revoked_at is not None
        or session.expires_at <= utcnow()
    ):
        raise Unauthorized("Your session has ended. Please sign in again.", code="session_revoked")
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise Unauthorized("This account is not active.", code="account_inactive")
    return AuthContext(user=user, session_id=session_id)


Auth = Annotated[AuthContext, Depends(get_auth)]


@dataclass
class BusinessContext:
    business: Business
    membership: Membership
    user: User
    permissions: frozenset[Permission]

    @property
    def business_id(self) -> uuid.UUID:
        return self.business.id

    @property
    def role(self) -> Role:
        return Role(self.membership.role)

    def can(self, permission: Permission) -> bool:
        return permission in self.permissions

    def require(self, permission: Permission) -> None:
        if permission not in self.permissions:
            raise Forbidden("You do not have permission to perform this action.", details={"permission": permission})


def get_business_context(db: DB, auth: Auth, business_id: Annotated[uuid.UUID, Path()]) -> BusinessContext:
    membership = db.scalar(
        select(Membership).where(
            Membership.business_id == business_id,
            Membership.user_id == auth.user.id,
            Membership.status == "active",
        )
    )
    # Same response for "does not exist" and "not a member" so ids cannot be probed.
    if membership is None:
        raise NotFound("Business not found.")
    business = db.get(Business, business_id)
    if business is None:
        raise NotFound("Business not found.")
    return BusinessContext(
        business=business, membership=membership, user=auth.user, permissions=permissions_for(membership.role)
    )


Ctx = Annotated[BusinessContext, Depends(get_business_context)]


def require(permission: Permission):  # noqa: ANN201
    """Route dependency enforcing a permission and returning the business context."""

    def dependency(ctx: Ctx) -> BusinessContext:
        ctx.require(permission)
        return ctx

    return Depends(dependency)
