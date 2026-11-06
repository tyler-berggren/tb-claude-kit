---
name: plan
description: Generate a new plan or resume an existing one. Number arg -> resume with fresh-eyes reconciliation. "NNN brainstorm" -> brainstorm through phases before building. "pr <topic>" or "NNN pr" -> PR mode, a plan for a team repo cut into same-day slices, one small pull request each. "NNN epic" -> publish or sync a PR-mode plan's epic and slice issues on the team's tracker, so the team sees the workstream and who it touches before any code. "NNN issue <slice>" or "issue <topic>" -> create or bring current one issue. "handoff" or "NNN handoff" -> get the plan ready for another agent to take over: current, cleaned up, and holding the critical context that so far exists only in this conversation. Supports scoped plan directories via for:<scope>. Topic/no arg -> generate from brain DB tasks and codebase context.
argument-hint: "[plan number | scope NNN | for:<scope> topic | NNN brainstorm | pr topic | NNN pr | NNN epic | NNN issue <slice> | issue topic | topic | update | carry | status | review | handoff | NNN handoff]"
---

## Available Plans
!`ROOTS=$(jq -r '.plan.roots[]?' .claude/kit.json 2>/dev/null); [ -z "$ROOTS" ] && ROOTS="cowork/plans"; OUT=$(echo "$ROOTS" | while IFS= read -r r; do find . -path "./$r/*.md" -not -name '.gitkeep' 2>/dev/null; done | sed 's|^\./||' | sort); [ -n "$OUT" ] && echo "$OUT" || echo "No plans yet"`

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
- **`handoff`** or **`NNN handoff`** -> Prepare the plan for another agent to take over: bring it current, clean it up, and write in the critical context that exists only in this conversation
- **`pr <topic>`** or **`NNN pr`** -> PR mode (see **PR Mode**): Generate or convert, with the plan cut into same-day slices, one pull request each, for a team repo
- **`NNN epic`** -> Epic mode (see **Epic Mode**): publish or sync a PR-mode plan's epic, and its slices as sub-issues, on the team's tracker
- **`NNN issue <slice>`** or **`issue <topic>`** -> Issue mode (see **Issue Mode**): create or bring current one issue — a slice's as it starts, or a standalone one
- **Topic, description, or no argument** -> Generate flow (research + brainstorm + write plan file)

## Input

Optional argument: `$ARGUMENTS`

**Resolve as:**
- `update` -> **Update flow**
- `carry` -> **Carry flow**
- `status` -> **Status flow**
- `review` -> **Review flow**
- `handoff` -> **Handoff flow** on the bound plan; a plan ref + `handoff` (`003 handoff`, `mvp 001 handoff`) -> **Handoff flow** on that plan
- A bare number (`003`) that matches an existing plan file -> **Resume flow**
- A scope + number (`mvp 001`, `data-portal 000`) -> **Resume flow** for that scope's plan
- A number + `brainstorm` (e.g. `013 brainstorm`), optionally scoped (`mvp 001 brainstorm`) -> **Brainstorm flow**
- A filename fragment (`tech-stack-rebuild`) that matches an existing plan -> **Resume flow**
- A full path (`cowork/plans/003_2026-05-10_tech-stack-rebuild.md`, `cowork/plans/mvp/001_seed-profile-design.md`) -> **Resume flow**
- `for:<scope> <topic>` (e.g. `for:data-portal build parcel POC`) -> **Generate flow** scoped to that directory
- `pr <topic>` -> **Generate flow in PR mode**; `NNN pr` -> **Resume flow**, converting an existing plan to PR mode first (see **PR Mode**)
- A plan ref + `epic` (`004 epic`, `mvp 001 epic`) -> **Epic Mode** on that plan
- A plan ref + `issue <slice>` (`004 issue S3`) -> **Issue Mode** for that slice; `issue <topic>` -> **Issue Mode**, a standalone issue (linked to the bound plan, if any)
- A topic, description, task IDs, pillar name, or empty -> **Generate flow**

**Mode files.** Only Generate and Resume are written out in this file. Every other mode lives in
its own file in this skill's folder. **Before acting in that mode, Read its file in full** —
`<this skill's folder>/<file>.md` — then follow it. This file's shared sections (Plan Scopes,
Pointing at a line, Batches, During the session, Global rules, Project overrides) still apply.

