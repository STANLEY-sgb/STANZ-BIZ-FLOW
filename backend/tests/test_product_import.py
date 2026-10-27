import csv
import io

from openpyxl import Workbook

from tests.conftest import join_business


def upload(api, bid, content: bytes, filename="products.csv", **params):
    query = "&".join(f"{k}={str(v).lower()}" for k, v in params.items())
    return api.client.post(
        f"/api/v1/businesses/{bid}/products/import?{query}",
        files={"file": (filename, content, "text/csv")},
        headers=api.headers,
    )


GOOD_CSV = (
    b"Product Name,Price,Buying price,Qty,Category,SKU,Brand,Storage,IMEI\n"
    b'Tecno Spark 20,"450,000",380000,4,Phones,TS20,Tecno,128GB,356000000000001\n'
    b"Phone case,15000,5000,30,Accessories,CASE1,,,\n"
    b"Screen protector,UGX 10000,,50,Accessories,SP1,,,\n"
)


def test_dry_run_reports_without_saving(make_user):
    owner = make_user()
    bid = owner.create_business()
    report = upload(owner, bid, GOOD_CSV, dry_run=True).json()
    assert (report["total_rows"], report["to_create"], report["invalid"]) == (3, 3, 0)
    assert report["preview"][0] == {
        "row": 2,
        "action": "create",
        "name": "Tecno Spark 20",
        "sku": "TS20",
        "selling_price": "450000.00",
        "quantity": "4",
        "message": None,
    }
    assert owner.get(f"/businesses/{bid}/products").json()["total"] == 0


def test_import_creates_products_stock_and_categories(make_user):
    owner = make_user()
    bid = owner.create_business(category="retail")  # no default categories for retail
    report = upload(owner, bid, GOOD_CSV, dry_run=False).json()
    assert report["created"] == 3

    products = {p["sku"]: p for p in owner.get(f"/businesses/{bid}/products").json()["items"]}
    tecno = products["TS20"]
    assert tecno["selling_price"] == "450000.00" and tecno["cost_price"] == "380000.00"
    assert tecno["quantity_on_hand"] == "4"
    assert tecno["attributes"] == {"brand": "Tecno", "storage": "128GB", "imei": "356000000000001"}
    assert products["SP1"]["selling_price"] == "10000.00"
    assert {c["name"] for c in owner.get(f"/businesses/{bid}/categories").json()} == {"Phones", "Accessories"}
    # Opening stock is recorded in the ledger, not just set.
    moves = owner.get(f"/businesses/{bid}/stock-movements", params={"product_id": tecno["id"]}).json()["items"]
    assert [(m["reason"], m["note"]) for m in moves] == [("opening", "Import")]


def test_validation_errors_block_import_unless_skipping(make_user):
    owner = make_user()
    bid = owner.create_business()
    bad = (
        b"name,selling price,quantity,sku,warranty\n"
        b"Good item,1000,1,A1,\n"
        b",500,1,A2,\n"  # missing name
        b"Bad price,abc,1,A3,\n"  # invalid price
        b"Negative,100,-2,A4,\n"  # negative quantity
        b"Duplicate,100,1,A1,\n"  # same SKU as row 2
        b"Bad warranty,100,1,A6,two\n"
    )
    report = upload(owner, bid, bad).json()
    assert report["invalid"] == 5 and report["to_create"] == 1
    messages = {(e["row"], e["column"]) for e in report["errors"]}
    assert messages == {
        ("3", "name"),
        ("4", "selling_price"),
        ("5", "quantity"),
        ("6", "sku"),
        ("7", "warranty_months"),
    }

    blocked = upload(owner, bid, bad, dry_run=False)
    assert blocked.status_code == 422 and blocked.json()["error"]["code"] == "import_has_errors"
    assert owner.get(f"/businesses/{bid}/products").json()["total"] == 0

    partial = upload(owner, bid, bad, dry_run=False, skip_invalid=True).json()
    assert partial["created"] == 1


