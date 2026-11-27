#!/usr/bin/env python3
"""Fail when the repository tracks corpus-derived or restricted content.

Run from anywhere inside the repository: python tools/check_published.py
Exit 0 when clean; exit 1 and print one line per finding otherwise.

Checks every tracked file (git ls-files) for:
  - a path listed in tools/corpus-inventory.txt (an entry ending in "/"
    covers everything under that directory);
  - a CSV row whose sensitivity column is "restricted";
  - text of the WREMO Community Emergency Hub Guide (marker phrases below,
    matched with any run of whitespace between words).
A pattern check cannot prove copyrighted text is absent; a human reviews the
inventory. Real corpus builds belong in the gitignored corpus/ directory.
"""
import codecs
import csv
import io
import os
import subprocess
import sys

INVENTORY = os.path.join("tools", "corpus-inventory.txt")

# Phrases from the WREMO Hub Guide section contents pages, kept as word lists
# so this file does not match itself.
GUIDE_MARKERS = [
    ("Locate", "the", "Community", "Emergency", "Hub", "kit"),
    ("Give", "an", "overview", "of", "who", "might", "be", "available", "to", "help"),
    ("help", "each", "other", "through", "the", "recovery"),
]


def git(root, *args):
    return subprocess.run(["git", *args], cwd=root, check=True,
                          capture_output=True, text=True, encoding="utf-8").stdout


def read_inventory(root):
    with open(os.path.join(root, INVENTORY), encoding="utf-8") as fh:
        return [line.strip() for line in fh if line.strip()]


def in_inventory(path, inventory):
    return any(path == e or (e.endswith("/") and path.startswith(e)) for e in inventory)


def decode(data):
    """File text; a UTF-16 or UTF-8 byte order mark selects the codec and is dropped."""
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8-sig", errors="ignore")


def has_restricted_row(text):
    """A row whose sensitivity column reads restricted, ignoring case and surrounding space."""
    for row in csv.DictReader(io.StringIO(text)):
        for key, value in row.items():
            if (isinstance(key, str) and key.strip().lower() == "sensitivity"
                    and isinstance(value, str) and value.strip().lower() == "restricted"):
                return True
    return False


def guide_marker(text):
    words = " ".join(text.split())
    for marker in GUIDE_MARKERS:
        phrase = " ".join(marker)
        if phrase in words:
            return phrase
    return None


def findings(root):
    inventory = read_inventory(root)
    for path in git(root, "ls-files", "-z").split("\0")[:-1]:
        if in_inventory(path, inventory):
            yield f"{path}: listed in {INVENTORY}"
        with open(os.path.join(root, path), "rb") as fh:
            text = decode(fh.read())
        if path.lower().endswith(".csv") and has_restricted_row(text):
            yield f"{path}: has a row with sensitivity=restricted"
        marker = guide_marker(text)
        if marker:
            yield f"{path}: contains WREMO Hub Guide text ({marker!r})"


def main():
    root = git(os.getcwd(), "rev-parse", "--show-toplevel").strip()
    found = list(findings(root))
    for line in found:
        print(line)
    if found:
        print(f"check_published: {len(found)} finding(s)", file=sys.stderr)
        return 1
    print("check_published: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
