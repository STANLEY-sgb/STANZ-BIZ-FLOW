"""Capture real API responses (after seed_and_smoke.py) as fixtures for the Flutter contract test."""

import json
import pathlib
import sys

import httpx

base = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000/api/v1"
out = pathlib.Path(__file__).resolve().parents[2] / "mobile" / "test" / "fixtures"
c = httpx.Client(base_url=base, timeout=30)
tok = c.post("/auth/login", json={"email": "demo@example.com", "password": "Demo12345!"}).json()
c.headers["Authorization"] = f"Bearer {tok['access_token']}"
me = c.get("/auth/me").json()
bid = me["businesses"][0]["business_id"]
b = f"/businesses/{bid}"
sales = c.get(f"{b}/sales").json()
prods = c.get(f"{b}/products", params={"limit": 100}).json()
cust = c.get(f"{b}/customers").json()["items"][0]["id"]
paths = {
    "login": None,
    "me": "/auth/me",
    "business": b,
    "subscription": f"{b}/subscription",
    "members": f"{b}/members",
    "categories": f"{b}/categories",
    "products": f"{b}/products",
    "product": f"{b}/products/{prods['items'][0]['id']}",
    "movements": f"{b}/stock-movements",
    "sales": f"{b}/sales",
    "sale": f"{b}/sales/{sales['items'][0]['id']}",
    "receipt": f"{b}/sales/{sales['items'][0]['id']}/receipt",
    "customers": f"{b}/customers",
    "customer": f"{b}/customers/{cust}",
    "expenses": f"{b}/expenses",
    "dashboard_today": (f"{b}/dashboard", {"period": "today"}),
    "dashboard_30d": (f"{b}/dashboard", {"period": "30d"}),
    "summary": f"{b}/reports/summary",
}
for name, p in paths.items():
    if p is None:
        data = tok
    else:
        path, params = (p, None) if isinstance(p, str) else p
        r = c.get(path, params=params)
        r.raise_for_status()
        data = r.json()
    (out / f"{name}.json").write_text(json.dumps(data, indent=1))
print("wrote", len(paths), "fixtures to", out)
