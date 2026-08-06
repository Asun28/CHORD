#!/usr/bin/env bash
# Design standard: no em dashes (U+2014) or en dashes (U+2013) in HubNode app text.
# See HubNode/DESIGN.md (ADR-009 in architecture.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PATTERN=$'[\u2013\u2014]'

if command -v rg >/dev/null 2>&1; then
  if rg -n --glob '*.swift' --glob '*.md' --glob '*.csv' --glob '*.json' --glob '*.jsonl' \
      -g '!scripts/*' \
      "$PATTERN" . 2>/dev/null; then
    echo ""
    echo "FAIL: em dash (U+2014) or en dash (U+2013) found."
    echo "Use full sentences or ASCII '-'."
    echo "See DESIGN.md section 1."
    exit 1
  fi
else
  # Fallback without ripgrep
  hits=$(find . \( -name '*.swift' -o -name '*.md' -o -name '*.csv' -o -name '*.json' -o -name '*.jsonl' \) \
    -not -path './scripts/*' -print0 | xargs -0 grep -n "$PATTERN" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    echo "FAIL: em/en dash found. See DESIGN.md."
    exit 1
  fi
fi

echo "OK: no em/en dashes in HubNode app text sources."
