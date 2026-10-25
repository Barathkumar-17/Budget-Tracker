"""Capture README screenshots of the demo account.

Run `python backend/seed_demo.py` first (it creates the account `demo`), then:

    BASE_URL=http://localhost:8000/ SHOTS=docs/img python e2e/screenshots.py

Desktop (1280x800) for the product pages and every section, and phone-sized
(390x844) shots of the landing page, dashboard and expenses.
"""
import os

from playwright.sync_api import sync_playwright

from common import open_app

USER = os.environ.get("DEMO_USER", "demo")
PASSWORD = os.environ.get("DEMO_PASSWORD", "demo-password")


def log_in(app):
    app.button("Log in")
    app.fill("Username", USER)
    app.fill("Password", PASSWORD, exact=True)
    app.button("Log in", last=True)
    app.has("You have")
    app.wait(1800)


def scroll_top(app):
    app.pg.mouse.wheel(0, -4000)
    app.wait(500)


with sync_playwright() as p:
    # ---- desktop ----
    browser, app, _ = open_app(p, scheme="dark", width=1280, height=800, scale=1)
    app.has("Know where your money goes.")
    app.wait(1200)
    app.shot("landing.png")
    app.button("Log in")
    app.wait(600)
    app.shot("login.png")
    app.button("Back to home", exact=False)
    log_in(app)
    app.shot("dashboard.png")
    for tab, name in [("Expenses", "expenses.png"), ("Budgets", "budgets.png"),
                      ("Recurring", "recurring.png"), ("Goals", "goals.png")]:
        app.tab(tab)
        app.wait(800)
        app.shot(name)

    # The add dialog, then the alert an over-budget expense triggers.
    app.tab("Expenses")
    app.button("Add expense")
    app.fill("Amount", "500")
    app.fill("Category", "Food")
    app.fill("Note", "Team dinner")
    app.shot("add-expense.png")
    app.save()
    app.has("Over budget in food")
    app.shot("overspend-alert.png")
    browser.close()

    # ---- phone ----
    browser, app, _ = open_app(p, scheme="dark", width=390, height=844, scale=2)
    app.has("Know where your money goes.")
    app.wait(1200)
    app.shot("phone-landing.png")
    log_in(app)
    app.shot("phone-dashboard.png")
    app.tab("Expenses")
    app.wait(800)
    app.shot("phone-expenses.png")
    browser.close()
print("screenshots written")
