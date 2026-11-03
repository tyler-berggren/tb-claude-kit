---
name: brain
description: Read, write, and search the project brain (notes, decisions, questions, insights, tasks, milestones). The single interface for all project knowledge and task management.
argument-hint: "[update|audit|focus|add|done|mantra|search|resolve|depends|tag|<pillar>] [args]"
---

## Focus Items
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, title, pillar FROM logs WHERE focus = 1 AND status = 'active';" 2>/dev/null || echo "No focus items set"`

## Active Tasks by Pillar
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, title, pillar, CASE WHEN focus=1 THEN '*' ELSE '' END FROM logs WHERE type = 'task' AND status IN ('active','blocked') ORDER BY pillar, priority ASC, created_at ASC;" 2>/dev/null || echo "No active tasks"`

## Open Questions
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, title FROM logs WHERE type = 'question' AND status = 'active';" 2>/dev/null || echo "None"`

## Recent Entries
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, type, title FROM logs WHERE tier IN ('hot','warm') AND status = 'active' ORDER BY created_at DESC LIMIT 12;" 2>/dev/null || echo "No entries yet"`

## Existing Tags
!`sqlite3 cowork/brain/BRAIN.db "SELECT DISTINCT tags FROM logs WHERE tags IS NOT NULL AND tags != '';" 2>/dev/null || echo "None yet"`

---

# Brain

Manage all project knowledge in `cowork/brain/BRAIN.db` — decisions, questions, insights, tasks, notes, and milestones. One skill, one database, one source of truth.

## Input

Optional argument: `$ARGUMENTS`

Dispatch on the first word:

- (empty) — **Review**: daily "what's going on" view
- `update` — **Update**: sync brain to reflect what just happened — mark completed tasks, log decisions, fix stale state
- `audit` — **Audit**: deep health check since last audit
- `focus` — **Focus**: set 2-3 focus items
- `add <type>` — **Add**: create a new entry (note, decision, question, insight, task, milestone)
- `done` — **Done**: close the session — sync the brain, consider the mantra and a lesson
- `mantra` — **Mantra**: consider updating the mantra based on recent work
- `search <query>` — **Search**: full-text search across title, body, and tags
- `resolve <question_id>` — **Resolve**: answer a question by creating a linked decision
- `depends <id> <depends_on_id>` — **Depends**: mark that an entry depends on a decision
- `tag <id> <tags>` — **Tag**: update tags on an existing entry
- A bare pillar name (e.g. `platform`, `backend`) — **Review** filtered to that pillar's tasks

---

## Review (default)

The daily "what's going on" view. Shows focus, tasks, questions, and recent decisions in one pass. The dynamic context above already loaded the current state — use it as your starting point.

### Procedure

1. Start from the auto-loaded state above. Query deeper if needed:
   ```sql
   -- Tasks with bodies for context
   SELECT id, title, body, tags, pillar, priority, status, meta
   FROM logs WHERE type = 'task' AND status IN ('active', 'blocked')
   ORDER BY pillar, priority ASC, created_at ASC;

   -- Recent decisions
   SELECT id, created_at, title, substr(body, 1, 120) FROM logs
   WHERE type = 'decision' AND status = 'active' ORDER BY created_at DESC LIMIT 10;
   ```
2. If a pillar was specified, filter tasks to that pillar only.
3. Present findings conversationally:
   - Focus items first, with brief status check
   - Active tasks grouped by pillar
   - Blocked items highlighted with why
   - Open questions that need resolution
   - Recent decisions that set direction
4. Run **Recalculate tiers** at the end.

---

## Update subcommand

Sync the brain to reflect what actually happened this session. Run after a block of work to make sure the DB matches reality — tasks that got done are marked done, decisions that were made are logged, stale state is cleaned up.

Usage: `update`

This is lighter than an audit. An audit looks back over days/weeks and asks strategic questions. Update looks at the current session and asks "does the brain match what just happened?"

### Procedure

1. **What shipped this session.** Check recent commits since the current session started (or last few hours if no session):
   ```bash
   git log --oneline --since='3 hours ago'
   ```
   Also check conversation context for work that was done.

