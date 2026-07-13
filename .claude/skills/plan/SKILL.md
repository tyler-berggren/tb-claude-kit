---
name: plan
description: Generate a new plan or resume an existing one. Number arg -> resume with fresh-eyes reconciliation. "NNN brainstorm" -> brainstorm through phases before building. Topic/no arg -> generate from brain DB tasks and codebase context.
argument-hint: "[plan number | NNN brainstorm | topic | update | carry | status | review]"
---

## Available Plans
!`ls -1 cowork/plans/*.md 2>/dev/null | grep -v .gitkeep || echo "No plans yet"`

## Active Plan-Linked Tasks
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, title, json_extract(meta, '$.plan_id') as plan FROM logs WHERE type = 'task' AND status = 'active' AND meta LIKE '%plan_id%';" 2>/dev/null || echo "No plan-linked tasks"`

---

# Plan

Generate a new plan or resume an existing one. Routing is based on the argument:
- **Number matching an existing plan** -> Resume flow (fresh-eyes reconciliation + execution)
- **Number + `brainstorm`** (e.g. `013 brainstorm`) -> Brainstorm flow (flesh out loose phases conversationally before building)
- **`update`** -> Sweep completed plan items and mark brain DB tasks done
- **`carry`** -> Sweep unfinished plan items back to brain DB
- **`status`** -> Status check of the current session's bound plan (or most recent active plan)
- **`review`** -> Review user's `{{bracketed}}` proposed changes to the bound plan
- **Topic, description, or no argument** -> Generate flow (research + brainstorm + write plan file)

## Input

Optional argument: `$ARGUMENTS`

**Resolve as:**
- `update` -> **Update flow**
- `carry` -> **Carry flow**
- `status` -> **Status flow**
- `review` -> **Review flow**
- A bare number (`003`) that matches an existing plan file -> **Resume flow**
- A number + `brainstorm` (e.g. `013 brainstorm`) -> **Brainstorm flow**
- A filename fragment (`tech-stack-rebuild`) that matches an existing plan -> **Resume flow**
- A full path (`cowork/plans/003_2026-05-10_tech-stack-rebuild.md`) -> **Resume flow**
- A topic, description, task IDs, pillar name, or empty -> **Generate flow**

---

## Generate Flow

Create a new plan from brain DB tasks, codebase context, and conversation.

### Step G1 — Gather context

1. If the argument references specific tasks, pillars, or tags, query them:
   ```sql
   -- By pillar
   SELECT * FROM logs WHERE type = 'task' AND status = 'active' AND pillar = '<ref>';
   -- By tag
   SELECT * FROM logs WHERE type = 'task' AND status = 'active' AND tags LIKE '%<ref>%';
   -- By title
   SELECT * FROM logs WHERE type = 'task' AND status = 'active' AND title LIKE '%<ref>%';
   -- By id(s)
   SELECT * FROM logs WHERE id IN (<ids>);
   ```
   If ambiguous, list candidates and ask.
2. If the argument is a broad topic or empty, query recent active tasks and decisions for context:
   ```sql
   SELECT id, type, title, body, pillar, tags FROM logs
   WHERE status = 'active' AND type IN ('task', 'decision', 'question')
   ORDER BY created_at DESC LIMIT 20;
   ```
3. **Reconcile with codebase.** For each relevant task, verify file paths and symbols still exist. Flag stale items.
4. Check existing plans to avoid overlap:
   ```sql
   SELECT id, title FROM logs
   WHERE type = 'task' AND status = 'active' AND json_extract(meta, '$.plan_id') IS NOT NULL;
   ```

### Step G2 — Brainstorm the plan

Present the proposed plan to the user. Do NOT write any files yet.

**Format:**
```
**Proposed Plan: <Title>**

**Source tasks:**
- #<id> — <title> (pillar: <pillar>)

**Scope:**
<2-3 sentences on what this plan covers and why>

**Proposed phases:**
1. <Phase name> — <1-line description>
2. ...

**Out of scope:**
- <items explicitly excluded>

**Verification:**
- <concrete test for each phase>
```

Wait for user approval or redirection before writing.

### Step G3 — Write the plan file

1. Determine the next plan number from `cowork/plans/`. Filename: `NNN_YYYY-MM-DD_topic.md`.
   The plan number `NNN` is zero-padded (e.g., `004`).
2. Write the plan file:
   - `# Plan: <Title>`
   - `## Source` — manifest linking each task by DB id:
     ```
     - entry #4 — **Task title** (pillar: pillar-name)
     - entry #5 — **Task title** (pillar: pillar-name)
     ```
   - `## Context` — background, motivation, current state
   - `## Build Order` — phased breakdown with `- [ ]` checkboxes for each item
   - `## Out of Scope`
   - `## Verification` — concrete test per phase
