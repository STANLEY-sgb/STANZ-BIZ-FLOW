# Security

## Controls implemented (with tests)

| Control | Where | Test |
|---|---|---|
| Argon2id password hashing, timing-equalised login | `core/security.py` | `test_password_hash_is_not_plaintext`, `test_wrong_password_and_unknown_email_look_identical` |
| Short-lived access tokens + server-side sessions (instant revocation) | `api/deps.py` | `test_logout_revokes_access_token` |
| Refresh-token rotation with reuse detection | `modules/auth.py` | `test_refresh_rotates_and_reuse_revokes_session` |
| Single-use, expiring password reset; ends all sessions; no account enumeration | `modules/auth.py` | `test_password_reset_flow` |
| Rate limiting on register, login, refresh, reset | `core/rate_limit.py` | `test_login_rate_limited` |
| Tenant isolation (404 for non-members, scoped lookups) | `api/deps.py` + every module | `tests/test_tenancy.py` |
| Role permissions on every endpoint | `core/permissions.py` | `tests/test_permissions.py` |
| Sensitive fields (cost price, IMEI/serial) hidden *and* protected from overwrite | `modules/products.py` | `test_cashier_can_sell_but_not_see_confidential_data` |
| Server-authoritative prices, totals and stock; idempotency | `modules/sales.py` | `tests/test_sales.py` |
| Paid plans only via verified provider callbacks | `modules/subscriptions.py` | `test_checkout_does_not_grant_plan` |
| CSV formula-injection guard on exports | `modules/reports.py` | — |
| Uniform error envelope, no stack traces to clients | `core/errors.py` | `test_error_responses_hide_internals` |
| Production refuses weak `JWT_SECRET` or the log-only email backend; API docs disabled | `core/config.py`, `main.py` | — |
| Tokens are stored only as SHA-256 digests (refresh, reset, invitation) | models | — |
| Mobile: tokens in Keystore/Keychain; `allowBackup=false`; HTTP allowed only in debug | `mobile/` | — |
| Audit trail for membership, product, stock, sale, refund, expense and subscription changes | `modules/audit.py` | `test_permission_changes_are_audited` |

Logs record method, path, status and duration. They never record query strings, request bodies, passwords or tokens.

## Still to do before production

- PostgreSQL Row-Level Security as defence in depth (needs a non-owner application role and a transaction-local
  `app.business_id` setting; it must be tested with the connection pooler)
- Redis-backed rate limiting when running more than one API instance
- File upload validation and signed URLs, when uploads are added
- Run `pip-audit` and `flutter pub outdated` in CI on every merge (the workflow includes `pip-audit`)
- An external penetration test before handling real customer data at scale

## Data retention

- Customers can be deleted. Their personal data is removed and the sales keep their financial record without
  the link.
- Expenses are soft-deleted so the financial audit trail stays intact.
- Sales and stock movements are never deleted. Corrections are new, auditable records (returns, adjustments).
- Revoked sessions and used tokens can be purged after 90 days by a scheduled job (not yet implemented).
