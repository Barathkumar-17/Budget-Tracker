# Budget Tracker

A personal budget and expense tracker: a **FastAPI + SQLite** backend and a **Flutter** app (Android and web).

> Single-user prototype. There is no authentication and it is not built for scale.

## Features

| Screen | What it does |
| --- | --- |
| **Dashboard** | A one-line verdict ("₹4,226 left, ₹774 below your safety line"), spent vs budget per category as rail lines, daily spend columns, month navigation, balance settings (opening balance and safety line) |
| **Expenses** | Grouped by day; add with amount, category chips, date picker and note; instant overspend and low-balance alerts; swipe or long-press to delete, with Undo |
| **Budgets** | Monthly cap per category, each shown as a line with its spend so far |
| **Recurring** | Templates (e.g. rent on the 1st) applied to a month with one tap; applying twice never duplicates |
| **Goals** | Savings goals with progress; contributions reduce the balance |

Categories are case-insensitive (`Food` and `food` are the same category). Amounts are stored as integer paise and exposed as rupees, so there is no floating-point drift.

## Design

The app treats a budget as a journey with a destination. Every budget category, savings goal and your balance is drawn as a **rail line**: the filled part is how far you have gone, the ring is the station you are heading for (a cap, a target, your safety line), and overspending runs the line past its ring in red. Red is used for nothing else.

