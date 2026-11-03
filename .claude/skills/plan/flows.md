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

   | Phase | Where | Status | Notes |
   |---|---|---|---|
   | 1. <name> | <plan>:<start>-<end> | done | <short note> |
   | 2. <name> | <plan>:<start>-<end> | done | <short note> |
   | 3. <name> | <plan>:<start>-<end> | open | next up |
   | ... | ... | ... | ... |

   **Deferred items**: <list any deferred/skipped items, each with its line>
   **Bonus work**: <any work done this session beyond the plan>
   **Next up**: Phase N — <what's next> (<plan>:<line> of the RESUME banner)
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
   **{{change summary}}** · <plan>:<line>
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
