"""Edge-path QA of the whole site, like a meticulous manual tester, codified.

Beyond walkthrough.py and demo_tour.py (which cover the happy path) this drives the real
Flutter web app in Chrome through the awkward paths: odd inputs on every field, dates and
months, sessions and two browsers, filters and undo, offline / sleeping / slow servers,
keyboard use, resizing, the landing page and the page metadata.

    cd backend && BUDGET_DB=edge.db uvicorn main:app --port 8010      # fresh DB, serves the app
    python seed_demo.py --api http://127.0.0.1:8010                   # demo / demo-password
    PYTHONIOENCODING=utf-8 BROWSER_CHANNEL=chrome BASE_URL=http://127.0.0.1:8010/ \\
        python e2e/edge_paths.py                                      # desktop 1280x800
    ... VIEWPORT_W=390 VIEWPORT_H=844 python e2e/edge_paths.py        # phone

Environment:
    BASE_URL       app + API origin (default http://127.0.0.1:8000/)
    VIEWPORT_W/H   window size (default 1280x800); under 760 px wide the phone layout is used
    SECTIONS       comma separated section numbers to run, e.g. SECTIONS=1,5,11 (default: all)
    SHOTS          screenshot folder (default e2e-shots/edge-<W>x<H>)
    STRICT_BUGS=1  also exit non-zero when a known-bug check fails (default: only on FAIL)
    SLOW           multiply the waits on a slow machine

Output: "PASS name" / "FAIL name" for a check that should hold (a FAIL is a script problem or a
regression), "BUG  id name" for a check of correct behaviour that the app currently gets wrong
(it passes by itself once the app is fixed), "NOTE" for an observation. A summary of the bugs
and of console / network noise is printed at the end. Every run creates its own users, so it
works on any database, and it never touches the demo account.
"""
import contextlib
import datetime
import json
import os
import re
import sys
import time
import traceback
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VW = int(os.environ.get("VIEWPORT_W", "1280"))
VH = int(os.environ.get("VIEWPORT_H", "800"))
WIDE = VW >= 760  # the app's own breakpoint (kWideBreakpoint)
os.environ.setdefault("SHOTS", os.path.join(ROOT, "e2e-shots", f"edge-{VW}x{VH}"))
sys.path.insert(0, HERE)

from playwright.sync_api import sync_playwright  # noqa: E402

import common  # noqa: E402
from common import App, BASE_URL, BUTTONS_JS, TABS, norm  # noqa: E402

SHOTS = common.SHOTS
API = BASE_URL.rstrip("/")
STRICT_BUGS = os.environ.get("STRICT_BUGS") == "1"

TODAY = datetime.date.today()


def add_months(d, n):
    y, m = divmod(d.year * 12 + d.month - 1 + n, 12)
    return datetime.date(y, m + 1, 1)


def mlabel(n=0):
    """'October 2026' for the month n months from this one."""
    return add_months(TODAY, n).strftime("%B %Y")


def mkey(n=0):
    return add_months(TODAY, n).strftime("%Y-%m")


# ------------------------------------------------------------------ results
results = []  # (name, status) status: PASS FAIL BUG
bugs = {}  # id -> dict
notes = []
events = []  # console / network noise
PHASE = "start"
QUIET = False  # True while a test deliberately breaks the network
CUR = {"app": None}
_seq = [0]


def shot(name):
    app = CUR["app"]
    if app is not None:
        try:
            app.shot(name)
        except Exception:
            pass


def step(name, ok, detail=""):
    ok = bool(ok)
    results.append((name, "PASS" if ok else "FAIL"))
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    if not ok:
        _seq[0] += 1
        shot(f"fail-{_seq[0]:02d}.png")
        if detail:
            print("     detail:", str(detail)[:400], flush=True)
        app = CUR["app"]
        if app is not None:
            try:
                print("     page text:", app.text()[:300], flush=True)
            except Exception:
                pass
    return ok


def bug(bid, title, ok, sev="medium", repro="", observed="", expected="", fix="", shot_name=None, take_shot=True):
    """A check of the behaviour a user should get. While the app gets it wrong this prints BUG
    and records the details for the final list; it is not a FAIL."""
    ok = bool(ok)
    if ok:
        results.append((f"{bid} {title}", "PASS"))
        print(f"PASS [{bid}] {title}", flush=True)
        return True
    results.append((f"{bid} {title}", "BUG"))
    print(f"BUG  [{bid}] ({sev}) {title}", flush=True)
    if observed:
        print("     observed:", str(observed)[:300], flush=True)
    sn = shot_name or f"bug-{bid}.png"
    if bid not in bugs:
        if take_shot:
            shot(sn)
        bugs[bid] = dict(id=bid, sev=sev, title=title, repro=repro, observed=observed,
                         expected=expected, fix=fix, shot=os.path.join(SHOTS, sn), phase=PHASE)
    return False


def note(text):
    notes.append((PHASE, text))
    print("NOTE " + text, flush=True)


# ------------------------------------------------------------------ HTTP helper
def api(method, path, body=None, token=None, raw=None):
    """Call the backend directly. Returns (status, parsed json or text)."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    req = urllib.request.Request(API + path, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            txt = r.read().decode()
            status = r.status
    except urllib.error.HTTPError as e:
        txt, status = e.read().decode(), e.code
    try:
        return status, (json.loads(txt) if txt else None)
    except ValueError:
        return status, txt


RUN = format(int(time.time() * 1000) % (36 ** 5), "x").rjust(4, "0")  # short, unique per run
PW = "edge test pw 1"
_users = [0]


def mk_user(tag="u", opening=None, line=None):
    """Register a fresh user straight through the API: (name, password, token)."""
    _users[0] += 1
    name = f"e{RUN}{tag}{_users[0]}"[:30]
    st, r = api("POST", "/auth/register", {"username": name, "password": PW})
    assert st == 201, (st, r)
    tok = r["token"]
    if opening is not None or line is not None:
        api("PUT", "/account", {"opening_balance": opening or 0, "low_balance_threshold": line or 0}, tok)
    return name, PW, tok


def add_exp(tok, amount, category, date=None, note="", month_offset=0, day=None):
    if date is None:
        d = add_months(TODAY, month_offset)
        date = d.replace(day=day or min(TODAY.day, 28)).isoformat()
    st, r = api("POST", "/expenses", {"amount": amount, "date": date, "category": category, "note": note}, tok)
    assert st == 201, (st, r)
    return r["expense"]


def list_exp(tok, month=None):
    st, r = api("GET", "/expenses" + (f"?month={month}" if month else ""), token=tok)
    return r


def account(tok):
    return api("GET", "/account", token=tok)[1]


# ------------------------------------------------------------------ browser plumbing
class Net:
    """Remembers the API calls a page makes, so a test can say what reached the server."""

    def __init__(self, page):
        self.reqs = []
        self.resps = []
        page.on("request", self._req)
        page.on("response", self._resp)

    def _req(self, r):
        if r.resource_type in ("fetch", "xhr"):
            self.reqs.append((r.method, r.url.replace(API, ""), r.post_data))

    def _resp(self, r):
        if r.request.resource_type in ("fetch", "xhr"):
            self.resps.append((r.request.method, r.url.replace(API, ""), r.status))

    def mark(self):
        return (len(self.reqs), len(self.resps))

    def sent(self, since, method=None, path=None):
        out = [q for q in self.reqs[since[0]:]]
        if method:
            out = [q for q in out if q[0] == method]
        if path:
            out = [q for q in out if path in q[1]]
        return out

    def statuses(self, since, path=None):
        out = self.resps[since[1]:]
        return [s for (m, u, s) in out if not path or path in u]

    def body(self, since, method, path):
        """JSON body of the last matching request, or None."""
        q = self.sent(since, method, path)
        try:
            return json.loads(q[-1][2]) if q else None
        except (TypeError, ValueError):
            return None


def hook(page):
    def on_console(m):
        if m.type == "error" and not m.text.startswith("Failed to load resource"):
            events.append(dict(phase=PHASE, kind="console", text=m.text[:200], quiet=QUIET))

    def on_failed(r):
        events.append(dict(phase=PHASE, kind="requestfailed",
                           text=f"{r.method} {r.url.replace(API, '')} {r.failure}", quiet=QUIET))

    def on_resp(r):
        if r.status >= 400:
            events.append(dict(phase=PHASE, kind=f"http{r.status}",
                               text=f"{r.request.method} {r.url.replace(API, '')}", quiet=QUIET))

    page.on("console", on_console)
    def on_pageerror(e):
        try:
            text = f"{e.name}: {e.message}"[:140] + " | " + " ".join((e.stack or "").split())[:160]
        except Exception:
            text = str(e)[:200]
        last = results[-1][0] if results else "-"
        events.append(dict(phase=PHASE, kind="pageerror", text=f"{text} [after: {last[:60]}]", quiet=QUIET))

    page.on("pageerror", on_pageerror)
    page.on("requestfailed", on_failed)
    page.on("response", on_resp)
    page.on("dialog", lambda d: (events.append(dict(phase=PHASE, kind="JS-DIALOG", text=d.message, quiet=False)), d.dismiss()))


@contextlib.contextmanager
def chrome(p):
    b = p.chromium.launch(channel=common.CHANNEL, headless=True)
    try:
        yield b
    finally:
        try:
            b.close()
        except Exception:
            pass


def enable_a11y(page):
    page.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=90000)
    page.wait_for_timeout(1500)
    page.evaluate("document.querySelector('flt-semantics-placeholder').click()")
    page.wait_for_timeout(1500)


def open_page(browser, token=None, w=None, h=None, scale=1, url=None, scheme="dark", goto=True):
    """A fresh browser context with the app open. With a token the session is pre-seeded
    (as if the user had logged in earlier), so the test starts on the dashboard."""
    w, h = w or VW, h or VH
    common.WIDTH, common.HEIGHT = w, h
    ctx = browser.new_context(viewport={"width": w, "height": h}, color_scheme=scheme, device_scale_factor=scale)
    if token:
        # seeded once per tab (sessionStorage survives a reload), so a reload keeps whatever the app did since
        ctx.add_init_script("if (!sessionStorage.getItem('seeded')) { sessionStorage.setItem('seeded', '1'); "
                            f"localStorage.setItem('flutter.session_token', JSON.stringify('{token}')); }}")
    page = ctx.new_page()
    hook(page)
    net = Net(page)
    app = App(page)
    CUR["app"] = app
    if goto:
        page.goto(url or BASE_URL)
        enable_a11y(page)
    return ctx, page, app, net


def login_as(browser, user, **kw):
    """Open the app already logged in as a user made by mk_user()."""
    name, pw, tok = user
    ctx, page, app, net = open_page(browser, token=tok, **kw)
    ok = app.has(f"Hi, {name.capitalize()}", 15000)
    return ctx, page, app, net, ok


def refresh_tab(app, name):
    """Flutter web's accessibility DOM can lag the canvas; re-open the section to read it."""
    other = "Goals" if name != "Goals" else "Dashboard"
    app.tab(other)
    app.tab(name)


def see(app, needle, tab=None, timeout=6000):
    """has(), and if it is missing re-open the section once (see refresh_tab)."""
    if app.has(needle, timeout):
        return True
    if tab:
        refresh_tab(app, tab)
        return app.has(needle, timeout)
    return False


def dialog_open(app):
    return app.count(r"^Save$") > 0 or app.count(r"^Cancel$") > 0


def field(app, label, exact=False):
    """The text currently in a field. Flutter fills the <input> only once the field has focus,
    so an empty reading is repeated after clicking into the field."""
    loc = app.pg.get_by_label(label, exact=exact).first
    try:
        val = loc.input_value(timeout=1500)
        if val:
            return val
    except Exception:
        pass
    try:
        loc.click()
        val = ""
        for _ in range(8):  # the text arrives a moment after the field is focused
            app.wait(300)
            val = app.pg.evaluate("(document.activeElement && document.activeElement.tagName === 'INPUT') ? document.activeElement.value : ''")
            if val:
                break
        return val
    except Exception:
        return None


def selected(app, name):
    """aria-current of the button with this exact name: the chosen filter tab / category pill."""
    return app.pg.evaluate(
        """(n) => { const e = Array.from(document.querySelectorAll('flt-semantics[role=button]')).find(
            x => ((x.getAttribute('aria-label') || x.textContent || '').trim().replace(/\\s+/g, ' ')) === n);
          return e ? e.getAttribute('aria-current') === 'true' : null; }""", name)


OVERFLOW_JS = r"""() => {
  const W = innerWidth, bad = [];
  document.querySelectorAll('flt-semantics').forEach(e => {
    const r = e.getBoundingClientRect();
    if (r.width > 0 && r.height > 0 && (r.right > W + 2 || r.left < -2))
      bad.push(((e.getAttribute('aria-label') || e.textContent || '').trim().slice(0, 30)) + ' [' + Math.round(r.left) + ',' + Math.round(r.right) + ']');
  });
  return {scrollW: document.documentElement.scrollWidth, W, bad: bad.slice(0, 8)};
}"""


def overflow(app):
    """Semantic boxes that stick out of the window sideways (a rough overflow detector)."""
    return app.pg.evaluate(OVERFLOW_JS)


def btn_rects(app, names):
    """Bounding boxes of the buttons with these exact names (the first of each)."""
    return app.pg.evaluate(
        """(names) => names.map(n => {
          const e = Array.from(document.querySelectorAll('flt-semantics[role=button]')).find(
            x => ((x.getAttribute('aria-label') || x.textContent || '').trim().replace(/\\s+/g, ' ')) === n);
          if (!e) return null; const r = e.getBoundingClientRect();
          return {n, x: r.x, y: r.y, w: r.width, h: r.height};
        })""", names)


def scroll_down(app, times=1, dy=None):
    app.pg.mouse.move(common.WIDTH / 2, common.HEIGHT / 2)
    for _ in range(times):
        app.pg.mouse.wheel(0, dy or common.HEIGHT * 0.7)
        app.wait(300)


def scroll_top(app):
    app.pg.mouse.move(common.WIDTH / 2, common.HEIGHT / 2)
    app.pg.mouse.wheel(0, -20000)
    app.wait(400)


def shotname(sec, name):
    return f"s{sec:02d}-{name}.png"


SECTIONS = {}


def sec(n, title):
    def deco(fn):
        SECTIONS[n] = (title, fn)
        return fn
    return deco


def http_get(path):
    """GET a static path: (status, content-type, text/bytes length, text)."""
    req = urllib.request.Request(API + path)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            body = r.read()
            return r.status, r.headers.get("content-type", ""), body.decode("utf-8", "replace"), dict(r.headers)
    except urllib.error.HTTPError as e:
        body = e.read()
        return e.code, e.headers.get("content-type", ""), body.decode("utf-8", "replace"), dict(e.headers)


