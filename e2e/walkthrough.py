"""Full UI walkthrough of every page against a running app + backend.

Run against a FRESH database (the arithmetic below assumes zero starting data):

    pip install playwright && playwright install chromium
    BASE_URL=http://localhost:3000/ python e2e/walkthrough.py

Exits non-zero if any step fails. Screenshots go to $SHOTS (default e2e-shots/).
"""
import datetime
import sys

from playwright.sync_api import sync_playwright

from common import open_app

results = []


def step(name, ok):
    results.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name, flush=True)


today = datetime.date.today()
this_month = today.strftime("%Y-%m")
prev_month = (today.replace(day=1) - datetime.timedelta(days=1)).strftime("%Y-%m")

with sync_playwright() as p:
    browser, app, errors = open_app(p)

    # ---------------- Dashboard ----------------
    step("dashboard: loads with empty state",
         app.has("Balance ₹0.00") and app.has("No expenses or budgets this month") and app.has("No data"))
    app.pg.mouse.click(36, 92)  # previous month
    app.wait(1200)
    step("dashboard: previous-month arrow", app.has(prev_month))
    app.pg.mouse.click(444, 92)  # next month
    app.wait(1200)
    step("dashboard: next-month arrow returns to this month", app.has(this_month))

    app.pg.mouse.click(416, 148)  # settings icon
    app.wait(1000)
    app.fill("Opening balance", "abc")
    app.save()
    step("account: non-numeric input rejected", app.has("Enter valid numbers"))
    app.snack_gone()
    app.pg.mouse.click(416, 148)
    app.wait(1000)
    app.fill("Opening balance", "1000")
    app.fill("Low-balance warning below", "500")
    app.save()
    step("account: opening balance and low-balance threshold saved", app.has("Balance ₹1000.00"))

    # ---------------- Budgets ----------------
    app.tab("Budgets")
    step("budgets: empty state", app.has(f"No budgets set for {this_month}"))
    app.fab()
    app.fill("Category", "")
    app.fill("Monthly cap", "50")
    app.save()
    step("budgets: blank category rejected", app.has("Category and a valid cap are required"))
    app.snack_gone()
    app.fab()
    app.fill("Category", "Food")
    app.fill("Monthly cap", "80")
    app.save()
    step("budgets: add (category lowercased)", app.has("food") and app.has("₹80.00"))
    app.tap_text("food")
    app.fill("Monthly cap", "100")
    app.save()
    step("budgets: edit existing cap", app.has("₹100.00") and app.gone("₹80.00"))
    app.shot("budgets.png")

    # ---------------- Expenses ----------------
    app.tab("Expenses")
    step("expenses: empty state", app.has("No expenses this month"))
    app.fab()
    app.fill("Amount", "150")
    app.fill("Category", "Food")
    app.fill("Note", "lunch")
    app.save()
    step("expenses: add over budget shows overspend alert", app.has("Over budget in food by ₹50.00"))
    step("expenses: row listed with note", app.has("food ₹150.00") and app.has("lunch"))
    app.snack_gone()

    app.fab()
    app.fill("Amount", "400")
    app.fill("Category", "Rent")
    app.save()
    step("expenses: balance below threshold shows low-balance alert", app.has("Low balance: ₹450.00"))
    app.snack_gone()

    app.fab()
    app.fill("Amount", "5")
    app.fill("Category", "Tea")
    app.fill("Date (YYYY-MM-DD)", "not-a-date")
    app.save()
    step("expenses: bad date shows a readable server error", app.has("date:"))
    app.snack_gone()

    app.fab()
    app.fill("Amount", "0")
    app.fill("Category", "Tea")
    app.save()
    step("expenses: zero amount rejected before the server", app.has("Amount and category are required"))
    app.snack_gone()

    app.fab()
    app.fill("Amount", "5")
    app.fill("Category", "Temp")
    app.save()
    step("expenses: temporary row added", app.has("temp ₹5.00"))
    app.snack_gone()
    app.swipe_left("temp")
    step("expenses: swipe-to-delete removes the row", app.gone("temp ₹5.00"))
    app.shot("expenses.png")

    # ---------------- Dashboard after spending ----------------
    app.tab("Dashboard")
    step("dashboard: balance reflects spending", app.has("Balance ₹450.00"))
    step("dashboard: low-balance card", app.has("Low balance — below ₹500.00"))
    step("dashboard: over-budget bar", app.has("₹150.00 / ₹100.00") and app.has("Over budget"))
    step("dashboard: uncapped category listed", app.has("rent") and app.has("₹400.00"))
    app.shot("dashboard.png")

    # ---------------- Recurring ----------------
    app.tab("Recurring")
    step("recurring: empty state", app.has("No recurring templates"))
    app.fab()
    app.fill("Amount", "10")
    app.fill("Category", "Netflix")
    app.fill("Day of month", "31")
    app.save()
    step("recurring: day outside 1-28 rejected", app.has("Check amount, category and day (1-28)"))
    app.snack_gone()
    app.fab()
    app.fill("Amount", "10")
    app.fill("Category", "Netflix")
    app.fill("Note", "plan")
    app.fill("Day of month", "5")
    app.save()
    step("recurring: template listed", app.has("netflix ₹10.00") and app.has("Day 5"))
    app.pg.get_by_role("button", name="Apply to this month").click()
    step("recurring: first apply adds one expense", app.has("Added 1 expense(s)"))
    app.snack_gone()
    app.pg.get_by_role("button", name="Apply to this month").click()
    step("recurring: second apply adds nothing", app.has("Already applied"))
    app.snack_gone()
    app.shot("recurring.png")

    app.tab("Expenses")
    step("expenses: recurring expense appears once", app.text().count("netflix ₹10.00") == 1)

    # ---------------- Goals ----------------
    app.tab("Goals")
    step("goals: empty state", app.has("No savings goals yet"))
    app.fab()
    app.fill("Name", "Laptop")
    app.fill("Target amount", "1000")
    app.save()
    step("goals: add goal", app.has("Laptop") and app.has("₹0.00 of ₹1000.00"))
    app.tap_text("Laptop")
    app.fill("Amount", "abc")
    app.save()
    step("goals: invalid contribution rejected", app.has("Enter a valid amount"))
    app.snack_gone()
    app.tap_text("Laptop")
    app.fill("Amount", "250")
    app.save()
    step("goals: contribute updates progress", app.has("₹250.00 of ₹1000.00"))
    app.fab()
    app.fill("Name", "Phone")
    app.fill("Target amount", "300")
    app.save()
    step("goals: second goal listed", app.has("Phone"))
    app.shot("goals.png")
    app.click_right_button(1)  # trash icon on the second row
    step("goals: delete goal", app.gone("Phone") and app.has("Laptop"))

    # ---------------- Recurring delete ----------------
    app.tab("Recurring")
    app.click_right_button(0)
    step("recurring: delete template", app.has("No recurring templates"))

    # ---------------- Final state ----------------
    app.tab("Dashboard")
    step("dashboard: final balance 1000-150-400-10-250 = 190", app.has("Balance ₹190.00"))
    app.tab("Expenses")
    step("expenses: final list has food, rent, netflix",
         app.has("food ₹150.00") and app.has("rent ₹400.00") and app.has("netflix ₹10.00"))

    bad = [e for e in errors if "CORS" in e or "Failed to fetch" in e or "Uncaught" in e]
    step("browser console: no CORS / fetch / uncaught errors", not bad)
    if bad:
        print("console errors:", bad[:5])
    browser.close()

failed = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed else 0)
