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

---

## Plan Scopes

Plans may live in more than one directory. The roots are configured per project in
`.claude/kit.json`; when the file or key is absent the single root is `cowork/plans`.

```json
{ "plan": { "roots": ["cowork/plans", "cowork/clients/*/projects/*/plans"] } }
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
| `cowork/clients/acme/projects/data-portal/plans/000_poc.md` | `data-portal` | `data-portal-000` |

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
   - Is there a `## Handoff` section (see **Handoff Flow**)? It is the last agent's account of state, decisions and dead ends. Read it before anything else, and check its **State** against `git status` and the current branch before trusting it.
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

Then ask the batch's open questions in the same message (see **Batches**) and write the answers into the plan. Uncleared review items come first: walk them with the owner now, or carry them into this session's block if they would rather look later. Wait for approval or redirection before any implementation. This is the batch's one confirmation: once approved, the work runs without stopping.

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

Phase 1 — <title> (<plan>:<start>-<end>): 3 concrete, 2 loose, 0 unknown
Phase 2 — <title> (<plan>:<start>-<end>): 1 concrete, 4 loose, 1 unknown
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

## PR Mode

The default flows assume one developer on one repo: phases, a checkout, commit when done. PR
mode is for work that lands in a **team repository** through pull requests reviewed by other
people, often on a codebase you do not own. The plan stays private (it lives in your own repo),
but its build order is a sequence of clean PRs, and the plan file travels with each PR, so it
has to read well to a reviewer who has never seen your notes. Most of that work changes code
and decisions other people made. So every body records its decisions, credits the prior work,
and tells the people it changes (see P5).

Usage: `pr <topic>` (generate), or `NNN pr` (convert an existing plan, then resume). A PR-mode plan
carries `**Mode:** pr` in its header; Resume detects it and applies these rules automatically.

### What changes from the default flows

| Default | PR mode |
|---|---|
| Build order in phases | Build order in **slices**: each one concern, built in one session, shipped as one PR that merges the same day it was branched — at most ~20 files / ~1,000 changed lines, or the size the team's own review tooling treats as light. Split by layer so users never see half a change. See **How to cut the work** below |
| Proposed phases (Generate, G2) | Proposed **slices**, one line each: what it delivers, what the owner will see, rough size |
| Reads the working tree | Reads the **remote default branch** (`git fetch`, then `git show origin/<default>:<path>`, `git grep <pat> origin/<default> -- <dir>`). A checkout on a feature branch is stale by definition |
| One brain task per phase | One brain task per PR: `Plan <id> PR-k: <title>` |
| Reply header `Plan NNN / Phase X` | `Plan NNN / PR-k` |
| Companion files cited freely | **No references a reviewer cannot follow**: no other plan numbers, no private companion files, no personal notes. Cite the code (path and line on the default branch), issues, PRs and ADRs instead |
| Items may name a phase's work loosely | **The next slice's items are checkable steps with a path**, each small enough that a coding agent with no memory of the conversation can do it, tick it with ` — done: <note>`, and commit. **Later slices stay one line each** (what it delivers, what the owner will see) until they are next — detail written far ahead of the code goes stale and has to be corrected before it can be built |

### How to cut the work: slices that merge the same day

The unit of work in a team repo is a **slice**: one concern, built in one session, shipped as one
PR that merges the same day it was branched. Weigh both costs before choosing fewer, bigger PRs:

- **A PR's fixed cost is usually small and unattended:** one CI run and a review bot, often in
  parallel, that nobody has to watch. Work goes on while they run.
- **A long-lived branch's costs grow with its size and its age.** The default branch moves under
  it, so it rebases again and again and re-verifies after each; features other people merge onto
  the model it is changing have to be ported onto it; a bigger diff draws more findings per review
  round; scope creeps in because the PR is "still open"; and every extra file is conflict surface.
  A dozen small PRs usually land sooner than one big one, and each is easier to review.

The rules:

- **Size signal.** At most ~20 files and ~1,000 changed lines, not counting generated files — or,
  better, the threshold the team's own review tooling uses for its lighter review. When a branch
  passes it, ship what is there and start the next slice. A slice that needs lettered sections is
  probably two slices.
