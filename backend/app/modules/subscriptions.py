"""Plans, entitlements and usage limits — enforced on the server.

Billing activation boundary: paid plans are only granted by `activate_paid_plan`,
which must be called from a verified payment-provider webhook (or an
App Store / Google Play server notification). No client-reported payment
success ever changes a plan. Until a provider is configured, the upgrade
endpoint returns `billing_not_configured`.
"""

import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import DB, BusinessContext, Ctx, require
from app.core.database import utcnow
from app.core.errors import AppError, PaymentRequired
from app.core.permissions import Permission
from app.core.plans import DEFAULT_PLAN, PLANS, Feature, Plan
from app.models import BusinessSubscription, Membership, Product, Sale
from app.modules import audit
from app.modules.reports_time import month_start_utc

ENTITLED_STATUSES = {"trialing", "active", "past_due"}  # past_due = grace period


def create_default_subscription(db: Session, business_id: uuid.UUID) -> BusinessSubscription:
    sub = BusinessSubscription(business_id=business_id, plan_code=DEFAULT_PLAN, status="active")
    db.add(sub)
    return sub


def get_subscription(db: Session, business_id: uuid.UUID) -> BusinessSubscription:
    sub = db.scalar(select(BusinessSubscription).where(BusinessSubscription.business_id == business_id))
    if sub is None:
        sub = create_default_subscription(db, business_id)
        db.flush()
    return sub


def effective_plan(db: Session, business_id: uuid.UUID, now: datetime | None = None) -> Plan:
    """The plan whose limits apply now. Lapsed paid plans fall back to Free (data is kept)."""
    sub = get_subscription(db, business_id)
    now = now or utcnow()
    if sub.status not in ENTITLED_STATUSES:
        return PLANS[DEFAULT_PLAN]
    if sub.status == "trialing" and sub.trial_ends_at and sub.trial_ends_at <= now:
        return PLANS[DEFAULT_PLAN]
    return PLANS.get(sub.plan_code, PLANS[DEFAULT_PLAN])


def require_feature(db: Session, business_id: uuid.UUID, feature: Feature) -> None:
    plan = effective_plan(db, business_id)
    if feature not in plan.features:
        raise PaymentRequired(
            f"This feature is not included in the {plan.name} plan.",
            code="feature_not_in_plan",
            details={"feature": feature, "plan": plan.code},
        )


def check_product_limit(db: Session, business_id: uuid.UUID) -> None:
    plan = effective_plan(db, business_id)
    if plan.max_products is None:
        return
    count = db.scalar(
        select(func.count()).select_from(Product).where(Product.business_id == business_id, Product.is_active)
    )
    if count >= plan.max_products:
        raise PaymentRequired(
            f"The {plan.name} plan allows up to {plan.max_products} active products.",
            details={"limit": plan.max_products, "plan": plan.code},
        )


def check_member_limit(db: Session, business_id: uuid.UUID, pending_invitations: int = 0) -> None:
    plan = effective_plan(db, business_id)
    if plan.max_members is None:
        return
    count = db.scalar(
        select(func.count())
        .select_from(Membership)
        .where(Membership.business_id == business_id, Membership.status == "active")
    )
    if count + pending_invitations >= plan.max_members:
        raise PaymentRequired(
            f"The {plan.name} plan allows up to {plan.max_members} team members.",
            details={"limit": plan.max_members, "plan": plan.code},
        )


def check_sales_limit(db: Session, business_id: uuid.UUID, timezone: str) -> None:
    plan = effective_plan(db, business_id)
    if plan.max_sales_per_month is None:
        return
    count = db.scalar(
        select(func.count())
        .select_from(Sale)
        .where(Sale.business_id == business_id, Sale.created_at >= month_start_utc(timezone))
    )
    if count >= plan.max_sales_per_month:
        raise PaymentRequired(
            f"The {plan.name} plan allows up to {plan.max_sales_per_month} sales per month.",
            details={"limit": plan.max_sales_per_month, "plan": plan.code},
        )


