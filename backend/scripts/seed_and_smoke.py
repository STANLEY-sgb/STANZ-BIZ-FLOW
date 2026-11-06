"""Seed a demo business through the real HTTP API and exercise every endpoint the mobile app uses.

    python scripts/seed_and_smoke.py [--base http://localhost:8000/api/v1] [--email demo@example.com]

Safe to re-run: it reuses the demo account if it exists and creates a fresh demo business each time
only when none exists. Exits non-zero if any check fails, so it can gate a release.
"""

import argparse
import sys
import uuid
from datetime import date, timedelta

import httpx

PASSWORD = "Demo12345!"
results: list[tuple[str, bool, str]] = []


def check(name: str, res: httpx.Response, expect: tuple[int, ...] = (200, 201, 204)):
    ok = res.status_code in expect
    results.append((name, ok, "" if ok else f"{res.status_code} {res.text[:200]}"))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + ("" if ok else f"  -> {res.status_code} {res.text[:200]}"))
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://localhost:8000/api/v1")
    ap.add_argument("--email", default="demo@example.com")
    args = ap.parse_args()
    c = httpx.Client(base_url=args.base, timeout=30)

    # --- Auth ---
    check("health", httpx.get(args.base.replace("/api/v1", "") + "/health"))
    res = c.post("/auth/register", json={"full_name": "Demo Owner", "email": args.email, "password": PASSWORD})
    if res.status_code == 409 or res.status_code == 400:
        res = c.post("/auth/login", json={"email": args.email, "password": PASSWORD, "device_name": "smoke"})
        check("login (existing demo user)", res)
    else:
        check("register", res)
    tok = res.json()
    c.headers["Authorization"] = f"Bearer {tok['access_token']}"
    check("login", c.post("/auth/login", json={"email": args.email, "password": PASSWORD, "device_name": "smoke"}))
    check(
        "login wrong password -> 401",
        c.post("/auth/login", json={"email": args.email, "password": "nope-nope1"}),
        (401,),
    )
    check("refresh", c.post("/auth/refresh", json={"refresh_token": tok["refresh_token"]}))
    me = check("me", c.get("/auth/me")).json()
    check("password reset request", c.post("/auth/password-reset/request", json={"email": args.email}))
    check("plans", c.get("/plans"))

    # --- Business ---
    if me["businesses"]:
        bid = me["businesses"][0]["business_id"]
        print(f"Reusing existing business {bid}")
    else:
        bid = check(
            "create business",
            c.post(
                "/businesses",
                json={
                    "name": "Kampala Phones & Accessories",
                    "category": "electronics",
                    "payment_methods": ["cash", "mobile_money", "card"],
                    "tax_rate_percent": "0",
                },
            ),
        ).json()["id"]
    b = f"/businesses/{bid}"
    check("get business", c.get(b))
    check("update business", c.patch(b, json={"phone": "+256700000000", "address": "Kampala Road, Kampala"}))
    check("onboarding step", c.post(f"{b}/onboarding", json={"step": "first_product"}))
    check("subscription", c.get(f"{b}/subscription"))
    check("start trial", c.post(f"{b}/subscription/trial", json={"plan_code": "professional"}), (200, 201, 400, 409))
    check("members", c.get(f"{b}/members"))
    check("invitations list", c.get(f"{b}/invitations"))
    check(
        "invite",
        c.post(f"{b}/invitations", json={"email": f"staff{uuid.uuid4().hex[:5]}@example.com", "role": "cashier"}),
        (200, 201, 402, 403),
    )

    # --- Catalogue ---
    cats = {x["name"]: x["id"] for x in check("categories", c.get(f"{b}/categories")).json()}
    if "Phones" not in cats:
        cats["Phones"] = check("create category", c.post(f"{b}/categories", json={"name": "Phones"})).json()["id"]
    products = check("list products", c.get(f"{b}/products", params={"limit": 100})).json()["items"]
    if len(products) < 8:
        catalogue = [
            ("Tecno Spark 20", "450000", "380000", "25", "6901001", "Phones"),
            ("Samsung Galaxy A15", "650000", "520000", "12", "6901002", "Phones"),
            ("Infinix Hot 40", "520000", "430000", "3", "6901003", "Phones"),
            ("Phone case", "15000", "5000", "80", "6901004", None),
            ("Fast charger 25W", "45000", "28000", "40", "6901005", None),
            ("USB-C cable", "12000", "5000", "60", "6901006", None),
            ("Earphones", "25000", "12000", "0", "6901007", None),
            ("Screen protector", "8000", "2000", "100", "6901008", None),
        ]
        for name, price, cost, stock, barcode, cat in catalogue:
            body = {
                "name": name,
                "selling_price": price,
                "cost_price": cost,
                "opening_stock": stock,
                "barcode": barcode,
                "sku": f"SKU-{barcode}",
                "reorder_level": "5",
            }
            if cat:
                body["category_id"] = cats[cat]
            res = c.post(f"{b}/products", json=body)
            if res.status_code == 409:
                continue
            check(f"create product {name}", res)
        products = c.get(f"{b}/products", params={"limit": 100}).json()["items"]
    by_name = {p["name"]: p for p in products}
    phone, case = by_name["Tecno Spark 20"], by_name["Phone case"]
    check("get product", c.get(f"{b}/products/{phone['id']}"))
    check("product lookup by barcode", c.get(f"{b}/products/lookup", params={"code": "6901001"}))
    check("search products", c.get(f"{b}/products", params={"q": "tecno"}))
    check("filter low stock", c.get(f"{b}/products", params={"stock": "low_stock"}))
    check("update product", c.patch(f"{b}/products/{case['id']}", json={"description": "Silicone protective case"}))
    check("archive product", c.post(f"{b}/products/{by_name['Earphones']['id']}/archive"))
    check("restore product", c.post(f"{b}/products/{by_name['Earphones']['id']}/restore"))
    check(
        "stock receipt",
        c.post(
            f"{b}/products/{phone['id']}/stock-movements", json={"type": "receipt", "quantity": "5", "note": "restock"}
        ),
    )
    check(
        "stock damage",
        c.post(
            f"{b}/products/{case['id']}/stock-movements", json={"type": "damage", "quantity": "1", "note": "dropped"}
        ),
    )
    check(
        "stock count",
        c.post(
            f"{b}/products/{case['id']}/stock-movements",
            json={"type": "count", "counted_quantity": "70", "note": "monthly count"},
        ),
    )
    check("stock movements", c.get(f"{b}/stock-movements", params={"product_id": phone["id"]}))
    check("export products csv", c.get(f"{b}/products/export.csv"))
    csv = b"name,selling_price,cost_price,opening_stock\nImport Test Item,1000,500,5\n"
    check(
        "import dry run",
        c.post(f"{b}/products/import", params={"dry_run": True}, files={"file": ("p.csv", csv, "text/csv")}),
    )

    # --- Customers ---
    custs = c.get(f"{b}/customers").json()["items"]
    if not custs:
        for n, ph in [
            ("Sarah Namukasa", "+256771000001"),
            ("David Okello", "+256772000002"),
            ("Grace Atim", "+256773000003"),
        ]:
            check(f"create customer {n}", c.post(f"{b}/customers", json={"name": n, "phone": ph}))
        custs = c.get(f"{b}/customers").json()["items"]
    check("customer detail", c.get(f"{b}/customers/{custs[0]['id']}"))
    check("search customers", c.get(f"{b}/customers", params={"q": "sar"}))

    # --- Sales ---
    sales = c.get(f"{b}/sales").json()["items"]
    if len(sales) < 5:
        plan = [
            ([(phone, "1"), (case, "2")], "cash"),
            ([(by_name["Samsung Galaxy A15"], "1")], "mobile_money"),
            ([(by_name["USB-C cable"], "3"), (by_name["Fast charger 25W"], "1")], "cash"),
            ([(by_name["Screen protector"], "5")], "card"),
            ([(by_name["Infinix Hot 40"], "1")], "cash"),
        ]
        for i, (lines, method) in enumerate(plan):
            res = c.post(
                f"{b}/sales",
                json={
                    "client_reference": uuid.uuid4().hex,
                    "customer_id": custs[i % len(custs)]["id"],
                    "items": [{"product_id": p["id"], "quantity": q} for p, q in lines],
                    "payments": [
                        {
                            "method": method,
                            "amount": "100000000"
                            if method == "cash"
                            else str(sum(float(p["selling_price"]) * float(q) for p, q in lines)),
                        }
                    ],
                },
            )
            check(f"create sale #{i + 1} ({method})", res)
    sales = check("list sales", c.get(f"{b}/sales")).json()["items"]
    sid = sales[0]["id"]
    sale = check("sale detail", c.get(f"{b}/sales/{sid}")).json()
    check("receipt", c.get(f"{b}/sales/{sid}/receipt"))
    ref = uuid.uuid4().hex
    body = {
        "client_reference": ref,
        "items": [{"product_id": case["id"], "quantity": "1"}],
        "payments": [{"method": "cash", "amount": "20000"}],
    }
    first = check("idempotent sale", c.post(f"{b}/sales", json=body)).json()
    again = check("idempotent sale replay", c.post(f"{b}/sales", json=body), (200, 201)).json()
    results.append(("replay returns same sale", first["id"] == again["id"], ""))
    print(f"[{'PASS' if first['id'] == again['id'] else 'FAIL'}] replay returns same sale")
    check(
        "oversell rejected",
        c.post(
            f"{b}/sales",
            json={
                "client_reference": uuid.uuid4().hex,
                "items": [{"product_id": by_name["Earphones"]["id"], "quantity": "999"}],
                "payments": [{"method": "cash", "amount": "99999999"}],
            },
        ),
        (409, 422),
    )
    check(
        "return item",
        c.post(
            f"{b}/sales/{sid}/returns",
            json={
                "client_reference": uuid.uuid4().hex,
                "reason": "Customer changed mind",
                "lines": [{"sale_item_id": sale["items"][0]["id"], "quantity": "1"}],
            },
        ),
    )
    check("offline sync batch", c.post(f"{b}/sync/sales", json={"sales": []}), (200, 422))
    check("sync status", c.get(f"{b}/sync/status"))

    # --- Expenses ---
    check("expense categories", c.get(f"{b}/expenses/categories"))
    exp = check(
        "create expense",
        c.post(
            f"{b}/expenses",
            json={
                "category": "rent",
                "amount": "300000",
                "expense_date": str(date.today()),
                "description": "Shop rent",
            },
        ),
    ).json()
    c.post(
        f"{b}/expenses",
        json={"category": "transport", "amount": "25000", "expense_date": str(date.today() - timedelta(days=1))},
    )
    check("list expenses", c.get(f"{b}/expenses"))
    check("update expense", c.patch(f"{b}/expenses/{exp['id']}", json={"amount": "310000"}))
    tmp = c.post(
        f"{b}/expenses", json={"category": "other", "amount": "1000", "expense_date": str(date.today())}
    ).json()
    check("delete expense", c.delete(f"{b}/expenses/{tmp['id']}"))

    # --- Reports ---
    for period in ("today", "7d", "30d", "month"):
        check(f"dashboard {period}", c.get(f"{b}/dashboard", params={"period": period}))
    check("summary", c.get(f"{b}/reports/summary"))
    for r in (
        "sales-by-day",
        "sales-by-product",
        "sales-by-category",
        "sales-by-cashier",
        "payment-methods",
        "expenses-by-category",
        "inventory",
        "low-stock",
        "sales-by-product.csv",
    ):
        check(f"report {r}", c.get(f"{b}/reports/{r}"))
    check("audit events", c.get(f"{b}/audit-events"))
    check("logout", c.post("/auth/logout"))

    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
    print(f"Demo login: {args.email} / {PASSWORD}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