3. Update each source task's meta with the plan link:
   ```sql
   UPDATE logs SET meta = json_set(COALESCE(meta, '{}'), '$.plan_id', '<NNN>') WHERE id = <id>;
   ```
   `plan_id` is always a zero-padded string matching the plan filename prefix (e.g., `'003'`, not `3`).
4. Create a brain DB task for each phase:
   ```sql
   INSERT INTO logs (type, title, pillar, status, meta)
   VALUES ('task', 'Plan NNN Phase X: <phase title>', '<pillar>', 'active', '{"plan_id":"<NNN>"}');
   ```
5. Do **not** start implementation. The user will invoke `/plan NNN` to resume and begin execution.

---

## Resume Flow

Resume work on an existing plan. Every invocation begins with a fresh-eyes reconciliation pass — never assume the planning agent was 100% accurate.

### Step R1 — Load and bind

1. Resolve the plan file path.
2. Read the full plan file.
3. **Bind this session to the plan.** For the rest of this conversation, `/plan update` and `/plan carry` default to this plan without requiring a ref.
4. Identify the current state:
   - Which phases are marked `**Status:** done`?
   - Which phases have a mix of `- [x]` and `- [ ]`?
   - Is there an existing RESUME WORK HERE banner? If so, note its location — that's where the last session stopped.

### Step R2 — Fresh-eyes reconciliation

Do not trust the plan's file paths, function names, line numbers, or assumptions as still-accurate. Verify against the actual codebase:

1. **Verify completed work.** For each `- [x]` item in the active and recent phases:
   - Spot-check that the claimed file/function exists and the described change is present.
   - Flag any `- [x]` items where the code doesn't match the claim.

2. **Verify open items.** For each `- [ ]` item in the next-up phase:
   - Open the files it references. Confirm they still exist and the described state is accurate.
   - Check `git log --since='<plan-date>' -- <referenced-files>` for commits that may have changed assumptions.
   - Note any drift: paths moved, APIs renamed, dependencies added/removed, related work that landed from other plans.

3. **Check for collisions.** Scan recent commits for changes in the plan's area that came from a different plan or session. Flag overlap.

4. **Reconcile with brain DB.** Check plan-linked tasks:
   ```sql
   SELECT id, title, status, meta FROM logs
   WHERE type = 'task' AND json_extract(meta, '$.plan_id') = '<NNN>';
   ```
   `plan_id` is always a zero-padded string matching the plan filename prefix (e.g., `'003'`, not `3`).
   Flag any DB tasks marked done that the plan file still shows as open (or vice versa).

### Step R3 — Brainstorm

Present findings to the user. Do NOT make any file edits yet.

**Format:**

```
**Plan NNN / Phase X — <phase title>**

**Reconciliation:**
- completed work verified against codebase
- drift or issues found
- brain DB sync status

**Next up:**
- <first open item> — <current state assessment>
- <second open item> — <any blockers or prerequisites noted>

**Proposed approach:**
<2-3 sentences on how to tackle the next phase, informed by the reconciliation>
```

Wait for user approval or redirection before proceeding to any implementation.

### Step R4 — Announce in replies

Once the user approves and work begins, prefix every subsequent response in this session with a short header:

```
**Plan NNN / Phase X**
```

This reminds the user which plan this session is bound to and makes conversation history scannable.

---

## Brainstorm Flow

Flesh out a loose plan conversationally, phase by phase, before building. Use when a plan exists as a first draft with rough phases that need design work before they're concrete enough to execute.

Usage: `<NNN> brainstorm` (e.g. `013 brainstorm`)

### Step B1 — Load and bind

Same as Resume flow R1: resolve plan file, read it, bind the session.

### Step B2 — Assess plan maturity

For each phase, classify its items:
- **Concrete** — specific enough to execute (file paths, API shapes, clear implementation steps)
- **Loose** — directionally correct but needs design decisions (e.g. "config schema" without specifying what the schema looks like)
- **Unknown** — open questions that need research or brainstorming before items can be written

Present a quick summary:
```
**Plan NNN — Brainstorm Mode**

Phase 1 — <title>: 3 concrete, 2 loose, 0 unknown
Phase 2 — <title>: 1 concrete, 4 loose, 1 unknown
...

Starting with Phase <X> (first phase with loose/unknown items).
```

If all phases are concrete, suggest switching to Resume flow instead.

### Step B3 — Phase-by-phase brainstorm

Work through one phase at a time, starting with the first phase that has loose or unknown items.

For each phase:

1. **Present the phase** — show all items, flag which are loose/unknown, note related brain DB entries and codebase state.
2. **Brainstorm conversationally** — same principles as `/brainstorm`: think out loud, be opinionated, ask questions, stay concrete, diverge then converge. Focus on:
   - API design (function signatures, config shapes, data models)
   - Architecture decisions (where does this code live, how does it interact with existing code)
   - Edge cases and unknowns that need resolution
   - Build order within the phase
