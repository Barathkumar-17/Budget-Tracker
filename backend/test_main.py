import importlib
import itertools
import os
import sqlite3
import tempfile

os.environ["BUDGET_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["WEB_DIR"] = os.path.join(tempfile.mkdtemp(), "no-web")  # tests run API-only

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from main import app  # noqa: E402

client = TestClient(app)
_n = itertools.count(1)
PASSWORD = "correct horse"


def signup(name=None, password=PASSWORD):
    """Register a fresh user; returns (auth headers, username)."""
    name = name or f"user{next(_n)}"
    r = client.post("/auth/register", json={"username": name, "password": password})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}, name


@pytest.fixture
def user():
    return signup()[0]


# ------------------------------------------------------------------ accounts
def test_register_login_me_logout():
    r = client.post("/auth/register", json={"username": "Alice_1", "password": PASSWORD})
    assert r.status_code == 201 and r.json()["username"] == "Alice_1" and r.json()["token"]

    r = client.post("/auth/login", json={"username": "alice_1", "password": PASSWORD})  # case-insensitive
    assert r.status_code == 200
    h = {"Authorization": f"Bearer {r.json()['token']}"}
    assert client.get("/auth/me", headers=h).json() == {"username": "Alice_1"}

    assert client.post("/auth/logout", headers=h).status_code == 204
    assert client.get("/auth/me", headers=h).status_code == 401  # the token no longer works
    assert client.get("/expenses", headers=h).status_code == 401


def test_registration_rules():
    signup("taken_name")
    dup = client.post("/auth/register", json={"username": "TAKEN_NAME", "password": PASSWORD})
    assert dup.status_code == 409 and "already taken" in dup.json()["detail"]
    for bad in [
        {"username": "ab", "password": PASSWORD},  # too short
        {"username": "has space", "password": PASSWORD},  # bad characters
        {"username": "x" * 31, "password": PASSWORD},  # too long
        {"username": "valid_name", "password": "short"},  # password under 8
    ]:
        assert client.post("/auth/register", json=bad).status_code == 422, bad


def test_login_failures_are_uniform():
    signup("real_user")
    wrong_pw = client.post("/auth/login", json={"username": "real_user", "password": "nope-nope"})
    no_user = client.post("/auth/login", json={"username": "ghost_user", "password": "nope-nope"})
    assert wrong_pw.status_code == no_user.status_code == 401
    assert wrong_pw.json() == no_user.json() == {"detail": "Wrong username or password"}


def test_passwords_are_hashed_and_salted():
    signup("hash_a", "same password 1")
    signup("hash_b", "same password 1")
    conn = sqlite3.connect(os.environ["BUDGET_DB"])
    rows = dict(conn.execute("SELECT username, password_hash FROM users WHERE username LIKE 'hash_%'").fetchall())
    conn.close()
    assert all(h.startswith("scrypt$") and "same password 1" not in h for h in rows.values())
    assert rows["hash_a"] != rows["hash_b"]  # per-user salt


@pytest.mark.parametrize("method,path,body", [
    ("get", "/account", None),
    ("put", "/account", {"opening_balance": 1, "low_balance_threshold": 0}),
    ("get", "/expenses", None),
    ("post", "/expenses", {"amount": 1, "date": "2026-10-01", "category": "x"}),
    ("put", "/expenses/1", {"amount": 1, "date": "2026-10-01", "category": "x"}),
    ("delete", "/expenses/1", None),
    ("get", "/budgets?month=2026-10", None),
    ("put", "/budgets", {"category": "x", "month": "2026-10", "cap": 1}),
    ("get", "/recurring", None),
    ("post", "/recurring", {"amount": 1, "category": "x", "day_of_month": 1}),
    ("delete", "/recurring/1", None),
    ("post", "/recurring/apply?month=2026-10", None),
    ("get", "/goals", None),
    ("post", "/goals", {"name": "x", "target": 1}),
    ("post", "/goals/1/contribute", {"amount": 1}),
    ("delete", "/goals/1", None),
    ("get", "/dashboard?month=2026-10", None),
    ("get", "/auth/me", None),
    ("post", "/auth/logout", None),
])
def test_every_data_endpoint_requires_login(method, path, body):
    kwargs = {"json": body} if body is not None else {}
    assert getattr(client, method)(path, **kwargs).status_code == 401, (method, path)
    bad = getattr(client, method)(path, headers={"Authorization": "Bearer not-a-real-token"}, **kwargs)
    assert bad.status_code == 401