2. **Find tasks that should be done.** Cross-reference what shipped against active tasks:
   ```sql
   SELECT id, title, pillar, status, meta FROM logs
   WHERE type = 'task' AND status = 'active'
   ORDER BY pillar, created_at DESC;
   ```
   For each active task, check: was this completed by the work that just happened? If yes, mark it done:
   ```sql
   UPDATE logs SET status = 'done',
     completed_at = datetime('now', 'localtime'),
     body = body || char(10) || '--- Done: <what was accomplished>'
   WHERE id = <id>;
   ```

3. **Find decisions that were made but not logged.** Check conversation context for architectural choices, technical decisions, or direction changes that happened during the session but weren't captured via `/brainstorm` or `/brain add`. Log any missing ones:
   ```sql
   INSERT INTO logs (type, title, body, tags, importance)
   VALUES ('decision', '<title>', '<rationale>', '<tags>', <importance>);
   ```

4. **Check plan progress.** If a plan was actively worked on, verify the plan file reflects current state — items checked off, status lines updated, RESUME banner in the right place. Report each gap or fix with the plan's path and line (`/plan`, **Pointing at a line**):
   ```sql
   SELECT id, title, meta FROM logs
   WHERE type = 'task' AND json_extract(meta, '$.plan_id') IS NOT NULL
   AND status = 'active';
   ```

5. **Fix stale state.** Look for obvious inconsistencies:
   - Tasks marked active that the codebase shows are done
   - Decisions that were superseded by newer decisions during this session
   - Focus items that were completed and should be cleared

6. **Present changes.** Summarize what was updated: tasks marked done, decisions logged, state fixed. Don't silently modify — show the user what changed.

7. Run **Recalculate tiers**.

---

## Audit subcommand

Deep health check — surfaces stale work, unresolved questions, unacted decisions, and what shipped since the last audit. Ends by recalibrating focus. Not on a fixed schedule — run whenever the brain needs a checkup.

Usage: `audit`

### Step 1 — Find the last audit

```sql
SELECT id, created_at, body FROM logs
WHERE type = 'milestone' AND tags LIKE '%audit%'
ORDER BY created_at DESC LIMIT 1;
```

If no prior audit, use 7 days ago as the baseline.

### Step 2 — What shipped

Check git history since the last audit:

```bash
git log --oneline --since='<last_audit_date>'
```

Query completed entries since the last audit:
```sql
SELECT id, type, title, body FROM logs
WHERE status = 'done' AND created_at > '<last_audit_date>'
ORDER BY created_at DESC;
```

Summarize what was accomplished. Group by pillar or theme. Start here — celebrate progress before digging into problems.

### Step 3 — Stale work

Find active tasks and questions that haven't been accessed since the last audit:

```sql
SELECT id, type, title, pillar, created_at, importance
FROM logs
WHERE status = 'active' AND type IN ('task', 'question')
AND created_at < '<last_audit_date>'
AND focus = 0
AND (json_extract(meta, '$.plan_id') IS NULL
  OR json_extract(meta, '$.plan_id') NOT IN (
    SELECT DISTINCT json_extract(meta, '$.plan_id') FROM logs
    WHERE completed_at >= datetime('now', '-14 days', 'localtime')
  ))
ORDER BY created_at ASC;
```

For each stale item (old, not focused, no plan momentum):
- Is it still relevant? Check codebase and recent decisions for context changes.
- Should it be dropped, deferred, or kept and reprioritized?

Present findings. Don't auto-drop — propose and wait for direction.

### Step 4 — Open questions

```sql
SELECT id, title, body, created_at, tags FROM logs
WHERE type = 'question' AND status = 'active'
ORDER BY importance DESC, created_at ASC;
```

For each:
- Has the answer emerged from recent work or decisions? If so, propose resolving it.
- Is it blocking anything? `SELECT id, title FROM logs WHERE json_extract(meta, '$.depends_on') LIKE '%<question_id>%';`
- How long has it been open?

### Step 5 — Unacted decisions

