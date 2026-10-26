import hashlib
import hmac
import os
import secrets
import sqlite3
from contextlib import contextmanager
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Annotated, NamedTuple

from fastapi import Depends, FastAPI, HTTPException, Path as PathParam, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, StrictInt, StringConstraints

DB_PATH = os.environ.get("BUDGET_DB", "budget.db")
# Compiled Flutter web app. When present (as in the Docker image) it is served at "/".
WEB_DIR = Path(os.environ.get("WEB_DIR", Path(__file__).parent / "web"))
HAS_WEB = (WEB_DIR / "index.html").is_file()
SESSION_DAYS = 30

app = FastAPI(title="Budget Tracker")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

MAX_BODY_BYTES = 8192  # every request body in this API is a few hundred bytes


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    """Refuse oversized bodies up front (also blocks absurdly deep JSON)."""
    declared = request.headers.get("content-length", "")
    if declared.isdigit() and int(declared) > MAX_BODY_BYTES:
        return JSONResponse({"detail": "Request body is too large"}, status_code=413)
    return await call_next(request)


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    """422 with the problems only. FastAPI also echoes the offending input, which
    cannot always be turned into JSON (NaN, lone surrogates) and would crash."""
    errors = [{"loc": list(e["loc"]), "msg": e["msg"], "type": e["type"]} for e in exc.errors()]
    return JSONResponse({"detail": errors}, status_code=422)


if not HAS_WEB:

    @app.api_route("/", methods=["GET", "HEAD"], include_in_schema=False)
    def root():
        """Friendly landing response; also satisfies host health probes."""
        return {"name": "Budget Tracker API", "docs": "/docs"}


# ---- money: stored as integer paise, exposed as rupees ----
def to_paise(x: Decimal | float) -> int:
    return int((Decimal(str(x)) * 100).to_integral_value())


def rupees(p: int | None):
    return None if p is None else p / 100


@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


DATA_TABLES = ["expenses", "budgets", "recurring", "goals", "account"]


