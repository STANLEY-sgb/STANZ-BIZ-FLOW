"""Registration, login, token refresh/rotation, logout and password recovery."""

import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Request, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.api.deps import DB, Auth
from app.core.config import get_settings
from app.core.database import utcnow
from app.core.errors import AppError, Conflict, Unauthorized
from app.core.mailer import send_email
from app.core.rate_limit import rate_limit
from app.core.security import (
    create_access_token,
    hash_password,
    hash_token,
    new_opaque_token,
    verify_password,
)
from app.models import AuthSession, Business, Membership, OneTimeToken, User
from app.modules import audit

router = APIRouter(prefix="/auth", tags=["auth"])


# --- Schemas ---------------------------------------------------------------------------------


def _validate_password(value: str) -> str:
    if len(value) < 8:
        raise ValueError("Password must be at least 8 characters.")
    if value.isdigit() or value.isalpha():
        raise ValueError("Password must contain both letters and numbers or symbols.")
    return value


class RegisterIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=160)
    email: EmailStr
    password: str = Field(max_length=128)
    phone: str | None = Field(default=None, max_length=32)

    _pw = field_validator("password")(_validate_password)


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(max_length=128)
    device_name: str | None = Field(default=None, max_length=120)


class RefreshIn(BaseModel):
    refresh_token: str = Field(max_length=200)


class PasswordResetRequestIn(BaseModel):
    email: EmailStr


class PasswordResetConfirmIn(BaseModel):
    token: str = Field(max_length=200)
    new_password: str = Field(max_length=128)

    _pw = field_validator("new_password")(_validate_password)


class ChangePasswordIn(BaseModel):
    current_password: str = Field(max_length=128)
    new_password: str = Field(max_length=128)

    _pw = field_validator("new_password")(_validate_password)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    full_name: str
    phone: str | None
    email_verified: bool = False


class MembershipSummary(BaseModel):
    business_id: uuid.UUID
    business_name: str
    role: str
    onboarding_completed: bool


class MeOut(BaseModel):
    user: UserOut
    businesses: list[MembershipSummary]


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserOut


class MessageOut(BaseModel):
    message: str


# --- Helpers ---------------------------------------------------------------------------------


def _user_out(user: User) -> UserOut:
    out = UserOut.model_validate(user)
    out.email_verified = user.email_verified_at is not None
    return out


def _issue_session(db: Session, user: User, user_agent: str | None) -> TokenOut:
    now = utcnow()
    refresh = new_opaque_token()
    session = AuthSession(
        user_id=user.id,
        refresh_token_hash=hash_token(refresh),
        user_agent=(user_agent or "")[:255] or None,
        created_at=now,
        last_used_at=now,
        expires_at=now + timedelta(days=get_settings().refresh_token_days),
    )
    db.add(session)
    db.flush()
    access, expires_in = create_access_token(user.id, session.id)
    return TokenOut(access_token=access, refresh_token=refresh, expires_in=expires_in, user=_user_out(user))


def _revoke_all_sessions(db: Session, user_id: uuid.UUID, now: datetime) -> None:
    db.execute(
        update(AuthSession)
        .where(AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=now)
    )


# --- Endpoints -------------------------------------------------------------------------------


@router.post(
    "/register",
    response_model=TokenOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("register"))],
)
def register(body: RegisterIn, request: Request, db: DB) -> TokenOut:
    email = body.email.lower()
    if db.scalar(select(User.id).where(User.email == email)):
        raise Conflict("An account with this email already exists.", code="email_taken")
    user = User(
        email=email,
        password_hash=hash_password(body.password),
        full_name=body.full_name.strip(),
        phone=body.phone,
    )
    db.add(user)
    db.flush()
    audit.record(db, action="user.registered", entity_type="user", entity_id=user.id, actor_id=user.id)
    tokens = _issue_session(db, user, request.headers.get("user-agent"))
    db.commit()
    return tokens


@router.post("/login", response_model=TokenOut, dependencies=[Depends(rate_limit("login"))])
def login(body: LoginIn, request: Request, db: DB) -> TokenOut:
    user = db.scalar(select(User).where(User.email == body.email.lower()))
    if not verify_password(body.password, user.password_hash if user else None) or not user.is_active:
        raise Unauthorized("Incorrect email or password.", code="invalid_credentials")
    tokens = _issue_session(db, user, body.device_name or request.headers.get("user-agent"))
    db.commit()
    return tokens


