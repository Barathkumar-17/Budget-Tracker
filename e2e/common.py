"""Shared helpers for driving the Flutter web app in a real browser.

Flutter draws to a canvas, so we switch on its accessibility layer and read
text from aria-labels and the semantics DOM. Every control is found by its
accessible name; nothing is clicked by coordinates.
"""
import os
import re
import time

from playwright.sync_api import sync_playwright

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8000/")
SHOTS = os.environ.get("SHOTS", "e2e-shots")
CHANNEL = os.environ.get("BROWSER_CHANNEL") or None  # e.g. "chrome" locally
SLOW = float(os.environ.get("SLOW", "1"))  # multiply waits on slow machines
WIDTH = int(os.environ.get("VIEWPORT_W", "390"))
HEIGHT = int(os.environ.get("VIEWPORT_H", "844"))
SCHEME = os.environ.get("COLOR_SCHEME", "dark")  # the browser preference; the app is dark only

TABS = ["Dashboard", "Expenses", "Budgets", "Recurring", "Goals"]

ALL_TEXT_JS = r"""() => {
  const labels = Array.from(document.querySelectorAll('[aria-label]')).map(e => e.getAttribute('aria-label'));
  return document.body.innerText + '\n' + labels.join('\n');
}"""

ROW_JS = r"""(needle) => {
  const hits = Array.from(document.querySelectorAll('flt-semantics, h2')).map(e => {
    const r = e.getBoundingClientRect();
    const t = (e.getAttribute('aria-label') || '') + ' ' + (e.textContent || '');
    return {t, x: r.x, y: r.y, width: r.width, height: r.height};
  }).filter(o => o.t.includes(needle) && o.width > 100 && o.height < 200 && o.height > 0);
  hits.sort((a, b) => a.height - b.height);
  return hits[0] || null;
}"""


BUTTONS_JS = r"""() => Array.from(document.querySelectorAll('flt-semantics[role=button]'))
  .map(e => (e.getAttribute('aria-label') || e.textContent || '').trim().replace(/\s+/g, ' '))"""


def norm(s):
    return re.sub(r"\s+", " ", s)


class App:
    def __init__(self, page):
        self.pg = page
        os.makedirs(SHOTS, exist_ok=True)

    # ---- waiting / reading ----
    def wait(self, ms):
        self.pg.wait_for_timeout(int(ms * SLOW))

    def text(self):
        return norm(self.pg.evaluate(ALL_TEXT_JS))

    def has(self, needle, timeout=8000):
        needle = norm(needle)
        end = time.time() + timeout * SLOW / 1000
        while time.time() < end:
            if needle in self.text():
                return True
            self.pg.wait_for_timeout(250)
        return False

    def gone(self, needle, timeout=4000):
        needle = norm(needle)
        end = time.time() + timeout * SLOW / 1000
        while time.time() < end:
            if needle not in self.text():
                return True
            self.pg.wait_for_timeout(250)
        return False

    def snack_gone(self):
        self.wait(6500)  # SnackBars last 4-6s

    def shot(self, name):
        self.pg.mouse.move(WIDTH / 2, 2)  # park the pointer out of the way: no hover tooltip or row highlight
        self.wait(700)
        self.pg.screenshot(path=os.path.join(SHOTS, name))

    # ---- actions ----
    def tab(self, name):
        """Go to a section (sidebar entry on wide windows, tab on phones)."""
        self.pg.get_by_role("button", name=name, exact=True).first.click()
        self.wait(1400)

    def button(self, name, exact=True, last=False):
        # Icon buttons expose their tooltip as well, so the name can read "Log out Log out".
        pattern = rf"^{re.escape(name)}(?: {re.escape(name)})?$" if exact else re.escape(name)
        loc = self.pg.get_by_role("button", name=re.compile(pattern))
        # Flutter only exposes what is near the viewport; scroll down until the button exists.
        for _ in range(6):
            if loc.count():
                break
            self.pg.mouse.move(WIDTH / 2, HEIGHT / 2)
            self.pg.mouse.wheel(0, HEIGHT * 0.6)
            self.wait(500)
        if not loc.count():
            # The accessibility DOM can lag a button that is already on screen; a small
            # scroll back and forth makes Flutter rebuild it.
            for dy in (-80, 80, -80, 80):
                self.pg.mouse.wheel(0, dy)
                self.wait(400)
                if loc.count():
                    break
        try:
            (loc.last if last else loc.first).click(timeout=8000)
        except Exception:
            self.shot("stuck.png")  # show what was on screen when the button never appeared
            names = self.pg.evaluate(BUTTONS_JS)
            print(f"no button matching {pattern!r}; buttons present: {names}", flush=True)
            raise
        self.wait(1000)

    def reload(self):
        """Reload the page and switch the accessibility layer back on."""
        self.pg.reload()
        self.pg.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=90000)
        self.pg.wait_for_timeout(2000)
        self.pg.evaluate("document.querySelector('flt-semantics-placeholder').click()")
        self.wait(2500)

    def snack_action(self, name):
        """Press a SnackBar action. The snackbar slides in, and a click on a moving
        semantics node can miss, so let it settle first and retry if it is still there."""
        self.wait(900)
        for _ in range(3):
            self.pg.get_by_role("button", name=name, exact=True).first.click()
            self.wait(1300)
            if not self.pg.get_by_role("button", name=name, exact=True).count():
                return
        raise AssertionError(f"snackbar action {name!r} never went away")

    def month_prev(self):
        self.button("Previous month")

    def month_next(self):
        self.button("Next month")

    def fill(self, label, value, exact=False):
        f = self.pg.get_by_label(label, exact=exact).first
        f.click()
        self.wait(500)  # Flutter web drops keys typed right after focus
        self.pg.keyboard.press("Control+A")
        self.pg.keyboard.press("Delete")
        if value:
            self.pg.keyboard.type(value, delay=15)

    def save(self):
        self.button("Save")
        self.wait(500)

    def cancel(self):
        self.button("Cancel")

    def count(self, pattern):
        """How many buttons have an accessible name matching the regex."""
        return self.pg.get_by_role("button", name=re.compile(pattern)).count()

    def press(self, pattern, last=False):
        """Click the button whose accessible name matches the regex."""
        loc = self.pg.get_by_role("button", name=re.compile(pattern))
        (loc.last if last else loc.first).click()
        self.wait(1100)

    def log_in(self, username, password):
        """From the landing page: open the login form, fill it, submit."""
        self.button("Log in")
        self.fill("Username", username)
        self.fill("Password", password, exact=True)
        self.button("Log in", last=True)

    def log_out(self):
        self.button("Log out")
        self.wait(800)


def open_app(playwright, base_url=BASE_URL, scheme=None, width=None, height=None, scale=2):
    """Open the app in a fresh browser; the size defaults to $VIEWPORT_W x $VIEWPORT_H."""
    global WIDTH, HEIGHT
    WIDTH, HEIGHT = width or WIDTH, height or HEIGHT
    browser = playwright.chromium.launch(channel=CHANNEL, headless=True)
    ctx = browser.new_context(
        viewport={"width": WIDTH, "height": HEIGHT}, color_scheme=scheme or SCHEME, device_scale_factor=scale)
    page = ctx.new_page()
    errors = []
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(base_url)
    page.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=90000)
    page.wait_for_timeout(2000)
    page.evaluate("document.querySelector('flt-semantics-placeholder').click()")
    page.wait_for_timeout(1500)
    return browser, App(page), errors
