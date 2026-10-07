---
name: swarm
description: Prep a plan for autonomous parallel execution, then run it with an orchestrated agent swarm. Phase is inferred from brain state — unregistered plan -> Setup, registered ready -> Run, running -> Resume. A team-repository run ends at the push; `land` then follows its open pull requests to merged. Also status / abort / report, and review — the owner's optional batch look from a parallel session while the run keeps going. Agents decide and continue; only critical issues park.
argument-hint: "[plan ref | scope NNN | status | abort | report | land [plan ref] | review [plan ref]]"
---

## Swarm State
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT id, plan_id, status, substr(created_at,1,10) FROM swarm_runs ORDER BY id DESC LIMIT 8;" 2>/dev/null || echo "No swarm runs yet"`

## Available Plans
!`ROOTS=$(jq -r '.plan.roots[]?' .claude/kit.json 2>/dev/null); [ -z "$ROOTS" ] && ROOTS="cowork/plans"; OUT=$(echo "$ROOTS" | while IFS= read -r r; do find . -path "./$r/*.md" -not -name '.gitkeep' 2>/dev/null; done | sed 's|^\./||' | sort); [ -n "$OUT" ] && echo "$OUT" || echo "No plans yet"`

---

# Swarm

Take a `/plan`-style plan file and complete it end-to-end without stopping — orchestrated by this session, parallel where the dependency graph allows. Two distinct phases, **inferred — never asked**. Route by the plan's **most recent** `swarm_runs` row (a remainder run supersedes the run it salvages):

| Brain state for the plan | Phase |
|---|---|
| No `swarm_runs` row | **Setup** — decompose, resolve every open question with the user, register the swarm |
| Row with `status = 'ready'` | **Run** — dispatch agents, review, merge, report |
| Row with `status = 'running'` | **Resume** — reconcile live state, continue the run |
| Row with `status = 'done'`, PR-mode, units still `shipped` or stacked | **Landing** — follow the open pull requests to merged (**Landing**); holds no builder slots |
| Row with `status = 'done'` / `'aborted'`, unfinished units remain | Report the outcome, then offer **Remainder setup** — a new, smaller run over what's left |
| Row with `status = 'done'`, everything merged | Report the outcome; a re-swarm requires the user to say so explicitly |

**Parallelism is an optimization, not the point.** The skill's promise is that the plan gets completed end-to-end without stopping. A plan that decomposes into a single serial chain still swarms — as a sequence of autonomous units — and setup reports that profile honestly rather than manufacturing fake parallelism.

The intended workflow: `/plan` generates the plan → `/swarm <ref>` (setup) → user reviews + `/commit` → **fresh session** → `/swarm <ref>` (run) → user reads `REPORT.md`.

**The core contract** is `/plan`'s **Batches** standard, applied to a whole run:
- Every question a human must answer is answered during Setup, and written into the plan.
- During Run, no agent stops to ask the user anything, and that includes the orchestrator. Agents make the call a senior developer would, build it to work, keep going, and record it as a call in the plan. At a genuine fork they still decide, but build the lean functional version and leave polish for a later pass.
- **Nothing parks for the owner unless it is critical** (`/plan`, **Batches**: irreversible, outward-facing, security or data exposure, money, or reversing an explicit owner decision). A fork in the road is not critical: decide it and build lean. Everything else ships through the normal pipeline.
- **UI is verified by code first, a headless browser second** (`/look`, **Headless**). This is every run's default and needs no setting. **No agent, and not the orchestrator, verifies in a headed browser on its own:** nobody drives the owner's shared window, and nobody launches a visible browser of their own. A visible browser appears only in `/swarm review`, which the owner runs. What neither code nor headless can verify is written down as unverified in the plan and the PR notes, and the unit moves on. Nobody spends time on UI that code or a headless browser cannot easily check.
- Calls, unverified items and critical parks all land in one numbered block in the plan. Only the critical parks wait on the owner; the rest they read when they choose.

## Branches live in worktrees

**The primary checkout belongs to the owner.** That is the repository root the owner's IDE has open. No swarm session or agent ever runs `git checkout`, `git switch`, `git reset`, `git stash` or a rebase there, and none writes the owner's branch. A run can take hours, and the owner keeps working in that checkout the whole time.

- **Every swarm branch is checked out in its own worktree under `.claude/worktrees/`:**
  - the integration branch `swarm/<plan_id>` at `.claude/worktrees/swarm-<plan_id>`;
  - each unit's branch in the worktree the Agent tool's `isolation: "worktree"` creates there;
  - a branch the review serves that has no worktree yet at `.claude/worktrees/review-<slug>`.

  A PR-mode plan whose code lives in another repository follows the same layout inside that repository (**Where the code lives**).
- **Address a worktree by its path.** Git work goes through `git -C <worktree>`, and files are read and written at the worktree's absolute path. The orchestrator's own working directory stays at the primary checkout. Switching branches is allowed only inside a worktree the session or agent created itself.
- **Branch without checking out.** Use `git worktree add -b <branch> <path> <base>` or `git branch <branch> <base>`. Git refuses to check out one branch in two worktrees, so when a branch is needed, use the worktree that already has it (`git worktree list`). Never move that branch out of its worktree.
- **Keep worktrees out of `git status`.** Unless `git check-ignore -q .claude/worktrees/` already succeeds, append `/.claude/worktrees/` to `.git/info/exclude`. That file is local to this clone, so the project's `.gitignore` stays the project's decision.
- **The brain has one copy.** `cowork/brain/BRAIN.db` is git-ignored and lives only in the primary checkout. Every session and agent uses it by that absolute path, never a worktree's copy.
- **The bookkeeping stays in the primary checkout, shared with the owner.** The plan, `SWARM.md`, `REPORT.md` and the review handoffs are read and written only there. The orchestrator edits them in the same files the owner has open and marks, so every `path:line` it gives points into the owner's IDE.
  - **Worktrees hold code only.** Their copies of the plan and `SWARM.md` are stale snapshots from the base commit. No session reads its state from them or writes them.
  - **No mid-run commits.** The orchestrator's edits sit uncommitted in the primary checkout beside the owner's own, and the owner may commit them whenever they like. At the end, the orchestrator commits just its bookkeeping paths, once (R4).
  - **Git never merges these files.** The integration branch never changes them, so the final fast-forward cannot conflict with them.

## Input

Optional argument: `$ARGUMENTS`

- `status` → **Status flow** (read-only)
- `abort` → **Abort flow**
- `report` → print the most recent run's `REPORT.md` path and summarize it
- `land [plan ref]` → **Landing**: follow a PR-mode run's open pull requests to merged, after the build run has ended. With no ref, every plan that has units still `shipped` or stacked
- `review [plan ref]` → **Review flow**: the owner's optional batch look, run from a **parallel session** while the run keeps going. Never the orchestrator's own session
- A plan ref (`021`, `mvp 001`, filename fragment, or full path) → resolve using the same rules as `/plan` (check `meta.plan_path` on brain tasks first, then scan roots; ask if ambiguous), then route by the table above
- Empty → if exactly one run is `ready` or `running`, use it; otherwise list and ask

## Brain schema

Swarm state lives in `cowork/brain/BRAIN.db`. Before any flow, ensure the tables exist (idempotent — safe on every invocation):

```sql
CREATE TABLE IF NOT EXISTS swarm_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  plan_id TEXT NOT NULL,
  plan_path TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('ready','running','done','aborted')),
  swarm_dir TEXT,
  integration_branch TEXT,
  base_commit TEXT,
  started_at TEXT,
  completed_at TEXT,
  notes TEXT,
  orchestrator TEXT
);
CREATE TABLE IF NOT EXISTS swarm_units (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER NOT NULL REFERENCES swarm_runs(id),
  unit_key TEXT NOT NULL,
  title TEXT NOT NULL,
  plan_phases TEXT,
  depends_on TEXT,
  resources TEXT,
  territory TEXT,
  model TEXT,
  model_reason TEXT,
  reviewer_model TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','working','review','parked','shipped','merged','failed','skipped')),
  branch TEXT,
  updated_at TEXT,
  result TEXT,
  lane TEXT,
  kind TEXT,
  pr TEXT
);
CREATE TABLE IF NOT EXISTS swarm_holds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER NOT NULL REFERENCES swarm_runs(id),
  tag TEXT NOT NULL,
  holder TEXT NOT NULL,
  detail TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  released_at TEXT
);
-- Every status change, logged by the database itself, so time estimates can learn stage durations.
CREATE TABLE IF NOT EXISTS swarm_unit_events (
  id INTEGER PRIMARY KEY,
  run_id INTEGER NOT NULL,
  unit_key TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  source TEXT NOT NULL DEFAULT 'live'
);
CREATE INDEX IF NOT EXISTS swarm_unit_events_unit ON swarm_unit_events(run_id, unit_key, at);
CREATE TRIGGER IF NOT EXISTS swarm_unit_status_event AFTER UPDATE OF status ON swarm_units
  WHEN OLD.status IS NOT NEW.status
  BEGIN INSERT INTO swarm_unit_events(run_id, unit_key, from_status, to_status)
        VALUES (NEW.run_id, NEW.unit_key, OLD.status, NEW.status); END;
CREATE TRIGGER IF NOT EXISTS swarm_unit_insert_event AFTER INSERT ON swarm_units
  BEGIN INSERT INTO swarm_unit_events(run_id, unit_key, from_status, to_status)
        VALUES (NEW.run_id, NEW.unit_key, NULL, NEW.status); END;
```

