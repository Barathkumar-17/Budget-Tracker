# Budget Tracker

A personal budget and expense tracker: a **FastAPI + SQLite** backend and a **Flutter** app (Android and web).

> Single-user prototype. There is no authentication and it is not built for scale.

## Features

| Tab | What it does |
| --- | --- |
| **Dashboard** | Balance, spent vs budget per category, daily spend trend, month navigation, opening balance and low-balance threshold |
| **Expenses** | Add an expense (amount, date, category, note), swipe to delete, instant overspend and low-balance alerts |
| **Budgets** | Monthly cap per category |
| **Recurring** | Templates (e.g. rent on the 1st) applied to a month with one tap; applying twice never duplicates |
| **Goals** | Savings goals with progress; contributions reduce the balance |

Categories are case-insensitive (`Food` and `food` are the same category). Amounts are stored as integer paise and exposed as rupees, so there is no floating-point drift.

## Repository layout

```
backend/   FastAPI app (main.py) and pytest suite (test_main.py)
app/       Flutter source: lib/ (screens, API client) and test/
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
pytest                                   # 10 tests
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
flutter create . --project-name budget_tracker
flutter pub get
```

Run it with the backend already up:

```bash
# Chrome
flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:8000

# Android emulator (10.0.2.2 is the host machine)
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

The default `API_URL` is `http://10.0.2.2:8000`. On a physical device use your computer's LAN IP and start the backend with `--host 0.0.0.0`. For Android over plain HTTP, add `android:usesCleartextTraffic="true"` to the `<application>` tag in `android/app/src/main/AndroidManifest.xml`.

Build for the web:

```bash
flutter build web --dart-define=API_URL=http://127.0.0.1:8000
```

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
| `test/widget_test.dart` | no | App shell and tab navigation |
| `test/ui_flow_test.dart` | no | Every tab's flows against an in-memory stub of the API: alerts, validation, readable server errors, recurring apply twice, goals, retry on network failure |
| `test/api_test.dart` | **yes**, port 8000 | The Dart API client end to end against the real backend |

The web build was also driven in real Chrome against the real backend (account, budget, overspend and low-balance alerts, recurring applied twice, goals); all steps passed.

## Releases

Tagged releases mark known-good states of `main`.