def test_sessions_expire():
    h, _ = signup()
    conn = sqlite3.connect(os.environ["BUDGET_DB"])
    conn.execute("UPDATE sessions SET created = datetime('now', '-31 days')")
    conn.commit()
    conn.close()
    assert client.get("/auth/me", headers=h).status_code == 401


# ---------------------------------------------------------------- isolation
def test_users_cannot_see_or_change_each_others_data():
    a, _ = signup()
    b, _ = signup()

    client.put("/account", json={"opening_balance": 1000, "low_balance_threshold": 100}, headers=a)
    client.put("/budgets", json={"category": "Food", "month": "2026-10", "cap": 100}, headers=a)
    exp = client.post("/expenses", json={"amount": 60, "date": "2026-10-03", "category": "Food"}, headers=a).json()["expense"]
    tmpl = client.post("/recurring", json={"amount": 5, "category": "Gym", "day_of_month": 2}, headers=a).json()
    goal = client.post("/goals", json={"name": "Trip", "target": 500}, headers=a).json()

    # B sees an empty world of their own
    assert client.get("/expenses", headers=b).json() == []
    assert client.get("/budgets", params={"month": "2026-10"}, headers=b).json() == []
    assert client.get("/recurring", headers=b).json() == []
    assert client.get("/goals", headers=b).json() == []
    assert client.get("/account", headers=b).json()["balance"] == 0
    d = client.get("/dashboard", params={"month": "2026-10"}, headers=b).json()
    assert d["total_spent"] == 0 and d["categories"] == [] and d["trend"] == []

    # ...and cannot touch A's records by id (404, not 403: their existence is not revealed)
    upd = {"amount": 1, "date": "2026-10-03", "category": "x"}
    assert client.put(f"/expenses/{exp['id']}", json=upd, headers=b).status_code == 404
    assert client.delete(f"/expenses/{exp['id']}", headers=b).status_code == 404
    assert client.delete(f"/recurring/{tmpl['id']}", headers=b).status_code == 404
    assert client.post(f"/goals/{goal['id']}/contribute", json={"amount": 1}, headers=b).status_code == 404
    assert client.delete(f"/goals/{goal['id']}", headers=b).status_code == 404

    # A's data is untouched by all of that
    assert [e["id"] for e in client.get("/expenses", headers=a).json()] == [exp["id"]]
    assert client.get("/goals", headers=a).json()[0]["saved"] == 0

    # B applying recurring creates nothing from A's templates; A's own apply still works
    assert client.post("/recurring/apply", params={"month": "2026-11"}, headers=b).json()["created"] == 0
    assert client.post("/recurring/apply", params={"month": "2026-11"}, headers=a).json()["created"] == 1


def test_same_category_and_month_are_independent_per_user():
    a, _ = signup()
    b, _ = signup()
    client.put("/budgets", json={"category": "Food", "month": "2026-10", "cap": 100}, headers=a)
    client.put("/budgets", json={"category": "food", "month": "2026-10", "cap": 900}, headers=b)
    assert client.get("/budgets", params={"month": "2026-10"}, headers=a).json()[0]["cap"] == 100
    assert client.get("/budgets", params={"month": "2026-10"}, headers=b).json()[0]["cap"] == 900
    ra = client.post("/expenses", json={"amount": 150, "date": "2026-10-03", "category": "food"}, headers=a).json()
    rb = client.post("/expenses", json={"amount": 150, "date": "2026-10-03", "category": "food"}, headers=b).json()
    assert ra["alert"]["over_by"] == 50 and rb["alert"] is None