- **Split by layer, not by adopter, when the visible result must land consistently.** Invisible
  plumbing first — the shared library capability, the new component, the additive column — each a
  PR that changes nothing a user sees; then one small PR that switches the visible change on
  everywhere at once. Users never see half a change, and reviewers never see a 200-file diff.
- **Shared code first, adopters after.** A change to a widely used package tends to pull every
  dependent into CI; an adopter-only change usually runs only that adopter's checks.
- **A wide refactor is expand–contract, never a big bang.** Add the new form beside the old so
  nothing breaks; move callers over in batches, each its own green PR; delete the old form once no
  caller remains. Other people's work keeps landing on a codebase that compiles both ways, instead
  of arriving on the old form and having to be ported.
- **Real isolation boundaries still split:** a schema change, a data backfill, anything touching
  auth or money gets its own PR, because a reviewer needs to see it alone.
- **Never hold two open branches over the same files.** Sequence them; the second rebases once,
  after the first merges.
- **Shape each slice for the pipeline.** Learn which paths trigger what in the team's CI. A diff
  confined to docs and agent config often runs a light gate, while build scripts or shared tooling
  pull in extra test groups and invalidate caches — batch those expensive-path changes into one
  slice. The project's `rules.plan` override is where its CI path map belongs.
- **Work that depends on data collected after merge is not a planned PR.** Put it in the close
  phase as a conditional follow-up and open it only if the data says so.

### Inside a slice: look first, test once

1. **Build with quick checks only:** type-check the package being edited and run only the tests
   related to the changed files (the test runner's related or changed-files mode, or the files by
   name). Seconds, not minutes. Never a whole suite mid-build, never the whole repo.
2. **The owner looks** at every user-facing change on a local run **before tests are written
   around it**, in the batch's review block (see **Batches**), never slice by slice. Check every
   changed page yourself first, in a headless browser of your own (a passing check is not a
   running app), then park the slice and add its look items: the URL, what changed, what to try
   and what right looks like. Changing their mind here is cheap, because nothing has been pinned
   yet. A lane's next slice may stack on a parked one. New ideas go to a later slice.
   **A stub never ships unconfirmed:** in a team repository a green pull request often merges and
   deploys on its own, so a slice holding a stub for a call the owner has not confirmed parks like
   a user-facing one, with dependents stacking on its branch. A call that is cheap to undo and needs
   no stub ships, and is listed in the review block for confirmation.
3. **Then the tests,** pinning what was approved. Data-layer logic — queries, predicates,
   permission rules — is the exception: prove it against a real engine as it is written. It does
   not depend on taste, and it is where the serious bugs hide.
4. **Ship through the project's ship command:** rebase once, run the team's scoped checks once
   with the prior-art sweep beside them (see P5), then the team's review bot locally if it has one.
   Then ship ready or as a draft, as the project's ship policy says.
5. **While CI runs, start the next slice.** When a CI group fails, push the fix as soon as it is
   ready: that run is already lost, and waiting for the rest of the verdict only gives the default
   branch time to move under the PR.

Keep the full output of every check in a log and search it — never re-run a check just to see
more of its output. Do not rebase mid-build: rebase once at ship time, when the host reports a
conflict, or when the slice needs something that just landed.

### Step P1 — Investigate on the default branch (Phase 0 of the plan)

Before proposing anything, inventory what exists: the components that already do the job, every
place the thing is implemented differently, the team's own recorded decisions (ADRs, decision
logs, issue threads, contract docs), open issues that already cover parts of the work, and any
priority tiers the team uses (release waves, milestones). Cite a path and line for every claim.
This phase is marked done in the plan with its findings summarised **in plain terms** under
Context; the evidence detail can live in a companion file for you, but the plan must stand
without it.

**Record who is behind each finding**: who built the component, wrote the decision record,
opened the issue, or has an open pull request over the same files. Most team-repo work
changes something someone else built or decided. P2 credits those people, and P5 tells them
what changes. Run this sweep in a fresh subagent when one is available, so its reading stays
out of the planning context. The project's `rules."plan"` may name a dedicated sweep agent or
script. Blame the lines the work will replace, read the pull requests they came from, and
search the host's issues and pull requests by concept, not only by file.

