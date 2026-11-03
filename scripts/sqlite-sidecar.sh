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
# Uses the AirSQLite sidecar layout: each database gets a folder
# ({dbname}.airsqlite/) containing per-table snapshot files
# ({table}.snapshot.ndjson). One JSON line per row, sorted by rowid,
# with _rowid as an explicit column. Views, FTS shadow tables, and
# sqlite_* internals are always skipped.

set -euo pipefail

# restore <db> [schema.sql] — rebuild a MISSING database from its sidecar folder
# (a fresh clone, or a new machine). Applies the schema first when given, so
# triggers, indexes and FTS tables come back too, then inserts every snapshot
# row with its original rowid. Refuses to touch a database that already exists.
if [ "${1:-}" = "restore" ]; then
  DB="${2:?usage: sqlite-sidecar.sh restore <db> [schema.sql]}"
  SCHEMA="${3:-}"
  SIDECAR_DIR="$(dirname "$DB")/$(basename "${DB%.*}").airsqlite"
  [ -e "$DB" ] && { echo "sqlite-sidecar: $DB already exists, not restoring" >&2; exit 1; }
  [ -d "$SIDECAR_DIR" ] || { echo "sqlite-sidecar: no $SIDECAR_DIR to restore from" >&2; exit 1; }
  TMP="$DB.restoring"
  rm -f "$TMP"
  [ -n "$SCHEMA" ] && sqlite3 "$TMP" < "$SCHEMA"
  python3 - "$TMP" "$SIDECAR_DIR" <<'PY'
import glob, json, os, sqlite3, sys
db, folder = sys.argv[1], sys.argv[2]
c = sqlite3.connect(db)
c.execute("PRAGMA ignore_check_constraints = ON")   # restore the data as it was, not as today's schema would accept it
total = 0
for path in sorted(glob.glob(os.path.join(folder, "*.snapshot.ndjson"))):
    table = os.path.basename(path)[: -len(".snapshot.ndjson")]
    cols = {r[1] for r in c.execute(f'PRAGMA table_info("{table}")')}
    for line in open(path, encoding="utf-8"):
        if not line.strip():
            continue
        row = json.loads(line)
        rowid = row.pop("_rowid", None)
        if not cols:   # no schema for this table: create it from the first row
            c.execute(f'CREATE TABLE "{table}" ({", ".join(chr(34) + k + chr(34) for k in row)})')
            cols = set(row)
        row = {k: v for k, v in row.items() if k in cols}
        keys = ["rowid"] + list(row) if rowid is not None else list(row)
        vals = ([rowid] if rowid is not None else []) + list(row.values())
        c.execute(f'INSERT INTO "{table}" ({", ".join(k if k == "rowid" else chr(34) + k + chr(34) for k in keys)}) '
                  f'VALUES ({", ".join("?" for _ in keys)})', vals)
        total += 1
c.commit()
print(f"sqlite-sidecar: restored {total} row(s)")
PY
  mv "$TMP" "$DB"
  exit 0
fi

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
  BASENAME=$(basename "$DB")
  DBNAME="${BASENAME%.*}"
  SIDECAR_DIR="$DIR/$DBNAME.airsqlite"
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

    # Ensure the sidecar folder exists
    mkdir -p "$SIDECAR_DIR"

    SIDECAR="$SIDECAR_DIR/$TABLE.snapshot.ndjson"
    printf '.mode json\nSELECT rowid AS _rowid, * FROM "%s" ORDER BY rowid;\n' "$TABLE" \
      | sqlite3 "$DB" \
      | python3 -c "
import sys, json
data = sys.stdin.read().strip()
if not data:
    sys.exit(0)
rows = json.loads(data)
for row in rows:
    print(json.dumps(row, ensure_ascii=False))
" > "$SIDECAR.tmp" 2>/dev/null

    if [ -f "$SIDECAR" ] && cmp -s "$SIDECAR.tmp" "$SIDECAR"; then
      rm "$SIDECAR.tmp"
    else
      mv "$SIDECAR.tmp" "$SIDECAR"
      CHANGED=$(( CHANGED + 1 ))
    fi

    # Migrate old flat sidecar if it exists
    OLD_SIDECAR="$DIR/$TABLE.ndjson"
    if [ -f "$OLD_SIDECAR" ]; then
      rm "$OLD_SIDECAR"
      echo "sqlite-sidecar: migrated $OLD_SIDECAR → $SIDECAR"
    fi
  done
done

if [ "$CHANGED" -gt 0 ]; then
  echo "sqlite-sidecar: regenerated $CHANGED sidecar(s)"
fi