def init_db():
    with db() as c:
        # Tables from the old single-user schema have no owner: keep their data, out of the way.
        for t in DATA_TABLES:
            cols = [r["name"] for r in c.execute(f"PRAGMA table_info({t})")]
            if cols and "user_id" not in cols:
                c.execute(f"ALTER TABLE {t} RENAME TO legacy_{t}")
        c.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE COLLATE NOCASE,
                password_hash TEXT NOT NULL,
                created TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                created TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                amount INTEGER NOT NULL CHECK (amount > 0),
                date TEXT NOT NULL,
                category TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                recurring_id INTEGER,
                UNIQUE (recurring_id, date)
            );
            CREATE TABLE IF NOT EXISTS budgets (
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                category TEXT NOT NULL,
                month TEXT NOT NULL,
                cap INTEGER NOT NULL CHECK (cap >= 0),
                PRIMARY KEY (user_id, category, month)
            );
            CREATE TABLE IF NOT EXISTS recurring (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                amount INTEGER NOT NULL CHECK (amount > 0),
                category TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                day_of_month INTEGER NOT NULL CHECK (day_of_month BETWEEN 1 AND 28)
            );
            CREATE TABLE IF NOT EXISTS goals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                target INTEGER NOT NULL CHECK (target > 0),
                saved INTEGER NOT NULL DEFAULT 0,
                deadline TEXT
            );
            CREATE TABLE IF NOT EXISTS account (
                user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                opening INTEGER NOT NULL DEFAULT 0,
                low_threshold INTEGER NOT NULL DEFAULT 0
            );
            """
        )


init_db()


# ---- passwords and sessions ----
def hash_password(password: str, salt: bytes | None = None) -> str:
    """scrypt with a per-user random salt; the plain password is never stored."""
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
    return f"scrypt${salt.hex()}${digest.hex()}"


def check_password(password: str, stored: str) -> bool:
    try:
        _, salt_hex, digest_hex = stored.split("$")
        expected = hash_password(password, bytes.fromhex(salt_hex)).split("$")[2]
    except ValueError:
        return False
    return hmac.compare_digest(expected, digest_hex)


# Checked when the username does not exist, so timing does not reveal which usernames are taken.
_DUMMY_HASH = hash_password("not-a-real-password")


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def new_session(c, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    c.execute("INSERT INTO sessions (token_hash, user_id) VALUES (?,?)", (token_digest(token), user_id))
    return token


class User(NamedTuple):
    id: int
    username: str
    token_hash: str


_bearer = HTTPBearer(auto_error=False)


def current_user(creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)]) -> User:
    """Every data endpoint requires a logged-in user."""
    unauthorized = HTTPException(
        401, "Please log in again", headers={"WWW-Authenticate": "Bearer"}
    )
    if creds is None:
        raise unauthorized
    digest = token_digest(creds.credentials)
    with db() as c:
        row = c.execute(
            "SELECT u.id, u.username FROM sessions s JOIN users u ON u.id = s.user_id "
            "WHERE s.token_hash=? AND s.created >= datetime('now', ?)",
            (digest, f"-{SESSION_DAYS} days"),
        ).fetchone()
    if row is None:
        raise unauthorized
    return User(row["id"], row["username"], digest)


CurrentUser = Annotated[User, Depends(current_user)]


# ---- schemas ----
# a four-digit year from 0001 (dates before that do not exist), then a real month
MONTH_PATTERN = r"^(000[1-9]|00[1-9][0-9]|0[1-9][0-9]{2}|[1-9][0-9]{3})-(0[1-9]|1[0-2])$"
MAX_RUPEES = Decimal(10) ** 10  # 1,000 crore: far beyond any personal budget, far below overflow
Rupees = Annotated[Decimal, Field(decimal_places=2, le=MAX_RUPEES)]
RowId = Annotated[int, PathParam(ge=1, le=2**63 - 1)]
Month = Annotated[str, Query(pattern=MONTH_PATTERN)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=60)]
Note = Annotated[str, StringConstraints(max_length=500)]
Username = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=3, max_length=30, pattern=r"^[A-Za-z0-9_.-]+$")
]


class RegisterIn(BaseModel):
    username: Username
    password: str = Field(min_length=8, max_length=128)


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=128)


class ExpenseIn(BaseModel):
    amount: Rupees = Field(gt=0)
    date: date
    category: Name
    note: Note = ""


class BudgetIn(BaseModel):
    category: Name
    month: str = Field(pattern=MONTH_PATTERN)
    cap: Rupees = Field(ge=0)


class RecurringIn(BaseModel):
    amount: Rupees = Field(gt=0)
    category: Name
    note: Note = ""
    day_of_month: StrictInt = Field(ge=1, le=28)


class GoalIn(BaseModel):
    name: Name
    target: Rupees = Field(gt=0)
    deadline: date | None = None


class ContributeIn(BaseModel):
    amount: Rupees = Field(gt=0)


class AccountIn(BaseModel):
    opening_balance: Rupees = Field(ge=0)
    low_balance_threshold: Rupees = Field(ge=0)


def expense_out(r):
    d = dict(r)
    d.pop("user_id", None)
    d["amount"] = rupees(d["amount"])
    return d


# ---- accounts ----
@app.post("/auth/register", status_code=201)
def register(body: RegisterIn):
    with db() as c:
        try:
            cur = c.execute(
                "INSERT INTO users (username, password_hash) VALUES (?,?)",
                (body.username, hash_password(body.password)),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(409, "That username is already taken") from None
        c.execute("INSERT INTO account (user_id) VALUES (?)", (cur.lastrowid,))
        return {"token": new_session(c, cur.lastrowid), "username": body.username}


@app.post("/auth/login")
def login(body: LoginIn):
    with db() as c:
        row = c.execute(
            "SELECT id, username, password_hash FROM users WHERE username=?", (body.username.strip(),)
        ).fetchone()
        ok = check_password(body.password, row["password_hash"] if row else _DUMMY_HASH)
        if row is None or not ok:
            raise HTTPException(401, "Wrong username or password")
        return {"token": new_session(c, row["id"]), "username": row["username"]}


@app.post("/auth/logout", status_code=204)
def logout(user: CurrentUser):
    with db() as c:
        c.execute("DELETE FROM sessions WHERE token_hash=?", (user.token_hash,))


@app.get("/auth/me")
def me(user: CurrentUser):
    return {"username": user.username}


# ---- balance ----
def balance_state(c, uid: int):
    a = c.execute("SELECT * FROM account WHERE user_id=?", (uid,)).fetchone()
    spent = c.execute("SELECT COALESCE(SUM(amount),0) s FROM expenses WHERE user_id=?", (uid,)).fetchone()["s"]
    saved = c.execute("SELECT COALESCE(SUM(saved),0) s FROM goals WHERE user_id=?", (uid,)).fetchone()["s"]
    bal = a["opening"] - spent - saved
    return {
        "balance": rupees(bal),
        "low_balance_threshold": rupees(a["low_threshold"]),
        "low_balance": a["low_threshold"] > 0 and bal < a["low_threshold"],
    }


@app.get("/account")
def get_account(user: CurrentUser):
    with db() as c:
        a = c.execute("SELECT * FROM account WHERE user_id=?", (user.id,)).fetchone()
        return {"opening_balance": rupees(a["opening"]), **balance_state(c, user.id)}


@app.put("/account")
def set_account(a: AccountIn, user: CurrentUser):
    with db() as c:
        c.execute(
            "UPDATE account SET opening=?, low_threshold=? WHERE user_id=?",
            (to_paise(a.opening_balance), to_paise(a.low_balance_threshold), user.id),
        )
        return {"opening_balance": float(a.opening_balance), **balance_state(c, user.id)}


# ---- expenses ----
def _overspend(c, uid: int, category: str, month: str):
    b = c.execute(
        "SELECT cap FROM budgets WHERE user_id=? AND category=? AND month=?", (uid, category, month)
    ).fetchone()
    if not b:
        return None
    spent = c.execute(
        "SELECT COALESCE(SUM(amount),0) s FROM expenses "
        "WHERE user_id=? AND category=? AND substr(date,1,7)=?",
        (uid, category, month),
    ).fetchone()["s"]
    if spent > b["cap"]:
        return {"category": category, "month": month, "cap": rupees(b["cap"]),
                "spent": rupees(spent), "over_by": rupees(spent - b["cap"])}
    return None


@app.post("/expenses", status_code=201)
def add_expense(e: ExpenseIn, user: CurrentUser):
    cat = e.category.lower()
    with db() as c:
        cur = c.execute(
            "INSERT INTO expenses (user_id, amount, date, category, note) VALUES (?,?,?,?,?)",
            (user.id, to_paise(e.amount), e.date.isoformat(), cat, e.note),
        )
        row = c.execute("SELECT * FROM expenses WHERE id=?", (cur.lastrowid,)).fetchone()
        return {"expense": expense_out(row),
                "alert": _overspend(c, user.id, cat, e.date.isoformat()[:7]),
                **balance_state(c, user.id)}


@app.get("/expenses")
def list_expenses(user: CurrentUser, month: Month | None = None, category: str | None = None):
    q, args = "SELECT * FROM expenses WHERE user_id=?", [user.id]
    if month:
        q += " AND substr(date,1,7)=?"
        args.append(month)
    if category:
        q += " AND category=?"
        args.append(category.strip().lower())
    with db() as c:
        return [expense_out(r) for r in c.execute(q + " ORDER BY date DESC, id DESC", args)]


@app.put("/expenses/{expense_id}")
def update_expense(expense_id: RowId, e: ExpenseIn, user: CurrentUser):
    cat = e.category.lower()
    with db() as c:
        try:
            cur = c.execute(
                "UPDATE expenses SET amount=?, date=?, category=?, note=? WHERE id=? AND user_id=?",
                (to_paise(e.amount), e.date.isoformat(), cat, e.note, expense_id, user.id),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(409, "This recurring expense already exists on that date")
        if cur.rowcount == 0:
            raise HTTPException(404, "expense not found")
        row = c.execute("SELECT * FROM expenses WHERE id=?", (expense_id,)).fetchone()
        return {"expense": expense_out(row),
                "alert": _overspend(c, user.id, cat, e.date.isoformat()[:7]),
                **balance_state(c, user.id)}


@app.delete("/expenses/{expense_id}", status_code=204)
def delete_expense(expense_id: RowId, user: CurrentUser):
    with db() as c:
        if c.execute("DELETE FROM expenses WHERE id=? AND user_id=?", (expense_id, user.id)).rowcount == 0:
            raise HTTPException(404, "expense not found")


# ---- budgets ----
@app.put("/budgets")
def set_budget(b: BudgetIn, user: CurrentUser):
    with db() as c:
        c.execute(
            "INSERT INTO budgets (user_id, category, month, cap) VALUES (?,?,?,?) "
            "ON CONFLICT(user_id, category, month) DO UPDATE SET cap=excluded.cap",
            (user.id, b.category.lower(), b.month, to_paise(b.cap)),
        )
    return {"category": b.category.lower(), "month": b.month, "cap": float(b.cap)}


@app.get("/budgets")
def list_budgets(month: Month, user: CurrentUser):
    with db() as c:
        return [
            {"category": r["category"], "month": r["month"], "cap": rupees(r["cap"])}
            for r in c.execute(
                "SELECT * FROM budgets WHERE user_id=? AND month=? ORDER BY category", (user.id, month))
        ]


# ---- recurring templates ----
def _recurring_out(r):
    d = dict(r)
    d.pop("user_id", None)
    d["amount"] = rupees(d["amount"])
    return d


@app.post("/recurring", status_code=201)
def add_recurring(r: RecurringIn, user: CurrentUser):
    with db() as c:
        cur = c.execute(
            "INSERT INTO recurring (user_id, amount, category, note, day_of_month) VALUES (?,?,?,?,?)",
            (user.id, to_paise(r.amount), r.category.lower(), r.note, r.day_of_month),
        )
        return _recurring_out(c.execute("SELECT * FROM recurring WHERE id=?", (cur.lastrowid,)).fetchone())


@app.get("/recurring")
def list_recurring(user: CurrentUser):
    with db() as c:
        return [_recurring_out(r) for r in c.execute(
            "SELECT * FROM recurring WHERE user_id=? ORDER BY id", (user.id,))]


@app.delete("/recurring/{rid}", status_code=204)
def delete_recurring(rid: RowId, user: CurrentUser):
    with db() as c:
        if c.execute("DELETE FROM recurring WHERE id=? AND user_id=?", (rid, user.id)).rowcount == 0:
            raise HTTPException(404, "template not found")


@app.post("/recurring/apply")
def apply_recurring(month: Month, user: CurrentUser):
    """Create this month's expenses from templates. Safe to call repeatedly."""
    created = 0
    with db() as c:
        for t in c.execute("SELECT * FROM recurring WHERE user_id=?", (user.id,)).fetchall():
            d = f"{month}-{t['day_of_month']:02d}"
            # Already there this month (even if the user moved it to another day)?
            if c.execute(
                "SELECT 1 FROM expenses WHERE user_id=? AND recurring_id=? AND substr(date,1,7)=?",
                (user.id, t["id"], month),
            ).fetchone():
                continue
            cur = c.execute(
                "INSERT OR IGNORE INTO expenses (user_id, amount, date, category, note, recurring_id) "
                "VALUES (?,?,?,?,?,?)",
                (user.id, t["amount"], d, t["category"], t["note"], t["id"]),
            )
            created += cur.rowcount
    return {"month": month, "created": created}


