import threading
import uuid

import pytest

from tests.conftest import IS_POSTGRES


@pytest.fixture
def shop(make_user):
    owner = make_user("Owner")
    bid = owner.create_business(tax_rate_percent="18")
    phone = owner.create_product(owner_bid := bid, name="Tecno Spark 20", price="450000", cost="380000", stock="3")
    case = owner.create_product(owner_bid, name="Phone case", price="15000", cost="5000", stock="50")
    return owner, bid, phone, case


def test_sale_totals_change_and_stock(shop):
    owner, bid, phone, case = shop
    res = owner.sell(bid, [(phone["id"], "1"), (case["id"], "2")], pay="500000")
    assert res.status_code == 201, res.text
    sale = res.json()
    assert sale["subtotal"] == "480000.00"
    assert sale["total"] == "480000.00"
    assert sale["change_due"] == "20000.00"
    # 18% tax extracted from a tax-inclusive total: 480000 * 18 / 118
    assert sale["tax_total"] == "73220.34"
    assert sale["receipt_number"] == "R-000001"
    # The recorded cash payment is net of change.
    assert sale["payments"] == [
        {
            "kind": "payment",
            "method": "cash",
            "amount": "480000.00",
            "reference": None,
            "created_at": sale["payments"][0]["created_at"],
        }
    ]
    assert owner.get(f"/businesses/{bid}/products/{phone['id']}").json()["quantity_on_hand"] == "2"
    assert owner.get(f"/businesses/{bid}/products/{case['id']}").json()["quantity_on_hand"] == "48"
    moves = owner.get(f"/businesses/{bid}/stock-movements", params={"product_id": phone["id"]}).json()["items"]
    assert [m["reason"] for m in moves] == ["sale", "opening"]


def test_client_totals_and_prices_are_ignored(shop):
    owner, bid, phone, _ = shop
    body = {
        "client_reference": uuid.uuid4().hex,
        "items": [{"product_id": phone["id"], "quantity": "1"}],
        "payments": [{"method": "cash", "amount": "450000"}],
        "total": "1",
        "unit_price": "1",  # unknown fields are ignored; server prices apply
    }
    sale = owner.post(f"/businesses/{bid}/sales", json=body).json()
    assert sale["total"] == "450000.00"


def test_price_change_detected(shop):
    owner, bid, phone, _ = shop
    owner.patch(f"/businesses/{bid}/products/{phone['id']}", json={"selling_price": "470000"})
    body = {
        "client_reference": uuid.uuid4().hex,
        "items": [{"product_id": phone["id"], "quantity": "1", "expected_unit_price": "450000"}],
        "payments": [{"method": "cash", "amount": "500000"}],
    }
    res = owner.post(f"/businesses/{bid}/sales", json=body)
    assert res.status_code == 409 and res.json()["error"]["code"] == "price_changed"


def test_price_edit_does_not_rewrite_history(shop):
    owner, bid, phone, _ = shop
    sale = owner.sell(bid, [(phone["id"], "1")]).json()
    owner.patch(f"/businesses/{bid}/products/{phone['id']}", json={"selling_price": "999999", "name": "Renamed"})
    again = owner.get(f"/businesses/{bid}/sales/{sale['id']}").json()
    assert again["items"][0]["unit_price"] == "450000.00"
    assert again["items"][0]["product_name"] == "Tecno Spark 20"


def test_idempotent_retry_returns_same_sale(shop):
    owner, bid, phone, _ = shop
    ref = uuid.uuid4().hex
    first = owner.sell(bid, [(phone["id"], "1")], ref=ref)
    second = owner.sell(bid, [(phone["id"], "1")], ref=ref)
    assert first.status_code == 201 and second.status_code == 200
    assert second.headers["Idempotent-Replay"] == "true"
    assert first.json()["id"] == second.json()["id"]
    assert owner.get(f"/businesses/{bid}/sales").json()["total"] == 1
    assert owner.get(f"/businesses/{bid}/products/{phone['id']}").json()["quantity_on_hand"] == "2"


def test_insufficient_stock_rejected_atomically(shop):
    owner, bid, phone, case = shop
    res = owner.sell(bid, [(case["id"], "1"), (phone["id"], "4")])
    assert res.status_code == 409 and res.json()["error"]["code"] == "insufficient_stock"
    # Nothing from the failed sale persisted, including the first line.
    assert owner.get(f"/businesses/{bid}/products/{case['id']}").json()["quantity_on_hand"] == "50"
    assert owner.get(f"/businesses/{bid}/sales").json()["total"] == 0
    # Receipt numbering is not consumed by failures.
    assert owner.sell(bid, [(case["id"], "1")]).json()["receipt_number"] == "R-000001"


def test_same_product_on_two_lines_counts_cumulatively(shop):
    owner, bid, phone, _ = shop
    res = owner.sell(bid, [(phone["id"], "2"), (phone["id"], "2")])
    assert res.status_code == 409


def test_stock_not_enforced_when_disabled(shop):
    owner, bid, phone, _ = shop
    owner.patch(f"/businesses/{bid}", json={"enforce_stock": False})
    assert owner.sell(bid, [(phone["id"], "5")]).status_code == 201
    assert owner.get(f"/businesses/{bid}/products/{phone['id']}").json()["quantity_on_hand"] == "-2"


