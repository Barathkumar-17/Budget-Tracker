"""UI + UX audit of the Budget Tracker web app: real screenshots, measured numbers.

Run against a running app + backend (fresh database recommended), for example:

    cd backend
    BUDGET_DB=audit.db python -m uvicorn main:app --port 8030 &
    python seed_demo.py --api http://127.0.0.1:8030
    cd ../e2e
    PYTHONIOENCODING=utf-8 BROWSER_CHANNEL=chrome BASE_URL=http://127.0.0.1:8030/ python ui_audit.py all

Stages (pass one or more as arguments; `all` runs them in this order):

    contrast  WCAG contrast ratios for every text/background pairing (pure maths, no browser)
    matrix    every screen at 11 viewport sizes -> $AUDIT_DIR/matrix/<size>/*.png (+ contact sheets)
    a11y      accessibility tree, heading order, touch targets, keyboard/focus, dialogs, live regions
    display   zoom 200/400 %, reduced motion, light colour scheme, forced colours, first-paint frames
    perf      slow-3G first load: what is seen when, bytes transferred, time to interactive
    ux        long lists (300 expenses), extreme values, month boundary, date picker, flow timings

Options by environment: AUDIT_DIR (default ./ui-audit-out), SIZES ("390x844,1280x800" limits the matrix),
BROWSER_CHANNEL=chrome to use installed Chrome, BASE_URL (default http://127.0.0.1:8000/).
Flutter draws to a canvas, so controls are found by accessible name through the semantics layer
(see common.py). Numbers are printed and also written to $AUDIT_DIR/results.json.
"""
import json
import math
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from playwright.sync_api import sync_playwright  # noqa: E402

import common  # noqa: E402
from common import App  # noqa: E402

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8000/")
API = BASE_URL.rstrip("/")
OUT = os.path.abspath(os.environ.get("AUDIT_DIR", "ui-audit-out"))
CHANNEL = os.environ.get("BROWSER_CHANNEL") or None
STAMP = str(int(time.time()) % 1000000)
_COUNTER = [0]


def _uniq(prefix):
    _COUNTER[0] += 1
    return f"{prefix}{STAMP}x{_COUNTER[0]}"[:30]
PW = "audit password 1"

SIZES = [(320, 568), (360, 740), (390, 844), (412, 915), (768, 1024), (1024, 768), (1280, 800),
         (1440, 900), (1920, 1080), (2560, 1440), (844, 390)]
if os.environ.get("SIZES"):
    SIZES = [tuple(int(v) for v in s.lower().split("x")) for s in os.environ["SIZES"].split(",")]

RESULTS = {}


def out(*parts):
    p = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(p) if os.path.splitext(p)[1] else p, exist_ok=True)
    return p


def note(stage, key, value):
    RESULTS.setdefault(stage, {})[key] = value
    print(f"[{stage}] {key}: {value}", flush=True)


def save_results():
    path = out("results.json")
    old = {}
    if os.path.exists(path):
        try:
            old = json.load(open(path, encoding="utf-8"))
        except Exception:
            old = {}
    old.update(RESULTS)
    json.dump(old, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False, default=str)


# ---------------------------------------------------------------- API helpers


def api(method, path, body=None, token=None, ok=(200, 201, 204)):
    req = urllib.request.Request(
        API + path, method=method, data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path}: {e.code} {e.read().decode()[:200]}")


def new_user(prefix):
    """Registers a fresh account through the API; returns (username, token)."""
    name = _uniq(prefix)
    s = api("POST", "/auth/register", {"username": name, "password": PW})
    return name, s["token"]


def demo_user(prefix):
    """A fresh account filled like seed_demo.py does (3 budgets, 9 expenses, 3 templates, 2 goals)."""
    name = _uniq(prefix)
    seed = os.path.join(HERE, "..", "backend", "seed_demo.py")
    subprocess.run([sys.executable, seed, "--api", API, "--username", name, "--password", PW],
                   check=True, capture_output=True)
    return name, api("POST", "/auth/login", {"username": name, "password": PW})["token"]


# ---------------------------------------------------------------- browser helpers


ANDROID_UA = ("Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) "
              "Chrome/130.0.0.0 Mobile Safari/537.36")


def is_mobile_size(w, h):
    """Sizes that stand for phones and tablets: they are opened as an Android touch device.
    This matters: Flutter picks a compact visual density (36 px buttons instead of 44) on a desktop
    user agent, so a phone must be emulated with a mobile UA to see what a phone really shows."""
    return w <= 844 and not (w, h) == (1024, 768) or (w, h) == (768, 1024)


def launch(p, w, h, scale=1, token=None, scheme="dark", reduced=None, forced=None, semantics=True,
           mobile=None, url=None):
    """New browser + page at w x h. With a token the page starts logged in (the app keeps its
    session token in localStorage under flutter.session_token). mobile=None decides from the size."""
    touch = is_mobile_size(w, h) if mobile is None else mobile
    common.WIDTH, common.HEIGHT = w, h
    browser = p.chromium.launch(channel=CHANNEL, headless=True)
    kw = dict(viewport={"width": w, "height": h}, device_scale_factor=scale, color_scheme=scheme)
    if reduced:
        kw["reduced_motion"] = reduced
    if forced:
        kw["forced_colors"] = forced
    if touch:
        kw.update(has_touch=True, is_mobile=True, user_agent=ANDROID_UA)
    ctx = browser.new_context(**kw)
    if token:
        ctx.add_init_script(f"localStorage.setItem('flutter.session_token', JSON.stringify('{token}'));")
    page = ctx.new_page()
    errors = []
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(url or BASE_URL)
    if semantics:
        enable_semantics(page)
    app = App(page)
    app.pg = page
    return browser, ctx, app, errors


def enable_semantics(page):
    """Switches Flutter's accessibility layer on. A mobile user agent needs a click that lands in the
    centre of the placeholder (what a screen reader sends); a desktop one takes a plain click."""
    page.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=90000)
    page.wait_for_timeout(1800)
    page.evaluate("""() => { const e = document.querySelector('flt-semantics-placeholder'); if (!e) return;
      const r = e.getBoundingClientRect();
      e.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, view: window,
                                               clientX: r.x + r.width / 2, clientY: r.y + r.height / 2})); }""")
    page.wait_for_timeout(1200)
    if not page.evaluate("document.querySelectorAll('flt-semantics').length"):
        page.evaluate("document.querySelector('flt-semantics-placeholder') && document.querySelector('flt-semantics-placeholder').click()")
        page.wait_for_timeout(1200)
    page.wait_for_timeout(500)