# ---- savings goals ----
def _goal_out(r):
    d = dict(r)
    d.pop("user_id", None)
    d["target"], d["saved"] = rupees(d["target"]), rupees(d["saved"])
    d["progress"] = round(min(d["saved"] / d["target"], 1.0), 4)
    return d


@app.post("/goals", status_code=201)
def add_goal(g: GoalIn, user: CurrentUser):
    with db() as c:
        cur = c.execute(
            "INSERT INTO goals (user_id, name, target, deadline) VALUES (?,?,?,?)",
            (user.id, g.name, to_paise(g.target), g.deadline.isoformat() if g.deadline else None),
        )
        return _goal_out(c.execute("SELECT * FROM goals WHERE id=?", (cur.lastrowid,)).fetchone())


@app.get("/goals")
def list_goals(user: CurrentUser):
    with db() as c:
        return [_goal_out(r) for r in c.execute("SELECT * FROM goals WHERE user_id=? ORDER BY id", (user.id,))]


@app.post("/goals/{gid}/contribute")
def contribute(gid: RowId, body: ContributeIn, user: CurrentUser):
    with db() as c:
        cur = c.execute(
            "UPDATE goals SET saved = saved + ? WHERE id=? AND user_id=?",
            (to_paise(body.amount), gid, user.id),
        )
        if cur.rowcount == 0:
            raise HTTPException(404, "goal not found")
        return {"goal": _goal_out(c.execute("SELECT * FROM goals WHERE id=?", (gid,)).fetchone()),
                **balance_state(c, user.id)}


