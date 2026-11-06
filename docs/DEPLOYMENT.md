# Deployment, backup & recovery

Nothing has been deployed. This guide describes what a deployment needs. Every external service listed must be
created and paid for by STANZ DIGITAL CONNECT.

## Required infrastructure

| Component | Notes |
|---|---|
| Managed PostgreSQL 15+ | Automated daily backups and point-in-time recovery enabled. Separate databases for staging and production |
| Container runtime for the API | Build from `backend/Dockerfile`. Runs as a non-root user and exposes `:8000` |
| HTTPS termination | Load balancer or platform proxy. Uvicorn runs with `--proxy-headers`. Restrict `--forwarded-allow-ips` to the proxy's addresses |
| Secret manager | Holds `DATABASE_URL`, `JWT_SECRET` (≥ 32 random characters) and SMTP credentials |
| SMTP provider | Needed for password reset and invitation emails (`EMAIL_BACKEND=smtp`) |
| Error monitoring | e.g. Sentry (not yet integrated) |
| Persistent volume for uploads | Product photos and logos when `STORAGE_BACKEND=local` (mounted at `/data/uploads` in the image). Back it up with the database, or switch to object storage |
| Redis (optional) | Only when running multiple API replicas (shared rate limits) |

## Environment variables

See `backend/.env.example`. In production set `APP_ENV=production`. The API refuses to start if `JWT_SECRET` is
missing or short, or if the email backend is `log`.

## Release procedure

1. Build and push the image from the commit that CI tested.
2. **Back up the database** (or confirm a recent automatic snapshot exists).
3. Run the migration as a one-off job: `alembic upgrade head`.
4. Roll out the new API version. Check `GET /ready` (database reachable) and `GET /health`.
5. Watch error rates and latency for 15 minutes.

**Rollback:** redeploy the previous image. Run `alembic downgrade -1` only if the migration is known to be
reversible and no new data depends on it. Otherwise restore from the pre-release backup.

## Backup & restore

```bash
# Logical backup (in addition to the provider's automatic snapshots)
pg_dump --format=custom --no-owner "$DATABASE_URL" > bizflow-$(date +%F).dump

# Restore into an EMPTY database
pg_restore --no-owner --dbname "$RESTORE_DATABASE_URL" bizflow-YYYY-MM-DD.dump
```

Run a restore drill into a staging database every quarter, then run the test suite and spot-check row counts.
Keep backups encrypted, in a different region or account from production.

## Mobile release

- Android: create an upload keystore (never commit it), configure `key.properties`, then
  `flutter build appbundle --dart-define=API_BASE_URL=https://api.<your-domain>/api/v1`.
- iOS: needs macOS, Xcode and an Apple Developer account.
- Store listings need final icons, screenshots, a privacy policy URL and a data-safety declaration
  (data collected: name, email, phone, business records).
- Selling subscriptions inside the app may require Google Play Billing or Apple In-App Purchase. Decide
  this before enabling any in-app purchase flow.

## Quick cloud demo (Render)

1. Push the repository to GitHub, then in Render choose **New → Blueprint** and select it (`render.yaml` is at the root).
2. Render creates the PostgreSQL database and the API, runs `alembic upgrade head` on every start, and generates `JWT_SECRET`.
3. Your API is then at `https://<service>.onrender.com/api/v1`. Seed demo data with
   `python backend/scripts/seed_and_smoke.py --base https://<service>.onrender.com/api/v1`.
4. Build the app: `flutter build apk --release --dart-define=API_BASE_URL=https://<service>.onrender.com/api/v1`.

Limits of the free plans: the API sleeps when idle (first request is slow), uploaded photos live on temporary disk and
disappear on redeploy (use S3-compatible storage or a persistent disk for real use), and the free database expires after 30 days.
Use `APP_ENV=production` only once SMTP email is configured; production refuses `EMAIL_BACKEND=log`.