def shot(app, path, wait=600, park=True):
    """Screenshot; parks the pointer so no hover state leaks into the picture."""
    if park:
        app.pg.mouse.move(2, 2)
    app.pg.wait_for_timeout(wait)
    app.pg.screenshot(path=path)
    return path


SEM_JS = r"""() => Array.from(document.querySelectorAll('flt-semantics')).map(e => {
  const r = e.getBoundingClientRect();
  return {role: e.getAttribute('role') || '', label: (e.getAttribute('aria-label') || '').slice(0, 80),
          text: (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 80),
          x: r.x, y: r.y, w: r.width, h: r.height, tabindex: e.getAttribute('tabindex'),
          current: e.getAttribute('aria-current'), disabled: e.getAttribute('aria-disabled'),
          live: e.getAttribute('aria-live'), modal: e.getAttribute('aria-modal'),
          expanded: e.getAttribute('aria-expanded'), tap: e.hasAttribute('flt-tappable')};
}).filter(o => o.w > 0 && o.h > 0)"""


def sem(app):
    return app.pg.evaluate(SEM_JS)


def overflow_report(app, w, h):
    """Semantics nodes that stick out of the viewport sideways (clipped or horizontally scrollable)."""
    bad = []
    for s in sem(app):
        if s["x"] < -1 or s["x"] + s["w"] > w + 1:
            if s["w"] < w * 3 and (s["role"] or s["text"]):  # ignore the page-wide scroll containers
                bad.append((s["role"], s["text"][:40], round(s["x"]), round(s["w"])))
    return bad[:8]


def scroll_series(app, name, folder, w, h, max_steps=6):
    """Top of the page, then wheel-scrolled screens until nothing moves: returns the file list."""
    files = []
    last = None
    for i in range(max_steps):
        path = os.path.join(folder, f"{name}-{i}.png")
        shot(app, path, wait=500 if i else 900)
        data = open(path, "rb").read()
        if data == last:
            os.remove(path)
            break
        last = data
        files.append(path)
        app.pg.mouse.move(w / 2, h / 2)
        app.pg.mouse.wheel(0, h * 0.8)
        app.pg.wait_for_timeout(700)
    app.pg.mouse.move(w / 2, h / 2)
    app.pg.mouse.wheel(0, -20000)
    app.pg.wait_for_timeout(600)
    return files


def sheet(files, path, gap=14, max_w=2600, label=True):
    """Contact sheet: images side by side (scaled down to max_w), for reviewing many screens at once."""
    from PIL import Image, ImageDraw
    files = [f for f in files if f and os.path.exists(f)]
    if not files:
        return None
    ims = [Image.open(f).convert("RGB") for f in files]
    total = sum(i.width for i in ims) + gap * (len(ims) - 1)
    scale = min(1.0, max_w / total)
    ims = [i.resize((max(1, int(i.width * scale)), max(1, int(i.height * scale)))) for i in ims]
    H = max(i.height for i in ims) + (16 if label else 0)
    sh = Image.new("RGB", (sum(i.width for i in ims) + gap * (len(ims) - 1), H), (60, 60, 70))
    x = 0
    d = ImageDraw.Draw(sh)
    for f, i in zip(files, ims):
        sh.paste(i, (x, 16 if label else 0))
        if label:
            d.text((x + 2, 2), os.path.basename(f)[:40], fill=(255, 255, 0))
        x += i.width + gap
    sh.save(path)
    return path


# =============================================================== STAGE: contrast


def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = rgb
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def over(fg, a, bg):
    """Composite colour fg at alpha a over opaque bg."""
    return tuple(round(f * a + b * (1 - a)) for f, b in zip(fg, bg))