| Mode | Read first |
|---|---|
| `NNN brainstorm` | `<this skill's folder>/brainstorm.md` |
| `pr <topic>`, `NNN pr`, or a resumed plan whose header has `**Mode:** pr` | `<this skill's folder>/pr-mode.md` |
| `NNN epic` | `<this skill's folder>/tracker.md` (Epic Mode, Issue policy), and `<this skill's folder>/pr-mode.md` — its P1 sweep and P5 bodies are what Epic Mode builds on |
| `NNN issue <slice>`, `issue <topic>` | `<this skill's folder>/tracker.md` (Issue Mode, Issue policy), and `<this skill's folder>/pr-mode.md` for the sweep (P1) and body shape (P5) |
| `update`, `carry`, `status`, `review` | `<this skill's folder>/flows.md` |
| `handoff`, `NNN handoff` | `<this skill's folder>/handoff.md`, and `<this skill's folder>/flows.md` for the Update Flow its H6 runs |

---

## Plan Scopes

Plans may live in more than one directory. The roots are configured per project in
`.claude/kit.json`; when the file or key is absent the single root is `cowork/plans`.

```json
{ "plan": { "roots": ["cowork/plans", "cowork/projects/*/plans"] } }
```

Roots may contain `*` wildcards. Plans nested in subdirectories of a root (e.g.
`cowork/plans/mvp/`, `cowork/plans/mvp/testing/`) are found automatically — subdirectories do
not need to be listed.

**Numbering is per-directory.** `cowork/plans/003_*.md` and `cowork/plans/mvp/003_*.md` can
both exist, so a bare `003` is ambiguous whenever more than one root or subdirectory is in play.

### Plan directories

A plan may be a single file, or a **directory** holding the plan plus its companion documents — an
audit, a research report, a findings matrix. Use a directory whenever a plan has supporting material
that belongs with it; the alternative (a sibling `cowork/audits/`, `cowork/matrices/`, … grouped by
document TYPE) scatters one piece of work across the tree and is not how this project files things.

```
cowork/plans/001_2026-09-11_shared-components/
├── 001_2026-09-11_shared-components.md    <- the plan; keeps the NNN_ prefix
└── audit.md                               <- companion; plain descriptive name
```

**A directory whose name matches `NNN_` is a PLAN, not a scope.** This is the rule that keeps the
derivation below from producing `001_2026-09-11_shared-components-001`. Concretely:

- The plan file inside it keeps the full `NNN_YYYY-MM-DD_topic.md` name. That prefix is what the
  Resume fallback scan matches on, so dropping it breaks `/plan NNN`.
- **Exactly one file in a plan directory carries the `NNN_` prefix.** Companions take plain names
  (`audit.md`, `research.md`), or the scan finds two candidates for one plan.
- A plan directory contributes its own `NNN` to its PARENT's numbering. When picking the next
  number, count `NNN_` directories alongside `NNN_` files — otherwise the next plan reuses the
  number.

**Sub-plans carved out of a plan get a letter suffix, inside the parent's directory.** When part
of a plan is refocused into its own narrower plan, it is `NNNa` (then `NNNb`, …), not a new
number or a scope: directory `cowork/plans/NNN_…/NNNa_<topic>/`, plan file `NNNa_YYYY-MM-DD_<topic>.md`,
`plan_id` `NNNa`. The number itself shows the lineage. Companions sit beside it as usual.

**`plan_id` is `<scope>-<NNN>`**, where scope is the plan's directory identity:

| Plan file | scope | `plan_id` |
|---|---|---|
| `cowork/plans/003_2026-05-10_rebuild.md` | *(none — directly in a root)* | `003` |
| `cowork/plans/001_2026-09-11_shared/001_2026-09-11_shared.md` | *(none — a plan DIRECTORY in a root)* | `001` |
| `cowork/plans/mvp/001_seed-profile.md` | `mvp` | `mvp-001` |
| `cowork/plans/mvp/001_seed/001_seed.md` | `mvp` | `mvp-001` |
| `cowork/plans/mvp/testing/001_proof.md` | `mvp-testing` | `mvp-testing-001` |
| `cowork/projects/data-portal/plans/000_poc.md` | `data-portal` | `data-portal-000` |