`swarm_unit_events` is written by the triggers, never by hand, so the timing record survives an
orchestrator that forgets. The upgrade below rebuilds `swarm_units`, which drops its triggers:
re-run the two `CREATE TRIGGER` statements after it. A run that started before the table existed can
be **backfilled** from its host's records (a PR's first commit → `working`, opened → `shipped`,
merged → `merged`) with `source = 'backfill'`. Leave out any stage that included waiting on the owner,
so the estimates learn work time, not waiting time.

`swarm_runs.status` is what makes phase inference work across sessions — keep it accurate at every transition.

`swarm_runs.orchestrator` is the name other sessions use to message the run's orchestrator session (the
name `ListAgents` reports as "This session is …"). `swarm_holds` records shared state a review session
has borrowed from a live run (see **Review flow**): one row per resource tag, open while `released_at`
is empty. **A brain created before these existed** gets them without a rebuild: `CREATE TABLE IF NOT
EXISTS` adds `swarm_holds`, and when `PRAGMA table_info(swarm_runs)` lacks `orchestrator`, run
`ALTER TABLE swarm_runs ADD COLUMN orchestrator TEXT;` once. Likewise, when
`PRAGMA table_info(swarm_units)` lacks `model_reason`, run
`ALTER TABLE swarm_units ADD COLUMN model_reason TEXT;` once.

`swarm_units.model` holds the tier the unit was last dispatched on (an agent type such as
`swarm-sonnet-medium`, **Model tiers**), and `model_reason` holds the signals behind it and any
difference between what was asked for and what was served. `reviewer_model` holds the reviewer's tier.
Setup writes the proposal and the orchestrator overwrites them when it dispatches, so the row always
records what actually ran and why.

`parked`, `shipped`, `lane`, `kind` and `pr` serve PR-mode runs (see **Team repositories**): `parked`
is built and held for the owner, normally only for a critical issue (see **Team repositories**); `shipped` has an open PR on its way through the
team's CI and review; `merged` then means the team merged it. **A brain created before these
existed** has a `swarm_units` table whose CHECK rejects the new statuses — `CREATE TABLE IF NOT
EXISTS` never alters it. When `SELECT sql FROM sqlite_master WHERE name = 'swarm_units'` lacks
`parked`, upgrade it once, in one transaction:

```sql
BEGIN;
ALTER TABLE swarm_units RENAME TO swarm_units_old;
-- the CREATE TABLE swarm_units statement above, verbatim
INSERT INTO swarm_units (id, run_id, unit_key, title, plan_phases, depends_on, resources, territory,
                         model, reviewer_model, status, branch, updated_at, result)
  SELECT id, run_id, unit_key, title, plan_phases, depends_on, resources, territory,
         model, reviewer_model, status, branch, updated_at, result FROM swarm_units_old;
DROP TABLE swarm_units_old;
COMMIT;
```

---

## Setup Flow

Goal: a committed, self-contained package a fresh orchestrator session can execute without a single human answer.

### Step S1 — Reconcile

Read the full plan. Run the `/plan` fresh-eyes pass in compressed form: verify the files, symbols, and line references the plan leans on still exist; check `git log` since the plan date for drift; check brain DB for plan-linked task status. If phases are already complete, they are excluded from the swarm, not re-done.

**Establish the checks contract.** Read `.claude/kit.json` `swarm.checks` (an array of shell commands). If absent, determine the project's check commands yourself (build, typecheck, lint, tests — whatever the repo actually uses) and record them in SWARM.md so no reviewer ever guesses. Then **run them on the current baseline**. A red baseline is a hard stop: a swarm cannot tell its own failures from inherited ones. Either the user fixes it before setup completes, or explicitly accepts the specific known-red checks as a logged decision that reviewers ignore those exact failures.

**Read prior retros.** Query `SELECT title, body FROM logs WHERE type = 'insight' AND tags LIKE '%swarm-retro%' ORDER BY id DESC LIMIT 10;` — lessons from earlier runs (slicings that merge-conflicted anyway, model assignments that failed review, estimate accuracy) directly inform S2.

### Step S2 — Decompose into units

A **unit** is the work one agent completes in one worktree: one phase, several phases, or part of a phase. Slice by these rules, in priority order:

1. **Serial chains that share files are ONE unit.** Parallelism comes from disjoint file territories, not from splitting a dependency chain across agents who would then merge-conflict on the same files. (E.g. a migration → scorer rewrite → re-score sequence touching the same modules is one unit for one agent.)
2. **Independent phases are separate units**, even small ones — they're free parallelism.
3. **A unit should be completable in one agent session.** Split a phase that mixes two independent territories; merge trivial phases into a neighbor.
4. Every unit gets: `depends_on` (unit keys — derived from real data/code dependencies, not plan numbering), `resources` (see below), `territory` (primary files/dirs it will edit — advisory, used for conflict forecasting), and its plan phases/items.
5. **A PR-mode plan decomposes by slice and lane instead** — each slice is a unit with a `lane` and a `kind`, its `depends_on` taken from the plan's *waits on* line, and its resource tags from `swarm.resources`. See **Team repositories**.
6. **A PR-mode plan keeps dependencies few.** Every *waits on* line costs a wait on the team's CI and review, so challenge each one at setup:
   - a slice waits on another only when its code cannot compile or run without it, never because the plan lists it later;
   - a chain small enough for one pull request is one slice;
   - a shared change that many slices need goes first, alone, or is built expand–contract (the new form beside the old) so adopters do not wait on a deletion;
   - what remains is stacked (**Team repositories**), and each surviving *waits on* says why in one clause.

   Report how many slices are independent in the parallelism profile.

**Resource tags** name shared mutable state *outside* git that the unit touches: `db:<name>` (a live database it migrates or rewrites), `deploy`, `tiles`, `dev-server`, or anything project-specific. Two units holding the same tag never run concurrently, even with disjoint code. Tag conservatively — a missing tag is a race, an extra tag is just lost parallelism.

Identify **gates**: plan checkpoints that must pass before dependents dispatch (e.g. a parity/measurement phase). A gate is a normal unit whose dependents simply wait on it.

**Propose a tier per unit and per reviewer** with **Model tiers**. For each unit, write the proposed tier and the signals that decided it into `model` and `model_reason`, and into the unit graph. This is a proposal. The owner can pin a unit's tier in S3, and the orchestrator makes the final call at dispatch (R2).

**Compute the parallelism profile.** From the graph: unit count, max useful concurrency, and the critical path as a share of total work. Turn it into a plain-words expectation for S3 — *"6 units, but the migration→scorer→re-score chain is ~70% of the work; expect roughly serial wall-clock with the UI phases riding alongside"*. A fully serial profile is fine — say so and proceed; the run is still autonomous end-to-end, which is the point. Never split a serial chain to make the profile look better.

### Step S3 — Resolve every open question with the user