def stage_contrast():
    MID = hexrgb("05060F")
    FROST = (186, 215, 247)
    ICE, FROSTT, MIST, FOG = map(hexrgb, ("D8ECF8", "D1E4FA", "C7D3EA", "9DA7BA"))
    VIOLET, WHITE = hexrgb("663AF3"), (255, 255, 255)
    BLUEPRINT, EMBER_T, TEAL_T = hexrgb("B6D9FC"), hexrgb("F08A6D"), hexrgb("3FBFA8")
    EMBER_B, TEAL_B = hexrgb("E46D4C"), hexrgb("269684")
    card_top = over(FROST, 0.055, MID)
    card = over(FROST, 0.03, MID)
    cardbot = over(FROST, 0.02, MID)
    deep = over(MID, 0.97, MID)
    surface2 = over((186, 214, 247), 0.06, MID)
    strong = over((186, 214, 247), 0.14, MID)
    field = over((199, 211, 234), 0.06, MID)
    # a tinted fill sits on a card, which sits on the page
    ember_fill = over(EMBER_B, 0.14, card)
    teal_fill = over(TEAL_B, 0.16, card)
    soft = over((199, 211, 234), 0.12, card)
    snack_base = hexrgb("0B0D1A")
    snack_alert = over(EMBER_B, 0.14, snack_base)
    snack_warn = snack_alert
    ghost_btn = over(FROST, 0.06, MID)
    hl_btn = over(FROST, 0.12, MID)
    violet_disabled = over(VIOLET, 0.5, MID)
    rows = [
        # name, fg, bg, large/UI threshold?
        ("Headline ice on midnight (page title)", ICE, MID, False),
        ("Body frost (ink2) on midnight", FROSTT, MID, False),
        ("Muted mist (ink3) on midnight", MIST, MID, False),
        ("Helper fog (ink4) on midnight", FOG, MID, False),
        ("Body frost on card top (5.5 %)", FROSTT, card_top, False),
        ("Muted mist on card (3 %)", MIST, card, False),
        ("Helper fog on card (3 %)", FOG, card, False),
        ("Helper fog on card top (5.5 %, panel title row)", FOG, card_top, False),
        ("Helper fog on dialog (deep)", FOG, deep, False),
        ("Violet button, white text 14 px/500", WHITE, VIOLET, False),
        ("Violet button hover #7A55F5, white text", WHITE, hexrgb("7A55F5"), False),
        ("Violet button disabled (50 %), white70 text", over(WHITE, 0.7, violet_disabled), violet_disabled, False),
        ("Ghost button white text on frost 6 %", WHITE, ghost_btn, False),
        ("Ghost button disabled (fog) on frost 6 %", FOG, ghost_btn, False),
        ("Link / blueprint #B6D9FC on midnight", BLUEPRINT, MID, False),
        ("Snackbar action (link) on snackbar base", BLUEPRINT, snack_base, False),
        ("Ember status text #F08A6D on midnight", EMBER_T, MID, False),
        ("Ember text on ember tint (Over budget tag, on card)", EMBER_T, ember_fill, False),
        ("Ember text on snackbar alert fill", EMBER_T, snack_alert, False),
        ("Teal status text #3FBFA8 on midnight", TEAL_T, MID, False),
        ("Teal text on teal tint (Within budget tag, on card)", TEAL_T, teal_fill, False),
        ("Tag cobalt (ink2 on 12 % mist, on card)", FROSTT, soft, False),
        ("Tag purple (blueprint on 12 % mist)", BLUEPRINT, soft, False),
        ("Tag plain (mist on surface2)", MIST, surface2, False),
        ("Placeholder rgba(199,211,234,.6) on field fill", over((199, 211, 234), 0.6, field), field, False),
        ("Input text white on field fill", WHITE, field, False),
        ("Read-only field text fog on frost 3 %", FOG, over(FROST, 0.03, MID), False),
        ("Money prefix fog on field", FOG, field, False),
        ("Error text ember #F08A6D on dialog (deep)", EMBER_T, deep, False),
        ("Bottom nav inactive label fog 11 px on deep pill", FOG, deep, False),
        ("Bottom nav active label white on strong", WHITE, strong, False),
        ("Top nav inactive mist on frost 5 % pill", MIST, over(FROST, 0.05, MID), False),
        ("Eyebrow mist 12.5 px mono on midnight", MIST, MID, False),
        ("Stat label fog on card", FOG, card, False),
        ("Stat value ember 30 px on card (large)", EMBER_T, card, True),
        ("Ring percentage ice on midnight (large)", ICE, MID, True),
        ("Landing foot text fog 13 px on midnight", FOG, MID, False),
        # non-text UI components, need 3:1
        ("UI: hairline rgba(186,215,247,.12) on midnight (card edge)", over(FROST, 0.12, MID), MID, True),
        ("UI: stronger edge line2 .24 on midnight (focused field/ghost btn edge)", over(FROST, 0.24, MID), MID, True),
        ("UI: input border .12 on field fill (resting input edge)", over(FROST, 0.12, field), field, True),
        ("UI: input border focused .24 on field", over(FROST, 0.24, field), field, True),
        ("UI: bar track rgba(199,211,234,.12) on card", over((199, 211, 234), 0.12, card), card, True),
        ("UI: bar fill link on track", BLUEPRINT, over((199, 211, 234), 0.12, card), True),
        ("UI: bar fill ember on track", EMBER_T, over((199, 211, 234), 0.12, card), True),
        ("UI: inactive nav icon fog on pill", FOG, deep, True),
        ("UI: violet button edge vs midnight", VIOLET, MID, True),
        ("UI: ghost button fill 6 % vs midnight (button shape)", ghost_btn, MID, True),
        ("UI: ghost button edge .12 on its fill", over(FROST, 0.12, ghost_btn), ghost_btn, True),
        ("UI: selected tab fill strong vs pill", strong, over(FROST, 0.05, MID), True),
        ("UI: chart bar iceDeep70 on card", over(hexrgb("98C0EF"), 0.7, card), card, True),
        ("UI: chart empty-day bar (track) on card", over((199, 211, 234), 0.12, card), card, True),
        ("UI: grid lines on midnight (decorative)", over(FROST, 0.06, MID), MID, True),
    ]
    table = []
    for name, fg, bg, big in rows:
        r = ratio(fg, bg)
        need = 3.0 if big else 4.5
        table.append((name, "#%02X%02X%02X" % fg, "#%02X%02X%02X" % bg, round(r, 2), need, "PASS" if r >= need else "FAIL"))
    print(f"{'pairing':74} {'fg':8} {'bg':8} {'ratio':>6} {'need':>4}")
    for t in table:
        print(f"{t[0]:74} {t[1]:8} {t[2]:8} {t[3]:6.2f} {t[4]:4}  {t[5]}")
    note("contrast", "table", table)
    note("contrast", "failures", [t[0] + f" ({t[3]})" for t in table if t[5] == "FAIL"])


# =============================================================== STAGE: matrix


def stage_matrix():
    folder_root = out("matrix")
    with sync_playwright() as p:
        for (w, h) in SIZES:
            tag = f"{w}x{h}"
            folder = out("matrix", tag)
            scale = 2 if w <= 420 or (w, h) == (844, 390) else 1
            problems = {}
            print(f"--- {tag} (scale {scale})", flush=True)
            try:
                matrix_one(p, w, h, scale, folder, problems)
            except Exception as e:  # keep going: one broken size must not hide the others
                problems["EXCEPTION"] = repr(e)[:300]
                print("matrix error", tag, repr(e)[:300], flush=True)
            note("matrix", tag, problems)
            files = sorted(os.listdir(folder))
            # contact sheets: a few screens per image so they can be reviewed
            def pick(*prefixes):
                return [os.path.join(folder, f) for f in files if any(f.startswith(x) for x in prefixes)]
            groups = {
                "A-public": pick("landing-", "login", "register"),
                "B-sections": pick("dash-", "expenses-", "budgets-", "recurring-", "goals-"),
                "C-dialogs": pick("dlg-", "snack"),
                "D-empty": pick("empty-"),
            }
            for gname, fl in groups.items():
                if gname == "A-public":
                    fl = [f for f in fl if "-" in os.path.basename(f)]
                for n in range(0, len(fl), 4):  # four screens per sheet keeps each one legible
                    sheet(fl[n:n + 4], os.path.join(folder, f"_sheet-{gname}-{n // 4}.png"), max_w=2400)
    save_results()


