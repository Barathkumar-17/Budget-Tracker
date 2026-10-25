"""Capture README screenshots of a seeded app (run backend/seed_demo.py first).

    BASE_URL=http://localhost:3000/ SHOTS=docs/img python e2e/screenshots.py
"""
from playwright.sync_api import sync_playwright

from common import open_app

with sync_playwright() as p:
    browser, app, _ = open_app(p)
    app.has("Balance")
    app.wait(1500)
    app.shot("dashboard.png")
    for tab, name in [("Expenses", "expenses.png"), ("Budgets", "budgets.png"),
                      ("Recurring", "recurring.png"), ("Goals", "goals.png")]:
        app.tab(tab)
        app.wait(800)
        app.shot(name)

    # An over-budget expense shows the alert right away.
    app.tab("Expenses")
    app.fab()
    app.fill("Amount", "500")
    app.fill("Category", "Food")
    app.fill("Note", "Team dinner")
    app.save()
    app.has("Over budget in food")
    app.shot("overspend-alert.png")
    browser.close()
print("screenshots written")
