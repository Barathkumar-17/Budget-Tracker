"""Fill a demo account with realistic data through the public API.

    python seed_demo.py                       # API at http://127.0.0.1:8000
    python seed_demo.py --api http://host:8000
    python seed_demo.py --username me --password "a long password"
    python seed_demo.py --force               # add even if the account already has data

Creates the account if it does not exist (otherwise logs in), then fills the
current month. Uses only the standard library. Dates are relative to today, so
the dashboard for the current month always has data.
"""
import argparse
import datetime
import json
import sys
import urllib.error
import urllib.request


def call(api, method, path, body=None, token=None, expect=(200, 201, 204)):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        api + path,
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        if e.code in expect:
            return e.code, None
        sys.exit(f"{method} {path} failed: {e.code} {raw}")
    except urllib.error.URLError as e:
        sys.exit(f"Cannot reach the API at {api}: {e.reason}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api", default="http://127.0.0.1:8000")
    ap.add_argument("--username", default="demo")
    ap.add_argument("--password", default="demo-password")
    ap.add_argument("--force", action="store_true", help="seed even if the account already has data")
    args = ap.parse_args()
    api = args.api.rstrip("/")

    creds = {"username": args.username, "password": args.password}
    status, session = call(api, "POST", "/auth/register", creds, expect=(409,))
    if status == 409:  # the account exists: log in instead
        _, session = call(api, "POST", "/auth/login", creds, expect=(401,))
        if session is None:
            sys.exit(f"The account '{args.username}' exists but that password is wrong.")
    token = session["token"]

    def get(path):
        return call(api, "GET", path, token=token)[1]

    def send(method, path, body=None):
        return call(api, method, path, body, token=token)[1]

    if not args.force and (get("/expenses") or get("/goals")):
        sys.exit(f"The account '{args.username}' already has data. Use another --username, or pass --force.")

    today = datetime.date.today()
    month = today.strftime("%Y-%m")

    send("PUT", "/account", {"opening_balance": 30000, "low_balance_threshold": 5000})

    for category, cap in {"food": 1500, "transport": 400, "fun": 1500}.items():
        send("PUT", "/budgets", {"category": category, "month": month, "cap": cap})

    # (days ago, amount, category, note) - clamped to the 1st so everything stays in this month
    for ago, amount, category, note in [
        (0, 180, "Food", "Lunch"),
        (1, 90, "Transport", "Metro card"),
        (2, 420, "Food", "Groceries"),
        (3, 250, "Fun", "Movie"),
        (4, 640, "Food", "Dinner out"),
        (6, 120, "Transport", "Cab"),
        (8, 300, "Food", "Snacks"),
        (9, 1500, "Fun", "Concert"),
        (11, 75, "Transport", "Bus"),
    ]:
        day = today.replace(day=max(1, today.day - ago))
        send("POST", "/expenses",
             {"amount": amount, "date": day.isoformat(), "category": category, "note": note})

    for amount, category, note, day in [(8000, "Rent", "Hostel rent", 1),
                                        (499, "Netflix", "Subscription", 5),
                                        (700, "Gym", "Membership", 10)]:
        send("POST", "/recurring",
             {"amount": amount, "category": category, "note": note, "day_of_month": day})
    created = send("POST", f"/recurring/apply?month={month}")["created"]

    for name, target, saved in [("Laptop", 60000, 9000), ("Trip", 20000, 4000)]:
        goal = send("POST", "/goals", {"name": name, "target": target})
        send("POST", f"/goals/{goal['id']}/contribute", {"amount": saved})

    acc = get("/account")
    print(f"Seeded {month} for '{args.username}': 9 expenses + {created} recurring, 3 budgets, 2 goals.")
    print(f"Balance Rs {acc['balance']:.2f} (low-balance warning below Rs {acc['low_balance_threshold']:.2f}).")
    print(f"Log in with username '{args.username}' and password '{args.password}'.")
    print("Food and fun are over budget; open the Dashboard to see the alerts.")


if __name__ == "__main__":
    main()
