import io
from urllib.parse import parse_qs, urlparse

import pytest
from PIL import Image

from app.core.storage import LocalStorage, set_storage
from tests.conftest import join_business


@pytest.fixture(autouse=True)
def storage(tmp_path):
    set_storage(LocalStorage(str(tmp_path / "uploads")))
    yield tmp_path / "uploads"
    set_storage(None)


def photo(size=(2400, 1600), fmt="JPEG", with_gps=True) -> bytes:
    img = Image.new("RGB", size, (244, 119, 69))
    buf = io.BytesIO()
    if with_gps and fmt == "JPEG":
        exif = Image.Exif()
        exif[0x010F] = "Samsung"  # Make
        exif[0x8825] = {1: "N", 2: (0.0, 18.0, 52.0)}  # GPS IFD: a location near Kampala
        img.save(buf, format=fmt, exif=exif)
    else:
        img.save(buf, format=fmt)
    return buf.getvalue()


def upload(api, path, data, filename="photo.jpg", ctype="image/jpeg"):
    return api.client.post(f"/api/v1{path}", files={"file": (filename, data, ctype)}, headers=api.headers)


def fetch(client, url):
    return client.get(url)


def test_product_image_upload_resizes_strips_metadata_and_serves_signed(client, make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid)
    res = upload(owner, f"/businesses/{bid}/products/{p['id']}/image", photo())
    assert res.status_code == 200, res.text
    url = res.json()["image_url"]
    assert url and "sig=" in url

    img_res = fetch(client, url)
    assert img_res.status_code == 200
    assert img_res.headers["content-type"] == "image/webp"
    assert img_res.headers["cache-control"].startswith("private")
    img = Image.open(io.BytesIO(img_res.content))
    assert img.format == "WEBP"
    assert max(img.size) == 1024  # downscaled from 2400 px
    assert not img.getexif(), "EXIF (including GPS location) must be stripped"
    # The product listing carries the same image.
    assert owner.get(f"/businesses/{bid}/products/{p['id']}").json()["image_url"]


def test_signed_links_cannot_be_forged_or_reused_after_expiry(client, make_user, monkeypatch):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid)
    url = upload(owner, f"/businesses/{bid}/products/{p['id']}/image", photo()).json()["image_url"]
    parsed = urlparse(url)
    q = parse_qs(parsed.query)
    tampered = f"{parsed.path}?exp={int(q['exp'][0]) + 99999}&sig={q['sig'][0]}"
    assert fetch(client, tampered).status_code == 403
    assert fetch(client, f"{parsed.path}?exp={q['exp'][0]}&sig={'0' * 40}").status_code == 403
    assert fetch(client, parsed.path).status_code == 422  # unsigned access is impossible

    import time

    monkeypatch.setattr(time, "time", lambda: int(q["exp"][0]) + 1)
    assert fetch(client, url).status_code == 403


def test_replacing_and_removing_an_image_deletes_old_files(client, make_user, storage):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid)
    upload(owner, f"/businesses/{bid}/products/{p['id']}/image", photo())
    upload(
        owner, f"/businesses/{bid}/products/{p['id']}/image", photo(size=(300, 300), fmt="PNG"), "a.png", "image/png"
    )
    assert len(list(storage.rglob("*.webp"))) == 1, "the replaced image must be removed from storage"
    res = owner.delete(f"/businesses/{bid}/products/{p['id']}/image")
    assert res.json()["image_url"] is None
    assert list(storage.rglob("*.webp")) == []


def test_rejects_non_images_and_oversized_files(make_user):
    owner = make_user()
    bid = owner.create_business()
    p = owner.create_product(bid)
    path = f"/businesses/{bid}/products/{p['id']}/image"
    # A script renamed to .jpg is detected by content, not by name.
    res = upload(owner, path, b"<script>alert(1)</script>", "evil.jpg")
    assert res.status_code == 400 and res.json()["error"]["code"] == "invalid_image"
    gif = io.BytesIO()
    Image.new("RGB", (10, 10)).save(gif, format="GIF")
    assert upload(owner, path, gif.getvalue(), "x.gif", "image/gif").json()["error"]["code"] == "unsupported_file_type"
    big = upload(owner, path, b"\xff\xd8" + b"0" * (5 * 1024 * 1024 + 10))
    assert big.json()["error"]["code"] == "file_too_large"


def test_permissions_and_tenant_isolation(make_user, pro_plan):
    owner, cashier, stranger = make_user(), make_user(), make_user()
    bid = owner.create_business()
    pro_plan(bid)
    join_business(owner, cashier, bid, "cashier")
    p = owner.create_product(bid)
    assert upload(cashier, f"/businesses/{bid}/products/{p['id']}/image", photo()).status_code == 403
    assert upload(stranger, f"/businesses/{bid}/products/{p['id']}/image", photo()).status_code == 404
    other = stranger.create_business("Other")
    assert upload(stranger, f"/businesses/{other}/products/{p['id']}/image", photo()).status_code == 404


def test_business_logo_appears_on_receipts(client, make_user):
    owner = make_user()
    bid = owner.create_business()
    res = upload(owner, f"/businesses/{bid}/logo", photo(size=(800, 800), fmt="PNG"), "logo.png", "image/png")
    assert res.status_code == 200
    logo = Image.open(io.BytesIO(fetch(client, res.json()["logo_url"]).content))
    assert max(logo.size) == 512
    assert owner.get(f"/businesses/{bid}").json()["logo_url"]
    p = owner.create_product(bid, price="1000", stock="5")
    sale = owner.sell(bid, [(p["id"], "1")]).json()
    assert owner.get(f"/businesses/{bid}/sales/{sale['id']}/receipt").json()["logo_url"]
    assert owner.delete(f"/businesses/{bid}/logo").status_code == 204
    assert owner.get(f"/businesses/{bid}").json()["logo_url"] is None
