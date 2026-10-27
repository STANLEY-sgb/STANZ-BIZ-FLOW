# STANZ BizFlow — implementation plan & status

_Last updated: 2026-10-27 (milestone 2: offline selling)_

## Starting point

The project folder was empty: no existing code, configuration or history to preserve. Tools available on the
development machine: Flutter 3.47.7 (Android toolchain OK), Python 3.13 and Git. **Not available:** PostgreSQL,
Docker, Redis. The visual reference illustration mentioned in the brief was not in the folder, so the palette
uses the brief's starting values, adjusted for contrast (see Design system below).

## Architecture decisions

| Decision | Choice | Why |
|---|---|---|
| Backend shape | Modular monolith (FastAPI) | One deployable, clear module boundaries, no premature microservices |
| Tenancy | Shared schema, `business_id` on every tenant row, enforced in one request dependency | Simple, indexable, testable; RLS can be layered on later |
| Auth | Argon2id passwords, 15-minute JWT access tokens, rotating opaque refresh tokens stored as SHA-256 hashes, server-side sessions | Instant revocation and reuse (theft) detection |
| Money | `NUMERIC(14,2)` in the database, `Decimal` in Python, integer minor units (`BigInt`) in Dart, strings on the wire | No binary floating point anywhere in the money path |
| Sales integrity | Server-side pricing, row locks (`SELECT … FOR UPDATE`) in a fixed order, a per-business receipt counter, `client_reference` idempotency keys | Prevents overselling, duplicate receipt numbers and duplicate sales on retry |
| Plans | Plan limits and features in one module (`app/core/plans.py`); prices not in code | Commercial decisions stay configurable |
| Mobile state | Riverpod 3 (providers + notifiers), GoRouter with a pure, unit-tested redirect policy | Testable and predictable |

## Milestone 1 — delivered and verified

**Backend (55 endpoints, 65 tests passing + 1 PostgreSQL-only test)**
- Auth: register, login, refresh with rotation and reuse detection, logout, logout-all, change password, password reset (single-use, expiring, all sessions revoked), rate limiting
- Businesses: create (with default categories per industry), settings, onboarding progress saved on the server, multi-business membership
- Team: invitations (email if configured, otherwise a shareable code), acceptance with email match, role changes, removal, last-owner protection, owner-only control of owner/admin roles
- Permissions: 6 roles × 21 permissions, enforced on every endpoint; cost prices and IMEI/serial attributes hidden from roles without access
- Products & inventory: CRUD, search (name/SKU/barcode), category and stock filters, barcode lookup, archive/restore, optimistic concurrency (`version`), append-only stock ledger (receipt, count, damage, adjustment, return, sale), weighted-average cost
- Sales/POS: atomic sales, price-change detection, line and order discounts (permission-gated), tax extraction from tax-inclusive prices, change calculation, net payment recording, receipts, partial/full returns with pro-rata refunds and optional restock, all idempotent
- Customers and expenses: CRUD; expenses soft-deleted with an audit trail
- Reports: dashboard (period comparison, cashier-restricted view), summary P&L, by day/product/category/cashier/payment method, expenses by category, inventory valuation, low stock, CSV export with formula-injection protection
- Subscriptions: Free / Starter / Professional limits enforced on the server, one trial per business, billing boundary that never grants a plan without verified payment
- Offline sync endpoint: batched, per-operation accept/duplicate/reject, device-clock sanity window
- Audit log, structured JSON logs, request IDs, health/readiness probes, uniform error envelope
- Alembic initial migration, tested to produce exactly the model schema and to downgrade cleanly; PostgreSQL DDL rendered and checked

**Mobile (28 tests passing, analyzer clean)**
- Design system: semantic colour tokens, 4-pt spacing, radii, motion, elevation, Inter font bundled for offline use
- Welcome, register, sign-in, forgot password; secure token storage; automatic refresh; session-expiry handling
- 3-step business creation wizard (type, region/currency/time zone, payment methods), resumable setup checklist, invitation acceptance, business switching
- Dashboard with real metrics, comparisons, low-stock alerts, top sellers and recent sales (cashier view limited to their own sales)
- Products: search, filters, detail, create/edit (device fields for phone shops), receive/count/damage stock, stock history
- POS: search or hardware-scanner input, cart, discounts (if permitted), payment methods, cash change, safe retry, receipt with share-as-text, returns
- Sales history, expenses, reports with a date range, team, plan & usage, business settings
- Bottom navigation on phones, navigation rail on tablets; layouts tested at 320 px width, 1.6× text and tablet size

## Milestone 2 — offline selling (delivered, 34 mobile tests passing)

- Drift/SQLite store on the device: product catalogue cache, business profile cache, durable sale queue
- POS falls back to the saved catalogue (barcode scans included) with an "as of last sync" banner
- Checkout queues the sale under the same idempotency key when the network fails, so it cannot be duplicated
- Background sync on start-up, on reconnect, every minute and on demand, with bounded exponential backoff
- Offline sync screen showing pending and rejected sales, the server's reason, and what to do next
- Queued sales are tied to the cashier who made them (safe on shared phones); sign-out warns about unsynced sales
- Tests: paging catalogue refresh, offline search and scan, idempotent re-queue (this caught and fixed a
  double stock decrement), accepted/duplicate/rejected handling, backoff, and per-user scoping

## Next milestones (recommended order)

1. **Product import/export:** CSV/Excel upload with preview, column mapping, row errors and an asynchronous job for large files.
3. **Product photos and receipt logo:** object storage, signed URLs and upload validation.
4. **Camera barcode scanning** (hardware/Bluetooth scanners already work through the search field).
5. **Customer screens in the app** (the API is done) and customer selection at checkout.
6. **Email provider** (SMTP is implemented and needs credentials), email verification.
7. **Billing provider** after choosing one (e.g. a Ugandan mobile money aggregator for web billing) and reviewing Google Play / App Store rules for in-app digital subscriptions.
8. **Hardening:** PostgreSQL Row-Level Security as a second isolation layer, Redis-backed rate limiting for multi-instance deployments, load testing, crash reporting (Sentry or Firebase Crashlytics).
9. **Brand assets:** final app icon and splash (the in-app logo mark is drawn in code for now), store screenshots.

## Known limitations (honest status)

- **No PostgreSQL run yet.** No PostgreSQL server was available on this machine, and running downloaded PostgreSQL binaries was blocked by the tool sandbox. The full suite passes on SQLite, the migration renders valid PostgreSQL DDL, and CI is configured to run the suite (including the concurrent-oversell test) on PostgreSQL 17. That test has **not been executed yet**.
- **Mobile app not yet run on a device or emulator against a live API.** The Dart code compiles: `flutter analyze` is clean and 28 tests pass. The first Android debug APK build was stopped because the machine ran low on memory, so a full Gradle build has not completed yet. iOS was not built: that needs macOS and Xcode.
- **Offline covers sales only.** Product edits, stock adjustments, expenses and returns need a connection (see OFFLINE_SYNC.md).
- The offline flow is unit-tested against a fake server and an in-memory SQLite database. It has not yet been
  tried on a real phone in airplane mode.
- Emails are not delivered until SMTP credentials are configured. The API reports `email_delivered: false` and never claims otherwise.
- No real payment processing. Payments are *recorded*, not charged.
- Rate limiting is in-memory (per process). Use a shared store before running multiple API replicas.
- Dark mode is intentionally not shipped yet.