### Step P2 — Decide, with defaults

Two tables in the plan, before Build Order:

- **The new standard** (when the plan standardises something): each existing component the
  plan names as *the* one, where it lives, and **why that one** over the alternatives found in P1.
  Reviewers accept "we chose X" far more readily when the table shows what else existed.
- **Decisions**: every decision, its **owner**, the **default the plan proceeds on**, and
  where in the build order it bites. Record for each one:
  - **why** it was made;
  - the **alternatives**, with what each would have gained and cost;
  - the **prior record** it builds on, changes or reverses (linked, author named);
  - **who it affects**.

  This is what every body in P5 draws from, so write it once here, tersely. A missing decision
  never blocks a PR. The default ships, and the PR body flags it and tells the people it
  affects. Record answers in a **Decisions taken** table as they arrive. A decision that is the
  plan owner's to make, and that bites before building starts, is an **open question** instead
  (see **Batches**): it is answered before the batch that needs it.

### Step P3 — Write the plan (PR mode template)

Same top-level sections as the default (`Source`, `Context`, `Build Order`, `Out of Scope`,
`Verification`), plus these, in this order after the header:

1. **The short version** — what ships, in which slices, for someone who reads nothing else —
   and a small **Status** block: where the work is, what is next. The whole plan stays short:
   goal, decisions, the slice list, status. History belongs in commits and PR bodies.
   **Review** and **Open questions** (see **Batches**) sit with it, near the top, when they
   hold anything; both are the owner's and stay out of any copy that travels with a PR.
2. **The new standard** and **Decisions** (P2).
3. **Priority tiers**, if the team has them: which adopters get full work and which are
   "wire only" (pointed at the standard, listed with a reason, never optimised). Put the tier
   next to every adopter that appears later.
4. **PR conventions for this plan**: how every body opens (see P5), who gets told what
   changes, how the plan file travels with the PR, and any preview-before-ship rule the
   project has.
5. **Handoff: ground rules for whoever codes this** — the reading list in order (the team's
   agent/contributor rules first), where and how to work (package manager, runtime, worktree,
   branch naming copied from the team's history, issue-first if the team requires it, one
   commit per section), the **stay-current steps** (fetch; fast-forward the primary checkout's
   default branch; read the log of the surface since the last session — and do not rebase a
   feature branch on a schedule: once, at ship time), the quick check for building and the full
   check for shipping, the ship command, and what to do when the plan turns out to be wrong.
6. **Build Order, by slice.** Each slice has: a `**Status:** open · **Waits on:** …` line; an
   **In plain terms** paragraph (what it does and why, for a non-engineer); for the NEXT slice,
   its checkable items, and for later slices one line (what it delivers, what the owner will see,
   rough size) until they are next; and an **Exit** line. Once the slices are published (see
   **Epic Mode**), each row also carries its issue number. A rollout is **one slice per adopter**,
   under a shared recipe so each stays short. The `RESUME WORK HERE` banner sits on the first
   open item, as always.
7. **Verification per PR** and **Risks**, as tables or short lists.

### Step P4 — Register

Brain: one task per PR (`Plan <id> PR-k: …`), `plan_id` and `plan_path` in `meta`; one decision
entry per row of **Decisions taken**; the open decisions as one question entry.

Then the tracker: `NNN epic` publishes the epic and, when the project publishes ahead (see
**Issue policy**), one sub-issue per slice, so the team sees the plan before any code.

### Step P5 — PR bodies, previews, and shipping

- **Every body is a decision record, written for the humans who read it.** This covers the
  epic, each issue and each PR. A PR body opens with, in order:
  - **Goal**: one or two sentences.
  - **Summary**: what changed, in plain language, naming the standard or component it
    introduces.
  - **Decisions**: every one, UI / UX / design first, then data, API and architecture. For
    each: why, what it gains and costs, the alternatives not taken and why, the prior record
    it builds on or changes (linked, author named), and whose call it is.
  - **Who this touches**.

  All of this comes before anything technical, and before the team's own template sections if
  it has any. A decision that changes or reverses someone's recorded decision says so in its
  first line. **The plan travels with the PR:** inline it in a collapsed block when it is
  short. When it is long, or the team keeps plans in the repo, commit it there and link it by
  a **commit-pinned** permalink. A relative link resolves against the default branch, where
  the file does not exist until merge, and hosts cap body size.
