import os
import sqlite3
from contextlib import contextmanager
from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, StringConstraints

DB_PATH = os.environ.get("BUDGET_DB", "budget.db")

app = FastAPI(title="Budget Tracker")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


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


def init_db():
    with db() as c:
        c.executescript(
            """
            CREATE TABLE IF NOT EXISTS expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                amount INTEGER NOT NULL CHECK (amount > 0),
                date TEXT NOT NULL,
                category TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                recurring_id INTEGER,
                UNIQUE (recurring_id, date)
            );
            CREATE TABLE IF NOT EXISTS budgets (
                category TEXT NOT NULL,
                month TEXT NOT NULL,
                cap INTEGER NOT NULL CHECK (cap >= 0),
                PRIMARY KEY (category, month)
            );
            CREATE TABLE IF NOT EXISTS recurring (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                amount INTEGER NOT NULL CHECK (amount > 0),
                category TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                day_of_month INTEGER NOT NULL CHECK (day_of_month BETWEEN 1 AND 28)
            );
            CREATE TABLE IF NOT EXISTS goals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                target INTEGER NOT NULL CHECK (target > 0),
                saved INTEGER NOT NULL DEFAULT 0,
                deadline TEXT
            );
            CREATE TABLE IF NOT EXISTS account (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                opening INTEGER NOT NULL DEFAULT 0,
                low_threshold INTEGER NOT NULL DEFAULT 0
            );
            INSERT OR IGNORE INTO account (id) VALUES (1);
            """
        )


init_db()


