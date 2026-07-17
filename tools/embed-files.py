#!/usr/bin/env python3
"""Embed the repo's source files into START_HERE.html as a JSON payload.

The page is self-contained (opened via file://, so JS cannot read the repo);
this script injects every file the slide-in viewer can show between the
<script id="file-db"> tags. Re-run after editing any embedded file:

    python3 tools/embed-files.py
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, "START_HERE.html")

# What the viewer can browse: everything shippable + the tests + key docs.
INCLUDE_DIRS = ["plugins", "tests", ".claude-plugin", "docs", "tools"]
INCLUDE_FILES = ["README.md", ".gitignore"]
SKIP_NAMES = {".DS_Store"}
MAX_FILE_BYTES = 200_000  # safety net; nothing in the repo approaches this

def collect():
    db = {}
    for d in INCLUDE_DIRS:
        base = os.path.join(ROOT, d)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames if x not in SKIP_NAMES]
            for f in sorted(filenames):
                if f in SKIP_NAMES:
                    continue
                full = os.path.join(dirpath, f)
                rel = os.path.relpath(full, ROOT)
                if os.path.getsize(full) > MAX_FILE_BYTES:
                    print(f"  skip (too big): {rel}", file=sys.stderr)
                    continue
                try:
                    db[rel] = open(full, encoding="utf-8").read()
                except UnicodeDecodeError:
                    print(f"  skip (binary): {rel}", file=sys.stderr)
    for f in INCLUDE_FILES:
        full = os.path.join(ROOT, f)
        if os.path.isfile(full):
            db[f] = open(full, encoding="utf-8").read()
    return db

def main():
    db = collect()
    # </ must not terminate the script tag from inside a JSON string
    payload = json.dumps(db, ensure_ascii=False).replace("</", "<\\/")
    page = open(PAGE, encoding="utf-8").read()
    new_page, n = re.subn(
        r'(<script id="file-db" type="application/json">)(.*?)(</script>)',
        lambda m: m.group(1) + "\n" + payload + "\n" + m.group(3),
        page, count=1, flags=re.S)
    if n != 1:
        sys.exit("ERROR: file-db script tag not found in START_HERE.html")
    open(PAGE, "w", encoding="utf-8").write(new_page)

    # verify every data-file / data-dir reference on the page resolves
    refs = re.findall(r'data-file="([^"]+)"', new_page)
    dirs = re.findall(r'data-dir="([^"]+)"', new_page)
    missing = [r for r in refs if r not in db]
    bad_dirs = [d for d in dirs if d and not any(k.startswith(d.rstrip("/") + "/") for k in db)]
    if missing or bad_dirs:
        for r in missing: print(f"  UNRESOLVED data-file: {r}", file=sys.stderr)
        for d in bad_dirs: print(f"  EMPTY data-dir: {d}", file=sys.stderr)
        sys.exit(1)
    kb = len(payload) / 1024
    print(f"embedded {len(db)} files ({kb:.0f} KB payload); "
          f"{len(set(refs))} file refs + {len(set(dirs))} dir refs all resolve")

if __name__ == "__main__":
    main()
