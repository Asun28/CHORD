#!/usr/bin/env python3
"""
ingest_wremo.py — build the hub corpus for the aggregation layer.

Fetches Wellington Region Community Emergency Hub data from authoritative sources,
extracts structured facts and prose, and emits a seedable corpus plus a staleness
report (which doubles as an SDG 13.1.3 / 11.b.2 indicator for the region).

WHAT IT DOES
  1. Authoritative hub locations + coordinates from GWRC's public ArcGIS service.
  2. Community Response Plan (CRP) PDF links harvested from WREMO's six area pages
     by reading actual <a href> values — never by constructing URLs. WREMO uses two
     inconsistent asset directories, at least one filename is misspelt, and one hub
     points at another hub's PDF; constructed URLs 404 silently.
  3. Downloads each CRP, extracts text, parses review date / neighbouring hubs /
     kit contents / named facilities.
  4. The regional Hub Guide, chunked by its six sections for retrieval.
  5. Emits: corpus.json, hubs.csv, staleness.csv, guide_chunks.jsonl,
     roles.csv, task_templates.csv, seed.sql, report.md

DESIGN NOTES
  - Structured facts go to columns; prose goes to chunks. Do not embed the lot:
    "which hubs neighbour Newtown" is a query, not a similarity search.
  - Asset sensitivity FAILS CLOSED. Anything that looks like aged care, social
    housing or a medical facility is marked 'restricted' and withheld from the
    public board view. Unclassified assets are also 'restricted' pending review.
  - Nothing is silently dropped. Anything unparsed lands in report.md.
  - The eight hub roles are a documented constant, not scraped data. They are
    seeded as literals below with source references.

LICENCE / ATTRIBUTION — READ THIS
  WREMO material is © Wellington Region Emergency Management Office, all rights
  reserved. The GWRC hub dataset is CC BY-NC-ND 4.0. This script ingests for
  local use and analysis. It does NOT grant you redistribution rights. Attribute
  WREMO and GWRC visibly in any interface. Request permission: info@wremo.nz

USAGE — in a virtual environment

  # first run: create and activate the venv, then install
  python3 -m venv .venv
  source .venv/bin/activate                 # Windows: .venv\\Scripts\\activate
  pip install -r requirements.txt           # or: pip install requests beautifulsoup4 pdfplumber

  python3 ingest_wremo.py                    # writes ./corpus (gitignored)
  python3 ingest_wremo.py --limit 5          # quick smoke test
  python3 ingest_wremo.py --skip-download    # re-parse cached PDFs

  Never commit the output: tools/check_published.py fails on corpus files.

  deactivate                                # when finished

  # later runs: just reactivate
  source .venv/bin/activate && python3 ingest_wremo.py

A venv is not optional on current macOS and Debian pythons — a bare `pip install`
fails with `error: externally-managed-environment`.
"""

from __future__ import annotations

import argparse
import csv
import difflib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
from dataclasses import dataclass, field, asdict
from pathlib import Path
from urllib.parse import urljoin, urlparse

_MISSING: list[str] = []
try:
    import requests
except ImportError:
    requests = None                      # type: ignore[assignment]
    _MISSING.append("requests")
try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None                 # type: ignore[assignment]
    _MISSING.append("beautifulsoup4")

if _MISSING:
    sys.exit(
        "Missing: " + ", ".join(_MISSING) + "\n\n"
        "Activate the venv and install with the interpreter's own pip — plain `pip`\n"
        "on PATH is often a different python:\n\n"
        "    python3 -m venv .venv\n"
        "    source .venv/bin/activate\n"
        "    python3 -m pip install -r requirements.txt\n\n"
        "(On Windows: .venv\\Scripts\\activate)"
    )

# PDF text extraction: any one of three backends will do. pdfplumber gives the
# best layout fidelity, pypdf is pure python and always installs, pdftotext is
# a system binary. Resolved once at startup and reported, so a failed wheel for
# one library never blocks the run.
_PDF_BACKEND = ""
try:
    import pdfplumber
    _PDF_BACKEND = "pdfplumber"
except ImportError:
    pdfplumber = None
if not _PDF_BACKEND:
    try:
        from pypdf import PdfReader
        _PDF_BACKEND = "pypdf"
    except ImportError:
        PdfReader = None                 # type: ignore[assignment]
if not _PDF_BACKEND and shutil.which("pdftotext"):
    _PDF_BACKEND = "pdftotext"


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

UA = "WellingtonHubCorpus/0.1 (hackathon prototype; contact info@wremo.nz)"
POLITE_DELAY_S = 0.5
TIMEOUT_S = 45

# Authoritative hub locations. Public ArcGIS MapServer layer, no token required.
HUB_LOCATIONS_URL = (
    "https://mapping.gw.govt.nz/arcgis/rest/services/GW/Emergencies_P/MapServer/2/query"
    "?where=1%3D1&outFields=*&outSR=4326&f=json"
)

WREMO_BASE = "https://www.wremo.nz"
AREA_PAGES = [
    ("Wellington City", "/get-ready/community-ready/community-emergency-hubs/find-your-hub/wellington-hubs/"),
    ("Lower Hutt",      "/get-ready/community-ready/community-emergency-hubs/find-your-hub/lower-hutt/"),
    ("Upper Hutt",      "/get-ready/community-ready/community-emergency-hubs/find-your-hub/upper-hutt/"),
    ("Porirua",         "/get-ready/community-ready/community-emergency-hubs/find-your-hub/porirua/"),
    ("Kapiti",          "/get-ready/community-ready/community-emergency-hubs/find-your-hub/kapiti/"),
    ("Wairarapa",       "/get-ready/community-ready/community-emergency-hubs/find-your-hub/wairarapa/"),
]