3. **Capture outputs to brain DB** — as decisions, insights, and questions emerge, log them immediately (same as `/brainstorm` Step 4). Link to the plan's brainstorm entry or create one if needed.
4. **Update the plan file** — rewrite the phase's items to be concrete based on the brainstorm. Replace loose items with specific implementation steps. Add new items that emerged. Mark resolved questions.
5. **User confirms** — present the updated phase and get approval before moving to the next phase.

### Step B4 — Transition to execution

After brainstorming through a phase (or set of phases), ask the user:
- **Continue brainstorming** the next phase, or
- **Switch to execution** on the now-concrete phases (transitions to Resume flow behavior — reconciliation + build)

The plan file is updated as you go, so a future session can pick up where you left off regardless of which mode you were in.

### Behavioral rules for brainstorm mode

- **Don't write code.** Brainstorm mode is for design, not implementation. If you find yourself reaching for Edit/Write on source files, you've left brainstorm mode — stop and ask if the user wants to switch to execution.
- **Update the plan file liberally.** The plan is the artifact. Every brainstorm conclusion should be reflected in more concrete plan items.
- **Log decisions to brain DB.** Design decisions made during brainstorm are durable — they outlive the plan. Use `parent_id` linking to the brainstorm or plan-linked entries.
- **One phase at a time.** Don't brainstorm Phase 4 before Phase 1 is concrete, unless the user explicitly jumps ahead. Earlier phases inform later ones.
- **Codebase research is encouraged.** Read files, grep for patterns, check existing implementations. The goal is to ground the brainstorm in reality, not speculate in the abstract.

---

## During the session

While working on a plan, follow these rules:

### Editing the plan file

- **Preserve, don't delete.** Completed items are marked `- [x]` with a progress note; they are never removed. The plan file doubles as an execution log.
- **Preserve structure.** Keep the plan's top-level sections (`Source`, `Context`, `Build Order`, `Out of scope`, `Verification`) and phase ordering intact.
- **Status at the phase level.** When a whole phase is done, add a `**Status:** done — <short note>` line at the top of that phase section.
- **Context is sacred.** Don't rewrite the `Source`, `Context`, or `Verification` sections unless the user explicitly asks.
- **Progress notes on items.** When completing an item, append ` — done: <1-line note>` on the same line. Example: `- [x] **Add TipTap deps** — done: installed @tiptap/react + 6 extensions`
- **New items.** If work surfaces that wasn't in the plan, add it to the end of the relevant phase or as a new trailing phase. Don't insert into completed phases.

### Behavioral rules

- **Brainstorm before editing code.** Before starting each phase or major item, briefly state your approach and wait for user confirmation.
- **Update the plan file before every commit.** Before staging and committing, update the plan file to reflect current progress:
  1. Mark completed items `- [x]` with progress notes.
  2. Add `**Status:** done — <short note>` to completed phases.
  3. Place a RESUME WORK HERE banner on the first open item. Move the banner forward as work progresses — there should be exactly one in the file at all times during an active session.
  4. If stopping mid-phase, note exactly what's done and what's next on the first open item.
  5. Include the plan file in the commit alongside the code changes.
- **Commit after each chunk of work.** After completing a phase, a logical group of items, or any meaningful chunk of work, commit the code changes AND the updated plan file together. Don't batch everything into one giant commit at the end.
- **Sync brain DB.** When completing a plan item that has a linked task in the DB, mark the DB task done:
  ```sql
  UPDATE logs SET status = 'done', completed_at = datetime('now', 'localtime'),
    body = body || char(10) || '--- Completed in plan <NNN>'
  WHERE id = <task_id>;
  ```

---

## Update Flow

Sweep the bound plan's completed items and mark corresponding brain DB tasks done.

Usage: `update` (uses the currently bound plan, or asks which plan)

### Procedure

1. Identify the bound plan (from current session context, or ask the user).
2. Read the plan's `## Source` manifest to get task ids.
3. For each manifest entry where the plan item is `- [x]`:
   - Mark the DB task done:
     ```sql
     UPDATE logs SET status = 'done', completed_at = datetime('now', 'localtime'),
       body = body || char(10) || '--- Completed in plan <NNN>' WHERE id = <id>;
     ```
4. For items still `- [ ]`: leave the DB task as-is.
5. Report: which tasks marked done, which still open.
6. Run `/brain digest`.

---

## Carry Flow

Sweep unfinished plan items back into the brain DB. Run when closing out a plan.

Usage: `carry` (uses the currently bound plan, or asks which plan)

### Procedure

