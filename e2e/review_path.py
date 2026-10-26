"""The review walkthrough, performed in a real browser on the review account.

    REVIEW_PASSWORD=... BASE_URL=https://<your-app>/ python e2e/review_path.py

The account is created and seeded by backend/seed_review.py (which also resets it:
`python backend/seed_review.py reset`). The path: dashboard, add Food 4,500 (over
budget), edit it to 1,000 (alert cleared), budgets, apply Netflix twice (no
duplicate), contribute 1,000 to Laptop, log out. REVIEW_USER defaults to "review".
"""
import datetime
import os
import sys

from playwright.sync_api import sync_playwright

from common import open_app

USER = os.environ.get("REVIEW_USER", "review")
PASSWORD = os.environ["REVIEW_PASSWORD"]
MONTH = "October 2026"  # the month the review data lives in

results = []
_app = None


def step(name, ok):
    results.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    if not ok and _app is not None:
        _app.shot(f"fail-{len(results):02d}.png")
        print("     page text:", _app.text()[:300], flush=True)


def go_to_month(app):
    """The app opens on today's month; walk to the month the review data is in."""
    today = datetime.date.today()
    delta = (today.year - 2026) * 12 + today.month - 10  # months after October 2026
    for _ in range(abs(delta)):
        app.month_prev() if delta > 0 else app.month_next()


with sync_playwright() as p:
    browser, app, errors = open_app(p)
    _app = app

    app.log_in(USER, PASSWORD)
    go_to_month(app)
    step("dashboard: starting balance, no alerts",
         app.has(MONTH) and app.has("You have ₹43,020 left") and app.gone("Low balance"))
    app.shot("review-01-dashboard.png")

    app.tab("Expenses")
    app.button("Add expense")
    app.fill("Amount", "4500")
    app.fill("Category", "Food")
    app.fill("Note", "Team dinner")
    app.save()
    step("add Food ₹4,500: over-budget alert", app.has("Over budget in food by ₹610"))
    app.shot("review-02-over-budget.png")
    app.snack_gone()

    app.tab("Dashboard")
    app.tab("Expenses")  # the accessibility tree can lag a freshly added row
    app.button("Edit Food ₹4,500")
    app.fill("Amount", "1000")
    app.save()
    step("edit it to ₹1,000: alert cleared", app.has("Updated Food ₹1,000") and app.gone("Over budget in food"))
    app.snack_gone()

    app.tab("Budgets")
    step("budgets: Food, Transport, Fun, Bills",
         app.has("Food") and app.has("Transport") and app.has("Fun") and app.has("Bills") and app.has("₹6,000"))
    app.shot("review-03-budgets.png")

    app.tab("Recurring")
    app.button(f"Apply to {MONTH}")
    step("apply Netflix: one expense added", app.has(f"Added 1 expense to {MONTH}"))
    app.snack_gone()
    app.button(f"Apply to {MONTH}")
    step("apply again: nothing to add (no duplicate)", app.has("Nothing to add"))
    app.snack_gone()
    app.tab("Expenses")
    step("exactly one Netflix expense", app.has("Netflix (1)"))  # the category filter counts them

    app.tab("Goals")
    app.button("Add money to Laptop")
    app.fill("Amount", "1000")
    app.save()
    step("contribute ₹1,000 to Laptop", app.has("Added ₹1,000 to Laptop") and app.has("₹3,000 of ₹60,000"))
    app.shot("review-04-goal.png")

    app.log_out()
    step("log out", app.has("Know where your money goes."))

    bad = [e for e in errors if "CORS" in e or "Failed to fetch" in e or "Uncaught" in e]
    step("browser console: no errors", not bad)
    browser.close()

failed = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed else 0)
