#!/usr/bin/env python3
"""Build Resources/Corpus/plan_chunks.jsonl from out/pdf/<slug>.txt.

One record per passage of a hub's Community Response Plan, tagged with the hub
slug so retrieval can be scoped to a single hub (architecture.md §9 — extract
facts into tables, retrieve prose; never let one hub's plan answer for another).
"""
import csv, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF_DIR = os.path.join(ROOT, "out", "pdf")
HUBS_CSV = os.path.join(ROOT, "HubNode", "HubNode", "Resources", "Corpus", "hubs.csv")
OUT = os.path.join(ROOT, "HubNode", "HubNode", "Resources", "Corpus", "plan_chunks.jsonl")

SECTIONS = [
    "Facility map",
    "Coordinate with neighbouring Community Emergency Hubs",
    "Community Response Plan and Emergency Hub Guide",
    "Responding as a community",
    "Places and spaces",
    "Infrastructure",
    "Services in the community",
    "Groups and networks of people",
    "Medical assistance",
    "Your Local Council",
]
SECTION_LOOKUP = {s.lower(): s for s in SECTIONS}

DROP = re.compile(r"^(page\s+\d+\s+of\s+\d+|\d+|MAP KEY)\s*$", re.I)
TARGET = 700
MAX_CHUNKS_PER_HUB = 60


def clean_lines(raw):
    out = []
    for line in raw.splitlines():
        s = " ".join(line.split())
        if not s or DROP.match(s):
            continue
        out.append(s)
    return out


def chunk(slug, name, reviewed_on, raw):
    section = "Community Response Plan"
    buf, chunks, part = [], [], 0
    def flush():
        nonlocal buf, part
        text = " ".join(buf).strip()
        buf = []
        if len(text) < 40:
            return
        chunks.append({
            "hub_id": slug,
            "section": section,
            "part": part,
            "text": text,
            "source_ref": f"{name} Community Response Plan"
                          + (f" (reviewed {reviewed_on})" if reviewed_on else ""),
            "reviewed_on": reviewed_on,
        })
        part += 1

    for line in clean_lines(raw):
        heading = SECTION_LOOKUP.get(line.lower())
        # Plans use question-style subheadings ("Where are the nearest medical
        # providers?"). They make the best section labels because a volunteer's
        # question often matches one almost word for word.
        if heading is None and line.endswith("?") and len(line) <= 70:
            heading = line
        if heading:
            flush()
            section = heading
            continue
        buf.append(line)
        if sum(len(x) + 1 for x in buf) >= TARGET:
            flush()
    flush()
    return chunks[:MAX_CHUNKS_PER_HUB]


def main():
    hubs = {h["slug"]: h for h in csv.DictReader(open(HUBS_CSV))}
    written = 0
    hubs_with_plan = 0
    with open(OUT, "w") as fh:
        for slug in sorted(hubs):
            path = os.path.join(PDF_DIR, slug + ".txt")
            if not os.path.exists(path):
                continue
            hub = hubs[slug]
            raw = open(path, errors="replace").read()
            rows = chunk(slug, hub["name"], hub["crp_reviewed_on"].strip(), raw)
            if not rows:
                continue
            hubs_with_plan += 1
            for r in rows:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")
                written += 1
    print(f"hubs with plan prose: {hubs_with_plan} / {len(hubs)}")
    print(f"chunks: {written}")
    print(f"bytes: {os.path.getsize(OUT)}")


if __name__ == "__main__":
    main()
