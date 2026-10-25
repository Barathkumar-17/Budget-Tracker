"""Shared helpers for driving the Flutter web app in a real browser.

Flutter draws to a canvas, so we switch on its accessibility layer and read
text from aria-labels and the semantics DOM. Buttons are found by accessible
name; only the bottom navigation tabs are clicked by coordinates.
"""
import os
import re
import time

from playwright.sync_api import sync_playwright

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8123/")
SHOTS = os.environ.get("SHOTS", "e2e-shots")
CHANNEL = os.environ.get("BROWSER_CHANNEL") or None  # e.g. "chrome" locally
SLOW = float(os.environ.get("SLOW", "1"))  # multiply waits on slow machines
WIDTH = int(os.environ.get("VIEWPORT_W", "390"))
HEIGHT = int(os.environ.get("VIEWPORT_H", "844"))
SCHEME = os.environ.get("COLOR_SCHEME", "light")  # light | dark

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
        self.pg.mouse.move(WIDTH / 2, 8)  # park the pointer on the header: no hover tooltip or row highlight
        self.wait(700)
        self.pg.screenshot(path=os.path.join(SHOTS, name))

    # ---- actions ----
    def tab(self, name):
        x = (TABS.index(name) + 0.5) * WIDTH / len(TABS)
        self.pg.mouse.click(x, HEIGHT - 36)
        self.wait(1400)

    def button(self, name, exact=True, last=False):
        loc = self.pg.get_by_role("button", name=name, exact=exact)
        (loc.last if last else loc.first).click()
        self.wait(1000)

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

    def fab(self, label):
        self.button(label)

    def month_prev(self):
        self.button("Previous month")

    def month_next(self):
        self.button("Next month")

    def fill(self, label, value):
        f = self.pg.get_by_label(label, exact=False).first
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

    def row_box(self, needle):
        """Bounding box of the innermost semantics node containing `needle`."""
        box = self.pg.evaluate(ROW_JS, needle)
        if not box:
            raise AssertionError(f"no row containing {needle!r}")
        return box

    def tap_text(self, needle):
        bb = self.row_box(needle)
        self.pg.mouse.click(bb["x"] + bb["width"] / 2, bb["y"] + bb["height"] / 2)
        self.wait(900)

    def long_press(self, needle, hold_ms=800):
        bb = self.row_box(needle)
        self.pg.mouse.move(bb["x"] + bb["width"] / 2, bb["y"] + bb["height"] / 2)
        self.pg.mouse.down()
        self.pg.wait_for_timeout(hold_ms)
        self.pg.mouse.up()
        self.wait(1000)

    def swipe_left(self, needle):
        box = self.row_box(needle)
        cy = box["y"] + box["height"] / 2
        start = box["x"] + box["width"] * 0.8
        self.pg.mouse.move(start, cy)
        self.pg.mouse.down()
        for i in range(1, 11):
            self.pg.mouse.move(start - i * 30, cy)
            self.pg.wait_for_timeout(30)
        self.pg.mouse.up()
        self.wait(1500)


def open_app(playwright, base_url=BASE_URL, scheme=None):
    browser = playwright.chromium.launch(channel=CHANNEL, headless=True)
    ctx = browser.new_context(
        viewport={"width": WIDTH, "height": HEIGHT}, color_scheme=scheme or SCHEME, device_scale_factor=2)
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