def test_payment_validation(shop):
    owner, bid, phone, _ = shop
    short = owner.sell(bid, [(phone["id"], "1")], pay="100")
    assert short.status_code == 400 and short.json()["error"]["code"] == "insufficient_payment"
    over = owner.sell(bid, [(phone["id"], "1")], pay="500000", method="mobile_money")
    assert over.status_code == 400 and over.json()["error"]["code"] == "overpayment"
    disabled = owner.sell(bid, [(phone["id"], "1")], pay="450000", method="card")
    assert disabled.status_code == 400 and disabled.json()["error"]["code"] == "payment_method_disabled"


def test_discounts_by_owner(shop):
    owner, bid, phone, case = shop
    body = {
        "client_reference": uuid.uuid4().hex,
        "items": [
            {"product_id": phone["id"], "quantity": "1", "discount": "10000"},
            {"product_id": case["id"], "quantity": "1"},
        ],
        "order_discount": "5000",
        "payments": [{"method": "mobile_money", "amount": "450000", "reference": "MM123"}],
    }
    sale = owner.post(f"/businesses/{bid}/sales", json=body).json()
    assert sale["subtotal"] == "465000.00"
    assert sale["discount_total"] == "15000.00"
    assert sale["total"] == "450000.00"
    too_big = body | {"client_reference": uuid.uuid4().hex, "order_discount": "999999"}
    assert owner.post(f"/businesses/{bid}/sales", json=too_big).status_code == 400


def test_receipt_numbers_are_sequential_and_receipt_renders(shop):
    owner, bid, _, case = shop
    numbers = [owner.sell(bid, [(case["id"], "1")]).json()["receipt_number"] for _ in range(3)]
    assert numbers == ["R-000001", "R-000002", "R-000003"]
    sale_id = owner.get(f"/businesses/{bid}/sales").json()["items"][0]["id"]
    receipt = owner.get(f"/businesses/{bid}/sales/{sale_id}/receipt").json()
    assert receipt["business_name"] == "Kampala Phones"
    assert receipt["currency"] == "UGX"
    assert receipt["lines"][0]["name"] == "Phone case"


def test_partial_then_full_return(shop):
    owner, bid, phone, case = shop
    sale = owner.sell(bid, [(case["id"], "4")], order_discount="4000").json()  # 60000 - 4000 = 56000
    item_id = sale["items"][0]["id"]

    def ret(q, restock=True):
        return owner.post(
            f"/businesses/{bid}/sales/{sale['id']}/returns",
            json={
                "client_reference": uuid.uuid4().hex,
                "lines": [{"sale_item_id": item_id, "quantity": q}],
                "reason": "Faulty",
                "restock": restock,
            },
        )

    first = ret("1")
    assert first.status_code == 201
    assert first.json()["amount"] == "14000.00"  # pro-rata share of the discounted total
    assert owner.get(f"/businesses/{bid}/sales/{sale['id']}").json()["status"] == "partially_refunded"
    assert ret("4").status_code == 400  # only 3 left to return
    assert ret("3", restock=False).json()["amount"] == "42000.00"
    final = owner.get(f"/businesses/{bid}/sales/{sale['id']}").json()
    assert final["status"] == "refunded" and final["refunded_total"] == "56000.00"
    # Only the restocked unit went back on the shelf.
    assert owner.get(f"/businesses/{bid}/products/{case['id']}").json()["quantity_on_hand"] == "47"


def test_return_is_idempotent(shop):
    owner, bid, _, case = shop
    sale = owner.sell(bid, [(case["id"], "2")]).json()
    body = {
        "client_reference": uuid.uuid4().hex,
        "lines": [{"sale_item_id": sale["items"][0]["id"], "quantity": "1"}],
        "reason": "Wrong colour",
    }
    a = owner.post(f"/businesses/{bid}/sales/{sale['id']}/returns", json=body).json()
    b = owner.post(f"/businesses/{bid}/sales/{sale['id']}/returns", json=body).json()
    assert a["id"] == b["id"]
    assert owner.get(f"/businesses/{bid}/sales/{sale['id']}").json()["refunded_total"] == "15000.00"


def test_archived_product_cannot_be_sold(shop):
    owner, bid, phone, _ = shop
    owner.post(f"/businesses/{bid}/products/{phone['id']}/archive")
    res = owner.sell(bid, [(phone["id"], "1")])
    assert res.status_code == 409 and res.json()["error"]["code"] == "product_archived"


@pytest.mark.skipif(not IS_POSTGRES, reason="row locking semantics require PostgreSQL (set TEST_DATABASE_URL)")
def test_concurrent_sales_cannot_oversell(make_user):
    owner = make_user()
    bid = owner.create_business()
    last = owner.create_product(bid, name="Last unit", price="1000", stock="1")
    results: list[int] = []

    def attempt():
        results.append(owner.sell(bid, [(last["id"], "1")]).status_code)

    threads = [threading.Thread(target=attempt) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(results) == [201] + [409] * 7
    assert owner.get(f"/businesses/{bid}/products/{last['id']}").json()["quantity_on_hand"] == "0"