# ==================================================================== 12 landing
@sec(12, "Landing page and page metadata")
def sec_landing(p):
    with chrome(p) as br:
        ctx, page, app, net = open_page(br)
        step("landing: the product page is shown first", app.has("Know where your money goes."))
        step("landing: no overflow at first paint", not overflow(app)["bad"] and overflow(app)["scrollW"] <= overflow(app)["W"],
             overflow(app))

        # every Create account / Log in button, in the nav, the hero and the closing panel
        def go_home():
            if app.has("Back to home", 500):
                app.button("Back to home")
                app.has("Know where your money goes.", 4000)

        def click_nth(label, which):
            go_home()
            scroll_top(app)
            if which == "closing":
                for _ in range(8):
                    scroll_down(app, 1, common.HEIGHT)
                    if app.has("Start with this month.", 300):
                        break
                scroll_down(app, 3, common.HEIGHT)
            loc = page.get_by_role("button", name=re.compile(rf"^{re.escape(label)}$"))
            boxes = []
            for i in range(loc.count()):
                b = loc.nth(i).bounding_box()
                if b:
                    boxes.append((b["y"], i))
            boxes.sort()
            idx = {"nav": 0, "hero": 1, "closing": -1}[which]
            if not boxes:
                return False
            if which == "hero" and len(boxes) < 2:
                return False
            loc.nth(boxes[idx][1]).click()
            app.wait(1200)
            return True

        for label, which, expect in [("Log in", "nav", "Welcome back"), ("Create account", "nav", "Create your account"),
                                     ("Log in", "hero", "Welcome back"), ("Create account", "hero", "Create your account"),
                                     ("Create account", "closing", "Create your account")]:
            clicked = click_nth(label, which)
            step(f"landing: the {which} '{label}' button opens '{expect}'", clicked and app.has(expect, 4000))
            if not clicked:
                shot(shotname(12, f"missing-{which}-{label.replace(' ', '')}"))
            go_home()
        step("landing: Back to home returns to the landing page", app.has("Know where your money goes."))

        # scroll through the page, nothing may stick out sideways
        scroll_top(app)
        seen = []
        alltxt = ""
        for i in range(10):
            ov = overflow(app)
            seen.append(ov)
            alltxt += " " + app.text()
            if i in (0, 2, 4, 6):
                app.shot(shotname(12, f"landing-scroll{i}"))
            scroll_down(app, 1, common.HEIGHT * 0.8)
        step("landing: scrolling the page never overflows sideways",
             all(not o["bad"] and o["scrollW"] <= o["W"] for o in seen), [o for o in seen if o["bad"]][:2])
        scroll_down(app, 6, common.HEIGHT)
        step("landing: the footer is reachable at the bottom", app.has("A prototype for a small number of users"))
        app.shot(shotname(12, "landing-bottom"))
        txt = alltxt
        step("landing: features, steps and closing call to action are on the page",
             all(s in txt for s in ["Five screens", "How it works", "Start with this month"]))

        # page metadata
        title = page.evaluate("document.title")
        note(f"landing: document.title at run time is {title!r}")
        step("meta: the tab title is the product name", title == "Budget Tracker")
        st, ct, html, _ = http_get("/")
        m = re.search(r"<title>(.*?)</title>", html, re.S)
        static_title = m.group(1) if m else None
        desc = re.search(r'name="description" content="(.*?)"', html)
        desc = desc.group(1) if desc else None
        note(f"meta: static index.html title={static_title!r}, description={desc!r}, "
             f"<html lang>={'yes' if re.search(r'<html[^>]*lang=', html) else 'missing'}")
        bug("META-1", "index.html still carries the Flutter template metadata",
            static_title == "Budget Tracker" and desc and "A new Flutter project" not in desc,
            sev="low",
            repro="curl http://<host>/ and read <title>, <meta name=description>, apple-mobile-web-app-title",
            observed=f"title={static_title!r}, description={desc!r} (visible in link previews, search results, and the tab until the app boots)",
            expected="title 'Budget Tracker' and a real one-line description",
            fix="app/web/index.html (<title>, meta description, apple-mobile-web-app-title); then rebuild into backend/web",
            shot_name=shotname(12, "landing-scroll0"))
        st, ct, mj, _ = http_get("/manifest.json")
        man = json.loads(mj) if st == 200 else {}
        note(f"meta: manifest name={man.get('name')!r} short_name={man.get('short_name')!r} "
             f"theme_color={man.get('theme_color')} background_color={man.get('background_color')} description={man.get('description')!r}")
        bug("META-2", "manifest.json is the Flutter template (name 'budget_tracker', blue #0175C2 theme, 'A new Flutter project.')",
            man.get("name") == "Budget Tracker" and "new Flutter project" not in man.get("description", "")
            and man.get("theme_color", "").lower() != "#0175c2",
            sev="low", repro="open /manifest.json, or install the PWA / add to home screen",
            observed=json.dumps({k: man.get(k) for k in ("name", "short_name", "theme_color", "background_color", "description")}),
            expected="product name, the app's midnight colours, a real description",
            fix="app/web/manifest.json")
        icons_ok = all(http_get("/" + i["src"])[0] == 200 for i in man.get("icons", []))
        step("meta: every manifest icon exists", icons_ok)
        st, ct, _, _ = http_get("/favicon.png")
        step("meta: favicon.png is served as an image", st == 200 and ct.startswith("image/"), (st, ct))
        icon_href = page.evaluate("(document.querySelector('link[rel~=icon]')||{}).href || null")
        note(f"meta: <link rel=icon> -> {icon_href}")
        st, ct, body, _ = http_get("/favicon.ico")
        note(f"meta: /favicon.ico -> HTTP {st} (browsers only ask for it when there is no <link rel=icon>)")
        vp = page.evaluate("(document.querySelector('meta[name=viewport]')||{}).content || null")
        step("meta: a viewport meta tag is present at run time", vp is not None, vp)
        ctx.close()


# ==================================================================== 4 dates and months
def pick_date(app, target_offset, day, from_offset=0):
    """In the expense dialog: open the date picker, go to the month `target_offset` months from
    this one, click `day`, press OK. Returns the dialog's Date button name afterwards."""
    pg = app.pg
    pg.get_by_role("button", name=re.compile(r"^Date, ")).first.click()
    app.wait(900)
    delta = target_offset - from_offset
    nav = "Next month" if delta > 0 else "Previous month"
    for _ in range(abs(delta)):
        pg.get_by_role("button", name=nav, exact=True).first.click()
        app.wait(450)
    d = add_months(TODAY, target_offset).replace(day=day)
    rx = rf"^{day}, {d.strftime('%A')}, {d.strftime('%B')} {day}, {d.year}"
    pg.get_by_role("button", name=re.compile(rx)).first.click()
    app.wait(400)
    pg.get_by_role("button", name="OK", exact=True).first.click()
    app.wait(900)
    names = [n for n in pg.evaluate(BUTTONS_JS) if n.startswith("Date, ")]
    return names[0] if names else None


def add_dated(app, amount, category, offset, day, note_=""):
    app.tab("Expenses")
    app.button("Add expense")
    app.fill("Amount", str(amount))
    fill_text(app, "Category", category)
    if note_:
        fill_text(app, "Note", note_)
    label = pick_date(app, offset, day)
    app.save()
    return label


@sec(4, "Dates, month navigation, per-month views")
def sec_dates(p):
    with chrome(p) as br:
        user = mk_user("d", opening=1000)
        tok = user[2]
        ctx, page, app, net, ok = login_as(br, user)
        step("dates: logged in", ok)
        prev1 = add_months(TODAY, -1)
        next1 = add_months(TODAY, 1)

        # ---- the picker itself
        app.tab("Expenses")
        app.button("Add expense")
        names = [n for n in page.evaluate(BUTTONS_JS) if n.startswith("Date, ")]
        step("dates: the dialog starts on today", names and names[0].startswith("Date, Today"), names)
        page.get_by_role("button", name=re.compile(r"^Date, ")).first.click()
        app.wait(900)
        page.get_by_role("button", name=re.compile(r"^Select year")).first.click()
        app.wait(900)
        years = [n for n in page.evaluate(BUTTONS_JS) if re.fullmatch(r"\d{4}", n)]
        app.shot(shotname(4, "picker-years"))
        step("dates: the picker offers five years back and one year ahead",
             str(TODAY.year - 5) in years and str(TODAY.year + 1) in years
             and str(TODAY.year - 6) not in years and str(TODAY.year + 2) not in years, years)
        page.keyboard.press("Escape")
        app.wait(600)
        if not app.count(r"^Date, "):  # Escape closed the whole dialog: reopen it
            if not dialog_open(app):
                app.button("Add expense")
        if app.count(r"^Select year") or app.count(r"^OK$"):
            app.press(r"^Cancel$")
        if dialog_open(app) and app.count(r"^Date, "):
            app.cancel()

        # ---- a day in the previous month
        label = add_dated(app, 11, "DatePrev", -1, 15)
        note(f"dates: the dialog's Date button reads {label!r}")
        step("dates: the picked date shows in the dialog", bool(label) and f"15 {prev1.strftime('%b')}" in label, label)
        step("dates: saving a previous-month expense says which month it went to",
             app.has(f"Added Dateprev ₹11 to {mlabel(-1)}", 6000))
        app.snack_gone()
        app.tab("Expenses")
        step("dates: ... and the current month's list does not show it", app.gone("DatePrev", 2000) and app.has(f"No expenses in {mlabel(0)}"))
        app.month_prev()
        step("dates: the previous month's list shows it", see(app, "Dateprev", "Expenses") and app.has(mlabel(-1)))
        app.tab("Dashboard")
        step("dates: the previous month's dashboard counts it and the balance reflects it (1000-11)",
             app.has("You have ₹989 left") and app.has("₹11"))
        app.month_next()

        # ---- an earlier day in this month
        label = add_dated(app, 12, "DateEarly", 0, 3)
        step("dates: an earlier day of this month is accepted with no 'to <month>' suffix",
             app.has("Added Dateearly ₹12", 6000) and app.gone(f"Added Dateearly ₹12 to", 300))
        app.snack_gone()
        refresh_tab(app, "Expenses")
        step("dates: ... and it is listed under this month with that day",
             app.count(r"^Edit Dateearly ₹12$") == 1 and app.has("3 Oct"), page.evaluate(BUTTONS_JS))
        step("dates: ... dated as picked", any(e["date"] == add_months(TODAY, 0).replace(day=3).isoformat() for e in list_exp(tok)))

        # ---- a future month; the balance counts it
        label = add_dated(app, 13, "DateFuture", 1, 10)
        step("dates: a future-month expense is accepted and names the month",
             app.has(f"Added Datefuture ₹13 to {mlabel(1)}", 6000))
        app.snack_gone()
        app.tab("Dashboard")
        step("dates: the balance already includes the future expense (1000-11-12-13 = 964)", app.has("You have ₹964 left"))
        note("dates: balance = opening - ALL expenses, including ones dated in future months (by design?)")
        app.tab("Expenses")
        app.month_next()
        step("dates: next month's list shows the future expense", see(app, "Datefuture", "Expenses") and app.has(mlabel(1)))
        app.month_prev()

        # ---- the picker label repeats the date
        app.tab("Expenses")
        app.button("Add expense")
        page.get_by_role("button", name=re.compile(r"^Date, ")).first.click()
        app.wait(800)
        page.get_by_role("button", name=re.compile(r"^Previous month$")).first.click()
        app.wait(400)
        page.get_by_role("button", name=re.compile(r"^20, ")).first.click()
        app.wait(300)
        page.get_by_role("button", name="OK", exact=True).first.click()
        app.wait(900)
        dlabel = [n for n in page.evaluate(BUTTONS_JS) if n.startswith("Date, ")][0]
        app.shot(shotname(4, "date-label"))
        dup = len(re.findall(r"\b20 [A-Z][a-z]{2}\b", dlabel)) > 1
        bug("DATE-1", "the date button repeats the date: 'Sun, 20 Sep · 20 Sep 2026'", not dup, sev="low",
            repro="Add expense, pick any day other than today / yesterday, look at the Date field",
            observed=f"accessible name {dlabel!r}; the visible text reads the same way",
            expected="'Sun, 20 Sep 2026' (weekday and date once)",
            fix="app/lib/expenses.dart _ExpenseDialogState build(): the Text(...) and Semantics label combine dayLabel() and shortDate()",
            shot_name=shotname(4, "date-label"))
        app.cancel()

        # ---- edit an expense into another month: it leaves the current view
        app.tab("Expenses")
        app.button("Edit Dateearly ₹12")
        names = [n for n in page.evaluate(BUTTONS_JS) if n.startswith("Date, ")]
        step("dates: the edit dialog starts on the expense's own date", names and "3 Oct" in names[0], names)
        label = pick_date(app, -1, 20, from_offset=0)
        app.save()
        step("dates: editing into another month says which month", app.has(f"Updated Dateearly ₹12 to {mlabel(-1)}", 6000))
        app.snack_gone()
        app.tab("Expenses")
        step("dates: ... and the row left this month's view", app.gone("Dateearly", 2000) and app.has(f"No expenses in {mlabel(0)}"))
        app.month_prev()
        step("dates: ... and is in the previous month now",
             see(app, "Dateearly", "Expenses") and app.count(r"^Edit Dateearly") == 1)
        app.month_next()

        # ---- month navigation on every tab: +2 then -3
        api("POST", "/recurring", {"amount": 5, "category": "Nav", "note": "", "day_of_month": 2}, tok)
        empties = {
            "Dashboard": lambda n: f"No budgets are set for {mlabel(n)}",
            "Expenses": lambda n: f"No expenses in {mlabel(n)}",
            "Budgets": lambda n: f"No budgets for {mlabel(n)}",
            "Recurring": lambda n: f"Add to {mlabel(n)}",
        }
        for tab_name, expect in empties.items():
            app.tab(tab_name)
            step(f"months: {tab_name} opens on {mlabel(0)}", app.has(mlabel(0)))
            for target in (1, 2):
                app.month_next()
                step(f"months: {tab_name} +{target} shows {mlabel(target)}", app.has(mlabel(target)))
            step(f"months: {tab_name} at +2 shows its empty state / heading ({expect(2)!r})", see(app, expect(2), tab_name))
            for target in (1, 0, -1):
                app.month_prev()
                step(f"months: {tab_name} back to {mlabel(target)}", app.has(mlabel(target)))
            app.month_next()  # back to this month for the next tab
        app.tab("Dashboard")
        app.month_next()
        app.month_next()
        step("months: Dashboard +2 has no spending message", app.has(f"Nothing spent in {mlabel(2)} yet.") and app.has(f"No spending recorded in {mlabel(2)}."))
        app.month_prev()
        app.month_prev()
        app.tab("Goals")
        step("months: Goals has no month switcher", app.count(r"^Previous month") == 0 and app.count(r"^Next month") == 0)
        app.tab("Dashboard")
        step("months: the chosen month is kept while moving between tabs", app.has(mlabel(0)))
        for i in range(3):
            app.month_next()
        step("months: three months on crosses the year ('January 2027' style label)", app.has(mlabel(3)), mlabel(3))
        for i in range(3):
            app.month_prev()
        for i in range(10):
            app.month_prev()
        step("months: ten months back crosses into the previous year", app.has(mlabel(-10)), mlabel(-10))
        for i in range(10):
            app.month_next()
        step("months: ... and returns to this month", app.has(mlabel(0)))

        # ---- budgets for a future month
        app.tab("Budgets")
        app.month_next()
        step("budgets: next month starts empty", app.has(f"No budgets for {mlabel(1)}"))
        app.button("Add budget")
        step("budgets: the dialog names the month it is for", app.has(f"For {mlabel(1)}"))
        fill_text(app, "Category", "Future")
        app.fill("Monthly cap", "100")
        app.save()
        step("budgets: a budget set for next month is listed there", see(app, "Change Future budget", "Budgets") or app.count(r"^Change Future budget") == 1)
        app.month_prev()
        step("budgets: ... but not in this month", app.has(f"No budgets for {mlabel(0)}") and app.count(r"^Change Future") == 0)
        app.tab("Dashboard")
        app.month_next()
        step("budgets: next month's dashboard shows the budget, nothing spent", app.has("₹0 of ₹100") and app.has("₹100 left"))
        app.month_prev()
        step("budgets: this month's dashboard has no budget", app.has(f"No budgets are set for {mlabel(0)}"))
        # an expense dated in next month, entered while viewing this month, runs the check for next month's budget
        add_dated(app, 150, "Future", 1, 12)
        step("budgets: an expense dated next month is checked against next month's budget",
             app.has("Over budget in future by ₹50", 6000))
        app.snack_gone()

        # ---- recurring: apply to next month, back, and again
        st, tmpl = api("GET", "/recurring", token=tok)
        for t in tmpl:  # keep one template only: day 5, amount 50
            api("DELETE", f"/recurring/{t['id']}", token=tok)
        api("POST", "/recurring", {"amount": 50, "category": "Rent4", "note": "month test", "day_of_month": 5}, tok)
        app.tab("Recurring")
        app.month_next()
        app.button(f"Apply to {mlabel(1)}")
        step("recurring: applying to next month adds one expense there", app.has(f"Added 1 expense to {mlabel(1)}", 6000))
        app.snack_gone()
        app.month_prev()
        app.button(f"Apply to {mlabel(0)}")
        step("recurring: applying to this month then adds this month's own", app.has(f"Added 1 expense to {mlabel(0)}", 6000))
        app.snack_gone()
        app.month_next()
        app.button(f"Apply to {mlabel(1)}")
        step("recurring: applying next month again adds nothing (idempotent)", app.has(f"Nothing to add: {mlabel(1)} is already up to date."))
        app.snack_gone()
        counts = {n: len([e for e in list_exp(tok, mkey(n)) if e["category"] == "rent4"]) for n in (-1, 0, 1, 2)}
        step("recurring: exactly one generated expense in this and in next month, none elsewhere",
             counts == {-1: 0, 0: 1, 1: 1, 2: 0}, counts)
        step("recurring: ... on the template's day", [e["date"] for e in list_exp(tok, mkey(1)) if e["category"] == "rent4"] == [f"{mkey(1)}-05"])
        app.tab("Expenses")
        step("expenses: next month lists the generated expense once", see(app, "Rent4", "Expenses") and app.count(r"^Edit Rent4") == 1)
        app.month_prev()
        step("expenses: this month lists it once", see(app, "Rent4", "Expenses") and app.count(r"^Edit Rent4") == 1)
        app.month_prev()
        step("expenses: the previous month has none", app.gone("Rent4", 2000))
        ctx.close()