- **Credit the work you build on, and tell the people you change.** Most work in a team repo
  changes code or decisions someone else made. Before each body goes up, run the prior-art
  sweep (P1's, re-run on the actual diff for a PR). It covers the blame of the replaced lines,
  the pull requests behind them, open pull requests over the same files, code owners,
  decision records, and issue threads on the same concepts.
  - **Credit** each piece of prior work by link and author name.
  - **Mention** (`@login`) each person with a real stake once, under **Who this touches**,
    with a line saying what changes for them. A real stake means their code is replaced,
    their recorded decision changed, their idea built on directly, or their open work
    overlaps. No reason, no mention.
  - **Leave out:** bots, and a code owner whose only stake is ownership where the host
    already requests their review.
  - **Once per concern.** Tag people on the epic and on the PR that changes their work, not
    on every issue in between. A slice's sub-issue names them by profile link, without the @.
    A standalone issue (no epic, no PR yet) tags like an epic.
  - **Timing.** Mention people when the text is created. A mention edited into a body is not
    reliably notified, so people found later go in a new comment.
  - **Package names.** Keep scoped package names (`@scope/pkg`) in code spans: hosts read a
    bare `@owner/name` as a team mention.
- **Look first.** Any user-facing change is viewed and confirmed on a local run by the person who
  owns the plan **before its tests are written and before the checks run** — not just before the
  push, when a change of mind throws both away. The routes to check, and the confirmation, are
  items in the plan's review block (see **Batches**).
- **Draft or ready is the project's ship policy** (`swarm.ship` in `.claude/kit.json`, or the
  `rules."plan"` override). The options:
  - `ready`: the owner has approved ready PRs in advance, and a PR is a draft only on their
    word for it.
  - `draft`: every PR opens as a draft.
  - `ask`: the question is put at ship time, every time. This is the default when no policy
    exists.

  Many teams auto-merge a ready PR, so ready is a shipping action. It happens only under a
  standing policy or the owner's explicit choice in that session. **A decision someone else
  owns does not by itself make a PR a draft.** The body records it, says plainly whose call
  it was, and tells the owner. Whether the PR waits for them is the policy's call; many teams
  prefer reacting to live code over debating drafts. A draft that waits on someone needs a
  direct ask to that person, because review requests alone are easy to ignore. Never merge
  from the skill.
- **Ship only through the project's ship command** (the `rules."plan"` override names it); that
  command is where the team's checks, review bot and body template are enforced.

### Behavioral rules in PR mode

- Run the stay-current steps before writing code in any session. Rebase a feature branch once,
  at ship time — not every session, and not because the default branch moved.
- Build with quick checks, let the owner look before tests are written, and run the full scoped
  checks once at ship time (see **Inside a slice**).
- One commit per lettered section; commit the plan file in **your** repo alongside, never into
  the team repo.
- Tick items with ` — done: <note>`; never delete an item; if a step is impossible as written,
  say so in the note and do the nearest correct thing without widening or narrowing scope.
- When a slice grows past the size signal, ship what is there and move the rest to the next
  slice. When a plan proposes one large PR instead, it names why a split by layer cannot work.
- In a project that works issue-first, a slice starts with `NNN issue <slice>`: the slice's issue
  is the team's view of its state, so it is current before the first commit.
- When the team's rules and this skill disagree, the team's rules win, and the plan says so.

---

## Epic Mode

Publish a PR-mode plan's workstream to the team's tracker **before building it**, so the people
it touches see the plan, its decisions and its order while they can still shape them. The unit
is the **epic** — the parent issue describing the whole workstream — and, when the project
publishes ahead (see **Issue policy**), **one sub-issue per slice**, wired together by their
blocking edges so the tracker shows the same dependency graph as the plan.