@router.post("/refresh", response_model=TokenOut, dependencies=[Depends(rate_limit("refresh"))])
def refresh(body: RefreshIn, db: DB) -> TokenOut:
    now = utcnow()
    digest = hash_token(body.refresh_token)
    session = db.scalar(select(AuthSession).where(AuthSession.refresh_token_hash == digest).with_for_update())
    if session is None:
        # A rotated-out token being replayed suggests theft: end that session entirely.
        reused = db.scalar(select(AuthSession).where(AuthSession.previous_token_hash == digest))
        if reused is not None and reused.revoked_at is None:
            reused.revoked_at = now
            audit.record(
                db,
                action="auth.refresh_reuse_detected",
                entity_type="session",
                entity_id=reused.id,
                actor_id=reused.user_id,
            )
            db.commit()
        raise Unauthorized("Your session has ended. Please sign in again.", code="session_revoked")
    if session.revoked_at is not None or session.expires_at <= now:
        raise Unauthorized("Your session has ended. Please sign in again.", code="session_revoked")
    user = db.get(User, session.user_id)
    if user is None or not user.is_active:
        raise Unauthorized("This account is not active.", code="account_inactive")

    new_refresh = new_opaque_token()
    session.previous_token_hash = session.refresh_token_hash
    session.refresh_token_hash = hash_token(new_refresh)
    session.last_used_at = now
    access, expires_in = create_access_token(user.id, session.id)
    db.commit()
    return TokenOut(access_token=access, refresh_token=new_refresh, expires_in=expires_in, user=_user_out(user))


@router.post("/logout", response_model=MessageOut)
def logout(db: DB, auth: Auth) -> MessageOut:
    session = db.get(AuthSession, auth.session_id)
    if session and session.revoked_at is None:
        session.revoked_at = utcnow()
        db.commit()
    return MessageOut(message="Signed out.")


@router.post("/logout-all", response_model=MessageOut)
def logout_all(db: DB, auth: Auth) -> MessageOut:
    _revoke_all_sessions(db, auth.user.id, utcnow())
    audit.record(db, action="auth.logout_all", entity_type="user", entity_id=auth.user.id, actor_id=auth.user.id)
    db.commit()
    return MessageOut(message="Signed out of all devices.")


@router.get("/me", response_model=MeOut)
def me(db: DB, auth: Auth) -> MeOut:
    rows = db.execute(
        select(Membership, Business)
        .join(Business, Business.id == Membership.business_id)
        .where(Membership.user_id == auth.user.id, Membership.status == "active")
        .order_by(Business.name)
    ).all()
    return MeOut(
        user=_user_out(auth.user),
        businesses=[
            MembershipSummary(
                business_id=b.id,
                business_name=b.name,
                role=m.role,
                onboarding_completed=b.onboarding_completed_at is not None,
            )
            for m, b in rows
        ],
    )


@router.post("/change-password", response_model=MessageOut)
def change_password(body: ChangePasswordIn, db: DB, auth: Auth) -> MessageOut:
    user = auth.user
    if not verify_password(body.current_password, user.password_hash):
        raise AppError("Your current password is incorrect.", code="invalid_credentials")
    user.password_hash = hash_password(body.new_password)
    now = utcnow()
    # Keep this device signed in; end every other session.
    db.execute(
        update(AuthSession)
        .where(AuthSession.user_id == user.id, AuthSession.id != auth.session_id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=now)
    )
    audit.record(db, action="auth.password_changed", entity_type="user", entity_id=user.id, actor_id=user.id)
    db.commit()
    return MessageOut(message="Password updated.")


_RESET_MESSAGE = "If an account exists for that email, password reset instructions have been sent."


@router.post("/password-reset/request", response_model=MessageOut, dependencies=[Depends(rate_limit("password_reset"))])
def request_password_reset(body: PasswordResetRequestIn, db: DB) -> MessageOut:
    settings = get_settings()
    user = db.scalar(select(User).where(User.email == body.email.lower()))
    if user is not None and user.is_active:
        token = new_opaque_token()
        now = utcnow()
        db.add(
            OneTimeToken(
                user_id=user.id,
                purpose="password_reset",
                token_hash=hash_token(token),
                created_at=now,
                expires_at=now + timedelta(minutes=settings.password_reset_minutes),
            )
        )
        db.commit()
        send_email(
            user.email,
            "Reset your STANZ BizFlow password",
            f"Use this link within {settings.password_reset_minutes} minutes to choose a new password:\n"
            f"{settings.public_app_url}/reset-password?token={token}\n\n"
            "If you did not request this, you can ignore this email.",
        )
    # Identical response either way, so the endpoint cannot be used to discover accounts.
    return MessageOut(message=_RESET_MESSAGE)


@router.post("/password-reset/confirm", response_model=MessageOut, dependencies=[Depends(rate_limit("password_reset"))])
def confirm_password_reset(body: PasswordResetConfirmIn, db: DB) -> MessageOut:
    now = utcnow()
    record = db.scalar(
        select(OneTimeToken)
        .where(OneTimeToken.token_hash == hash_token(body.token), OneTimeToken.purpose == "password_reset")
        .with_for_update()
    )
    if record is None or record.used_at is not None or record.expires_at <= now:
        raise AppError("This reset link is invalid or has expired.", code="token_invalid")
    user = db.get(User, record.user_id)
    record.used_at = now
    user.password_hash = hash_password(body.new_password)
    _revoke_all_sessions(db, user.id, now)
    audit.record(db, action="auth.password_reset", entity_type="user", entity_id=user.id, actor_id=user.id)
    db.commit()
    return MessageOut(message="Your password has been reset. Please sign in.")
