"""Business workspaces, onboarding progress, team membership and invitations."""

import uuid
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import DB, Auth, BusinessContext, Ctx, require
from app.core.config import get_settings
from app.core.database import utcnow
from app.core.errors import AppError, Conflict, Forbidden, NotFound
from app.core.mailer import send_email
from app.core.permissions import Permission, Role, permissions_for
from app.core.plans import Feature
from app.core.security import hash_token, new_opaque_token
from app.core.storage import signed_url
from app.models import Business, Category, Invitation, Membership, User
from app.modules import audit, subscriptions

router = APIRouter(tags=["businesses"])

BUSINESS_CATEGORIES = (
    "retail",
    "supermarket",
    "electronics",
    "fashion",
    "wholesale",
    "beauty",
    "restaurant",
    "services",
    "other",
)
PAYMENT_METHODS = ("cash", "mobile_money", "bank_transfer", "card", "other")
ONBOARDING_STEPS = ("first_product", "payment_methods", "invite_team", "done")

# Sensible starting categories so a new workspace is useful immediately; owners can rename or add more.
DEFAULT_CATEGORIES: dict[str, tuple[str, ...]] = {
    "electronics": ("Phones", "Accessories", "Laptops", "Repairs"),
    "supermarket": ("Groceries", "Beverages", "Household", "Personal care"),
    "fashion": ("Men", "Women", "Children", "Shoes", "Accessories"),
    "beauty": ("Services", "Hair products", "Skin care"),
    "restaurant": ("Food", "Drinks"),
}


# --- Schemas ---------------------------------------------------------------------------------


class BusinessSettings(BaseModel):
    phone: str | None = Field(default=None, max_length=32)
    email: EmailStr | None = None
    address: str | None = Field(default=None, max_length=300)
    receipt_footer: str | None = Field(default=None, max_length=300)
    tax_rate_percent: Decimal | None = Field(default=None, ge=0, le=100, max_digits=5, decimal_places=2)
    enforce_stock: bool | None = None
    payment_methods: list[Literal["cash", "mobile_money", "bank_transfer", "card", "other"]] | None = Field(
        default=None, min_length=1
    )
    receipt_prefix: str | None = Field(default=None, min_length=1, max_length=8, pattern=r"^[A-Za-z0-9-]+$")


class BusinessCreate(BusinessSettings):
    name: str = Field(min_length=2, max_length=160)
    category: Literal[BUSINESS_CATEGORIES]  # type: ignore[valid-type]
    country_code: str = Field(default="UG", min_length=2, max_length=2)
    currency: str = Field(default="UGX", min_length=3, max_length=3)
    timezone: str = Field(default="Africa/Kampala", max_length=64)

    @field_validator("country_code", "currency")
    @classmethod
    def _upper(cls, v: str) -> str:
        if not v.isalpha():
            raise ValueError("Must be letters only.")
        return v.upper()

    @field_validator("timezone")
    @classmethod
    def _tz(cls, v: str) -> str:
        try:
            ZoneInfo(v)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError("Unknown time zone.") from exc
        return v


class BusinessUpdate(BusinessSettings):
    name: str | None = Field(default=None, min_length=2, max_length=160)
    timezone: str | None = Field(default=None, max_length=64)

    _tz = field_validator("timezone")(lambda v: v if v is None else BusinessCreate._tz(v))


class BusinessOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    category: str
    country_code: str
    currency: str
    timezone: str
    phone: str | None
    email: str | None
    address: str | None
    receipt_footer: str | None
    logo_url: str | None = None
    tax_rate_percent: Decimal
    enforce_stock: bool
    payment_methods: list[str]
    receipt_prefix: str
    onboarding_step: str
    onboarding_completed: bool
    created_at: datetime


class BusinessWithRole(BusinessOut):
    role: str
    permissions: list[str]


class OnboardingIn(BaseModel):
    step: Literal[ONBOARDING_STEPS]  # type: ignore[valid-type]


class MemberOut(BaseModel):
    membership_id: uuid.UUID
    user_id: uuid.UUID
    full_name: str
    email: str
    role: str
    status: str
    joined_at: datetime


