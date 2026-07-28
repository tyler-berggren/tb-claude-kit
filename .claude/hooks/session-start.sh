#!/bin/bash
DB="cowork/brain/BRAIN.db"

if [ ! -f "$DB" ]; then
  exit 0
fi

# --- Schema integrity guard: auto-migrate drift and SURFACE it (never fail silently) ---
# CREATE TABLE IF NOT EXISTS can add missing *tables* but never missing *columns* on an
# existing table, so an old DB silently drifts and every query below returns empty. This
# heals both and injects a visible notice into the session context when it does.
SCHEMA_NOTICE=""
SCHEMA_FILE="cowork/brain/schema.sql"
if [ -f "$SCHEMA_FILE" ]; then
  HEALED=""
  COLS=$(sqlite3 "$DB" "PRAGMA table_info(logs);" 2>/dev/null | awk -F'|' '{print $2}')
  ensure_col() {
    printf '%s\n' "$COLS" | grep -qx "$1" || {
      if sqlite3 "$DB" "ALTER TABLE logs ADD COLUMN $2;" 2>/dev/null; then HEALED="$HEALED $1"; fi
    }
  }
  # logs columns that a CREATE TABLE IF NOT EXISTS re-apply cannot backfill:
  ensure_col priority      "priority INTEGER"
  ensure_col tier          "tier TEXT NOT NULL DEFAULT 'warm' CHECK (tier IN ('hot','warm','cold','archived'))"
  ensure_col completed_at  "completed_at TEXT"
  ensure_col superseded_by "superseded_by INTEGER REFERENCES logs(id)"
  # (re)apply schema to create any missing tables (sessions/journal/mantra) + indexes.
  # Columns are ensured first so index creation (e.g. idx_logs_tier) can't fail.
  SCHEMA_ERR=$(sqlite3 "$DB" < "$SCHEMA_FILE" 2>&1 >/dev/null)
  if [ -n "$HEALED" ] || [ -n "$SCHEMA_ERR" ]; then
    SCHEMA_NOTICE="⚠️ BRAIN.db schema was out of date and auto-migrated at session start."
    [ -n "$HEALED" ] && SCHEMA_NOTICE="$SCHEMA_NOTICE Added missing logs columns:$HEALED."
    [ -n "$SCHEMA_ERR" ] && SCHEMA_NOTICE="$SCHEMA_NOTICE Remaining errors: $SCHEMA_ERR"
    SCHEMA_NOTICE="$SCHEMA_NOTICE Prior sessions may have run against a degraded schema — tier/journal/mantra state may be incomplete; consider re-running /brain digest."
  fi
fi

# Close any stale sessions (crashed/killed without SessionEnd hook firing)
sqlite3 "$DB" "UPDATE sessions SET ended_at = started_at WHERE ended_at IS NULL AND pid IS NOT NULL AND pid != $$;"

# Find the last closed session before inserting a new one
LAST_SESSION_ID=$(sqlite3 "$DB" "SELECT id FROM sessions WHERE ended_at IS NOT NULL ORDER BY ended_at DESC LIMIT 1;")
LAST_SESSION_START=""
if [ -n "$LAST_SESSION_ID" ]; then
  LAST_SESSION_START=$(sqlite3 "$DB" "SELECT started_at FROM sessions WHERE id = $LAST_SESSION_ID;")
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

# Query last session's work for mantra review
LAST_SESSION_LOGS=""
LAST_SESSION_JOURNAL=""
if [ -n "$LAST_SESSION_START" ]; then
  LAST_SESSION_LOGS=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, type, title FROM logs WHERE created_at >= '$LAST_SESSION_START' ORDER BY created_at DESC LIMIT 15;")
  LAST_SESSION_JOURNAL=$(sqlite3 "$DB" "SELECT content FROM journal WHERE session_id = '$LAST_SESSION_ID' ORDER BY created_at DESC LIMIT 1;")
fi
LAST_SESSION_SUMMARY=""
if [ -n "$LAST_SESSION_ID" ]; then
  LAST_SESSION_SUMMARY=$(sqlite3 "$DB" "SELECT summary FROM sessions WHERE id = $LAST_SESSION_ID;")
fi

CTX="## Brain State (auto-loaded at session start)"

if [ -n "$SCHEMA_NOTICE" ]; then
  CTX="$CTX

$SCHEMA_NOTICE"
fi

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

# Append last session context for mantra review
if [ -n "$LAST_SESSION_LOGS" ] || [ -n "$LAST_SESSION_JOURNAL" ] || [ -n "$LAST_SESSION_SUMMARY" ]; then
  CTX="$CTX

### Last Session (#$LAST_SESSION_ID)"
  if [ -n "$LAST_SESSION_SUMMARY" ]; then
    CTX="$CTX
Summary: $LAST_SESSION_SUMMARY"
  fi
  if [ -n "$LAST_SESSION_JOURNAL" ]; then
    CTX="$CTX
Journal: $LAST_SESSION_JOURNAL"
  fi
  if [ -n "$LAST_SESSION_LOGS" ]; then
    CTX="$CTX
Entries created:
$LAST_SESSION_LOGS"
  fi
fi

CTX="$CTX

### Mantra Review
Review the last session's work above and the current mantra. If the last session surfaced patterns, non-obvious knowledge, shifted assumptions, or tricky areas that a fresh session would benefit from — update the mantra silently (DB + MANTRA.md + CLAUDE.md block) before starting your work. Skip if the last session was routine or the mantra already captures it. Do not ask the user — just update or skip.

### Compound Lesson
Before wrapping up a substantive session, consider: did a reusable lesson or pattern emerge? If yes, write it as a brain insight tagged 'lesson' — one sentence stating the rule, then Why and How to apply. If nothing novel was learned, skip this entirely."

# Escape for JSON
CTX_ESCAPED=$(printf '%s' "$CTX" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

echo "{\"hookSpecificOutput\":{\"additionalContext\":$CTX_ESCAPED}}"
