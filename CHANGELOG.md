# Changelog

## 1.0.0

First release.

- Accounts: register, log in and out; scrypt-hashed passwords; bearer-token sessions that survive a reload; every record belongs to one user.
- Expenses with add, edit, filter by category, and Remove with Undo; instant over-budget and low-balance alerts.
- Monthly budgets, recurring templates applied once per month, savings goals, and a dashboard with a one-line verdict.
- Money stored as integer paise; Indian digit grouping.
- Midnight-glass interface for web and Android: top pill navigation on wide windows, floating bottom pill on phones; keeps retrying with a clear message while a free-tier server wakes up.
- One Docker image serves the Flutter web app and the API; Render redeploys on every push to `main`.
- Browser walkthroughs (61 steps), a 30-step guided demo tour, 55 backend tests, a 421-check API sweep and 74 Flutter tests that need no backend.