# ==================================================================== 7 recurring
@sec(7, "Recurring: templates, apply, undo, duplicates")
def sec_recurring(p):
    with chrome(p) as br:
        user = mk_user("r", opening=5000)
        tok = user[2]
        add_exp(tok, 1, "Manual", note="plain")
        ctx, page, app, net, ok = login_as(br, user)
        step("recurring: logged in", ok)
        app.tab("Expenses")
        app.has("Manual", 4000)
        c0 = app.text().count("Recurring")
        app.tab("Recurring")

        # ---- day 1 and day 28, paise
        app.button("Add template")
        app.fill("Amount", "99.99")
        fill_text(app, "Category", "Rent1")
        app.fill("Day of month", "1")
        app.save()
        step("recurring: a template for day 1 with paise (₹99.99)", see(app, "₹99.99", "Recurring") and app.has("Day 1"))
        app.button("Add template")
        app.fill("Amount", "12.5")
        fill_text(app, "Category", "Sub28")
        fill_text(app, "Note", "monthly sub")
        app.fill("Day of month", "28")
        app.save()
        step("recurring: a template for day 28 (₹12.50)", see(app, "₹12.50", "Recurring") and app.has("Day 28"))
        step("recurring: the stat strip adds them up (2 templates, ₹112.49 a month, ₹99.99 largest)",
             app.has("₹112.49") and app.has("Largest template"))
        app.shot(shotname(7, "templates"))
        for label, bad in (("0", "0"), ("29", "29"), ("blank", ""), ("1.5", "1.5")):
            app.button("Add template")
            app.fill("Amount", "5")
            fill_text(app, "Category", "BadDay")
            app.fill("Day of month", bad)
            app.save()
            step(f"recurring: day {label} is refused inline", app.has("Pick a day from 1 to 28"))
            app.cancel()

        # ---- apply twice
        app.button(f"Apply to {mlabel(0)}")
        step("recurring: the first apply adds both", app.has(f"Added 2 expenses to {mlabel(0)}", 6000))
        app.snack_gone()
        exps = {e["category"]: e for e in list_exp(tok, mkey(0))}
        step("recurring: ... on days 1 and 28 with the exact paise",
             exps["rent1"]["date"] == f"{mkey(0)}-01" and exps["rent1"]["amount"] == 99.99
             and exps["sub28"]["date"] == f"{mkey(0)}-28" and exps["sub28"]["amount"] == 12.5, exps.keys())
        app.button(f"Apply to {mlabel(0)}")
        step("recurring: the second apply adds nothing", app.has("Nothing to add"))
        app.snack_gone()
        app.tab("Expenses")
        wait_count(app, r"^Edit Rent1", 1, "Expenses")
        step("expenses: the generated rows are there once each",
             app.count(r"^Edit Rent1 ₹99.99$") == 1 and app.count(r"^Edit Sub28 ₹12.50$") == 1)
        c1 = app.text().count("Recurring")
        step("expenses: generated rows carry the 'Recurring' tag", c1 - c0 >= 2, (c0, c1))
        app.shot(shotname(7, "expenses-recurring-tags"))
        app.tab("Dashboard")
        step("dashboard: the balance includes the generated rows (5000 - 1 - 99.99 - 12.5 = 4886.51)", app.has("You have ₹4,886.51 left"))

        # ---- remove a generated expense, apply again: it is re-created
        app.tab("Expenses")
        app.button("Remove Rent1 ₹99.99")
        step("recurring: a generated expense can be removed", app.has("Deleted Rent1 ₹99.99"))
        app.snack_gone()
        app.tab("Recurring")
        app.button(f"Apply to {mlabel(0)}")
        step("recurring: apply after removing an applied expense re-creates just that one",
             app.has(f"Added 1 expense to {mlabel(0)}", 6000))
        app.snack_gone()
        step("recurring: ... on the server exactly one rent1 row again",
             len([e for e in list_exp(tok, mkey(0)) if e["category"] == "rent1"]) == 1)

        # ---- Remove + Undo of a generated expense, then apply
        app.tab("Expenses")
        app.button("Remove Sub28 ₹12.50")
        app.snack_action("Undo")
        app.wait(800)
        back = [e for e in list_exp(tok, mkey(0)) if e["category"] == "sub28"]
        linked = len(back) == 1 and back[0]["recurring_id"] is not None
        app.snack_gone()
        app.tab("Recurring")
        app.button(f"Apply to {mlabel(0)}")
        app.wait(1000)
        dup = len([e for e in list_exp(tok, mkey(0)) if e["category"] == "sub28"])
        app.shot(shotname(7, "undo-then-apply"))
        bug("REC-1", "removing a recurring expense and pressing Undo loses its link to the template; the next Apply adds a duplicate",
            linked and dup == 1, sev="medium",
            repro="Recurring: add a template, Apply; Expenses: Remove the generated row, Undo; Recurring: Apply again",
            observed=f"restored row has recurring_id={back[0]['recurring_id'] if back else '?'} (no 'Recurring' tag); after Apply there are {dup} rows for it and the app said 'Added 1 expense'",
            expected="Undo restores the same row including recurring_id, so Apply says 'Nothing to add'",
            fix="app/lib/expenses.dart _delete() Undo calls Api.addExpense without recurring_id; backend/main.py: let POST /expenses accept recurring_id (or add an undelete endpoint)")
        app.snack_gone()
        ctx.close()

        # ---- Remove + Undo of a template, then apply
        u2 = mk_user("r2", opening=5000)
        api("POST", "/recurring", {"amount": 30, "category": "Gym", "note": "tmpl", "day_of_month": 10}, u2[2])
        api("POST", f"/recurring/apply?month={mkey(0)}", token=u2[2])
        ctx, page, app, net, ok = login_as(br, u2)
        app.tab("Recurring")
        wait_count(app, r"^Remove Gym template$", 1, "Recurring")
        app.button("Remove Gym template")
        step("recurring: removing a template offers Undo", app.has("Deleted Gym ₹30 template") and app.has("Undo"))
        app.snack_action("Undo")
        app.wait(800)
        st, tl = api("GET", "/recurring", token=u2[2])
        step("recurring: Undo brings the template back with the same fields",
             len(tl) == 1 and tl[0]["category"] == "gym" and tl[0]["note"] == "tmpl" and tl[0]["day_of_month"] == 10 and tl[0]["amount"] == 30, tl)
        app.snack_gone()
        refresh_tab(app, "Recurring")
        app.button(f"Apply to {mlabel(0)}")
        app.wait(1000)
        gyms = len([e for e in list_exp(u2[2], mkey(0)) if e["category"] == "gym"])
        app.shot(shotname(7, "template-undo-then-apply"))
        bug("REC-2", "removing a template and pressing Undo, then Apply, duplicates the month's expense",
            gyms == 1, sev="medium",
            repro="Recurring: add a template, Apply; Remove the template, Undo; Apply again",
            observed=f"{gyms} 'gym' expenses this month (the restored template has a new id, so the unique (recurring_id, date) guard does not match)",
            expected="'Nothing to add'; one expense per template per month",
            fix="backend/main.py apply_recurring: also skip when an expense with the same category, amount and date already exists for that month, or make Undo re-use the template's id (app/lib/recurring.dart _delete())")
        ctx.close()


# ==================================================================== 8 goals
@sec(8, "Goals: reach, overshoot, 0.01, delete, same name")
def sec_goals(p):
    with chrome(p) as br:
        user = mk_user("g", opening=1000)
        tok = user[2]
        ctx, page, app, net, ok = login_as(br, user)
        step("goals: logged in", ok)
        app.tab("Goals")
        app.button("Add goal")
        fill_text(app, "Name", "Bike")
        app.fill("Target amount", "100")
        app.save()
        step("goals: a goal is added with its target", see(app, "₹0 of ₹100", "Goals") and app.has("₹100 to go"))
        # contribute more than the target
        app.button("Add money to Bike")
        app.fill("Amount", "150")
        app.save()
        step("goals: contributing above the target is accepted", app.has("Added ₹150 to Bike", 6000))
        app.snack_gone()
        step("goals: the goal is marked 'Goal reached'", app.has("Goal reached"))
        app.shot(shotname(8, "goal-overshoot"))
        txt = app.text()
        over_pct = re.findall(r"\b(1\d\d)\s?%", txt)
        note(f"goals: percentages above 99 seen on the Goals page after saving ₹150 of ₹100: {over_pct}")
        bug("GOAL-1", "a goal saved above its target shows 150% in the ring and 150 % overall progress (should cap at 100%)",
            not over_pct, sev="low",
            repro="Goals: add a goal with target 100, Add money 150",
            observed=f"the ring centre and the 'Overall progress' stat read {over_pct or ['150%']} while the bar is full and the tag says 'Goal reached'",
            expected="progress capped at 100% (the API already caps progress at 1.0)",
            fix="app/lib/goals.dart _GoalPanel (percent = (saved / target * 100).floor()) and _content (Overall progress): wrap in min(100, ...); the backend _goal_out() already does min(…, 1.0)",
            shot_name=shotname(8, "goal-overshoot"))
        app.tab("Dashboard")
        step("goals: the balance dropped by the contribution (1000 - 150 = 850)", app.has("You have ₹850 left"))
        step("goals: the dashboard shows the goal with its amounts", app.has("₹150 of ₹100"))
        app.shot(shotname(8, "dashboard-goal-over"))

        # 0.01
        app.tab("Goals")
        app.button("Add money to Bike")
        app.fill("Amount", "0.01")
        app.save()
        step("goals: a contribution of ₹0.01 is accepted and shown to the paisa", app.has("Added ₹0.01 to Bike", 6000))
        app.snack_gone()
        app.tab("Dashboard")
        step("goals: the balance moved by one paisa (849.99)", app.has("You have ₹849.99 left"))

        # same name
        app.tab("Goals")
        app.button("Add goal")
        fill_text(app, "Name", "Bike")
        app.fill("Target amount", "50")
        app.save()
        step("goals: a second goal with the same name is allowed", wait_count(app, r"^Add money to Bike$", 2, "Goals"))
        app.button("Add money to Bike", last=True)
        app.fill("Amount", "25")
        app.save()
        app.wait(800)
        goals = api("GET", "/goals", token=tok)[1]
        step("goals: money goes to the goal whose button was pressed (the second one)",
             [g["saved"] for g in goals] == [150.01, 25], [g["saved"] for g in goals])
        app.snack_gone()
        app.shot(shotname(8, "two-bikes"))

        # delete: Cancel then confirm
        refresh_tab(app, "Goals")
        app.button("Remove Bike")
        step("goals: Remove asks 'Delete Bike?' and says where the money goes",
             app.has("Delete Bike?") and app.has("saved towards it goes back into your balance"))
        app.shot(shotname(8, "delete-dialog"))
        app.cancel()
        step("goals: Cancel keeps both goals", app.gone("Delete Bike?", 2000) and len(api("GET", "/goals", token=tok)[1]) == 2)
        app.button("Remove Bike")
        app.button("Delete goal", last=True)
        app.wait(900)
        goals = api("GET", "/goals", token=tok)[1]
        step("goals: confirming deletes the first goal only", len(goals) == 1 and goals[0]["saved"] == 25, goals)
        app.tab("Dashboard")
        step("goals: deleting returned its ₹150.01 (1000 - 25 = 975)", app.has("You have ₹975 left"))
        # overdraft: a goal can take more than the balance
        app.tab("Goals")
        app.button("Add money to Bike")
        app.fill("Amount", "5000")
        app.save()
        app.snack_gone()
        app.tab("Dashboard")
        step("goals: contributing more than the balance leaves a negative balance (shown with a minus)",
             app.has("You have −₹4,025 left"))
        note("goals: nothing stops a goal contribution larger than the available balance (balance goes negative)")
        app.shot(shotname(8, "dashboard-negative"))
        ctx.close()


# ==================================================================== 2 money inputs
MONEY_ALL = ["0", "0.00", "-5", "5.555", "1e5", ".5", "5.", "", "abc", "999999999999", "1" + "0" * 29,
             "007", "0005.50", "1,000", "1.2.3", "100000000000000000"]
MONEY_SHORT = ["0", "-5", "5.555", "", "999999999999", "1" + "0" * 29, "0005.50", ".5"]
KEPT = set("0123456789.")  # the field only lets these characters in (ui.dart LabeledField)
MAX_PAISE_RUPEES = 92233720368547758  # what SQLite can hold as integer paise


def parsed(typed):
    try:
        return float(typed)
    except ValueError:
        return None


