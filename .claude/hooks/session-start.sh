#!/bin/bash
DB="cowork/brain/BRAIN.db"

if [ ! -f "$DB" ]; then
  exit 0
fi

# Insert session row with PID for concurrent session safety
sqlite3 "$DB" "INSERT INTO sessions (agent, goals, pid) VALUES ('claude-code', 'auto-started', $$);"

# Recalculate tiers — Phase 1 (SQL)
sqlite3 "$DB" "
UPDATE logs SET tier = 'archived'
WHERE status IN ('done', 'dropped', 'superseded') OR importance = 0;

UPDATE logs SET tier = 'cold'
WHERE status IN ('active', 'blocked');

UPDATE logs SET tier = 'warm'
WHERE status IN ('active', 'blocked') AND (
  importance >= 6
  OR created_at >= datetime('now', '-14 days', 'localtime')
);

UPDATE logs SET tier = 'hot'
WHERE status IN ('active', 'blocked') AND focus = 1;
"

# Recalculate tiers — Phase 2 (plan momentum)
PLAN_IDS=$(sqlite3 "$DB" "SELECT DISTINCT json_extract(meta, '\$.plan_id') FROM logs WHERE type='task' AND status='active' AND json_extract(meta, '\$.plan_id') IS NOT NULL;")
for PLAN_ID in $PLAN_IDS; do
  HAS_COMPLETION=$(sqlite3 "$DB" "SELECT count(*) FROM logs WHERE json_extract(meta, '\$.plan_id') = '$PLAN_ID' AND completed_at >= datetime('now', '-14 days', 'localtime');")
  PLAN_MOD=$(git log -1 --format=%aI -- "cowork/plans/*${PLAN_ID}*.md" 2>/dev/null)
  DOMINATED=0
  if [ "$HAS_COMPLETION" -gt 0 ]; then
    DOMINATED=1
  elif [ -n "$PLAN_MOD" ]; then
    MOD_TS=$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$PLAN_MOD" +%s 2>/dev/null)
    CUTOFF=$(date -v-14d +%s)
    if [ -n "$MOD_TS" ] && [ "$MOD_TS" -gt "$CUTOFF" ]; then
      DOMINATED=1
    fi
  fi
  if [ "$DOMINATED" -eq 1 ]; then
    sqlite3 "$DB" "UPDATE logs SET tier = 'hot' WHERE type='task' AND status='active' AND json_extract(meta, '\$.plan_id') = '$PLAN_ID';"
  fi
done

# Query brain state
MANTRA=$(sqlite3 "$DB" "SELECT content FROM mantra LIMIT 1;")
FOCUS=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, title, pillar FROM logs WHERE focus = 1 AND status = 'active';")
RECENT=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, type, title FROM logs ORDER BY created_at DESC LIMIT 8;")
TASKS=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, title, pillar FROM logs WHERE type = 'task' AND status = 'active' ORDER BY pillar, priority;")
QUESTIONS=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, title FROM logs WHERE type = 'question' AND status = 'active';")

CTX="## Brain State (auto-loaded at session start)"

if [ -n "$MANTRA" ]; then
  CTX="$CTX
### Mantra
$MANTRA"
fi

CTX="$CTX
### Focus Items"
if [ -n "$FOCUS" ]; then
  CTX="$CTX
$FOCUS"
else
  CTX="$CTX
No focus items set."
fi

CTX="$CTX
### Active Tasks"
if [ -n "$TASKS" ]; then
  CTX="$CTX
$TASKS"
else
  CTX="$CTX
No active tasks."
fi

if [ -n "$QUESTIONS" ]; then
  CTX="$CTX
### Open Questions
$QUESTIONS"
fi

CTX="$CTX
### Recent Entries
$RECENT"

# Escape for JSON
CTX_ESCAPED=$(printf '%s' "$CTX" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

echo "{\"hookSpecificOutput\":{\"additionalContext\":$CTX_ESCAPED}}"