This is the heart of setup. Collect and present, via AskUserQuestion (batched, with recommendations, each question naming the plan line it comes from, per `/plan`'s **Pointing at a line**):

1. Every open question in the plan's `## Open questions` (see `/plan`, **Batches**), and every item in its Risks section that requires human judgment. Setup is the batch's gate: a question that bites any unit is answered here
2. Every ambiguity or drift found in S1/S2
3. Run policy for THIS swarm: may agents touch the live/prod database? May the swarm deploy, or does the deploy phase get excluded and left for the user? Merge to main at the end, or leave the integration branch for review? (For a PR-mode plan — a team repository — the answer is never "merge to main", and the ship and look policies come from `swarm.ship` / `swarm.look` when kit.json records them; ask only what they leave open. See **Team repositories** below.) Max concurrent agents (default from `.claude/kit.json` `swarm.maxAgents`, else 6)?
4. Show the proposed per-unit tiers (from S2) as part of the setup summary: the tier and its deciding signal for each unit. Ask only about proposals that are genuine judgment calls. Tell the owner they can **pin** any unit's tier. A pin becomes a D-numbered decision in SWARM.md, and the orchestrator never moves a pinned unit at dispatch, though a failure can still escalate it (**Model tiers**)
5. Lead the summary with the parallelism profile and expected wall-clock shape, so the user knows what kind of run they're approving — a wide fan-out or a supervised serial march

Anything the user delegates back ("you decide") gets a committed default written down. **Where answers go:**
- A question about **what gets built** is answered in the plan itself, per `/plan`'s **Batches**. The answer goes into its **Answer:** line, then becomes one of the plan's numbered decisions.
- A **run-policy** answer (database, deploy, merge target, concurrency) goes into SWARM.md.

Log the material answers as brain `decision` entries (normal `/brainstorm` conventions, tagged `swarm`). **A question that survives setup unanswered is a setup failure** — either get it answered or write the decision rule an agent will apply.

### Step S4 — Write the swarm package

Create `cowork/swarm/<plan_id>/SWARM.md` (own directory — never inside a plan root, where it would pollute `/plan` numbering):

- **Run config** — plan path, merge target, policy answers from S3, max agents, the checks contract (exact commands reviewers run), and the parallelism profile
- **Decision record** — the run-policy answers and delegated defaults, numbered (`D1`, `D2`…) so briefs can cite them. Decisions about what gets built live in the plan, and briefs cite them by the plan's own numbers
- **Unit graph** — table: unit key, title, plan phases, depends_on, resources, territory, proposed tier (with `pinned` and the D-number when the owner pinned it) and its deciding signal, reviewer tier; plus a short dispatch-order narrative
- **Per-unit briefs** — one section per unit, fully self-contained (`### Unit U3 — <title>`): objective, the plan items it owns (copied, not referenced by number alone), file territory, what it must NOT touch, its verification criteria from the plan, relevant decisions (`per D4: …`), and known landmines from S1
- **The agent protocol** (copied verbatim into the file so briefs can reference it — see **Run rules** below)

Then:
- Insert the `swarm_runs` row (`status = 'ready'`, `swarm_dir`, `plan_id`, `plan_path`) and one `swarm_units` row per unit
- Add one line under the plan's title: `> **Swarm:** prepared YYYY-MM-DD — see cowork/swarm/<plan_id>/SWARM.md`
- Beyond the answers S3 wrote into it, do not rewrite the plan — it stays the source of truth for *what*; SWARM.md owns *who and in what order*

### Step S5 — Hand off

Tell the user: review `SWARM.md` (especially the decision record), giving the line range of the decision record, the unit graph and each brief, then commit (`/commit`), then start a **fresh session** and invoke `/swarm <ref>` — and that starting that session with `/rc` gives remote monitoring of the run. **Never start the run in the setup session** — the run deserves a full context window.

### Model tiers

Every agent a run spawns (builder, fixer, reviewer) is dispatched as one of five **tiers**. A tier is an
agent type in `.claude/agents/` that fixes both the model and the reasoning effort. The Agent tool has
no per-call effort, so the agent type is the only way to set it. The definitions name models by
alias (`sonnet`, `opus`), so they always get the newest model the running Claude Code knows.

| Tier (`subagent_type`) | Model · effort | For a task that is… |
|---|---|---|
| `swarm-sonnet-low` | sonnet · low | **very simple**: a copy or label sweep, config plumbing, an explicit item list in one or two files |
| `swarm-sonnet-medium` | sonnet · medium | **typical and well defined** (the default): the brief names the files and items, the territory is one module or follows an existing pattern, verification is concrete |
| `swarm-sonnet-high` | sonnet · high | **slightly above average**: well specified but with more moving parts, such as several files in one module, logic with edge cases to test, or user-facing UI to verify |
| `swarm-opus-medium` | opus · medium | **two notches above average**: exactly one unstarred signal from the table below, or a narrow ★ unit that has no pattern to copy |
| `swarm-opus-high` | opus · high | **three notches above average**: a ★ signal with reach (dependents, several packages, an open fork), or two or more signals |

A unit's brief is self-contained and fully specified: objective, the plan items copied in, territory,
what not to touch, and how to verify. That is narrow, pre-specified work, and Sonnet does it well. So
**`swarm-sonnet-medium` is the default**, and a unit goes to Opus only when a signal applies. Lean
toward the cheaper, faster tier: when a unit sits on the line between two tiers, pick the lower one and
let review and **Escalation** catch a miss. A wrong low pick costs one review cycle, while a wrong high
pick costs time and tokens on every unit it touches.

| Signal | Why it needs Opus |
|---|---|
| ★ Holds a resource tag (a live database, deploy, anything outside git) | A mistake there is not undone by reverting a branch |
| ★ Is a gate | Everything after it trusts its result |
| ★ Algorithm, scoring, concurrency, auth, permissions or security work | Correctness depends on reasoning, not on following a pattern |
| Two or more units depend on it | A weak result spreads to every unit after it |
| Its territory spans modules and the codebase has no pattern to copy | The design is being invented, not repeated |
| The brief leaves a genuine fork open ("decide X") | The call is the work |
| Builds on an upstream call marked `uncertain`, or on a conflict the orchestrator resolved | Its footing moved after setup wrote the brief |
| A remainder-run unit whose earlier attempt failed | It has already beaten one attempt |

Do not move a unit up a tier out of general caution. Each step up needs a reason you can name.

**Narrow ★ units build on Sonnet, reviewed by Opus.** A ★ signal is about what's at stake, not
always about how hard the work is. When a ★ unit is **narrow** (one clause, one function, or one
file) and **copies a pattern the codebase already has** (the brief names the precedent), and it has
no other signal (no dependents, no open fork, no resource tag), build it on `swarm-sonnet-high` and
give it a `swarm-opus-high` reviewer. The builder follows the pattern, and the Opus reviewer judges
whether the result is safe. Record `narrow ★, pattern <precedent>` in `model_reason`. A narrow ★ unit
with no pattern to copy goes to `swarm-opus-medium`. Resource tags and gates never take this route:
they stay on Opus.

**Reviewers** use the same tiers:

| Tier | Reviews |
|---|---|
| `swarm-opus-high` | Gates, units whose failure cascades, a narrow ★ unit built on Sonnet, and the final integration review (R3), which is always this tier |
| `swarm-opus-medium` | A Sonnet-built unit that reports an `uncertain` call, and a unit that asked for Opus but ran on Sonnet |
| `swarm-sonnet-medium` | **Default reviewer** |
| `swarm-sonnet-low` | A checklist review of a `swarm-sonnet-low` unit: files changed match the territory, grep-level checks, the project's checks pass |

**Who decides.** Setup proposes (S2) and the owner can pin (S3). The orchestrator makes the final call
when it dispatches (R2): it re-runs the tables with what the run has shown so far, and records the
tier and the signals that decided it in `model` and `model_reason`. It may move an unpinned unit
either way. A pinned unit keeps its tier at dispatch. Escalation after a failure applies to every
unit, pinned or not.

**Escalation.** A tier that turns out too low costs a review cycle, not a stalled run:
- **First fix cycle:** if the reviewer's findings are about judgment (the wrong approach, a missed edge
  case, a misread of the brief), the fix runs at least on `swarm-opus-medium`, or one tier above the
  unit's if that is higher. Mechanical findings (lint, a missed item, a failing check with an obvious
  cause) keep the unit's tier.
- **Second fix cycle:** always `swarm-opus-high`.
- **Watchdog re-dispatch:** the unit goes out one tier higher.
- **Run-level:** when two Sonnet-built units in one run fail review on judgment, the tiers are too
  loose for this plan. From then on, every undispatched unit the owner has not pinned goes out one tier
  higher. Record this as an amendment.

**The orchestrator itself** runs on whatever model and effort the run session was started with. It
makes the tier calls and resolves every merge conflict, so it should be Opus. R1 says so when it is not.

**When the tiers are missing.** Agent definitions load when a session starts. A session started
before `.claude/agents/swarm-*.md` existed, or a project installed without them, has no tier types
(the Agent tool answers "Agent type not found"). Fall back to `general-purpose` with the tier's model
passed as the per-call `model`. The effort then follows the orchestrator's. Say so in the dispatch
message, and tell the owner a fresh session picks the tiers up.