def test_existing_products_skipped_or_updated_via_stock_count(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid, name="Old name", sku="TS20", price="400000", stock="2")
    upload(owner, bid, GOOD_CSV, dry_run=False)
    assert owner.get(f"/businesses/{bid}/products/{p['id']}").json()["name"] == "Old name"  # skipped by default

    report = upload(owner, bid, GOOD_CSV, dry_run=False, update_existing=True).json()
    assert report["updated"] == 3 and report["created"] == 0  # all three exist after the first run
    updated = owner.get(f"/businesses/{bid}/products/{p['id']}").json()
    assert updated["name"] == "Tecno Spark 20" and updated["selling_price"] == "450000.00"
    assert updated["quantity_on_hand"] == "4"
    moves = owner.get(f"/businesses/{bid}/stock-movements", params={"product_id": p["id"]}).json()["items"]
    assert moves[0]["reason"] == "count" and moves[0]["quantity_change"] == "2"


def test_excel_import(make_user):
    owner = make_user()
    bid = owner.create_business()
    wb = Workbook()
    ws = wb.active
    ws.append(["Item", "Retail price", "Stock", "Barcode"])
    ws.append(["Charger 25W", 35000, 12, 6001234567890])
    ws.append(["Earphones", 20000.0, 7, None])
    buf = io.BytesIO()
    wb.save(buf)
    report = upload(owner, bid, buf.getvalue(), filename="stock.xlsx", dry_run=False).json()
    assert report["created"] == 2
    charger = owner.get(f"/businesses/{bid}/products/lookup", params={"code": "6001234567890"}).json()
    assert charger["selling_price"] == "35000.00" and charger["quantity_on_hand"] == "12"


def test_file_format_errors(make_user):
    owner = make_user()
    bid = owner.create_business()
    assert upload(owner, bid, b"foo,bar\n1,2\n").json()["error"]["code"] == "missing_columns"
    assert upload(owner, bid, b"").json()["error"]["code"] == "empty_file"
    res = upload(owner, bid, b"x" * (2 * 1024 * 1024 + 10))
    assert res.json()["error"]["code"] == "file_too_large"
    res = upload(owner, bid, b"%PDF-1.4", filename="list.pdf")
    assert res.json()["error"]["code"] == "unsupported_file_type"


def test_plan_limit_enforced(make_user):
    owner = make_user()
    bid = owner.create_business()
    rows = "name,price\n" + "".join(f"Item {i},100\n" for i in range(51))  # Free plan allows 50
    report = upload(owner, bid, rows.encode()).json()
    assert report["plan_limit_exceeded"] is True
    res = upload(owner, bid, rows.encode(), dry_run=False)
    assert res.status_code == 402
    assert owner.get(f"/businesses/{bid}/products").json()["total"] == 0


def test_permissions_and_tenant_isolation(make_user, pro_plan):
    owner, cashier, stranger = make_user(), make_user(), make_user()
    bid = owner.create_business()
    pro_plan(bid)
    join_business(owner, cashier, bid, "cashier")
    assert upload(cashier, bid, GOOD_CSV).status_code == 403
    assert upload(stranger, bid, GOOD_CSV).status_code == 404
    # A SKU that exists in another business is a new product here.
    other = stranger.create_business("Other shop")
    stranger.create_product(other, sku="TS20")
    assert upload(owner, bid, GOOD_CSV).json()["to_create"] == 3


def test_export_round_trips_and_hides_sensitive_columns(make_user, pro_plan):
    owner, cashier = make_user(), make_user()
    bid = owner.create_business()
    pro_plan(bid)
    join_business(owner, cashier, bid, "cashier")
    upload(owner, bid, GOOD_CSV, dry_run=False)
    owner.create_product(bid, name="=HYPERLINK(evil)", sku="X1")

    res = owner.get(f"/businesses/{bid}/products/export.csv")
    assert res.status_code == 200 and res.headers["content-type"].startswith("text/csv")
    rows = list(csv.DictReader(io.StringIO(res.content.decode("utf-8-sig"))))
    tecno = next(r for r in rows if r["sku"] == "TS20")
    assert tecno["cost_price"] == "380000.00" and tecno["imei"] == "356000000000001"
    assert next(r for r in rows if r["sku"] == "X1")["name"].startswith("'=")

    # Re-importing the export into a fresh business recreates the catalogue.
    fresh = owner.create_business("Second branch")
    pro_plan(fresh)
    report = upload(owner, fresh, res.content, dry_run=False).json()
    assert report["created"] == len(rows)

    cashier_rows = list(
        csv.DictReader(io.StringIO(cashier.get(f"/businesses/{bid}/products/export.csv").content.decode("utf-8-sig")))
    )
    assert "cost_price" not in cashier_rows[0] and "imei" not in cashier_rows[0]