class RoleUpdate(BaseModel):
    role: Role


class InvitationCreate(BaseModel):
    email: EmailStr
    role: Role


class InvitationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    role: str
    created_at: datetime
    expires_at: datetime
    accepted_at: datetime | None
    revoked_at: datetime | None


class InvitationCreated(InvitationOut):
    # Returned once so the inviter can share it (e.g. via WhatsApp) when email is unavailable.
    accept_token: str
    email_delivered: bool


class AcceptInvitationIn(BaseModel):
    token: str = Field(max_length=200)


# --- Helpers ---------------------------------------------------------------------------------


def business_out(b: Business) -> BusinessOut:
    data = {c: getattr(b, c) for c in BusinessOut.model_fields if hasattr(b, c) and c != "payment_methods"}
    return BusinessOut(
        **data,
        payment_methods=[m for m in b.payment_methods.split(",") if m],
        onboarding_completed=b.onboarding_completed_at is not None,
        logo_url=signed_url(b.logo_file_id),
    )


def _apply_settings(b: Business, body: BusinessSettings) -> None:
    for field, value in body.model_dump(exclude_unset=True).items():
        if field == "payment_methods":
            value = ",".join(dict.fromkeys(value))
        elif field == "email" and value is not None:
            value = str(value).lower()
        elif field == "receipt_prefix":
            value = value.upper()
        setattr(b, field, value)


def _active_owner_count(db: Session, business_id: uuid.UUID) -> int:
    return db.scalar(
        select(func.count())
        .select_from(Membership)
        .where(Membership.business_id == business_id, Membership.role == Role.OWNER, Membership.status == "active")
    )


def _get_membership(db: Session, ctx: BusinessContext, membership_id: uuid.UUID) -> Membership:
    m = db.scalar(select(Membership).where(Membership.id == membership_id, Membership.business_id == ctx.business_id))
    if m is None:
        raise NotFound("Team member not found.")
    return m


_PRIVILEGED = {Role.OWNER, Role.ADMIN}


def _guard_privileged_change(ctx: BusinessContext, *roles: Role) -> None:
    if any(r in _PRIVILEGED for r in roles) and ctx.role != Role.OWNER:
        raise Forbidden("Only a business owner can grant, change or remove owner and admin roles.")


# --- Business endpoints ----------------------------------------------------------------------


@router.post("/businesses", response_model=BusinessWithRole, status_code=status.HTTP_201_CREATED)
def create_business(body: BusinessCreate, db: DB, auth: Auth) -> BusinessWithRole:
    business = Business(
        name=body.name.strip(),
        category=body.category,
        country_code=body.country_code,
        currency=body.currency,
        timezone=body.timezone,
        created_by=auth.user.id,
    )
    _apply_settings(
        business, BusinessSettings(**body.model_dump(include=set(BusinessSettings.model_fields), exclude_unset=True))
    )
    db.add(business)
    db.flush()
    db.add(Membership(business_id=business.id, user_id=auth.user.id, role=Role.OWNER))
    subscriptions.create_default_subscription(db, business.id)
    for name in DEFAULT_CATEGORIES.get(body.category, ()):
        db.add(Category(business_id=business.id, name=name))
    audit.record(
        db,
        action="business.created",
        entity_type="business",
        entity_id=business.id,
        business_id=business.id,
        actor_id=auth.user.id,
        summary=business.name,
    )
    db.commit()
    return BusinessWithRole(
        **business_out(business).model_dump(), role=Role.OWNER, permissions=sorted(permissions_for(Role.OWNER))
    )


@router.get("/businesses/{business_id}", response_model=BusinessWithRole)
def get_business(ctx: Ctx) -> BusinessWithRole:
    return BusinessWithRole(
        **business_out(ctx.business).model_dump(), role=ctx.role, permissions=sorted(ctx.permissions)
    )


