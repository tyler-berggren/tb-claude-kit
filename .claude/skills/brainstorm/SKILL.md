---
name: brainstorm
description: Work through an idea conversationally with Claude. All brainstorms are logged in the brain with any decisions, questions, insights, or tasks that emerge.
argument-hint: "[topic or idea] | hater [topic] | [id to revisit] | list | focus"
---

## Recent Brainstorms
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || e.id, e.created_at, e.title, (SELECT count(*) FROM logs c WHERE c.parent_id = e.id) || ' outputs' FROM logs e WHERE e.type = 'note' AND e.tags LIKE '%brainstorm%' ORDER BY e.created_at DESC LIMIT 5;" 2>/dev/null || echo "No brainstorms yet"`

## Recent Decisions & Insights (for context)
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, type, title FROM logs WHERE type IN ('decision','insight') AND status = 'active' ORDER BY created_at DESC LIMIT 8;" 2>/dev/null || echo "None yet"`

---

# Brainstorm

Work through an idea conversationally. Every brainstorm is logged in the brain DB as a note with `brainstorm` tag, and any outputs (decisions, questions, insights, tasks) are linked as children via `parent_id`.

## Input

Optional argument: `$ARGUMENTS`

Dispatch:
- `focus` -> start a **Focus Brainstorm** on the current focus items.
- `hater <topic>` -> start a **Hater Brainstorm** — constructive skepticism to pressure-test the topic.
- `hater` (no topic) -> ask the user what to pressure-test.
- A topic or idea string -> start a **New Brainstorm** on that topic.
- A bare number (e.g. `42`) -> **Revisit** brainstorm entry #42 and continue the conversation.
- `list` -> **List** all brainstorms with their output counts.
- Empty -> ask the user what they'd like to brainstorm.

---

## New Brainstorm

### Step 1 — Create the brainstorm entry

Insert a note to anchor the session:
```sql
INSERT INTO logs (type, title, body, tags, importance)
VALUES ('note', '<topic title>', 'Brainstorm session started.', 'brainstorm', 5);
```

Note the new entry's id — all outputs from this session link back to it via `parent_id`.

### Step 2 — Set context

Before diving in, gather relevant context:

1. Check the brain DB for related entries (decisions, questions, insights, prior brainstorms):
   ```sql
   SELECT id, type, title, substr(body, 1, 200) FROM logs
   WHERE (title LIKE '%<keyword>%' OR body LIKE '%<keyword>%' OR tags LIKE '%<keyword>%')
   AND status = 'active' ORDER BY created_at DESC LIMIT 10;
   ```
2. Check the codebase if the topic relates to implementation.
3. Briefly present what you found — prior thinking on this topic, related decisions, open questions.

### Step 3 — Brainstorm conversationally

This is a back-and-forth, not a monologue. Follow these principles:

- **Think out loud.** Share reasoning, not just conclusions. Surface assumptions.
- **Be opinionated but holdable.** Offer a clear perspective, but hold it loosely. Push back on weak ideas; build on strong ones.
- **Ask questions.** Don't just answer — probe. "What if we..." and "Have you considered..." are more valuable than lengthy analysis.
- **Stay concrete.** Tie abstract ideas to specific implementation, user scenarios, or project constraints. Reference the codebase and brain entries when relevant.
- **Diverge then converge.** Early in the brainstorm, explore widely. As clarity emerges, narrow toward decisions and actions.
- **Keep it moving.** Each response should advance the conversation. If you're restating the same ground, pivot or propose a decision point.

### Step 4 — Capture outputs as they emerge

As the conversation produces clear outputs, log them immediately — don't wait until the end. Each output is a new entry with `parent_id` pointing to the brainstorm note:

**Decisions:**
```sql
INSERT INTO logs (type, title, body, tags, parent_id)
VALUES ('decision', '<what was decided>', '<rationale>', '<tags>', <brainstorm_id>);
```

**Questions surfaced:**
```sql
INSERT INTO logs (type, title, body, tags, parent_id)
VALUES ('question', '<the question>', '<context for why it matters>', '<tags>', <brainstorm_id>);
```

**Insights:**
```sql
INSERT INTO logs (type, title, body, tags, parent_id)
VALUES ('insight', '<the insight>', '<supporting reasoning>', '<tags>', <brainstorm_id>);
```

**Tasks identified:**
```sql
INSERT INTO logs (type, title, body, tags, pillar, parent_id)
VALUES ('task', '<actionable task>', '<context and acceptance criteria>', '<tags>', '<pillar>', <brainstorm_id>);
```

Announce each capture briefly: "Logged decision #N: ..." so the user knows it's recorded without breaking flow.

### Step 5 — Close the brainstorm

When the conversation reaches a natural stopping point (or the user signals done):

1. Update the brainstorm entry's body with a summary:
   ```sql
   UPDATE logs SET body = '<summary of what was discussed and concluded>'
   WHERE id = <brainstorm_id>;
   ```
2. Count and report outputs:
   ```sql
   SELECT type, count(*) FROM logs WHERE parent_id = <brainstorm_id> GROUP BY type;
   ```
3. Present a brief wrap-up: what was explored, what was decided, what questions remain open, and what tasks were created.
4. Run the brain digest to update `cowork/brain/BRAIN.md`.

---

## Focus Brainstorm

Start a brainstorm session anchored to the current focus items. Usage: `/brainstorm focus`

### Procedure

1. Load focus items:
   ```sql
   SELECT id, type, title, body, tags, pillar FROM logs
   WHERE focus = 1 AND status = 'active';
   ```

