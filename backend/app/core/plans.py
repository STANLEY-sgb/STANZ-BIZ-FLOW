"""Subscription plan catalogue.

Plan limits and entitlements live here (and only here). Prices are deliberately
NOT defined in code: they are commercial decisions configured per market in the
billing provider / `subscription_prices` once billing is activated.
`None` means unlimited.
"""

from dataclasses import dataclass, field
from enum import StrEnum


class Feature(StrEnum):
    TEAM = "team"
    ADVANCED_REPORTS = "advanced_reports"
    EXPORTS = "exports"
    CUSTOMERS = "customers"
    EXPENSES = "expenses"
    MULTI_BRANCH = "multi_branch"


@dataclass(frozen=True)
class Plan:
    code: str
    name: str
    max_products: int | None
    max_members: int | None
    max_sales_per_month: int | None
    features: frozenset[Feature] = field(default_factory=frozenset)
    trial_days: int = 0


PLANS: dict[str, Plan] = {
    "free": Plan(
        code="free",
        name="Free",
        max_products=50,
        max_members=1,
        max_sales_per_month=300,
        features=frozenset({Feature.CUSTOMERS, Feature.EXPENSES}),
    ),
    "starter": Plan(
        code="starter",
        name="Starter",
        max_products=1000,
        max_members=3,
        max_sales_per_month=5000,
        features=frozenset({Feature.CUSTOMERS, Feature.EXPENSES, Feature.TEAM, Feature.EXPORTS}),
        trial_days=14,
    ),
    "professional": Plan(
        code="professional",
        name="Professional",
        max_products=None,
        max_members=25,
        max_sales_per_month=None,
        features=frozenset(Feature),
        trial_days=14,
    ),
}

DEFAULT_PLAN = "free"
