"""Patch the generated Android project: network access, app name and icon.

`flutter create` only adds the INTERNET permission to the debug manifest, so a
release APK cannot make network calls. It also names the app "budget_tracker"
and gives it Flutter's icon. Run this once after `flutter create .`:

    python tool/patch_android.py               # add INTERNET permission
    python tool/patch_android.py --cleartext   # also allow plain http:// APIs

Safe to run repeatedly. Use --cleartext only for a local http:// backend
(for example the emulator's http://10.0.2.2:8000); an https:// API does not
need it.
"""
import pathlib
import re
import shutil
import sys

APP = pathlib.Path(__file__).resolve().parent.parent
manifest = APP / "android/app/src/main/AndroidManifest.xml"
if not manifest.exists():
    sys.exit("android/ not found: run `flutter create . --project-name budget_tracker` first.")

text = manifest.read_text(encoding="utf-8")
changed = []

perm = '<uses-permission android:name="android.permission.INTERNET"/>'
if "android.permission.INTERNET" not in text:
    text = text.replace("<application", f"{perm}\n    <application", 1)
    changed.append("INTERNET permission")

if "--cleartext" in sys.argv and "usesCleartextTraffic" not in text:
    text = text.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    changed.append("usesCleartextTraffic")

label = re.search(r'android:label="([^"]*)"', text)
if label and label.group(1) != "Budget Tracker":
    text = text.replace(label.group(0), 'android:label="Budget Tracker"', 1)
    changed.append("app name")

res = APP / "android/app/src/main/res"
icons = sorted((APP / "brand/android").glob("mipmap-*/ic_launcher.png"))
for icon in icons:
    target = res / icon.parent.name / "ic_launcher.png"
    if target.parent.exists() and target.read_bytes() != icon.read_bytes():
        shutil.copy(icon, target)
        if "launcher icon" not in changed:
            changed.append("launcher icon")

if changed:
    manifest.write_text(text, encoding="utf-8")
    print("patched:", ", ".join(changed))
else:
    print("nothing to change")