Derivation: for a plan sitting directly in a configured root, there is no scope. For a plan in a
subdirectory of a root, scope is the relative path from that root with `/` replaced by `-` —
**skipping any path segment that is itself a plan directory** (matches `NNN_`), since that segment
names the plan rather than a scope. For a root containing wildcards, scope is the last
wildcard-matched segment.

**`meta.plan_path` is authoritative.** Always store the plan's full repo-relative path in
`meta.plan_path`. `plan_id` is a human handle for the command line and can collide across roots;
`plan_path` cannot. Resume resolves by `plan_path` first and only falls back to scanning.

**Filenames.** New plans always get the date: `NNN_YYYY-MM-DD_topic.md`. Older plans may omit it
(`NNN_topic.md`) — match on the `NNN_` prefix when resolving so both forms work. Never rename an
existing plan to fit the convention.

---

## Pointing at a line

Plans grow to hundreds of lines, and the owner reads them in an editor. So **every message to the
owner that refers to part of a plan gives the line it sits on.** That covers a phase or slice, an
item, an open question, a review item, a decision, a `{{bracketed}}` proposal, the RESUME banner,
the Handoff section and a reconciliation finding. It also covers companion files (an audit,
`SWARM.md`, `REPORT.md`) and code a finding cites. "Q3 is still open" sends the owner searching,
while "Q3 (`cowork/plans/012_2026-06-20_auth-redesign.md:88`) is still open" takes them to it.

- **Path and line, clickable.** Give the repo-relative path with `:line`, or `:start-end` for
  anything longer than one item (a slice, the review block, the Handoff section). Use whatever
  form the environment makes clickable: a markdown link where the client renders one, plain
  `path:line` in a terminal. In the templates in this skill, `<plan>:<line>` stands for this.
- **Look the number up just before sending.** The plan changes under a session: items get ticked,
  review items appended, the banner moved. A number from an earlier read, or from memory, is
  wrong. Run `grep -n` for the heading or item after the last edit to the file, then write the
  message.
- **Line numbers go in messages, never in the plan.** A line number is a pointer for the reader
  of one message. Inside the plan, an issue or a PR body, name a part of the plan by something
  stable: its heading, the slice id, `Q3`, review item `#4`, decision `D7`. The next edit above it
  moves every line. Code citations in a plan keep their path and line as before, and every resume
  re-checks them.
- **Questions too.** An open question put through the question tool names its plan line in the
  question text, so the owner can read the context before choosing.

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

**Open questions:**
- Q1 — <question> · bites: <phases> · recommended: <option>
```

Wait for user approval or redirection before writing. Ask the open questions in the same round
(see **Batches**); the ones still unanswered go into the plan's `## Open questions`.

### Step G3 — Write the plan file

1. Determine the target directory and plan number.
   - **Scoped** (`for:<scope>` given, or the topic clearly belongs to an existing scope): use that
     scope's directory. Create it if it doesn't exist. If the scope is ambiguous or unrecognized,
     ask rather than guessing.
   - **Default:** the first configured root (`cowork/plans` when unconfigured).

   Find the highest `NNN` prefix **in that directory only** — numbering is per-directory, and
   counts `NNN_` DIRECTORIES (plan directories) alongside `NNN_` files. The new plan gets
   `NNN + 1`, zero-padded to 3 digits, starting at `000` if the directory is empty.
   Filename: `NNN_YYYY-MM-DD_topic.md`.

   Write a bare file. Promote it to a plan directory (`NNN_YYYY-MM-DD_topic/` holding
   `NNN_YYYY-MM-DD_topic.md` plus companions) the moment the plan gains a supporting document —
   see **Plan directories**. Never file that companion under a new `cowork/<doc-type>/` folder.
2. Write the plan file:
   - `# Plan: <Title>`
   - `## Source` — manifest linking each task by DB id:
     ```
     - entry #4 — **Task title** (pillar: pillar-name)
     - entry #5 — **Task title** (pillar: pillar-name)
     ```
   - `## Context` — background, motivation, current state
   - `## Open questions` — every question the owner must answer before building, in the
     **Batches** format (leave it out when there are none)
   - `## Build Order` — phased breakdown with `- [ ]` checkboxes for each item
   - `## Out of Scope`
   - `## Verification` — concrete test per phase
