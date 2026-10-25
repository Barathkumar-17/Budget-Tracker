"""The README "demo tour", performed exactly as a person would and asserted step by step.

Start the backend on a FRESH database, seed the demo account, then run the tour:

    cd backend && uvicorn main:app --port 8000      # serves the built app at /
    python seed_demo.py                              # creates demo / demo-password
    BASE_URL=http://127.0.0.1:8000/ python e2e/demo_tour.py

The tour changes the demo account (spends money, moves goals, edits a budget), so re-create
the database before every run. Desktop size by default (1280x800, screenshots at scale 1);
set VIEWPORT_W=390 VIEWPORT_H=844 for a phone and SHOTS=<dir> to keep the pictures apart.
Screenshots go to $SHOTS (default docs/img/tour). Exits non-zero if any step fails.
"""
import datetime
import os
import sys

# SHOTS is read when common is imported, so choose its default before that import.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("SHOTS", os.path.join(ROOT, "docs", "img", "tour"))

from playwright.sync_api import sync_playwright  # noqa: E402

from common import open_app  # noqa: E402

results = []
_app = None  # set once the browser is open, so a failing step can snapshot the screen


def step(name, ok):
    results.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    if not ok and _app is not None:
        _app.shot(f"fail-{len(results):02d}.png")
        print("     page text:", _app.text()[:400], flush=True)


today = datetime.date.today()
this_month = today.strftime("%B %Y")
prev_month = (today.replace(day=1) - datetime.timedelta(days=1)).strftime("%B %Y")

width = int(os.environ.get("VIEWPORT_W", "1280"))
height = int(os.environ.get("VIEWPORT_H", "800"))

