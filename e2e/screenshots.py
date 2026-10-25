"""Capture README screenshots of a seeded app (run backend/seed_demo.py first).

    BASE_URL=http://localhost:3000/ SHOTS=docs/img python e2e/screenshots.py

Phone-sized (390x844 @2x). Light screens plus a dark dashboard.
"""
from playwright.sync_api import sync_playwright

from common import open_app

with sync_playwright() as p:
    browser, app, _ = open_app(p, scheme="light")
    app.has("left")
    app.wait(1500)
    app.shot("dashboard.png")
    for tab, name in [("Expenses", "expenses.png"), ("Budgets", "budgets.png"),
                      ("Recurring", "recurring.png"), ("Goals", "goals.png")]:
        app.tab(tab)
        app.wait(800)
        app.shot(name)

    # The add page, then the alert an over-budget expense triggers.
    app.tab("Expenses")
    app.fab("Add expense")
    app.fill("Amount", "500")
    app.fill("Category", "Food")
    app.fill("Note", "Team dinner")
    app.shot("add-expense.png")
    app.save()
    app.has("Over budget in food")
    app.shot("overspend-alert.png")
    browser.close()

    browser, app, _ = open_app(p, scheme="dark")
    app.has("left")
    app.wait(1500)
    app.shot("dashboard-dark.png")
    browser.close()
print("screenshots written")