3. Update each source task's meta with the plan link:
   ```sql
   UPDATE logs SET meta = json_set(COALESCE(meta, '{}'), '$.plan_id', '<plan_id>',
     '$.plan_path', '<repo-relative path to the plan file>') WHERE id = <id>;
   ```
   See **Plan Scopes** for how `plan_id` is derived. Always write `plan_path` as well — it is what
   Resume actually resolves against.
4. Create a brain DB task for each phase:
   ```sql
   INSERT INTO logs (type, title, pillar, status, meta)
   VALUES ('task', 'Plan <plan_id> Phase X: <phase title>', '<pillar>', 'active',
     json('{"plan_id":"<plan_id>","plan_path":"<path>"}'));
   ```
5. Do **not** start implementation. The user will invoke `/plan <plan_id>` (e.g. `/plan 004` or
   `/plan mvp 001`) to resume and begin execution.

---

## Resume Flow

Resume work on an existing plan. Every invocation begins with a fresh-eyes reconciliation pass — never assume the planning agent was 100% accurate.

### Step R1 — Load and bind

1. Resolve the plan file path. Search in order, stopping at the first hit:
   a. A full path, if one was given.
   b. `meta.plan_path` on a brain DB task whose `plan_id` matches the argument.
   c. If a scope was given (`mvp 001`), that scope's directory for a `001_*.md` file.
   d. All configured roots and their subdirectories for a matching `NNN_*` prefix — a plan
      directory's own file is found this way, since the prefix is on the file too. Ignore a
      matching `NNN_` DIRECTORY name itself; the plan is the file inside it. If more than one
      directory yields a match, list the candidates and ask — do not guess.
2. Read the full plan file.
3. **Bind this session to the plan.** For the rest of this conversation, `/plan update` and `/plan carry` default to this plan without requiring a ref.
4. If the plan header carries `**Mode:** pr`, apply **PR Mode** rules for the rest of the session (the reply header is `**Plan NNN / PR-k**`, the stay-current steps run before any code, and every ship goes through the project's ship command).
5. Identify the current state:
   - Which phases are marked `**Status:** done`?
   - Which phases have a mix of `- [x]` and `- [ ]`?
   - Is there an existing RESUME WORK HERE banner? If so, note its location — that's where the last session stopped.
   - Is there a `## Handoff` section (see **Handoff Flow**)? It is the last agent's account of state, decisions and dead ends. Read it before anything else, and check its **State** against `git worktree list` and the `git status` of the worktree it names before trusting it. Continue work in that worktree, never by checking its branch out in the primary checkout.
   - Does `## Review` hold uncleared items, or `## Open questions` hold open ones (see **Batches**)? Both go to the owner in R3, before any new work.

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
   `plan_id` is `'NNN'` for plans directly in a root, or `'<scope>-NNN'` for scoped plans — see
   **Plan Scopes**. Always a string, never an integer (`'003'`, not `3`).
   Flag any DB tasks marked done that the plan file still shows as open (or vice versa).

### Step R3 — Brainstorm

Present findings to the user. Do NOT make any file edits yet.

**Format:**

```
**Plan NNN / Phase X — <phase title>** · <plan>:<start>-<end>

**Reconciliation:**
- completed work verified against codebase
- drift or issues found — each with the plan line it affects and the code <path>:<line> behind it
- brain DB sync status

**Waiting on you from last session:** <uncleared review items, by number and line — or none>

**This batch:**
- <first open item> (<plan>:<line>) — <current state assessment>
- <second open item> (<plan>:<line>) — <any blockers or prerequisites noted>

**Open questions this batch needs:** <Q-numbers with their lines, asked below — or none>

**Proposed approach:**
<2-3 sentences on how to tackle the batch, informed by the reconciliation>
```

Then ask the batch's open questions in the same message (see **Batches**) and write the answers into the plan. Critical review items that hold work come first: settle them with the owner now. Uncleared calls and unverified items are only mentioned (a count and the block's line range) and carry into this session's block. Wait for approval or redirection before any implementation. This is the session's one confirmation: once approved, the work runs without stopping, and under **Autopilot** (on by default) it carries on past the batch through the plan's build order and its `## Work ahead` queue.