@sec(2, "Money inputs on every amount field")
def sec_money(p):
    with chrome(p) as br:
        user = mk_user("m", opening=1000)
        tok = user[2]
        ctx, page, app, net, ok = login_as(br, user)
        step("money: logged in", ok)
        # a goal with a huge target so contributions of any size are possible
        st, g = api("POST", "/goals", {"name": "Contrib", "target": 10 ** 12}, tok)
        month = mkey(0)

        def open_expense():
            app.tab("Expenses")
            app.button("Add expense")
            app.fill("Category", "Mx")

        def open_budget():
            app.tab("Budgets")
            app.button("Add budget")
            app.fill("Category", "Mb")

        def open_recurring():
            app.tab("Recurring")
            app.button("Add template")
            app.fill("Category", "Mr")
            app.fill("Day of month", "5")

        def open_goal():
            app.tab("Goals")
            app.button("Add goal")
            app.fill("Name", "Mg")

        def open_contrib():
            app.tab("Goals")
            app.button("Add money to Contrib")

        def open_settings():
            app.tab("Dashboard")
            app.button("Balance settings")

        specs = [
            # name, opener, label, method, path, json key, zero allowed, stored-value reader, values
            ("expense amount", open_expense, "Amount", "POST", "/expenses", "amount", False,
             lambda: (list_exp(tok) or [{}])[0].get("amount"), MONEY_ALL),
            ("budget cap", open_budget, "Monthly cap", "PUT", "/budgets", "cap", True,
             lambda: next((b["cap"] for b in api("GET", f"/budgets?month={month}", token=tok)[1] if b["category"] == "mb"), None),
             MONEY_SHORT),
            ("recurring amount", open_recurring, "Amount", "POST", "/recurring", "amount", False,
             lambda: (api("GET", "/recurring", token=tok)[1] or [{}])[-1].get("amount"), MONEY_SHORT),
            ("goal target", open_goal, "Target amount", "POST", "/goals", "target", False,
             lambda: next(iter([x["target"] for x in api("GET", "/goals", token=tok)[1] if x["name"] == "Mg"][-1:]), None),
             MONEY_SHORT),
            ("goal contribution", open_contrib, "Amount", "POST", f"/goals/{g['id']}/contribute", "amount", False,
             lambda: api("GET", "/goals", token=tok)[1][0]["saved"], MONEY_SHORT),
            ("opening balance", open_settings, "Opening balance", "PUT", "/account", "opening_balance", True,
             lambda: account(tok)["opening_balance"], MONEY_SHORT),
            ("safety line", open_settings, "Safety line", "PUT", "/account", "low_balance_threshold", True,
             lambda: account(tok)["low_balance_threshold"], MONEY_SHORT),
        ]
        table = []
        raw422 = []
        fivehundreds = []
        dropped = []
        for name, opener, label, method, path, jkey, zero_ok, stored, values in specs:
            for v in values:
                if not dialog_open(app):
                    opener()
                    if not dialog_open(app):
                        step(f"money: {name}: dialog opens", False)
                        break
                app.fill(label, v)
                typed = field(app, label)
                m = net.mark()
                before = stored()
                app.save()
                app.wait(1300)
                sent = net.body(m, method, path)
                sent_v = sent.get(jkey) if sent else None
                sts = net.statuses(m, path)
                still = dialog_open(app)
                txt = app.text()
                p_ = parsed(typed or "")
                exp_typed = "".join(c for c in v if c in KEPT)
                tag = f"{name}: {v[:12] + '..(%d)' % len(v) if len(v) > 14 else repr(v)}"
                # what the user sees
                msgs = [s for s in ("Enter an amount above 0", "Enter an amount, 0 or more", "Enter a number, for example 5000",
                                    "Enter a number, for example 1000 (or 0)", "Decimal input should have no more than 2 decimal places",
                                    "Server error 500", "Input should be", "less than") if s in txt]
                outcome = ("rejected inline" if (still and sent is None) else
                           "SERVER %s" % sts if (still and sts and sts[-1] >= 400) else
                           "saved" if (not still and sts and sts[-1] < 400) else "?")
                table.append((name, v if len(v) < 16 else v[:6] + "...(%d digits)" % len(v), typed if len(typed or "") < 16 else "...", sent_v if sent_v is None or sent_v < 1e15 else "%.3g" % sent_v, outcome, ";".join(msgs)[:60]))
                # 1. the field only keeps digits and the dot
                if typed != exp_typed:
                    step(f"money: {tag}: typed text is filtered to digits and dot", False, (typed, exp_typed))
                if v != exp_typed and v not in ("", "abc"):
                    dropped.append(f"{name}: typed {v!r} -> field shows {typed!r}")
                # 2. expectations by case
                if p_ is None or (p_ == 0 and not zero_ok):
                    step(f"money: {tag}: rejected inline, nothing sent", still and sent is None and
                         any(m_ in txt for m_ in ("Enter an amount", "Enter a number")), (outcome, msgs))
                elif p_ > 0 and abs(round(p_, 2) - p_) > 1e-9:
                    if sts and sts[-1] == 422:
                        raw422.append(f"{name} {v}")
                    elif sent is None:
                        step(f"money: {tag}: 3 decimals are stopped before the server", True)
                elif p_ >= MAX_PAISE_RUPEES:
                    if sts and sts[-1] >= 500:
                        fivehundreds.append(f"{name} {v[:8]}.. ({len(v)} digits) -> HTTP {sts[-1]}, screen: {msgs}")
                    elif sent is None:
                        step(f"money: {tag}: absurd amount is stopped before the server", True)
                else:
                    ok_sent = (sent is not None and abs(float(sent_v) - p_) < 1e-9) and sts and sts[-1] < 400
                    now = stored()
                    want = (float(before or 0) + p_) if name == "goal contribution" else p_
                    step(f"money: {tag}: saved exactly as {p_:g}",
                         ok_sent and not still and now is not None and abs(float(now) - want) < 1e-6 * max(1, abs(want)),
                         (outcome, sent_v, now, want))
                    if still:
                        app.cancel()
            if dialog_open(app):
                app.cancel()
        print("\n  field / typed / field shows / amount sent / outcome / messages")
        for r in table:
            print("  | %-18s | %-18s | %-18s | %-12s | %-22s | %s" % tuple(str(x) for x in r))
        print()
        bug("MONEY-1", "a 3-decimal amount is sent to the server and comes back as raw validation text",
            not raw422, sev="medium",
            repro="Add expense (also: budget cap, recurring, goal target, contribution, balance settings), amount 5.555, Save",
            observed="red text 'amount: Decimal input should have no more than 2 decimal places' (cap / target / opening_balance for the other fields) after a round trip; " + ", ".join(raw422[:3]),
            expected="inline 'Use at most 2 decimals, for example 5.55' before sending (or round to paise); never pydantic wording",
            fix="app/lib/*.dart amount validation (shared helper next to LabeledField money:true); api.dart _errorMessage() should drop the 'field: ' prefix and translate decimal_max_places",
            shot_name=shotname(2, "decimals"))
        bug("MONEY-2", "an amount of 18+ digits (e.g. 30 digits) makes the server return HTTP 500 'Server error 500'",
            not fivehundreds, sev="high",
            repro="Add expense, amount 1 followed by 29 zeros (or 100000000000000000), Save. Same on every amount field; PUT /account with 1e30 also 500s",
            observed="; ".join(fivehundreds[:3]) or "-",
            expected="a 422 'amount is too large' (Pydantic le=) and the dialog shows a readable message; never a 500",
            fix="backend/main.py: add le=<max> (e.g. 10**12) to every Decimal Field in ExpenseIn/BudgetIn/RecurringIn/GoalIn/ContributeIn/AccountIn (SQLite integer paise overflow in to_paise); app: cap the digits in LabeledField")
        bug("MONEY-3", "the number field silently drops characters it does not like: '-5' is saved as 5 and '1e5' as 15",
            not any("-5" in d or "1e5" in d for d in dropped), sev="low",
            repro="Add expense, type -5 (or paste 1e5), Save: the minus / the e disappear while typing and a different amount is saved",
            observed="; ".join(dropped[:4]),
            expected="reject with a message, or at least keep the user's characters visible until they are fixed",
            fix="app/lib/ui.dart LabeledField inputFormatters (allow [0-9.] only): paste handling / show an error when characters were removed")

        # how a huge amount looks once saved
        app.tab("Expenses")
        app.has("Mx", 4000)
        app.shot(shotname(2, "huge-expenses"))
        ov = overflow(app)
        step("money: a ₹999999999999 expense does not push the Expenses list sideways", not ov["bad"], ov)
        app.tab("Dashboard")
        app.has("Hi, ", 4000)
        app.shot(shotname(2, "huge-dashboard"))
        ov = overflow(app)
        step("money: a ₹999999999999 expense does not push the Dashboard sideways", not ov["bad"], ov)
        ctx.close()


# ==================================================================== 6 budgets
def add_budget_ui(app, category, cap):
    app.button("Add budget")
    fill_text(app, "Category", category)
    app.fill("Monthly cap", str(cap))
    app.save()
    app.wait(500)


@sec(6, "Budgets: dedupe, cap 0, tags, left to spend")
def sec_budgets(p):
    with chrome(p) as br:
        user = mk_user("b", opening=5000)
        tok = user[2]
        ctx, page, app, net, ok = login_as(br, user)
        step("budgets: logged in", ok)
        app.tab("Budgets")

        # ---- the same category in different case is one budget
        add_budget_ui(app, "food", 100)
        step("budgets: 'food' is added and shown capitalised", see(app, "Change Food budget", "Budgets") and app.has("₹100"))
        add_budget_ui(app, "FOOD", 200)
        add_budget_ui(app, "Food ", 300)
        wait_count(app, r"^Change .* budget$", 1, "Budgets")
        step("budgets: 'food', 'FOOD' and 'Food ' are one budget row", app.count(r"^Change .* budget$") == 1,
             page.evaluate(BUTTONS_JS))
        st, bl = api("GET", f"/budgets?month={mkey(0)}", token=tok)
        step("budgets: ... with the last cap (₹300) on the server", [(b["category"], b["cap"]) for b in bl] == [("food", 300)], bl)
        step("budgets: ... and ₹300 on screen", app.has("₹300") and app.gone("₹100", 500) and app.gone("₹200", 500))

        # ---- a new category
        add_budget_ui(app, "Pet Care", 50)
        step("budgets: a second category gets its own row", wait_count(app, r"^Change Pet Care budget$", 1, "Budgets")
             and app.count(r"^Change .* budget$") == 2)
        # editing is by Change; the category is read only there
        app.button("Change Pet Care budget")
        step("budgets: Change shows the category read-only with the current cap",
             app.has("Change budget") and field(app, "Monthly cap") == "50")
        try:
            dis = page.get_by_label("Category", exact=False).first.is_disabled()
        except Exception:
            dis = None
        note(f"budgets: the category field in 'Change budget' is {'disabled' if dis else 'editable?' if dis is False else 'not exposed'}")
        app.cancel()

        # ---- tags and bars flip as Food is spent: 0/300 -> 100 -> 260 (87%) -> 310
        def tags():
            t = app.text()
            return dict(within=t.count("Within budget"), close=t.count("Close to limit"), over=t.count("Over budget"))

        refresh_tab(app, "Budgets")
        t0 = tags()
        step("budgets: nothing spent -> both rows say 'Within budget'", t0["within"] == 2 and t0["close"] == 0, t0)
        add_exp(tok, 100, "Food")
        refresh_tab(app, "Budgets")
        step("budgets: ₹100 of ₹300 is still 'Within budget'", app.has("₹100 spent") and tags()["close"] == 0, tags())
        app.shot(shotname(6, "bars-within"))
        add_exp(tok, 160, "Food")
        refresh_tab(app, "Budgets")
        t = tags()
        step("budgets: ₹260 of ₹300 (87%) flips to 'Close to limit'", t["close"] == 1 and t["within"] == 1, t)
        app.shot(shotname(6, "bars-close"))
        base = tags()["over"]
        add_exp(tok, 50, "Food")
        refresh_tab(app, "Budgets")
        t = tags()
        step("budgets: ₹310 of ₹300 flips to 'Over budget' with '₹10 over budget'",
             t["over"] == base + 1 and t["close"] == 0 and app.has("₹10 over budget"), (base, t))
        app.shot(shotname(6, "bars-over"))
        step("budgets: 'Left to spend' = caps - spend of the budgeted categories (₹350 - ₹310 = ₹40)", app.has("Left to spend") and app.has("₹40"))
        add_exp(tok, 60, "Pet Care")
        refresh_tab(app, "Budgets")
        step("budgets: overspending the total shows a minus sign (₹350 - ₹370 = −₹20)", app.has("−₹20"), app.text()[:200])
        app.shot(shotname(6, "left-to-spend-negative"))
        # raising the cap flips it back
        app.button("Change Food budget")
        app.fill("Monthly cap", "1000")
        app.save()
        step("budgets: raising the cap flips Food back to 'Within budget'", app.has("₹690 left") or app.has("₹1,000"), app.text()[:200])
        # ---- cap 0 with nothing spent
        text0 = app.text()
        base_over = text0.count("Over budget")
        add_budget_ui(app, "Zero", 0)
        step("budgets: a cap of 0 is accepted", wait_count(app, r"^Change Zero budget$", 1, "Budgets"))
        txt = app.text()
        note(f"budgets: 'Over budget' occurrences before/after adding a ₹0 cap with nothing spent: {base_over} -> {txt.count('Over budget')}")
        app.shot(shotname(6, "cap-zero"))
        bug("BUD-1", "a ₹0 budget with nothing spent is tagged 'Over budget' (and drawn as a full red bar)",
            txt.count("Over budget") == base_over, sev="medium",
            repro="Budgets > Add budget > any category, cap 0, Save (no expenses in it)",
            observed="the row shows the red 'Over budget' tag and a full bar while it says '₹0 left' and the Dashboard counts 0 categories over budget",
            expected="'Within budget' / 'At limit' until something is spent; consistent with the Dashboard count",
            fix="app/lib/budgets.dart _BudgetRow: ratio = cap == 0 ? 2.0 : ... (same in dashboard.dart _budgetRow, and the sort ratio): use spent > cap for over, and only treat cap 0 as full when spent > 0",
            shot_name=shotname(6, "cap-zero"))
        # an expense in a ₹0 budget alerts
        add_exp(tok, 10, "Zero")
        app.tab("Dashboard")
        app.has("Zero", 4000)
        step("budgets: spending in a ₹0 category shows ₹10 over budget on the Dashboard", app.has("₹10 over budget"))
        app.tab("Budgets")
        api("DELETE", "/expenses/" + str(list_exp(tok)[0]["id"]), token=tok)

        app.button("Add budget")
        fill_text(app, "Category", "Blank")
        app.save()
        step("budgets: ... 'Enter an amount, 0 or more'", app.has("Enter an amount, 0 or more"))
        app.cancel()
        ctx.close()


# ==================================================================== 9 dashboard
@sec(9, "Dashboard: safety line, negative balance, links, order")
def sec_dashboard(p):
    with chrome(p) as br:
        user = mk_user("h", opening=1000)
        tok = user[2]
        ctx, page, app, net, ok = login_as(br, user)
        step("dashboard: logged in", ok)

        def settings(opening=None, line=None, save=True):
            app.button("Balance settings")
            if opening is not None:
                app.fill("Opening balance", str(opening))
            if line is not None:
                app.fill("Safety line", str(line))
            if save:
                app.save()
            app.wait(600)

        step("dashboard: no safety line -> a prompt to set one and no banner",
             app.has("You have ₹1,000 left. Set a safety line") and app.gone("Low balance:", 500))
        settings(line=500)
        step("dashboard: balance above the line -> '₹500 above your safety line', no banner",
             app.has("You have ₹1,000 left, ₹500 above your safety line.") and app.gone("Low balance:", 500))
        settings(line=2000)
        step("dashboard: balance below the line -> banner and sentence",
             app.has("Low balance: ₹1,000 left, ₹1,000 below your ₹2,000 safety line.")
             and app.has("You have ₹1,000 left, ₹1,000 below your safety line."))
        app.shot(shotname(9, "banner-on"))
        settings(line=1000)
        step("dashboard: balance exactly on the line is not low", app.gone("Low balance:", 1500) and app.has("₹0 above your safety line"))
        settings(line=2000)
        settings(line=0)
        step("dashboard: safety line 0 turns the warning off", app.gone("Low balance:", 1500) and app.has("Set a safety line"))
        app.shot(shotname(9, "banner-off"))

        # Cancel keeps everything; reopening is pre-filled (an unchanged Save must not alter the server)
        settings(line=300)
        app.button("Balance settings")
        app.fill("Opening balance", "99999")
        app.cancel()
        step("dashboard: Cancel closes the dialog without saving", not dialog_open(app) and account(tok)["opening_balance"] == 1000)
        app.button("Balance settings")
        step("dashboard: ... reopening shows the saved opening balance", field(app, "Opening balance") == "1000", field(app, "Opening balance"))
        app.save()
        acc = account(tok)
        step("dashboard: ... and saving without changes keeps opening balance and safety line (dialog was pre-filled)",
             acc["opening_balance"] == 1000 and acc["low_balance_threshold"] == 300, acc)
        settings(line=0)

        # negative balance
        app.button("Add expense")
        app.fill("Amount", "1500")
        fill_text(app, "Category", "Splurge")
        app.save()
        step("dashboard: spending past the opening balance is accepted", app.has("Added Splurge ₹1,500", 6000))
        app.snack_gone()
        step("dashboard: a negative balance reads '−₹500' in the sentence and the Balance stat",
             app.has("You have −₹500 left") and app.text().count("−₹500") >= 2, app.text()[:300])
        app.shot(shotname(9, "negative-balance"))
        settings(line=1000)
        step("dashboard: ... and the banner says how far below the line (₹1,500)",
             app.has("Low balance: −₹500 left, ₹1,500 below your ₹1,000 safety line."))
        app.shot(shotname(9, "negative-banner"))
        settings(line=0)

        # chart and links
        step("dashboard: the daily chart is present with its summary", app.has("Highest day:") and app.has("Daily spend"))
        app.press(r"^View all$")
        step("dashboard: Recent expenses 'View all' opens Expenses", app.has("Everything you spent in"))
        app.tab("Dashboard")
        app.press(r"^Manage$")
        step("dashboard: Budgets 'Manage' opens Budgets", app.has("Monthly caps") or app.has(f"No budgets for {mlabel(0)}"))
        app.tab("Dashboard")
        app.press(r"^Set a budget$")
        step("dashboard: 'Set a budget' opens Budgets", app.has(f"No budgets for {mlabel(0)}"))
        app.tab("Dashboard")
        app.press(r"^Add a goal$")
        step("dashboard: Goals 'Add a goal' opens Goals", app.has("No savings goals yet"))
        api("POST", "/goals", {"name": "Hat", "target": 10}, tok)
        app.tab("Dashboard")
        refresh_tab(app, "Dashboard")
        app.press(r"^View all$", last=True)
        step("dashboard: Savings goals 'View all' opens Goals", see(app, "Add money to Hat", "Goals"))
        ctx.close()

        # recent expenses order: newest day first, newest id first within a day, only five
        u2 = mk_user("h2", opening=1000)
        for d, n in [(1, "ord1"), (2, "ord2"), (3, "ord3"), (4, "ord4"), (5, "ord5"), (6, "ord6"), (7, "ord7a"), (7, "ord7b")]:
            add_exp(u2[2], 10 + d, "Order", day=d, note=n)
        ctx, page, app, net, ok = login_as(br, u2)
        txt = app.text()
        pos = {n: txt.find(n) for n in ("ord7b", "ord7a", "ord6", "ord5", "ord4", "ord3", "ord2", "ord1")}
        step("dashboard: Recent expenses lists only the five newest", all(pos[n] >= 0 for n in ("ord7b", "ord7a", "ord6", "ord5", "ord4"))
             and all(pos[n] < 0 for n in ("ord3", "ord2", "ord1")), pos)
        step("dashboard: ... newest day first, then the later entry of the same day",
             0 <= pos["ord7b"] < pos["ord7a"] < pos["ord6"] < pos["ord5"] < pos["ord4"], pos)
        app.shot(shotname(9, "recent-order"))
        ctx.close()


