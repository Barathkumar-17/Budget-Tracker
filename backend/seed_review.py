"""A separate account for reviewing the app, seeded with a known October 2026.

It never touches the shared `demo` account or anyone else's data, and it works
through the public API only. The password is read from the REVIEW_PASSWORD
environment variable or typed at a hidden prompt; it is never printed or saved.

    python backend/seed_review.py setup         # create or complete the account (safe to repeat)
    python backend/seed_review.py verify        # check the starting totals
    python backend/seed_review.py walkthrough   # run the rehearsal steps through the API
    python backend/seed_review.py reset         # undo a rehearsal: back to the starting state

Settings (environment): BASE_URL (default: the hosted app), REVIEW_USER (default: review),
REVIEW_PASSWORD (else a hidden prompt). The container runs `setup` at start when
REVIEW_PASSWORD is set, so the account survives the free tier's disk wipes.
"""
import getpass
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("BASE_URL", "https://budget-tracker-8n5q.onrender.com").rstrip("/")
USER = os.environ.get("REVIEW_USER", "review")
MONTH = "2026-10"

ACCOUNT = {"opening_balance": 50000, "low_balance_threshold": 5000}
BUDGETS = {"food": 6000, "transport": 2500, "fun": 3000, "bills": 5000}
# (date, category, amount, note): the past two weeks of October
EXPENSES = [
    ("2026-10-13", "food", 450, "Canteen lunch"),
    ("2026-10-14", "transport", 150, "Metro card top-up"),
    ("2026-10-15", "bills", 1200, "Mobile and broadband"),
    ("2026-10-17", "food", 320, "Breakfast and chai"),
    ("2026-10-18", "fun", 600, "Movie night"),
    ("2026-10-19", "transport", 300, "Cab to the station"),
    ("2026-10-21", "food", 780, "Weekly groceries"),
    ("2026-10-23", "transport", 220, "Auto to college"),
    ("2026-10-24", "fun", 400, "Gaming cafe"),
    ("2026-10-25", "food", 560, "Dinner with friends"),
]
NETFLIX = {"amount": 299, "category": "Netflix", "note": "Netflix subscription", "day_of_month": 5}
GOAL_NAME, GOAL_TARGET, GOAL_START = "Laptop", 60000, 2000

# what the opening dashboard must show
SPENT = {"food": 2110, "transport": 670, "fun": 1000, "bills": 1200}
TOTAL_SPENT = sum(SPENT.values())  # 4980
START_BALANCE = ACCOUNT["opening_balance"] - TOTAL_SPENT - GOAL_START  # 43020

token = None


def call(method, path, body=None, auth=True, ok=(200, 201, 204)):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if auth and token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            payload = json.loads(raw)
        except ValueError:
            payload = {"detail": f"HTTP {e.code}"}
        if e.code in ok:
            return e.code, payload
        return e.code, payload


def need(status, payload, what, good=(200, 201, 204)):
    if status not in good:
        sys.exit(f"{what} failed: {status} {payload}")
    return payload


def password(confirm):
    pw = os.environ.get("REVIEW_PASSWORD")
    if pw:
        return pw
    pw = getpass.getpass(f"Password for '{USER}' (hidden): ")
    if confirm and getpass.getpass("Again: ") != pw:
        sys.exit("The passwords differ.")
    return pw


def sign_in(create):
    """Log in; with create=True register the account first if it does not exist."""
    global token
    pw = password(confirm=create and not os.environ.get("REVIEW_PASSWORD"))
    status, payload = call("POST", "/auth/login", {"username": USER, "password": pw}, auth=False)
    if status == 200:
        token = payload["token"]
        return
    if status == 401 and create:
        status, payload = call("POST", "/auth/register", {"username": USER, "password": pw}, auth=False)
        if status == 201:
            token = payload["token"]
            print(f"created account '{USER}'")
            return
        if status == 409:
            sys.exit(f"'{USER}' already exists with a different password.")
    sys.exit(f"could not sign in as '{USER}': {status} {payload.get('detail')}")


def goals():
    return need(*call("GET", "/goals"), "list goals")


def laptop():
    return next((g for g in goals() if g["name"] == GOAL_NAME), None)


def ensure_goal():
    g = laptop()
    if g is None:
        g = need(*call("POST", "/goals", {"name": GOAL_NAME, "target": GOAL_TARGET}), "add goal")
    if g["saved"] < GOAL_START:  # the normal contribution flow
        need(*call("POST", f"/goals/{g['id']}/contribute", {"amount": GOAL_START - g["saved"]}), "contribute")


def seeded(e):
    return (e["date"], e["category"], round(e["amount"]), e["note"])