### Step R4 — Announce in replies

Once the user approves and work begins, prefix every subsequent response in this session with a short header:

```
**Plan NNN / Phase X**
```

This reminds the user which plan this session is bound to and makes conversation history scannable.

---

## Brainstorm Flow

In `<this skill's folder>/brainstorm.md`. Read it before acting in brainstorm mode.

---

## PR Mode

In `<this skill's folder>/pr-mode.md`. Read it before acting in PR mode, including a resumed plan with `**Mode:** pr`.

---

## Epic Mode, Issue Mode, Issue policy

In `<this skill's folder>/tracker.md`. Read it before acting in Epic or Issue mode.

---

## Batches: questions first, decide and continue, a record at the end

A **batch** is any stretch of work that runs through more than one item or slice: a resumed
session working down the build order, or a `/swarm` run. The owner's open questions are answered
before it starts. Inside it, calls are made and the work keeps going. Nothing waits for the owner
unless it is **critical**. Every call is recorded in one review block, which the owner reads and
overrules when they choose.

### Before: open questions, answered in the plan

Every question that needs the owner lives in the plan's `## Open questions` section:

```markdown
## Open questions

**Q3 — <the question, in product terms>** · bites: <items or slices> · raised: YYYY-MM-DD
- Options: **A** <option> — <what it gains, what it costs>; **B** <option> — <…>
- Recommended: **A**, because <reason>
- **Answer:** _(open)_
```

- **Top-level only.** A question belongs here when its answer changes what gets built across
  items, is expensive to reverse, or is product judgment only the owner can supply. A question
  that a recorded decision or standard already answers is not asked: apply it and record the
  call. Anything smaller is decided inside the batch (below).
- **The gate.** A batch does not start while a question that bites one of its own items reads
  `_(open)_`. Questions that bite only later items stay listed and do not hold it.
- **Asking.** Put the open ones to the owner in one round — the question tool when there is
  one, batched, recommendation first, each naming its plan line (see **Pointing at a line**) —
  and write each answer into its **Answer:** line. Then
  move it into the plan's decisions with the next number (the Decisions table in PR mode, the
  Handoff section's **Decisions** otherwise) and log it to the brain as a `decision`. "You
  decide" is an answer: record the default taken. The section keeps only what is still open.
- Questions are numbered once and never renumbered.

### During: decide, build, record

Inside a batch nobody stops to ask the owner anything, and nothing waits for them, except in the
one case below. Think like a senior developer: make the call, build it, and keep going.

- **Where a call comes from:** the plan, then its decisions, then the brain's decisions, then
  the codebase's conventions, then the smallest reasonable reading of the item. Commit to it.
  Design, layout and wording are calls too.
- **Build it so it works.** A call is always functional, never a hollow stub. An overruled call
  becomes a fix item later, which costs less than a stalled batch.
- **At a genuine fork, decide and build lean.** When it is truly unclear which way best reaches
  the goal, still pick one, but keep follow-on work to a minimum: make it functional end to end
  and stop, with no polish, extensions or dependent work stacked on it until a later pass needs
  them. Tokens spent building what may be un-built are waste. Mark the call **uncertain** in the
  review block. Where the choice is clear, build it properly as usual.
- **Every call is recorded** in the review block: the call, the options, why this one, what
  switching would cost, and what depends on it. It never holds the item: the item ships.
- **The only thing that parks is a critical issue:** something the owner has not pre-approved that
  is irreversible or outward-facing (deleting shared data, notifying people, spending money,
  touching production data), a security, privacy or permissions exposure, reversing a decision the
  owner explicitly made. A fork in the road is not critical: decide it and build lean (above).
  Stop only that item: park it, notify the owner, and carry on with everything that does not
  depend on it. **When unsure, it is not critical.**
- **Verify UI in order, then stop.**
  1. **Code:** types, tests, and the logic that renders the change.
  2. **A headless browser of your own** (`/look`, **Headless**), only when code cannot settle it:
     the page loads without errors, the changed control is there, the interaction works, and
     nothing overflows at a phone width.
  3. **Otherwise, note it and move on:** an **unverified** item in the review block (and in the PR
     notes in PR mode) saying what could not be checked and why. Do not spend time on UI that code
     or a headless browser cannot easily check. The owner's shared browser is never part of the loop.

