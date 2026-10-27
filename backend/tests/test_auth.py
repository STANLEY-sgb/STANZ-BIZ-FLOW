from app.core import mailer
from app.modules import auth as auth_module


def test_register_login_and_me(client, make_user):
    user = make_user("Amina Nakato")
    me = user.get("/auth/me")
    assert me.status_code == 200
    assert me.json()["user"]["full_name"] == "Amina Nakato"
    assert me.json()["businesses"] == []

    res = client.post("/api/v1/auth/login", json={"email": user.email.upper(), "password": "Secret123!"})
    assert res.status_code == 200
    assert res.json()["access_token"]


def test_duplicate_email_rejected(client, make_user):
    user = make_user()
    res = client.post("/api/v1/auth/register", json={"full_name": "X Y", "email": user.email, "password": "Another123"})
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "email_taken"


def test_weak_password_rejected(client):
    res = client.post(
        "/api/v1/auth/register", json={"full_name": "X Y", "email": "a@example.com", "password": "12345678"}
    )
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "validation_error"


def test_wrong_password_and_unknown_email_look_identical(client, make_user):
    user = make_user()
    wrong = client.post("/api/v1/auth/login", json={"email": user.email, "password": "Wrong1234"})
    unknown = client.post("/api/v1/auth/login", json={"email": "nobody@example.com", "password": "Wrong1234"})
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()


def test_password_hash_is_not_plaintext(session_factory, make_user):
    from sqlalchemy import select

    from app.models import User

    user = make_user()
    with session_factory() as db:
        stored = db.scalar(select(User.password_hash).where(User.email == user.email))
    assert "Secret123!" not in stored
    assert stored.startswith("$argon2")


def test_refresh_rotates_and_reuse_revokes_session(client, make_user):
    user = make_user()
    first = user.tokens["refresh_token"]
    res = client.post("/api/v1/auth/refresh", json={"refresh_token": first})
    assert res.status_code == 200
    second = res.json()["refresh_token"]
    assert second != first

    # Replaying the old token is treated as theft: the whole session is revoked.
    replay = client.post("/api/v1/auth/refresh", json={"refresh_token": first})
    assert replay.status_code == 401
    after = client.post("/api/v1/auth/refresh", json={"refresh_token": second})
    assert after.status_code == 401


def test_logout_revokes_access_token(client, make_user):
    user = make_user()
    assert user.post("/auth/logout").status_code == 200
    assert user.get("/auth/me").status_code == 401


def test_invalid_and_missing_tokens(client):
    assert client.get("/api/v1/auth/me").status_code == 401
    res = client.get("/api/v1/auth/me", headers={"Authorization": "Bearer not-a-jwt"})
    assert res.status_code == 401
    assert res.json()["error"]["code"] == "token_invalid"


def test_password_reset_flow(client, make_user, monkeypatch):
    sent = {}

    def fake_send(to, subject, body):
        sent["body"] = body
        return True

    monkeypatch.setattr(auth_module, "send_email", fake_send)
    user = make_user()
    res = client.post("/api/v1/auth/password-reset/request", json={"email": user.email})
    assert res.status_code == 200
    token = sent["body"].split("token=")[1].split()[0]

    # Unknown email gets the same answer and sends nothing.
    sent.clear()
    other = client.post("/api/v1/auth/password-reset/request", json={"email": "ghost@example.com"})
    assert other.json() == res.json()
    assert sent == {}

    ok = client.post("/api/v1/auth/password-reset/confirm", json={"token": token, "new_password": "NewPass456"})
    assert ok.status_code == 200
    # Existing sessions are ended and the token is single-use.
    assert user.get("/auth/me").status_code == 401
    again = client.post("/api/v1/auth/password-reset/confirm", json={"token": token, "new_password": "Other789x"})
    assert again.status_code == 400
    login = client.post("/api/v1/auth/login", json={"email": user.email, "password": "NewPass456"})
    assert login.status_code == 200


def test_log_email_backend_never_claims_delivery():
    assert mailer.send_email("a@example.com", "s", "b") is False


def test_login_rate_limited(client, make_user):
    user = make_user()
    codes = [
        client.post("/api/v1/auth/login", json={"email": user.email, "password": "Wrong1234"}).status_code
        for _ in range(12)
    ]
    assert 429 in codes