Decisions are only valuable if they lead to action:

```sql
SELECT d.id, d.title, d.created_at, substr(d.body, 1, 150),
  (SELECT count(*) FROM logs t WHERE json_extract(t.meta, '$.depends_on') LIKE '%' || d.id || '%') as dependents
FROM logs d
WHERE d.type = 'decision' AND d.status = 'active'
AND d.created_at > '<last_audit_date>'
ORDER BY d.created_at DESC;
```

Flag decisions with no downstream tasks or dependents.

### Step 6 — Brain health

```sql
-- Entry counts by type and status
SELECT type, status, count(*) FROM logs GROUP BY type, status ORDER BY type, status;

-- Tier distribution
SELECT tier, count(*) FROM logs WHERE status = 'active' GROUP BY tier;

-- Tag frequency (top 15)
SELECT tags, count(*) FROM logs WHERE tags IS NOT NULL AND tags != '' GROUP BY tags ORDER BY count(*) DESC LIMIT 15;

-- Pillar distribution of active tasks
SELECT pillar, count(*) FROM logs WHERE type = 'task' AND status = 'active' GROUP BY pillar;
```

Note anything out of balance: too many hot items, pillars with no active tasks, tag sprawl.

### Step 7 — Docs staleness

Check if documents in `cowork/` reference superseded or dropped decisions:

```bash
grep -oP '#\d+' cowork/platform/*.md cowork/notes/*.md 2>/dev/null | grep -oP '\d+' | sort -u
```

```sql
SELECT id, title, status, superseded_by FROM logs
WHERE id IN (<extracted_ids>) AND status IN ('superseded', 'dropped');
```

If staleness is found, list affected docs and propose updates.

### Step 8 — Set focus

Run the **Focus** procedure (see below).

### Step 9 — Log the audit

```sql
INSERT INTO logs (type, title, body, tags, importance)
VALUES ('milestone',
  'Audit — <date>',
  '<summary: what shipped, what was dropped/deferred, new focus items, brain health notes>',
  'audit',
  7);
```

### Step 10 — Update mantra

The mantra is Claude's self-authored context — what matters that CLAUDE.md doesn't say. Not a changelog or status summary. Think: what would a fresh Claude session need to know that isn't in CLAUDE.md? Patterns, non-obvious knowledge, tricky areas, current momentum, working assumptions.

1. Read the current mantra (the block between the mantra marker lines in CLAUDE.md, already in your context) and recent high-signal entries:
   ```sql
   SELECT id, type, title, substr(body, 1, 300), created_at FROM logs
   WHERE created_at > '<last_audit_date>'
   AND type IN ('decision', 'milestone', 'insight')
   AND importance >= 5
   ORDER BY created_at DESC;
   ```
2. Rewrite the mantra. Ask: what did I learn this period that a fresh session would benefit from? What's non-obvious about where the project is right now? What keeps tripping me up or coming up repeatedly? What assumptions am I working under?
3. Write it via the **Mantra subcommand** procedure.

### Step 11 — Recalculate tiers

Run **Recalculate tiers**.

---

## Focus subcommand

Set 2-3 focus items. These appear at the top of every session start.

Usage: `focus`

### Procedure

1. Show current focus items and their status.
2. Clear existing focus:
   ```sql
   UPDATE logs SET focus = 0 WHERE focus = 1;
   ```
3. Propose 2-3 focus items based on:
   - What has momentum and should be finished?
   - What's been stuck and needs dedicated attention?
   - What's most important strategically right now?
4. Present the proposed focus set and wait for user approval.
5. On approval:
   ```sql
   UPDATE logs SET focus = 1 WHERE id IN (<id1>, <id2>, <id3>);
   ```
6. Run **Recalculate tiers**.

---

## Add subcommand

Create a new entry. Usage: `add <type>` where type is one of: `note`, `decision`, `question`, `insight`, `task`, `milestone`.

### Procedure