def matrix_one(p, w, h, scale, folder, problems):
    # ---------- public pages
    browser, ctx, app, errors = launch(p, w, h, scale)
    # the whole landing page in one frame: a tall viewport, then cropped to the content
    app.pg.set_viewport_size({"width": w, "height": 5200})
    app.pg.wait_for_timeout(1500)
    last = max((s["y"] + s["h"] for s in sem(app) if s["h"] < 400 and s["w"] > 0 and s["text"]), default=h)
    path = shot(app, os.path.join(folder, "landing-full.png"), wait=900)
    from PIL import Image
    im = Image.open(path)
    im.crop((0, 0, im.width, min(im.height, int((last + 60) * scale)))).save(path)
    problems["landing_content_height"] = round(last)
    app.pg.set_viewport_size({"width": w, "height": h})
    app.pg.wait_for_timeout(1200)
    shot(app, os.path.join(folder, "landing-top.png"))
    problems["landing_overflow"] = overflow_report(app, w, h)
    app.button("Log in")
    app.wait(800)
    shot(app, os.path.join(folder, "login.png"))
    problems["login_overflow"] = overflow_report(app, w, h)
    app.button("Log in", last=True)  # empty submit: inline errors
    app.wait(500)
    shot(app, os.path.join(folder, "login-errors.png"))
    app.button("Create an account")
    app.wait(500)
    shot(app, os.path.join(folder, "register.png"))
    problems["register_overflow"] = overflow_report(app, w, h)
    browser.close()

    # ---------- populated account (own copy: this run mutates it)
    name, token = demo_user("ad")
    browser, ctx, app, errors = launch(p, w, h, scale, token=token)
    app.wait(2500)
    wide = w >= 760
    for label, tab in (("dash", "Dashboard"), ("expenses", "Expenses"), ("budgets", "Budgets"),
                       ("recurring", "Recurring"), ("goals", "Goals")):
        if label != "dash":
            app.tab(tab)
            app.wait(700)
        files = scroll_series(app, label, folder, w, h, max_steps=8 if w < 800 else 3)
        ov = overflow_report(app, w, h)
        if ov:
            problems[f"{label}_overflow"] = ov
    # dialogs and snackbar
    app.tab("Dashboard")
    app.button("Balance settings")
    app.wait(500)
    shot(app, os.path.join(folder, "dlg-balance.png"))
    problems["dlg_balance_overflow"] = overflow_report(app, w, h)
    app.cancel()
    app.button("Add expense")
    app.wait(500)
    shot(app, os.path.join(folder, "dlg-add-expense.png"))
    problems["dlg_add_overflow"] = overflow_report(app, w, h)
    app.fill("Amount", "100")
    app.fill("Category", "Food")
    app.save()
    app.wait(500)
    shot(app, os.path.join(folder, "snack-alert.png"), wait=300)
    app.wait(6500)
    app.tab("Goals")
    app.wait(600)
    app.button("Remove Laptop")
    app.wait(500)
    shot(app, os.path.join(folder, "dlg-goal-delete.png"))
    app.cancel()
    app.button("Add goal")
    app.wait(500)
    shot(app, os.path.join(folder, "dlg-goal-add.png"))
    app.cancel()
    app.tab("Recurring")
    app.button("Add template")
    app.wait(500)
    shot(app, os.path.join(folder, "dlg-template-add.png"))
    problems["dlg_template_overflow"] = overflow_report(app, w, h)
    app.cancel()
    app.tab("Budgets")
    app.button("Add budget")
    app.wait(500)
    shot(app, os.path.join(folder, "dlg-budget-add.png"))
    app.cancel()
    bad = [e for e in errors if "CORS" in e or "Failed" in e or "Uncaught" in e or "overflow" in e.lower()]
    if bad:
        problems["console"] = bad[:3]
    browser.close()

    # ---------- brand-new account: the empty state of every section
    name, token = new_user("ae")
    browser, ctx, app, errors = launch(p, w, h, scale, token=token)
    app.wait(2500)
    for label, tab in (("dash", "Dashboard"), ("expenses", "Expenses"), ("budgets", "Budgets"),
                       ("recurring", "Recurring"), ("goals", "Goals")):
        if label != "dash":
            app.tab(tab)
            app.wait(700)
        files = scroll_series(app, "empty-" + label, folder, w, h, max_steps=3)
        ov = overflow_report(app, w, h)
        if ov:
            problems[f"empty_{label}_overflow"] = ov
    browser.close()


# =============================================================== STAGE: a11y

TOUCH_JS = r"""() => Array.from(document.querySelectorAll('flt-semantics[role=button], flt-semantics[role=link], flt-semantics[role=checkbox], flt-semantics[role=textbox], input, textarea'))
  .map(e => {const r = e.getBoundingClientRect(); return {role: e.getAttribute('role') || e.tagName.toLowerCase(),
    name: ((e.getAttribute('aria-label') || e.textContent || '').trim().replace(/\s+/g, ' ')).slice(0, 40),
    x: r.x, y: r.y, w: r.width, h: r.height}}).filter(o => o.w > 0 && o.h > 0)"""

HEADINGS_JS = r"""() => Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6,[role=heading]'))
  .map(e => ({tag: e.tagName.toLowerCase(), text: (e.textContent || '').trim().slice(0, 40), y: Math.round(e.getBoundingClientRect().y)}))"""

ACTIVE_JS = r"""() => { const a = document.activeElement; if (!a) return null; const r = a.getBoundingClientRect();
  return {tag: a.tagName.toLowerCase(), role: a.getAttribute('role'), label: (a.getAttribute('aria-label') || a.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40),
          x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height)}; }"""


def tab_walk(app, n=14):
    seen = []
    for _ in range(n):
        app.pg.keyboard.press("Tab")
        app.pg.wait_for_timeout(250)
        a = app.pg.evaluate(ACTIVE_JS)
        seen.append(a)
    return seen


