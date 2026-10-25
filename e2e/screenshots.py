"""Capture README screenshots of the demo account.

Run `python backend/seed_demo.py` first (it creates the account `demo`), then:

    BASE_URL=http://localhost:8000/ SHOTS=docs/img python e2e/screenshots.py

Phone-sized (390x844 @2x). The login screens, the light screens and a dark dashboard.
"""
import os

from playwright.sync_api import sync_playwright

from common import open_app

USER = os.environ.get("DEMO_USER", "demo")
PASSWORD = os.environ.get("DEMO_PASSWORD", "demo-password")


def log_in(app):
    app.fill("Username", USER)
    app.fill("Password", PASSWORD, exact=True)
    app.button("Log in")
    app.has("left")
    app.wait(1500)


with sync_playwright() as p:
    browser, app, _ = open_app(p, scheme="light")
    app.has("Know where your money goes.")
    app.wait(1200)
    app.shot("login.png")
    app.button("Create an account")
    app.wait(600)
    app.shot("register.png")
    app.button("I already have an account")

    log_in(app)
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
    app.has("Know where your money goes.")
    log_in(app)
    app.shot("dashboard-dark.png")
    browser.close()
print("screenshots written")
