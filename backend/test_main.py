import os
import tempfile

os.environ["BUDGET_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["WEB_DIR"] = os.path.join(tempfile.mkdtemp(), "no-web")  # tests run API-only

from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402

client = TestClient(app)


def test_expense_budget_dashboard_flow():
    client.put("/budgets", json={"category": "Food", "month": "2026-10", "cap": 100})
    r = client.post("/expenses", json={"amount": 60.10, "date": "2026-10-03", "category": "Food"})
    assert r.status_code == 201 and r.json()["alert"] is None
    r = client.post("/expenses", json={"amount": 55, "date": "2026-10-04", "category": "food"})
    assert r.json()["alert"]["over_by"] == 15.1

    d = client.get("/dashboard", params={"month": "2026-10"}).json()
    assert d["total_spent"] == 115.1
    assert d["categories"][0] == {"category": "food", "spent": 115.1, "cap": 100.0, "over": True}
    assert len(d["trend"]) == 2


def test_validation_and_404():
    assert client.post("/expenses", json={"amount": -1, "date": "2026-10-03", "category": "x"}).status_code == 422
    assert client.delete("/expenses/9999").status_code == 404


def test_low_balance_and_goals():
    client.put("/account", json={"opening_balance": 1000, "low_balance_threshold": 300})
    base = client.get("/account").json()["balance"]  # opening minus earlier test expenses
    g = client.post("/goals", json={"name": "Headphones", "target": 500}).json()
    r = client.post(f"/goals/{g['id']}/contribute", json={"amount": 100.25}).json()
    assert r["goal"]["saved"] == 100.25 and r["goal"]["progress"] == 0.2005
    assert r["balance"] == round(base - 100.25, 2)
    big = client.post("/expenses", json={"amount": 900, "date": "2026-10-05", "category": "misc"}).json()
    assert big["low_balance"] is True
    assert client.get("/goals").json()[0]["name"] == "Headphones"
    assert client.delete(f"/goals/{g['id']}").status_code == 204


def test_recurring_is_idempotent():
    t = client.post("/recurring", json={"amount": 499, "category": "Subscriptions",
                                        "note": "music", "day_of_month": 5}).json()
    assert client.post("/recurring/apply", params={"month": "2026-11"}).json()["created"] == 1
    assert client.post("/recurring/apply", params={"month": "2026-11"}).json()["created"] == 0
    rows = client.get("/expenses", params={"month": "2026-11"}).json()
    assert rows[0]["amount"] == 499 and rows[0]["date"] == "2026-11-05"
    assert client.delete(f"/recurring/{t['id']}").status_code == 204


def test_month_params_are_validated():
    assert client.post("/recurring/apply", params={"month": "2026-13"}).status_code == 422
    assert client.post("/recurring/apply", params={"month": "abcd-ef7"}).status_code == 422
    assert client.get("/dashboard", params={"month": "2026-1"}).status_code == 422
    assert client.get("/budgets", params={"month": "nope"}).status_code == 422
    assert client.get("/expenses", params={"month": "2026-00"}).status_code == 422
    # no expense with an impossible date was created by the rejected calls
    assert client.get("/expenses", params={"month": "2026-13"}).status_code == 422


def test_blank_names_are_rejected_and_trimmed():
    bad = {"amount": 5, "date": "2026-10-03", "category": "   "}
    assert client.post("/expenses", json=bad).status_code == 422
    assert client.put("/budgets", json={"category": " ", "month": "2026-10", "cap": 1}).status_code == 422
    assert client.post("/recurring", json={"amount": 1, "category": " ", "day_of_month": 1}).status_code == 422
    assert client.post("/goals", json={"name": "  ", "target": 10}).status_code == 422
    r = client.post("/expenses", json={"amount": 5, "date": "2026-09-03", "category": "  Tea "}).json()
    assert r["expense"]["category"] == "tea"


def test_update_expense_and_filters():
    e = client.post("/expenses", json={"amount": 10, "date": "2026-08-01", "category": "Snacks"}).json()["expense"]
    r = client.put(f"/expenses/{e['id']}", json={"amount": 12.5, "date": "2026-08-02",
                                                  "category": "SNACKS", "note": "edited"})
    assert r.status_code == 200 and r.json()["amount"] == 12.5 and r.json()["category"] == "snacks"
    assert client.put("/expenses/99999", json={"amount": 1, "date": "2026-08-02", "category": "x"}).status_code == 404
    rows = client.get("/expenses", params={"month": "2026-08", "category": "Snacks"}).json()
    assert [x["note"] for x in rows] == ["edited"]
    assert client.get("/expenses", params={"month": "2026-08", "category": "nothing"}).json() == []


def test_budget_upsert_and_amount_precision():
    client.put("/budgets", json={"category": "Rent", "month": "2027-01", "cap": 100})
    client.put("/budgets", json={"category": "rent", "month": "2027-01", "cap": 250.5})
    assert client.get("/budgets", params={"month": "2027-01"}).json() == [
        {"category": "rent", "month": "2027-01", "cap": 250.5}]
    # more than 2 decimal places is rejected, not silently rounded
    assert client.post("/expenses", json={"amount": 1.005, "date": "2027-01-01", "category": "x"}).status_code == 422
    # 0.1 + 0.2 style amounts stay exact in paise
    for amt in (0.1, 0.2):
        client.post("/expenses", json={"amount": amt, "date": "2027-02-01", "category": "tiny"})
    assert client.get("/dashboard", params={"month": "2027-02"}).json()["total_spent"] == 0.3


def test_recurring_per_month_and_goal_progress_clamped():
    t = client.post("/recurring", json={"amount": 20, "category": "Gym", "day_of_month": 28}).json()
    assert client.post("/recurring/apply", params={"month": "2027-03"}).json()["created"] == 1
    assert client.post("/recurring/apply", params={"month": "2027-04"}).json()["created"] == 1
    assert client.post("/recurring/apply", params={"month": "2027-04"}).json()["created"] == 0
    assert client.get("/expenses", params={"month": "2027-03"}).json()[0]["date"] == "2027-03-28"
    assert client.delete(f"/recurring/{t['id']}").status_code == 204
    assert client.delete(f"/recurring/{t['id']}").status_code == 404

    g = client.post("/goals", json={"name": "Trip", "target": 100}).json()
    r = client.post(f"/goals/{g['id']}/contribute", json={"amount": 150}).json()
    assert r["goal"]["progress"] == 1.0 and r["goal"]["saved"] == 150
    assert client.post("/goals/99999/contribute", json={"amount": 1}).status_code == 404
    assert client.post(f"/goals/{g['id']}/contribute", json={"amount": 0}).status_code == 422
    client.delete(f"/goals/{g['id']}")


def test_account_validation_and_low_balance_threshold_zero_disables_warning():
    assert client.put("/account", json={"opening_balance": -1, "low_balance_threshold": 0}).status_code == 422
    r = client.put("/account", json={"opening_balance": 0, "low_balance_threshold": 0}).json()
    assert r["low_balance"] is False


def test_root_and_head_for_health_probes():
    assert client.get("/").json() == {"name": "Budget Tracker API", "docs": "/docs"}
    assert client.head("/").status_code == 200


def test_serves_the_web_app_when_present(tmp_path, monkeypatch):
    """With a compiled web app next to the API (the Docker image), "/" is the app and the API still works."""
    import importlib

    import main as main_module

    (tmp_path / "index.html").write_text("<html>the app</html>")
    (tmp_path / "main.dart.js").write_text("console.log('js')")
    monkeypatch.setenv("WEB_DIR", str(tmp_path))
    reloaded = importlib.reload(main_module)
    try:
        c = TestClient(reloaded.app)
        assert c.get("/").text == "<html>the app</html>"
        assert c.head("/").status_code == 200
        assert c.get("/main.dart.js").text == "console.log('js')"
        assert c.get("/missing-file.js").status_code == 404
        # API routes registered before the static mount still win
        assert c.get("/account").json()["balance"] is not None
        assert c.get("/dashboard", params={"month": "2026-10"}).status_code == 200
        assert c.get("/docs").status_code == 200
    finally:
        monkeypatch.delenv("WEB_DIR")
        importlib.reload(main_module)