# ------------------------------------------------------------------ features
def test_expense_budget_dashboard_flow(user):
    client.put("/budgets", json={"category": "Food", "month": "2026-10", "cap": 100}, headers=user)
    r = client.post("/expenses", json={"amount": 60.10, "date": "2026-10-03", "category": "Food"}, headers=user)
    assert r.status_code == 201 and r.json()["alert"] is None
    r = client.post("/expenses", json={"amount": 55, "date": "2026-10-04", "category": "food"}, headers=user)
    assert r.json()["alert"]["over_by"] == 15.1

    d = client.get("/dashboard", params={"month": "2026-10"}, headers=user).json()
    assert d["total_spent"] == 115.1
    assert d["categories"][0] == {"category": "food", "spent": 115.1, "cap": 100.0, "over": True}
    assert len(d["trend"]) == 2


def test_validation_and_404(user):
    bad = {"amount": -1, "date": "2026-10-03", "category": "x"}
    assert client.post("/expenses", json=bad, headers=user).status_code == 422
    assert client.delete("/expenses/9999", headers=user).status_code == 404


def test_low_balance_and_goals(user):
    client.put("/account", json={"opening_balance": 1000, "low_balance_threshold": 300}, headers=user)
    g = client.post("/goals", json={"name": "Headphones", "target": 500}, headers=user).json()
    r = client.post(f"/goals/{g['id']}/contribute", json={"amount": 100.25}, headers=user).json()
    assert r["goal"]["saved"] == 100.25 and r["goal"]["progress"] == 0.2005
    assert r["balance"] == 899.75
    big = client.post("/expenses", json={"amount": 900, "date": "2026-10-05", "category": "misc"}, headers=user).json()
    assert big["low_balance"] is True and big["balance"] == -0.25
    assert client.get("/goals", headers=user).json()[0]["name"] == "Headphones"
    assert client.delete(f"/goals/{g['id']}", headers=user).status_code == 204


def test_recurring_is_idempotent(user):
    t = client.post("/recurring", json={"amount": 499, "category": "Subscriptions",
                                        "note": "music", "day_of_month": 5}, headers=user).json()
    assert client.post("/recurring/apply", params={"month": "2026-11"}, headers=user).json()["created"] == 1
    assert client.post("/recurring/apply", params={"month": "2026-11"}, headers=user).json()["created"] == 0
    rows = client.get("/expenses", params={"month": "2026-11"}, headers=user).json()
    assert rows[0]["amount"] == 499 and rows[0]["date"] == "2026-11-05"
    assert client.delete(f"/recurring/{t['id']}", headers=user).status_code == 204


def test_month_params_are_validated(user):
    assert client.post("/recurring/apply", params={"month": "2026-13"}, headers=user).status_code == 422
    assert client.post("/recurring/apply", params={"month": "abcd-ef7"}, headers=user).status_code == 422
    assert client.get("/dashboard", params={"month": "2026-1"}, headers=user).status_code == 422
    assert client.get("/budgets", params={"month": "nope"}, headers=user).status_code == 422
    assert client.get("/expenses", params={"month": "2026-00"}, headers=user).status_code == 422


def test_blank_names_are_rejected_and_trimmed(user):
    bad = {"amount": 5, "date": "2026-10-03", "category": "   "}
    assert client.post("/expenses", json=bad, headers=user).status_code == 422
    assert client.put("/budgets", json={"category": " ", "month": "2026-10", "cap": 1}, headers=user).status_code == 422
    assert client.post("/recurring", json={"amount": 1, "category": " ", "day_of_month": 1}, headers=user).status_code == 422
    assert client.post("/goals", json={"name": "  ", "target": 10}, headers=user).status_code == 422
    r = client.post("/expenses", json={"amount": 5, "date": "2026-09-03", "category": "  Tea "}, headers=user).json()
    assert r["expense"]["category"] == "tea"


