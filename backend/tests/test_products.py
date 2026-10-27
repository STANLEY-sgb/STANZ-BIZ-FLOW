def test_product_crud_search_and_filters(make_user):
    owner = make_user()
    bid = owner.create_business()
    phones = next(c for c in owner.get(f"/businesses/{bid}/categories").json() if c["name"] == "Phones")
    a = owner.create_product(
        bid,
        name="Samsung Galaxy A15",
        sku="SGA15-128",
        barcode="8806095",
        category_id=phones["id"],
        reorder_level="2",
        stock="2",
        attributes={"brand": "Samsung", "storage": "128GB"},
    )
    owner.create_product(bid, name="iPhone 13", stock="0")
    owner.create_product(bid, name="Charger", stock="20", reorder_level="5")

    assert a["stock_status"] == "low_stock"
    q = owner.get(f"/businesses/{bid}/products", params={"q": "galaxy"}).json()
    assert [p["name"] for p in q["items"]] == ["Samsung Galaxy A15"]
    assert owner.get(f"/businesses/{bid}/products", params={"q": "sga15"}).json()["total"] == 1
    assert (
        owner.get(f"/businesses/{bid}/products", params={"stock": "out_of_stock"}).json()["items"][0]["name"]
        == "iPhone 13"
    )
    assert owner.get(f"/businesses/{bid}/products", params={"stock": "low_stock"}).json()["total"] == 1
    assert owner.get(f"/businesses/{bid}/products", params={"category_id": phones["id"]}).json()["total"] == 1
    assert owner.get(f"/businesses/{bid}/products/lookup", params={"code": "8806095"}).json()["id"] == a["id"]

    page = owner.get(f"/businesses/{bid}/products", params={"limit": 2}).json()
    assert page["total"] == 3 and len(page["items"]) == 2


def test_duplicate_sku_and_barcode_rejected(make_user):
    owner = make_user()
    bid = owner.create_business()
    owner.create_product(bid, name="A", sku="X1", barcode="111")
    r1 = owner.post(f"/businesses/{bid}/products", json={"name": "B", "selling_price": "1", "sku": "X1"})
    r2 = owner.post(f"/businesses/{bid}/products", json={"name": "B", "selling_price": "1", "barcode": "111"})
    assert r1.json()["error"]["code"] == "duplicate_sku"
    assert r2.json()["error"]["code"] == "duplicate_barcode"


def test_optimistic_concurrency(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid)
    ok = owner.patch(f"/businesses/{bid}/products/{p['id']}", json={"name": "New", "version": p["version"]})
    assert ok.status_code == 200
    stale = owner.patch(f"/businesses/{bid}/products/{p['id']}", json={"name": "Stale", "version": p["version"]})
    assert stale.status_code == 409 and stale.json()["error"]["code"] == "version_conflict"


def test_product_edit_cannot_change_stock_directly(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid, stock="5")
    owner.patch(f"/businesses/{bid}/products/{p['id']}", json={"quantity_on_hand": "999"})
    assert owner.get(f"/businesses/{bid}/products/{p['id']}").json()["quantity_on_hand"] == "5"


def test_stock_adjustments(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid, cost="100", stock="10")
    url = f"/businesses/{bid}/products/{p['id']}/stock-movements"

    r = owner.post(url, json={"type": "receipt", "quantity": "10", "unit_cost": "200"})
    assert r.status_code == 201 and r.json()["quantity_after"] == "20"
    # Weighted average cost: (10*100 + 10*200) / 20 = 150
    assert owner.get(f"/businesses/{bid}/products/{p['id']}").json()["cost_price"] == "150.00"

    assert owner.post(url, json={"type": "damage", "quantity": "2"}).status_code == 422  # note required
    assert owner.post(url, json={"type": "damage", "quantity": "2", "note": "Dropped"}).json()["quantity_after"] == "18"
    assert owner.post(url, json={"type": "damage", "quantity": "50", "note": "x"}).status_code == 409
    count = owner.post(url, json={"type": "count", "counted_quantity": "15", "note": "Monthly count"}).json()
    assert count["quantity_change"] == "-3" and count["quantity_after"] == "15"
    assert (
        owner.post(url, json={"type": "adjustment", "quantity": "-1.5", "note": "Split pack"}).json()["quantity_after"]
        == "13.5"
    )

    moves = owner.get(f"/businesses/{bid}/stock-movements", params={"product_id": p["id"]}).json()["items"]
    assert sum(float(m["quantity_change"]) for m in moves) == 13.5


def test_archive_and_restore(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid)
    owner.post(f"/businesses/{bid}/products/{p['id']}/archive")
    assert owner.get(f"/businesses/{bid}/products").json()["total"] == 0
    assert owner.get(f"/businesses/{bid}/products", params={"include_archived": True}).json()["total"] == 1
    owner.post(f"/businesses/{bid}/products/{p['id']}/restore")
    assert owner.get(f"/businesses/{bid}/products").json()["total"] == 1


def test_money_is_exact(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid, price="0.10", stock="100")
    sale = owner.sell(bid, [(p["id"], "3")], pay="0.30").json()
    assert sale["total"] == "0.30" and sale["change_due"] == "0.00"