- Navy header carrying the month; light and dark themes follow the system.
- Barlow typeface with tabular figures so amounts line up (bundled in `app/assets/fonts`, SIL Open Font License).
- Android-first Material 3: bottom navigation bar on phones, navigation rail and a centred column on wide windows, 48dp touch targets, system Back returns to the Dashboard.
- Status is never colour alone: over-budget and low-balance also use words and icons. Text scales with the system font size (tested at 2x). Expenses can be deleted without swiping (long-press, or the screen reader's actions menu).
- Amounts use Indian digit grouping (₹1,50,000) and drop the decimals when there are no paise.

## Demo

Try it with realistic data in about two minutes.

<p>
  <img src="docs/img/dashboard.png" width="230" alt="Dashboard: verdict, balance line and budget lines">
  <img src="docs/img/expenses.png" width="230" alt="Expenses grouped by day">
  <img src="docs/img/add-expense.png" width="230" alt="Add expense page">
</p>
<p>
  <img src="docs/img/overspend-alert.png" width="230" alt="Alert after an over-budget expense">
  <img src="docs/img/budgets.png" width="230" alt="Budgets as rail lines">
  <img src="docs/img/recurring.png" width="230" alt="Recurring templates">
</p>
<p>
  <img src="docs/img/goals.png" width="230" alt="Savings goals">
  <img src="docs/img/dashboard-dark.png" width="230" alt="Dashboard in the dark theme">
</p>

**1. Start the backend on a fresh database and load the demo data**

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --port 8000          # leave running
python seed_demo.py                    # in a second terminal
```

The seed script fills the current month through the public API: a ₹30,000 opening balance, three budgets, nine expenses, three recurring templates (rent, Netflix, gym, already applied) and two savings goals. It refuses to run on a database that already has data (`--force` overrides that). With Docker, run `docker compose exec api python seed_demo.py` instead.

**2. Open the app** (see [App](#app) for setup)

```bash
cd app && flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:8000
```

**3. Take the tour**

| Where | Try this | You should see |
| --- | --- | --- |
| **Dashboard** | Read the top panel and the lines | An amber panel: "₹4,226 left, ₹774 below your safety line", the balance line stopping short of the safety ring. *Fun* and *Food* run past their ring in red with "over budget"; *Transport* still has its ring ahead |
| **Dashboard** | Tap the sliders icon (Balance settings), set *Opening balance* to `40000`, Save | The panel turns calm: "₹14,226 left, ₹9,226 above your safety line", with a check icon |
| **Dashboard** | Use the arrows by the month | Other months are empty; the arrows return you to this month |
| **Add expense** | Tap **Add expense**, enter `500`, tap the *Food* chip, Save | An alert: **Over budget in food by ₹540** |
| **Expenses** | Swipe a row to the left, or long-press it | The expense is deleted (long-press asks first) and an **Undo** appears |
| **Budgets** | Tap *Food*, change the cap to `3000`, Save | Add the same `500` expense again: no alert any more |
| **Recurring** | Tap **Apply to October 2026** (your current month) | "Nothing to add: ... is already up to date." Applying twice never adds duplicates |
| **Recurring** | Tap **Add template**, enter `100` / `Netflix` / day `31`, Save | An inline message: "Pick a day from 1 to 28" |
| **Goals** | Tap *Laptop*, add `1000` | "Added ₹1,000 to Laptop"; progress moves to ₹10,000 of ₹60,000 and the balance drops by ₹1,000 |

**Reset the demo:** stop the backend, delete `backend/budget.db` (with Docker: `docker compose down -v`), then start again and re-run the seed script.

## Repository layout

```
backend/            FastAPI app (main.py), pytest suite, demo seed script, Dockerfile
app/                Flutter source: lib/ (screens, theme, API client), test/, assets/fonts, Dockerfile
e2e/                Real-browser walkthrough of every page, README screenshot script
docs/img/           Screenshots used in this README
docker-compose.yml  Runs backend and web app together
render.yaml         Render blueprint (two Docker services)
```

Flutter platform folders (`android/`, `web/`, ...) are generated, not committed.

## Prerequisites

- Python 3.10+
- Flutter 3.35+ (Dart 3)
- Chrome, or an Android emulator, to run the app

## Backend

```bash
cd backend
pip install -r requirements.txt
pytest                                   # 11 tests
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

- Interactive API docs: http://127.0.0.1:8000/docs
- The database is `backend/budget.db`. Set `BUDGET_DB=/path/to/file.db` to use another file.

### API summary

| Method | Path | Purpose |
| --- | --- | --- |
| GET / PUT | `/account` | Opening balance, low-balance threshold, current balance |
| POST / GET | `/expenses` | Add (response includes `alert` and `low_balance`) / list (`month`, `category`) |
| PUT / DELETE | `/expenses/{id}` | Update / delete |
| PUT / GET | `/budgets` | Set a cap / list caps for a `month` |
| POST / GET | `/recurring` | Add / list templates |
| DELETE | `/recurring/{id}` | Delete a template |
| POST | `/recurring/apply?month=YYYY-MM` | Create the month's expenses; returns `{"created": n}` (0 on repeat) |
| POST / GET | `/goals` | Add / list goals |
| POST | `/goals/{id}/contribute` | Add savings to a goal |
| DELETE | `/goals/{id}` | Delete a goal |
| GET | `/dashboard?month=YYYY-MM` | Totals, per-category spent vs cap, daily trend |

## App

Generate the platform folders once (this does not touch `lib/` or `test/`):

```bash
cd app
flutter create . --project-name budget_tracker   # add --platforms=web,android,windows to pick targets
flutter pub get
```

Run it with the backend already up:

```bash
# Chrome
flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:8000

# Android emulator (10.0.2.2 is the host machine)
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

The default `API_URL` is `http://10.0.2.2:8000`. On a physical device use your computer's LAN IP and start the backend with `--host 0.0.0.0`.

### Android: one extra step

`flutter create` only grants the `INTERNET` permission to *debug* builds, so a release APK cannot reach the API. After generating the platform folders, run:

```bash
python tool/patch_android.py --cleartext   # --cleartext only for a plain http:// API
```

It is safe to run repeatedly. Then build the APK:

```bash
flutter build apk --release --dart-define=API_URL=http://10.0.2.2:8000
# -> build/app/outputs/flutter-apk/app-release.apk
```

### Other builds

```bash
flutter build web --release --dart-define=API_URL=http://127.0.0.1:8000       # build/web
flutter build windows --release --dart-define=API_URL=http://127.0.0.1:8000   # Windows desktop (add --platforms=windows to flutter create)
```

## Docker

Run the backend and the web app together:

```bash
docker compose up --build
```

- App: http://localhost:3000
- API and docs: http://localhost:8000 and http://localhost:8000/docs
- Data is kept in the `budget-data` volume. `docker compose down -v` deletes it.

The web image bakes the API address in at build time (`API_URL` in `docker-compose.yml`, default `http://localhost:8000`). It must be an address the *browser* can reach. To serve it from another host, change that value and rebuild.

> The Docker files have not been run through Docker (it wasn't available where this was developed). Their build steps were replayed natively and the base images verified to exist, but treat the first `docker compose up --build` as the real test.

## Deploy on Render (free tier)

`render.yaml` describes two Docker web services, the API and the web app.

1. On https://render.com choose **New > Blueprint** and select this repository. Do **not** create a plain "Web Service" at the repo root: the Dockerfiles live in `backend/` and `app/`, so Render would fail with "open Dockerfile: no such file".
2. After the first deploy, open the API service and copy its URL. If it is not `https://budget-tracker-api.onrender.com` (names must be unique across Render), set the web service's `API_URL` environment variable to the real URL and redeploy the web service. The URL is baked into the web build.
3. Optional demo data: `python backend/seed_demo.py --api https://<your-api>.onrender.com`

A root `Dockerfile` also exists that builds the API, so a plain "Web Service" created at the repo root deploys the API as is. The web app still needs its own service (Root Directory `app`).

If you create the services by hand instead, set **Root Directory** to `backend` (API) or `app` (web), runtime **Docker**, and give the web service an `API_URL` environment variable.

Free-tier limits: services sleep after about 15 minutes idle (the first request then takes up to a minute), the filesystem is wiped on every restart or deploy so the SQLite data resets, and the URLs are public with no login. Use it as a demo, not for real finances. The Flutter build is memory-hungry and may not fit on a free instance.

## Testing

```bash
# 1. Backend unit tests
cd backend && pytest

# 2. Start a throwaway backend for the Flutter tests
BUDGET_DB=/tmp/t.db uvicorn main:app --port 8000

# 3. Static analysis and tests
cd app
flutter analyze
flutter test --dart-define=API_URL=http://127.0.0.1:8000
```

| Test | Needs backend? | Covers |
| --- | --- | --- |
| `test/format_test.dart` | no | Money formatting (Indian grouping, paise), day and month labels, category colours |
| `test/widget_test.dart` | no | App shell and tab navigation |
| `test/ui_flow_test.dart` | no | Every screen against an in-memory stub of the API: alerts, inline validation, readable server errors, Undo, long-press delete, month navigation, empty states, system Back, the wide layout, and 2x system text size without overflow |
| `test/api_test.dart` | **yes**, port 8000 | The Dart API client end to end against the real backend |

### Full UI walkthrough (real browser)

`e2e/walkthrough.py` drives the compiled web app in a real browser through every page: empty states, month navigation, account settings, adding/editing/deleting budgets, expenses (including swipe-to-delete, overspend and low-balance alerts, validation errors), recurring templates (applied twice), goals, and the final balance arithmetic. It needs a **fresh** database.

```bash
pip install playwright && playwright install chromium

# terminal 1: backend on a FRESH database
cd backend && uvicorn main:app --port 8000

# terminal 2: build and serve the web app
cd app && flutter build web --dart-define=API_URL=http://127.0.0.1:8000
python -m http.server 8123 --directory build/web

# terminal 3: run the walkthrough from the repository root
BASE_URL=http://127.0.0.1:8123/ python e2e/walkthrough.py
```

Set `BROWSER_CHANNEL=chrome` to use an installed Chrome instead of Playwright's Chromium, and `SLOW=2` on a slow machine. The last full run passed 45 of 45 steps.

## Releases

Tagged releases mark known-good states of `main`.
