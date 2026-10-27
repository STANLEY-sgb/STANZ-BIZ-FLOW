# Offline & synchronisation policy

Status: **implemented on both sides.** The server endpoints are `POST /businesses/{id}/sync/sales` and
`GET /businesses/{id}/sync/status`. The device side is a Drift/SQLite store in `mobile/lib/data/local/`.

## How it works on the phone

1. When the shell opens, and whenever connectivity returns, the app downloads the full active catalogue
   (100 products per page) and caches the business profile. Both are stored per business.
2. The POS searches the live server. If the network is unreachable it falls back to the saved catalogue and
   shows a banner: "Products and stock as of <time>".
3. At checkout the app first tries the server. If that fails with a network error, the **same request with the
   same idempotency key** is saved in `pending_sales`, tagged with the business, the cashier's user ID and the
   device ID. If the original request actually reached the server, the later sync is answered `duplicate`.
4. The sync engine sends due sales in batches of 25: at start-up, on reconnect, every 60 seconds and on
   "Sync now". Results are stored per sale. Accepted and duplicate sales get their server receipt numbers and
   are pruned after 7 days. Rejected sales stay on the **Offline sync** screen with the server's reason and
   advice on what to do.
5. Only the cashier who recorded a sale can send it. If someone else signs in on a shared phone, those sales
   wait until the original user signs back in. Signing out warns about sales that have not synced.

## Rules

| Situation | Behaviour |
|---|---|
| Every queued sale | Gets a unique `client_reference` (UUID) when it is created on the device and keeps it for life |
| Network timeout or app killed mid-sync | The device resends. The server answers `duplicate` with the original receipt number, so nothing is recorded twice |
| Server validation | Identical to online sales: authentication, **active** membership, permissions, current prices, stock, plan limits |
| Two offline devices sell the last unit | The first to sync is `accepted`. The second is `rejected` with `insufficient_stock` and is never silently confirmed. The device keeps it under "Needs review" for a manager to resolve (receive stock, then resubmit, or record a refund) |
| Price changed while offline | `rejected` / `price_changed`. A manager resubmits at the current price, with an authorised discount if the customer paid the old price |
| Membership revoked or role lost | The whole batch is refused (`404` / `403`). The queue stays on the device; the app asks the user to sign in to a business they still belong to |
| Implausible device clock | The server records its own time; the device time is kept in `client_created_at` |
| Conflicting product edits | Product updates carry `version`. A stale version returns `409 version_conflict` and the user reloads |
| One bad operation in a batch | Each operation commits independently, so the rest still sync |
| Stock shown while offline | The device labels it "as of last sync" and never presents it as current |

## Device schema (Drift, `local_db.dart`)

- `pending_sales(client_reference PK, business_id, user_id, payload_json, preview_total, summary, created_at,
  state[pending|syncing|accepted|duplicate|rejected], attempts, next_attempt_at, last_error_code,
  last_error_message, server_sale_id, receipt_number, acknowledged_at)`
- `cached_products(business_id, id, name_lower, sku, barcode, is_active, json, synced_at)`
- `key_values(key, value)`: cached business profile and last catalogue sync time

Retries use bounded exponential backoff: 5 s, 10 s, 20 s … capped at 10 minutes. Authentication tokens stay in
the platform keystore, never in SQLite.

## Known limits

- Product edits, stock adjustments, expenses and returns still need a connection. Only sales are queued.
- The local database is protected by app sandboxing but is not separately encrypted (SQLCipher is a possible
  later hardening step). It holds catalogue data and queued sales, never passwords or tokens.
