"""Give the generated web shell the app's own name, colours and icons.

`flutter create` writes web/index.html and web/manifest.json with the project
name, a placeholder description, Flutter's blue and Flutter's icons. Run this
once after `flutter create . --platforms=web` (the Dockerfile does):

    python tool/patch_web.py

Safe to run repeatedly.
"""
import json
import pathlib
import re
import shutil
import sys

APP = pathlib.Path(__file__).resolve().parent.parent
WEB = APP / "web"
BRAND = APP / "brand"
if not WEB.exists():
    sys.exit("web/ not found: run `flutter create . --project-name budget_tracker --platforms=web` first.")

NAME = "Budget Tracker"
DESCRIPTION = "Know where your money goes: expenses, monthly budgets, recurring bills and savings goals, in rupees."
MIDNIGHT = "#05060F"

# ---- index.html
html_path = WEB / "index.html"
html = html_path.read_text(encoding="utf-8")
html = re.sub(r"<title>.*?</title>", f"<title>{NAME}</title>", html)
html = re.sub(r'(<meta name="description" content=")[^"]*(")', rf"\g<1>{DESCRIPTION}\g<2>", html)
html = re.sub(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")', rf"\g<1>{NAME}\g<2>", html)
if 'name="theme-color"' not in html:
    html = html.replace(
        "<title>",
        f'<meta name="theme-color" content="{MIDNIGHT}">\n  <meta name="color-scheme" content="dark">\n  <title>',
        1,
    )
if "background:" not in html:  # no white flash while the app loads
    html = html.replace(
        "</head>",
        f"  <style>html, body {{ margin: 0; background: {MIDNIGHT}; }}</style>\n</head>",
        1,
    )
html_path.write_text(html, encoding="utf-8")

# ---- manifest.json
manifest_path = WEB / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest.update(
    name=NAME,
    short_name=NAME,
    description=DESCRIPTION,
    background_color=MIDNIGHT,
    theme_color=MIDNIGHT,
)
manifest_path.write_text(json.dumps(manifest, indent=4) + "\n", encoding="utf-8")

# ---- icons
shutil.copy(BRAND / "favicon.png", WEB / "favicon.png")
for name in ("Icon-192.png", "Icon-512.png", "Icon-maskable-192.png", "Icon-maskable-512.png"):
    shutil.copy(BRAND / name, WEB / "icons" / name)
print("patched web/index.html, web/manifest.json and the icons")
