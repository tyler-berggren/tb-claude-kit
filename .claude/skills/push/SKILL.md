---
name: push
description: Commit all changes and push to remote.
---

# Push Changes

Stages all files, commits with an auto-generated message, and pushes to remote.

## Input

Optional argument: `$ARGUMENTS`

## Procedure

1. Run `git status` to see what's uncommitted
2. **Regenerate SQLite sidecars** (if configured)

   Before staging, check for `sqlite_tracking` in `.claude/kit.json`. If the array is non-empty,
   for each entry regenerate snapshot files in the AirSQLite sidecar layout so `git add -A` picks
   them up:

   ```bash
   jq -e '.sqlite_tracking | length > 0' .claude/kit.json >/dev/null 2>&1 && \
     jq -c '.sqlite_tracking[]' .claude/kit.json | while IFS= read -r entry; do
       DB=$(echo "$entry" | jq -r '.db')
       [ -f "$DB" ] || continue
       DIR=$(dirname "$DB")
       DBNAME=$(basename "$DB"); DBNAME="${DBNAME%.*}"
       SIDECAR_DIR="$DIR/$DBNAME.airsqlite"
       TABLES=$(echo "$entry" | jq -r 'if (.tables | length) > 0 then .tables[] else empty end')
       if [ -z "$TABLES" ]; then
         TABLES=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
       fi
       echo "$TABLES" | while IFS= read -r TABLE; do
         [ -z "$TABLE" ] && continue
         mkdir -p "$SIDECAR_DIR"
         printf '.mode json\nSELECT rowid AS _rowid, * FROM "%s" ORDER BY rowid;\n' "$TABLE" \
           | sqlite3 "$DB" \
           | python3 -c "
   import sys, json
   data = sys.stdin.read().strip()
   if data:
       [print(json.dumps(r, ensure_ascii=False)) for r in json.loads(data)]
   " > "$SIDECAR_DIR/$TABLE.snapshot.ndjson"
         # migrate old flat sidecar
         [ -f "$DIR/$TABLE.ndjson" ] && rm "$DIR/$TABLE.ndjson"
       done
     done
   ```

3. If there are uncommitted changes, stage and commit: `git add -A && git commit -m "<message>"`
4. Push: `git push`

## Rules

- **No permission required** — Execute immediately without asking
- **Concise messages** — Summarize what changed, not every detail
- **Never skip hooks** (`--no-verify`)
- **Include all files** — `git add -A`, never be selective
- **If nothing to commit** — Just push existing commits

---

## Project overrides

If `.claude/kit.json` has a `rules."push"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."push" // empty' .claude/kit.json 2>/dev/null
```