def test_update_expense_returns_alert_and_filters(user):
    client.put("/budgets", json={"category": "snacks", "month": "2026-08", "cap": 10}, headers=user)
    e = client.post("/expenses", json={"amount": 10, "date": "2026-08-01", "category": "Snacks"}, headers=user).json()["expense"]
    r = client.put(f"/expenses/{e['id']}", headers=user, json={
        "amount": 12.5, "date": "2026-08-02", "category": "SNACKS", "note": "edited"})
    assert r.status_code == 200
    body = r.json()
    assert body["expense"]["amount"] == 12.5 and body["expense"]["category"] == "snacks"
    assert body["alert"]["over_by"] == 2.5  # editing can push a category over its cap
    assert client.put("/expenses/99999", json={"amount": 1, "date": "2026-08-02", "category": "x"},
                      headers=user).status_code == 404
    rows = client.get("/expenses", params={"month": "2026-08", "category": "Snacks"}, headers=user).json()
    assert [x["note"] for x in rows] == ["edited"]
    assert client.get("/expenses", params={"month": "2026-08", "category": "nothing"}, headers=user).json() == []


def test_budget_upsert_and_amount_precision(user):
    client.put("/budgets", json={"category": "Rent", "month": "2027-01", "cap": 100}, headers=user)
    client.put("/budgets", json={"category": "rent", "month": "2027-01", "cap": 250.5}, headers=user)
    assert client.get("/budgets", params={"month": "2027-01"}, headers=user).json() == [
        {"category": "rent", "month": "2027-01", "cap": 250.5}]
    # more than 2 decimal places is rejected, not silently rounded
    assert client.post("/expenses", json={"amount": 1.005, "date": "2027-01-01", "category": "x"},
                       headers=user).status_code == 422
    for amt in (0.1, 0.2):  # 0.1 + 0.2 stays exact in paise
        client.post("/expenses", json={"amount": amt, "date": "2027-02-01", "category": "tiny"}, headers=user)
    assert client.get("/dashboard", params={"month": "2027-02"}, headers=user).json()["total_spent"] == 0.3


def test_recurring_per_month_and_goal_progress_clamped(user):
    t = client.post("/recurring", json={"amount": 20, "category": "Gym", "day_of_month": 28}, headers=user).json()
    for month, expect in [("2027-03", 1), ("2027-04", 1), ("2027-04", 0)]:
        assert client.post("/recurring/apply", params={"month": month}, headers=user).json()["created"] == expect
    assert client.get("/expenses", params={"month": "2027-03"}, headers=user).json()[0]["date"] == "2027-03-28"
    assert client.delete(f"/recurring/{t['id']}", headers=user).status_code == 204
    assert client.delete(f"/recurring/{t['id']}", headers=user).status_code == 404

    g = client.post("/goals", json={"name": "Trip", "target": 100}, headers=user).json()
    r = client.post(f"/goals/{g['id']}/contribute", json={"amount": 150}, headers=user).json()
    assert r["goal"]["progress"] == 1.0 and r["goal"]["saved"] == 150
    assert client.post("/goals/99999/contribute", json={"amount": 1}, headers=user).status_code == 404
    assert client.post(f"/goals/{g['id']}/contribute", json={"amount": 0}, headers=user).status_code == 422


def test_account_validation(user):
    assert client.put("/account", json={"opening_balance": -1, "low_balance_threshold": 0},
                      headers=user).status_code == 422
    r = client.put("/account", json={"opening_balance": 0, "low_balance_threshold": 0}, headers=user).json()
    assert r["low_balance"] is False