# ==================================================================== 10 navigation, sizes, keyboard
SECTION_MARKERS = {
    "Dashboard": ("Hi, ",),
    "Expenses": ("Everything you spent in", "will be listed here"),
    "Budgets": ("A monthly cap per category",),
    "Recurring": ("Bills and subscriptions that repeat",),
    "Goals": ("Money you are setting aside",),
}


def which_section(app):
    t = app.text()
    for name, markers in SECTION_MARKERS.items():
        if any(m in t for m in markers):
            return name
    return None


try:  # optional: only used to judge how visible the keyboard focus is
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover
    Image = None


def clip_img(page, box, pad=8):
    import io
    c = {"x": max(0, box["x"] - pad), "y": max(0, box["y"] - pad), "width": box["width"] + 2 * pad, "height": box["height"] + 2 * pad}
    return Image.open(io.BytesIO(page.screenshot(clip=c))).convert("RGB")


def max_diff(a, b):
    """Largest per-channel colour difference between two equally sized images (0-255)."""
    return max(max(px) for px in ImageChops.difference(a, b).getdata())


def nav_rects(app):
    return [r for r in btn_rects(app, TABS) if r]


@sec(10, "Navigation, reload, Back, URLs, resize, keyboard")
def sec_nav(p):
    with chrome(p) as br:
        user = mk_user("n", opening=5000)
        tok = user[2]
        for i in range(1, 13):
            add_exp(tok, 10 + i, ["Food", "Rent", "Fun"][i % 3], day=min(i, 20), note=f"nav row {i}")
        api("PUT", "/budgets", {"category": "Food", "month": mkey(0), "cap": 50}, tok)
        api("POST", "/goals", {"name": "Nav goal", "target": 500}, tok)
        api("POST", "/recurring", {"amount": 9, "category": "Navsub", "note": "", "day_of_month": 3}, tok)
        ctx, page, app, net, ok = login_as(br, user)
        step("nav: logged in", ok)

        # ---- reload on every section
        landed = {}
        for t in TABS:
            app.tab(t)
            if t != "Dashboard":
                app.month_prev() if t in ("Expenses", "Budgets", "Recurring") else None
            before = which_section(app)
            app.reload()
            logged = app.has("Dashboard", 8000) and app.has("Log out", 3000)
            landed[t] = (logged, which_section(app), app.has(mlabel(-1), 300))
            step(f"nav: a reload on {t} keeps the user logged in", logged and before == t, (before, landed[t]))
        note("nav: after a reload the app opens on: " + "; ".join(f"{t} -> {landed[t][1]}" for t in TABS)
             + " (the viewed month " + ("is kept" if any(v[2] for v in landed.values()) else "resets to the current month") + ")")
        bug("NAV-1", "a reload (or a bookmark) always returns to the Dashboard of the current month; section and month are not in the URL",
            all(landed[t][1] == t for t in TABS), sev="low",
            repro="Open Goals (or any section, or another month), press F5",
            observed="the Dashboard opens, in this month: " + "; ".join(f"{t}->{landed[t][1]}" for t in TABS),
            expected="the same section stays open (and ideally deep links like #/expenses work)",
            fix="app/lib/main.dart: keep the section (and month) in the URL or in shared_preferences next to the session token")

        # ---- browser Back from each section
        back = {}
        for t in TABS[1:]:
            app.tab(t)
            page.go_back()
            app.wait(1500)
            back[t] = (page.url, which_section(app) or ("login/landing" if app.has("Know where") else "?"))
            step(f"nav: browser Back from {t} stays in the app on the Dashboard",
                 back[t][1] == "Dashboard", back[t])
        # Back on the dashboard itself
        app.wait(500)
        hist = page.evaluate("history.length")
        page.go_back()
        app.wait(1500)
        note(f"nav: Back on the Dashboard -> url {page.url!r}, history length {hist}")
        if not page.url.startswith(BASE_URL.rstrip("/")):
            page.go_forward()
            app.wait(1500)
        # Back while a dialog is open closes the dialog only
        if app.has("Hi, ", 4000) or which_section(app) is not None:
            app.tab("Goals")
            app.button("Add goal")
            page.go_back()
            app.wait(1200)
            note(f"nav: Back with a dialog open -> dialog {'closed' if not dialog_open(app) else 'still open'}, "
                 f"section {which_section(app)}")
            if dialog_open(app):
                app.cancel()

        # ---- direct URLs
        for path in ("expenses", "goals", "dashboard", "budgets?month=2026-10", "recurring", "account", "nonexistent.js", "index.html", "docs", "openapi.json"):
            st, ct, body, hdr = http_get("/" + path)
            note(f"nav: GET /{path} -> HTTP {st} {ct.split(';')[0]} {body[:60].strip()!r}")
        pg2 = ctx.new_page()
        resp = pg2.goto(BASE_URL.rstrip("/") + "/expenses")
        shown = pg2.evaluate("document.body.innerText").strip()[:80]
        pg2.screenshot(path=os.path.join(SHOTS, "s10-url-expenses.png"))
        bug("NAV-2", "typing/bookmarking /expenses, /goals, /dashboard... shows raw JSON ({\"detail\": \"Please log in again\"}) and unknown paths a bare JSON 404",
            "{" not in shown, sev="low",
            repro="Open http://<host>/expenses (or /goals, /budgets, /nonexistent) in the browser",
            observed=f"page body is {shown!r} (HTTP {resp.status}); the REST routes share their names with the natural page URLs",
            expected="the app (index.html) for unknown / page-like paths, or a friendly 404 page; API under /api",
            fix="backend/main.py: mount the API under /api (and update app/lib/api.dart) or add an SPA fallback for GET requests that accept text/html",
            shot_name="s10-url-expenses.png", take_shot=False)
        pg2.close()
        app.pg.bring_to_front()
        ctx.close()

        # ---- resizing: landing page and logged-in app
        sizes = [(320, 700), (360, 740), (390, 844), (759, 900), (760, 900), (768, 900), (1024, 800), (1280, 800), (1920, 1080)]
        ctx, page, app, net = open_page(br, w=sizes[0][0], h=sizes[0][1])
        for w, h in sizes:
            page.set_viewport_size({"width": w, "height": h})
            common.WIDTH, common.HEIGHT = w, h
            app.wait(1200)
            ok_land = app.has("Know where your money goes.", 4000)
            ov = overflow(app)
            app.shot(f"s10-landing-{w}.png")
            step(f"resize {w}px: landing page renders without sideways overflow",
                 ok_land and not ov["bad"] and ov["scrollW"] <= ov["W"], ov)
        ctx.close()
        ctx, page, app, net, ok = login_as(br, user, w=sizes[0][0], h=sizes[0][1])
        for w, h in sizes:
            page.set_viewport_size({"width": w, "height": h})
            common.WIDTH, common.HEIGHT = w, h
            app.wait(1300)
            for t in ("Dashboard", "Expenses", "Goals"):
                app.tab(t)
                app.wait(500)
                ov = overflow(app)
                if t in ("Dashboard", "Expenses"):
                    app.shot(f"s10-{t.lower()}-{w}.png")
                step(f"resize {w}px: {t} has no sideways overflow", not ov["bad"] and ov["scrollW"] <= ov["W"], ov)
            rects = nav_rects(app)
            inside = len(rects) == 5 and all(r["x"] >= -1 and r["x"] + r["w"] <= w + 1 and r["y"] >= -1 and r["y"] + r["h"] <= h + 1 for r in rects)
            step(f"resize {w}px: all five navigation buttons are inside the window", inside, rects)
            wide = w >= 760
            if rects:
                at_bottom = rects[0]["y"] > h / 2
                step(f"resize {w}px: navigation is at the {'top' if wide else 'bottom'} (breakpoint 760)", at_bottom != wide, rects[0])
            # the last row is not hidden behind the bottom pill
            app.tab("Expenses")
            scroll_down(app, 14, h)
            app.wait(500)
            row_btns = page.evaluate(
                """() => Array.from(document.querySelectorAll('flt-semantics[role=button]')).map(e => {
                  const n=(e.getAttribute('aria-label')||e.textContent||'').trim(); const r=e.getBoundingClientRect();
                  return {n, y:r.y, b:r.bottom, h:r.height}; }).filter(o => o.n.startsWith('Remove ') && o.h>0)""")
            nav_top = min((r["y"] for r in nav_rects(app)), default=h)
            if row_btns and not wide:
                last_b = max(r["b"] for r in row_btns)
                step(f"resize {w}px: after scrolling to the end the last row's buttons clear the bottom pill",
                     last_b <= nav_top + 2, (last_b, nav_top))
                app.shot(f"s10-expenses-end-{w}.png")
            elif row_btns:
                step(f"resize {w}px: after scrolling to the end the last row is on screen", max(r["b"] for r in row_btns) <= h, row_btns[-1])
        step("resize: after all the resizing the user is still logged in", app.has("Log out"))
        ctx.close()

        # ---- keyboard: Tab through the login form
        ctx, page, app, net = open_page(br)
        app.button("Log in")
        app.wait(600)
        stops = tab_stops(page, 14, shots=((3, shotname(10, "tab-login-3")),))
        note("nav: Tab order on the login form (after the username field is focused): " + " > ".join(stops))

        def first(s):
            return next((i for i, x in enumerate(stops) if s in x), None)
        isub = first("Log in")
        step("keyboard: Tab from the Username field goes to the Password field", stops[0].startswith("input:"), stops)
        step("keyboard: Tab reaches the Log in button after the fields", isub is not None and isub > 0, stops)
        ctx.close()
        if Image is not None:
            # put the focus on the submit button and measure how much the picture changed
            ctx, page, app, net = open_page(br)
            app.button("Log in")
            app.wait(600)
            submit_box = page.get_by_role("button", name=re.compile(r"^Log in$")).last.bounding_box()
            base = clip_img(page, submit_box)
            diff = None
            for _ in range(8):
                page.keyboard.press("Tab")
                page.wait_for_timeout(350)
                nm = page.evaluate("(document.activeElement.textContent || '').trim().slice(0, 6)")
                if nm == "Log in":
                    diff = max_diff(base, clip_img(page, submit_box))
                    break
            note(f"keyboard: focusing the Log in button changes its pixels by at most {diff}/255")
            step("keyboard: the Log in button can be focused with Tab", diff is not None)
            bug("A11Y-2", "keyboard focus is almost invisible: the focused button changes by a barely visible fill, there is no focus ring",
                diff is not None and diff >= 60, sev="medium",
                repro="Log in screen: press Tab until the Log in button is focused (also the nav pills and dialog buttons) and look for the focus indicator",
                observed=f"largest colour change on the focused Log in button is {diff}/255 (a ring or outline would be above 100); text fields show a similarly faint border change",
                expected="a clearly visible focus ring (WCAG 2.4.7 / 2.4.11) on every focusable control",
                fix="app/lib/theme.dart: set focusColor / a visible side on Outlined/FilledButton, InputDecoration focusedBorder and InkWell focusColor (e.g. a 2 px k.link outline)",
                shot_name=shotname(10, "tab-login-3"))
            ctx.close()
        else:
            note("keyboard: Pillow is not installed, the focus-visibility measurement was skipped")
        # ---- keyboard on the dashboard
        ctx, page, app, net, ok = login_as(br, user)
        page.mouse.click(5, 5)
        stops = tab_stops(page, 14, shots=((2, shotname(10, "tab-dashboard-2")),))
        note("nav: Tab order on the Dashboard: " + " > ".join(stops))
        order = [next((i for i, x in enumerate(stops) if x.endswith(":" + t)), None) for t in ("Add expense", "Manage", "View all")]
        step("keyboard: on the Dashboard Tab reaches Add expense, then Manage, then View all (top to bottom)",
             all(o is not None for o in order) and order == sorted(order), (order, stops))
        ctx.close()

        # ---- Escape closes dialogs, Enter submits them
        u2 = mk_user("n2", opening=5000)
        api("POST", "/goals", {"name": "Esc goal", "target": 100}, u2[2])
        ctx, page, app, net, ok = login_as(br, u2)
        dialogs = [
            ("Add expense", "Expenses", lambda: app.button("Add expense")),
            ("Add budget", "Budgets", lambda: app.button("Add budget")),
            ("Add template", "Recurring", lambda: app.button("Add template")),
            ("Add goal", "Goals", lambda: app.button("Add goal")),
            ("Add money", "Goals", lambda: app.button("Add money to Esc goal")),
            ("Delete goal", "Goals", lambda: app.button("Remove Esc goal")),
        ]
        for name, tab_name, opener in dialogs:
            app.tab(tab_name)
            m = net.mark()
            opener()
            was_open = app.count(r"^(Save|Cancel)$") > 0
            if name == "Add expense":
                app.fill("Amount", "5")
                fill_text(app, "Category", "EscTest")
            page.keyboard.press("Escape")
            app.wait(900)
            closed = app.count(r"^(Save|Cancel)$") == 0
            no_writes = not [q for q in net.sent(m) if q[0] != "GET"]
            step(f"keyboard: Escape closes the '{name}' dialog without saving", was_open and closed and no_writes,
                 (was_open, closed, net.sent(m)))
            if not closed:
                app.cancel()
        # Enter submits on the last field
        app.tab("Budgets")
        m = net.mark()
        app.button("Add budget")
        fill_text(app, "Category", "Enterbud")
        app.fill("Monthly cap", "77")
        page.keyboard.press("Enter")
        app.wait(1200)
        step("keyboard: Enter in the last field submits the budget dialog",
             not dialog_open(app) and len(net.sent(m, "PUT", "/budgets")) == 1)
        app.tab("Goals")
        m = net.mark()
        app.button("Add goal")
        fill_text(app, "Name", "Entergoal")
        page.keyboard.press("Enter")
        app.wait(900)
        step("keyboard: Enter in the first of two fields does not submit",
             dialog_open(app) and not net.sent(m, "POST", "/goals"))
        app.fill("Target amount", "40")
        page.keyboard.press("Enter")
        app.wait(1200)
        step("keyboard: Enter in the last field submits the goal dialog",
             not dialog_open(app) and len(net.sent(m, "POST", "/goals")) == 1)
        m = net.mark()
        app.button("Add money to Entergoal")
        app.fill("Amount", "3")
        page.keyboard.press("Enter")
        app.wait(1200)
        step("keyboard: Enter submits the contribution dialog", not dialog_open(app) and len(net.sent(m, "POST", "/contribute")) == 1)
        app.tab("Recurring")
        m = net.mark()
        app.button("Add template")
        app.fill("Amount", "4")
        fill_text(app, "Category", "Enterrec")
        app.fill("Day of month", "6")
        page.keyboard.press("Enter")
        app.wait(1200)
        step("keyboard: Enter submits the template dialog", not dialog_open(app) and len(net.sent(m, "POST", "/recurring")) == 1)
        app.tab("Dashboard")
        m = net.mark()
        app.button("Balance settings")
        app.fill("Safety line", "10")
        page.keyboard.press("Enter")
        app.wait(1200)
        step("keyboard: Enter submits the balance settings dialog", not dialog_open(app) and len(net.sent(m, "PUT", "/account")) == 1)
        ctx.close()