def stage_a11y():
    name, token = demo_user("aa")
    with sync_playwright() as p:
        # ---- touch targets on the phone layout, and everywhere
        for (w, h) in ((390, 844), (1280, 800)):
            browser, ctx, app, errors = launch(p, w, h, 1, token=token)
            app.wait(2500)
            small = {}
            for tab in ("Dashboard", "Expenses", "Budgets", "Recurring", "Goals"):
                app.tab(tab)
                app.wait(700)
                for yscroll in (0, 700, 1400):
                    app.pg.mouse.move(w / 2, h / 2)
                    app.pg.mouse.wheel(0, -9999 if yscroll == 0 else 700)
                    app.pg.wait_for_timeout(500)
                    for t in app.pg.evaluate(TOUCH_JS):
                        if t["y"] < 0 or t["y"] + t["h"] > h or t["x"] < 0 or t["x"] + t["w"] > w:
                            continue  # clipped by the viewport: its box is not its real size
                        key = f"{tab}: {t['role']} '{t['name']}'"
                        small[key] = (round(t["w"]), round(t["h"]))
            thr = 44 if w < 760 else 24
            low = {k: v for k, v in small.items() if v[0] < thr or v[1] < thr}
            under44 = {k: v for k, v in small.items() if v[0] < 44 or v[1] < 44}
            note("a11y", f"targets_{w}", {"total": len(small), f"below_{thr}": low, "below_44": len(under44),
                                         "below_44_list": under44 if w < 760 else {}})
            # dialogs
            app.tab("Dashboard")
            app.button("Add expense")
            app.wait(600)
            dlg = {f"{t['role']} '{t['name']}'": (round(t['w']), round(t['h'])) for t in app.pg.evaluate(TOUCH_JS)}
            note("a11y", f"dialog_targets_{w}", dlg)
            browser.close()

        # ---- accessibility tree, headings, live regions
        browser, ctx, app, errors = launch(p, 390, 844, 1, token=token)
        app.wait(2500)
        heads = {}
        for tab in ("Dashboard", "Expenses", "Budgets", "Recurring", "Goals"):
            app.tab(tab)
            app.wait(800)
            heads[tab] = app.pg.evaluate(HEADINGS_JS)
        note("a11y", "headings_per_page", heads)
        s = sem(app)
        note("a11y", "semantics_roles", {r or "none": sum(1 for x in s if x["role"] == r) for r in {x["role"] for x in s}})
        # unnamed controls: role=button without a name
        unnamed = app.pg.evaluate(r"""() => Array.from(document.querySelectorAll('flt-semantics[role=button]')).filter(e => !((e.getAttribute('aria-label')||e.textContent||'').trim())).length""")
        note("a11y", "buttons_without_name", unnamed)
        note("a11y", "lang_attr", app.pg.evaluate("document.documentElement.lang"))
        note("a11y", "title", app.pg.title())
        note("a11y", "meta_description", app.pg.evaluate("(document.querySelector('meta[name=description]')||{}).content"))
        note("a11y", "viewport_meta", app.pg.evaluate("(document.querySelector('meta[name=viewport]')||{}).content"))
        note("a11y", "theme_color_meta", app.pg.evaluate("(document.querySelector('meta[name=theme-color]')||{}).content"))
        note("a11y", "live_regions", app.pg.evaluate(r"""() => Array.from(document.querySelectorAll('[aria-live],[role=alert],[role=status]')).map(e => ({tag: e.tagName.toLowerCase(), live: e.getAttribute('aria-live'), role: e.getAttribute('role'), text: (e.textContent||'').trim().slice(0,60)}))"""))
        # month label live region and the snackbar announcement
        app.tab("Expenses")
        app.button("Add expense")
        app.fill("Amount", "50")
        app.fill("Category", "Food")
        app.save()
        app.wait(900)
        note("a11y", "after_alert_live_regions", app.pg.evaluate(r"""() => Array.from(document.querySelectorAll('[aria-live],[role=alert],[role=status]')).map(e => ({tag: e.tagName.toLowerCase(), live: e.getAttribute('aria-live'), role: e.getAttribute('role'), text: (e.textContent||'').trim().slice(0,90)}))"""))
        shot(app, out("a11y", "snack-390.png"), wait=200)
        app.wait(6500)
        # dialog semantics
        app.button("Add expense")
        app.wait(600)
        note("a11y", "dialog_nodes", [x for x in sem(app) if x["modal"] or x["role"] in ("dialog", "alertdialog")])
        note("a11y", "dialog_aria", app.pg.evaluate(r"""() => Array.from(document.querySelectorAll('[role=dialog],[role=alertdialog],[aria-modal]')).map(e => ({tag: e.tagName.toLowerCase(), role: e.getAttribute('role'), modal: e.getAttribute('aria-modal'), label: e.getAttribute('aria-label'), text: (e.textContent||'').trim().slice(0,60)}))"""))
        browser.close()

        # ---- keyboard: login, dashboard, dialogs (desktop size)
        browser, ctx, app, errors = launch(p, 1280, 800, 1)
        app.button("Log in")
        app.wait(900)
        walk = tab_walk(app, 8)
        note("a11y", "keyboard_login_tab_order", [(a or {}).get("label") or (a or {}).get("tag") for a in walk])
        # focus visible: focus the username input and a button
        app.pg.keyboard.press("Shift+Tab")
        for i in range(8):
            a = app.pg.evaluate(ACTIVE_JS)
            if a and a["tag"] in ("input", "textarea"):
                break
            app.pg.keyboard.press("Tab")
            app.pg.wait_for_timeout(200)
        shot(app, out("a11y", "focus-input-login.png"), park=False)
        # Enter submits?
        app.pg.keyboard.type("demo")
        app.pg.keyboard.press("Tab")
        app.pg.wait_for_timeout(250)
        app.pg.keyboard.type("wrong password")
        app.pg.keyboard.press("Enter")
        app.wait(1200)
        note("a11y", "login_enter_submits_and_shows_error", app.has("Wrong username or password", timeout=3000))
        # focus on a button (the visible one) on the login page
        app.pg.keyboard.press("Tab")
        app.pg.keyboard.press("Tab")
        app.pg.keyboard.press("Tab")
        shot(app, out("a11y", "focus-button-login.png"), park=False)
        note("a11y", "focus_after_3_more_tabs", app.pg.evaluate(ACTIVE_JS))
        browser.close()

        # ---- focus visibility the way a sighted keyboard user gets it: no accessibility layer switched on
        from PIL import Image, ImageChops
        browser, ctx, app, errors = launch(p, 1280, 800, 1, semantics=False)
        app.pg.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=60000)
        app.pg.wait_for_timeout(4000)
        base = out("a11y", "nosem-0.png")
        app.pg.screenshot(path=base)
        deltas = []
        for i in range(1, 6):
            app.pg.keyboard.press("Tab")
            app.pg.wait_for_timeout(500)
            f = out("a11y", f"nosem-{i}.png")
            app.pg.screenshot(path=f)
            a, b2 = Image.open(base).convert("RGB"), Image.open(f).convert("RGB")
            box = ImageChops.difference(a, b2).getbbox()
            mx = max(ImageChops.difference(a, b2).getextrema(), key=lambda e: e[1])[1] if box else 0
            # luminance contrast of the focused control against its own unfocused look
            if box:
                ca, cb = a.crop(box).resize((1, 1), Image.BOX).getpixel((0, 0)), b2.crop(box).resize((1, 1), Image.BOX).getpixel((0, 0))
                deltas.append((i, box, mx, round(ratio(ca, cb), 2)))
            else:
                deltas.append((i, None, 0, 1.0))
        note("a11y", "keyboard_focus_change_without_semantics (tab#, changed box, max channel delta, contrast focused/unfocused)", deltas)
        browser.close()

        browser, ctx, app, errors = launch(p, 1280, 800, 1, token=token)
        app.wait(2500)
        walk = tab_walk(app, 12)
        note("a11y", "keyboard_dashboard_tab_order", [(a or {}).get("label") or (a or {}).get("tag") for a in walk])
        shot(app, out("a11y", "focus-dashboard.png"), park=False)
        # open Add expense with the keyboard: Enter on the focused button? search it
        app.pg.keyboard.press("Escape")
        app.button("Add expense")
        app.wait(700)
        note("a11y", "dialog_initial_focus", app.pg.evaluate(ACTIVE_JS))
        trail = []
        for i in range(14):
            app.pg.keyboard.press("Tab")
            app.pg.wait_for_timeout(250)
            a = app.pg.evaluate(ACTIVE_JS)
            trail.append((a or {}).get("label") or (a or {}).get("tag"))
        note("a11y", "dialog_tab_trail_14_presses", trail)
        shot(app, out("a11y", "focus-in-dialog.png"), park=False)
        # Escape closes?
        app.pg.keyboard.press("Escape")
        app.wait(700)
        note("a11y", "escape_closes_dialog", app.gone("Add expense", timeout=1500) or not app.has("Note (optional)", timeout=1500))
        # Enter in the last field submits (amount+category set via typing)
        app.button("Add expense")
        app.fill("Amount", "12")
        app.fill("Category", "Tea")
        app.fill("Note", "keyboard only")
        app.pg.keyboard.press("Enter")
        app.wait(1500)
        note("a11y", "enter_in_note_submits_dialog_closed", app.gone("Note (optional)", timeout=3000))
        browser.close()
    save_results()


