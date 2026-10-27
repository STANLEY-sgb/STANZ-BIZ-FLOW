# Offline & synchronisation policy

Status: the **server contract is implemented and tested** (`POST /businesses/{id}/sync/sales`,
`GET /businesses/{id}/sync/status`). The device-side queue (Drift/SQLite) is the next milestone.

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

## Planned device schema (Drift)

`pending_operations(id, client_reference UNIQUE, business_id, device_id, type, payload_json, created_at,
state[pending|syncing|accepted|duplicate|rejected], attempts, last_error_code, last_error_message,
server_sale_id, receipt_number, acknowledged_at)`

Retries use bounded exponential backoff (5 s → 10 min). Authentication tokens stay in the platform keystore,
never in SQLite.