# ---- schemas ----
MONTH_PATTERN = r"^\d{4}-(0[1-9]|1[0-2])$"
Month = Annotated[str, Query(pattern=MONTH_PATTERN)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class ExpenseIn(BaseModel):
    amount: Decimal = Field(gt=0, decimal_places=2)
    date: date
    category: Name
    note: str = ""


class BudgetIn(BaseModel):
    category: Name
    month: str = Field(pattern=MONTH_PATTERN)
    cap: Decimal = Field(ge=0, decimal_places=2)


class RecurringIn(BaseModel):
    amount: Decimal = Field(gt=0, decimal_places=2)
    category: Name
    note: str = ""
    day_of_month: int = Field(ge=1, le=28)


class GoalIn(BaseModel):
    name: Name
    target: Decimal = Field(gt=0, decimal_places=2)
    deadline: date | None = None


class ContributeIn(BaseModel):
    amount: Decimal = Field(gt=0, decimal_places=2)


class AccountIn(BaseModel):
    opening_balance: Decimal = Field(ge=0, decimal_places=2)
    low_balance_threshold: Decimal = Field(ge=0, decimal_places=2)


def expense_out(r):
    d = dict(r)
    d["amount"] = rupees(d["amount"])
    return d


# ---- balance ----
def balance_state(c):
    a = c.execute("SELECT * FROM account WHERE id=1").fetchone()
    spent = c.execute("SELECT COALESCE(SUM(amount),0) s FROM expenses").fetchone()["s"]
    saved = c.execute("SELECT COALESCE(SUM(saved),0) s FROM goals").fetchone()["s"]
    bal = a["opening"] - spent - saved
    return {
        "balance": rupees(bal),
        "low_balance_threshold": rupees(a["low_threshold"]),
        "low_balance": a["low_threshold"] > 0 and bal < a["low_threshold"],
    }


@app.get("/account")
def get_account():
    with db() as c:
        a = c.execute("SELECT * FROM account WHERE id=1").fetchone()
        return {"opening_balance": rupees(a["opening"]), **balance_state(c)}


@app.put("/account")
def set_account(a: AccountIn):
    with db() as c:
        c.execute(
            "UPDATE account SET opening=?, low_threshold=? WHERE id=1",
            (to_paise(a.opening_balance), to_paise(a.low_balance_threshold)),
        )
        return {"opening_balance": float(a.opening_balance), **balance_state(c)}


# ---- expenses ----
def _overspend(c, category: str, month: str):
    b = c.execute(
        "SELECT cap FROM budgets WHERE category=? AND month=?", (category, month)
    ).fetchone()
    if not b:
        return None
    spent = c.execute(
        "SELECT COALESCE(SUM(amount),0) s FROM expenses WHERE category=? AND substr(date,1,7)=?",
        (category, month),
    ).fetchone()["s"]
    if spent > b["cap"]:
        return {"category": category, "month": month, "cap": rupees(b["cap"]),
                "spent": rupees(spent), "over_by": rupees(spent - b["cap"])}
    return None


@app.post("/expenses", status_code=201)
def add_expense(e: ExpenseIn):
    cat = e.category.lower()
    with db() as c:
        cur = c.execute(
            "INSERT INTO expenses (amount, date, category, note) VALUES (?,?,?,?)",
            (to_paise(e.amount), e.date.isoformat(), cat, e.note),
        )
        row = c.execute("SELECT * FROM expenses WHERE id=?", (cur.lastrowid,)).fetchone()
        return {"expense": expense_out(row),
                "alert": _overspend(c, cat, e.date.isoformat()[:7]),
                **balance_state(c)}


@app.get("/expenses")
def list_expenses(month: Month | None = None, category: str | None = None):
    q, args = "SELECT * FROM expenses WHERE 1=1", []
    if month:
        q += " AND substr(date,1,7)=?"
        args.append(month)
    if category:
        q += " AND category=?"
        args.append(category.lower())
    with db() as c:
        return [expense_out(r) for r in c.execute(q + " ORDER BY date DESC, id DESC", args)]


@app.put("/expenses/{expense_id}")
def update_expense(expense_id: int, e: ExpenseIn):
    with db() as c:
        cur = c.execute(
            "UPDATE expenses SET amount=?, date=?, category=?, note=? WHERE id=?",
            (to_paise(e.amount), e.date.isoformat(), e.category.lower(), e.note, expense_id),
        )
        if cur.rowcount == 0:
            raise HTTPException(404, "expense not found")
        return expense_out(c.execute("SELECT * FROM expenses WHERE id=?", (expense_id,)).fetchone())


@app.delete("/expenses/{expense_id}", status_code=204)
def delete_expense(expense_id: int):
    with db() as c:
        if c.execute("DELETE FROM expenses WHERE id=?", (expense_id,)).rowcount == 0:
            raise HTTPException(404, "expense not found")


# ---- budgets ----
@app.put("/budgets")
def set_budget(b: BudgetIn):
    with db() as c:
        c.execute(
            "INSERT INTO budgets (category, month, cap) VALUES (?,?,?) "
            "ON CONFLICT(category, month) DO UPDATE SET cap=excluded.cap",
            (b.category.lower(), b.month, to_paise(b.cap)),
        )
    return {"category": b.category.lower(), "month": b.month, "cap": float(b.cap)}


@app.get("/budgets")
def list_budgets(month: Month):
    with db() as c:
        return [
            {"category": r["category"], "month": r["month"], "cap": rupees(r["cap"])}
            for r in c.execute("SELECT * FROM budgets WHERE month=? ORDER BY category", (month,))
        ]


# ---- recurring templates ----
@app.post("/recurring", status_code=201)
def add_recurring(r: RecurringIn):
    with db() as c:
        cur = c.execute(
            "INSERT INTO recurring (amount, category, note, day_of_month) VALUES (?,?,?,?)",
            (to_paise(r.amount), r.category.lower(), r.note, r.day_of_month),
        )
        return _recurring_out(c.execute("SELECT * FROM recurring WHERE id=?", (cur.lastrowid,)).fetchone())


def _recurring_out(r):
    d = dict(r)
    d["amount"] = rupees(d["amount"])
    return d


@app.get("/recurring")
def list_recurring():
    with db() as c:
        return [_recurring_out(r) for r in c.execute("SELECT * FROM recurring ORDER BY id")]


@app.delete("/recurring/{rid}", status_code=204)
def delete_recurring(rid: int):
    with db() as c:
        if c.execute("DELETE FROM recurring WHERE id=?", (rid,)).rowcount == 0:
            raise HTTPException(404, "template not found")


@app.post("/recurring/apply")
def apply_recurring(month: Month):
    """Create this month's expenses from templates. Safe to call repeatedly."""
    created = 0
    with db() as c:
        for t in c.execute("SELECT * FROM recurring").fetchall():
            d = f"{month}-{t['day_of_month']:02d}"
            cur = c.execute(
                "INSERT OR IGNORE INTO expenses (amount, date, category, note, recurring_id) "
                "VALUES (?,?,?,?,?)",
                (t["amount"], d, t["category"], t["note"], t["id"]),
            )
            created += cur.rowcount
    return {"month": month, "created": created}


# ---- savings goals ----
def _goal_out(r):
    d = dict(r)
    d["target"], d["saved"] = rupees(d["target"]), rupees(d["saved"])
    d["progress"] = round(min(d["saved"] / d["target"], 1.0), 4)
    return d


@app.post("/goals", status_code=201)
def add_goal(g: GoalIn):
    with db() as c:
        cur = c.execute(
            "INSERT INTO goals (name, target, deadline) VALUES (?,?,?)",
            (g.name, to_paise(g.target), g.deadline.isoformat() if g.deadline else None),
        )
        return _goal_out(c.execute("SELECT * FROM goals WHERE id=?", (cur.lastrowid,)).fetchone())


@app.get("/goals")
def list_goals():
    with db() as c:
        return [_goal_out(r) for r in c.execute("SELECT * FROM goals ORDER BY id")]


@app.post("/goals/{gid}/contribute")
def contribute(gid: int, body: ContributeIn):
    with db() as c:
        if not c.execute("SELECT 1 FROM goals WHERE id=?", (gid,)).fetchone():
            raise HTTPException(404, "goal not found")
        c.execute("UPDATE goals SET saved = saved + ? WHERE id=?", (to_paise(body.amount), gid))
        return {"goal": _goal_out(c.execute("SELECT * FROM goals WHERE id=?", (gid,)).fetchone()),
                **balance_state(c)}


@app.delete("/goals/{gid}", status_code=204)
def delete_goal(gid: int):
    with db() as c:
        if c.execute("DELETE FROM goals WHERE id=?", (gid,)).rowcount == 0:
            raise HTTPException(404, "goal not found")


# ---- dashboard ----
@app.get("/dashboard")
def dashboard(month: Month):
    """Spent vs budget per category for a month, daily trend, balance state."""
    with db() as c:
        spent = {
            r["category"]: r["s"]
            for r in c.execute(
                "SELECT category, SUM(amount) s FROM expenses "
                "WHERE substr(date,1,7)=? GROUP BY category", (month,))
        }
        caps = {
            r["category"]: r["cap"]
            for r in c.execute("SELECT category, cap FROM budgets WHERE month=?", (month,))
        }
        trend = [
            {"date": r["date"], "total": rupees(r["s"])}
            for r in c.execute(
                "SELECT date, SUM(amount) s FROM expenses "
                "WHERE substr(date,1,7)=? GROUP BY date ORDER BY date", (month,))
        ]
        bal = balance_state(c)
    cats = []
    for name in sorted(set(spent) | set(caps)):
        s, cap = spent.get(name, 0), caps.get(name)
        cats.append({"category": name, "spent": rupees(s), "cap": rupees(cap),
                     "over": cap is not None and s > cap})
    return {"month": month, "total_spent": rupees(sum(spent.values())),
            "categories": cats, "trend": trend, **bal}