HUB_GUIDE_PAGE = "/get-ready/community-ready/community-emergency-hubs/hub-guide/"

# The eight roles are documented and stable. Seeded, not scraped.
# priority_rank 1-4 are WREMO's designated priority roles: fill these first.
ROLES = [
    ("hub_supervisor",        "Hub Supervisor",         "Oversees all activities in the Community Emergency Hub.",   1),
    ("information_coord",     "Information Coordination","Coordinates information collection and display.",          2),
    ("public_information",    "Public Information",     "Maintains public-facing noticeboards.",                     3),
    ("reception",             "Reception",              "Greets visitors and directs them.",                         4),
    ("needs_and_offers",      "Needs and Offers",       "Matches community requests with available resources.",      5),
    ("community_space",       "Community Space",        "Provides support areas for visitors.",                      6),
    ("communications",        "Communications",         "Manages contact with the Emergency Operations Centre.",     7),
    ("facility_maintenance",  "Facility Maintenance",   "Maintains safety, cleanliness and resources.",              8),
]

# Hub Guide section headings, in document order. Used to chunk the guide.
GUIDE_SECTIONS = [
    "Accessing the hub",
    "Working as a team",
    "Setting up",
    "Before you open",
    "Your community's response",
    "Thinking about recovery",
]

# Sensitivity classification. FAIL CLOSED: default is 'restricted'.
RESTRICTED_PATTERNS = [
    # Aged and residential care. 'village' only in its aged-care senses — a bare
    # \bvillage\b wrongly withheld Grenada Village Hall, which is a hub venue.
    r"rest\s*homes?", r"resthome", r"life\s*care", r"lifecare", r"retirement",
    r"aged\s*care", r"residential\s*care", r"\bhospice\b", r"dementia", r"nursing",
    r"retirement\s+village", r"lifestyle\s+village", r"village\s+at\s+the\b",
    # Care of dependants, including all early-childhood settings. Under-fives
    # cannot self-evacuate, which is why the plans list them. Kindergartens and
    # pre-schools belong here alongside playcentres and kōhanga reo — treating
    # them differently was indefensible either way. Primary and secondary
    # schools stay public: they are hub venues and publicly known.
    r"\bday\s*care\b", r"child\s*care", r"childcare", r"respite",
    r"k[oō]hanga", r"\bcr[eè]che\b", r"\bplaycentre\b", r"\bplay\s*centre\b",
    r"\bkindergarten\b", r"\bkindy\b", r"pre[-\s]?school", r"\bearly\s*learning\b",
    r"\bmontessori\b", r"\bnursery\b",
    # Housing with a vulnerability signal. Bare \bhousing\b and \bflats\b are
    # deliberately broad: 'Marshall Court Flats, Park Rd (council housing)' was
    # published to the public board because 'council housing' matched nothing.
    r"\bhousing\b", r"\bflats\b", r"pensioner", r"people'?s\s+homes?",
    r"\bhostel\b", r"\bboarding\s*house\b",
    # Health. Bare \bmedical\b, because 'Churton Park Medical Care' and
    # 'Miramar Medical' both slipped past 'medical cent(re)'.
    r"\bmedical\b", r"health\s*cent", r"health\s*clinic", r"\bhospital\b",
    r"\bclinic\b", r"\bhospice\b", r"\bdoctors?\b", r"\bsurgery\b",
    r"\bdisab", r"mental\s*health",
    # Custodial and protective
    r"refuge", r"women'?s\s*refuge", r"\bprison\b", r"self[-\s]?care\s*unit",
    r"\bcorrections?\b",
]

# Words that carry no proper-noun information. A candidate made up only of these
# is a category label ('> Pharmacy', '> Rest homes'), not an asset, and is dropped
# rather than classified — categories inflated the first run to 3,850 entries.
CATEGORY_WORDS = {
    "school", "schools", "kura", "college", "kindergarten", "kindy", "preschool",
    "playcentre", "creche", "montessori", "nursery", "dentist", "dental",
    "church", "churches", "chapel", "marae", "mosque", "temple",
    "pharmacy", "pharmacies", "chemist", "supermarket", "supermarkets",
    "dairy", "dairies", "shop", "shops", "shopping", "retail",
    "park", "parks", "reserve", "field", "fields", "playground",
    "hall", "halls", "centre", "center", "community", "library", "libraries",
    "pool", "pools", "gym", "club", "clubs", "sports", "scout", "guides",
    "home", "homes", "house", "housing", "flats", "units", "unit",
    "tank", "tanks", "water", "tap", "taps", "rainwater", "private",
    "station", "fire", "police", "ambulance", "medical", "health", "hospital",
    "rest", "retirement", "care", "day", "doctors", "surgery", "clinic",
    "group", "groups", "staff", "students", "people", "peoples", "person",
    "other", "others", "motor", "caravans", "tents", "camp",
    "emergency", "civil", "defence", "hub", "hubs", "and", "or", "the", "of",
    "at", "in", "on", "near", "also", "eg", "etc", "local", "nearby",
}

STREET_TOKENS = (r"\b(rd|road|st|street|ave|avenue|dr|drive|cres|crescent|"
                 r"terrace|tce|lane|way|quay|parade|pde|place|grove|close|"
                 r"esplanade|highway|hwy|cnr|corner)\b")
PUBLIC_PATTERNS = [
    # Note: kindergarten / pre-school are NOT here — see RESTRICTED_PATTERNS.
    r"\bschool\b", r"\bcollege\b", r"\bkura\b",
    r"\bpark\b", r"reserve", r"\bhall\b", r"community\s*cent", r"\bmarae\b",
    r"\blibrary\b", r"\bchurch\b", r"sports\s*(club|ground)", r"\bpool\b",
    r"water\s*tank", r"emergency\s*water", r"supermarket", r"\bdairy\b",
    r"petrol", r"service\s*station", r"pharmac", r"fire\s*station",
    r"police\s*station", r"\bshops\b", r"shopping\s*cent",
]

