import httpx

from app.core import storage as storage_mod


def test_supabase_storage_roundtrip(monkeypatch):
    objects: dict[str, bytes] = {}
    seen_auth = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen_auth.append(request.headers["authorization"])
        key = request.url.path
        if request.method == "POST":
            objects[key] = request.content
            return httpx.Response(200, json={"Key": key})
        if request.method == "GET":
            return httpx.Response(200, content=objects[key]) if key in objects else httpx.Response(400)
        objects.pop(key, None)
        return httpx.Response(200)

    transport = httpx.MockTransport(handler)
    for verb in ("post", "get", "delete"):
        monkeypatch.setattr(
            storage_mod.httpx,
            verb,
            lambda url, _v=verb, **kw: httpx.Client(transport=transport).request(
                _v.upper(), url, headers=kw.get("headers"), content=kw.get("content")
            ),
        )
    s = storage_mod.SupabaseStorage("https://x.supabase.co", "service-key", "bucket")
    s.put("a/b.jpg", b"data")
    assert s.get("a/b.jpg") == b"data"
    s.delete("a/b.jpg")
    assert s.get("a/b.jpg") is None
    assert set(seen_auth) == {"Bearer service-key"}