### After: one review block

The record of the batch goes into **one** numbered section of the plan, `## Review`, directly under
the Handoff section (or under the title when there is none). Critical parks come first, because they
are the only items that hold work:

```markdown
## Review

**Session YYYY-MM-DD** · 1 critical waiting · 6 calls, 2 unverified

- [ ] **1 · critical** — <what is parked and why it could not ship without the owner>
  Options: <the alternatives> · Recommended: <one> · Holds: <items>
- [ ] **2 · call** — <the call made> · shipped in <PR or commit>
  Options: <the alternatives> · Why: <reason> · Certainty: sure | uncertain (built lean) · Switching costs: <what>
- [ ] **3 · unverified** — <what could not be checked, and why> · <URL, when there is one>
  Runs on: <app> from <checkout or branch> · Item: <slice or phase>
- [x] **4 · call** — <…> — cleared: <the owner's answer>
```

- **Written as it happens.** Each item is appended as it arises, so a crashed session loses
  nothing. There is one writer: when agents run in parallel, they report their calls, unverified
  items and critical parks, and the session that coordinates them writes the block.
- **An unverified item carries its URL when there is one,** and says what it **runs on** (the app,
  and the checkout or branch that serves it), so the owner can check it themselves if they want to.
  The owner may also run a **look** (a page they want to see); those items take the same shape.
- **The owner may mark items in the plan directly:** `[x]` approves, `[fix]` plus an indented
  `fix:` note asks for a change, and a note under one of a call's options changes that option. Anyone
  who writes the block re-reads it from disk first, so those marks survive. An unmarked call stands
  as built. An unmarked critical item still holds its work.
- **At the end of the batch, tidy it:** merge duplicates, drop what a later item superseded, and
  number it 1…N with critical items first. Hand the block over with its line range and the count of
  critical items waiting. Walk it item by item only when the owner asks to.
- **Clearing an item:**
  - an approval of a critical item releases whatever was waiting on it;
  - an answer to a call becomes a numbered decision, logged to the brain;
  - an overruled call or a rejection becomes a fix item in the build order, and a new idea becomes a later item.

  Tick the item with the owner's words.
- **Once every item is cleared,** delete that session's entries. Their outcomes live in the
  decisions, the build order and the commits, and the plan stays short. An uncleared item carries
  into the next session's block.
- **The block is the owner's.** In PR mode it never travels with a pull request: leave it out of
  any copy of the plan that goes to the team.

---

## Autopilot: keep working ahead

On by default for every resumed plan and every swarm run; a project turns it off in `kit.json`. The
R3 confirmation approves the plan's whole build order. The plan keeps a short ranked `## Work ahead`
queue; while a long job runs, the session starts the top item that does not touch it; when only waits
remain, a background heartbeat keeps it awake; a turn ends with status, never "what next?". It stops
only when everything left is the owner's. The full rules are in `<this skill's folder>/autopilot.md`:
read it at Resume's R3, before the batch starts.

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

- **Confirm the approach once, before the batch.** Resume's R3 is that confirmation, together with the batch's open questions. After it, work runs as a batch (see **Batches**): no further stops, calls flagged in the review block.
- **Never ask what to work on next.** Under **Autopilot**, the next item comes from `## Work ahead` and the build order; a wait is filled with the top runnable item; a turn ends with status. Keep `## Work ahead` current in every plan commit.
- **Update the plan file before every commit.** Before staging and committing, update the plan file to reflect current progress:
  1. Mark completed items `- [x]` with progress notes.
  2. Add `**Status:** done — <short note>` to completed phases.
  3. Place a RESUME WORK HERE banner on the first open item. Move the banner forward as work progresses — there should be exactly one in the file at all times during an active session.
  4. If stopping mid-phase, note exactly what's done and what's next on the first open item.
  5. Include the plan file in the commit alongside the code changes. When the code is on a worktree's branch, commit the plan separately in the primary checkout (**The IDE holds main**, under **Global rules**).