MONTHS = {m.lower(): i for i, m in enumerate(
    ["January", "February", "March", "April", "May", "June", "July",
     "August", "September", "October", "November", "December"], start=1)}


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

@dataclass
class Asset:
    kind: str
    name: str
    sensitivity: str            # 'public' | 'restricted'
    classified_by: str          # 'pattern' | 'default_closed'


@dataclass
class Hub:
    slug: str
    name: str
    ta_name: str = ""
    address: str = ""
    lat: float | None = None
    lon: float | None = None
    crp_url: str = ""
    crp_filename: str = ""
    crp_reviewed_on: str = ""       # ISO yyyy-mm, best effort
    crp_reviewed_source: str = ""   # 'filename' | 'document' | ''
    neighbours: list[str] = field(default_factory=list)
    kit_contents: list[str] = field(default_factory=list)
    assets: list[Asset] = field(default_factory=list)
    text_chars: int = 0
    warnings: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
    return s


def norm_name(s: str) -> str:
    """Aggressive normalisation for fuzzy matching hub names across sources."""
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\b(community|emergency|hub|centre|center|school|hall|the)\b", " ", s)
    s = re.sub(r"[^a-z0-9]+", "", s)
    return s


def link_keys(filename: str, label: str) -> list[list[str]]:
    """
    Candidate match keys for a plan link, in tiers of decreasing specificity.

    Tier 0 comes from the filename, which is the cleanest signal
    ('Aro-Valley-CRP-November-2025.pdf' -> 'Aro Valley'). Tier 1 comes from the
    link label, which is noisier — several Masterton plans are labelled just
    'Masterton', and there is a 'Reponse Plan' typo upstream. Tiers are tried in
    order and the first that produces a hit wins, so a vague label can never
    steal a hub from a specific filename.

    Multi-suburb plans ('Churton-Park-and-Glenside') yield a key per suburb
    within their tier, so one plan can serve several hubs.
    """
    stem = re.sub(r"[-_](CRP|CPR)[-_].*$", "", Path(filename).stem, flags=re.I)
    stem = re.sub(r"[-_](CRP|CPR)$", "", stem, flags=re.I)
    # Territorial authority prefixes used in the Wairarapa files, e.g. MDC-Douglas-Park
    stem = re.sub(r"^(MDC|CDC|SWDC|WCC|HCC|UHCC|PCC|KCDC|GWRC)[-_]", "", stem, flags=re.I)
    lab = re.sub(r"\b(community\s+)?re?sponse\s+plan\b", "", label, flags=re.I)
    lab = re.sub(r"\b(CRP|CPR|plan)\b", "", lab, flags=re.I)

    tiers: list[list[str]] = []
    for base in (stem.replace("-", " ").replace("_", " "), lab):
        base = base.strip(" -–&,")
        tier: list[str] = []
        if base:
            for cand in [base] + re.split(r"\s*(?:&|,|/|\band\b)\s*", base):
                k = norm_name(cand)
                if len(k) >= 3 and k not in tier:
                    tier.append(k)
        tiers.append(tier)
    return tiers


def hub_keys(hub_name: str) -> list[str]:
    """
    Candidate match keys for a hub from the locations layer, which names hubs as
    'Suburb - Venue' ('Te Horo - Te Horo Community Hall'). The suburb is the part
    that corresponds to a plan; the venue is not.
    """
    out: list[str] = []
    parts = [hub_name]
    if " - " in hub_name:
        left, right = hub_name.split(" - ", 1)
        parts += [left, right]
        parts += re.split(r"\s*(?:&|,|/|\band\b)\s*", left)
    for p in parts:
        k = norm_name(p)
        if len(k) >= 3:
            out.append(k)
    seen, uniq = set(), []
    for k in out:
        if k not in seen:
            seen.add(k)
            uniq.append(k)
    return uniq


def session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": UA})
    return s


def get(sess: requests.Session, url: str, *, binary: bool = False, tries: int = 3):
    last = None
    for attempt in range(tries):
        try:
            r = sess.get(url, timeout=TIMEOUT_S)
            if r.status_code == 200:
                return r.content if binary else r.text
            last = f"HTTP {r.status_code}"
        except requests.RequestException as e:
            last = str(e)
        time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"{url} -> {last}")


def parse_date_from_filename(fn: str) -> tuple[str, str]:
    """'Newtown-CRP-November-2025.pdf' -> ('2025-11', 'filename')"""
    m = re.search(r"([A-Za-z]+)[-_\s](20\d{2})", fn)
    if m and m.group(1).lower() in MONTHS:
        return f"{m.group(2)}-{MONTHS[m.group(1).lower()]:02d}", "filename"
    m = re.search(r"(20\d{2})", fn)
    if m:
        return f"{m.group(1)}-01", "filename"
    return "", ""


def parse_date_from_text(text: str) -> tuple[str, str]:
    m = re.search(r"(?:reviewed|updated|version|date)[:\s]*([A-Za-z]+)\s+(20\d{2})",
                  text, re.I)
    if m and m.group(1).lower() in MONTHS:
        return f"{m.group(2)}-{MONTHS[m.group(1).lower()]:02d}", "document"
    return "", ""


def classify(name: str) -> tuple[str, str]:
    low = name.lower()
    for pat in RESTRICTED_PATTERNS:
        if re.search(pat, low):
            return "restricted", "pattern"
    for pat in PUBLIC_PATTERNS:
        if re.search(pat, low):
            return "public", "pattern"
    return "restricted", "default_closed"   # fail closed


