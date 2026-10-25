# Budget Tracker

A personal budget and expense tracker with accounts: a **FastAPI + SQLite** backend and a **Flutter** app (Android and web).

> A prototype for a small number of users: each person has their own account and sees only their own data. It is not built for scale.

## Features

| Screen | What it does |
| --- | --- |
| **Login** | Register, log in and log out. Passwords are stored hashed (scrypt, per-user salt), the session survives a reload, and every feature below works on the logged-in user's own data only |
| **Dashboard** | A one-line verdict ("₹4,226 left, ₹774 below your safety line"), spent vs budget per category as rail lines, daily spend columns, month navigation, balance settings (opening balance and safety line) |
| **Expenses** | Grouped by day; add with amount, category chips, date picker and note; instant overspend and low-balance alerts; tap to edit, swipe or long-press to delete (with Undo) |
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
  <img src="docs/img/login.png" width="230" alt="Login screen">
</p>

**1. Start the backend and load the demo account**

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --port 8000          # leave running
python seed_demo.py                    # in a second terminal
```

The seed script creates the account `demo` (password `demo-password`; change them with `--username` and `--password`) and fills the current month through the public API: a ₹30,000 opening balance, three budgets, nine expenses, three recurring templates (rent, Netflix, gym, already applied) and two savings goals. It refuses to add data to an account that already has some (`--force` overrides that). With Docker, run `docker compose exec app python seed_demo.py` instead.

**2. Open the app** (see [App](#app) for setup)

```bash
cd app && flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:8000
```

**3. Take the tour**

| Where | Try this | You should see |
| --- | --- | --- |
| **Login** | Log in as `demo` / `demo-password` (or tap **Create an account** to make your own) | The Dashboard for the current month. Use the account icon at the top right to see who is logged in or to log out |
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
Dockerfile          Builds the app and the API into one image
docker-compose.yml  Runs that image locally on port 8000
render.yaml         Render blueprint (one Docker service)
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
pytest                                   # 39 tests
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

- Interactive API docs: http://127.0.0.1:8000/docs
- The database is `backend/budget.db`. Set `BUDGET_DB=/path/to/file.db` to use another file.

### API summary

Every endpoint except `/auth/register` and `/auth/login` needs `Authorization: Bearer <token>` and only ever touches that user's data (another user's record is a 404). Sessions last 30 days.

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/auth/register`, `/auth/login` | Create an account / log in: both return a session `token` |
| POST / GET | `/auth/logout`, `/auth/me` | End the session / who am I |
| GET / PUT | `/account` | Opening balance, low-balance threshold, current balance |
| POST / GET | `/expenses` | Add (response includes `alert` and `low_balance`) / list (`month`, `category`) |
| PUT / DELETE | `/expenses/{id}` | Update (same response as add, so editing can alert too) / delete |
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

One container runs the whole app: the Flutter web app and the API, behind one port.

```bash
docker compose up --build
```

- App: http://localhost:8000
- API docs: http://localhost:8000/docs
- Demo data: `docker compose exec app python seed_demo.py`
- Data lives in the `budget-data` volume. `docker compose down -v` deletes it.

Without Compose: `docker build -t budget-tracker . && docker run -p 8000:8000 -v budget-data:/data budget-tracker`.

The `Dockerfile` has two stages. The first builds the Flutter web app with `API_URL=same-origin`, so the app talks to whatever server it was loaded from. The second is the API image, which serves that build at `/`. The first build downloads the Flutter SDK image, so it takes a few minutes.

To run the same thing without Docker: build the app with `flutter build web --dart-define=API_URL=same-origin`, copy `app/build/web` to `backend/web`, and start `uvicorn main:app`. The backend serves `backend/web` at `/` whenever it exists (override the folder with `WEB_DIR`).

## Deploy on Render (free tier)

Render builds the root `Dockerfile`, so one service gives you the app and the API at one URL.

1. On https://render.com choose **New > Web Service** (or **New > Blueprint** to use `render.yaml`) and select this repository.
2. Runtime **Docker**, repository root, default settings. No environment variables are needed.
3. Wait for the first build (several minutes: it downloads Flutter and compiles the app), then open the service URL. The app is at `/` and the API docs at `/docs`.
4. Optional demo data: `python backend/seed_demo.py --api https://<your-service>.onrender.com`

Free-tier limits: the service sleeps after about 15 minutes idle (the first request then takes up to a minute), the filesystem is wiped on every restart or deploy so the SQLite data resets, and the URL is public with no login. Use it as a demo, not for real finances.

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
| `test/widget_test.dart` | no | With nobody logged in the app opens on the login screen |
| `test/ui_flow_test.dart` | no | Every screen against an in-memory stub of the API. Accounts: log in, register with validation, wrong password, taken username, unreachable server, log out, expired session, start-up retry. Plus alerts, inline validation, edit, Undo, long-press delete, month navigation, empty states, system Back, the wide layout, and 2x system text without overflow |
| `test/api_test.dart` | **yes**, port 8000 | The Dart API client against the real backend: accounts, login required, users isolated from each other, and the full feature flow. Registers its own users, so it can be re-run on any database |

### Full UI walkthrough (real browser)

`e2e/walkthrough.py` drives the compiled web app in a real browser through everything: the login and registration screens (including their validation and a wrong password), every tab, budgets (add and edit), expenses (add, edit, swipe and long-press delete with Undo, overspend and low-balance alerts), recurring templates (applied twice), goals, log out and back in, staying logged in after a page reload, and a second user who sees none of the first user's data. Each run registers its own users, so the database does not need to be empty.

```bash
pip install playwright && playwright install chromium

# build the app for a single server and put it next to the backend
cd app && flutter build web --dart-define=API_URL=same-origin
cp -r build/web ../backend/web            # (Windows: xcopy /E /I build\web ..ackend\web)

# start the backend, which now serves the app too
cd ../backend && uvicorn main:app --port 8000

# in another terminal, from the repository root
BASE_URL=http://127.0.0.1:8000/ python e2e/walkthrough.py
```

Set `BROWSER_CHANNEL=chrome` to use an installed Chrome instead of Playwright's Chromium, and `SLOW=2` on a slow machine. The last full run passed 60 of 60 steps.

## Releases

Tagged releases mark known-good states of `main`.