def start_trial(db: Session, business_id: uuid.UUID, plan_code: str, actor_id: uuid.UUID) -> BusinessSubscription:
    plan = PLANS[plan_code]
    sub = get_subscription(db, business_id)
    if sub.trial_ends_at is not None:
        raise AppError("A free trial has already been used for this business.", code="trial_used")
    if plan.trial_days <= 0:
        raise AppError("This plan does not offer a trial.", code="no_trial")
    sub.plan_code = plan.code
    sub.status = "trialing"
    sub.trial_ends_at = utcnow() + timedelta(days=plan.trial_days)
    audit.record(
        db,
        action="subscription.trial_started",
        entity_type="subscription",
        entity_id=sub.id,
        business_id=business_id,
        actor_id=actor_id,
        summary=f"Trial of {plan.name}",
    )
    return sub


def activate_paid_plan(
    db: Session, business_id: uuid.UUID, plan_code: str, period_end: datetime, provider: str, provider_reference: str
) -> BusinessSubscription:
    """Call ONLY after verifying the payment with the provider server-side."""
    sub = get_subscription(db, business_id)
    sub.plan_code = PLANS[plan_code].code
    sub.status = "active"
    sub.current_period_end = period_end
    sub.provider = provider
    sub.provider_reference = provider_reference
    audit.record(
        db,
        action="subscription.activated",
        entity_type="subscription",
        entity_id=sub.id,
        business_id=business_id,
        summary=f"{plan_code} via {provider}",
    )
    return sub


# --- API -------------------------------------------------------------------------------------


class PlanOut(BaseModel):
    code: str
    name: str
    max_products: int | None
    max_members: int | None
    max_sales_per_month: int | None
    features: list[str]
    trial_days: int


class SubscriptionOut(BaseModel):
    plan: PlanOut
    status: str
    trial_ends_at: datetime | None
    current_period_end: datetime | None
    usage: dict[str, int]


class TrialIn(BaseModel):
    plan_code: str


def _plan_out(plan: Plan) -> PlanOut:
    return PlanOut(
        code=plan.code,
        name=plan.name,
        max_products=plan.max_products,
        max_members=plan.max_members,
        max_sales_per_month=plan.max_sales_per_month,
        features=sorted(plan.features),
        trial_days=plan.trial_days,
    )


router = APIRouter(tags=["subscriptions"])


@router.get("/plans", response_model=list[PlanOut])
def list_plans() -> list[PlanOut]:
    return [_plan_out(p) for p in PLANS.values()]


@router.get("/businesses/{business_id}/subscription", response_model=SubscriptionOut)
def current_subscription(db: DB, ctx: Ctx) -> SubscriptionOut:
    sub = get_subscription(db, ctx.business_id)
    plan = effective_plan(db, ctx.business_id)
    bid = ctx.business_id
    usage = {
        "products": db.scalar(
            select(func.count()).select_from(Product).where(Product.business_id == bid, Product.is_active)
        ),
        "members": db.scalar(
            select(func.count())
            .select_from(Membership)
            .where(Membership.business_id == bid, Membership.status == "active")
        ),
        "sales_this_month": db.scalar(
            select(func.count())
            .select_from(Sale)
            .where(Sale.business_id == bid, Sale.created_at >= month_start_utc(ctx.business.timezone))
        ),
    }
    db.commit()
    return SubscriptionOut(
        plan=_plan_out(plan),
        status=sub.status,
        trial_ends_at=sub.trial_ends_at,
        current_period_end=sub.current_period_end,
        usage=usage,
    )


@router.post("/businesses/{business_id}/subscription/trial", response_model=SubscriptionOut)
def begin_trial(
    body: TrialIn, db: DB, ctx: BusinessContext = require(Permission.SUBSCRIPTION_MANAGE)
) -> SubscriptionOut:
    if body.plan_code not in PLANS:
        raise AppError("Unknown plan.", code="unknown_plan")
    start_trial(db, ctx.business_id, body.plan_code, ctx.user.id)
    db.commit()
    return current_subscription(db, ctx)


@router.post("/businesses/{business_id}/subscription/checkout")
def start_checkout(body: TrialIn, ctx: BusinessContext = require(Permission.SUBSCRIPTION_MANAGE)) -> None:
    # Integration boundary: create a provider checkout session here once a provider is selected.
    raise AppError(
        "Online billing is not yet available. Contact STANZ DIGITAL CONNECT to upgrade.",
        code="billing_not_configured",
    )
