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
  started_at      TEXT (ISO 8601, local time)
  ended_at        TEXT
  agent           TEXT
  goals           TEXT
  summary         TEXT
  key_files       TEXT (comma-separated)
  pid             INTEGER (shell PID for concurrent session safety)

journal:
  id              INTEGER PRIMARY KEY AUTOINCREMENT
  created_at      TEXT (ISO 8601, local time)
  session_id      TEXT
  content         TEXT NOT NULL

mantra:
  content         TEXT (single row — the project's self-authored narrative)
  updated_at      TEXT (ISO 8601, local time)
```

## Mantra System

The mantra is Claude's self-authored context — what Claude thinks is important that CLAUDE.md doesn't say. Not a project status summary or changelog. It's the complement to CLAUDE.md: CLAUDE.md is human-authored project instructions, the mantra is Claude's own evolving understanding of what matters. Patterns learned across sessions, non-obvious codebase knowledge, current momentum, things that keep coming up, tricky areas, working assumptions.

**Three sync points** (kept in sync by `/brain audit`):
1. `mantra` table in BRAIN.db — source of truth
2. `cowork/brain/MANTRA.md` — readable export
3. `<!-- BEGIN:mantra -->` block in CLAUDE.md — inline for fresh sessions (optional)

```bash
# Read current mantra
sqlite3 cowork/brain/BRAIN.db "SELECT content FROM mantra LIMIT 1;"

# Update mantra
sqlite3 cowork/brain/BRAIN.db "UPDATE mantra SET content = '...', updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime');"
```

The `logs` table is the main knowledge store (decisions, tasks, questions, insights, notes, milestones). `journal` captures per-session reflections written during `/brain done`. `mantra` holds Claude's self-authored context (complement to CLAUDE.md). `sessions` tracks session lifecycle (auto-managed by hooks).

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
sqlite3 cowork/brain/BRAIN.db "SELECT id, started_at, ended_at, goals, summary FROM sessions ORDER BY started_at DESC LIMIT 10;"
```

## Entry Types

- `note` — general observations, context, research, brainstorm summaries
- `decision` — choices made with rationale in body
- `question` — open questions to resolve (resolve via `/brain resolve`)
- `insight` — patterns or realizations worth preserving
- `task` — work items (managed via `/brain add task` and `/brain done`)
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

Tiers control what gets loaded at session start and what appears in digests. They are **computed, not manually set** — recalculated during digest and audit.

Temperature reflects **work completed**, not metadata touches. No per-entry access tracking.

### Rules (evaluated in order)

1. **archived**: `status` IN (done, dropped, superseded) OR `importance` = 0
2. **hot**: `focus` = 1, OR plan-linked task with plan momentum (see below)
3. **warm**: `importance` >= 6, OR `created_at` within 14 days
4. **cold**: everything else that's active

### Plan Momentum

A plan-linked task is hot if its plan has momentum — meaning real work is completing:

1. **Sibling completion**: another task with the same `meta.plan_id` has `completed_at` within 14 days
2. **Plan file activity**: `git log -1 --format=%aI -- cowork/plans/*<NNN>*.md` shows modification within 14 days

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

# Check 2: plan file modified in last 14 days
PLAN_MOD=$(git log -1 --format=%aI -- "cowork/plans/*<plan_id>*.md" 2>/dev/null)

# If either signal, heat up active tasks in this plan
if [ "$HAS_COMPLETION" -gt 0 ] || [ -n "$PLAN_MOD" -a "$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$PLAN_MOD" +%s 2>/dev/null)" -gt "$(date -v-14d +%s)" ]; then
  sqlite3 cowork/brain/BRAIN.db "UPDATE logs SET tier = 'hot' WHERE type='task' AND status='active' AND json_extract(meta, '$.plan_id') = '<plan_id>';"
fi
```

### Visibility by Tier

- **hot**: loaded at session start, shown in digests
- **warm**: shown in digests, searchable
- **cold**: searchable, hidden from digests
- **archived**: direct search only