Usage: `NNN epic` publishes the first time and syncs every time after. The plan must be in PR
mode; convert it first (`NNN pr`) if it is not.

A plan may carry more than one epic's work — two workstreams sharing one build order because
they touch the same files. Each slice then names its epic, and each epic is published on its own:
its own body, its own sub-issues, its own people. Nothing about one epic appears in the other's
issues except a real dependency, stated as one.

### Step E1 — Load

Resolve, read and bind the plan as in R1, and read **Issue policy**. For each epic the plan
names, collect what already exists: the epic's issue (if any), its sub-issues from the host's
native listing, and each slice's recorded issue (the slice table's issue column, or the brain
task's `meta.issue`). **Nothing is created twice:** an issue that exists is synced (E5), never
duplicated.

### Step E2 — Sweep

Run the prior-art sweep (P1's) over the plan's areas: one run per lane or area, not one per
slice. It supplies each decision's prior record — what it builds on, changes or reverses, linked,
author named — and, for each person, the stake that earns a mention. Use the project's sweep agent
when it names one.

### Step E3 — Draft

Write every body to a file before anything is posted.

- **The epic** — P5's decision record at workstream scale: **Goal**; **Summary** in plain
  language; **Decisions**, each with why, what it gains and costs, the alternatives not taken,
  its prior record, and whose call it was; **The slices**, as a table — slice, what a user will
  see, blocked by; **Who this touches**, one `@mention` each with what changes for them; and how
  to reach the owner.
  **If the epic already exists,** its body is not where new people are told: a mention edited
  into a body is not reliably notified. Draft a **new comment** carrying the slice table and the
  mentions, and refresh the body separately without adding any.
- **Each slice** — **Goal** in a sentence or two; **What a user will see** ("nothing — plumbing"
  is an answer); the **Decisions** that bite in this slice, in the same shape; **Prior work**,
  credited by link and **by name without the @** (the epic and the slice's PR do the tagging —
  once per concern); **Blocked by**; the epic; and a status line, `Planned — not started`.
  Describe the area rather than line numbers: a planned issue is read weeks before its slice
  starts, and line numbers will have moved.
- Run the project's body check on every file, when it names one, and fix what it reports.

Titles follow the team's convention; the project override names it.

### Step E4 — Preview, then publish on the owner's word

Posting notifies people and cannot be taken back, so show it first: how many issues will be
created, updated and closed; the epic's body or comment in full; two representative slice
bodies; every person mentioned, with the reason. **Publish only on the owner's go.**

Then publish in **dependency order**, blockers first, so every blocked-by can name a real issue:

- attach each slice to its parent with the host's **native sub-issue** relationship, and add the
  host's **native blocking links** where it has them; where it has none, the body's Blocked by
  line carries the numbers;
- apply the project's assignee and labels, and **never a label the project lists as one its
  automation acts on** — a planned issue that lands in an agent queue gets built by somebody
  else;
- record each issue number in the plan's slice table and in its brain task (`meta.issue`), and
  commit the plan.

### Step E5 — Sync on every re-run

`NNN epic` after the plan changed brings the tracker back in line with it:

- a new slice gets a new sub-issue, in its place in the graph;
- a slice that has **not started**, whose one-liner, decisions or blockers changed, gets its body
  updated — with no mention added by the edit; anyone newly touched gets a comment;
- a slice merged into another, or dropped, has its issue **closed with a comment** saying where the
  work went;
- a slice that has started belongs to **Issue Mode**, and is left alone here.

Report what was created, updated and closed, with links.

---

## Issue Mode

Create, or bring current, **one** issue.

- **`NNN issue <slice>`** — the slice is about to start, or its scope just changed. Bring its
  issue current: the slice's checkable items become its acceptance criteria, its decisions and
  blockers are refreshed, and its status line becomes `In progress`. When it has no issue yet —
  the project publishes on start, or the slice was added after publishing — create it, attached
  to its epic with its blocking links, exactly as E4 does for one slice. In a project that works
  issue-first this runs before the slice's first commit.
- **`issue <topic>`** — a standalone issue: a defect found mid-work, an idea parked for later, a
  follow-up a review surfaced. The same decision record at issue scale: what, and why it matters;
  the evidence (steps to reproduce, the route, what right looks like); the prior work, credited;
  and — because no epic or PR will tag anyone for it — `@mentions` for the people with a stake.
  Attach it to an epic when one applies. With a plan bound, add it to the plan (a new slice, or a
  follow-up under *Out of Scope*) and link it both ways.

Either way: sweep the issue's area, draft to a file, run the body check, and show the body and the
mentions. **Creating an issue, or posting anything that mentions a person, waits for the owner's
go**; an agent running a plan unattended gets that go once, up front, for the issues it will
create. Refreshing the body of an issue that already exists, with no mention added, does not.

---

## Issue policy

Epic and Issue modes read the project's tracker settings from `.claude/kit.json`:

```json
{
  "plan": {
    "issues": {
      "publish": "ahead",
      "repo": "your-org/your-repo",
      "assignee": "your-login",
      "labels": ["P2"],
      "neverLabels": ["agent-queue"],
      "check": "node scripts/check-body.mjs {file} --kind {kind}",
      "sweep": "prior-art"
    }
  }
}
```

- **`publish`** — `ahead`: Epic mode publishes every slice as a sub-issue before building starts.
  `on-start` (the default): Epic mode publishes the epic alone, and each slice's issue is created
  by Issue mode when that slice starts.
- **`repo`** — the tracker's repository, when it is not the session's own.
- **`assignee`**, **`labels`** — applied to every issue created.
- **`neverLabels`** — labels the team's automation acts on (an agent queue, an auto-close rule);
  never applied by this skill.
- **`check`** — a command that lints a body file before it is posted; `{file}` and `{kind}`
  (`epic`, `issue`, `pr` or `comment`) are filled in.
- **`sweep`** — the prior-art sweep agent or script, when the project has one.

The tracker is reached through the host's CLI (`gh` for GitHub, including its sub-issue and
issue-dependency APIs). When a key is absent, the mode asks rather than guesses.

