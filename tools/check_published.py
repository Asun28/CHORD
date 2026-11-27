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


# UTF-32 marks come first: the UTF-16LE mark is a prefix of the UTF-32LE mark.
BOMS = [
    (codecs.BOM_UTF32_LE, "utf-32"),
    (codecs.BOM_UTF32_BE, "utf-32"),
    (codecs.BOM_UTF16_LE, "utf-16"),
    (codecs.BOM_UTF16_BE, "utf-16"),
    (codecs.BOM_UTF8, "utf-8-sig"),
]


def codec_of(data):
    """The codec a byte order mark selects, else UTF-8."""
    return next((codec for bom, codec in BOMS if data.startswith(bom)), "utf-8")


def decode(data):
    """File text for the marker check; undecodable bytes are dropped."""
    return data.decode(codec_of(data), errors="ignore")


def strict_text(data):
    """File text for the CSV check, or None when the bytes do not decode or hold a NUL."""
    try:
        text = data.decode(codec_of(data))
    except UnicodeDecodeError:
        return None
    return None if "\0" in text else text


def has_restricted_row(text):
    """A row with restricted in any sensitivity column, ignoring case and surrounding space.

    The header is the first row with a non-blank cell. Raises csv.Error on a malformed file."""
    rows = csv.reader(io.StringIO(text, newline=""))
    header = next((row for row in rows if any(cell.strip() for cell in row)), [])
    columns = [i for i, name in enumerate(header) if name.strip().lower() == "sensitivity"]
    return any(i < len(row) and row[i].strip().lower() == "restricted"
               for row in rows for i in columns)


def csv_finding(path, data):
    """A finding for a CSV with a restricted row, or one this guard cannot read; None when clean."""
    text = strict_text(data)
    if text is None:
        return f"{path}: not UTF-8, UTF-16 or UTF-32 text, so its rows cannot be checked"
    try:
        restricted = has_restricted_row(text)
    except csv.Error as err:
        return f"{path}: cannot be parsed as CSV ({err}), so its rows cannot be checked"
    return f"{path}: has a row with sensitivity=restricted" if restricted else None


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
            data = fh.read()
        if path.lower().endswith(".csv"):
            finding = csv_finding(path, data)
            if finding:
                yield finding
        marker = guide_marker(decode(data))
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
