---
name: brain
description: Read, write, and search the project brain (notes, decisions, questions, insights, tasks, milestones). The single interface for all project knowledge and task management.
argument-hint: "[update|audit|focus|add|done|journal|mantra|search|resolve|depends|tag|digest|<pillar>] [args]"
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
- `done` — **Done**: close the session — summarize, journal, update mantra
- `journal` — **Journal**: consider writing a journal entry based on recent work
- `mantra` — **Mantra**: consider updating the mantra based on recent work
- `search <query>` — **Search**: full-text search across title, body, and tags
- `resolve <question_id>` — **Resolve**: answer a question by creating a linked decision
- `depends <id> <depends_on_id>` — **Depends**: mark that an entry depends on a decision
- `tag <id> <tags>` — **Tag**: update tags on an existing entry
- `digest` — **Digest**: regenerate `cowork/brain/BRAIN.md`
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
4. Run **Digest** at the end.

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

4. **Check plan progress.** If a plan was actively worked on, verify the plan file reflects current state — items checked off, status lines updated, RESUME banner in the right place:
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

7. **Recalculate tiers** (without regenerating `BRAIN.md`). Run the full two-phase tier recalculation from USAGE.md (SQL phase + plan momentum shell phase).

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

1. Read the current mantra and recent high-signal entries:
   ```sql
   SELECT content FROM mantra LIMIT 1;
   SELECT id, type, title, substr(body, 1, 300), created_at FROM logs
   WHERE created_at > '<last_audit_date>'
   AND type IN ('decision', 'milestone', 'insight')
   AND importance >= 5
   ORDER BY created_at DESC;
   ```
2. Rewrite the mantra. Ask: what did I learn this period that a fresh session would benefit from? What's non-obvious about where the project is right now? What keeps tripping me up or coming up repeatedly? What assumptions am I working under?
3. Update via the **Mantra subcommand** procedure (DB update + MANTRA.md export + CLAUDE.md mantra block).

### Step 11 — Recalculate tiers and regenerate digest

Run **Digest** (which includes tier recalculation).

---

## Focus subcommand

Set 2-3 focus items. These appear at the top of every session start and in the brain digest.

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
6. Run **Digest**.

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
6. Run **Digest**.

---

## Done subcommand

Close the session — summarize what happened, write a journal entry, and consider updating the mantra. Usage: `done`

### Procedure

1. **Gather session context.** Find the current session and recent work:
   ```sql
   SELECT id, started_at, goals FROM sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1;
   ```
   ```bash
   git log --oneline --since='<started_at>'
   ```
   Also review conversation context for what was accomplished.

2. **Write session summary.** Summarize what was attempted, accomplished, and what's left:
   ```sql
   UPDATE sessions SET summary = '<summary>', key_files = '<files>' WHERE id = <session_id>;
   ```

3. **Journal entry.** Write a short journal entry — what happened, what was learned, what surprised you. This is Claude's perspective, not a changelog. Write it conversationally, like a brief note to the next session. Insert it directly, then share it inline with the user.
   ```sql
   INSERT INTO journal (session_id, content)
   VALUES ('<session_id>', '<journal_entry>');
   ```

4. **Mantra check.** Read the current mantra:
   ```sql
   SELECT content FROM mantra LIMIT 1;
   ```
   Did this session surface anything a fresh Claude session would need to know that isn't in CLAUDE.md? New patterns, non-obvious gotchas, shifted assumptions, tricky areas discovered? If yes, update via the **Mantra subcommand** procedure. If it was routine work, skip. Either way, share the current mantra inline with the user so they can see what future sessions will start with.

5. Run **Digest**.

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
5. Confirm both entries. Run **Digest**.

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

## Journal subcommand

Reflect on recent work and consider writing a journal entry. Same as the journal step in `/brain done`, just standalone.

### Procedure

1. Review conversation context and recent commits for what just happened.
2. Write a short journal entry — what happened, what was learned, what surprised you. This is Claude's perspective, not a changelog. Write it conversationally, like a brief note to the next session.
3. Find the current session, insert directly, then share the entry inline with the user:
   ```sql
   SELECT id FROM sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1;
   INSERT INTO journal (session_id, content) VALUES ('<session_id>', '<content>');
   ```

---

## Mantra subcommand

