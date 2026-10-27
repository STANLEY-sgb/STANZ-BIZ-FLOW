# STANZ BizFlow — implementation plan & status

_Last updated: 2026-10-28 (milestone 3: import/export, customers)_

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

## Device test — Samsung Galaxy S21 (SM-G991U, Android 13), 2026-10-28

The debug APK was installed over wireless debugging, talking to a local API through `adb reverse`. Everything
below was done in the real app on the phone, and the results were checked against the server:

| Flow | Result |
|---|---|
| Register → 3-step business setup → checklist | ✅ account and business created; industry categories loaded |
| Add product with phone-shop details (brand, model, storage, colour, warranty, IMEI) | ✅ stored exactly |
| Online sale: 1 phone + 2 cases, cash 700,000 | ✅ receipt R-000001, total 680,000, change 20,000 |
| Receive stock with unit cost | ✅ 2 → 6 units, weighted-average cost 506,667 |
| Reports | ✅ net sales, COGS and gross profit match the server |
| Server stopped → POS uses saved catalogue with an "Offline…" banner | ✅ |
| Offline barcode scan → sale queued | ✅ |
| App force-killed with a queued sale, server restarted, app relaunched | ✅ synced once (R-000002), stock correct |
| Expired access token on relaunch | ✅ refreshed automatically |
| Two tills, last stock: phone queues 6 offline while a second till sells 1 | ✅ server **rejected** the offline sale (`insufficient_stock`); no partial data |
| Manager restocks → cashier taps Retry | ✅ recorded once (R-000004), stock 6 → 0 |

Issues found on the device and fixed in this milestone:
- Prices were truncated ("UGX 65…") at the phone's large font size. Money now scales down and never truncates,
  and a regression test covers it.
- Product tiles, cart lines and the product form were cramped at large font sizes, so their layouts were reworked.
- Rejected offline sales had no Retry action, although the guidance told users to retry. Retry was added, with a test.
- The offline catalogue kept stale stock after an online sale. It is now refreshed after every online sale.
- Copy and visual fixes: comparison wording, header alignment, button labels, setup checklist ticks, and the
  welcome illustration overlapping at large font sizes.
- The Gradle heap was lowered from 8 GB to 3 GB (Kotlin compiled in-process). The template default had caused
  out-of-memory kills on this 12 GB machine.

## Milestone 3 — product import/export and customers (delivered, device-tested)

- **Import** (`POST /products/import`) for CSV or Excel (.xlsx), up to 5,000 rows / 2 MB. Common header spellings
  are recognised ("Price", "Qty", "Buying price"…). A dry run reports every row (new / update / skip / error,
  using spreadsheet row numbers) before anything is saved. Applying is a single transaction. Duplicate SKUs or
  barcodes are caught. Categories are created as needed. Existing products are skipped unless "update existing"
  is chosen, and stock differences are then recorded as stock-count movements. Plan limits are enforced, and
  users without cost or IMEI permission cannot set those fields.
- **Export** (`GET /products/export.csv`) in the same layout (it round-trips). Cost and IMEI columns depend on
  role, spreadsheet formulas are neutralised, and a UTF-8 BOM is added so Excel opens it correctly.
- **Mobile:** an import screen (pick file → review → confirm), export through the Android share sheet,
  a customers list and detail screen (purchases and total spent), and an optional customer picker at checkout
  with quick-add.
- **Tests:** 9 backend import/export tests; mobile model and session tests.
- **Device test (S21):** picked a real CSV from Downloads, got the 5-new / 2-error report, imported the valid
  rows; exported via the share sheet; added a customer at checkout, and the receipt and customer stats were
  verified on the server.
- **Found on the device and fixed:** after an offline start, the app never reloaded the user's profile, so
  their name and business list stayed missing. It now retries with backoff, and a test covers it.
- **Build fix (Windows):** turned off Kotlin incremental compilation, which crashes when plugin sources (Pub
  cache on C:) and the project (E:) are on different drives.

## Next milestones (recommended order)

1. **Product photos and receipt logo:** object storage, signed URLs and upload validation.
2. **Camera barcode scanning** (hardware/Bluetooth scanners already work through the search field).
3. **Email provider** (SMTP is implemented and needs credentials), email verification.
4. **Billing provider** after choosing one (e.g. a Ugandan mobile money aggregator for web billing) and reviewing Google Play / App Store rules for in-app digital subscriptions.
5. **Hardening:** asynchronous jobs for very large imports, PostgreSQL Row-Level Security as a second isolation layer, Redis-backed rate limiting for multi-instance deployments, load testing, crash reporting (Sentry or Firebase Crashlytics).
6. **Brand assets:** final app icon and splash (the in-app logo mark is drawn in code for now), store screenshots.

## Known limitations (honest status)

- **PostgreSQL verified in CI, not locally.** No PostgreSQL server is available on the development machine. GitHub Actions run `18c82a1` passed the full backend suite against a PostgreSQL 17 service, including the step that enables the concurrent-oversell test. The step passed; the per-test log was not downloaded.
- **Android tested on one real device** (Samsung S21, Android 13), see above. iOS has not been built: that
  needs macOS and Xcode. Small and older Android phones still need a pass.
- **Offline covers sales only.** Product edits, stock adjustments, expenses and returns need a connection (see OFFLINE_SYNC.md).
- Offline was simulated on the device by stopping the server or removing the adb tunnel. Network errors
  look the same to the app as airplane mode, but airplane mode itself was not toggled, because that would also
  have cut the wireless debugging connection.
- Emails are not delivered until SMTP credentials are configured. The API reports `email_delivered: false` and never claims otherwise.
- No real payment processing. Payments are *recorded*, not charged.
- Rate limiting is in-memory (per process). Use a shared store before running multiple API replicas.
- Dark mode is intentionally not shipped yet.
