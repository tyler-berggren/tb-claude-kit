# Brain DB Usage Reference

Database: `cowork/brain/BRAIN.db`

## Schema

```sql
logs:
  id              INTEGER PRIMARY KEY AUTOINCREMENT
  created_at      TEXT (ISO 8601, local time)
  type            TEXT (note, decision, question, insight, task, milestone)
  title           TEXT NOT NULL
  body            TEXT
  tags            TEXT (comma-separated)
  status          TEXT (active, done, blocked, dropped, superseded)
  parent_id       INTEGER (FK -> logs.id, for question->decision links and brainstorm->output links)
  meta            TEXT (JSON blob: plan_id, from_plan, blocked_by, depends_on)
  priority        INTEGER (lower = higher priority, relative within pillar)
  pillar          TEXT (broad area, defined per project)
  focus           INTEGER (0 or 1, max 3 items at a time)
  importance      INTEGER (0-10, default 5)
  tier            TEXT (hot, warm, cold, archived)
  completed_at    TEXT (ISO 8601, set when marking tasks done)
  supersedes      INTEGER (FK -> logs.id, the entry this one replaces)
  superseded_by   INTEGER (FK -> logs.id, the entry that replaced this one)

sessions:
  id              INTEGER PRIMARY KEY AUTOINCREMENT
  session_id      TEXT (Claude Code's session id, from the hook input)
  started_at      TEXT (ISO 8601, local time)
  ended_at        TEXT (set by the SessionEnd hook; NULL while running or after a crash)
```

The `logs` table is the knowledge store (decisions, tasks, questions, insights, notes, milestones). `sessions` records when each Claude Code session started and ended; the hooks manage it, and the session-start hook uses the previous session's start to list what it added, for the mantra review.

**The mantra is not in the DB.** It lives in the project's CLAUDE.md, between the line `<!-- BEGIN:mantra -->` and the line `<!-- END:mantra -->`, so it loads with CLAUDE.md and its history is git's. See `/brain mantra`.

**The DB is git-ignored.** To keep the brain in git, list it under `sqlite_tracking` in `.claude/kit.json` (install.sh does by default); `/commit` writes `cowork/brain/BRAIN.airsqlite/logs.snapshot.ndjson`, and the session-start hook rebuilds a missing DB from it (`scripts/sqlite-sidecar.sh restore`).

## Common Queries

```bash
# Recent entries
sqlite3 cowork/brain/BRAIN.db "SELECT id, created_at, type, title, status FROM logs ORDER BY created_at DESC LIMIT 20;"

# Active tasks by pillar
sqlite3 cowork/brain/BRAIN.db "SELECT id, title, pillar, priority FROM logs WHERE type='task' AND status='active' ORDER BY pillar, priority;"

# Focus items
sqlite3 cowork/brain/BRAIN.db "SELECT id, title, pillar FROM logs WHERE focus = 1 AND status = 'active';"

# Full-text search (FTS5, ranked by relevance)
sqlite3 cowork/brain/BRAIN.db "SELECT e.id, e.type, e.title, rank FROM logs_fts f JOIN logs e ON e.id = f.rowid WHERE logs_fts MATCH 'keyword' ORDER BY rank;"

# FTS5 with boolean operators
sqlite3 cowork/brain/BRAIN.db "SELECT e.id, e.type, e.title FROM logs_fts f JOIN logs e ON e.id = f.rowid WHERE logs_fts MATCH 'sync OR connector' ORDER BY rank;"

# Fallback: LIKE search (for partial words FTS5 misses)
sqlite3 cowork/brain/BRAIN.db "SELECT id, type, title, body FROM logs WHERE title LIKE '%keyword%' OR body LIKE '%keyword%';"

# Search by tag
sqlite3 cowork/brain/BRAIN.db "SELECT id, type, title FROM logs WHERE tags LIKE '%tagname%';"

# Open questions
sqlite3 cowork/brain/BRAIN.db "SELECT id, title, body FROM logs WHERE type='question' AND status='active';"

# What depends on a decision
sqlite3 cowork/brain/BRAIN.db "SELECT id, type, title FROM logs WHERE json_extract(meta, '$.depends_on') LIKE '%DECISION_ID%';"

# Supersession chain for an entry
sqlite3 cowork/brain/BRAIN.db "SELECT id, title, status, supersedes, superseded_by FROM logs WHERE id = ID OR supersedes = ID OR superseded_by = ID;"

# Recent sessions
sqlite3 cowork/brain/BRAIN.db "SELECT id, started_at, ended_at FROM sessions ORDER BY id DESC LIMIT 10;"
```