---

## Batches: questions first, one review at the end

A **batch** is any stretch of work that runs through more than one item or slice: a resumed
session working down the build order, or a `/swarm` run. The owner's attention is spent at the
two ends of a batch and nowhere in between. Their open questions are answered before it starts,
and everything that needs their eyes or their judgment waits in one review block after it ends.

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

### During: decide, stub, flag

Inside a batch nobody stops to ask the owner anything, except in the one case below. Think like
a senior engineer and product manager: make the call and flag it for the review.

- **Where a call comes from:** the plan, then its decisions, then the brain's decisions, then
  the codebase's conventions, then the smallest reasonable reading of the item. Commit to it.
- **When the options cost real work,** pick the best one and build the **seam** in full — the
  types, exports, schema, routes and contracts that later items or other agents consume — and
  the behaviour behind it minimally. A change of course after the review then throws little
  away, and nothing downstream waits. Mark the stub in the code where the project's conventions
  allow it.
- **Every call is flagged** in the review block: the call, the options, why this one, what is
  stubbed (paths), what switching would cost, and what depends on it.
- **The only interruption** is something the owner has not pre-approved that is irreversible or
  outward-facing — deleting shared data, notifying people, spending money, touching production —
  or a security or data-exposure risk. Even then, stop only that item: park it, notify the owner,
  and carry on with everything that does not depend on it.
- **Verify UI without the owner.** Check a changed page in a headless browser of your own
  (`/look`, **Headless**): it loads without errors, the changed control is there, the interaction
  works, nothing overflows at a phone width, and one screenshot per page per width is looked at
  for breakage. How it looks — design, layout, wording, a design choice — goes to the review
  block for the owner.

### After: one review block

Everything the owner needs to see or decide goes into **one** numbered section of the plan,
`## Review`, directly under the Handoff section (or under the title when there is none):

```markdown
## Review

**Session YYYY-MM-DD** · 2 of 5 cleared · to open the pages: <how to start the app>

- [ ] **1 · look** — <what changed> · <URL>
  Do: <what to click or try> · Right: <what right looks like> · Widths: 1440, 390
  Agent checked: <what the headless check confirmed> · Item: <slice or phase>
- [ ] **2 · call** — <the call made>
  Options: <the alternatives> · Why: <reason> · Stubbed: <paths, or nothing>
  Switching costs: <what> · Depends on it: <items>
- [x] **3 · look + call** — <…> — cleared: <the owner's answer>
```