**Checking what was served.** The tier you request is not always what runs:
- **Why it can differ.** Some Claude Code versions have ignored a requested subagent model
  (anthropics/claude-code#83920, #97588), and the `CLAUDE_CODE_SUBAGENT_MODEL` settings can override
  it. The VS Code UI can also show a subagent's model wrongly (#97634), so it is not evidence.
- **Where the truth is.** Every assistant message in a subagent's transcript records the model the API
  served and the effort it ran at. Read them from the transcript the Agent tool's launch result names
  as `output_file`:
  `jq -r 'select(.type=="assistant") | "\(.message.model) \(.effort)"' <output_file> | sort | uniq -c`.
  A tier is honoured when the served model's family matches (`claude-sonnet-…` for a Sonnet tier) and
  the effort matches. That file's format is internal to Claude Code: extract only those fields, never
  read the whole file, and if they cannot be parsed, record the served tier as `unverified`.
- **When it differs.** A unit that ran above its tier costs more and needs nothing else. A unit that
  asked for Opus and ran on Sonnet gets a `swarm-opus-medium` reviewer or higher (R2 step 3). One that
  ran at a lower effort than asked is reviewed one tier higher than planned.

### Team repositories (PR-mode plans)

A plan carrying `**Mode:** pr` lands in a repository other people own, through reviewed pull
requests. The swarm still completes the plan without stopping, but two things change: the unit
of shipping is the plan's **slice**, and a slice is finished when **the team** merges its PR.
User-facing slices ship like any other; the owner reviews the recorded calls when they choose,
and only a critical issue holds a slice for them.

**Units are slices; lanes are the parallelism.** Read each slice's lane and *waits on* line from
the plan. A **lane** is a chain of slices over the same files — usually one adopter or one
package — and its slices run in order, while lanes that share no files run side by side. Never
split a slice's files across two agents. A slice may **stack** on its lane's previous slice
(branch from that branch, in its own worktree) so the lane never stalls behind a review or CI; once the
earlier slice's squash merge lands, the later one replays only its own commits
(`git rebase --onto origin/<default> <earlier-branch-head>`, run in that slice's worktree).
A dependent is **ready to build as soon as the slice it waits on is `shipped`**: it never waits for
that pull request to merge. When it finishes building it checks the parent's pull request once. If the
parent has merged, it replays onto the default branch and ships. If not, it stops there as
`parked` with `result` beginning `stacked on <unit>`, hands its slot back, and **Landing** ships it
when the parent merges. A stacked unit is not waiting on the owner and is never listed as a park.

**Every unit carries a `kind`**, which says how its UI is verified. None of them waits for the owner:

| kind | means | ships |
|---|---|---|
| `invisible` | nothing a user can see changes: plumbing, a shared package, config | as soon as its checks and review pass |
| `fix` | restores intended behaviour, with no design choice in it | the same |
| `user-facing` | a change a person will see or feel | the same, after the UI is verified by code, then headless, with anything unverifiable recorded |

**Park only for a critical issue.** A team repository often merges and deploys a green pull
request on its own, so a unit that would ship something critical must not: irreversible or
outward-facing action not pre-approved in SWARM.md, a security, privacy or permissions exposure,
money, a production data change, or a reversal of a decision the owner explicitly made. That unit
parks, its dependents stack on its branch, and the owner is notified. When unsure, it is not
critical: make the call, ship it, record it. A call is always functional, never a hollow stub. At a
genuine fork, where it is truly unclear which way is best, the call is built lean: working end to
end, with follow-on work kept to a minimum and polish left for a later pass, so little is un-built
if the owner overrules it. An overruled call becomes a fix slice, which is cheaper than a stalled lane.

**Resource tags come from the project's map.** A team repository usually shares one local stack
across every worktree: dev servers bound to fixed ports, one local database, one package
install. `swarm.resources` in `.claude/kit.json` maps path globs to tags, so setup tags each unit
by the territory it touches instead of guessing. Two units holding a tag never run at once.

**Where the code lives.** When the plan's code is a checkout other than the session's own repo —
a sibling clone, a symlinked repository, a submodule — the Agent tool's `isolation: "worktree"`
isolates the **wrong** repository. Each unit then creates its own worktree in the target
checkout at `.claude/worktrees/<slug>`, using the create and bootstrap commands from
`swarm.worktree` in kit.json. It works only there, and removes the worktree once its slice has merged. The target's
primary checkout is someone's IDE too, so its branch is never switched (**Branches live in worktrees**).

**A worktree pool, when the project has one.** Creating a worktree per agent is expensive in a big
repository: every build, fix, ship and replay agent pays for a fresh checkout and dependency install,
installs queue behind each other, and removing them all stalls the orchestrator. When
`swarm.worktree.pool` is set, units **lease a slot** instead:

- **Slots are bootstrapped once and reused.** They persist across runs; nothing removes one mid-run.
- **A unit leases a slot at dispatch** (the pool's `acquire` command, with the unit's lane and
  branch) **and hands it back once its branch is pushed** (`shipped`) or it parks (`release`). A
  released slot is reset to a clean, detached default branch with its installed dependencies kept.
- **Lane affinity.** The pool prefers the slot the lane used last, so a stacked slice starts where its
  parent's tree already is, and a replay onto the default branch is an in-place rebase.
- **A fix, ship or replay agent for a unit reuses that unit's slot** while it still holds one. For a
  `shipped` unit it leases again (affinity usually returns the same slot) and switches to the
  existing branch; it never creates a new worktree.
- **No free slot is a scheduling signal, not an error:** the unit waits for the next release, like a
  unit waiting on a resource tag. Size the pool at the concurrency cap plus two.

**Standing policies are read, not re-asked.** A project may record two in kit.json; setup reads
them and asks (S3) only what they leave open:

- `swarm.ship` — how a finished slice's PR goes up. `ready`: the owner has pre-approved ready
  PRs, and a slice is a draft only on their word. `draft`: every PR opens as a draft. `ask`
  (the default): the ship command asks, which an unattended run cannot do, so the slice parks
  with the question.
- `swarm.look` — whether user-facing work waits for the owner. `none` (the default): it never
  does, and only critical issues park. `batch`: an opt-in for projects that want the older flow,
  in which every user-facing slice parks for one batch look. `per-slice`: each user-facing slice parks
  and notifies on its own.

**The run, per slice:**

1. **Build** in the unit's worktree with the project's quick checks. **Verify UI by code first**
   (types, tests, the rendering logic), then **in a headless browser of the agent's own** (`/look`,
   **Headless**) when code cannot settle it. What neither verifies is recorded as unverified and
   left; the agent does not keep trying. No agent verifies in a headed browser: it never drives the
   owner's shared window and never launches a visible browser of its own.
2. **Every slice ships:** write its tests, then run the project's ship command (`rules.plan` names
   it) under the `swarm.ship` policy. Its calls and unverified items go into the plan's review
   block, and the unverified ones also go into the PR notes.
3. **Only a critical slice parks** (`status = 'parked'`, see above), with the reason in the
   review block, and so does every user-facing slice when `swarm.look` opts into `batch`.
4. **The team's own review tool is the reviewer** when `swarm.review` names one — a review bot
   whose verdict the team's merge honours. It runs against the pushed head and replaces the
   swarm's reviewer agent for that unit; a second review would be duplicate spend. A blocking
   finding is fixed and re-reviewed, two cycles at most, then `failed`.
   **When `swarm.review` is `"team"`**, the team's bot reviews every pull request by itself once it
   is open, and its verdict is what the merge honours. Then no review runs before the push and no
   reviewer agent is spawned for the unit: the unit ships as soon as its checks pass, and a blocking
   verdict reaches **Landing** like a red CI group. The project's rules name any class of slice that
   still gets a review before it ships.
5. **The build run ends at the push.** A shipping agent ends at the push and never waits on CI or
   review, and neither does the run: once every unit is `shipped`, stacked, `parked`, `failed` or
   `skipped`, the orchestrator finalizes (R4) and the builder slots are free for the next run. What
   happens to the open pull requests after that is **Landing**'s job.
6. **Landing watches CI and fixes on red at once.** One watcher covers every open PR (`status =
   'shipped'`, `pr` recorded).
   **A red caused by the CI infrastructure** (a process killed for memory, a lost or hung machine,
   every failing test at 0–1 ms) is rerun first — by the project's watcher when `swarm.watch` names
   one — and gets a fix agent only if it repeats on the same head. When a CI group fails, push the fix as soon as it is ready — that run is already
   lost, and waiting only lets the default branch move under the PR. A PR the host reports as
   conflicting is re-synced by merging the default branch in, once reviewers have seen its
   history.
7. **`merged` means the team merged it.** When the PR lands on the default branch, Landing marks
   the unit and replays and ships whatever was stacked on it.

**Never merge anything into the team's default branch locally.**

#### Landing

A team's CI and review take minutes to tens of minutes per pull request, and nothing a builder does
makes them faster. So the build run does not wait for them. **Landing** is the small loop that
follows the open pull requests to merged. The orchestrator enters it in its own session as soon as
the build run is finalized, and `/swarm land` enters it from any later session; either way it is
safe to start a new build run for another plan while it goes on.

- **It holds no builder slots.** At most `swarm.land.maxAgents` agents (default 2) work for it at
  once, each leasing a worktree or pool slot only for its fix or replay. Its heavy steps go through
  the same gate as everyone else's (**Machine budget**).
- **It is event-driven.** Start the project's watcher (`swarm.land.watch`, `<prs>` replaced by the
  open PR numbers) in the background. It exits when any pull request changes state, which re-invokes
  the session. Never poll in the foreground. With no watcher configured, use one background wait
  matched to how long the team's CI takes, then read every open PR's state once.
- **On each wake, for every unit whose pull request changed:**
  - **Merged** → set `merged`, tick its plan items, close out its issue if the project does that.
    Then, for each unit stacked on it: lease a slot, replay its own commits onto the default branch,
    run the ship command, set `shipped`.
  - **A CI group red, or the team's review tool blocked it** → one fix agent on the unit's branch
    with the failing output, tier by **Model tiers**, **Escalation**. Push the fix as soon as it is
    ready. Two fix cycles at most, then `failed`, and whatever is stacked on it becomes `skipped`.
    An infrastructure red is left to the project's rerun (`swarm.watch`) unless it repeats on the
    same head.
  - **Conflicting with the default branch** → re-sync it (merge the default branch in) and push.
  - **Closed without merging** → `failed`, with who closed it in `result`.
- **Nothing here waits on the owner** except a critical park, which was already recorded at build time.
- **It ends when no unit is `shipped` or stacked.** Then: append a **Landing** section to the run's
  `REPORT.md` (merged, failed, fix cycles, the time from push to merge per unit), log the retro
  entries R4 would have logged about CI and review, and send one push notification with the outcome.