def extract_text(pdf_path: Path) -> str:
    """Extract text using whichever backend is available. See _PDF_BACKEND."""
    if _PDF_BACKEND == "pdfplumber":
        out = []
        with pdfplumber.open(str(pdf_path)) as pdf:
            for page in pdf.pages:
                out.append(page.extract_text() or "")
        return "\n".join(out)

    if _PDF_BACKEND == "pypdf":
        reader = PdfReader(str(pdf_path))
        return "\n".join((p.extract_text() or "") for p in reader.pages)

    if _PDF_BACKEND == "pdftotext":
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as tmp:
            tmp_path = tmp.name
        try:
            subprocess.run(["pdftotext", "-layout", str(pdf_path), tmp_path],
                           check=True, capture_output=True, timeout=120)
            return Path(tmp_path).read_text(errors="replace")
        finally:
            Path(tmp_path).unlink(missing_ok=True)

    raise RuntimeError(
        "No PDF text extractor available. Install any one of these:\n"
        "    python3 -m pip install pdfplumber      # best layout fidelity\n"
        "    python3 -m pip install pypdf           # pure python, always installs\n"
        "    brew install poppler                   # provides pdftotext"
    )


# ---------------------------------------------------------------------------
# Extraction from CRP text
# ---------------------------------------------------------------------------

def extract_neighbours(text: str) -> list[str]:
    """CRPs name neighbouring hubs for resource coordination. Layout varies."""
    out: list[str] = []
    m = re.search(
        r"neighbou?ring\s+(?:community\s+emergency\s+)?hubs?\b(.{0,600})",
        text, re.I | re.S)
    if m:
        block = m.group(1)
        block = re.split(r"\n\s*\n", block)[0]
        for line in block.splitlines():
            line = line.strip(" •-–\t")
            if not line or len(line) < 3:
                continue
            if re.match(r"^(your|these|the|if|for|contact|when)\b", line, re.I):
                continue
            for part in re.split(r"[,;]| and ", line):
                part = part.strip(" .•-–")
                if 2 < len(part) < 60 and not part.lower().startswith("hub"):
                    out.append(part)
    seen, uniq = set(), []
    for n in out:
        k = norm_name(n)
        if k and k not in seen:
            seen.add(k)
            uniq.append(n)
    return uniq[:8]


def extract_kit(text: str) -> list[str]:
    m = re.search(r"(?:hub\s+kit|kit\s+contains?|kit\s+includes?)\b(.{0,400})",
                  text, re.I | re.S)
    if not m:
        return []
    block = re.split(r"\n\s*\n", m.group(1))[0]
    items = [p.strip(" .•-–\n\t") for p in re.split(r"[,;\n]| and ", block)]
    return [i for i in items if 2 < len(i) < 80][:15]


def clean_candidate(line: str) -> str:
    """Normalise a list line: NFKC folds ligatures ('ﬁelds' -> 'fields'), strip the
    '>' bullet these PDFs use, and drop trailing punctuation."""
    line = unicodedata.normalize("NFKC", line)
    line = re.sub(r"^[\s>•·▪◦\-–—*]+", "", line)
    line = re.sub(r"[\s,;:.]+$", "", line)
    return re.sub(r"\s{2,}", " ", line).strip()


def is_specific_place(name: str) -> bool:
    """
    True if the candidate names a particular place rather than a category.
    Evidence: a street token, a street number, or at least one capitalised word
    that isn't a generic category word.
    """
    if re.search(STREET_TOKENS, name, re.I):
        return True
    if re.search(r"\b\d{1,4}[A-Za-z]?\b", name):
        return True
    tokens = re.findall(r"[A-Za-z’']+", name)
    for t in tokens:
        if t[:1].isupper() and re.sub(r"[’']", "", t.lower()) not in CATEGORY_WORDS:
            return True
    return False


