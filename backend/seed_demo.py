"""Fill a fresh Budget Tracker database with demo data through the public API.

    python seed_demo.py                       # API at http://127.0.0.1:8000
    python seed_demo.py --api http://host:8000
    python seed_demo.py --force               # add even if data already exists

Uses only the standard library. Dates are relative to today, so the dashboard
for the current month always has data.
"""
import argparse
import datetime
import json
import sys
import urllib.error
import urllib.request


def call(api, method, path, body=None):
    req = urllib.request.Request(
        api + path,
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} failed: {e.code} {e.read().decode()}")
    except urllib.error.URLError as e:
        sys.exit(f"Cannot reach the API at {api}: {e.reason}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api", default="http://127.0.0.1:8000")
    ap.add_argument("--force", action="store_true", help="seed even if the database already has data")
    args = ap.parse_args()
    api = args.api.rstrip("/")

    if not args.force and (call(api, "GET", "/expenses") or call(api, "GET", "/goals")):
        sys.exit("The database already has data. Use a fresh database, or pass --force.")

    today = datetime.date.today()
    month = today.strftime("%Y-%m")

    call(api, "PUT", "/account", {"opening_balance": 30000, "low_balance_threshold": 5000})

    for category, cap in {"food": 1500, "transport": 400, "fun": 1500}.items():
        call(api, "PUT", "/budgets", {"category": category, "month": month, "cap": cap})

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
        call(api, "POST", "/expenses",
             {"amount": amount, "date": day.isoformat(), "category": category, "note": note})

    for amount, category, note, day in [(8000, "Rent", "Hostel rent", 1),
                                        (499, "Netflix", "Subscription", 5),
                                        (700, "Gym", "Membership", 10)]:
        call(api, "POST", "/recurring",
             {"amount": amount, "category": category, "note": note, "day_of_month": day})
    created = call(api, "POST", f"/recurring/apply?month={month}")["created"]

    for name, target, saved in [("Laptop", 60000, 9000), ("Trip", 20000, 4000)]:
        goal = call(api, "POST", "/goals", {"name": name, "target": target})
        call(api, "POST", f"/goals/{goal['id']}/contribute", {"amount": saved})

    acc = call(api, "GET", "/account")
    print(f"Seeded {month}: 9 expenses + {created} recurring, 3 budgets, 2 goals.")
    print(f"Balance Rs {acc['balance']:.2f} (low-balance warning below Rs {acc['low_balance_threshold']:.2f}).")
    print("Food and fun are over budget; open the Dashboard to see the alerts.")


if __name__ == "__main__":
    main()