## Entry Types

- `note` — general observations, context, research, brainstorm summaries
- `decision` — choices made with rationale in body
- `question` — open questions to resolve (resolve via `/brain resolve`)
- `insight` — patterns or realizations worth preserving
- `task` — work items (managed via `/brain add task` and `/brain update`)
- `milestone` — significant project events, weekly review snapshots

## Tag Conventions

Tags are **always stored sorted alphabetically and lowercase**. Every skill normalizes on write: split by comma, trim, lowercase, sort, deduplicate, rejoin.

```bash
# Check existing tags before inventing new ones
sqlite3 cowork/brain/BRAIN.db "SELECT DISTINCT tags FROM logs WHERE tags IS NOT NULL AND tags != '' ORDER BY tags;"

# Find entries with a specific tag
sqlite3 cowork/brain/BRAIN.db "SELECT id, type, title FROM logs WHERE ',' || tags || ',' LIKE '%,tagname,%';"
```

## Tier System

Tiers control what gets loaded at session start and what `/brain` shows. They are **computed, not manually set** — recalculated at every session start and by `/brain` after any change.

Temperature reflects **work completed**, not metadata touches. No per-entry access tracking.

### Rules (evaluated in order)

1. **archived**: `status` IN (done, dropped, superseded) OR `importance` = 0
2. **hot**: `focus` = 1, OR plan-linked task with plan momentum (see below)
3. **warm**: `importance` >= 6, OR `created_at` within 14 days
4. **cold**: everything else that's active

### Plan Momentum

A plan-linked task is hot if its plan has momentum — meaning real work is completing:

1. **Sibling completion**: another task with the same `meta.plan_id` has `completed_at` within 14 days
2. **Plan file activity**: `git log -1 --format=%at -- cowork/plans/*<NNN>*.md` shows modification within 14 days

Either signal counts. The skill checks both during tier recalculation.

### Recalculation

Tier recalc is a two-phase process: SQL for most rules, then a shell + SQL pass for plan momentum.

**Phase 1 — SQL (focus, importance, recency, archived):**

```sql
-- Step 1: archived
UPDATE logs SET tier = 'archived'
WHERE status IN ('done', 'dropped', 'superseded') OR importance = 0;

-- Step 2: reset active/blocked to cold (baseline)
UPDATE logs SET tier = 'cold'
WHERE status IN ('active', 'blocked');

-- Step 3: warm (importance >= 6 or recent)
UPDATE logs SET tier = 'warm'
WHERE status IN ('active', 'blocked') AND (
  importance >= 6
  OR created_at >= datetime('now', '-14 days', 'localtime')
);

-- Step 4: hot (focus only — plan momentum handled in phase 2)
UPDATE logs SET tier = 'hot'
WHERE status IN ('active', 'blocked') AND focus = 1;
```

**Phase 2 — Plan momentum (shell + SQL):**

For each plan with active tasks:

```bash
# Get plans with active tasks
sqlite3 cowork/brain/BRAIN.db "SELECT DISTINCT json_extract(meta, '$.plan_id') FROM logs WHERE type='task' AND status='active' AND json_extract(meta, '$.plan_id') IS NOT NULL;"
```

For each plan_id, check momentum:

```bash
# Check 1: sibling task completed in last 14 days
HAS_COMPLETION=$(sqlite3 cowork/brain/BRAIN.db "SELECT count(*) FROM logs WHERE json_extract(meta, '$.plan_id') = '<plan_id>' AND completed_at >= datetime('now', '-14 days', 'localtime');")

# Check 2: plan file modified in last 14 days (Unix seconds from git; works on macOS and Linux,
# where parsing %aI with BSD date fails on the colon in its offset)
MOD_TS=$(git log -1 --format=%at -- "cowork/plans/*<plan_id>*.md" 2>/dev/null)
CUTOFF=$(( $(date +%s) - 14 * 86400 ))

# If either signal, heat up active tasks in this plan
if [ "$HAS_COMPLETION" -gt 0 ] || { [ -n "$MOD_TS" ] && [ "$MOD_TS" -gt "$CUTOFF" ]; }; then
  sqlite3 cowork/brain/BRAIN.db "UPDATE logs SET tier = 'hot' WHERE type='task' AND status='active' AND json_extract(meta, '$.plan_id') = '<plan_id>';"
fi
```

### Visibility by Tier

- **hot**: loaded at session start, shown by `/brain`
- **warm**: shown by `/brain`, searchable
- **cold**: searchable, hidden from `/brain`
- **archived**: direct search only