with sync_playwright() as p:
    browser, app, errors = open_app(p, width=width, height=height, scale=1)
    _app = app

    # ---------------- 1. Landing -> login -> demo account ----------------
    step("1 landing: 'Know where your money goes.'", app.has("Know where your money goes."))
    app.shot("tour-01-landing.png")
    app.button("Log in")
    step("1 landing: Log in opens the login form", app.has("Welcome back"))
    app.shot("tour-02-login.png")
    app.button("Use demo account")
    step("1 login: Use demo account lands on the dashboard", app.has("Hi, Demo"))

    # ---------------- 2. Dashboard as seeded ----------------
    app.wait(1500)
    step("2 dashboard: state sentence", app.has("You have ₹4,226 left, ₹774 below your safety line."))
    step("2 dashboard: low-balance banner",
         app.has("Low balance: ₹4,226 left, ₹774 below your ₹5,000 safety line."))
    # Food: 180+420+640+300 = 1540 of 1500; Fun: 250+1500 = 1750 of 1500; Transport 285 of 400.
    step("2 dashboard: Food over budget by ₹40", app.has("₹1,540 of ₹1,500") and app.has("₹40 over budget"))
    step("2 dashboard: Fun over budget by ₹250", app.has("₹1,750 of ₹1,500") and app.has("₹250 over budget"))
    step("2 dashboard: Transport still has room", app.has("₹285 of ₹400"))
    app.shot("tour-03-dashboard.png")

    # ---------------- 3. Balance settings ----------------
    app.button("Balance settings")
    step("3 settings: dialog opens", app.has("Opening balance"))
    app.shot("tour-04-balance-settings.png")
    app.fill("Opening balance", "40000")
    app.save()
    step("3 settings: opening 40000 -> 'above your safety line'",
         app.has("You have ₹14,226 left, ₹9,226 above your safety line."))
    step("3 settings: low-balance banner is gone", app.gone("Low balance:"))
    app.shot("tour-05-balance-raised.png")

    # ---------------- 4. Month arrows ----------------
    app.month_prev()
    step("4 months: previous arrow shows " + prev_month, app.has(prev_month))
    app.shot("tour-06-previous-month.png")
    app.month_next()
    step("4 months: next arrow returns to " + this_month, app.has(this_month))

    # ---------------- 5. Add a 500 Food expense -> overspend alert ----------------
    app.tab("Expenses")
    app.button("Add expense")
    step("5 expenses: add dialog opens", app.has("Amount") and app.has("Category"))
    app.fill("Amount", "500")
    app.button("Food")  # the category pill under the Category field
    app.shot("tour-07-add-expense.png")
    app.save()
    step("5 expenses: alert 'Over budget in food by ₹540'", app.has("Over budget in food by ₹540"))
    app.shot("tour-08-overspend-alert.png")
    app.snack_gone()

    # ---------------- 6. Remove -> Undo ----------------
    # Flutter web's accessibility DOM can lag a freshly added row; re-open the tab so it is there.
    app.tab("Dashboard")
    app.tab("Expenses")
    app.button("Remove Food ₹500")
    step("6 expenses: Remove deletes the row and offers Undo",
         app.has("Deleted Food ₹500") and app.has("Undo") and app.gone("Edit Food ₹500", 3000))
    app.shot("tour-09-removed-undo.png")
    app.snack_action("Undo")
    app.tab("Dashboard")  # same lag after the row comes back
    app.tab("Expenses")
    step("6 expenses: Undo brings the row back", app.count(r"^Edit Food ₹500") == 1)
    app.snack_gone()

    # ---------------- 7. Edit the row ----------------
    app.button("Edit Food ₹500")
    step("7 expenses: Edit opens the expense", app.has("Edit expense"))
    app.fill("Amount", "300")
    app.save()
    # Food is still over its 1,500 cap (1,540 + 300), so saving re-runs the budget check.
    step("7 expenses: edited to 300 and the budget is checked again",
         app.has("Over budget in food by ₹340") and app.has("Edit Food ₹300"))
    app.shot("tour-10-edited.png")
    app.snack_gone()

    # ---------------- 8. Raise the Food budget, add 500 again: no alert ----------------
    app.tab("Budgets")
    app.button("Change Food budget")
    step("8 budgets: Change opens the dialog", app.has("Change budget"))
    app.fill("Monthly cap", "3000")
    app.save()
    step("8 budgets: Food cap is now ₹3,000", app.has("₹3,000"))
    app.shot("tour-11-food-budget.png")
    app.tab("Expenses")
    app.button("Add expense")
    app.fill("Amount", "500")
    app.button("Food")
    app.save()
    step("8 expenses: the same 500 Food expense is added", app.has("Added Food ₹500") or app.count(r"^Edit Food ₹500") == 1)
    step("8 expenses: no 'Over budget' alert any more", app.gone("Over budget in food"))
    app.shot("tour-12-no-alert.png")
    app.snack_gone()

    # ---------------- 9. Recurring: apply twice, bad day ----------------
    app.tab("Recurring")
    app.button(f"Apply to {this_month}")
    step("9 recurring: applying again says 'Nothing to add'", app.has("Nothing to add"))
    app.shot("tour-13-nothing-to-add.png")
    app.snack_gone()
    app.button("Add template")
    app.fill("Amount", "100")
    app.fill("Category", "Netflix")
    app.fill("Day of month", "31")
    app.save()
    step("9 recurring: day 31 rejected inline 'Pick a day from 1 to 28'", app.has("Pick a day from 1 to 28"))
    app.shot("tour-14-bad-day.png")
    app.cancel()
    step("9 recurring: Cancel closes the dialog", app.gone("Pick a day from 1 to 28"))

    # ---------------- 10. Goals ----------------
    app.tab("Goals")
    step("10 goals: Laptop starts at ₹9,000 of ₹60,000", app.has("₹9,000 of ₹60,000"))
    app.button("Add money to Laptop")
    app.fill("Amount", "1000")
    app.save()
    step("10 goals: 'Added ₹1,000 to Laptop' and '₹10,000 of ₹60,000'",
         app.has("Added ₹1,000 to Laptop") and app.has("₹10,000 of ₹60,000"))
    app.shot("tour-15-goal-contribution.png")
    app.snack_gone()

    # ---------------- 11. Log out ----------------
    app.log_out()
    step("11 log out: back on the landing page",
         app.has("Know where your money goes.") and app.gone("Add money to Laptop"))
    app.shot("tour-16-logged-out.png")

    bad = [e for e in errors if "CORS" in e or "Failed to fetch" in e or "Uncaught" in e]
    step("browser console: no CORS / fetch / uncaught errors", not bad)
    if bad:
        print("console errors:", bad[:5])
    browser.close()

failed = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed else 0)