@router.patch("/businesses/{business_id}", response_model=BusinessWithRole)
def update_business(
    body: BusinessUpdate, db: DB, ctx: BusinessContext = require(Permission.BUSINESS_MANAGE)
) -> BusinessWithRole:
    _apply_settings(ctx.business, body)
    if body.name is not None:
        ctx.business.name = body.name.strip()
    if body.timezone is not None:
        ctx.business.timezone = body.timezone
    audit.record(
        db,
        action="business.updated",
        entity_type="business",
        entity_id=ctx.business_id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=", ".join(sorted(body.model_dump(exclude_unset=True))),
    )
    db.commit()
    return get_business(ctx)


@router.post("/businesses/{business_id}/onboarding", response_model=BusinessWithRole)
def update_onboarding(
    body: OnboardingIn, db: DB, ctx: BusinessContext = require(Permission.BUSINESS_MANAGE)
) -> BusinessWithRole:
    ctx.business.onboarding_step = body.step
    if body.step == "done" and ctx.business.onboarding_completed_at is None:
        ctx.business.onboarding_completed_at = utcnow()
    db.commit()
    return get_business(ctx)


# --- Team ------------------------------------------------------------------------------------


@router.get("/businesses/{business_id}/members", response_model=list[MemberOut])
def list_members(db: DB, ctx: BusinessContext = require(Permission.TEAM_VIEW)) -> list[MemberOut]:
    rows = db.execute(
        select(Membership, User)
        .join(User, User.id == Membership.user_id)
        .where(Membership.business_id == ctx.business_id, Membership.status == "active")
        .order_by(User.full_name)
    ).all()
    return [
        MemberOut(
            membership_id=m.id,
            user_id=u.id,
            full_name=u.full_name,
            email=u.email,
            role=m.role,
            status=m.status,
            joined_at=m.created_at,
        )
        for m, u in rows
    ]


@router.patch("/businesses/{business_id}/members/{membership_id}", response_model=MemberOut)
def change_member_role(
    membership_id: uuid.UUID, body: RoleUpdate, db: DB, ctx: BusinessContext = require(Permission.TEAM_MANAGE)
) -> MemberOut:
    m = _get_membership(db, ctx, membership_id)
    if m.status != "active":
        raise NotFound("Team member not found.")
    _guard_privileged_change(ctx, Role(m.role), body.role)
    if m.role == Role.OWNER and body.role != Role.OWNER and _active_owner_count(db, ctx.business_id) <= 1:
        raise Conflict("A business must always have at least one owner.", code="last_owner")
    old = m.role
    m.role = body.role
    audit.record(
        db,
        action="member.role_changed",
        entity_type="membership",
        entity_id=m.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{old} -> {body.role}",
    )
    db.commit()
    user = db.get(User, m.user_id)
    return MemberOut(
        membership_id=m.id,
        user_id=user.id,
        full_name=user.full_name,
        email=user.email,
        role=m.role,
        status=m.status,
        joined_at=m.created_at,
    )


