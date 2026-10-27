# Architecture

## Backend (`backend/app`)

```
core/        config, database, security (Argon2id, JWT, token hashing), errors, money, permissions,
             plans, rate limiting, logging, mailer
models/      SQLAlchemy 2 models (identity, business, catalog, sales)
api/         request dependencies (auth + tenant context) and pagination
modules/     one router + service per domain:
             auth, businesses (team, invitations), products, inventory (ledger service),
             sales (POS, receipts, returns), customers, expenses, reports, subscriptions, sync, audit, health
```

### Tenant isolation

Every business-scoped route lives under `/api/v1/businesses/{business_id}/…` and depends on
`get_business_context`. That dependency:

1. authenticates the bearer token *and* checks that its server-side session has not been revoked;
2. loads the caller's **active** membership for that business, returning `404` (never `403`) when there is none,
   so business IDs cannot be probed;
3. derives permissions from the membership role on the server.

Every query then filters on `ctx.business_id`. Records referenced inside a request body (product, category or
customer IDs) are always looked up *within* that business. `tests/test_tenancy.py` tries ID swapping, cross-tenant
writes, search, receipts, exports and returns.

### Roles

| Role | Highlights |
|---|---|
| owner | everything, including subscription |
| admin | everything except subscription; cannot grant, change or remove owner or admin roles |
| manager | catalogue, stock, sales, discounts, refunds, customers, expenses, reports |
| cashier | sell, view products (no cost prices or device IDs), customers |
| inventory_manager | catalogue, costs, device IDs, stock adjustments |
| accountant | reports, expenses, sales history, cost prices |

The mobile app hides controls the role cannot use, purely for convenience: the server checks permissions on
every request.

### Sale transaction

`create_sale` runs inside one database transaction:

1. return the existing sale if the `client_reference` was already used (idempotent replay);
2. check permissions, the plan's sales limit, payment methods and the customer;
3. lock the business row (receipt counter), then lock the products sorted by ID (deadlock-free ordering);
4. price every line from the product record, reject `price_changed` if the cashier saw a different price;
5. write stock movements (rejecting `insufficient_stock` if stock enforcement is on);
6. calculate discounts, tax-inclusive tax, tendered amount and change; record net payments;
7. assign the next receipt number, write the sale, items, payments and audit event, then commit.

A race between two identical retries is caught by the unique `(business_id, client_reference)` constraint and
resolved by returning the winning sale.

## Mobile (`mobile/lib`)

```
core/        theme (tokens, theme), api (client, errors, secure token store), money, session, widgets
data/        typed models and the REST wrapper
features/    auth, onboarding, dashboard, products, pos, sales, expenses, reports, more (team, plan, settings)
app/         router (pure redirect policy) and adaptive shell
```

### Design system

Colours are only referenced through `BizColors` tokens:

| Token | Value | Use |
|---|---|---|
| primary | `#F47745` | primary actions, selected states |
| secondary | `#438FCB` | information, charts, secondary actions |
| navy | `#20243F` | headings, navigation, hero surfaces |
| secondaryContainer | `#EAF4FC` | soft info backgrounds |
| background | `#F8FAFC` | page background |
| textSecondary | `#5F6B7E` | darkened from `#687386` to keep AA contrast on the off-white background |
| warning | `#B87508` | darkened from `#D99018` so warning text on white passes AA |
| success / error | `#21865A` / `#D94848` | status |

Type: Inter (bundled, SIL OFL), with tabular figures for money. Spacing uses a 4-point scale and is capped at a
720 px content width on tablets. Animations stay short and turn off when the system asks for reduced motion.