@app.delete("/goals/{gid}", status_code=204)
def delete_goal(gid: RowId, user: CurrentUser):
    with db() as c:
        if c.execute("DELETE FROM goals WHERE id=? AND user_id=?", (gid, user.id)).rowcount == 0:
            raise HTTPException(404, "goal not found")


# ---- dashboard ----
@app.get("/dashboard")
def dashboard(month: Month, user: CurrentUser):
    """Spent vs budget per category for a month, daily trend, balance state."""
    uid = user.id
    with db() as c:
        spent = {
            r["category"]: r["s"]
            for r in c.execute(
                "SELECT category, SUM(amount) s FROM expenses "
                "WHERE user_id=? AND substr(date,1,7)=? GROUP BY category", (uid, month))
        }
        caps = {
            r["category"]: r["cap"]
            for r in c.execute("SELECT category, cap FROM budgets WHERE user_id=? AND month=?", (uid, month))
        }
        trend = [
            {"date": r["date"], "total": rupees(r["s"])}
            for r in c.execute(
                "SELECT date, SUM(amount) s FROM expenses "
                "WHERE user_id=? AND substr(date,1,7)=? GROUP BY date ORDER BY date", (uid, month))
        ]
        bal = balance_state(c, uid)
    cats = []
    for name in sorted(set(spent) | set(caps)):
        s, cap = spent.get(name, 0), caps.get(name)
        cats.append({"category": name, "spent": rupees(s), "cap": rupees(cap),
                     "over": cap is not None and s > cap})
    return {"month": month, "total_spent": rupees(sum(spent.values())),
            "categories": cats, "trend": trend, **bal}


# Registered last so every API route above wins; anything else is a web app file.
class SafeStaticFiles(StaticFiles):
    async def get_response(self, path, scope):
        try:
            return await super().get_response(path, scope)
        except ValueError:  # e.g. an embedded NUL character in the path
            raise HTTPException(404)


if HAS_WEB:
    app.mount("/", SafeStaticFiles(directory=WEB_DIR, html=True), name="web")
