import uuid
from datetime import UTC, datetime, timedelta

from tests.conftest import join_business


def test_free_plan_limits_enforced_on_server(make_user, session_factory):
    owner = make_user()
    bid = owner.create_business()
    sub = owner.get(f"/businesses/{bid}/subscription").json()
    assert sub["plan"]["code"] == "free"
    limit = sub["plan"]["max_products"]

    from app.models import Product

    with session_factory() as db:
        for i in range(limit):
            db.add(Product(business_id=uuid.UUID(bid), name=f"P{i}", selling_price=1))
        db.commit()
    res = owner.post(f"/businesses/{bid}/products", json={"name": "One too many", "selling_price": "1"})
    assert res.status_code == 402 and res.json()["error"]["code"] == "plan_limit"


def test_team_requires_paid_plan_and_trial_unlocks_it(make_user):
    owner, staff = make_user(), make_user()
    bid = owner.create_business()
    res = owner.post(f"/businesses/{bid}/invitations", json={"email": staff.email, "role": "cashier"})
    assert res.status_code == 402 and res.json()["error"]["code"] == "feature_not_in_plan"

    trial = owner.post(f"/businesses/{bid}/subscription/trial", json={"plan_code": "starter"})
    assert trial.status_code == 200 and trial.json()["status"] == "trialing"
    join_business(owner, staff, bid, "cashier")
    # Trials are once per business.
    assert owner.post(f"/businesses/{bid}/subscription/trial", json={"plan_code": "professional"}).status_code == 400


def test_checkout_does_not_grant_plan(make_user):
    owner = make_user()
    bid = owner.create_business()
    res = owner.post(f"/businesses/{bid}/subscription/checkout", json={"plan_code": "professional"})
    assert res.json()["error"]["code"] == "billing_not_configured"
    assert owner.get(f"/businesses/{bid}/subscription").json()["plan"]["code"] == "free"


def test_plans_are_public_and_have_no_hardcoded_prices(client):
    plans = client.get("/api/v1/plans").json()
    assert [p["code"] for p in plans] == ["free", "starter", "professional"]
    assert all("price" not in p for p in plans)


def _offline_sale(product_id: str, qty: str = "1", ref: str | None = None, when: datetime | None = None, **extra):
    return {
        "client_reference": ref or uuid.uuid4().hex,
        "items": [{"product_id": product_id, "quantity": qty}],
        "payments": [{"method": "cash", "amount": "10000000"}],
        "client_created_at": (when or datetime.now(UTC) - timedelta(hours=2)).isoformat(),
    } | extra


def test_sync_accepts_dedupes_and_rejects_individually(make_user):
    owner = make_user()
    bid = owner.create_business()
    last = owner.create_product(bid, name="Last phone", price="300000", stock="1")
    case = owner.create_product(bid, name="Case", price="10000", stock="10")
    a = _offline_sale(case["id"])
    when = datetime.now(UTC) - timedelta(hours=5)
    batch = {
        "device_id": "device-1234",
        "sales": [
            a,
            _offline_sale(last["id"], when=when),
            _offline_sale(last["id"]),  # second device sold the same last unit
        ],
    }
    res = owner.post(f"/businesses/{bid}/sync/sales", json=batch).json()["results"]
    assert [r["status"] for r in res] == ["accepted", "accepted", "rejected"]
    assert res[2]["error"]["code"] == "insufficient_stock"

    # Retrying after a timeout must not duplicate anything.
    retry = owner.post(f"/businesses/{bid}/sync/sales", json={"device_id": "device-1234", "sales": [a]}).json()
    assert retry["results"][0]["status"] == "duplicate"
    assert retry["results"][0]["receipt_number"] == res[0]["receipt_number"]
    assert owner.get(f"/businesses/{bid}/sales").json()["total"] == 2

    # The device's time is kept when plausible.
    sale = owner.get(f"/businesses/{bid}/sales/{res[1]['sale_id']}").json()
    assert sale["source"] == "offline"
    assert abs(datetime.fromisoformat(sale["created_at"]) - when) < timedelta(seconds=1)


def test_sync_rejects_implausible_device_clock(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid, price="1000", stock="10")
    future = datetime.now(UTC) + timedelta(days=3)
    res = owner.post(
        f"/businesses/{bid}/sync/sales", json={"device_id": "device-1", "sales": [_offline_sale(p["id"], when=future)]}
    ).json()
    sale = owner.get(f"/businesses/{bid}/sales/{res['results'][0]['sale_id']}").json()
    assert datetime.fromisoformat(sale["created_at"]) < datetime.now(UTC) + timedelta(minutes=1)


def test_sync_after_membership_revoked_is_refused(make_user, pro_plan):
    owner, cashier = make_user(), make_user()
    bid = owner.create_business()
    pro_plan(bid)
    join_business(owner, cashier, bid, "cashier")
    p = owner.create_product(bid, price="1000", stock="10")
    members = {m["email"]: m for m in owner.get(f"/businesses/{bid}/members").json()}
    owner.delete(f"/businesses/{bid}/members/{members[cashier.email]['membership_id']}")
    res = cashier.post(f"/businesses/{bid}/sync/sales", json={"device_id": "dev-1", "sales": [_offline_sale(p["id"])]})
    assert res.status_code == 404
    assert owner.get(f"/businesses/{bid}/products/{p['id']}").json()["quantity_on_hand"] == "10"


def test_health_endpoints(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").json() == {"status": "ready"}


def test_error_responses_hide_internals(client):
    res = client.get("/api/v1/nope")
    assert res.status_code == 404
    assert set(res.json()) == {"error"}
