#!/bin/bash
# Regenerate NDJSON sidecars for tracked SQLite databases.
# Called by /commit before staging. Config lives in .claude/kit.json:
#
#   "sqlite_tracking": [
#     {
#       "db": "cowork/prospecting/PROSPECTS.db",
#       "tables": ["prospects", "rejected", "contact_attempts"],
#       "exclude": ["logs_fts*"]
#     }
#   ]
#
# Each table gets a .ndjson sidecar next to the .db file, one JSON line per
# row, sorted by rowid. Views, FTS shadow tables, and sqlite_* internals are
# always skipped. The "exclude" array adds extra glob patterns to skip.

set -euo pipefail

KIT_JSON=".claude/kit.json"

if [ ! -f "$KIT_JSON" ]; then
  exit 0
fi

ENTRIES=$(jq -r '.sqlite_tracking // empty' "$KIT_JSON" 2>/dev/null)
if [ -z "$ENTRIES" ] || [ "$ENTRIES" = "null" ]; then
  exit 0
fi

COUNT=$(echo "$ENTRIES" | jq 'length')
if [ "$COUNT" -eq 0 ]; then
  exit 0
fi

CHANGED=0

for i in $(seq 0 $(( COUNT - 1 ))); do
  DB=$(echo "$ENTRIES" | jq -r ".[$i].db")
  if [ ! -f "$DB" ]; then
    echo "sqlite-sidecar: warning: $DB not found, skipping"
    continue
  fi

  DIR=$(dirname "$DB")
  TABLES_FILTER=$(echo "$ENTRIES" | jq -r ".[$i].tables // [] | .[]" 2>/dev/null)
  EXCLUDES=$(echo "$ENTRIES" | jq -r ".[$i].exclude // [] | .[]" 2>/dev/null)

  ALL_TABLES=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")

  for TABLE in $ALL_TABLES; do
    # skip if tables filter is set and this table isn't in it
    if [ -n "$TABLES_FILTER" ]; then
      if ! echo "$TABLES_FILTER" | grep -qx "$TABLE"; then
        continue
      fi
    fi

    # skip if matches an exclude pattern
    SKIP=0
    if [ -n "$EXCLUDES" ]; then
      while IFS= read -r PATTERN; do
        case "$TABLE" in
          $PATTERN) SKIP=1; break ;;
        esac
      done <<< "$EXCLUDES"
    fi
    if [ "$SKIP" -eq 1 ]; then
      continue
    fi

    SIDECAR="$DIR/$TABLE.ndjson"
    printf '.mode json\nSELECT * FROM "%s" ORDER BY rowid;\n' "$TABLE" \
      | sqlite3 "$DB" \
      | python3 -c "
import sys, json
data = sys.stdin.read().strip()
if not data:
    sys.exit(0)
rows = json.loads(data)
for row in rows:
    print(json.dumps(row, ensure_ascii=False, separators=(',', ':')))
" > "$SIDECAR.tmp" 2>/dev/null

    if [ -f "$SIDECAR" ] && cmp -s "$SIDECAR.tmp" "$SIDECAR"; then
      rm "$SIDECAR.tmp"
    else
      mv "$SIDECAR.tmp" "$SIDECAR"
      CHANGED=$(( CHANGED + 1 ))
    fi
  done
done

if [ "$CHANGED" -gt 0 ]; then
  echo "sqlite-sidecar: regenerated $CHANGED sidecar(s)"
fi