- **A stalled pull request is a finding, not a wait.** One with no state change for a long time
  (three times the team's usual CI time) is read once: a required check that never started, a review
  nobody was asked for, a label that pauses CI. Record what it is waiting on in `result` and in the
  report, notify once, and keep landing the rest.

**An optional batch look happens beside the run, not inside it.** When a slice is parked for a
critical issue, when `swarm.look` opts into looks, or when the owner asks, the orchestrator:

1. tidies the plan's `## Review` block (`/plan`, **Batches**) into one numbered list for all of
   them: each look with its URL, what changed, what to try, what right looks like, the widths and
   what it **runs on** (the app, and the checkout that serves it — normally the lane's latest
   branch, which carries every slice stacked in it; a look that needs another branch, such as a fix
   that shipped from its own, names that one), and each call with its options and switching cost;
2. sends a push notification that the review is ready — the one mid-run interruption worth
   sending — telling the owner to open a **parallel session** and run `/swarm review`;
3. keeps dispatching. The review session serves the pages, borrows only the shared state they
   need (recorded in `swarm_holds`, and announced to this session by message), gives each piece
   back as soon as its looks are done, and ends with one handoff (**Review flow**).

When the handoff arrives:
- **Re-read the plan from disk before writing it.** The owner marks items in the plan directly, and
  those marks are uncommitted edits.
- Apply the handoff as **one amendment** across the slices it touches: D-numbered in SWARM.md, and
  a product or design answer also becomes a plan decision. A consequence the review session applied
  without asking is flagged as that in the review block.
- Only what changed is shown again at the next look. A slice that was parked for the look writes its
  tests and ships once approved; under the default (`swarm.look: none`) the rest have already shipped.

A run whose remaining work is critical parks waiting on the owner is **waiting, not stalled**, and so
is a unit waiting on a review hold: the status says so, and the stall watchdog leaves both alone.

---

## Run Flow

The orchestrator session. It dispatches, reviews, merges, and reports. It writes the plan file, SWARM.md, REPORT.md, and the brain; agents never do.

### Step R1 — Load and preflight

1. Load the `swarm_runs` row, `SWARM.md`, and the plan. Ensure `status = 'ready'`.
2. Preflight. The primary checkout's branch and working tree are the owner's and are not checked; it can be on any branch, with edits in progress.
   - The merge target's tip contains the committed swarm package (`SWARM.md` and the plan with its answers).
   - `git worktree list` shows no leftover `swarm/` worktrees.
   - `.claude/worktrees/` is ignored (**Branches live in worktrees**).
   - This session runs on `opus` (**Model tiers**). If it does not, say so in the dispatch message
     and continue. That message is the owner's cue to restart on `opus` if they want to.
   - **The tiers load and are honoured** (**Model tiers**). Spawn one probe as `swarm-sonnet-low`
     with a one-line prompt, then read what it was served from its transcript (**Checking what was
     served**). If the type is not found, use the fallback in **When the tiers are missing**. If it was
     served something other than Sonnet at low effort, tiers are not being honoured in this session.
     In either case, say so in the dispatch message, send a push notification, and continue. Units
     then run on the orchestrator's model or effort, which costs more but builds no worse.
   - **The prompt guard is live.** The same probe's prompt asks it to run `cd /tmp && git --version`
     once and report what came back. A refusal that names `bash-guard` means agents cannot stop the
     run on a permission prompt. Anything else (the command ran, or the owner was asked) means the
     hook in the agent definitions did not load: say so in the dispatch message, send a push
     notification, and lead every unit's prompt with the **Never make the owner approve a command**
     rule under a bold heading, since the written rule is then the only protection.

   If commits landed since setup, do a fast delta check. If they invalidate unit briefs, stop and tell the user to re-run setup; don't guess.
3. Create the integration branch in its own worktree, from the merge target's tip, never from the primary checkout's HEAD: `git worktree add -b swarm/<plan_id> .claude/worktrees/swarm-<plan_id> <merge-target>`. Never check it out in the primary checkout. Record `base_commit`, `integration_branch`, `started_at` and `orchestrator` (this session's name, from `ListAgents`), and note the worktree path in SWARM.md's run config. Set status `running`.
4. Announce the dispatch order in one short message (this is what `/rc` monitoring sees first).
5. **Hand the owner a progress display with live time estimates** (`/pbar`), unprompted, as the last
   thing in that message. It shows units merged out of the total, what is in flight, anything parked,
   and open PRs. It also carries the estimate block from `eta.py` in this skill's folder:

   ```bash
   python3 <this skill's folder>/eta.py --db cowork/brain/BRAIN.db --run <id> --slots <maxAgents> [--stack-in-lane]
   ```

   Pass `--stack-in-lane` for a PR-mode run whose lanes stack. The block gives:
   - **each in-flight action:** the unit's stage (build or land), elapsed, expected, time left, and OVERDUE past it;
   - **each lane (phase):** units done out of total, and its finish time;
   - **the whole run:** time left, a finish clock time, and a slow case.

   It learns each stage's duration from `swarm_unit_events`, starting from a prior and pulling toward
   the observed median as units finish, with this run's own samples weighted double. So **the estimate
   gets more accurate as the run goes**, and it says how many samples it rests on. Parked units, and
   everything waiting on them, get no estimate: the display names what they wait on. The script is
   read-only. Re-print the display's command whenever you give a status update (`/pbar` §4b).

### Step R2 — Dispatch loop

Event-driven, until every unit is terminal (`merged`, `failed`, or `skipped`):

1. **Ready set** = pending units whose `depends_on` are all `merged` and whose `resources` collide with no unit currently `working`/`review`. In a PR-mode run a dependency counts once it is `shipped` (or stacked): the dependent builds stacked on its branch and never waits for the merge (**Team repositories**).
2. **Pick each ready unit's tier** (**Model tiers**). Start from its proposal, keep it if pinned, and otherwise re-run the tables against what the run now knows: the calls and conflicts in the units it depends on, and how Sonnet-built units have fared in review so far. Write the result and its deciding signals to `model` and `model_reason` before dispatching.

   Dispatch every ready unit up to the concurrency cap, in a single message: `Agent` tool, `subagent_type` = the tier just picked, `run_in_background: true`, `isolation: "worktree"`. Pass no `model`: the tier sets it. Never dispatch a unit as `general-purpose` except as the fallback in **When the tiers are missing**, since that would inherit the orchestrator's model and effort. The prompt is the unit's brief from SWARM.md plus the agent protocol, plus: unit key, run id, the brain's absolute path (for the review-hold check), integration branch name, the integration tip's sha at dispatch, and required branch name `swarm/<plan_id>-<unit_key>`. The Agent tool's worktree does not start on the integration branch, so the agent's first step creates its branch from that sha inside its own worktree. The sha carries every dependency merged so far. An open review hold never blocks dispatch: units honour it themselves, only at the step that uses the held state. Mark units `working`. When the plan's code lives in a checkout other than the session's repo, dispatch without `isolation` and have the brief create the unit's worktree in the target checkout with `swarm.worktree`'s commands (see **Team repositories**).
3. On a completion notification: **check what was served** (**Model tiers**, **Checking what was served**). When it differs from the tier requested, record both in `model_reason` and adjust the reviewer's tier as that section says. Then spawn a **reviewer agent** (read-only, background, `subagent_type` = the unit's reviewer tier, raised to at least `swarm-opus-medium` when a Sonnet-built unit reports an `uncertain` call) with the unit brief, the worktree path, the unit's verification criteria, and the checks contract from SWARM.md (exact commands — reviewers never guess). It inspects the diff, runs those checks in the worktree, and returns PASS or FAIL with findings. Mark the unit `review`.
4. **Reviewer PASS** → merge the unit branch into the integration branch, in the integration worktree (`git -C .claude/worktrees/swarm-<plan_id> merge …`). The orchestrator resolves any conflicts itself — it holds every brief and both sides of the conflict; agents never see each other's work. Then:
   - mark plan items `- [x]` with progress notes (per `/plan` conventions);
   - append the unit's **Calls**, **Unverified** items and any **Critical** park to the plan's `## Review` block (`/plan`, **Batches**) — the orchestrator is its only writer;
   - update `swarm_units` (`merged`, `result` = one-line summary);
   - remove the unit's worktree, **in the background** (`run_in_background`), never inline in the
     dispatch loop, or release its slot when the project has a pool. The plan edits stay uncommitted in the primary checkout;
   - loop back to 1, because a merge may unblock dependents.
5. **Reviewer FAIL** → spawn a fix agent in the same worktree with the findings. Pick its tier by **Model tiers**, **Escalation**: at least `swarm-opus-medium` when the findings are about judgment, the unit's tier when they are mechanical, and always `swarm-opus-high` on the **second** cycle. Update `model` and `model_reason` whenever the tier changes. Max **two** fix cycles; then mark the unit `failed`, record why, and continue — everything not depending on it still runs. Dependents of a failed unit become `skipped`.
6. Post a one-line progress note as each unit changes state. Between events there is nothing to poll — background agents re-invoke the session when they finish.

**Stall watchdog.** A hung agent never sends a completion notification, and a remote-monitored run that silently stalls defeats the system. Keep a background timer alive whenever units are in flight (a background `sleep 1800` re-invokes the session when it exits; restart it each cycle). On each wake: any unit in `working`/`review` with no state change for ~30 minutes gets investigated — `ListAgents` to see if its agent is alive. Dead agent, no commits → reset the unit to `pending` and re-dispatch one tier higher. Dead agent, commits present → send to review. Alive and progressing → leave it, reset the timer. Two watchdog re-dispatches on the same unit → mark it `failed` and move on. A unit waiting on an open review hold is not stalled. A hold whose holder session has left `ListAgents` is released: set `released_at` and note it.

**Mid-run steering.** The no-questions rule binds agents, not the user. A user message arriving mid-run (typically via `/rc`) is an **amendment**: append it to the SWARM.md decision record, timestamped, continuing the D-numbering; one that decides what gets built also becomes a plan decision, and clears any review item it answers. Amendments apply to not-yet-dispatched units immediately; in-flight units are unaffected unless the user explicitly says to stop one (then `TaskStop` it and re-dispatch under the amended brief, or skip it, per their instruction). Every amendment and its effect is listed in REPORT.md. Never pause the swarm to wait for possible steering — amendments are applied when they arrive, not solicited.

### Step R3 — Integration gate

When all units are terminal — and for a PR-mode run that means `shipped`, stacked, `parked`,
`failed` or `skipped`, since the build run ends at the push (**Team repositories**). A PR-mode run
has no integration branch to verify: skip to R4, then continue into **Landing**.

1. Run the plan's Verification table end-to-end in the integration worktree, plus the project's standard checks.
2. Spawn a final reviewer over the integration branch's full diff against `base_commit`: cross-unit coherence, plan coverage, nothing half-merged. Always `swarm-opus-high` — this is the last line of defense, never economized.
3. Fix findings directly (orchestrator or a fix agent). This is the last line of defense before the merge target.

### Step R4 — Finalize

1. Merge the integration branch into the merge target per the setup decision. The default is to merge to main locally with no push; if the decision was to leave the branch, say so prominently. A PR-mode plan merges nothing into the default branch: each slice's branch is left for the ship command, per **Team repositories**. To merge without switching any checkout's branch:
   - **Bring the target in first.** In the integration worktree, merge the merge target into `swarm/<plan_id>`. That picks up anything the owner committed during the run. Resolve conflicts there, and re-run the checks if anything came in.
   - **Then fast-forward the target.** If the primary checkout has the target checked out, run `git -C <primary> merge --ff-only swarm/<plan_id>`. This advances the owner's branch in place; git refuses if it would overwrite their uncommitted edits. If no worktree has the target checked out, run `git fetch . swarm/<plan_id>:<merge-target>`.
   - **If git refuses,** leave the branch, and say plainly why and what the owner runs to finish. Never stash, reset or check out anything to force it.
2. Update the plan: `**Status:** done` on completed phases, RESUME WORK HERE banner on the first failed/skipped item if any. Mark linked brain tasks done (per `/plan` update conventions).
3. **Tidy the plan's `## Review` block** (`/plan`, **Batches**): every call, unverified item and critical park the run produced, deduplicated, numbered 1…N with the critical parks first. Only the critical parks hold anything; the calls are a record the owner reads and overrules when they choose.
4. Write `cowork/swarm/<plan_id>/REPORT.md` — **the user's morning-after read**:
   - Outcome summary: units merged / failed / skipped, wall-clock, phases done
   - **Waiting on you** — the count of critical parks (what actually waits), the count of calls and unverified items, and a pointer to the plan's `## Review` block. The block is the one list; the report never keeps a second one
   - Verification results (actual output, including anything that failed)
   - **Tiers** — one row per tier: units built, first-pass review rate, and fix cycles. Then list each unit that escalated, with its original tier, the tier it finished on, and why, and each unit whose served model or effort differed from its tier
   - Follow-ups and loose ends, routed like `/plan carry` would
5. **Retro to the brain.** Log 2–4 `insight` entries tagged `swarm-retro`: which unit slicings merge-conflicted despite disjoint territories, how each tier fared in review (a tier that kept escalating was too low for its tasks; an Opus tier that never found anything to fix may have been more than needed; whether narrow ★ units built on Sonnet passed their Opus review), and which **Model tiers** signals (from `model_reason`) predicted a failure or turned out unneeded, actual wall-clock vs. the setup profile, anything that would change the next setup's slicing. This is what S1 reads next time — the heuristics improve from your runs, not from guesses.
6. Set run status `done` (`completed_at`), remove the remaining unit worktrees, delete merged unit branches, and keep the integration branch.
   - **Commit the bookkeeping** in the primary checkout, limited to its paths: `git -C <primary> commit --only -- <plan> cowork/swarm/<plan_id>/`. The owner's other staged and unstaged work stays as it was. The review marks in the plan go in with it. Skip the commit, and say so, when the primary checkout is not on the merge target or is mid-merge, mid-rebase or mid-cherry-pick.
   - **Merged:** also remove the integration worktree, never with `--force`. A dirty one means something was written there by mistake: report it and leave it.
   - **Left for review:** keep the integration worktree, so the owner can open it without switching their IDE's branch.
7. **Notify.** Send a push notification (`PushNotification`) with the one-line outcome — "Swarm 021: 5/6 units merged, U4 failed, 1 critical park waiting on you, 12 calls recorded (see the plan's Review)". The user designed this to run while they're away; completion and failure are the two interruptions worth sending. Also notify on a hard mid-run stop (baseline drift, aborted run).
8. Final message: outcome first, then how many critical parks wait on the owner and how many calls were recorded, with the line range of the plan's `## Review` block, and where the report is. If anything failed, say so plainly — never bury a failed unit in a success narrative.

### Resume (status = 'running')

An interrupted run. Record this session's name as `swarm_runs.orchestrator` (a review session messages it there). Reconcile before touching anything: `ListAgents` for still-live agents, `git worktree list` + branch state vs `swarm_units` rows. If the integration worktree is gone, re-add it from the existing branch (`git worktree add .claude/worktrees/swarm-<plan_id> swarm/<plan_id>`); never check the branch out in the primary checkout. A unit `working` with no live agent and no commits → back to `pending`; with commits → send it to review. Then re-enter the dispatch loop.

---

## Machine budget

A swarm shares one machine with the owner, who is working on it, and with any other session running there. Left alone, every unit's checks assume they have the whole machine: a test runner starts a worker per core, a check script fans out across the cores, each unit starts its own dev server and browser. Six units doing that at once ask for several times the cores and the memory there are, and the machine stalls for everyone. So a run keeps to a budget, and the budget covers **memory as well as cores**: a machine that runs out of memory starts swapping, and from then on everything on it is slow, the owner's work included.

**The budget's only job is to keep the machine usable. It is not there to slow the run.** Every limit below is either free (it costs the run nothing) or adaptive (it only bites while the machine is actually short). With memory to spare, a run goes as wide as `maxAgents` allows. Prefer the adaptive limits to a low fixed cap: a cap low enough to be safe in the worst moment wastes the machine the rest of the time.

- **Fewer builders than cores.** `swarm.maxAgents` caps the units building at once. The default is 4. Agents that are reading and editing are cheap; their checks, servers and simulators are not.
- **Heavy steps take turns.** A heavy step is anything that loads the machine for more than a moment: a check or test run, a type-check or build, a browser capture run. Every heavy step goes through the gate:

  ```bash
  <this skill's folder>/machine.sh run --label "<unit>: <what>" -- <command> [args…]
  ```

  The gate has `swarm.machine.heavySlots` slots (default 2), machine-wide, across every swarm on the machine. A step waits its turn, then runs at lower priority with the project's worker caps (`swarm.machine.env`) in its environment, and exits with the command's own code. A holder that died gives its slot back.
- **A big step takes more than one slot.** A native app build, a production bundle build, anything that uses every core and several gigabytes: pass `--weight <slots>` (or `all`), or list it once in `swarm.machine.weights`, which matches text in the command line so no agent has to remember. Weight it so two of them cannot run at once but a light check still can beside one: with three slots, a weight of 2. `all` is for the rare step nothing should run beside.
- **The gate waits for memory, not only for a slot.** Before a step starts, the gate reads the machine's memory state (`machine.sh pressure`): the kernel's pressure level, the share of memory free, and whether swap has grown since the last reading. While memory is short the step waits (for `memWait` seconds at most, then runs anyway), holding its slot so nothing piles in behind it. With memory to spare this check adds no delay. How much swap is in use is never the signal: that number is a high-water mark and stays high long after the shortage has passed.
- **Servers are leased, never free.** A dev server is one to three gigabytes for as long as it runs, so it counts. Start every long-running server through a lease:

  ```bash
  <this skill's folder>/machine.sh serve --tag <resource tag> -- <command> [args…]
  ```

  One holder per tag (two units can never start the same app on the same port), and at most `swarm.machine.serverSlots` servers at once (default 2). The lease lasts until the command exits; a unit stops its server the moment its page checks are done. When the tag or a slot is still taken after `serverWait` seconds, `serve` exits 75 and says who holds it: the unit does everything else first, tries once more, then records the page check as unverified. A project's own serve script should take the lease itself, so units cannot forget.
- **Standing resources start on demand and stop when their lane ends.** A simulator, an emulator, a virtual machine, a database a few units need: the unit that holds its resource tag starts it, and the last unit of that lane stops it. Never start one at preflight "for the run", and never leave one up between lanes. Several gigabytes sitting idle for hours is the easiest way to run a machine out of memory, and starting one on demand costs seconds. Two lanes that each need a multi-gigabyte standing resource may run side by side when the machine has room: each checks `machine.sh pressure` before it starts its resource, and waits while memory is short.
- **No daemons left behind.** A build tool that leaves a daemon running after the build (a compiler server, a build daemon) is told not to, in `swarm.machine.env` or on its command line. A unit that started one anyway stops it before it reports.
- **Run only the checks the change can affect.** Related tests, the type-check of the packages touched, the guards the diff can trip. A whole package suite, or the whole repository's, belongs to CI when the project has one; a unit runs one locally only when the project's checks say so.
- **Clean up what you started.** Before reporting, a unit stops every server, watcher, browser, simulator and daemon it started, by process id or port. After each report the orchestrator sweeps the unit's worktree (`machine.sh sweep <worktree>`), which stops anything still running from inside it, and says so in the run log when it found something. **A unit that is stopped mid-run is swept too**: pausing or aborting a run sweeps every in-flight unit's worktree and stops the standing resources those units held.
- **The orchestrator dispatches by memory, not only by count.** Before each dispatch it runs `machine.sh pressure`. When memory is short it dispatches nothing new, waits for the next unit to finish (or a few minutes), and reads again; as soon as it reads `ok` it fills the slots again. This hold is temporary and needs no amendment. Only a machine that stays short with nothing new dispatched is a finding: then lower `maxAgents` by one for the rest of the run, record it as an amendment with what `machine.sh list` and the largest processes showed, and put the cause in the report.
- **Setup budgets the standing load.** At setup, list what will stay running for the length of the run (the project's shared stack, a container VM, the owner's editor) and what each standing resource costs, and set the slots and the weights so the common case fits in the machine's memory with room left for the owner. Keep `maxAgents` as high as the project's settings allow: the pressure check handles the worst case. Record the arithmetic in SWARM.md's run config.

## Run rules (the agent protocol)

Copied into SWARM.md at setup; binding for every spawned agent.

- **Never ask the user anything.** Facing a judgment call, including a design, layout or wording one? Decide as a senior developer would, applying the decision protocol: (1) the plan and its decisions are authoritative → (2) the SWARM.md decision record → (3) brain DB decisions → (4) the codebase's conventions and the smallest reasonable reading of the item. Build it so it works, keep going, and record it under `Calls`. A call the owner overrules later becomes a fix slice, which beats a stalled swarm.
- **At a genuine fork, decide and build lean.** When it is truly unclear which way best reaches the goal, still pick one, but keep follow-on work to a minimum: make it functional end to end and stop there, with no polish, extensions or dependent work stacked on it until a later pass needs them. Tokens spent building what may be un-built are waste. Mark the call `uncertain`.
- **The one exception is a critical issue:** an action not pre-approved in SWARM.md that is irreversible or outward-facing (deleting shared data, notifying people, spending money, touching production), a security, privacy or permissions exposure, or reversing a decision the owner explicitly made. Do not take it and do not wait: finish what does not depend on it, and report it under `Critical`. The orchestrator parks the unit and notifies the owner. When unsure, it is not critical.
- **Verify UI in order, then stop.** (1) Code: types, tests, the logic that renders it. (2) Only if code cannot settle it, your own headless browser (`/look`, **Headless**): the page loads without errors, the changed control is there, the interaction works, and nothing overflows at a phone width. (3) If neither can verify it cheaply, record it under `Unverified` with what you could not check and why, and move on. Do not fight a page that will not render headless. Never verify in a headed browser: do not drive the owner's shared window, and do not launch a visible browser of your own.
- **Stay in your territory.** Read anything; edit only your unit's files. Never edit the plan file, `cowork/**` (brain, plans, swarm files), or `.claude/**` — your worktree's copies would conflict on merge. The orchestrator owns all bookkeeping.
- **Never make the owner approve a command.** A run is unattended, and some command shapes prompt the owner whatever the project allows. The common one: `cd <dir>` followed by `git` or `gh` in the same shell call. Use `git -C <path> …` for every git command and the host CLI's repository flag (`gh … --repo <owner>/<name>`), with absolute paths for scripts and files, so no `cd` is needed. When a tool truly needs a working directory, use `env -C <dir> <command>` or give the `cd` a shell call of its own. Also avoid command substitution (`$(…)`, backticks), process substitution, here-documents and `eval`: run the inner command in its own call, and write longer text to a file and pass the file. Scripts you write for your own unit follow the same rule. **The swarm agent types enforce this:** `bash-guard.py` in this skill's folder refuses those shapes before they can prompt and tells you the form to use. A refusal is not a failure: re-issue the command in that form, and never retry the refused shape.
- **Stay inside the machine budget.** Run every heavy step (a check, a test run, a type-check or build, a browser capture run) through the gate, `<the swarm skill's folder>/machine.sh run -- <command>`; your prompt gives the full path. A big step (a native app build, a production bundle build) takes the weight the project gives it. Start every long-running server through `machine.sh serve --tag <tag> -- <command>` (or the project's serve script, which does); exit 75 means someone else holds it: do everything else first, try once more, then record the check under `Unverified`. Start a simulator, emulator or other standing resource only when you hold its tag and only when you need it, and stop it when your brief says your lane ends with you. Run only the checks your change can affect: never a whole suite the project's checks do not ask for. Before you report, stop every server, watcher, browser and build daemon you started, by process id or port, never by a pattern that could match another unit's (see **Machine budget**).
- **Work only in your own worktree.** Your first step is creating your assigned branch there from the integration sha in your prompt (`git switch -c <branch> <sha>`). Never `cd` into, check out in, or write to the primary checkout (the owner's IDE) or another unit's worktree. The brain's absolute path is for reading `swarm_holds`, nothing else.
- **Commit your work** on your assigned branch, in coherent chunks with real messages. Never stage `cowork/` paths.
- **Verify before reporting done.** Run your brief's verification criteria and the project's checks yourself. Report honestly: what passed, what you couldn't verify, what you decided, what a human should look at. The structured final report is your only channel out, and it has five sections:
  - `Done`
  - `Calls`: each with the options, why this one, whether it is `uncertain` (built lean), what switching would cost, and what depends on it
  - `Unverified`: UI or behaviour that neither code nor a headless browser could check, each with the URL when there is one, what could not be checked, and why
  - `Critical`: what must not ship without the owner, and why (empty for almost every unit)
  - `Blocked`

  The orchestrator copies `Calls`, `Unverified` and `Critical` into the plan's review block, and a ship agent puts `Unverified` into the PR notes.
- **Respect resource tags.** If your brief carries none, do not touch shared external state (live DBs, deploys) at all.
- **Honour review holds.** The owner may be reviewing in a parallel session that has borrowed some of
  the shared state (**Review flow**). Right before any step that uses a tagged resource's shared
  state, check for an open hold on that tag:
  `sqlite3 <brain> "SELECT holder, detail FROM swarm_holds WHERE run_id = <run> AND tag = '<tag>' AND released_at IS NULL"`.
  - **Steps that count:** starting a dev server on a fixed port, resetting or migrating a database.
  - **While held:** carry on with everything that does not need it, and do the held step last.
  - **If that step is all that is left:** re-check every minute until the hold is released.
  - **Never stop, restart or reuse a process you did not start**, even when it holds the port you need.

Orchestrator-side:

- **Only the orchestrator merges, and only after review.** No unit branch reaches the integration branch unreviewed.
- **Resource locks are absolute** — never dispatch into a held tag, even if the code territories are disjoint.
- **Keep `swarm_runs` / `swarm_units` current at every transition** — it's what a resume session reconstructs the world from.
- **Every time written to a run log comes from the clock** (`date -u +%H:%MZ` at the moment of
  writing), never from memory: a remembered time drifts by hours across a long session.
- **Long waits never run in the foreground.** A poll loop (`while/until … sleep`) holds its agent
  until a tool timeout kills it. Waits run in the background and notify on completion, or belong to
  the run's watcher.
- **Re-read the plan from disk before every write.** The owner can edit it at any time, most often by marking review items, and a write from a stale copy erases their marks.
- **Honour review holds yourself.** A database reset, a check that starts a server, a batch step: check `swarm_holds` first, exactly as units do.
- **Keep the run inside the machine budget** (**Machine budget**): dispatch no more than `swarm.maxAgents` builders, read `machine.sh pressure` before every dispatch and hold new units while memory is short, put the gate's full path in every dispatch, sweep each unit's worktree after its report or when it is stopped, start no standing resource at preflight, and route your own heavy steps through the gate too.
- **Failures degrade, never halt.** One failed unit skips its dependents and the rest of the swarm continues. The report tells the user what's left.

---

## Remainder Setup

The salvage path. When `/swarm <ref>` hits a `done` or `aborted` run with unmerged units, report the outcome, then offer to set up a remainder run. On yes:

1. **Diff reality against the plan.** What actually merged (integration branch history, plan checkboxes, REPORT.md) vs. what the failed/skipped units owned. Salvageable commits on surviving unit branches are noted — a failed unit's partial work can seed a fresh brief rather than being redone blind.
2. **Re-run Setup over only the remainder** — same S1–S5, but smaller: the decision record carries forward from the prior SWARM.md (copied, then extended — prior answers are not re-asked), and the plan's uncleared review items are cleared with the owner first, as S3 items, now that a human is present. New failures get fresh root-cause attention in the briefs: a unit that failed review twice needs a better brief or a different slicing, not a third identical attempt.
3. Register as a **new** `swarm_runs` row (the old one is history, never reopened), with `notes` linking back to the prior run id. The new SWARM.md lives in the same `cowork/swarm/<plan_id>/` directory as `SWARM-2.md` / `REPORT-2.md`, suffix incrementing.
4. Hand off as usual: review, commit, fresh session, `/swarm <ref>`.

---

## Review Flow

`/swarm review [plan ref]` is the owner's optional batch look, run from a **parallel session** while the run
keeps going. It is needed only for critical parks, or when the owner wants to walk the recorded calls
or a project opts into looks (`swarm.look`). The orchestrator keeps dispatching. This session:
- borrows only the shared state the looks need;
- gives each piece back as soon as its looks are done;
- ends with one handoff.

It never writes the plan's bookkeeping, SWARM.md, REPORT.md or unit rows; the orchestrator stays
their only writer. The owner marks items in the plan directly. Serving is configured by
`swarm.reviewStack` (**Project overrides**); without it, ask the owner once how an app is started from
a checkout, and use the answer for the whole session.

### V1 — Find the run and its orchestrator

- **The run** is the plan's `running` row, or the only `running` row when no plan ref is given.
- **The orchestrator** is `swarm_runs.orchestrator`, confirmed live in `ListAgents`. When the column is
  empty or that session is gone, find the peer session running `/swarm` for this plan. Ask the owner
  only if more than one could be it. Record the answer in `orchestrator`.
- **Never run in the orchestrator's own session:** the review would stall its dispatch loop. Say so
  and tell the owner to open a parallel session.

### V2 — Plan what to serve

- **Sort the open items** in the plan's `## Review` block. Looks need serving; calls need only the owner.
- **Name each look's app and checkout** from its **runs on** detail. For an older item without one,
  use its unit's branch, or its lane's latest parked branch, which carries every slice stacked in it. A
  look needing a branch the lane's latest does not carry (a fix that shipped from its own branch) gets
  its own checkout.
- **A checkout is always a worktree.** Serve a branch from the worktree that already has it
  (`git worktree list`). Only when none does, add one at `.claude/worktrees/review-<slug>`, and remove
  it at V9. Never check a branch out in the primary checkout (the owner's IDE) or switch a unit's
  worktree to another branch.
- **Group the click-through by server set.**
  - Lanes an in-flight unit is waiting on come first, so their servers are released first.
  - Within a group, each app is served from one checkout; a later group swaps a server's checkout at
    most once.
  - A look that spans two checkouts is split, and each half says where it was checked.

### V3 — Check what is in use

- **Find what's running:** the units `working` or in `review` and their tags, and any listener on the
  ports the looks need. For each listener, note the checkout it serves from (its working directory).
- **Don't take over a port a unit is using right now** for its own page check. Order those looks last,
  or wait for the check to finish. Never stop a process this session did not start.
- **Reuse the shared stack as it is** (`reviewStack.shared`). Start it (`reviewStack.sharedStart`) only
  when it is down.

### V4 — Take the hold, then tell the orchestrator

- **Hold before serving.** Insert one `swarm_holds` row per tag:
  - one for each app served (`reviewStack.tag`);
  - one for each tag in `reviewStack.holdAlso`, such as a local database, so that nothing resets the
    fixtures mid-review.

  Each row's `holder` is this session's name; its `detail` is the app and the checkout.
- **Message the orchestrator** with:
  - what is held, and from which checkouts;
  - that in-flight units keep building and defer the held steps;
  - a request to relay the hold to any unit touching those tags, because a unit dispatched before the
    hold rule existed learns of it only that way;
  - that the verdicts will arrive as one handoff.

### V5 — Serve

- **Start each app from its checkout** with `reviewStack.serve`, in the background, with its full log
  kept (`reviewStack.logs`).
- **One start at a time per checkout.** A start may install packages into its checkout first, and two
  installs into one checkout corrupt each other. Wait for the first app to listen before starting the
  next from the same checkout. Different checkouts start in parallel.
- **Confirm each server.** Its port listens from the intended checkout, and its looks' first URL
  answers through the shared stack. A cookie-less request redirected to sign-in is normal.
- **Confirm the fixtures** each look's setup note names are present. Re-apply any that are missing
  with the note's own commands.
- **Don't walk the pages yourself.** The units already checked them headless, and the owner is here to
  look.

### V6 — Hand over the browser

- **Launch the shared browser** (`/look`) on the first group's first URL, and a status display
  (`/pbar`). For each served app, the display shows whether it is up, which checkout serves it, and
  whether its page answers.
- **Give the owner:**
  - the click-through order by group, each with its plan line range;
  - the checkout each group runs on;
  - how to give a verdict: in the plan, `[x]` to approve, `[fix]` with a note, or a note under a
    call's option to change it; or by telling this session.
- **The owner opens every URL.** Never navigate or resize their window.

### V7 — Swap and release as the owner goes

- **Never let a look run on the wrong checkout.** Before the owner reaches a look whose app needs
  another checkout, swap that server and say so. A swap restarts the server from another worktree. It
  never switches the branch of the worktree it was serving from. A look checked on the wrong checkout is void: say so
  the moment it is noticed, and have it retested.
- **Release a group's servers as soon as its looks are done**, since a unit may be waiting:
  1. stop the servers this session started;
  2. restore the `reviewStack.restore` paths in those checkouts (files the dev server rewrites), so
     each checkout ends as it was found. In a checkout a unit is still working in, undo only the dev
     server's own change;
  3. set `released_at` on those holds;
  4. message the orchestrator `released: <tags>`.
- **Triage errors the owner reports.** If an error is not from the slices under review, check whether
  the default branch has it too, say so, and move on. It is not a verdict on the slice.

### V8 — Collect the verdicts

- **Read the owner's marks** in the plan's `## Review` block in the primary checkout, plus anything they said to this session. The working-tree diff there also carries the orchestrator's uncommitted edits, so read marks from the block, not the diff.
- **An unmarked call is not accepted.** Ask once about all of them: all clear, or which to change?
- **Apply what a changed call implies** for its sibling options. Flag each such change as applied
  without asking.

### V9 — Hand off and let go

1. **Write the handoff** to `cowork/swarm/<plan_id>/review-YYYY-MM-DD-<n>.md`:
   - what was served from which checkout;
   - each item's verdict: approved, a fix in the owner's words, a changed call, or a consequence
     applied;
   - anything to check before an open PR merges;
   - errors seen that belong to the default branch.
2. **Release every remaining hold**, with the four steps above, and remove the `review-<slug>`
   worktrees this session added.
3. **Message the orchestrator** the handoff's path and a one-line summary. It applies the handoff as
   one amendment (**The batch look**, under **Team repositories**).
4. **Tell the owner what happens next,** in one short list.

A review session that ends abruptly leaves its holds open. The orchestrator's watchdog and the next
`/swarm review` treat a hold whose holder has left `ListAgents` as released: they stop nothing, set
`released_at`, and note it.

---

## Status Flow

Read-only. Load the run and units, print: run status, the integration worktree's path, unit table (key, title, status, branch — and for a PR-mode run, lane, kind and PR), live agents (`ListAgents`), open review holds (`swarm_holds`, with their holder), and what's blocking what. Parked slices waiting on the owner are listed with the count of open items in the plan's `## Review` block and its line range. Do not start or resume work.

## Abort Flow

Confirm with the user unless the session is non-interactive. Then: stop live agents (`TaskStop`), sweep each one's worktree and stop the standing resources they held (**Machine budget**), set run `aborted` with a note, mark in-flight units `failed`. **Keep** worktrees, branches, and the integration branch for inspection — deleting work is the user's call. Send a push notification with the abort summary, and report what was merged, what was in flight, and that `/swarm <ref>` now offers Remainder setup over what's left.

---

## Global rules

- **Phase inference is silent.** Never ask "setup or run?" — the brain state answers it.
- **Setup is conversational, run is autonomous.** All human judgment is front-loaded into S3.
- **The plan file remains the source of truth for what** (and its `## Review` block for what waits on the owner); SWARM.md for who/when; REPORT.md for what actually happened.
- **One swarm per plan at a time.** A `ready` or `running` row blocks a second setup for the same plan.
- **Point at the line.** Every message to the owner that mentions part of the plan, `SWARM.md` or `REPORT.md` cites its path and line, looked up just before sending (`/plan`, **Pointing at a line**). The files themselves name parts by stable ids (unit keys, D-numbers, review item numbers), never by line.

## Project overrides

`.claude/kit.json` — `swarm.maxAgents` (default 4) caps how many units build at once (**Machine budget**); `swarm.checks` is the project's verification command list (reviewers run these verbatim; when absent, setup determines and records them in SWARM.md); `rules."swarm"` applies as an additional instruction. For PR-mode plans (see **Team repositories**):

| Key | What it holds |
|---|---|
| `swarm.worktree.pool` | `{ "acquire": "<command>", "release": "<command>", "list": "<command>", "size": <n> }` — the slot pool (**Where the code lives**); `<lane>`, `<branch>`, `<base>` and `<slot>` are substituted, and `acquire` prints the slot's path on its last line |
| `swarm.worktree.pool.prune` | A command that drops build output from every free slot, when `release` does not already do it |
| `swarm.land` | `{ "maxAgents": <n>, "watch": "<command>" }` — **Landing**: how many fix and replay agents work at once (default 2), and the background watcher that exits when any of `<prs>` changes state |
| `swarm.watch` | The project's CI watcher: what reruns infrastructure reds, and where it logs; the orchestrator dispatches no fix for a red the watcher will rerun |
| `swarm.worktree` | `{ "create": "<command>", "remove": "<command>" }` for a target checkout outside the session's repo; `<slug>` and `<branch>` are substituted. Put the worktree at `.claude/worktrees/<slug>` in the target, and include the repo's own bootstrap in `create` |
| `swarm.machine` | `{ "heavySlots": <n>, "weights": { "<text>": <n> \| "all" }, "nice": <0–19>, "waitMax": <s>, "minFreePct": <n>, "memWait": <s>, "serverSlots": <n>, "serverWait": <s>, "env": { "<NAME>": "<value>" } }` — the machine budget (**Machine budget**): how many heavy slots there are (default 2); how many slots a step takes when its command line contains the text (`"all"` for a native or production build); the priority drop (default 10); how long a step waits for slots before running anyway (default 900); the share of free memory below which memory counts as short (default 10) and how long a step waits for it to ease (default 300); how many leased servers run at once (default 2) and how long `serve` waits for one (default 600); and caps exported to each step (a test runner's maximum workers, a build tool's "no daemon" switch) |
| `swarm.resources` | `{ "<path glob>": "<tag>" }` — shared local state a unit touching that path holds: a fixed-port dev server, the one local database, the package install |
| `swarm.review` | The team's review tool, run against a pushed PR (`<pr>` is substituted); it replaces the swarm's reviewer agent. Or `"team"`: the team's bot reviews every PR itself, so nothing reviews before the push |
| `swarm.ship` | `ready` \| `draft` \| `ask` (default `ask`) — the owner's standing ship policy |
| `swarm.look` | `none` \| `batch` \| `per-slice` (default `none`) — whether user-facing slices wait for the owner's look. `none`: they ship once verified by code, then headless |
| `swarm.reviewStack` | How `/swarm review` serves a look (below) |

`swarm.reviewStack` keys (`<app>` and `<checkout>` are substituted; every key is optional):

| Key | What it holds |
|---|---|
| `shared` | A command that exits 0 when the shared stack every app sits behind (a proxy, an auth service) is up |
| `sharedStart` | How to start that stack when it is down: a command, or a skill to invoke |
| `serve` | The long-running command that serves one app from one checkout |
| `port` | A command printing the port that app listens on |
| `tag` | The resource tag serving that app holds, matching the tags units carry (e.g. `port:<app>`) |
| `holdAlso` | Tags the whole review holds, such as the local database its fixtures live in |
| `restore` | Path globs the dev server rewrites in a checkout; their uncommitted changes are restored when a server stops |
| `logs` | The directory server logs go to |

```bash
jq -r '.swarm.maxAgents // 4, ((.swarm.checks // []) | join(" && ")), (.swarm.ship // "ask"), (.swarm.look // "none"), (.rules."swarm" // empty)' .claude/kit.json 2>/dev/null
jq '.swarm.reviewStack // empty' .claude/kit.json 2>/dev/null
jq '.swarm.machine // empty' .claude/kit.json 2>/dev/null
```