# --------------------------------------------------------------------- misc
def test_root_and_head_for_health_probes():
    assert client.get("/").json() == {"name": "Budget Tracker API", "docs": "/docs"}
    assert client.head("/").status_code == 200


def test_serves_the_web_app_when_present(tmp_path, monkeypatch):
    """With a compiled web app next to the API (the Docker image), "/" is the app and the API still works."""
    (tmp_path / "index.html").write_text("<html>the app</html>")
    (tmp_path / "main.dart.js").write_text("console.log('js')")
    monkeypatch.setenv("WEB_DIR", str(tmp_path))
    reloaded = importlib.reload(main)
    try:
        c = TestClient(reloaded.app)
        assert c.get("/").text == "<html>the app</html>"
        assert c.head("/").status_code == 200
        assert c.get("/main.dart.js").text == "console.log('js')"
        assert c.get("/missing-file.js").status_code == 404
        assert c.get("/account").status_code == 401  # API routes still win (and still need login)
        assert c.get("/docs").status_code == 200
    finally:
        monkeypatch.delenv("WEB_DIR")
        importlib.reload(main)


def test_old_single_user_database_is_kept_not_destroyed(tmp_path, monkeypatch):
    """An existing pre-accounts database gets new tables; its old rows are kept under legacy_* names."""
    original_db = os.environ["BUDGET_DB"]
    legacy = tmp_path / "old.db"
    conn = sqlite3.connect(legacy)
    conn.executescript(
        "CREATE TABLE expenses (id INTEGER PRIMARY KEY, amount INTEGER, date TEXT, category TEXT,"
        " note TEXT, recurring_id INTEGER);"
        "INSERT INTO expenses (amount, date, category, note) VALUES (500, '2026-01-01', 'food', 'old');"
    )
    conn.commit()
    conn.close()
    monkeypatch.setenv("BUDGET_DB", str(legacy))
    reloaded = importlib.reload(main)
    try:
        conn = sqlite3.connect(legacy)
        assert conn.execute("SELECT COUNT(*) FROM legacy_expenses").fetchone()[0] == 1
        assert "user_id" in [r[1] for r in conn.execute("PRAGMA table_info(expenses)")]
        conn.close()
        c = TestClient(reloaded.app)
        r = c.post("/auth/register", json={"username": "newcomer", "password": PASSWORD})
        assert r.status_code == 201
        h = {"Authorization": f"Bearer {r.json()['token']}"}
        assert c.get("/expenses", headers=h).json() == []  # old rows belong to nobody
    finally:
        monkeypatch.setenv("BUDGET_DB", original_db)
        importlib.reload(main)


# ------------------------------------------------------------ hard limits
def _expense(amount, **over):
    body = {"amount": amount, "date": "2026-10-03", "category": "food", "note": ""}
    body.update(over)
    return body


@pytest.mark.parametrize("amount", [10**10 + 0.01, 1e18, 9.3e16, "1e1000000", "99999999999999999999.99"])
def test_amounts_beyond_the_cap_are_refused_not_a_server_error(user, amount):
    assert client.post("/expenses", json=_expense(amount), headers=user).status_code == 422


def test_the_largest_allowed_amount_still_works_and_totals_stay_sane(user):
    for _ in range(3):
        assert client.post("/expenses", json=_expense(10**10), headers=user).status_code == 201
    assert client.get("/dashboard?month=2026-10", headers=user).json()["total_spent"] == 3 * 10**10


def test_two_huge_templates_cannot_break_the_account(user):
    big = {"amount": 10**10, "category": "big", "day_of_month": 1}
    for _ in range(2):
        assert client.post("/recurring", json=big, headers=user).status_code == 201
    assert client.post("/recurring/apply?month=2026-10", headers=user).json()["created"] == 2
    assert client.get("/account", headers=user).status_code == 200
    assert client.get("/dashboard?month=2026-10", headers=user).status_code == 200