@router.delete("/businesses/{business_id}/members/{membership_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(membership_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.TEAM_MANAGE)) -> None:
    m = _get_membership(db, ctx, membership_id)
    if m.status != "active":
        return
    _guard_privileged_change(ctx, Role(m.role))
    if m.role == Role.OWNER and _active_owner_count(db, ctx.business_id) <= 1:
        raise Conflict("A business must always have at least one owner.", code="last_owner")
    m.status = "revoked"
    audit.record(
        db,
        action="member.removed",
        entity_type="membership",
        entity_id=m.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
    )
    db.commit()


@router.get("/businesses/{business_id}/invitations", response_model=list[InvitationOut])
def list_invitations(db: DB, ctx: BusinessContext = require(Permission.TEAM_MANAGE)) -> list[Invitation]:
    return list(
        db.scalars(
            select(Invitation)
            .where(
                Invitation.business_id == ctx.business_id,
                Invitation.accepted_at.is_(None),
                Invitation.revoked_at.is_(None),
                Invitation.expires_at > utcnow(),
            )
            .order_by(Invitation.created_at.desc())
        )
    )


@router.post(
    "/businesses/{business_id}/invitations", response_model=InvitationCreated, status_code=status.HTTP_201_CREATED
)
def invite_member(
    body: InvitationCreate, db: DB, ctx: BusinessContext = require(Permission.TEAM_MANAGE)
) -> InvitationCreated:
    subscriptions.require_feature(db, ctx.business_id, Feature.TEAM)
    pending = len(list_invitations(db, ctx))
    subscriptions.check_member_limit(db, ctx.business_id, pending_invitations=pending)
    _guard_privileged_change(ctx, body.role)
    email = body.email.lower()
    already = db.scalar(
        select(Membership.id)
        .join(User, User.id == Membership.user_id)
        .where(Membership.business_id == ctx.business_id, User.email == email, Membership.status == "active")
    )
    if already:
        raise Conflict("This person is already a member of the business.", code="already_member")

    settings = get_settings()
    token = new_opaque_token()
    now = utcnow()
    inv = Invitation(
        business_id=ctx.business_id,
        email=email,
        role=body.role,
        token_hash=hash_token(token),
        invited_by=ctx.user.id,
        created_at=now,
        expires_at=now + timedelta(days=settings.invitation_days),
    )
    db.add(inv)
    audit.record(
        db,
        action="invitation.created",
        entity_type="invitation",
        entity_id=inv.id,
        business_id=ctx.business_id,
        actor_id=ctx.user.id,
        summary=f"{body.role}",
    )
    db.commit()
    delivered = send_email(
        email,
        f"You've been invited to {ctx.business.name} on STANZ BizFlow",
        f"{ctx.user.full_name} invited you to join {ctx.business.name} as {body.role.replace('_', ' ')}.\n"
        f"Accept within {settings.invitation_days} days: {settings.public_app_url}/invite?token={token}",
    )
    return InvitationCreated(
        **InvitationOut.model_validate(inv).model_dump(), accept_token=token, email_delivered=delivered
    )


@router.delete("/businesses/{business_id}/invitations/{invitation_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_invitation(invitation_id: uuid.UUID, db: DB, ctx: BusinessContext = require(Permission.TEAM_MANAGE)) -> None:
    inv = db.scalar(select(Invitation).where(Invitation.id == invitation_id, Invitation.business_id == ctx.business_id))
    if inv is None:
        raise NotFound("Invitation not found.")
    if inv.accepted_at is None and inv.revoked_at is None:
        inv.revoked_at = utcnow()
        audit.record(
            db,
            action="invitation.revoked",
            entity_type="invitation",
            entity_id=inv.id,
            business_id=ctx.business_id,
            actor_id=ctx.user.id,
        )
        db.commit()


@router.post("/invitations/accept", response_model=BusinessWithRole)
def accept_invitation(body: AcceptInvitationIn, db: DB, auth: Auth) -> BusinessWithRole:
    now = utcnow()
    inv = db.scalar(select(Invitation).where(Invitation.token_hash == hash_token(body.token)).with_for_update())
    if inv is None or inv.revoked_at is not None or inv.accepted_at is not None or inv.expires_at <= now:
        raise AppError("This invitation is invalid or has expired.", code="invitation_invalid")
    if inv.email != auth.user.email:
        raise Forbidden("This invitation was sent to a different email address.", code="invitation_email_mismatch")
    membership = db.scalar(
        select(Membership).where(Membership.business_id == inv.business_id, Membership.user_id == auth.user.id)
    )
    if membership is None:
        membership = Membership(business_id=inv.business_id, user_id=auth.user.id, role=inv.role)
        db.add(membership)
    else:
        membership.role, membership.status = inv.role, "active"
    inv.accepted_at = now
    audit.record(
        db,
        action="invitation.accepted",
        entity_type="invitation",
        entity_id=inv.id,
        business_id=inv.business_id,
        actor_id=auth.user.id,
        summary=inv.role,
    )
    db.commit()
    business = db.get(Business, inv.business_id)
    return BusinessWithRole(
        **business_out(business).model_dump(),
        role=membership.role,
        permissions=sorted(permissions_for(membership.role)),
    )