- **Written as it happens.** Each look or call is appended as it arises, so a crashed session
  loses nothing. There is one writer: when agents run in parallel, they report their looks and
  calls, and the session that coordinates them writes the block.
- **One sequence, in click-through order** — by app or area, then by page. A **look** item always
  carries its own URL, which the owner opens in the shared browser themselves.
- **At the end of the batch, tidy it:** merge duplicates, request every URL again and fix what no
  longer renders, drop what a later item superseded, and number it 1…N. Then load the open items
  into the session's todo tool when it has one. When it has none, the checkboxes are the list,
  and after each cleared item report `k of N cleared — next: #m (<plan>:<line>)`. Hand the
  block over with its line range, and walk it item by item, each by number and line.
- **Clearing an item:**
  - an approval releases whatever was waiting on it;
  - an answer to a call becomes a numbered decision, logged to the brain;
  - a rejection becomes a fix item in the build order, and a new idea becomes a later item.

  Tick the item with the owner's words.
- **Once every item is cleared,** delete that session's entries. Their outcomes live in the
  decisions, the build order and the commits, and the plan stays short. An uncleared item carries
  into the next session's block.
- **The block is the owner's.** In PR mode it never travels with a pull request: leave it out of
  any copy of the plan that goes to the team.

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

---

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
- **State** — branch and worktree, uncommitted or unpushed work, stashes, open PRs and their
  review state, running servers, migrations or data changes applied, deploys, messages sent;
  and what was verified (command and result) versus not yet verified.
- **Open questions** — who answers each one, and the default assumed until they do.
- **Waiting on the owner** — looks and calls made this session that nobody has cleared yet.

Leave out what the plan already says, what the code or `git log` shows in a minute, and the
story of the session. Never write a secret; say where it lives instead.

Put each finding where the next agent will look for it:

- About one item -> on that item, as a note or sub-bullet.
- Outlives this plan (a project-wide convention, a tool quirk) -> the brain DB as an `insight`,
  not the plan.
- A decision -> the Handoff section's **Decisions** (in PR mode, the **Decisions taken** table
  instead), and the brain DB as a `decision` entry with `plan_id` and `plan_path` in `meta`.
- A question for the owner -> `## Open questions`; a look or call waiting on them -> `## Review`
  (see **Batches**), tidied and numbered.
- Everything else -> the Handoff section.

The Handoff section sits directly under the plan's title. Each handoff rewrites it instead of
appending: carry forward what is still true, drop what no longer holds, and leave out any empty
part except **State** and **Next**.

```markdown
## Handoff

**Updated:** YYYY-MM-DD · **Resume at:** <phase or PR> — <the item under the RESUME banner>

**State**
- Branch `<branch>` at `<sha>`; uncommitted: <paths, or none>; unpushed: <count, or none>
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

---

## Global rules

- **No permission needed** — Execute immediately without asking. The one exception is the team's
  tracker: creating an issue, or posting anything that mentions a person, waits for the owner's go
  (see **Epic Mode**), because it notifies people and cannot be taken back.
- **Fresh eyes are mandatory** — Every `/plan` invocation does the reconciliation pass, even if you were just working on this plan 5 minutes ago.
- **Point at the line** — every message to the owner that mentions part of a plan cites its path and line, looked up just before sending (see **Pointing at a line**).
- **One plan per session** — A session binds to one plan at a time. If the user wants to switch, they run `/plan <different-ref>` which rebinds.
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
- its look-first rule;
- its quick and full check commands;
- its slice-size signal;
- the map of which paths trigger what in its CI;
- its prior-art sweep agent or script, and its rules for who gets mentioned where;
- its tracker conventions beyond **Issue policy**: issue title style, and which parent issue each
  kind of slice hangs under.

```bash
jq -r '.rules."plan" // empty' .claude/kit.json 2>/dev/null
```