2. Load related context — recent decisions, insights, and open questions connected to these focus items:
   ```sql
   SELECT id, type, title, substr(body, 1, 200) FROM logs
   WHERE status = 'active' AND type IN ('decision', 'insight', 'question')
   ORDER BY created_at DESC LIMIT 15;
   ```

3. Create a brainstorm entry that references the focus items:
   ```sql
   INSERT INTO logs (type, title, body, tags, importance)
   VALUES ('note', 'Focus brainstorm: <combined topic from focus items>',
     'Brainstorm session on current focus items: <list titles and IDs>.',
     'brainstorm,focus', 7);
   ```

4. Present the focus items, their descriptions, and related context. Then ask the user which focus item to start with, or whether to tackle them together (if they're related).

5. Proceed with brainstorming (Steps 3-5 from New Brainstorm above). Keep the conversation grounded in the focus items — when outputs emerge, note which focus task they advance.

---

## Hater Brainstorm

Pressure-test an idea like a skeptical investor or CTO would. Usage: `/brainstorm hater <topic>`

The goal is not to kill ideas — it's to make them stronger by surfacing risks, edge cases, and gaps in thinking before they become expensive surprises.

### Procedure

Follow the same Steps 1, 2, 4, and 5 as **New Brainstorm**, with these modifications:

**Step 1 — Create the brainstorm entry** with tags `brainstorm,hater`:
```sql
INSERT INTO logs (type, title, body, tags, importance)
VALUES ('note', 'Hater: <topic title>', 'Hater brainstorm — pressure-testing assumptions.', 'brainstorm,hater', 6);
```

**Step 3 — Brainstorm with a skeptic's lens.** Replace the standard principles with:

- **Default to doubt.** Assume the idea has a fatal flaw you haven't found yet. Your job is to find it — or confirm it's not there.
- **Attack the assumptions, not the person.** Every plan rests on beliefs about the market, the user, the tech, the timeline. Name those beliefs explicitly, then stress-test each one. "This assumes X — what if X is wrong?"
- **Ask the investor questions.** "What's the failure mode?", "Who else has tried this and what happened?", "What's the second-order effect?", "What does this look like at 10x scale?", "Where's the hidden cost?"
- **Find the edge cases.** The happy path is easy. Probe the unhappy paths — the user who doesn't fit the model, the technical constraint that only shows up at scale, the regulatory angle nobody mentioned.
- **Be specific about risk.** Don't say "this could be risky." Say "if churn exceeds 30% in month 2, this unit economics model breaks because..." Concrete scenarios, not vibes.
- **Steel-man before you attack.** Before poking a hole, show you understand why the idea is compelling. Then explain why that's not enough.
- **Every criticism carries a suggestion.** Never raise a risk without proposing at least one way to address it. "This breaks if X" is incomplete — "This breaks if X; you could mitigate by Y or validate with Z" is the standard. Unproductive negativity is a bug.
- **Flag research gaps honestly.** When a risk or decision hinges on something neither of us actually knows — market data, technical benchmarks, competitor behavior, legal constraints — say so and suggest a `/research` topic. Don't pretend to have the answer and don't assume the user does either. Before suggesting research, check `cowork/research/` for existing reports that already cover the topic. If a report exists, reference it instead of proposing redundant work.
- **Converge on what survives.** The output isn't a graveyard of killed ideas — it's a ranked list of risks with severity and mitigation options, a set of questions that need answers before committing, and the core thesis restated with its actual (not imagined) strength.

---

## Revisit

Continue a prior brainstorm. Usage: `/brainstorm <id>`

### Procedure

1. Load the brainstorm entry and all its children:
   ```sql
   SELECT id, type, title, body, tags FROM logs WHERE id = <id>;
   SELECT id, type, title, body, tags, status FROM logs WHERE parent_id = <id> ORDER BY created_at;
   ```
2. Present the state: original topic, summary, and all outputs (decisions, questions, insights, tasks) with their current status.
3. Ask the user what aspect they want to revisit or continue.
4. Resume brainstorming — new outputs still link to the same parent via `parent_id`.

---

## List

Show all brainstorms with output counts. Usage: `/brainstorm list`

### Procedure

1. Query:
   ```sql
   SELECT e.id, e.created_at, e.title,
     (SELECT count(*) FROM logs c WHERE c.parent_id = e.id) as outputs,
     (SELECT group_concat(DISTINCT c.type) FROM logs c WHERE c.parent_id = e.id) as output_types
   FROM logs e
   WHERE e.type = 'note' AND e.tags LIKE '%brainstorm%'
   ORDER BY e.created_at DESC;
   ```
2. Present as a list with id, date, title, and output summary. Highlight any with open questions.

---

## Global rules

- **No permission needed** — Execute immediately without asking.
- **Log as you go** — Capture outputs during the conversation, not after. The brain DB is the record.
- **Link everything** — Every output entry must have `parent_id` set to the brainstorm entry's id.
- **Normalize tags** — Split by comma, trim, lowercase, sort alphabetically, deduplicate, rejoin. Check existing tags (shown in dynamic context above) before inventing new ones.
- **DB is truth** — Never read from `cowork/brain/BRAIN.md` to determine state. Always query the DB.
- **Decisions are permanent** — Don't update a decision entry. If thinking changes, create a new decision that supersedes it (set `supersedes` column, mark old one `superseded`).

---

## Project overrides

If `.claude/kit.json` has a `rules."brainstorm"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."brainstorm" // empty' .claude/kit.json 2>/dev/null
```
