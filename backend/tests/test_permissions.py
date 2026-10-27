import uuid

from tests.conftest import join_business


def _shop_with(make_user, pro_plan, role: str):
    owner, member = make_user("Owner"), make_user(role)
    bid = owner.create_business()
    pro_plan(bid)
    join_business(owner, member, bid, role)
    product = owner.create_product(bid, attributes={"brand": "Samsung", "imei": "356789012345678"})
    return owner, member, bid, product


def test_cashier_can_sell_but_not_see_confidential_data(make_user, pro_plan):
    owner, cashier, bid, product = _shop_with(make_user, pro_plan, "cashier")

    seen = cashier.get(f"/businesses/{bid}/products/{product['id']}").json()
    assert seen["cost_price"] is None
    assert "imei" not in seen["attributes"] and seen["attributes"]["brand"] == "Samsung"
    assert owner.get(f"/businesses/{bid}/products/{product['id']}").json()["attributes"]["imei"]

    assert cashier.sell(bid, [(product["id"], "1")]).status_code == 201
    for path in ("/reports/summary", "/members", "/expenses", "/audit-events"):
        assert cashier.get(f"/businesses/{bid}{path}").status_code == 403, path
    assert cashier.post(f"/businesses/{bid}/products", json={"name": "x", "selling_price": "1"}).status_code == 403
    assert cashier.patch(f"/businesses/{bid}", json={"name": "x"}).status_code == 403
    assert cashier.post(f"/businesses/{bid}/subscription/trial", json={"plan_code": "starter"}).status_code == 403

    dash = cashier.get(f"/businesses/{bid}/dashboard").json()
    assert dash["scope"] == "own_sales" and dash["current"] is None
    assert dash["inventory"]["valuation_at_cost"] is None


def test_cashier_cannot_discount_or_refund(make_user, pro_plan):
    owner, cashier, bid, product = _shop_with(make_user, pro_plan, "cashier")
    res = cashier.sell(bid, [(product["id"], "1")], order_discount="1000")
    assert res.status_code == 403 and res.json()["error"]["code"] == "discount_not_allowed"
    sale = cashier.sell(bid, [(product["id"], "1")]).json()
    ret = {
        "client_reference": uuid.uuid4().hex,
        "lines": [{"sale_item_id": sale["items"][0]["id"], "quantity": "1"}],
        "reason": "Customer changed mind",
    }
    assert cashier.post(f"/businesses/{bid}/sales/{sale['id']}/returns", json=ret).status_code == 403


def test_cashier_only_sees_own_sales(make_user, pro_plan):
    owner, cashier, bid, product = _shop_with(make_user, pro_plan, "cashier")
    owner_sale = owner.sell(bid, [(product["id"], "1")]).json()
    cashier.sell(bid, [(product["id"], "1")])
    assert cashier.get(f"/businesses/{bid}/sales").json()["total"] == 1
    assert cashier.get(f"/businesses/{bid}/sales/{owner_sale['id']}").status_code == 404
    assert owner.get(f"/businesses/{bid}/sales").json()["total"] == 2


def test_cashier_cannot_replay_someone_elses_reference(make_user, pro_plan):
    owner, cashier, bid, product = _shop_with(make_user, pro_plan, "cashier")
    ref = uuid.uuid4().hex
    assert owner.sell(bid, [(product["id"], "1")], ref=ref).status_code == 201
    res = cashier.sell(bid, [(product["id"], "1")], ref=ref)
    assert res.status_code == 409


def test_inventory_manager_scope(make_user, pro_plan):
    owner, inv, bid, product = _shop_with(make_user, pro_plan, "inventory_manager")
    adj = {"type": "receipt", "quantity": "3", "unit_cost": "500000"}
    assert inv.post(f"/businesses/{bid}/products/{product['id']}/stock-movements", json=adj).status_code == 201
    assert inv.sell(bid, [(product["id"], "1")]).status_code == 403
    assert inv.get(f"/businesses/{bid}/reports/summary").status_code == 403


def test_last_owner_cannot_be_removed_or_demoted(make_user):
    owner = make_user()
    bid = owner.create_business()
    me = owner.get(f"/businesses/{bid}/members").json()[0]
    res = owner.patch(f"/businesses/{bid}/members/{me['membership_id']}", json={"role": "manager"})
    assert res.status_code == 409 and res.json()["error"]["code"] == "last_owner"
    assert owner.delete(f"/businesses/{bid}/members/{me['membership_id']}").status_code == 409


def test_admin_cannot_grant_owner_or_remove_owner(make_user, pro_plan):
    owner, admin, bid, _ = _shop_with(make_user, pro_plan, "admin")
    members = {m["email"]: m for m in owner.get(f"/businesses/{bid}/members").json()}
    target = make_user("New")
    assert (
        admin.post(f"/businesses/{bid}/invitations", json={"email": target.email, "role": "owner"}).status_code == 403
    )
    owner_mid = members[owner.email]["membership_id"]
    assert admin.delete(f"/businesses/{bid}/members/{owner_mid}").status_code == 403
    # Admins can still manage ordinary staff.
    assert (
        admin.post(f"/businesses/{bid}/invitations", json={"email": target.email, "role": "cashier"}).status_code == 201
    )


def test_removed_member_loses_access_immediately(make_user, pro_plan):
    owner, cashier, bid, product = _shop_with(make_user, pro_plan, "cashier")
    members = {m["email"]: m for m in owner.get(f"/businesses/{bid}/members").json()}
    assert owner.delete(f"/businesses/{bid}/members/{members[cashier.email]['membership_id']}").status_code == 204
    assert cashier.get(f"/businesses/{bid}/products").status_code == 404
    assert cashier.sell(bid, [(product["id"], "1")]).status_code == 404


def test_invitation_requires_matching_email(make_user, pro_plan):
    owner, stranger = make_user(), make_user()
    bid = owner.create_business()
    pro_plan(bid)
    inv = owner.post(f"/businesses/{bid}/invitations", json={"email": "someone@example.com", "role": "cashier"})
    res = stranger.post("/invitations/accept", json={"token": inv.json()["accept_token"]})
    assert res.status_code == 403


def test_permission_changes_are_audited(make_user, pro_plan):
    owner, cashier, bid, _ = _shop_with(make_user, pro_plan, "cashier")
    members = {m["email"]: m for m in owner.get(f"/businesses/{bid}/members").json()}
    owner.patch(f"/businesses/{bid}/members/{members[cashier.email]['membership_id']}", json={"role": "manager"})
    actions = [e["action"] for e in owner.get(f"/businesses/{bid}/audit-events").json()["items"]]
    assert "member.role_changed" in actions and "invitation.accepted" in actions