# ==================================================================== 5 expenses
def inr(x):
    """Format like the app's money(): ₹1,23,456.50 (Indian grouping, paise only if any)."""
    paise = round(abs(float(x)) * 100)
    r, pa = divmod(paise, 100)
    s = str(r)
    if len(s) > 3:
        head, tail, groups = s[:-3], s[-3:], []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        if head:
            groups.insert(0, head)
        s = ",".join(groups) + "," + tail
    return ("−" if x < 0 and paise else "") + "₹" + s + (f".{pa:02d}" if pa else "")


def wait_count(app, pattern, n, tab=None, timeout=6):
    """Poll until exactly n buttons match; re-open the tab once if the DOM lags."""
    for attempt in range(2):
        end = time.time() + timeout
        while time.time() < end:
            if app.count(pattern) == n:
                return True
            app.pg.wait_for_timeout(250)
        if attempt == 0 and tab:
            refresh_tab(app, tab)
    return False


def names_of(rows):
    return sorted(r["category"] for r in rows)


@sec(5, "Expenses: filters, edit, remove, undo, double remove")
def sec_expenses(p):
    with chrome(p) as br:
        user = mk_user("e", opening=5000)
        tok = user[2]
        for a, c, d, n in [(100, "Food", 2, "f1"), (200, "Food", 3, "f2"), (300, "Food", 4, "f3"),
                           (1000, "Rent", 1, "r1"), (50, "Fun", 5, "n1"), (60, "Fun", 6, "n2")]:
            add_exp(tok, a, c, day=d, note=n)
        api("PUT", "/budgets", {"category": "Food", "month": mkey(0), "cap": 250}, tok)
        ctx, page, app, net, ok = login_as(br, user)
        step("expenses: logged in", ok)
        app.tab("Expenses")
        step("expenses: six rows, tabs All (6) / Rent (1) / Food (3) / Fun (2)",
             wait_count(app, r"^All \(6\)$", 1, "Expenses") and app.count(r"^Food \(3\)$") == 1
             and app.count(r"^Fun \(2\)$") == 1 and app.count(r"^Rent \(1\)$") == 1, page.evaluate(BUTTONS_JS))
        step("expenses: the stat strip totals the month (₹1,710) and names the biggest category (Rent)",
             app.has("₹1,710") and app.has("Rent") and app.has("Biggest category"))
        app.shot(shotname(5, "expenses-all"))

        # ---- filter
        app.press(r"^Food \(3\)$")
        step("expenses: the Food filter shows only the three Food rows",
             wait_count(app, r"^Edit Food ", 3) and app.count(r"^Edit Rent ") == 0 and app.count(r"^Edit Fun ") == 0)
        step("expenses: ... with a footer '3 of 6 expenses, ₹600 in Food'", app.has("3 of 6 expenses, ₹600 in Food"))
        app.shot(shotname(5, "expenses-food-filter"))

        # ---- filter, then Remove
        app.button("Remove Food ₹300")
        step("expenses: removing inside the filter offers Undo", app.has("Deleted Food ₹300") and app.has("Undo"))
        step("expenses: ... the tabs become Food (2) / All (5) and the filter stays on Food",
             wait_count(app, r"^Food \(2\)$", 1, "Expenses") and app.count(r"^All \(5\)$") == 1
             and app.count(r"^Edit Food ") == 2 and app.has("2 of 5 expenses, ₹300 in Food"))
        app.snack_gone()

        # ---- filter, then add a new category
        app.button("Add expense")
        app.fill("Amount", "7")
        fill_text(app, "Category", "Zed")
        app.save()
        step("expenses: adding a new category while filtered makes its tab appear",
             wait_count(app, r"^Zed \(1\)$", 1, "Expenses") and app.count(r"^All \(6\)$") == 1)
        app.snack_gone()
        app.press(r"^All \(6\)$")
        step("expenses: All shows everything again", wait_count(app, r"^Edit ", 6))

        # ---- edit amount / category / note
        app.button("Edit Fun ₹60")
        dl = [n for n in page.evaluate(BUTTONS_JS) if n.startswith("Date, ")]
        step("expenses: the edit dialog shows the row's amount, date and category",
             field(app, "Amount") == "60" and selected(app, "Fun") is True and dl and "6 Oct" in dl[0]
             and field(app, "Category") == "Fun" and field(app, "Note") == "n2", (dl, selected(app, "Fun")))
        app.save()  # unchanged: the note must survive, i.e. the dialog was pre-filled
        app.wait(900)
        kept = [e for e in list_exp(tok) if e["category"] == "fun" and e["amount"] == 60]
        step("expenses: saving an edit without changes keeps category, amount and note",
             len(kept) == 1 and kept[0]["note"] == "n2", kept)
        app.snack_gone()
        app.button("Edit Fun ₹60")
        app.fill("Amount", "65")
        fill_text(app, "Category", "Fun2")
        fill_text(app, "Note", "edited note")
        app.save()
        step("expenses: the edited row shows the new category and amount",
             wait_count(app, r"^Edit Fun2 ₹65$", 1, "Expenses") and app.count(r"^Edit Fun ₹60$") == 0)
        step("expenses: ... and the tabs follow (Fun (1), Fun2 (1))",
             app.count(r"^Fun \(1\)$") == 1 and app.count(r"^Fun2 \(1\)$") == 1)
        step("expenses: ... and the server has the new note",
             any(e["category"] == "fun2" and e["note"] == "edited note" and e["amount"] == 65 for e in list_exp(tok)))
        app.snack_gone()

        # ---- edit into a category that has a budget -> alert
        app.button("Edit Rent ₹1,000")
        fill_text(app, "Category", "Food")
        app.save()
        food = sum(e["amount"] for e in list_exp(tok, mkey(0)) if e["category"] == "food")
        step(f"expenses: moving a row into over-budget Food alerts 'Over budget in food by {inr(food - 250)}'",
             app.has(f"Over budget in food by {inr(food - 250)}", 6000))
        app.snack_gone()

        # ---- Undo restores category, note and date
        app.button("Remove Fun ₹50")
        step("expenses: removing a row offers Undo", app.has("Deleted Fun ₹50") and app.has("Undo"))
        before = [e for e in list_exp(tok) if e["note"] == "n1"]
        step("expenses: ... the row is gone from the server", not before, before)
        app.snack_action("Undo")
        app.wait(800)
        back = [e for e in list_exp(tok) if e["note"] == "n1"]
        step("expenses: Undo brings back category, amount, note and date",
             len(back) == 1 and back[0]["category"] == "fun" and back[0]["amount"] == 50
             and back[0]["date"] == f"{mkey(0)}-05", back)
        refresh_tab(app, "Expenses")
        step("expenses: ... and the row is on screen again", app.count(r"^Edit Fun ₹50$") == 1)
        app.snack_gone()
        ctx.close()

        # ---- removing the last remaining row -> empty state, Undo brings it back
        u1 = mk_user("e1", opening=100)
        add_exp(u1[2], 5, "Solo", note="only one")
        ctx, page, app, net, ok = login_as(br, u1)
        app.tab("Expenses")
        wait_count(app, r"^Edit Solo", 1, "Expenses")
        app.button("Remove Solo ₹5")
        step("expenses: removing the last row shows the empty state",
             app.has(f"No expenses in {mlabel(0)}") and app.has("Deleted Solo ₹5"))
        app.shot(shotname(5, "expenses-empty-after-remove"))
        step("expenses: ... the stat strip and filter tabs are gone with it", app.count(r"^All \(") == 0)
        app.snack_action("Undo")
        refresh_tab(app, "Expenses")
        step("expenses: Undo on the empty state brings the row back", wait_count(app, r"^Edit Solo ₹5$", 1, "Expenses"))
        ctx.close()

        # ---- rapid double Remove
        for label, delay in (("normal speed", 0), ("slow server (1.5 s per delete)", 1500)):
            u2 = mk_user("e2", opening=1000)
            for amount, cat in [(11, "Aaa"), (22, "Bbb"), (33, "Ccc")]:
                add_exp(u2[2], amount, cat, day=5)
            ctx, page, app, net, ok = login_as(br, u2)
            app.tab("Expenses")
            wait_count(app, r"^Edit ", 3, "Expenses")
            if delay:
                def slow(route):
                    if route.request.method == "DELETE":
                        page.wait_for_timeout(delay)
                    route.continue_()
                page.route("**/expenses/*", slow)
            m = net.mark()
            page.get_by_role("button", name="Remove Ccc ₹33").first.dblclick()
            app.wait(2500 if delay else 1500)
            rest = names_of(list_exp(u2[2]))
            dels = net.sent(m, "DELETE")
            err = app.has("expense not found", 800)
            step(f"expenses: double-clicking Remove ({label}) removes exactly that one row",
                 rest == ["aaa", "bbb"], (rest, dels))
            app.shot(shotname(5, f"double-remove-{'slow' if delay else 'fast'}"))
            bug(f"EXP-2{'b' if delay else ''}", f"double-clicking Remove ({label}) sends two DELETEs and ends with an 'expense not found' error instead of the Undo offer",
                len(dels) == 1 and not err, sev="low",
                repro="Expenses: double-click (or tap twice quickly) a row's Remove button",
                observed=f"{len(dels)} DELETE requests, the second returns 404 and the red 'expense not found' snackbar replaces 'Deleted ... Undo'",
                expected="one DELETE; the Undo snackbar stays",
                fix="app/lib/expenses.dart _ExpensesScreenState._delete(): return early when _hidden already contains the id (and ignore a 404 on a row that is already hidden)",
                shot_name=shotname(5, f"double-remove-{'slow' if delay else 'fast'}"))
            ctx.close()


# ==================================================================== 11 resilience
def set_quiet(v):
    """While True the console / network noise is marked 'intentional' (the test breaks the network)."""
    global QUIET
    QUIET = v


@sec(11, "Resilience: offline, sleeping server, errors, slow server")
def sec_resilience(p):
    with chrome(p) as br:
        user = mk_user("z", opening=1000)
        tok = user[2]
        add_exp(tok, 20, "Zed", note="resilience row")

        # ---- A. a save while the connection is gone
        ctx, page, app, net, ok = login_as(br, user)
        step("resilience: logged in", ok)
        app.tab("Expenses")
        wait_count(app, r"^Edit Zed", 1, "Expenses")
        app.button("Add expense")
        app.fill("Amount", "5")
        fill_text(app, "Category", "Offline")
        set_quiet(True)
        ctx.set_offline(True)
        app.save()
        app.wait(1500)
        txt = app.text()
        app.shot(shotname(11, "offline-save"))
        technical = [s for s in ("ClientException", "Failed to fetch", "uri=") if s in txt]
        step("resilience: a failed save keeps the dialog open with an error", dialog_open(app))
        bug("RES-1", "saving while offline shows a raw exception ('ClientException: Failed to fetch, uri=http://...')",
            not technical, sev="medium",
            repro="Open Add expense, fill it, go offline (DevTools > Network > Offline), press Save",
            observed=f"red box contains {technical}; the same for goals, budgets, templates, balance settings",
            expected="'Could not reach the server. Check your connection and try again.' (the login screen already says this)",
            fix="app/lib/expenses.dart _submit() catch (e) and common.dart _FormDialogState._submit() catch: map non-ApiException errors to the same message auth_screen.dart uses",
            shot_name=shotname(11, "offline-save"))
        ctx.set_offline(False)
        set_quiet(False)
        app.save()
        step("resilience: back online the same dialog saves", app.has("Added Offline ₹5", 8000))
        app.snack_gone()

        # ---- B. switching section while offline, then coming back
        set_quiet(True)
        ctx.set_offline(True)
        app.tab("Goals")
        step("resilience: loading offline first shows 'Waking up the server…'", app.has("Waking up the server", 12000))
        app.shot(shotname(11, "offline-waking"))
        ctx.set_offline(False)
        step("resilience: going back online, the screen loads on its own", app.has("No savings goals yet", 25000))
        set_quiet(False)

        # ---- C. offline until the retries run out
        set_quiet(True)
        ctx.set_offline(True)
        app.tab("Expenses")
        t0 = time.time()
        got = app.has("Could not reach the server", 75000)
        took = time.time() - t0
        app.shot(shotname(11, "offline-error"))
        step("resilience: offline long enough -> 'Could not reach the server' with a Retry button",
             got and app.count(r"^Retry$") == 1)
        note(f"resilience: the error appeared after {took:.0f}s offline (a 'Waking up the server' panel is shown meanwhile)")
        bug("RES-2", "offline, the app says 'Waking up the server… free hosting sleeps' for ~40 s before 'Could not reach the server'",
            took < 15, sev="low",
            repro="Log in, go offline, open any section: wait",
            observed=f"{took:.0f} s of a misleading 'waking up' message (retries 2+4+6+8+10+12 s) for a user whose Wi-Fi dropped",
            expected="when navigator.onLine is false (or the failure is instant), go straight to the offline state with Retry",
            fix="app/lib/common.dart Loader._start / isServerAsleep(): skip the wake-up retries when the browser reports it is offline")
        ctx.set_offline(False)
        app.press(r"^Retry$")
        step("resilience: Retry after reconnecting loads the data", see(app, "Zed", None, 15000) or app.has("Zed", 8000))
        set_quiet(False)

        # ---- D. log out and log in without a connection
        set_quiet(True)
        ctx.set_offline(True)
        app.log_out()
        step("resilience: logging out offline still signs the user out locally",
             app.has("Know where your money goes.", 6000))
        app.button("Log in")
        app.fill("Username", user[0])
        app.fill("Password", user[1], exact=True)
        app.button("Log in", last=True)
        step("resilience: logging in offline gives a readable message",
             app.has("Could not reach the server. Check your connection and try again.", 8000))
        app.shot(shotname(11, "offline-login"))
        step("resilience: ... and the form is usable again (no stuck spinner)", app.count(r"^Log in$") >= 1)
        ctx.set_offline(False)
        set_quiet(False)
        app.button("Log in", last=True)
        step("resilience: the same form logs in once the connection is back", app.has(f"Hi, {user[0].capitalize()}", 10000))
        ctx.close()

        # ---- E. a sleeping server at start-up: the first 3 requests fail
        ctx, page, app, net = open_page(br, token=tok, goto=False)
        cnt = {"n": 0}

        def flaky(route):
            cnt["n"] += 1
            if cnt["n"] <= 3:
                route.abort("connectionrefused")
            else:
                route.continue_()

        set_quiet(True)
        page.route("**/auth/me", flaky)
        page.goto(BASE_URL)
        enable_a11y(page)
        step("resilience: a sleeping server at start-up shows 'Waking up the server…'", app.has("Waking up the server", 10000))
        app.shot(shotname(11, "waking-startup"))
        step("resilience: ... and the app loads by itself once the server answers",
             app.has(f"Hi, {user[0].capitalize()}", 40000) and cnt["n"] == 4, cnt)
        set_quiet(False)
        page.unroute("**/auth/me")

        # ---- E2. gateway errors (503) on data loads
        cnt2 = {"n": 0}

        def gateway(route):
            if route.request.method == "GET":
                cnt2["n"] += 1
                if cnt2["n"] <= 2:
                    route.fulfill(status=503, content_type="application/json", body='{"detail":"starting"}')
                    return
            route.continue_()

        set_quiet(True)
        page.route(re.compile(r"/expenses\?month="), gateway)
        app.tab("Expenses")
        step("resilience: a 503 from the host counts as a sleeping server", app.has("Waking up the server", 8000))
        step("resilience: ... and the list loads when the host recovers", app.has("Zed", 30000))
        set_quiet(False)
        page.unroute(re.compile(r"/expenses\?month="))

        # ---- F. a 500 from the server on a data load
        def broken(route):
            route.fulfill(status=500, content_type="application/json", body='{"detail":"boom"}')

        set_quiet(True)
        page.route(re.compile(r"/goals$"), broken)
        app.tab("Goals")
        app.has("Could not reach the server", 6000)
        txt = app.text()
        app.shot(shotname(11, "server-500"))
        bug("RES-3", "a server error (HTTP 500) on a data load is described as 'Could not reach the server … check that you are online'",
            "Could not reach the server" not in txt, sev="low",
            repro="Make any GET return 500 (or stop the database), open a section",
            observed="the offline panel appears although the server answered",
            expected="'Something went wrong on our side' with Retry; keep 'could not reach' for network failures",
            fix="app/lib/common.dart ErrorState / Loader: branch on ApiException vs ClientException")
        page.unroute(re.compile(r"/goals$"))
        set_quiet(False)
        if app.count(r"^Retry$"):
            app.press(r"^Retry$")
            step("resilience: Retry works once the server is healthy again", app.has("No savings goals yet", 10000))
        ctx.close()

        # ---- G. slow responses: busy states and no double submits
        u2 = mk_user("z2", opening=1000)
        ctx, page, app, net, ok = login_as(br, u2)

        def slow(route):
            if route.request.method in ("POST", "PUT", "DELETE"):
                page.wait_for_timeout(3000)
            route.continue_()

        page.route(re.compile(r"/(expenses|goals|recurring|budgets|account)"), slow)
        app.tab("Expenses")
        app.button("Add expense")
        app.fill("Amount", "8")
        fill_text(app, "Category", "Slow")
        m = net.mark()
        page.get_by_role("button", name=re.compile(r"^Save$")).first.dblclick()
        app.wait(900)
        app.shot(shotname(11, "slow-save-busy"))
        named = app.count(r"^Save$")
        page.keyboard.press("Enter")  # a third attempt while the first is in flight
        app.wait(300)
        step("resilience: while saving, the dialog stays open (Cancel is inert)", dialog_open(app) or app.count(r"^Save$") == 0)
        app.has("Added Slow", 9000)
        app.wait(1500)
        posts = net.sent(m, "POST", "/expenses")
        step("resilience: double-click + Enter on a slow Save send exactly one request", len(posts) == 1, len(posts))
        step("resilience: ... and the server has exactly one expense", len([e for e in list_exp(u2[2]) if e["category"] == "slow"]) == 1)
        bug("A11Y-1", "while a button is busy its accessible name disappears (the spinner replaces the label)",
            named >= 1, sev="low",
            repro="Slow network, press Save / Log in: a screen reader finds a nameless, disabled button",
            observed=f"{named} buttons named 'Save' while the request was running",
            expected="keep the label (e.g. Semantics(label: 'Saving…') or the original name) on the busy button",
            fix="app/lib/ui.dart Btn.build(): wrap the busy child in Semantics(label: label, ...) / ExcludeSemantics for the spinner",
            shot_name=shotname(11, "slow-save-busy"))
        app.snack_gone()

        app.tab("Goals")
        api("POST", "/goals", {"name": "Slow goal", "target": 100}, u2[2])
        refresh_tab(app, "Goals")
        app.button("Add money to Slow goal")
        app.fill("Amount", "4")
        m = net.mark()
        page.keyboard.press("Enter")
        app.wait(200)
        page.keyboard.press("Enter")
        app.wait(5000)
        saved = api("GET", "/goals", token=u2[2])[1][0]["saved"]
        step("resilience: Enter twice on a slow contribution adds the money once", saved == 4 and len(net.sent(m, "POST", "/contribute")) == 1,
             (saved, net.sent(m, "POST", "/contribute")))

        app.tab("Dashboard")
        m = net.mark()
        app.button("Balance settings")
        app.fill("Opening balance", "2000")
        page.get_by_role("button", name=re.compile(r"^Save$")).first.dblclick()
        app.wait(5000)
        step("resilience: double-clicking Save on balance settings sends one request", len(net.sent(m, "PUT", "/account")) == 1)
        page.unroute(re.compile(r"/(expenses|goals|recurring|budgets|account)"))

        # slow reads: switching section twice quickly ends on the last one
        def slow_get(route):
            if route.request.method == "GET":
                page.wait_for_timeout(2500)
            route.continue_()

        page.route(re.compile(r"/(goals|expenses)"), slow_get)
        app.tab("Goals")
        app.shot(shotname(11, "slow-load"))
        app.tab("Expenses")
        app.wait(5000)
        step("resilience: a slow section does not overwrite the one opened after it",
             app.has("Everything you spent in") and app.gone("Money you are setting aside", 500))
        page.unroute(re.compile(r"/(goals|expenses)"))
        ctx.close()

        # ---- H. login with slow responses
        u3 = mk_user("z3")
        ctx, page, app, net = open_page(br)

        def slow_login(route):
            page.wait_for_timeout(3000)
            route.continue_()

        page.route("**/auth/login", slow_login)
        app.button("Log in")
        app.fill("Username", u3[0])
        app.fill("Password", u3[1], exact=True)
        m = net.mark()
        page.get_by_role("button", name=re.compile(r"^Log in$")).last.click()
        app.wait(400)
        page.keyboard.press("Enter")
        app.wait(400)
        app.shot(shotname(11, "slow-login-busy"))
        back_busy = app.count(r"^Back to home$")
        step("resilience: while logging in slowly a second Enter sends nothing more", len(net.sent(m, "POST", "/auth/login")) <= 1)
        step("resilience: ... and the slow login completes", app.has(f"Hi, {u3[0].capitalize()}", 12000))
        step("resilience: only one login request in total", len(net.sent(m, "POST", "/auth/login")) == 1, net.sent(m, "POST", "/auth/login"))
        ctx.close()