# =============================================================== STAGE: display


FRAMES_JS = r"""() => ({bg: getComputedStyle(document.body).backgroundColor, html: getComputedStyle(document.documentElement).backgroundColor,
  color_scheme: getComputedStyle(document.documentElement).colorScheme})"""


def stage_display():
    name, token = demo_user("ad2")
    from PIL import Image
    with sync_playwright() as p:
        # ---- first paint frames (no semantics click: just watch the page load)
        for scheme in ("dark", "light"):
            browser = p.chromium.launch(channel=CHANNEL, headless=True)
            ctx = browser.new_context(viewport={"width": 390, "height": 844}, color_scheme=scheme)
            page = ctx.new_page()
            frames = []
            t0 = time.time()
            page.goto(BASE_URL, wait_until="commit")
            while time.time() - t0 < 6:
                try:
                    f = out("display", f"first-paint-{scheme}-{len(frames):02d}.png")
                    page.screenshot(path=f)
                    frames.append((round(time.time() - t0, 2), f))
                except Exception:
                    pass
                page.wait_for_timeout(50)
            stats = []
            for t, f in frames:
                im = Image.open(f).convert("RGB").resize((20, 40))
                px = list(im.getdata())
                avg = tuple(sum(c[i] for c in px) // len(px) for i in range(3))
                stats.append((t, avg))
            note("display", f"first_paint_{scheme}", {"frames": len(frames),
                 "brightest_avg": max(stats, key=lambda s: sum(s[1])),
                 "timeline_every_5th": stats[::5]})
            # contact sheet of a handful of frames
            pick = [f for _, f in frames[::max(1, len(frames) // 10)]][:11]
            sheet(pick, out("display", f"first-paint-{scheme}-sheet.png"), max_w=2400)
            note("display", f"body_bg_{scheme}", page.evaluate(FRAMES_JS))
            browser.close()
        # ---- zoom equivalents
        def one(label, w, h, scale, token=token, **kw):
            browser, ctx, app, errors = launch(p, w, h, scale, token=token, **kw)
            app.wait(2500)
            res = []
            for tab in ("Dashboard", "Expenses", "Budgets"):
                app.tab(tab)
                app.wait(700)
                shot(app, out("display", f"{label}-{tab}.png"))
                res.append((tab, overflow_report(app, w, h)))
            app.button("Add expense") if False else None
            browser.close()
            return res
        note("display", "zoom200_640x400@2x", one("zoom200-640x400", 640, 400, 2))
        note("display", "zoom400_320x200@4x_dash", one("zoom400-320x200", 320, 200, 4))
        note("display", "zoom200_phone_195x422@2x", one("zoom200-phone", 195, 422, 2))
        # ---- reduced motion: sample a transition (tab switch) and the ring animation
        for rm in ("no-preference", "reduce"):
            browser, ctx, app, errors = launch(p, 390, 844, 1, token=token, reduced=rm)
            app.wait(2500)
            app.tab("Budgets")  # bars animate in
            frames = []
            for i in range(8):
                f = out("display", f"motion-{rm}-{i}.png")
                app.pg.screenshot(path=f)
                frames.append(f)
                app.pg.wait_for_timeout(90)
            sizes = [os.path.getsize(f) for f in frames]
            distinct = len({open(f, 'rb').read() for f in frames})
            note("display", f"motion_{rm}", {"distinct_frames_of_8": distinct})
            sheet(frames, out("display", f"motion-{rm}-sheet.png"), max_w=2400)
            browser.close()
        # ---- light scheme + forced colours
        for label, kw in (("scheme-light", {"scheme": "light"}), ("forced-colors", {"forced": "active"})):
            browser, ctx, app, errors = launch(p, 390, 844, 1, token=token, **kw)
            app.wait(2500)
            shot(app, out("display", f"{label}-dash.png"))
            app.tab("Expenses")
            shot(app, out("display", f"{label}-expenses.png"))
            app.button("Add expense")
            app.wait(600)
            shot(app, out("display", f"{label}-dialog.png"))
            browser.close()
        browser, ctx, app, errors = launch(p, 1280, 800, 1, forced="active")
        shot(app, out("display", "forced-colors-landing-1280.png"))
        browser.close()
    save_results()


# =============================================================== STAGE: perf


def stage_perf():
    with sync_playwright() as p:
        for label, preset in (("fast", None), ("slow3g", dict(latency=400, down=400 * 1024 / 8 * 8 / 8, up=400 * 1024 / 8))):
            browser = p.chromium.launch(channel=CHANNEL, headless=True)
            ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1)
            page = ctx.new_page()
            reqs = []
            sizes = {}
            page.on("requestfinished", lambda r: reqs.append(r))
            cdp = ctx.new_cdp_session(page)
            cdp.send("Network.enable")
            cdp.send("Network.setCacheDisabled", {"cacheDisabled": True})
            if preset:
                # "Slow 3G" from Chrome DevTools: 400 kbit/s down, 400 ms RTT
                cdp.send("Network.emulateNetworkConditions", {"offline": False, "latency": 400,
                         "downloadThroughput": 400 * 1000 / 8, "uploadThroughput": 400 * 1000 / 8})
            enc = {}
            cdp.on("Network.loadingFinished", lambda e: enc.__setitem__(e["requestId"], e["encodedDataLength"]))
            urls = {}
            cdp.on("Network.responseReceived", lambda e: urls.__setitem__(e["requestId"], (e["response"]["url"], e["type"], e["response"].get("headers", {}).get("content-encoding"))))
            t0 = time.time()
            page.goto(BASE_URL, wait_until="commit")
            timeline = []
            tti = None
            frames = []
            limit = 150 if preset else 30
            while time.time() - t0 < limit:
                t = time.time() - t0
                try:
                    has_sem = page.evaluate("!!document.querySelector('flt-semantics-placeholder')")
                    glass = page.evaluate("!!document.querySelector('flutter-view, flt-glass-pane')")
                    f = out("perf", f"{label}-{len(frames):03d}.png")
                    if len(frames) < 60 or int(t) % 5 == 0:
                        page.screenshot(path=f)
                        frames.append((round(t, 1), f))
                    timeline.append((round(t, 1), glass, has_sem))
                    if has_sem and tti is None:
                        tti = round(t, 1)
                        page.wait_for_timeout(2500 if preset else 1500)
                        f = out("perf", f"{label}-ready.png")
                        page.screenshot(path=f)
                        break
                except Exception:
                    pass
                page.wait_for_timeout(500 if preset else 150)
            total = {}
            for rid, (u, typ, ce) in urls.items():
                total[u.replace(BASE_URL, "/")] = (enc.get(rid, 0), ce)
            big = sorted(total.items(), key=lambda kv: -kv[1][0])[:10]
            note("perf", f"{label}_time_to_ready_s", tti)
            note("perf", f"{label}_total_transfer_kB", round(sum(v[0] for v in total.values()) / 1024))
            note("perf", f"{label}_largest_requests", [(k, round(v[0] / 1024), v[1]) for k, v in big])
            note("perf", f"{label}_request_count", len(total))
            note("perf", f"{label}_hosts", sorted({u.split('/')[2] for u in (x[0] for x in urls.values()) if u.startswith('http')}))
            pick = [f for _, f in frames[:: max(1, len(frames) // 10)]][:11]
            sheet(pick, out("perf", f"{label}-sheet.png"), max_w=2400)
            note("perf", f"{label}_frame_times", [t for t, _ in frames[:: max(1, len(frames) // 10)]][:11])
            browser.close()
    save_results()


# =============================================================== STAGE: ux


def stage_ux():
    """Long lists, extreme values, month boundary, date picker, timings of the main flows."""
    today = datetime.date.today()
    # ---- a user with 300 expenses this month, 12 budgets
    big, tbig = new_user("big")
    cats = ["Food", "Transport", "Rent", "Fun", "Shopping", "Bills", "Health", "Groceries", "Coffee", "Gym", "Books", "Travel"]
    api("PUT", "/account", {"opening_balance": 500000, "low_balance_threshold": 10000}, tbig)
    for i, c in enumerate(cats):
        api("PUT", "/budgets", {"category": c, "month": today.strftime("%Y-%m"), "cap": 2000 + 500 * i}, tbig)
    for i in range(300):
        d = today.replace(day=1 + i % max(1, today.day))
        api("POST", "/expenses", {"amount": 25 + (i * 37) % 900, "date": d.isoformat(), "category": cats[i % len(cats)],
                                  "note": f"Item number {i + 1}" + (" with a rather long note that goes on and on to see how it truncates" if i % 17 == 0 else "")}, tbig)
    # ---- many goals / templates / budgets; extreme values
    many, tmany = new_user("many")
    for i in range(24):
        g = api("POST", "/goals", {"name": f"Goal {i + 1} " + ("with a really long name that wraps over lines " if i % 5 == 0 else "x"), "target": 5000 * (i + 1)}, tmany)
        if i % 3 == 0:
            api("POST", f"/goals/{g['id']}/contribute", {"amount": 1000 * (i + 1)}, tmany)
    for i in range(18):
        api("POST", "/recurring", {"amount": 100 * (i + 1), "category": f"Subscription {i + 1}", "note": "monthly", "day_of_month": 1 + i}, tmany)
    api("PUT", "/account", {"opening_balance": 1000000, "low_balance_threshold": 0}, tmany)
    for i in range(22):
        api("PUT", "/budgets", {"category": f"Category number {i + 1}", "month": today.strftime("%Y-%m"), "cap": 1000 * (i + 1)}, tmany)
        api("POST", "/expenses", {"amount": 300 * (i + 1), "date": today.isoformat(), "category": f"Category number {i + 1}", "note": ""}, tmany)
    ext, text = new_user("ext")
    api("PUT", "/account", {"opening_balance": 1234567.5, "low_balance_threshold": 99999999}, text)
    api("POST", "/expenses", {"amount": 98765432123.45, "date": today.isoformat(), "category": "Mansion " + "of the very long category name " * 3, "note": "N " * 80}, text)
    api("POST", "/expenses", {"amount": 0.01, "date": today.isoformat(), "category": "Tiny", "note": ""}, text)
    api("POST", "/expenses", {"amount": 100000, "date": today.isoformat(), "category": "Lakh", "note": "exactly one lakh"}, text)
    api("POST", "/expenses", {"amount": 10000000, "date": today.isoformat(), "category": "Crore", "note": "exactly one crore"}, text)
    api("PUT", "/budgets", {"category": "Crore", "month": today.strftime("%Y-%m"), "cap": 0}, text)
    api("POST", "/goals", {"name": "A" * 60, "target": 123456789012}, text)

    with sync_playwright() as p:
        for who, tok in (("big", tbig), ("many", tmany), ("ext", text)):
            for (w, h) in ((390, 844), (1280, 800)):
                browser, ctx, app, errors = launch(p, w, h, 1, token=tok)
                app.wait(2500)
                for tab in ("Dashboard", "Expenses", "Budgets", "Recurring", "Goals"):
                    t0 = time.time()
                    app.tab(tab)
                    app.wait(900)
                    ft = time.time() - t0
                    folder = out("ux", f"{who}-{w}")
                    files = scroll_series(app, tab.lower(), folder, w, h, max_steps=3)
                    sheet(files, os.path.join(folder, f"_{tab.lower()}.png"), max_w=2200)
                browser.close()
        # scroll the 300-row list: frame pacing via rAF while wheel-scrolling
        browser, ctx, app, errors = launch(p, 1280, 800, 1, token=tbig)
        app.wait(2500)
        t0 = time.time()
        app.tab("Expenses")
        app.pg.wait_for_timeout(500)
        app.pg.evaluate("""() => { window.__f = []; let last = performance.now(); const loop = (t) => { window.__f.push(t - last); last = t; requestAnimationFrame(loop); }; requestAnimationFrame(loop); }""")
        for i in range(30):
            app.pg.mouse.move(640, 500)
            app.pg.mouse.wheel(0, 400)
            app.pg.wait_for_timeout(60)
        app.pg.wait_for_timeout(500)
        fr = app.pg.evaluate("window.__f")
        fr = sorted(fr[5:])
        note("ux", "scroll_300_rows_frame_ms", {"n": len(fr), "median": round(fr[len(fr) // 2], 1), "p95": round(fr[int(len(fr) * .95)], 1), "max": round(fr[-1], 1)})
        shot(app, out("ux", "expenses-big-scrolled.png"))
        app.pg.mouse.wheel(0, 200000)
        app.pg.wait_for_timeout(1200)
        shot(app, out("ux", "expenses-big-bottom.png"))
        # DOM weight and memory
        note("ux", "dom_nodes_big_list", app.pg.evaluate("document.querySelectorAll('*').length"))
        browser.close()

        # ---- date picker and the month boundary, on the demo account
        name, token = demo_user("ax")
        browser, ctx, app, errors = launch(p, 1280, 800, 1, token=token)
        app.wait(2500)
        app.tab("Expenses")
        app.button("Add expense")
        app.wait(600)
        shot(app, out("ux", "dlg-add-1280.png"))
        app.press(r"^Date,")
        app.wait(900)
        shot(app, out("ux", "datepicker-1280.png"))
        note("ux", "datepicker_buttons", app.pg.evaluate(r"""() => Array.from(document.querySelectorAll('flt-semantics[role=button]')).map(e => (e.getAttribute('aria-label')||e.textContent||'').trim().replace(/\s+/g,' ').slice(0,30))"""))
        app.pg.keyboard.press("Escape")
        app.wait(500)
        browser.close()
        browser, ctx, app, errors = launch(p, 390, 844, 2, token=token)
        app.wait(2500)
        app.tab("Expenses")
        app.button("Add expense")
        app.wait(600)
        app.press(r"^Date,")
        app.wait(900)
        shot(app, out("ux", "datepicker-390.png"))
        app.pg.keyboard.press("Escape")
        app.wait(500)
        app.cancel()
        # month switcher: previous month, and next month beyond the present
        app.tab("Dashboard")
        app.month_prev()
        app.wait(1200)
        shot(app, out("ux", "prev-month-dash-390.png"))
        app.tab("Expenses")
        shot(app, out("ux", "prev-month-expenses-390.png"))
        app.tab("Budgets")
        shot(app, out("ux", "prev-month-budgets-390.png"))
        app.tab("Recurring")
        shot(app, out("ux", "prev-month-recurring-390.png"))
        for i in range(14):
            app.month_next()
        app.wait(900)
        shot(app, out("ux", "next-months-390.png"))
        note("ux", "month_after_14_next", app.has("2027", timeout=500))
        # reload keeps tab/month? URL stays?
        note("ux", "url_after_navigation", app.pg.url)
        app.reload()
        app.wait(1200)
        note("ux", "after_reload_shows", [t for t in ("Dashboard", "Expenses", "Recurring") if app.has(t, timeout=500)])
        shot(app, out("ux", "after-reload-390.png"))
        app.pg.go_back()
        app.pg.wait_for_timeout(1500)
        note("ux", "after_browser_back_url", app.pg.url)
        browser.close()
    save_results()


STAGES = {"contrast": stage_contrast, "matrix": stage_matrix, "a11y": stage_a11y,
          "display": stage_display, "perf": stage_perf, "ux": stage_ux}

if __name__ == "__main__":
    want = sys.argv[1:] or ["all"]
    if "all" in want:
        want = list(STAGES)
    os.makedirs(OUT, exist_ok=True)
    for s in want:
        print(f"===== stage {s}", flush=True)
        STAGES[s]()
        save_results()
    print("done; output in", OUT)