1. Identify the bound plan.
2. Read the plan. Collect all unfinished items (`- [ ]`, out of scope, deferred).
3. **Propose routing.** For each unfinished item:
   - **(a) Already in brain** — the task exists in DB and is still active. Just clear the `plan_id` from meta.
   - **(b) New task** — the plan surfaced work not originally in the brain. Propose a pillar and create a new entry.
   - **(c) Big enough for its own plan** — flag for the user.
4. Present the routing table. Wait for approval.
5. On approval:
   - For existing tasks: clear `plan_id`, update body with carry note.
   - For new tasks: insert with `meta: {"from_plan": "NNN"}` and appropriate pillar.
   - In the plan file: annotate carried items.
6. Run `/brain digest`.

### Rules

- **Never drop items.** Every unfinished item routes somewhere.
- **Breadcrumbs.** The plan notes where items went; DB entries note where they came from.

---

## Status Flow

Quick status check of the currently bound plan (or the most recent active plan if no plan is bound this session).

Usage: `status`

### Procedure

1. **Identify the plan.** Use the bound plan from the current session. If none is bound, find the most recent active plan:
   ```sql
   SELECT id, title, meta FROM logs
   WHERE type = 'task' AND status = 'active' AND json_extract(meta, '$.plan_id') IS NOT NULL
   ORDER BY created_at DESC LIMIT 1;
   ```
   Read that plan file.

2. **Scan phases.** For each phase, classify:
   - **Done** — has `**Status:** done` marker
   - **In progress** — has a mix of `- [x]` and `- [ ]` items
   - **Open** — all items are `- [ ]`
   - **Carried/Deferred** — explicitly marked as carried or deferred

3. **Present a summary table.** Format:

   ```
   **Plan NNN: <Title>**

   | Phase | Status | Notes |
   |---|---|---|
   | 1. <name> | done | <short note> |
   | 2. <name> | done | <short note> |
   | 3. <name> | open | next up |
   | ... | ... | ... |

   **Deferred items**: <list any deferred/skipped items>
   **Bonus work**: <any work done this session beyond the plan>
   **Next up**: Phase N — <what's next>
   ```

4. **Do NOT start any work.** Status is read-only. If the user wants to resume, they run `/plan <NNN>`.

---

## Review Flow

Review user-proposed changes to a plan. The user marks their proposed edits with `{{double curly braces}}` in the plan file, then runs `/plan review`. Claude reviews the bracketed changes for clarity, feasibility, and coherence with the rest of the plan.

Usage: `review` (uses the currently bound plan, or asks which plan)

### Procedure

1. **Identify the plan.** Use the bound plan from the current session. If none is bound, check if there's only one plan with `{{` markers — use that. Otherwise ask.

2. **Read the plan file.** Scan for all `{{...}}` bracketed sections. These are the user's proposed changes — they may be additions, replacements, rewrites, or annotations.

3. **For each bracketed change, assess:**
   - **Clarity** — Is the item specific enough to execute? Does it need more detail, file paths, or acceptance criteria?
   - **Feasibility** — Is this realistic given the tech stack, timeline, and existing architecture? Flag anything that sounds simple but is actually complex (or vice versa).
   - **Coherence** — Does this change conflict with or duplicate other plan items? Does it belong in the phase it's placed in, or should it move? Does it affect downstream phases?
   - **Completeness** — Did the change introduce new dependencies or prerequisites that aren't accounted for elsewhere in the plan?

4. **Present the review.** For each bracketed change:
   ```
   **{{change summary}}**
   ✓ Looks good / ⚠ Suggestion / ✗ Issue

   <1-3 sentences of feedback>
   ```

5. **Propose final edits.** After reviewing all changes:
   - Offer to accept all brackets as-is (remove the `{{}}` markers, keep the content)
   - Suggest specific rewrites for any items flagged with issues
   - Flag any new items that should be added elsewhere in the plan as a consequence

6. **On user approval:** Remove all `{{}}` markers from the plan file — either accepting the content as-is or applying the agreed rewrites. The plan should have zero `{{}}` markers when done.

### Rules

- **User's intent wins.** The brackets represent what the user wants. Don't reject outright — improve and integrate.
- **Don't rewrite unprompted.** Only modify content inside or directly adjacent to `{{}}` markers. Leave the rest of the plan untouched.
- **Flag scope creep.** If a bracketed change significantly expands scope, note it explicitly so the user can make a conscious decision.

---

## Global rules

- **No permission needed** — Execute immediately without asking.
- **Fresh eyes are mandatory** — Every `/plan` invocation does the reconciliation pass, even if you were just working on this plan 5 minutes ago.
- **One plan per session** — A session binds to one plan at a time. If the user wants to switch, they run `/plan <different-ref>` which rebinds.
- **The plan file is a baton.** Every edit should serve the handoff to the next session. A future Claude — with zero memory of this conversation — will open this file cold and need to resume within a minute.
