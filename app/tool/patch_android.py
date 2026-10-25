"""Patch the generated Android manifest so release builds can reach the API.

`flutter create` only adds the INTERNET permission to the debug manifest, so a
release APK cannot make network calls. Run this once after `flutter create .`:

    python tool/patch_android.py               # add INTERNET permission
    python tool/patch_android.py --cleartext   # also allow plain http:// APIs

Safe to run repeatedly. Use --cleartext only for a local http:// backend
(for example the emulator's http://10.0.2.2:8000); an https:// API does not
need it.
"""
import pathlib
import sys

manifest = pathlib.Path(__file__).resolve().parent.parent / "android/app/src/main/AndroidManifest.xml"
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

if changed:
    manifest.write_text(text, encoding="utf-8")
    print("patched:", ", ".join(changed))
else:
    print("nothing to change")
