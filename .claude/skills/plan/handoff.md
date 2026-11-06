## Handoff Flow

Get the plan ready for a different agent to take over: a fresh session, a cloud session, a
teammate's agent, or `/swarm`. That agent sees the repo and this file, not this conversation, so
anything that matters and lives only in the conversation is lost unless it goes into the plan.
Handoff leaves the plan **current**, **clean**, and **carrying that context**.

Usage: `handoff` (uses the currently bound plan), or a plan ref + `handoff` (`003 handoff`, `mvp 001 handoff`)

### Step H1 — Load

Resolve, read and bind the plan as in R1. With no plan bound and no ref given, use the plan this
session has been editing; if that is not clear, ask. That is the only question. Everything else
runs without stopping.

### Step H2 — Bring it current

Check every claim against the code and `git`, not against your memory of the session:

- Tick every item this session finished, with ` — done: <note>`, and mark finished phases
  `**Status:** done`. Verify each one first: the change is in the code, and the test that proves
  it has passed. Code that is written but untested stays open, with a note saying so.
- On the item in progress, write what is done and what is left.
- Work that happened but was never an item goes in as a new, ticked item (see **New items**).
- Place exactly one RESUME WORK HERE banner, on the first open item.
- Bring `## Work ahead` current (the plan skill's `autopilot.md`): the next runnable items, ranked, each with its line and what it waits on.

### Step H3 — Capture what only this conversation knows

Go back through the conversation for anything the next agent would otherwise get wrong, redo,
or have to ask about:

- **Constraints** — instructions from the user that shaped the work: scope changes, things to
  avoid, preferences, who reviews what. Quote the user when their words are the reason.
- **Decisions** — what was decided and why, and the alternative that lost.
- **Dead ends** — approaches tried and abandoned, with what happened (the error, the
  measurement), so nobody tries them again.
- **Gotchas** — non-obvious facts learned the hard way: a flaky test, a required env var, a
  command that works where the obvious one fails.
- **State** — branch and the worktree path it is checked out in, uncommitted or unpushed work, stashes, open PRs and their
  review state, running servers, migrations or data changes applied, deploys, messages sent;
  and what was verified (command and result) versus not yet verified.
- **Open questions** — who answers each one, and the default assumed until they do.
- **Waiting on the owner** — critical parks that hold work, then calls made and items left
  unverified this session that nobody has read yet.

Leave out what the plan already says, what the code or `git log` shows in a minute, and the
story of the session. Never write a secret; say where it lives instead.

Put each finding where the next agent will look for it:

- About one item -> on that item, as a note or sub-bullet.
- Outlives this plan (a project-wide convention, a tool quirk) -> the brain DB as an `insight`,
  not the plan.
- A decision -> the Handoff section's **Decisions** (in PR mode, the **Decisions taken** table
  instead), and the brain DB as a `decision` entry with `plan_id` and `plan_path` in `meta`.
- A question for the owner -> `## Open questions`; a call, an unverified item or a critical park -> `## Review`
  (see **Batches**), tidied and numbered.
- Everything else -> the Handoff section.

The Handoff section sits directly under the plan's title. Each handoff rewrites it instead of
appending: carry forward what is still true, drop what no longer holds, and leave out any empty
part except **State** and **Next**.

```markdown
## Handoff

**Updated:** YYYY-MM-DD · **Resume at:** <phase or PR> — <the item under the RESUME banner>

**State**
- Branch `<branch>` at `<sha>` in `<worktree path, or the primary checkout>`; uncommitted: <paths, or none>; unpushed: <count, or none>
- Running or half-applied: <servers, migrations, deploys, open PRs, or nothing>
- Verified: <command -> result>; not yet verified: <what>

**Next:** <the first concrete action: file, function, command>

**Constraints**
- <instruction> — <from whom, and why>

**Decisions**
- <decision> — <why>; not <alternative>, because <reason>

**Dead ends**
- <approach> — <what happened>

**Gotchas**
- <fact>

**Open questions**
- <question for someone other than the owner> — <who answers>; assuming <default> until then
```

The owner's own questions and review items are not repeated here: they live in `## Open
questions` and `## Review`, and **Next** says when either holds something.

In PR mode the plan travels with every PR, so the snapshot opens the existing ground-rules
handoff section (P3, item 5) instead of adding a new one, and meets the same reviewer standard
as the rest of the plan: plain terms, no private references.

**Keep it to a screen.** Work cut into same-day slices hands off at a slice boundary, where the
open PR already carries most of the state. A Handoff section that runs past a screen means the
work in flight is too big or the section is carrying history — move history onto the items it
concerns, or drop it.

### Step H4 — Clean up

The plan should read as one coherent document, not a trail of session notes. Clean-up removes
noise, never history:

- Fold scratch notes, reminders-to-self and duplicate bullets into the item or section they
  belong to.
- Where a decision changed the approach, rewrite the affected open items to match. Completed
  items keep their text, with a note if the new direction makes them misleading.
- Correct paths, names and line numbers this session proved stale.
- Amend **Context** or **Verification** only where this session proved them wrong, in place,
  with `(corrected YYYY-MM-DD: …)`. Handoff counts as the explicit request the **Context is
  sacred** rule asks for, for corrections only.
- Leave `{{bracketed}}` proposals as they are and list them under **Open questions**, so the
  next session runs `/plan review`.
- Never delete a completed item or its note.

### Step H5 — Cold read

Read the plan top to bottom as the next agent will: no memory of this conversation, only this
file and the repo. Every question you would have to ask before starting is a gap; answer it in
the plan. When subagents are available, a fresh one is the better reader: give it only the plan
path, tell it to change nothing, ask what it would do first and what it would need to know, and
fill each gap it names.

### Step H6 — Sync, commit, report

1. Sync the brain DB as in the **Update Flow**.
2. Commit the plan file in the repo that holds it (`Plan <id>: handoff — <one line>`). Finished,
   tested code goes in the same commit under the usual rule; half-done code stays uncommitted,
   and **State** says so.
3. Report:

   ```
   **Plan NNN — ready for handoff**

   Resume with: `/plan NNN` -> <phase or PR> — <item> (<plan>:<line>)
   Captured: <count per part of the Handoff section> (<plan>:<start>-<end>)
   Corrected: <stale claims fixed, each with its line, or none>
   Open for you: <open questions and uncleared review items, each with its line, or none>
   Left uncommitted: <paths, or none>
   ```

### Rules

- **Records, never builds.** Handoff verifies, writes and tidies. It does not start the next item.
- **Critical means the next agent would act differently without it.** If you're unsure whether a fact belongs, check whether the code or `git log` already shows it. If it does, leave it out.
- **Safe to repeat.** The Handoff section is rewritten each time, so running handoff twice
  duplicates nothing.
