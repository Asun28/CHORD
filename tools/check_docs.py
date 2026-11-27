#!/usr/bin/env python3
"""Check the design documents and product copy for four rules.

Usage: python tools/check_docs.py [--root DIR]

Rules:
  adr-010   architecture.md contains "ADR-010" (the web node runtime decision).
  dash      no product-copy file contains an em dash (U+2014) or en dash
            (U+2013), as a character or as an HTML entity (ADR-009).
  hub-count no product-copy file contains "127 hubs", including forms with up
            to three words between, such as "127 community hubs".
  plan-count no product-copy file says there are 125 plans ("125 hub
            response plans") or that every hub has a plan: 114 of the 125
            hubs have a published plan and 11 have none.

Product-copy files are the files listed in PRODUCT_COPY: the documents
T1-DESIGN-RECONCILE edited or created. Add a file here when it becomes
product copy. A listed file that is missing, unreadable or not UTF-8 fails
the check.

Exit 0 when every rule holds; exit 1 and print one line per finding,
"<path>: <rule>: <detail>", otherwise. Standard library only.
"""
import argparse
import os
import re
import sys

PRODUCT_COPY = [
    "architecture.md",
    "verified-findings.md",
    "scope-and-pitch-v4.md",
    "Wellington Design System Draft/export/hub-companion-prd-v0.3.md",
    "Wellington Design System Draft/export/what-was-built.md",
    "HubNode/README.md",
    "HubNode/FEATURES.md",
    "docs/index.html",
    "docs/CAPABILITIES.md",
    "LICENSE",
]

DASH = re.compile("[–—]|&(?:mdash|ndash);|&#(?:8211|8212|x201[34]);", re.IGNORECASE)
OLD_COUNT = re.compile(r"(?<![\d.])127(?![\d.])(?:\s+[A-Za-z-]+){0,3}\s+hubs?\b", re.IGNORECASE)
PLAN_COUNT = re.compile(
    r"(?<![\d.])125(?![\d.])(?:\s+[A-Za-z-]+){0,3}\s+plans?\b"
    r"|\bevery\s+(?:[A-Za-z-]+\s+){0,2}hubs?\b[^.;:]{0,60}?\bhas\b[^.;:]{0,40}?\bplan\b",
    re.IGNORECASE,
)


def read(root, rel, findings):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="strict") as f:
            return f.read()
    except (OSError, UnicodeDecodeError) as e:
        findings.append(f"{rel}: readable: missing or unreadable ({e.__class__.__name__})")
        return None


def check(root):
    findings = []
    texts = {rel: read(root, rel, findings) for rel in PRODUCT_COPY}
    arch = texts["architecture.md"]
    if arch is not None and "ADR-010" not in arch:
        findings.append("architecture.md: adr-010: no ADR-010 entry")
    for rel, text in texts.items():
        if text is None:
            continue
        for number, line in enumerate(text.splitlines(), 1):
            for m in DASH.finditer(line):
                findings.append(f"{rel}:{number}: dash: {m.group(0).encode('unicode_escape').decode()} at column {m.start() + 1}")
            for m in OLD_COUNT.finditer(line):
                findings.append(f"{rel}:{number}: hub-count: {m.group(0)!r} (use 125 hubs)")
            for m in PLAN_COUNT.finditer(line):
                findings.append(f"{rel}:{number}: plan-count: {m.group(0)!r} (114 of 125 hubs have a published plan)")
    return findings


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser.add_argument("--root", default=default_root, help="repository root (default: parent of tools/)")
    args = parser.parse_args(argv)
    findings = check(args.root)
    for line in findings:
        print(line)
    if findings:
        print(f"check_docs: FAIL, {len(findings)} finding(s)")
        return 1
    print(f"check_docs: OK, {len(PRODUCT_COPY)} product-copy files checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