1. Parse the type from the argument. If missing or invalid, ask the user.
2. Ask the user for:
   - **Title** (required) — concise summary
   - **Body** (optional) — detail, rationale, context
   - **Tags** (optional) — comma-separated, reuse existing tags shown above
   - **Importance** (optional) — 0-10, defaults to 5
   - For **task** type, also ask:
     - **Pillar** (required) — check existing pillars and suggest best fit
     - **Priority** (optional) — integer, lower = higher priority
3. **Normalize tags**: split by comma, trim, lowercase, sort alphabetically, deduplicate, rejoin.
4. Insert:
   ```sql
   -- For non-task types:
   INSERT INTO logs (type, title, body, tags, importance)
   VALUES ('<type>', '<title>', '<body>', '<normalized_tags>', <importance>);

   -- For tasks:
   INSERT INTO logs (type, title, body, tags, pillar, priority, importance)
   VALUES ('task', '<title>', '<body>', '<normalized_tags>', '<pillar>', <priority>, <importance>);
   ```
5. Confirm the entry was created (show id and created_at).
6. Run **Recalculate tiers**.

---

## Done subcommand

Close the session: make the brain match what happened, then consider the mantra and a lesson. Usage: `done`

### Procedure

1. Run the **Update** procedure (tasks done, decisions logged, plan progress, stale state).
2. **Mantra check.** Did this session surface anything a fresh session would need that CLAUDE.md doesn't say — a new pattern, a non-obvious gotcha, a shifted assumption, a tricky area? If yes, rewrite the mantra via the **Mantra subcommand** procedure. If the work was routine, skip.
3. **Compound lesson.** If a reusable lesson emerged, write it as an insight tagged `lesson`: one sentence stating the rule, then Why and How to apply.
4. Tell the user in two or three lines what changed in the brain and the mantra.

---

## Search subcommand

Full-text search across the brain using FTS5. Usage: `search <query>`

### Procedure

1. Search using FTS5 (ranked by relevance via BM25):
   ```sql
   SELECT e.id, e.created_at, e.type, e.title, substr(e.body, 1, 200), e.tags, e.tier, rank
   FROM logs_fts f
   JOIN logs e ON e.id = f.rowid
   WHERE logs_fts MATCH '<query>'
   ORDER BY rank;
   ```
   FTS5 query syntax: `word1 word2` (implicit AND), `word1 OR word2`, `"exact phrase"`, `prefix*`, `NOT word`.
2. If FTS5 returns no results, fall back to LIKE:
   ```sql
   SELECT id, created_at, type, title, substr(body, 1, 200), tags, tier
   FROM logs
   WHERE title LIKE '%<query>%' OR body LIKE '%<query>%' OR tags LIKE '%<query>%'
   ORDER BY created_at DESC;
   ```
3. Present results grouped by type with enough context to be useful.
4. If no results from either method, suggest related queries based on existing tags.

---

## Resolve subcommand

Answer an open question by creating a linked decision. Usage: `resolve <question_id>`

### Procedure

1. Read the question:
   ```sql
   SELECT id, title, body, tags FROM logs WHERE id = <question_id> AND type = 'question';
   ```
   If not a question, error.
2. Ask the user: "What's the answer/decision?" (or infer from conversation context).
3. Create the decision with `parent_id` linking back to the question:
   ```sql
   INSERT INTO logs (type, title, body, tags, parent_id)
   VALUES ('decision', '<decision_title>', '<rationale>', '<tags>', <question_id>);
   ```
4. Mark the question as resolved:
   ```sql
   UPDATE logs SET status = 'done',
     body = body || char(10) || '--- Resolved by decision #' || <new_decision_id>
   WHERE id = <question_id>;
   ```
5. Confirm both entries. Run **Recalculate tiers**.

---

## Depends subcommand

Mark that an entry depends on a decision. Usage: `depends <id> <depends_on_id>`

### Procedure

1. Verify both entries exist. The dependency target should be a decision.
2. Update the dependent entry's meta:
   ```sql
   UPDATE logs SET meta = json_set(COALESCE(meta, '{}'), '$.depends_on',
     json_array(<depends_on_id>))
   WHERE id = <id>;
   ```
   If `depends_on` already exists in meta, append to the array rather than replacing.
