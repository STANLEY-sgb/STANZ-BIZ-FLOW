import uuid
from datetime import date


def test_summary_matches_records(make_user):
    owner = make_user()
    bid = owner.create_business()
    phone = owner.create_product(bid, name="Phone", price="500000", cost="400000", stock="10")
    gift = owner.create_product(bid, name="Free sticker", price="1000", cost="0", stock="10")

    owner.sell(bid, [(phone["id"], "2")], order_discount="20000")  # 1,000,000 - 20,000
    sale = owner.sell(bid, [(phone["id"], "1")]).json()  # 500,000
    owner.post(
        f"/businesses/{bid}/sales/{sale['id']}/returns",
        json={
            "client_reference": uuid.uuid4().hex,
            "lines": [{"sale_item_id": sale["items"][0]["id"], "quantity": "1"}],
            "reason": "Defective",
            "restock": True,
        },
    )
    today = date.today().isoformat()
    owner.post(f"/businesses/{bid}/expenses", json={"category": "rent", "amount": "300000", "expense_date": today})

    s = owner.get(f"/businesses/{bid}/reports/summary").json()
    assert s["sales_count"] == 2
    assert s["gross_sales"] == "1500000.00"
    assert s["discounts"] == "20000.00"
    assert s["refunds"] == "500000.00"
    assert s["net_sales"] == "980000.00"
    assert s["cogs"] == "800000.00"  # 3 sold at 400k, 1 restocked
    assert s["gross_profit"] == "180000.00"
    assert s["expenses"] == "300000.00"
    assert s["net_profit"] == "-120000.00"
    assert s["cost_data_complete"] is True

    owner.sell(bid, [(gift["id"], "1")])
    assert owner.get(f"/businesses/{bid}/reports/summary").json()["cost_data_complete"] is False


def test_breakdowns_and_dashboard(make_user):
    owner = make_user()
    bid = owner.create_business()
    phones = next(c for c in owner.get(f"/businesses/{bid}/categories").json() if c["name"] == "Phones")
    phone = owner.create_product(
        bid, name="Phone", price="500000", cost="400000", stock="10", category_id=phones["id"], reorder_level="9"
    )
    case = owner.create_product(bid, name="Case", price="10000", cost="3000", stock="100")
    owner.sell(bid, [(phone["id"], "1"), (case["id"], "3")])
    owner.sell(bid, [(case["id"], "1")], method="mobile_money", pay="10000")

    by_product = owner.get(f"/businesses/{bid}/reports/sales-by-product").json()
    assert by_product[0]["name"] == "Phone" and by_product[0]["gross_profit"] == "100000.00"
    assert by_product[1]["quantity"] == "4"
    by_cat = {r["label"]: r["amount"] for r in owner.get(f"/businesses/{bid}/reports/sales-by-category").json()}
    assert by_cat == {"Phones": "500000.00", "Uncategorised": "40000.00"}
    pm = {r["label"]: r["amount"] for r in owner.get(f"/businesses/{bid}/reports/payment-methods").json()}
    assert pm == {"cash": "530000.00", "mobile_money": "10000.00"}
    days = owner.get(f"/businesses/{bid}/reports/sales-by-day").json()
    assert sum(d["sales_count"] for d in days) == 2

    dash = owner.get(f"/businesses/{bid}/dashboard").json()
    assert dash["scope"] == "business"
    assert dash["current"]["net_sales"] == "540000.00"
    assert dash["previous"]["sales_count"] == 0
    assert dash["inventory"]["low_stock"] == 1
    assert dash["low_stock"][0]["name"] == "Phone"
    assert len(dash["recent_sales"]) == 2
    assert dash["my_sales_today"]["count"] == 2


def test_empty_business_reports_zero_not_fabricated(make_user):
    owner = make_user()
    bid = owner.create_business()
    s = owner.get(f"/businesses/{bid}/reports/summary").json()
    assert s["sales_count"] == 0 and s["net_sales"] == "0.00" and s["average_sale"] == "0.00"


def test_invalid_range(make_user):
    owner = make_user()
    bid = owner.create_business()
    r = owner.get(f"/businesses/{bid}/reports/summary", params={"date_from": "2026-05-02", "date_to": "2026-05-01"})
    assert r.status_code == 400
    r = owner.get(f"/businesses/{bid}/reports/summary", params={"date_from": "2020-01-01", "date_to": "2026-05-01"})
    assert r.json()["error"]["code"] == "range_too_large"


def test_expenses_crud_and_soft_delete(make_user):
    owner = make_user()
    bid = owner.create_business()
    e = owner.post(
        f"/businesses/{bid}/expenses",
        json={"category": "transport", "amount": "15000", "expense_date": "2026-10-02", "description": "Boda"},
    ).json()
    assert e["currency"] == "UGX"
    owner.patch(f"/businesses/{bid}/expenses/{e['id']}", json={"amount": "20000"})
    listed = owner.get(f"/businesses/{bid}/expenses", params={"date_from": "2026-10-01"}).json()
    assert listed["items"][0]["amount"] == "20000.00"
    assert owner.delete(f"/businesses/{bid}/expenses/{e['id']}").status_code == 204
    assert owner.get(f"/businesses/{bid}/expenses").json()["total"] == 0
    assert (
        owner.post(
            f"/businesses/{bid}/expenses", json={"category": "rent", "amount": "-1", "expense_date": "2026-10-02"}
        ).status_code
        == 422
    )
