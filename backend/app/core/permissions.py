"""Roles and permissions. The backend is the single source of truth."""

from enum import StrEnum


class Role(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    MANAGER = "manager"
    CASHIER = "cashier"
    INVENTORY_MANAGER = "inventory_manager"
    ACCOUNTANT = "accountant"


class Permission(StrEnum):
    BUSINESS_VIEW = "business.view"
    BUSINESS_MANAGE = "business.manage"
    TEAM_VIEW = "team.view"
    TEAM_MANAGE = "team.manage"
    SUBSCRIPTION_MANAGE = "subscription.manage"
    PRODUCTS_VIEW = "products.view"
    PRODUCTS_MANAGE = "products.manage"
    PRODUCTS_VIEW_COST = "products.view_cost"
    DEVICE_IDS_VIEW = "products.view_device_ids"
    INVENTORY_ADJUST = "inventory.adjust"
    INVENTORY_VIEW = "inventory.view"
    SALES_CREATE = "sales.create"
    SALES_VIEW_ALL = "sales.view_all"
    SALES_DISCOUNT = "sales.discount"
    SALES_REFUND = "sales.refund"
    CUSTOMERS_VIEW = "customers.view"
    CUSTOMERS_MANAGE = "customers.manage"
    EXPENSES_VIEW = "expenses.view"
    EXPENSES_MANAGE = "expenses.manage"
    REPORTS_VIEW = "reports.view"
    AUDIT_VIEW = "audit.view"


P = Permission

_ALL = frozenset(Permission)

ROLE_PERMISSIONS: dict[Role, frozenset[Permission]] = {
    Role.OWNER: _ALL,
    Role.ADMIN: _ALL - {P.SUBSCRIPTION_MANAGE},
    Role.MANAGER: frozenset(
        {
            P.BUSINESS_VIEW,
            P.TEAM_VIEW,
            P.PRODUCTS_VIEW,
            P.PRODUCTS_MANAGE,
            P.PRODUCTS_VIEW_COST,
            P.DEVICE_IDS_VIEW,
            P.INVENTORY_VIEW,
            P.INVENTORY_ADJUST,
            P.SALES_CREATE,
            P.SALES_VIEW_ALL,
            P.SALES_DISCOUNT,
            P.SALES_REFUND,
            P.CUSTOMERS_VIEW,
            P.CUSTOMERS_MANAGE,
            P.EXPENSES_VIEW,
            P.EXPENSES_MANAGE,
            P.REPORTS_VIEW,
        }
    ),
    Role.CASHIER: frozenset(
        {P.BUSINESS_VIEW, P.PRODUCTS_VIEW, P.INVENTORY_VIEW, P.SALES_CREATE, P.CUSTOMERS_VIEW, P.CUSTOMERS_MANAGE}
    ),
    Role.INVENTORY_MANAGER: frozenset(
        {
            P.BUSINESS_VIEW,
            P.PRODUCTS_VIEW,
            P.PRODUCTS_MANAGE,
            P.PRODUCTS_VIEW_COST,
            P.DEVICE_IDS_VIEW,
            P.INVENTORY_VIEW,
            P.INVENTORY_ADJUST,
        }
    ),
    Role.ACCOUNTANT: frozenset(
        {
            P.BUSINESS_VIEW,
            P.PRODUCTS_VIEW,
            P.PRODUCTS_VIEW_COST,
            P.INVENTORY_VIEW,
            P.SALES_VIEW_ALL,
            P.EXPENSES_VIEW,
            P.EXPENSES_MANAGE,
            P.REPORTS_VIEW,
            P.CUSTOMERS_VIEW,
        }
    ),
}


def permissions_for(role: Role | str) -> frozenset[Permission]:
    return ROLE_PERMISSIONS[Role(role)]
