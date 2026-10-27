"""Business A must never see or touch Business B's data, whatever IDs are supplied."""

import uuid


def _two_tenants(make_user):
    alice, bob = make_user("Alice"), make_user("Bob")
    a = alice.create_business("Alice Electronics")
    b = bob.create_business("Bob Fashion", category="fashion")
    a_product = alice.create_product(a)
    b_product = bob.create_product(b, name="Denim jacket", price="85000", cost="40000")
    return alice, bob, a, b, a_product, b_product


def test_cannot_read_other_business(make_user):
    alice, bob, a, b, a_product, _ = _two_tenants(make_user)
    sale = alice.sell(a, [(a_product["id"], "1")]).json()
    alice.post(f"/businesses/{a}/expenses", json={"category": "rent", "amount": "500000", "expense_date": "2026-10-01"})

    for path in (
        f"/businesses/{a}",
        f"/businesses/{a}/products",
        f"/businesses/{a}/products/{a_product['id']}",
        f"/businesses/{a}/sales",
        f"/businesses/{a}/sales/{sale['id']}",
        f"/businesses/{a}/sales/{sale['id']}/receipt",
        f"/businesses/{a}/expenses",
        f"/businesses/{a}/dashboard",
        f"/businesses/{a}/reports/summary",
        f"/businesses/{a}/reports/sales-by-product.csv",
        f"/businesses/{a}/members",
        f"/businesses/{a}/stock-movements",
        f"/businesses/{a}/customers",
        f"/businesses/{a}/audit-events",
        f"/businesses/{a}/subscription",
    ):
        res = bob.get(path)
        assert res.status_code == 404, (path, res.status_code)


def test_ids_from_other_tenant_are_not_found_within_own_tenant(make_user):
    alice, bob, a, b, a_product, _ = _two_tenants(make_user)
    sale = alice.sell(a, [(a_product["id"], "1")]).json()
    # Bob addresses Alice's objects through his own business path.
    assert bob.get(f"/businesses/{b}/products/{a_product['id']}").status_code == 404
    assert bob.get(f"/businesses/{b}/sales/{sale['id']}").status_code == 404
    assert bob.patch(f"/businesses/{b}/products/{a_product['id']}", json={"selling_price": "1"}).status_code == 404
    assert bob.post(f"/businesses/{b}/products/{a_product['id']}/archive").status_code == 404
    adj = {"type": "receipt", "quantity": "10"}
    assert bob.post(f"/businesses/{b}/products/{a_product['id']}/stock-movements", json=adj).status_code == 404
    ret = {
        "client_reference": uuid.uuid4().hex,
        "lines": [{"sale_item_id": sale["items"][0]["id"], "quantity": "1"}],
        "reason": "test",
    }
    assert bob.post(f"/businesses/{b}/sales/{sale['id']}/returns", json=ret).status_code == 404


def test_cannot_sell_other_tenants_product(make_user):
    alice, bob, a, b, a_product, _ = _two_tenants(make_user)
    res = bob.sell(b, [(a_product["id"], "1")])
    assert res.status_code == 404
    # Alice's stock is untouched.
    assert alice.get(f"/businesses/{a}/products/{a_product['id']}").json()["quantity_on_hand"] == "5"


def test_cannot_write_into_other_business(make_user):
    alice, bob, a, b, _, _ = _two_tenants(make_user)
    assert bob.post(f"/businesses/{a}/products", json={"name": "x", "selling_price": "1"}).status_code == 404
    assert bob.patch(f"/businesses/{a}", json={"name": "Hacked"}).status_code == 404
    assert bob.post(f"/businesses/{a}/invitations", json={"email": bob.email, "role": "owner"}).status_code == 404
    assert alice.get(f"/businesses/{a}").json()["name"] == "Alice Electronics"


def test_cross_tenant_category_and_customer_rejected(make_user):
    alice, bob, a, b, _, _ = _two_tenants(make_user)
    a_category = alice.get(f"/businesses/{a}/categories").json()[0]["id"]
    res = bob.post(f"/businesses/{b}/products", json={"name": "x", "selling_price": "1", "category_id": a_category})
    assert res.status_code == 400
    a_customer = alice.post(f"/businesses/{a}/customers", json={"name": "Kato"}).json()["id"]
    b_product = bob.get(f"/businesses/{b}/products").json()["items"][0]["id"]
    res = bob.sell(b, [(b_product, "1")], customer_id=a_customer)
    assert res.status_code == 400
    assert res.json()["error"]["code"] == "customer_not_found"


def test_same_sku_allowed_in_different_businesses(make_user):
    alice, bob, a, b, _, _ = _two_tenants(make_user)
    alice.create_product(a, name="Cable", sku="USB-C-1", price="10000")
    bob.create_product(b, name="Cable", sku="USB-C-1", price="12000")


def test_bob_search_never_returns_alice_products(make_user):
    alice, bob, a, b, _, _ = _two_tenants(make_user)
    res = bob.get(f"/businesses/{b}/products", params={"q": "samsung"})
    assert res.json()["total"] == 0


def test_unknown_business_id_is_404(make_user):
    alice = make_user()
    assert alice.get(f"/businesses/{uuid.uuid4()}").status_code == 404