3. Confirm. Show: "Entry #X now depends on decision #Y: <decision_title>"

---

## Tag subcommand

Update tags on an entry. Usage: `tag <id> <tags>`

### Procedure

1. Read the current entry:
   ```sql
   SELECT id, title, tags FROM logs WHERE id = <id>;
   ```
2. **Normalize tags**: split by comma, trim, lowercase, sort alphabetically, deduplicate, rejoin.
3. Update:
   ```sql
   UPDATE logs SET tags = '<normalized_tags>' WHERE id = <id>;
   ```
4. Confirm the change.

---

## Mantra subcommand

Reflect on recent work and consider updating the mantra. The mantra is Claude's self-authored context — what matters that the rest of CLAUDE.md doesn't say: patterns, non-obvious knowledge, tricky areas, current momentum, working assumptions. It is not a changelog or a status report.

It lives in one place: CLAUDE.md, between the line that is exactly `<!-- BEGIN:mantra -->` and the line that is exactly `<!-- END:mantra -->`. It is already in your context. There is no copy in the DB or anywhere else.

### Procedure

1. Review conversation context and recent work. Ask: did this session surface anything a fresh session would need that isn't already written down?
2. If nothing meaningful, say so and skip. Don't update for routine work.
3. Rewrite the block with the Edit tool. Match the WHOLE marker lines — never the first place the marker text appears, since prose elsewhere may quote it. If the block doesn't exist, add a `## Mantra` section at the end of CLAUDE.md holding both marker lines.
4. **Stay within about 4,000 characters.** Rewrite rather than append: merge, cut what is stale, cut what CLAUDE.md or the code now says. The session-start hook flags a mantra over budget.
5. Show the user the lines that changed. No confirmation needed — git history is the mantra's history, and the user can revert.

---

## Recalculate tiers

Tiers are computed, never set by hand. Run the full two-phase recalculation from USAGE.md: the SQL phase (archived, cold, warm, focus-hot), then the plan-momentum shell phase. The session-start hook runs the same thing on every start.

---

## Shared conventions

- **The DB is the only copy.** There is no markdown export. Query the DB; `/brain` with no argument is the readable view.
- **Recalculate tiers** at the end of any subcommand that changes status, focus or importance.
- **Normalize tags on every write.** Split by comma, trim, lowercase, sort alphabetically, deduplicate, rejoin. Check existing tags (shown in dynamic context above) before inventing new ones.
- **Set completed_at when marking tasks done.** Always set `completed_at = datetime('now', 'localtime')` — this drives plan momentum detection.
- **Decisions are permanent.** Don't update a decision — create a new one that supersedes it (`supersedes` column) and mark the old one `superseded` (`superseded_by` column).
- **Questions resolve into decisions.** Use `resolve <id>` to create the linked decision.
- **Decision dependencies.** Use `depends` to track what builds on what.
- **Sessions are auto-logged.** The hooks record each session's start and end by Claude Code's session id. Nothing else is stored per session.
- **Pillar consistency.** Check existing pillars before creating new ones. Pillars are broad areas, not fine-grained categories.
- **Priority is relative per pillar.** Priority 1 in one pillar has no relation to priority 1 in another.
- **Meta is structured.** Use `json_set` / `json_extract`. Common keys: `plan_id`, `from_plan`, `blocked_by`, `depends_on`.
- **`plan_id` is a zero-padded string.** Always `'003'`, never bare `3`.

## Global rules

- **No permission needed** — Execute immediately without asking.
- **Brainstorm before writing** — For Add, present what you'll insert and wait for confirmation.
- **Keep it conversational** — Review, Audit, and Search results should be narrated, not raw SQL output.
- **Opinionated but collaborative** — During Audit, propose what to drop, defer, and focus on. Hold it loosely — the user makes the final call.
- **Don't auto-drop** — Propose changes. Wait for confirmation before executing status/tier/focus updates.

---

## Project overrides

If `.claude/kit.json` has a `rules."brain"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."brain" // empty' .claude/kit.json 2>/dev/null
```
