import os
import tempfile

os.environ["BUDGET_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

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