- **Commit after each chunk of work.** After completing a phase, a logical group of items, or any meaningful chunk of work, commit the code changes AND the updated plan file together. Don't batch everything into one giant commit at the end.
- **Sync brain DB.** When completing a plan item that has a linked task in the DB, mark the DB task done:
  ```sql
  UPDATE logs SET status = 'done', completed_at = datetime('now', 'localtime'),
    body = body || char(10) || '--- Completed in plan <NNN>'
  WHERE id = <task_id>;
  ```

---

## Update, Carry, Status and Review Flows

In `<this skill's folder>/flows.md`. Read it before running `update`, `carry`, `status` or `review`.

---

## Handoff Flow

In `<this skill's folder>/handoff.md`. Read it before running `handoff`.

---

## Global rules

- **No permission needed** — Execute immediately without asking. The one exception is the team's
  tracker: creating an issue, or posting anything that mentions a person, waits for the owner's go
  (see **Epic Mode**), because it notifies people and cannot be taken back.
- **Fresh eyes are mandatory** — Every `/plan` invocation does the reconciliation pass, even if you were just working on this plan 5 minutes ago.
- **Point at the line** — every message to the owner that mentions part of a plan cites its path and line, looked up just before sending (see **Pointing at a line**).
- **One plan per session** — A session binds to one plan at a time. If the user wants to switch, they run `/plan <different-ref>` which rebinds.
- **The IDE holds main; other branches live in worktrees.** The primary checkout is the repository root the owner's IDE has open, and it stays on the branch it is on. No `/plan` flow runs `git checkout`, `git switch`, `git stash` or `git reset` there.
  - **Default flows** commit on whatever branch the primary checkout already has.
  - **Work that needs its own branch** gets a worktree at `.claude/worktrees/<slug>`: a PR-mode slice, a stacked slice, or a branch the owner asked for. Create it with `git worktree add -b <branch> .claude/worktrees/<slug> <base>`, or reuse the worktree that already has the branch (`git worktree list`). Build, check and commit there; switching branches is allowed only inside a worktree this session created.
  - **The plan file stays in the primary checkout.** It is read, edited and cited there, even while the code is built in a worktree. That is the copy the owner has open, so every `path:line` they click opens it, and the owner and Claude work in one copy.
    - A worktree's copy of the plan is a stale snapshot: never read state from it or write it.
    - Code commits go on the worktree's branch.
    - Plan edits are committed in the primary checkout, limited to that path (`git -C <primary> commit --only -- <plan>`), so the owner's other staged work stays as it was. When that checkout is mid-merge, mid-rebase or mid-cherry-pick, leave the plan edits uncommitted and say so.
    - Other files on the branch are read and cited at the worktree's path.
  - **Ignore and clean up worktrees.** Unless `git check-ignore -q .claude/worktrees/` succeeds, append `/.claude/worktrees/` to `.git/info/exclude`. That file is local to the clone, so the project's `.gitignore` stays the project's call. Remove a worktree once its branch has merged, never with `--force`.
  - **A team repository gets the same layout**: worktrees at `.claude/worktrees/<slug>` inside it, and its primary checkout left alone.
  - **`/swarm` builds on this rule** (its **Branches live in worktrees**).
- **The plan file is a baton, and a baton is short.** Every edit should serve the handoff to the next session. A future Claude — with zero memory of this conversation — will open this file cold and need to resume within a minute, which a plan of goal, decisions, slices and a status block allows and a long execution log does not. `/plan handoff` is the deliberate version: run it before a session ends or another agent takes over.

---

## Project overrides

If `.claude/kit.json` has a `rules."plan"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.
For **PR mode**, the override is where a project names:

- its ship command and ship policy;
- its branch and title conventions;
- its issue-first rule;
- its priority tiers;
- whether it opts back into owner looks before shipping (`swarm.look`), and how its pages are served for one;
- its quick and full check commands;
- its slice-size signal;
- the map of which paths trigger what in its CI;
- its prior-art sweep agent or script, and its rules for who gets mentioned where;
- its tracker conventions beyond **Issue policy**: issue title style, and which parent issue each
  kind of slice hangs under.

```bash
jq -r '.rules."plan" // empty' .claude/kit.json 2>/dev/null
```
