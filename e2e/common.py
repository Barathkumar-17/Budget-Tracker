"""Shared helpers for driving the Flutter web app in a real browser.

Flutter draws to a canvas, so we switch on its accessibility layer and read
text from aria-labels. Taps on unlabeled widgets (tabs, FAB) use coordinates
for a 480x900 viewport.
"""
import os
import re
import time

from playwright.sync_api import sync_playwright

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8123/")
SHOTS = os.environ.get("SHOTS", "e2e-shots")
CHANNEL = os.environ.get("BROWSER_CHANNEL") or None  # e.g. "chrome" locally
SLOW = float(os.environ.get("SLOW", "1"))  # multiply waits on slow machines

TAB_X = {"Dashboard": 48, "Expenses": 144, "Budgets": 240, "Recurring": 336, "Goals": 432}

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

BUTTONS_JS = """() => Array.from(document.querySelectorAll('flt-semantics[role=button]')).map(e => {
  const r = e.getBoundingClientRect();
  return {x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height};
})"""


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
        self.wait(5500)  # SnackBar lasts 4s; it also covers the FAB

    def shot(self, name):
        self.pg.screenshot(path=os.path.join(SHOTS, name))

    # ---- actions ----
    def tab(self, name):
        self.pg.mouse.click(TAB_X[name], 850)
        self.wait(1300)

    def fab(self):
        self.pg.mouse.click(436, 776)
        self.wait(900)

    def fill(self, label, value):
        f = self.pg.get_by_label(label, exact=False).first
        f.click()
        self.wait(500)  # Flutter web drops keys typed right after focus
        self.pg.keyboard.press("Control+A")
        self.pg.keyboard.press("Delete")
        if value:
            self.pg.keyboard.type(value, delay=15)

    def save(self):
        self.pg.get_by_role("button", name="Save").click()
        self.wait(1500)

    def cancel(self):
        self.pg.get_by_role("button", name="Cancel").click()
        self.wait(800)

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

    def right_buttons(self):
        """Icon buttons in the right-hand column of the list area, top to bottom."""
        bs = self.pg.evaluate(BUTTONS_JS)
        return sorted((b for b in bs if b["x"] > 400 and 80 < b["y"] < 735), key=lambda b: b["y"])

    def click_right_button(self, index):
        b = self.right_buttons()[index]
        self.pg.mouse.click(b["x"], b["y"])
        self.wait(1300)

    def swipe_left(self, needle):
        box = self.row_box(needle)
        cy = box["y"] + box["height"] / 2
        start = box["x"] + box["width"] * 0.8
        self.pg.mouse.move(start, cy)
        self.pg.mouse.down()
        for i in range(1, 11):
            self.pg.mouse.move(start - i * 40, cy)
            self.pg.wait_for_timeout(30)
        self.pg.mouse.up()
        self.wait(1500)


def open_app(playwright, base_url=BASE_URL):
    browser = playwright.chromium.launch(channel=CHANNEL, headless=True)
    page = browser.new_page(viewport={"width": 480, "height": 900})
    errors = []
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(base_url)
    page.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=90000)
    page.wait_for_timeout(2000)
    page.evaluate("document.querySelector('flt-semantics-placeholder').click()")
    page.wait_for_timeout(1500)
    return browser, App(page), errors