# ==================================================================== 1 auth
def reg_form(app, name, pw, confirm=None):
    app.fill("Username", name)
    app.fill("Password", pw, exact=True)
    app.fill("Confirm password", pw if confirm is None else confirm)


def to_register(app):
    """From the landing page to the registration form."""
    app.button("Create account")
    return app.has("Create your account", 5000)


def submit(app):
    app.button("Create account" if app.has("Create your account", 300) else "Log in", last=True)


def token_of(page):
    raw = page.evaluate("localStorage.getItem('flutter.session_token')")
    return json.loads(raw) if raw else None


def tab_stops(page, n=14, shots=()):
    """The element that has focus after each Tab press, by accessible name. `shots` is a tuple of
    (press number, screenshot name): a picture is taken after that press."""
    js = """(()=>{const a=document.activeElement;const s=a.closest&&a.closest('flt-semantics');
        const nm=(a.getAttribute('aria-label')||(s&&(s.getAttribute('aria-label')||s.textContent))||a.textContent||'').trim().replace(/\\s+/g,' ').slice(0,30);
        return a.tagName.toLowerCase()+':'+nm})()"""
    out = []
    for i in range(n):
        page.keyboard.press("Tab")
        page.wait_for_timeout(250)
        out.append(page.evaluate(js))
        for k, name in shots:
            if k == i + 1:
                shot(name)
    return out


@sec(1, "Auth edge cases")
def sec_auth(p):
    with chrome(p) as br:
        u = mk_user("a")
        name = u[0]
        ctx, page, app, net = open_page(br)
        step("auth: landing", app.has("Know where your money goes."))
        step("auth: Create account opens the form", to_register(app))

        # --- the same name in another case is the same user
        m = net.mark()
        reg_form(app, name.upper(), PW)
        submit(app)
        step("auth: registering an existing name in capitals is refused inline",
             app.has("That username is already taken") and app.gone("Hi, ", 500))
        step("auth: ... and it did reach the server exactly once", len(net.sent(m, "POST", "/auth/register")) == 1)

        # --- username rules, nothing is sent for any of these
        for label, bad in [("with a space inside", "ab cd"), ("2 characters", "ab"),
                           ("31 characters", "x" * 31), ("unicode", "José"), ("unicode letters", "用户名用户"),
                           ("symbol", "a@b.com")]:
            m = net.mark()
            reg_form(app, bad, PW)
            submit(app)
            ok = app.has("Use 3-30 letters, numbers, dots, dashes or underscores", 3000)
            step(f"auth: username {label} is rejected inline, nothing sent",
                 ok and not net.sent(m, "POST", "/auth/register"), net.sent(m))

        # --- password rules
        m = net.mark()
        reg_form(app, f"e{RUN}pw", "x" * 7)
        submit(app)
        step("auth: password of 7 characters is rejected inline, nothing sent",
             app.has("Use at least 8 characters", 3000) and not net.sent(m, "POST", "/auth/register"))
        m = net.mark()
        reg_form(app, f"e{RUN}pw", "longenough1", confirm="longenough2")
        submit(app)
        step("auth: password mismatch is rejected inline, nothing sent",
             app.has("The passwords do not match", 3000) and not net.sent(m, "POST", "/auth/register"))

        # --- 129 characters: the UI lets it through, what does the user see?
        m = net.mark()
        reg_form(app, f"e{RUN}p129", "p" * 129)
        submit(app)
        app.wait(1500)
        txt = app.text()
        st = net.statuses(m, "/auth/register")
        shot(shotname(1, "password-129"))
        raw = ("String should have at most" in txt) or ("password:" in txt)
        note(f"auth: 129-character password -> server status {st}")
        bug("AUTH-1", "an over-long password (129 chars) shows the raw validation text instead of a readable message",
            not raw, sev="low",
            repro="Create account, any free username, a 129-character password (twice), Create account",
            observed="red box reads 'password: String should have at most 128 characters' (pydantic text with the field name)",
            expected="inline 'Use at most 128 characters' on the Password field, checked before sending (like the 8-character minimum)",
            fix="app/lib/auth_screen.dart _validate() (add a max-length rule); api.dart _errorMessage() could also turn known 422 types into plain English",
            shot_name=shotname(1, "password-129"))
        # 128 is fine
        n128 = f"e{RUN}p128"
        reg_form(app, n128, "q" * 128)
        submit(app)
        step("auth: a 128-character password is accepted", app.has(f"Hi, {n128.capitalize()}", 10000))
        app.log_out()
        app.button("Log in")
        app.fill("Username", n128)
        app.fill("Password", "q" * 128, exact=True)
        app.button("Log in", last=True)
        step("auth: the 128-character password works on login", app.has(f"Hi, {n128.capitalize()}", 10000))
        app.log_out()

        # --- boundary usernames made through the UI: 3 and 30 characters
        for label, nm in [("30-character", (f"e{RUN}" + "x" * 30)[:30]), ("3-character", None)]:
            if nm is None:
                for _ in range(5):
                    nm = os.urandom(2).hex()[:3]
                    if api("POST", "/auth/login", {"username": nm, "password": "zzzzzzzz"})[0] == 401:
                        break
            app.button("Create account")
            reg_form(app, nm, PW)
            submit(app)
            step(f"auth: a {label} username can register ({nm[:12]})", app.has(f"Hi, {nm.capitalize()}", 10000))
            if label.startswith("30"):
                app.shot(shotname(1, "username-30-chars"))
                ov = overflow(app)
                step("auth: the 30-character name does not overflow the header", not ov["bad"], ov)
            app.log_out()

        # --- Enter key
        app.button("Log in")
        app.fill("Username", name)
        app.fill("Password", PW, exact=True)
        m = net.mark()
        page.keyboard.press("Enter")
        step("auth: Enter in the password field logs in", app.has(f"Hi, {name.capitalize()}", 10000))
        step("auth: ... with exactly one login request", len(net.sent(m, "POST", "/auth/login")) == 1)
        app.log_out()
        app.button("Create account")
        n2 = f"e{RUN}ent"
        reg_form(app, n2, PW)
        m = net.mark()
        page.keyboard.press("Enter")
        step("auth: Enter in the confirm field registers", app.has(f"Hi, {n2.capitalize()}", 10000))
        step("auth: ... with exactly one register request", len(net.sent(m, "POST", "/auth/register")) == 1)
        app.log_out()

        # --- double click on the submit button
        app.button("Create account")
        n3 = f"e{RUN}dbl"
        reg_form(app, n3, PW)
        m = net.mark()
        page.get_by_role("button", name=re.compile(r"^Create account$")).last.dblclick()
        app.has("Hi, ", 10000)
        app.wait(1500)
        step("auth: double-clicking Create account sends one request", len(net.sent(m, "POST", "/auth/register")) == 1,
             net.sent(m, "POST", "/auth/register"))
        step("auth: ... and lands on the dashboard without a 'taken' error",
             app.has(f"Hi, {n3.capitalize()}") and app.gone("already taken", 500))
        app.log_out()
        app.button("Log in")
        app.fill("Username", n3)
        app.fill("Password", PW, exact=True)
        m = net.mark()
        page.get_by_role("button", name=re.compile(r"^Log in$")).last.dblclick()
        app.has("Hi, ", 10000)
        app.wait(1000)
        step("auth: double-clicking Log in sends one request", len(net.sent(m, "POST", "/auth/login")) == 1)
        app.log_out()

        # --- Show password
        app.button("Log in")
        app.fill("Password", "visible?", exact=True)
        before = page.get_by_label("Password", exact=True).first.get_attribute("type")
        errs0 = len([e for e in events if e["kind"] == "pageerror"])
        app.button("Show password")
        step("auth: Show password becomes Hide password", app.has("Hide password", 3000))
        after = page.get_by_label("Password", exact=True).first.get_attribute("type")
        step("auth: the field type flips password -> text", (before, after) == ("password", "text"), (before, after))
        app.shot(shotname(1, "show-password"))
        errs1 = len([e for e in events if e["kind"] == "pageerror"]) - errs0
        bug("AUTH-4", "pressing Show password throws an uncaught JavaScript 'Error' in the console (main.dart.js) every time",
            errs1 == 0, sev="low",
            repro="Log in screen, type a password, press the eye icon (also Hide password) with DevTools console open",
            observed=f"{errs1} uncaught page error(s) per press: 'Error at ... main.dart.js'; the toggle itself works",
            expected="no uncaught exceptions",
            fix="app/lib/auth_screen.dart: the obscureText toggle on the focused password field (try keeping a stable key on the TextField / use ExcludeFocus on the IconBtn); may be a Flutter web engine issue to report upstream",
            shot_name=shotname(1, "show-password"))
        app.button("Hide password")
        step("auth: Hide password hides it again",
             page.get_by_label("Password", exact=True).first.get_attribute("type") == "password")

        # --- switching Log in <-> Create account clears the errors
        app.fill("Username", "")
        app.fill("Password", "", exact=True)
        app.button("Log in", last=True)
        step("auth: empty login shows both errors", app.has("Enter your username") and app.has("Enter your password"))
        app.button("Create an account")
        step("auth: switching to Create account clears the login errors",
             app.has("Create your account") and app.gone("Enter your username", 1500) and app.gone("Enter your password", 500))
        reg_form(app, "a", "b", confirm="c")
        submit(app)
        step("auth: registration errors shown", app.has("The passwords do not match"))
        app.button("I already have an account")
        step("auth: switching back to Log in clears the registration errors",
             app.has("Welcome back") and app.gone("The passwords do not match", 1500) and app.gone("Use at least 8 characters", 500))
        app.button("Create account")  # the segmented tab
        step("auth: the Create account tab switches too", app.has("Create your account"))
        app.button("Log in")  # the segmented tab (first match)
        step("auth: the Log in tab switches back", app.has("Welcome back"))
        un = field(app, "Username")
        note(f"auth: the typed username is {'kept' if un else 'cleared'} when switching modes ({un!r})")

        # --- Back to home
        app.button("Back to home")
        step("auth: Back to home returns to the landing page",
             app.has("Know where your money goes.") and app.gone("Welcome back", 500))
        app.button("Log in")
        step("auth: ... and Log in opens an empty form again", field(app, "Username") == "")

        # --- login: spaces around the username, capitals, passwords with spaces
        app.fill("Username", f"   {name}   ")
        app.fill("Password", PW, exact=True)
        app.button("Log in", last=True)
        step("auth: leading/trailing spaces around the username are ignored on login",
             app.has(f"Hi, {name.capitalize()}", 10000))
        app.log_out()
        app.button("Log in")
        app.fill("Username", name.upper())
        app.fill("Password", PW, exact=True)
        app.button("Log in", last=True)
        step("auth: logging in with the name in capitals works", app.has(f"Hi, {name.capitalize()}", 10000))
        app.log_out()
        api("POST", "/auth/register", {"username": f"e{RUN}spc", "password": "  spaced pw  "})
        app.button("Log in")
        app.fill("Username", f"e{RUN}spc")
        app.fill("Password", "spaced pw", exact=True)
        app.button("Log in", last=True)
        a1 = app.has("Wrong username or password", 5000)
        app.fill("Password", "  spaced pw  ", exact=True)
        app.button("Log in", last=True)
        step("auth: passwords are not trimmed (wrong without the spaces, right with them)",
             a1 and app.has("Hi, ", 10000))
        app.log_out()
        app.button("Log in")
        app.fill("Username", "x" * 101)
        app.fill("Password", "whatever", exact=True)
        app.button("Log in", last=True)
        app.wait(1500)
        t = app.text()
        bug("AUTH-1b", "a 101-character username on the login form shows raw validation text",
            "String should have at most" not in t and "username:" not in t, sev="low",
            repro="Log in, 101-character username, any password, Log in",
            observed="'username: String should have at most 100 characters'", expected="'Wrong username or password'",
            fix="same as AUTH-1: api.dart _errorMessage() / auth_screen.dart _submit()")
        ctx.close()

        # --- session expiry from outside
        u2 = mk_user("s")
        ctx, page, app, net, ok = login_as(br, u2)
        step("auth: logged in with a pre-seeded session", ok)
        tok = token_of(page)
        step("auth: the browser stores the session token under flutter.session_token", bool(tok) and tok == u2[2], tok)
        st, _ = api("POST", "/auth/logout", token=tok)
        step("auth: revoking the token from outside works (204)", st == 204, st)
        app.tab("Expenses")
        step("auth: after the session is revoked the next click lands on the login screen with a notice",
             app.has("Your session ended. Please log in again.", 8000) and app.has("Welcome back"))
        app.shot(shotname(1, "session-ended"))
        step("auth: the dead token is removed from the browser", token_of(page) is None)
        app.fill("Username", u2[0])
        app.fill("Password", u2[1], exact=True)
        app.button("Log in", last=True)
        step("auth: logging in again works and the notice is gone",
             app.has(f"Hi, {u2[0].capitalize()}", 10000) and app.gone("Your session ended", 1500))
        app.reload()
        step("auth: ... and a reload keeps the new session", app.has(f"Hi, {u2[0].capitalize()}", 10000))
        ctx.close()

        # --- session expires while a dialog is open
        u3 = mk_user("d")
        ctx, page, app, net, ok = login_as(br, u3)
        app.tab("Expenses")
        app.button("Add expense")
        app.fill("Amount", "5")
        app.fill("Category", "Late")
        api("POST", "/auth/logout", token=u3[2])
        app.save()
        app.wait(1500)
        still = app.count(r"^Save$") > 0
        app.shot(shotname(1, "expired-with-dialog"))
        step("auth: expiry while a dialog is open clears the dead token", token_of(page) is None)
        bug("AUTH-3", "the Add expense dialog stays on top of the login screen after the session ended",
            not still, sev="low",
            repro="Log in, open Add expense, revoke the session elsewhere (log out in another browser), press Save",
            observed="the dialog (with 'Please log in again' inside) remains over the login screen",
            expected="open dialogs are closed when the session ends and only the login screen is shown",
            fix="app/lib/main.dart _Gate / auth.dart _sessionEnded(): Navigator.popUntil(first) when the status becomes loggedOut",
            shot_name=shotname(1, "expired-with-dialog"))
        if still:
            app.cancel()
        step("auth: after closing the dialog the login screen shows the 'session ended' notice",
             app.has("Your session ended. Please log in again.", 4000) and app.has("Welcome back"))
        ctx.close()

        # --- the same user in two browsers at once
        u4 = mk_user("t", opening=1000)
        ctx_a, pa, app_a, net_a, ok_a = login_as(br, u4)
        step("auth: browser A is logged in", ok_a)
        ctx_b, pb, app_b, net_b = open_page(br)
        app_b.log_in(u4[0], u4[1])
        step("auth: browser B logs in as the same user through the form",
             app_b.has(f"Hi, {u4[0].capitalize()}", 10000))
        CUR["app"] = app_a
        app_a.tab("Expenses")
        app_a.button("Add expense")
        app_a.fill("Amount", "77")
        app_a.fill("Category", "Shared")
        app_a.save()
        step("auth: A adds an expense", app_a.has("Added Shared ₹77") or app_a.count(r"^Edit Shared") == 1)
        CUR["app"] = app_b
        app_b.tab("Expenses")
        step("auth: B sees A's expense after re-opening the Expenses tab", see(app_b, "Shared", "Expenses"))
        app_b.tab("Dashboard")
        step("auth: B's balance reflects it (1000 - 77 = 923)", app_b.has("You have ₹923 left"))
        CUR["app"] = app_a
        app_a.log_out()
        step("auth: A logs out", app_a.has("Know where your money goes."))
        CUR["app"] = app_b
        app_b.tab("Expenses")
        step("auth: B stays logged in after A logs out (sessions are separate)",
             app_b.has("Shared") and app_b.gone("Your session ended", 1000))
        ctx_a.close()
        ctx_b.close()