def extract_assets(text: str) -> list[Asset]:
    """
    Pull place-like lines from the list-shaped regions of a plan and classify them.

    This feeds a privacy gate, so the failure preference is asymmetric: a park
    wrongly withheld is cosmetic, an aged-care address wrongly shown is not.
    Category labels are dropped rather than classified. Everything that survives
    is written to assets.csv for human review — patterns miss, eyes don't.
    """
    seen: set[str] = set()
    assets: list[Asset] = []
    for raw in text.splitlines():
        name = clean_candidate(raw)
        if not (4 < len(name) < 90):
            continue
        words = name.split()
        if len(words) > 12:
            continue
        # Skip prose: sentences and instructions rather than place names.
        if re.match(r"^(check|make|set|ensure|assign|record|display|open|contact|"
                    r"write|place|collect|confirm|find|put|identify|tell|ask|keep|"
                    r"if|when|your|this|these|those|there|you|we|it|use|do|be|for|"
                    r"to|from|with|without|remember|note|consider)\b", name, re.I):
            continue
        caps = sum(1 for w in words if w[:1].isupper())
        if caps < max(1, len(words) // 2):
            continue

        # Sentence fragments that happen to be capitalised, e.g.
        # 'Maungaraki Community Hall if damaged', 'Churton Park Medical Care is
        # set up to move to Amesbury'.
        if re.search(r"\b(if|may be|will|would|should|is set up|are set up|can be|"
                     r"liaise|depending|unless|once)\b", name, re.I):
            continue

        water = bool(re.search(r"water\s*tanks?|emergency\s*water|water\s*tap", name, re.I))
        if not water and not is_specific_place(name):
            continue                      # category label, not an asset

        key = norm_name(name)
        if not key or key in seen:
            continue

        sens, how = classify(name)
        # Only keep assets whose type is positively identified. A candidate that
        # matches neither vocabulary is unclassifiable text, not a facility —
        # keeping those as 'restricted' produced 12,561 junk rows ('AVERT',
        # 'Amateur radio', bare street addresses) and made review impossible.
        if how == "default_closed" and not water:
            continue

        seen.add(key)
        kind = ("emergency_water" if water else
                "restricted_facility" if sens == "restricted" else "public_place")
        assets.append(Asset(kind=kind, name=name, sensitivity=sens, classified_by=how))
    return assets


# ---------------------------------------------------------------------------
# Fetch stages
# ---------------------------------------------------------------------------

def fetch_hub_locations(sess: requests.Session) -> list[dict]:
    raw = get(sess, HUB_LOCATIONS_URL)
    data = json.loads(raw)
    feats = data.get("features", [])
    out = []
    for f in feats:
        a = {k.lower(): v for k, v in (f.get("attributes") or {}).items()}
        geom = f.get("geometry") or {}
        out.append({
            "name": (a.get("name") or "").strip(),
            "ta_name": (a.get("ta_name") or "").strip(),
            "address": (a.get("address") or "").strip(),
            "suburb": (a.get("suburb") or a.get("town") or "").strip(),
            "lon": geom.get("x") if geom.get("x") is not None else a.get("x"),
            "lat": geom.get("y") if geom.get("y") is not None else a.get("y"),
        })
    return [h for h in out if h["name"]]


def harvest_crp_links(sess: requests.Session) -> list[dict]:
    """Read real hrefs from the six area pages. Never construct URLs."""
    found: list[dict] = []
    for area, path in AREA_PAGES:
        url = urljoin(WREMO_BASE, path)
        try:
            html = get(sess, url)
        except RuntimeError as e:
            print(f"  ! area page failed: {area}: {e}", file=sys.stderr)
            continue
        soup = BeautifulSoup(html, "html.parser")
        n = 0
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if not href.lower().endswith(".pdf"):
                continue
            full = urljoin(url, href)
            fn = Path(urlparse(full).path).name
            # CRPs and the odd CPR typo; exclude the regional guide itself
            if not re.search(r"(CRP|CPR)", fn, re.I):
                continue
            label = (a.get_text(" ", strip=True) or "").strip()
            name = label or re.sub(r"[-_](CRP|CPR).*$", "", fn, flags=re.I).replace("-", " ")
            found.append({"area": area, "url": full, "filename": fn, "label": name})
            n += 1
        print(f"  {area}: {n} plan link(s)")
        time.sleep(POLITE_DELAY_S)

    dedup, seen = [], set()
    for f in found:
        if f["url"] in seen:
            continue
        seen.add(f["url"])
        dedup.append(f)
    return dedup


def fetch_hub_guide(sess: requests.Session, out_dir: Path) -> tuple[str, str]:
    page_url = urljoin(WREMO_BASE, HUB_GUIDE_PAGE)
    html = get(sess, page_url)
    soup = BeautifulSoup(html, "html.parser")
    guide_url = ""
    for a in soup.find_all("a", href=True):
        if a["href"].lower().endswith(".pdf") and re.search(r"hub.?guide", a["href"], re.I):
            guide_url = urljoin(page_url, a["href"])
            break
    if not guide_url:
        return "", ""
    dest = out_dir / "pdf" / Path(urlparse(guide_url).path).name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        dest.write_bytes(get(sess, guide_url, binary=True))
    return guide_url, extract_text(dest)


def chunk_guide(text: str) -> list[dict]:
    """Split the guide on its six known section headings."""
    idx = []
    for sec in GUIDE_SECTIONS:
        m = re.search(re.escape(sec), text, re.I)
        idx.append((m.start() if m else -1, sec))
    present = sorted([p for p in idx if p[0] >= 0])
    chunks = []
    for i, (pos, sec) in enumerate(present):
        end = present[i + 1][0] if i + 1 < len(present) else len(text)
        body = text[pos:end].strip()
        for j in range(0, len(body), 1800):
            part = body[j:j + 1800]
            chunks.append({
                "section": sec,
                "part": j // 1800,
                "text": part,
                "source_ref": f"WREMO Wellington Region Hub Guide — {sec}",
            })
    missing = [s for p, s in idx if p < 0]
    if missing:
        chunks.append({"section": "_unmatched_headings", "part": 0,
                       "text": ", ".join(missing), "source_ref": "parser note"})
    return chunks


# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

def sql_str(v) -> str:
    if v is None or v == "":
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"


def write_outputs(out: Path, hubs: list[Hub], guide_url: str,
                  guide_chunks: list[dict], unmatched: list[dict],
                  loc_only: list[str]) -> None:
    out.mkdir(parents=True, exist_ok=True)

    (out / "corpus.json").write_text(json.dumps({
        "generated_from": {"hub_locations": HUB_LOCATIONS_URL,
                           "area_pages": [urljoin(WREMO_BASE, p) for _, p in AREA_PAGES],
                           "hub_guide": guide_url},
        "attribution": "Hub locations © Greater Wellington Regional Council (CC BY-NC-ND 4.0). "
                       "Hub Guide and Community Response Plans © WREMO, all rights reserved.",
        "hubs": [asdict(h) for h in hubs],
    }, indent=2))

    with (out / "hubs.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["slug", "name", "ta_name", "address", "lat", "lon",
                    "crp_url", "crp_reviewed_on", "reviewed_source",
                    "neighbours", "n_assets_public", "n_assets_restricted", "warnings"])
        for h in hubs:
            w.writerow([h.slug, h.name, h.ta_name, h.address, h.lat, h.lon,
                        h.crp_url, h.crp_reviewed_on, h.crp_reviewed_source,
                        "; ".join(h.neighbours),
                        sum(1 for a in h.assets if a.sensitivity == "public"),
                        sum(1 for a in h.assets if a.sensitivity == "restricted"),
                        "; ".join(h.warnings)])

    # Full asset list for review in a spreadsheet. Sort restricted first so the
    # privacy-relevant rows are at the top.
    with (out / "assets.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["hub", "ta_name", "kind", "asset", "sensitivity", "classified_by"])
        rows = [(h.name, h.ta_name, a.kind, a.name, a.sensitivity, a.classified_by)
                for h in hubs for a in h.assets]
        for r in sorted(rows, key=lambda x: (x[4] != "restricted", x[0], x[3])):
            w.writerow(r)

    # Staleness — this is the SDG 13.1.3 / 11.b.2 indicator for the region.
    with (out / "staleness.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["name", "ta_name", "crp_reviewed_on", "age_months", "status"])
        for h in sorted(hubs, key=lambda x: (x.crp_reviewed_on or "0000-00")):
            age, status = "", "no_plan_found"
            if h.crp_reviewed_on:
                y, m = (int(x) for x in h.crp_reviewed_on.split("-"))
                age = (2026 - y) * 12 + (8 - m)
                status = ("current" if age <= 24 else
                          "ageing" if age <= 48 else "stale")
            w.writerow([h.name, h.ta_name, h.crp_reviewed_on, age, status])

    with (out / "guide_chunks.jsonl").open("w") as f:
        for c in guide_chunks:
            f.write(json.dumps(c) + "\n")

    with (out / "roles.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["code", "name", "description", "priority_rank", "source_ref"])
        for code, name, desc, rank in ROLES:
            w.writerow([code, name, desc, rank,
                        "WREMO Hub Guide — Working as a team"])

    # Task templates: seeded from guide sections, to be reviewed by a human.
    with (out / "task_templates.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["role_code", "phase", "text", "source_ref", "needs_review"])
        for c in guide_chunks:
            if c["section"].startswith("_"):
                continue
            phase = slugify(c["section"]).replace("-", "_")
            for line in c["text"].splitlines():
                line = line.strip(" •-–\t")
                if 12 < len(line) < 160 and re.match(
                        r"^(check|make sure|set up|ensure|assign|record|display|"
                        r"open|contact|write|place|collect|confirm|find|put|"
                        r"identify|tell|ask|keep)\b", line, re.I):
                    w.writerow(["", phase, line, c["source_ref"], "yes"])

    with (out / "seed.sql").open("w") as f:
        f.write("-- Seed for the aggregation layer. See architecture.md §3.\n")
        f.write("-- Attribution: GWRC (CC BY-NC-ND 4.0); WREMO (all rights reserved).\n\n")
        f.write("BEGIN;\n\n")
        for code, name, desc, rank in ROLES:
            f.write("INSERT INTO role (code, name, description, priority_rank, source_ref) "
                    f"VALUES ({sql_str(code)}, {sql_str(name)}, {sql_str(desc)}, {rank}, "
                    f"{sql_str('WREMO Hub Guide — Working as a team')}) "
                    "ON CONFLICT (code) DO NOTHING;\n")
        f.write("\n")
        for h in hubs:
            geom = ("NULL" if h.lat is None or h.lon is None
                    else f"ST_SetSRID(ST_MakePoint({h.lon}, {h.lat}),4326)::geography")
            f.write("INSERT INTO hub (id, name, ta_name, address, geom, crp_url, "
                    "crp_reviewed_on, kit_contents) VALUES ("
                    f"{sql_str(h.slug)}, {sql_str(h.name)}, {sql_str(h.ta_name)}, "
                    f"{sql_str(h.address)}, {geom}, {sql_str(h.crp_url)}, "
                    f"{sql_str(h.crp_reviewed_on + '-01' if h.crp_reviewed_on else None)}, "
                    f"{sql_str(json.dumps(h.kit_contents))}::jsonb)"
                    " ON CONFLICT (id) DO NOTHING;\n")
        f.write("\n")
        for h in hubs:
            for a in h.assets:
                f.write("INSERT INTO hub_asset (hub_id, kind, name, sensitivity) VALUES ("
                        f"{sql_str(h.slug)}, {sql_str(a.kind)}, {sql_str(a.name)}, "
                        f"{sql_str(a.sensitivity)});\n")
        f.write("\n-- Neighbour edges resolved by name; unresolved names listed in report.md\n")
        by_key = {norm_name(h.name): h.slug for h in hubs}
        for h in hubs:
            for nb in h.neighbours:
                tgt = by_key.get(norm_name(nb))
                if tgt and tgt != h.slug:
                    f.write("INSERT INTO hub_neighbour (hub_id, neighbour_hub_id) VALUES ("
                            f"{sql_str(h.slug)}, {sql_str(tgt)}) ON CONFLICT DO NOTHING;\n")
        f.write("\nCOMMIT;\n")

    # Report
    with_plan = [h for h in hubs if h.crp_url]
    dated = [h for h in with_plan if h.crp_reviewed_on]
    def age(h):
        y, m = (int(x) for x in h.crp_reviewed_on.split("-"))
        return (2026 - y) * 12 + (8 - m)
    stale = [h for h in dated if age(h) > 48]
    ageing = [h for h in dated if 24 < age(h) <= 48]
    no_plan = [h for h in hubs if not h.crp_url]

    lines = [
        "# Ingest report", "",
        f"- Hubs from GWRC locations layer: **{len(hubs)}**",
        f"- Hubs with a published response plan: **{len(with_plan)}**",
        f"- Plans with a determinable review date: **{len(dated)}**",
        "",
        "## SDG 13.1.3 / 11.b.2 indicator — currency of local DRR strategies", "",
        f"- Current (≤24 months): **{len(dated) - len(ageing) - len(stale)}**",
        f"- Ageing (24–48 months): **{len(ageing)}**",
        f"- Stale (>48 months): **{len(stale)}**",
        f"- No plan published: **{len(no_plan)}**",
        "",
        f"**Proportion of hubs with ANY published plan: "
        f"{len(with_plan) / max(1, len(hubs)) * 100:.0f}%** ({len(with_plan)}/{len(hubs)})",
        "",
        f"**Proportion of hubs with a CURRENT plan (reviewed within 24 months): "
        f"{(len(dated) - len(ageing) - len(stale)) / max(1, len(hubs)) * 100:.0f}%** "
        f"({len(dated) - len(ageing) - len(stale)}/{len(hubs)})",
        "",
        "Quote the second figure as the SDG 13.1.3 / 11.b.2 contribution. Report both — "
        "the gap between them is the finding.",
        "",
    ]
    if stale:
        lines += ["### Stale plans (>4 years)", ""] + \
                 [f"- {h.name} — {h.crp_reviewed_on}" for h in sorted(stale, key=age, reverse=True)] + [""]
    if no_plan:
        lines += ["### Hubs with no plan found", ""] + \
                 [f"- {h.name} ({h.ta_name})" for h in no_plan] + [""]
    if unmatched:
        lines += ["### Plan links that matched no hub in the locations layer",
                  "*Fix by hand — do not construct URLs.*", ""] + \
                 [f"- `{u['filename']}` — {u['label']} ({u['area']})" for u in unmatched] + [""]
    if loc_only:
        lines += ["### Unresolved neighbour names", ""] + \
                 [f"- {n}" for n in sorted(set(loc_only))] + [""]
    warned = [h for h in hubs if h.warnings]
    if warned:
        lines += ["### Parse warnings", ""] + \
                 [f"- {h.name}: {'; '.join(h.warnings)}" for h in warned] + [""]
    # Asset review. The full list lives in assets.csv — inlining thousands of rows
    # made this report unreadable, which defeats the purpose of a review step.
    pub = [(h.name, a.name) for h in hubs for a in h.assets if a.sensitivity == "public"]
    res = [(h.name, a.name) for h in hubs for a in h.assets if a.sensitivity == "restricted"]
    closed = [(h.name, a.name) for h in hubs for a in h.assets
              if a.classified_by == "default_closed"]

    lines += [
        "## Asset review — do this before anything renders on a screen", "",
        f"- Visible on the public board: **{len(pub)}**",
        f"- Withheld to the coordinator view: **{len(res)}** "
        f"(of which **{len(closed)}** withheld only because nothing matched — "
        "check for false positives)",
        "",
        "Open **assets.csv** — restricted rows sort to the top. Two questions:",
        "",
        "1. **Is anything in `public` actually sensitive?** Aged care, social housing, "
        "a medical facility, a refuge. This is the only direction that leaks.",
        "2. **Is anything in `restricted` merely a venue?** Over-withholding costs the "
        "board usefulness, not safety.",
        "",
        "### Withheld facilities (verify these are right)", "",
    ]
    last = None
    for hub_name, asset_name in sorted(res)[:120]:
        if hub_name != last:
            lines.append(f"**{hub_name}**")
            last = hub_name
        lines.append(f"- {asset_name}")
    if len(res) > 120:
        lines.append(f"\n*…and {len(res) - 120} more — see assets.csv.*")
    lines.append("")

    lines += [
        "## Review before shipping", "",
        "1. The PUBLIC asset list above. Do this one first.",
        "2. `task_templates.csv` rows are all `needs_review=yes`. Assign role codes and delete noise.",
        "3. Assets marked `restricted` are withheld from the public board view and shown "
        "   only in the coordinator view (architecture.md §8).",
        "4. Attribute WREMO and GWRC visibly. Redistribution is not granted by either licence.",
        "",
    ]
    (out / "report.md").write_text("\n".join(lines))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="corpus",
                    help="output directory, gitignored (default: %(default)s)")
    ap.add_argument("--limit", type=int, default=0, help="only process N plans")
    ap.add_argument("--skip-download", action="store_true")
    args = ap.parse_args()

    out = Path(args.out)
    (out / "pdf").mkdir(parents=True, exist_ok=True)
    sess = session()

    if not _PDF_BACKEND:
        sys.exit(
            "No PDF text extractor available. Install any one of these:\n\n"
            "    python3 -m pip install pdfplumber      # best layout fidelity\n"
            "    python3 -m pip install pypdf           # pure python, always installs\n"
            "    brew install poppler                   # provides pdftotext\n"
        )
    print(f"PDF backend: {_PDF_BACKEND}")

    print("1/5 hub locations (GWRC ArcGIS)…")
    locs = fetch_hub_locations(sess)
    print(f"    {len(locs)} hubs")

    print("2/5 harvesting plan links from WREMO area pages…")
    links = harvest_crp_links(sess)
    print(f"    {len(links)} plan link(s) total")

    hubs: dict[str, Hub] = {}
    for l in locs:
        slug = slugify(l["name"])
        hubs[slug] = Hub(slug=slug, name=l["name"], ta_name=l["ta_name"],
                         address=", ".join(x for x in (l["address"], l["suburb"]) if x),
                         lat=l["lat"], lon=l["lon"])

    # Index hub keys -> slugs. One key may legitimately hit several hubs, and one
    # plan may cover several hubs (Churton Park & Glenside, Thorndon and Pipitea).
    key_index: dict[str, list[str]] = {}
    for slug, h in hubs.items():
        for k in hub_keys(h.name):
            key_index.setdefault(k, []).append(slug)

    def assign(slug: str, link: dict) -> None:
        h = hubs[slug]
        if not h.crp_url:
            h.crp_url, h.crp_filename = link["url"], link["filename"]

    link_key_cache = [(l, link_keys(l["filename"], l["label"])) for l in links]
    used: set[str] = set()

    # Pass 1 — exact matches, most specific tier first. Stopping at the first tier
    # that hits prevents 'Karori' stealing 'Karori West' and stops the three plans
    # labelled only 'Masterton' from claiming every Masterton hub.
    for l, tiers in link_key_cache:
        for tier in tiers:
            hit = False
            for k in tier:
                for slug in key_index.get(k, []):
                    assign(slug, l)
                    hit = True
            if hit:
                used.add(l["url"])
                break

    # Pass 2 — substring, only for hubs still without a plan, longest key first.
    for l, tiers in link_key_cache:
        if l["url"] in used:
            continue
        for tier in tiers:
            hit = False
            for k in sorted(tier, key=len, reverse=True):
                if len(k) < 5:
                    continue
                for hk, slugs in key_index.items():
                    if len(hk) < 5 or (k not in hk and hk not in k):
                        continue
                    for slug in slugs:
                        if not hubs[slug].crp_url:
                            assign(slug, l)
                            hit = True
                if hit:
                    break
            if hit:
                used.add(l["url"])
                break

    # Pass 3 — fuzzy, for upstream spelling drift ('Reikorangi' vs 'Reikiorangi').
    # Conservative threshold; anything below it stays in the report for a human.
    leftovers = [(l, t) for l, t in link_key_cache if l["url"] not in used]
    for slug, h in hubs.items():
        if h.crp_url:
            continue
        best, best_ratio, best_link = None, 0.0, None
        for hk in hub_keys(h.name):
            for l, tiers in leftovers:
                for k in (tiers[0] or tiers[1]):
                    r = difflib.SequenceMatcher(None, hk, k).ratio()
                    if r > best_ratio:
                        best, best_ratio, best_link = k, r, l
        if best_link and best_ratio >= 0.85:
            assign(slug, best_link)
            used.add(best_link["url"])
            h.warnings.append(f"plan matched fuzzily ({best_ratio:.2f}) via '{best}' "
                              "— verify this is the right plan")

    unmatched = [l for l, _ in link_key_cache if l["url"] not in used]
    matched = sum(1 for h in hubs.values() if h.crp_url)
    print(f"    matched {matched}/{len(hubs)} hubs to a plan; "
          f"{len(unmatched)} link(s) unmatched")

    todo = [h for h in hubs.values() if h.crp_url]
    if args.limit:
        todo = todo[:args.limit]

    print(f"3/5 downloading and parsing {len(todo)} plan(s)…")
    for i, h in enumerate(todo, 1):
        dest = out / "pdf" / h.crp_filename

        # The review date lives in the filename, so the staleness indicator is
        # computable without downloading a single PDF. Parse it BEFORE the file
        # gate below, or a skipped download silently destroys the indicator.
        h.crp_reviewed_on, h.crp_reviewed_source = parse_date_from_filename(h.crp_filename)

        # Extracted text is cached alongside the PDF and is the only thing the
        # parsers need. Prefer the cache when the source PDF has gone missing —
        # cloud-sync clients relocate files, and re-fetching 114 PDFs to recover
        # text we already have is wasteful and impolite to WREMO's server.
        txt_cache = out / "pdf" / (h.slug + ".txt")
        try:
            if not dest.exists() and not txt_cache.exists() and not args.skip_download:
                dest.write_bytes(get(sess, h.crp_url, binary=True))
                time.sleep(POLITE_DELAY_S)

            if dest.exists():
                text = extract_text(dest)
            elif txt_cache.exists():
                text = txt_cache.read_text(errors="replace")
                h.warnings.append("source PDF missing — used cached extracted text")
            else:
                h.warnings.append("no PDF and no cached text — review date still known "
                                  "from filename, but neighbours and assets unavailable")
                continue
            h.text_chars = len(text)
            if h.text_chars < 400:
                h.warnings.append(f"suspiciously little text ({h.text_chars} chars) "
                                  "— may be scanned, needs OCR")
            if not h.crp_reviewed_on:
                h.crp_reviewed_on, h.crp_reviewed_source = parse_date_from_text(text)
            if not h.crp_reviewed_on:
                h.warnings.append("no review date found")
            h.neighbours = extract_neighbours(text)
            if not h.neighbours:
                h.warnings.append("no neighbouring hubs parsed")
            h.kit_contents = extract_kit(text)
            h.assets = extract_assets(text)
            (out / "pdf" / (h.slug + ".txt")).write_text(text)
        except Exception as e:                       # noqa: BLE001
            h.warnings.append(f"error: {e}")
        if i % 10 == 0:
            print(f"    {i}/{len(todo)}")

    print("4/5 hub guide…")
    try:
        guide_url, guide_text = fetch_hub_guide(sess, out)
        guide_chunks = chunk_guide(guide_text) if guide_text else []
        print(f"    {len(guide_chunks)} chunk(s)")
    except Exception as e:                           # noqa: BLE001
        print(f"    ! guide failed: {e}", file=sys.stderr)
        guide_url, guide_chunks = "", []

    all_keys = {norm_name(h.name) for h in hubs.values()}
    unresolved = [nb for h in hubs.values() for nb in h.neighbours
                  if norm_name(nb) not in all_keys]

    print("5/5 writing outputs…")
    write_outputs(out, list(hubs.values()), guide_url, guide_chunks,
                  unmatched, unresolved)
    print(f"\nDone. Read {out / 'report.md'} first — the headline number is in there.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
