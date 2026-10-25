"""Full UI walkthrough of every page against a running app + backend.

Every run registers its own new users, so it works on any database:

    pip install playwright && playwright install chromium
    BASE_URL=http://localhost:3000/ python e2e/walkthrough.py

Exits non-zero if any step fails. Screenshots go to $SHOTS (default e2e-shots/).
"""
import datetime
import sys
import time

from playwright.sync_api import sync_playwright

from common import open_app

results = []
_app = None  # set once the browser is open, so a failing step can snapshot the screen


def step(name, ok):
    results.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    if not ok and _app is not None:
        _app.shot(f"fail-{len(results):02d}.png")
        print("     page text:", _app.text()[:300], flush=True)


stamp = int(time.time())
username = f"walk{stamp}"
other_user = f"other{stamp}"
password = "walkthrough pw 1"

today = datetime.date.today()
this_month = today.strftime("%B %Y")
this_month_name = today.strftime("%B")
prev_month = (today.replace(day=1) - datetime.timedelta(days=1)).strftime("%B %Y")

with sync_playwright() as p:
    browser, app, errors = open_app(p)
    _app = app

    # ---------------- Accounts: log in / register ----------------
    step("accounts: the app opens on the login screen",
         app.has("Know where your money goes.") and app.has("Log in") and app.has("Create an account"))
    app.button("Log in")
    step("accounts: empty login is rejected inline",
         app.has("Enter your username") and app.has("Enter your password"))
    app.fill("Username", "nobody_here")
    app.fill("Password", "wrong password", exact=True)
    app.button("Log in")
    step("accounts: unknown user gets one clear message", app.has("Wrong username or password"))
    app.button("Create an account")
    step("accounts: registration form", app.has("Create your account") and app.has("Confirm password"))
    app.fill("Username", "ab")
    app.fill("Password", "short", exact=True)
    app.fill("Confirm password", "other")
    app.button("Create account")
    step("accounts: registration rules are shown inline",
         app.has("Use 3-30 letters, numbers, dots, dashes or underscores")
         and app.has("Use at least 8 characters") and app.has("The passwords do not match"))
    app.fill("Username", username)
    app.fill("Password", password, exact=True)
    app.fill("Confirm password", password)
    app.button("Create account")

    # ---------------- Dashboard ----------------
    step("dashboard: loads with empty state",
         app.has("₹0 left") and app.has(f"Nothing spent or budgeted in {this_month} yet") and app.has("Daily spend"))
    step("dashboard: no safety line yet", app.has("Set a safety line to be warned when money runs low."))
    step("dashboard: Add expense button is available", app.has("Add expense"))
    app.month_prev()
    step("dashboard: previous-month arrow", app.has(prev_month))
    app.month_next()
    step("dashboard: next-month arrow returns to this month", app.has(this_month))

    app.button("Balance settings")
    app.fill("Opening balance", "abc")  # letters are filtered out, leaving the field empty
    app.save()
    step("account: empty opening balance rejected inline", app.has("Enter a number, for example 5000"))
    app.fill("Opening balance", "1000")
    app.fill("Safety line", "500")
    app.save()
    step("account: opening balance and safety line saved",
         app.has("₹1,000 left, ₹500 above your safety line") and app.has("Safety line ₹500")
         and app.has("Balance ₹1,000"))

    # ---------------- Budgets ----------------
    app.tab("Budgets")
    step("budgets: empty state", app.has(f"No budgets for {this_month}"))
    app.fab("Add budget")
    app.fill("Monthly cap", "50")
    app.save()
    step("budgets: blank category rejected inline", app.has("Give the category a name, for example Food"))
    app.fill("Category", "Food")
    app.fill("Monthly cap", "80")
    app.save()
    step("budgets: add (category shown capitalised)", app.has("Food") and app.has("₹80"))
    app.tap_text("Food")
    step("budgets: tapping a row opens the change sheet", app.has("Change budget"))
    app.fill("Monthly cap", "100")
    app.save()
    step("budgets: edit existing cap", app.has("₹100") and app.gone("₹80"))
    app.shot("budgets.png")

    # ---------------- Expenses ----------------
    app.tab("Expenses")
    step("expenses: empty state", app.has(f"No expenses in {this_month}"))
    app.fab("Add expense")
    step("expenses: add page opens", app.has("Add expense") and app.has("Category") and app.has("Date"))
    app.fill("Amount", "150")
    app.fill("Category", "Food")
    app.fill("Note", "lunch")
    app.save()
    step("expenses: over budget shows the overspend alert", app.has("Over budget in food by ₹50"))
    step("expenses: row listed under Today with its note", app.has("Today") and app.has("lunch") and app.has("₹150"))
    app.snack_gone()

    app.tap_text("lunch")
    step("expenses: tapping a row opens it for editing", app.has("Edit expense"))
    app.fill("Note", "lunch edited")
    app.save()
    # Food is already over its budget, so saving the edit shows the overspend alert (not "Updated").
    step("expenses: edit is saved and re-checks the budget",
         app.has("Over budget in food by ₹50") and app.has("lunch edited"))
    app.snack_gone()

    app.fab("Add expense")
    app.fill("Amount", "400")
    app.fill("Category", "Rent")
    app.save()
    step("expenses: balance below safety line shows a low-balance alert",
         app.has("Low balance: ₹450 left, below your ₹500 safety line"))
    app.snack_gone()

    app.fab("Add expense")
    app.fill("Amount", "0")
    app.fill("Category", "Tea")
    app.save()
    step("expenses: zero amount rejected before the server", app.has("Enter an amount above 0"))
    app.fill("Amount", "5")
    app.fill("Category", "Temp")
    app.save()
    step("expenses: temporary row added", app.has("Added Temp ₹5") or app.has("Temp"))
    app.snack_gone()

    app.swipe_left("Temp")
    step("expenses: swipe-to-delete removes the row and offers Undo", app.has("Deleted Temp ₹5"))
    app.snack_action("Undo")
    # Flutter web's accessibility DOM can lag the canvas for a freshly inserted row while the
    # app is idle (the row is on screen but not yet in the DOM). Re-open the tab to read it.
    app.tab("Dashboard")
    app.tab("Expenses")
    step("expenses: Undo brings the row back", app.has("Temp") and app.has("₹5"))
    app.snack_gone()
    app.long_press("Temp")
    step("expenses: long-press asks before deleting", app.has("Delete Temp ₹5?"))
    app.button("Delete", last=True)
    step("expenses: confirmed long-press delete works", app.has("Deleted Temp ₹5"))
    app.snack_gone()
    app.shot("expenses.png")

    # ---------------- Dashboard after spending ----------------
    app.tab("Dashboard")
    step("dashboard: state sentence reflects the low balance",
         app.has("₹450 left, ₹50 below your safety line"))
    step("dashboard: over-budget line", app.has("₹150 of ₹100") and app.has("₹50 over budget"))
    step("dashboard: uncapped category listed", app.has("Rent") and app.has("₹400") and app.has("No budget set"))
    step("dashboard: spent this month", app.has(f"Spent in {this_month_name}: ₹550"))
    app.shot("dashboard.png")

    # ---------------- Recurring ----------------
    app.tab("Recurring")
    step("recurring: empty state", app.has("No recurring expenses"))
    app.fab("Add template")
    app.fill("Amount", "10")
    app.fill("Category", "Netflix")
    app.fill("Day of month", "31")
    app.save()
    step("recurring: day outside 1-28 rejected inline", app.has("Pick a day from 1 to 28"))
    app.fill("Note", "plan")
    app.fill("Day of month", "5")
    app.save()
    step("recurring: template listed", app.has("Netflix") and app.has("Day 5 of every month"))
    app.button(f"Apply to {this_month}")
    step("recurring: first apply adds one expense", app.has(f"Added 1 expense to {this_month}"))
    app.snack_gone()
    app.button(f"Apply to {this_month}")
    step("recurring: second apply adds nothing", app.has("Nothing to add"))
    app.snack_gone()
    app.shot("recurring.png")

    app.tab("Expenses")
    step("expenses: recurring expense appears once", app.text().count("Netflix") == 1 and app.has("Recurring"))

    # ---------------- Goals ----------------
    app.tab("Goals")
    step("goals: empty state", app.has("No savings goals yet"))
    app.fab("Add goal")
    app.fill("Name", "Laptop")
    app.fill("Target amount", "1000")
    app.save()
    step("goals: add goal", app.has("Laptop") and app.has("₹0 of ₹1,000"))
    app.tap_text("Laptop")
    step("goals: tapping a goal opens the contribution sheet", app.has("Add to Laptop"))
    app.fill("Amount", "abc")
    app.save()
    step("goals: empty contribution rejected inline", app.has("Enter an amount above 0"))
    app.fill("Amount", "250")
    app.save()
    step("goals: contribute updates progress", app.has("Added ₹250 to Laptop") and app.has("₹250 of ₹1,000"))
    app.snack_gone()
    app.fab("Add goal")
    app.fill("Name", "Phone")
    app.fill("Target amount", "300")
    app.save()
    step("goals: second goal listed", app.has("Phone"))
    app.shot("goals.png")
    app.button("Options for Phone")
    app.pg.get_by_role("menuitem", name="Delete goal").click()
    app.wait(1000)
    step("goals: delete asks for confirmation", app.has("Delete Phone?"))
    app.button("Delete goal", last=True)
    step("goals: delete goal", app.gone("Phone") and app.has("Laptop"))

    # ---------------- Recurring delete ----------------
    app.tab("Recurring")
    app.button("Delete Netflix template")
    step("recurring: delete template with Undo offered",
         app.has("No recurring expenses") and app.has("Undo"))

    # ---------------- Final state ----------------
    app.tab("Dashboard")
    step("dashboard: final balance 1000-150-400-10-250 = 190",
         app.has("₹190 left, ₹310 below your safety line"))
    app.tab("Expenses")
    step("expenses: final list has food, rent and netflix", app.has("Food") and app.has("Rent") and app.has("Netflix"))

    # ---------------- Accounts: log out, log back in, privacy ----------------
    app.button("Account")
    step("accounts: the menu shows who is logged in", app.has(f"Signed in as {username}"))
    app.pg.get_by_role("menuitem", name="Log out").click()
    app.wait(1500)
    step("accounts: log out returns to the login screen",
         app.has("Know where your money goes.") and app.gone("Add expense"))
    app.fill("Username", username)
    app.fill("Password", "the wrong password", exact=True)
    app.button("Log in")
    step("accounts: a wrong password is refused", app.has("Wrong username or password"))
    app.fill("Password", password, exact=True)
    app.button("Log in")
    step("accounts: logging back in restores the data", app.has("₹190 left, ₹310 below your safety line"))
    app.reload()
    step("accounts: a page reload stays logged in", app.has("₹190 left, ₹310 below your safety line"))

    app.button("Account")
    app.pg.get_by_role("menuitem", name="Log out").click()
    app.wait(1500)
    app.button("Create an account")
    app.fill("Username", other_user)
    app.fill("Password", password, exact=True)
    app.fill("Confirm password", password)
    app.button("Create account")
    step("accounts: a second user starts with an empty account", app.has("₹0 left"))
    app.tab("Expenses")
    step("accounts: and cannot see the first user's expenses",
         app.has(f"No expenses in {this_month}") and app.gone("Rent"))
    app.tab("Goals")
    step("accounts: or their goals", app.has("No savings goals yet") and app.gone("Laptop"))

    bad = [e for e in errors if "CORS" in e or "Failed to fetch" in e or "Uncaught" in e]
    step("browser console: no CORS / fetch / uncaught errors", not bad)
    if bad:
        print("console errors:", bad[:5])
    browser.close()

failed = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed else 0)