# ==================================================================== 3 text inputs
def fill_text(app, label, value, exact=False):
    """fill() for free text: non-ASCII and long values are inserted as one input event."""
    f = app.pg.get_by_label(label, exact=exact).first
    f.click()
    app.wait(500)
    app.pg.keyboard.press("Control+A")
    app.pg.keyboard.press("Delete")
    if value:
        if value.isascii() and len(value) <= 60:
            app.pg.keyboard.type(value, delay=15)
        else:
            app.pg.keyboard.insert_text(value)
            app.wait(300)


LEAF_HEIGHT_JS = r"""(needle) => {
  // heights of the smallest semantic boxes that contain the text (a row, or the text itself)
  const hits = [];
  document.querySelectorAll('flt-semantics').forEach(e => {
    const t = (e.getAttribute('aria-label') || '') + ' ' + (e.textContent || '');
    const r = e.getBoundingClientRect();
    if (t.includes(needle) && r.width > 40 && r.height > 0) hits.push(Math.round(r.height));
  });
  hits.sort((a, b) => a - b);
  return hits.slice(0, 3);
}"""


def leaf_heights(app, needle):
    return app.pg.evaluate(LEAF_HEIGHT_JS, needle)


@sec(3, "Text inputs: emoji, spaces, long, HTML, SQL")
def sec_text(p):
    cat200 = "A" + "b" * 199
    script_cat = "<script>alert(1)</script>"
    xss_note = '<img src=x onerror="window.__xss=1">'
    sql_cat = "'; DROP TABLE expenses;--"
    sql_note = "Robert'); DROP TABLE users;--"
    long_note = "Longnote " + "word " * 199  # about 1000 characters with spaces
    solid_note = "Solid" + "W" * 995  # 1000 characters, no spaces
    js_before = len([e for e in events if e["kind"] == "JS-DIALOG"])
    with chrome(p) as br:
        user = mk_user("x", opening=100000)
        tok = user[2]
        ctx, page, app, net, ok = login_as(br, user)
        step("text: logged in", ok)

        def add_ui(amount, category, note_=""):
            app.tab("Expenses")
            app.button("Add expense")
            app.fill("Amount", amount)
            fill_text(app, "Category", category)
            if note_:
                fill_text(app, "Note", note_)
            app.save()

        # emoji through the form
        add_ui("10", "🍕 Pizza", "emoji note 😀")
        step("text: an emoji category is accepted", app.has("Added") or not dialog_open(app))
        app.wait(1500)
        rows = list_exp(tok)
        step("text: the emoji category and note are stored intact",
             any(r["category"] == "🍕 pizza" and r["note"] == "emoji note 😀" for r in rows), rows[:1])
        app.tab("Dashboard")
        app.tab("Expenses")
        step("text: the emoji row is listed and its buttons are named after it", app.count(r"^Edit .*Pizza ₹10$") == 1,
             page.evaluate(BUTTONS_JS))

        # only spaces
        m = net.mark()
        app.button("Add expense")
        app.fill("Amount", "9")
        fill_text(app, "Category", "     ")
        app.save()
        step("text: a category of only spaces is rejected inline, nothing sent",
             app.has("Pick or type a category") and not net.sent(m, "POST", "/expenses"))
        app.cancel()

        # 200 characters through the form
        add_ui("11", cat200, "n200")
        app.wait(1500)
        step("text: a 200-character category is accepted", any(r["category"] == cat200.lower() for r in list_exp(tok)))

        # script / SQL text through the form
        add_ui("12", script_cat, xss_note)
        app.wait(1200)
        add_ui("13", sql_cat, sql_note)
        app.wait(1200)
        rows = list_exp(tok)
        step("text: HTML-looking text is stored verbatim (lower-cased category)",
             any(r["category"] == script_cat.lower() and r["note"] == xss_note for r in rows))
        step("text: SQL-looking text is stored verbatim and the tables are intact",
             any(r["category"] == sql_cat.lower() and r["note"] == sql_note for r in rows) and len(rows) >= 4, len(rows))

        # more rows through the API (faster): long notes, unbroken long note
        add_exp(tok, 14, "Plain", note=long_note)
        add_exp(tok, 15, "Plain", note=solid_note)
        add_exp(tok, 16, "Plain", note="   padded   ")
        api("PUT", "/budgets", {"category": cat200, "month": mkey(0), "cap": 100}, tok)
        api("PUT", "/budgets", {"category": script_cat, "month": mkey(0), "cap": 100}, tok)
        api("PUT", "/budgets", {"category": "Plain", "month": mkey(0), "cap": 10}, tok)
        api("POST", "/recurring", {"amount": 21, "category": cat200, "note": long_note, "day_of_month": 3}, tok)
        api("POST", "/recurring", {"amount": 22, "category": script_cat, "note": xss_note, "day_of_month": 4}, tok)
        names = ["Line1\nLine2", "G" * 200, "Goal <b>bold</b> 🎯", "A very long goal name " * 10, "'; DROP TABLE goals;--"]
        for nm in names:
            st, g = api("POST", "/goals", {"name": nm, "target": 500}, tok)
            step(f"text: the API accepts the goal name {nm[:20]!r}", st == 201, (st, g))
        app.reload()
        app.has("Hi, ", 10000)

        # Expenses
        app.tab("Expenses")
        app.has("Plain", 6000)
        app.shot(shotname(3, "expenses"))
        ov = overflow(app)
        step("text: the Expenses list does not overflow sideways with the odd text", not ov["bad"], ov)
        step("text: HTML-looking text is shown as plain text", app.has("<script>alert(1)</script>") or app.has(script_cat))
        step("text: SQL-looking text is shown as plain text", app.has("Drop Table Expenses") and app.has("DROP TABLE users"))
        # (heights of semantic containers are not a reliable measure of the painted text: judge the screenshots)
        if not WIDE:
            scroll_down(app, 2)
            app.shot(shotname(3, "expenses-scrolled"))
        # filter on the long category tab (the tab label is as long as the category)
        long_tab = [b for b in page.evaluate(BUTTONS_JS) if b.startswith("A" + "b" * 20)]
        step("text: the 200-character category has a filter tab", bool(long_tab), page.evaluate(BUTTONS_JS)[:12])
        if long_tab:
            app.press(r"^A" + "b" * 20)
            app.shot(shotname(3, "expenses-long-tab"))
            ov = overflow(app)
            step("text: the long filter tab does not overflow sideways", not ov["bad"] and ov["scrollW"] <= ov["W"], ov)
            app.press(r"^All \(")

        # Dashboard
        app.tab("Dashboard")
        app.has("Hi, ", 6000)
        app.shot(shotname(3, "dashboard"))
        ov = overflow(app)
        step("text: the Dashboard does not overflow sideways with the odd text", not ov["bad"], ov)
        scroll_down(app, 1)
        app.shot(shotname(3, "dashboard-scrolled"))

        # Budgets
        app.tab("Budgets")
        app.has("Plain", 6000)
        app.shot(shotname(3, "budgets"))
        ov = overflow(app)
        step("text: Budgets does not overflow sideways with the odd categories", not ov["bad"], ov)

        # Recurring
        app.tab("Recurring")
        app.has("Templates", 6000)
        app.shot(shotname(3, "recurring"))
        ov = overflow(app)
        step("text: Recurring does not overflow sideways with the odd templates", not ov["bad"], ov)

        # Goals
        app.tab("Goals")
        app.has("Saved so far", 6000)
        app.shot(shotname(3, "goals"))
        ov = overflow(app)
        step("text: Goals does not overflow sideways with the odd names", not ov["bad"], ov)
        step("text: the newline goal is listed", app.has("Line1") and app.has("Line2"))
        step("text: HTML in a goal name is plain text", app.has("<b>bold</b>"))
        scroll_down(app, 2)
        app.shot(shotname(3, "goals-scrolled"))
        # the dialogs that repeat the name
        scroll_top(app)
        if app.count(r"^Add money to G{20}"):
            app.press(r"^Add money to G{20}")
            app.shot(shotname(3, "goal-dialog-long-name"))
            ov = overflow(app)
            step("text: the 'Add to <200-character name>' dialog fits the screen", not ov["bad"] and ov["scrollW"] <= ov["W"], ov)
            app.cancel()
            app.press(r"^Remove G{20}")
            app.shot(shotname(3, "goal-delete-long-name"))
            ov = overflow(app)
            step("text: the 'Delete <200-character name>?' dialog fits the screen", not ov["bad"] and ov["scrollW"] <= ov["W"], ov)
            app.cancel()
        else:
            note("text: the 200-character goal's buttons were not in the accessibility tree; dialog check skipped")

        # nothing was executed
        jsd = len([e for e in events if e["kind"] == "JS-DIALOG"]) - js_before
        step("text: no script ran (no alert dialog)", jsd == 0)
        step("text: no injected <img>/<script> elements, no window.__xss",
             page.evaluate("!window.__xss && !document.querySelector('img[src=x]') && !document.querySelector('script:not([src])')") is True)
        step("text: every expense row is still there after the SQL-looking text",
             len(list_exp(tok)) >= 7, len(list_exp(tok)))
        ctx.close()


# ==== SECTIONS-INSERT-HERE ====


def main():
    pick = os.environ.get("SECTIONS")
    wanted = [int(x) for x in pick.split(",")] if pick else sorted(SECTIONS)
    global PHASE
    t0 = time.time()
    with sync_playwright() as p:
        for n in wanted:
            title, fn = SECTIONS[n]
            PHASE = f"{n} {title}"
            print(f"\n===== {PHASE} ({VW}x{VH}) =====", flush=True)
            try:
                fn(p)
            except Exception as e:  # a crashed section must not hide the others
                traceback.print_exc()
                step(f"section {n} ran to the end ({type(e).__name__}: {str(e)[:120]})", False)
    report(time.time() - t0)


def report(elapsed):
    fails = [n for n, s in results if s == "FAIL"]
    bad = [n for n, s in results if s == "BUG"]
    print("\n" + "=" * 70)
    print(f"viewport {VW}x{VH}: {len(results)} checks, {sum(1 for _, s in results if s == 'PASS')} passed, "
          f"{len(fails)} FAIL, {len(bad)} BUG  ({elapsed:.0f}s)")
    if fails:
        print("\nFAILED CHECKS (script problem or regression):")
        for n in fails:
            print("  -", n)
    if bugs:
        print("\nKNOWN BUGS (the app gets these wrong):")
        order = {"high": 0, "medium": 1, "low": 2}
        for b in sorted(bugs.values(), key=lambda b: order.get(b["sev"], 3)):
            print(f"  [{b['id']}] {b['sev'].upper()}: {b['title']}")
            print(f"      repro:    {b['repro']}")
            print(f"      observed: {b['observed']}")
            print(f"      expected: {b['expected']}")
            print(f"      fix:      {b['fix']}")
            print(f"      shot:     {b['shot']}")
    if notes:
        print("\nOBSERVATIONS:")
        for ph, t in notes:
            print(f"  ({ph}) {t}")
    if events:
        print("\nCONSOLE / NETWORK NOISE (grouped; 'intentional' = the test broke the network on purpose):")
        agg = {}
        for e in events:
            k = (e["phase"], e["kind"], e["text"], e["quiet"])
            agg[k] = agg.get(k, 0) + 1
        for (ph, kind, text, quiet), c in sorted(agg.items()):
            tag = "intentional" if quiet else "UNEXPECTED" if (kind in ("pageerror", "console", "requestfailed", "http500", "JS-DIALOG") or kind.startswith("http5")) else "http"
            print(f"  [{tag}] x{c} {kind} {text}  ({ph})")
    sys.exit(1 if fails or (STRICT_BUGS and bad) else 0)


if __name__ == "__main__":
    main()
