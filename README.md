# STANZ BizFlow

Business operations platform for retailers and small businesses — products, inventory, point of sale,
expenses and reporting in one mobile app. A product of **STANZ DIGITAL CONNECT**.

| Part | Stack | Folder |
|------|-------|--------|
| Mobile app (Android, iOS) | Flutter 3.47, Riverpod 3, GoRouter 18, Dio | [`mobile/`](mobile) |
| API | Python 3.13, FastAPI, SQLAlchemy 2, Alembic, Pydantic 2 | [`backend/`](backend) |
| Database | PostgreSQL 17 (SQLite is used only by the fast local test run) | — |

## Quick start

### API

```bash
cd backend
python -m venv .venv
.venv/Scripts/pip install -r requirements-dev.txt     # Windows (use .venv/bin on macOS/Linux)
cp .env.example .env                                   # then set DATABASE_URL and JWT_SECRET
.venv/Scripts/alembic upgrade head
.venv/Scripts/uvicorn app.main:app --reload
```

Interactive API docs: http://localhost:8000/docs (disabled when `APP_ENV=production`).

With Docker installed, `docker compose up` starts PostgreSQL and the API together and runs the migrations.

### Mobile app

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1   # Android emulator → local API
```

Release builds must point `API_BASE_URL` at an **HTTPS** endpoint. Plain HTTP is allowed only in debug builds.

### Tests

```bash
cd backend && .venv/Scripts/python -m pytest -q        # 65 tests (SQLite)
TEST_DATABASE_URL=postgresql+psycopg://…/bizflow_test pytest -q   # same suite + concurrency test on PostgreSQL
cd mobile && flutter analyze && flutter test            # 36 tests
```

CI (`.github/workflows/ci.yml`) runs lint, both backend test modes, a dependency audit, and the Flutter analyze and test steps.

## Documentation

- [Implementation plan & status](docs/IMPLEMENTATION_PLAN.md): what is done, what is next, and known limitations
- [Architecture](docs/ARCHITECTURE.md): modules, tenancy, permissions, design system
- [Reporting definitions](docs/REPORTING.md): exactly how every dashboard figure is calculated
- [Offline & sync policy](docs/OFFLINE_SYNC.md)
- [Security](docs/SECURITY.md)
- [Deployment, backup & recovery](docs/DEPLOYMENT.md)
