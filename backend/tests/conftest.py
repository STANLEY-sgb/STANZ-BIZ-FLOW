"""Test fixtures.

By default tests run against an isolated SQLite database for speed. Set
TEST_DATABASE_URL to a *disposable* PostgreSQL database to run the same suite
(plus the PostgreSQL-only concurrency tests) against the production engine:

    TEST_DATABASE_URL=postgresql+psycopg://bizflow:bizflow@localhost:5432/bizflow_test pytest

Never point TEST_DATABASE_URL at a database containing real business records:
every table is dropped and recreated.
"""

import os
import uuid

os.environ.setdefault("JWT_SECRET", "test-secret-" + "x" * 40)
os.environ.setdefault("APP_ENV", "test")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401  (register all tables)
from app.core.database import Base, get_db
from app.core.rate_limit import store as rate_limit_store
from app.main import app

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")
IS_POSTGRES = bool(TEST_DATABASE_URL and TEST_DATABASE_URL.startswith("postgresql"))


@pytest.fixture
def engine():
    if TEST_DATABASE_URL:
        eng = create_engine(TEST_DATABASE_URL, pool_size=20)
    else:
        eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.drop_all(eng)
    Base.metadata.create_all(eng)
    yield eng
    Base.metadata.drop_all(eng)
    eng.dispose()


@pytest.fixture
def session_factory(engine):
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


@pytest.fixture
def client(session_factory):
    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    rate_limit_store.reset()
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


# --- Helpers ---------------------------------------------------------------------------------


class Api:
    """Small helper around the test client representing one signed-in user."""

    def __init__(self, client: TestClient, email: str, name: str = "Test User"):
        self.client = client
        self.email = email
        res = client.post("/api/v1/auth/register", json={"full_name": name, "email": email, "password": "Secret123!"})
        assert res.status_code == 201, res.text
        self.tokens = res.json()
        self.user_id = self.tokens["user"]["id"]

    @property
    def headers(self) -> dict:
        return {"Authorization": f"Bearer {self.tokens['access_token']}"}

    def get(self, path: str, **kw):
        return self.client.get(f"/api/v1{path}", headers=self.headers, **kw)

    def post(self, path: str, json=None, **kw):
        return self.client.post(f"/api/v1{path}", json=json, headers=self.headers, **kw)

    def patch(self, path: str, json=None, **kw):
        return self.client.patch(f"/api/v1{path}", json=json, headers=self.headers, **kw)

    def delete(self, path: str, **kw):
        return self.client.delete(f"/api/v1{path}", headers=self.headers, **kw)

    def create_business(self, name: str = "Kampala Phones", **extra) -> str:
        body = {"name": name, "category": "electronics", "payment_methods": ["cash", "mobile_money"]} | extra
        res = self.post("/businesses", json=body)
        assert res.status_code == 201, res.text
        return res.json()["id"]

    def create_product(
        self, bid: str, name: str = "Samsung Galaxy A15", price="650000", cost="520000", stock="5", **extra
    ) -> dict:
        body = {"name": name, "selling_price": price, "cost_price": cost, "opening_stock": stock} | extra
        res = self.post(f"/businesses/{bid}/products", json=body)
        assert res.status_code == 201, res.text
        return res.json()

    def sell(
        self,
        bid: str,
        items: list[tuple[str, str]],
        pay: str | None = None,
        method: str = "cash",
        ref: str | None = None,
        **extra,
    ):
        body = {
            "client_reference": ref or uuid.uuid4().hex,
            "items": [{"product_id": pid, "quantity": q} for pid, q in items],
            "payments": [{"method": method, "amount": pay or "100000000"}],
        } | extra
        return self.post(f"/businesses/{bid}/sales", json=body)


def join_business(owner: Api, member: Api, bid: str, role: str) -> None:
    """Invite and accept, upgrading the plan first so team members are allowed."""
    inv = owner.post(f"/businesses/{bid}/invitations", json={"email": member.email, "role": role})
    assert inv.status_code == 201, inv.text
    res = member.post("/invitations/accept", json={"token": inv.json()["accept_token"]})
    assert res.status_code == 200, res.text


@pytest.fixture
def make_user(client):
    counter = {"n": 0}

    def factory(name: str = "Test User") -> Api:
        counter["n"] += 1
        return Api(client, f"user{counter['n']}_{uuid.uuid4().hex[:6]}@example.com", name)

    return factory


@pytest.fixture
def pro_plan(session_factory):
    """Put a business on the Professional plan directly (simulating a verified provider webhook)."""
    from datetime import timedelta

    from app.core.database import utcnow
    from app.modules.subscriptions import activate_paid_plan

    def apply(bid: str) -> None:
        with session_factory() as db:
            activate_paid_plan(db, uuid.UUID(bid), "professional", utcnow() + timedelta(days=30), "test", "ref")
            db.commit()

    return apply