def test_validation_errors_never_echo_unserialisable_input(user):
    raw = '{"amount": NaN, "date": "2026-10-03", "category": "x"}'
    r = client.post("/expenses", content=raw, headers={**user, "Content-Type": "application/json"})
    assert r.status_code == 422 and "detail" in r.json()
    surrogate = r'{"amount": 5, "date": "2026-10-03", "category": "\ud800"}'  # a lone surrogate, JSON-escaped
    r = client.post("/expenses", content=surrogate, headers={**user, "Content-Type": "application/json"})
    assert r.status_code == 422


def test_ids_outside_the_integer_range_are_rejected_cleanly(user):
    for path in ("/expenses/99999999999999999999", "/goals/9223372036854775808", "/recurring/0"):
        assert client.delete(path, headers=user).status_code in (404, 422)


def test_text_and_body_limits(user):
    assert client.post("/expenses", json=_expense(5, category="c" * 61), headers=user).status_code == 422
    assert client.post("/expenses", json=_expense(5, category="c" * 60), headers=user).status_code == 201
    assert client.post("/expenses", json=_expense(5, note="n" * 501), headers=user).status_code == 422
    assert client.post("/expenses", json=_expense(5, note="n" * 20000), headers=user).status_code == 413


def test_month_must_be_a_real_calendar_month(user):
    assert client.post("/recurring/apply?month=0000-01", headers=user).status_code == 422
    assert client.post("/recurring/apply?month=2026-13", headers=user).status_code == 422
    assert client.post("/recurring/apply?month=0001-01", headers=user).status_code == 200


def test_day_of_month_must_be_a_number_not_a_boolean(user):
    body = {"amount": 5, "category": "x", "day_of_month": True}
    assert client.post("/recurring", json=body, headers=user).status_code == 422


def test_recurring_apply_adds_one_expense_per_template_and_month(user):
    tid = client.post("/recurring", json={"amount": 100, "category": "rent", "day_of_month": 5}, headers=user).json()["id"]
    assert client.post("/recurring/apply?month=2026-11", headers=user).json()["created"] == 1
    # the user moves it to another day: applying again must not add a second one
    eid = client.get("/expenses?month=2026-11", headers=user).json()[0]["id"]
    moved = _expense(100, date="2026-11-20", category="rent")
    assert client.put(f"/expenses/{eid}", json=moved, headers=user).status_code == 200
    assert client.post("/recurring/apply?month=2026-11", headers=user).json()["created"] == 0
    # but if the expense is deleted, applying fills the gap again
    assert client.delete(f"/expenses/{eid}", headers=user).status_code == 204
    assert client.post("/recurring/apply?month=2026-11", headers=user).json()["created"] == 1
    assert tid


def test_moving_a_generated_expense_onto_its_sibling_is_a_conflict_not_a_crash(user):
    client.post("/recurring", json={"amount": 100, "category": "rent", "day_of_month": 5}, headers=user)
    client.post("/recurring/apply?month=2026-11", headers=user)
    client.post("/recurring/apply?month=2026-12", headers=user)
    dec = client.get("/expenses?month=2026-12", headers=user).json()[0]
    clash = _expense(100, date="2026-11-05", category="rent")
    assert client.put(f"/expenses/{dec['id']}", json=clash, headers=user).status_code == 409


def test_category_filter_trims_like_writes_do(user):
    client.post("/expenses", json=_expense(5, category=" Food "), headers=user)
    assert len(client.get("/expenses?category=%20food%20", headers=user).json()) == 1


def test_a_nul_byte_in_a_path_is_not_found_not_a_crash(tmp_path, monkeypatch):
    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<!doctype html><title>x</title>")
    monkeypatch.setenv("WEB_DIR", str(web))
    reloaded = importlib.reload(main)
    try:
        c = TestClient(reloaded.app)
        assert c.get("/%00").status_code == 404
        assert c.get("/").status_code == 200
    finally:
        monkeypatch.undo()
        importlib.reload(main)