Reflect on recent work and consider updating the mantra. Same as the mantra check in `/brain done`, just standalone. The mantra is Claude's self-authored context — what matters that CLAUDE.md doesn't say. Patterns, non-obvious knowledge, tricky areas, current momentum, working assumptions.

### Procedure

1. Read the current mantra:
   ```sql
   SELECT content, updated_at FROM mantra LIMIT 1;
   ```
2. Review conversation context and recent work. Ask: did this session surface anything a fresh Claude session would need to know that isn't in CLAUDE.md? New patterns, non-obvious gotchas, shifted assumptions, tricky areas discovered?
3. If nothing meaningful to add, say so and skip. Don't update for routine work.
4. If updating, show the proposed new mantra to the user first.
3. Update:
   ```sql
   UPDATE mantra SET content = '<narrative>', updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime');
   ```
   If no row exists: `INSERT INTO mantra (content, updated_at) VALUES ('<narrative>', strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'));`
4. Export to `cowork/brain/MANTRA.md`:
   ```markdown
   <!-- Auto-generated from BRAIN.db mantra table. Do not edit directly — use /brain mantra to update. -->
   # Mantra

   {narrative}
   ```
5. Update the `<!-- BEGIN:mantra -->` block in CLAUDE.md with the same content. If the block doesn't exist yet, append it after the Brain section.
6. Confirm.

---

## Digest subcommand

Regenerate `cowork/brain/BRAIN.md` — a single read-only markdown snapshot combining knowledge and tasks for browsing.

### Procedure

1. **Recalculate tiers** — run the full two-phase tier recalculation from USAGE.md (SQL phase for archived/cold/warm/focus-hot, then shell phase for plan momentum).

2. Query all data for the digest:
   - Mantra (`SELECT content FROM mantra LIMIT 1`)
   - Focus items
   - Active/blocked tasks by pillar
   - Open questions
   - Recent decisions (hot/warm, last 15)
   - Insights (hot/warm)
   - Recent notes (hot/warm, last 10)
   - Milestones (all, chronological)
   - Tier stats

3. Write `cowork/brain/BRAIN.md`:

```markdown
# Brain

> Auto-generated from `cowork/brain/BRAIN.db`. Do not edit — use `/brain` commands.
> Last updated: {YYYY-MM-DD HH:MM}

## Mantra

{content from mantra table, or "No mantra set — run /brain audit to generate."}

## Focus

{focus items with pillar — or "No focus items set"}

## Active Tasks

### {Pillar Name}

- #{id} **{title}** — {body truncated to ~120 chars} `#{tag1}` `#{tag2}`
  {if blocked: Blocked: {reason}}
  {if plan-linked: -> plan NNN}

### {Next Pillar}
...

## Open Questions

{active questions, newest first}

## Recent Decisions

{last 15 decisions with rationale}

## Insights

{hot/warm insights}

## Recent Notes

{last 10 hot/warm notes, truncated}

## Milestones

{all milestones, chronological}

---

{hot} hot / {warm} warm / {cold} cold / {archived} archived
```

4. Each entry renders as:
   ```
   - **{title}** ({date}) — {body truncated to ~150 chars} `#{tag1}` `#{tag2}`
   ```

---

## Shared conventions

- **DB is truth, markdown is view.** Never read from `cowork/brain/BRAIN.md` to determine state — always query the DB.
- **Auto-digest.** Run Digest at the end of any subcommand that modifies data.
- **Normalize tags on every write.** Split by comma, trim, lowercase, sort alphabetically, deduplicate, rejoin. Check existing tags (shown in dynamic context above) before inventing new ones.
- **Set completed_at when marking tasks done.** Always set `completed_at = datetime('now', 'localtime')` — this drives plan momentum detection.
- **Recalculate tiers during Digest.** See the Digest procedure and USAGE.md for the two-phase recalculation (SQL + plan momentum shell).
- **Decisions are permanent.** Don't update a decision — create a new one that supersedes it (`supersedes` column) and mark the old one `superseded` (`superseded_by` column).
- **Questions resolve into decisions.** Use `resolve <id>` to create the linked decision.
- **Decision dependencies.** Use `depends` to track what builds on what.
- **Sessions are auto-logged.** Hooks create/close session rows. Use `/brain done` to close with journal + summary.
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