def setup():
    sign_in(create=True)
    need(*call("PUT", "/account", ACCOUNT), "account")
    for cat, cap in BUDGETS.items():
        need(*call("PUT", "/budgets", {"category": cat, "month": MONTH, "cap": cap}), f"budget {cat}")
    have = {seeded(e) for e in need(*call("GET", f"/expenses?month={MONTH}"), "list expenses")}
    added = 0
    for date, cat, amount, note in EXPENSES:
        if (date, cat, amount, note) not in have:
            need(*call("POST", "/expenses", {"amount": amount, "date": date, "category": cat, "note": note}), "add expense")
            added += 1
    templates = need(*call("GET", "/recurring"), "list recurring")
    if not any(t["category"] == "netflix" and round(t["amount"]) == NETFLIX["amount"] for t in templates):
        need(*call("POST", "/recurring", NETFLIX), "add template")
    ensure_goal()
    print(f"seeded ({added} new expenses)")
    verify(sign=False)


def verify(sign=True):
    if sign:
        sign_in(create=False)
    d = need(*call("GET", f"/dashboard?month={MONTH}"), "dashboard")
    cats = {c["category"]: c for c in d["categories"]}
    problems = []
    if round(d["total_spent"]) != TOTAL_SPENT:
        problems.append(f"total spent {d['total_spent']} (expected {TOTAL_SPENT})")
    if round(d["balance"]) != START_BALANCE:
        problems.append(f"balance {d['balance']} (expected {START_BALANCE})")
    if d["low_balance"]:
        problems.append("low-balance warning is on")
    for cat, want in SPENT.items():
        c = cats.get(cat)
        if not c or round(c["spent"]) != want or round(c["cap"]) != BUDGETS[cat] or c["over"]:
            problems.append(f"{cat}: {c}")
    g = laptop()
    if not g or round(g["saved"]) != GOAL_START:
        problems.append(f"Laptop saved {g and g['saved']} (expected {GOAL_START})")
    if problems:
        sys.exit("NOT at the starting state:\n  " + "\n  ".join(problems))
    print(f"starting state OK: spent Rs {TOTAL_SPENT:,}, balance Rs {START_BALANCE:,}, "
          f"Laptop Rs {GOAL_START:,} of Rs {GOAL_TARGET:,}, no alerts")


def walkthrough():
    sign_in(create=False)
    verify(sign=False)
    s, p = call("POST", "/expenses", {"amount": 4500, "date": "2026-10-26", "category": "Food", "note": "Team dinner"})
    need(s, p, "add Food 4500")
    assert p["alert"] and round(p["alert"]["over_by"]) == 610, p["alert"]
    print("add Food Rs 4,500   -> over budget by Rs", round(p["alert"]["over_by"]))
    s, p = call("PUT", f"/expenses/{p['expense']['id']}", {"amount": 1000, "date": "2026-10-26", "category": "Food", "note": "Team dinner"})
    need(s, p, "edit to 1000")
    assert p["alert"] is None, p["alert"]
    print("edit it to Rs 1,000 -> alert cleared")
    caps = {b["category"]: b["cap"] for b in need(*call("GET", f"/budgets?month={MONTH}"), "budgets")}
    print("budgets             ->", ", ".join(f"{k} {int(v):,}" for k, v in caps.items()))
    first = need(*call("POST", f"/recurring/apply?month={MONTH}"), "apply 1")["created"]
    second = need(*call("POST", f"/recurring/apply?month={MONTH}"), "apply 2")["created"]
    assert (first, second) == (1, 0), (first, second)
    print("apply Netflix twice -> created", first, "then", second)
    s, p = call("POST", f"/goals/{laptop()['id']}/contribute", {"amount": 1000})
    need(s, p, "contribute")
    print("contribute Rs 1,000 -> Laptop", f"{p['goal']['saved']:,.0f}", "of", f"{p['goal']['target']:,.0f}")
    call("POST", "/auth/logout")
    print("logged out")


def reset():
    """Undo a rehearsal: drop every October expense that is not part of the seed
    (the walkthrough's Food and the Netflix one), and put Laptop back to its start."""
    sign_in(create=False)
    keep = set(EXPENSES)
    removed = 0
    for e in need(*call("GET", f"/expenses?month={MONTH}"), "list expenses"):
        if (e["date"], e["category"], round(e["amount"]), e["note"]) not in keep:
            need(*call("DELETE", f"/expenses/{e['id']}"), "delete expense")
            removed += 1
    g = laptop()
    if g and round(g["saved"]) != GOAL_START:  # there is no withdrawal: recreate the goal
        need(*call("DELETE", f"/goals/{g['id']}"), "delete goal")
        ensure_goal()
    print(f"reset: removed {removed} expense(s)")
    verify(sign=False)


if __name__ == "__main__":
    cmds = {"setup": setup, "verify": verify, "walkthrough": walkthrough, "reset": reset}
    if len(sys.argv) != 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    cmds[sys.argv[1]]()
