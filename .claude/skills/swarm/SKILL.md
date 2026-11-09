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
| Row with `status = 'done'` / `'aborted'`, unfinished units remain | Report the outcome, then run **Remainder setup** — a new, smaller run over what's left — under **Autopilot** (asked first only when a project sets `autopilot: ask` or `off`, or the run was aborted by the owner) |
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
- **Where `.claude/worktrees/<slug>` really is.** In this skill that path is shorthand for
  `$(~/.claude-kit/scripts/wt-path <slug>)`. It is the repo's `.claude/worktrees/<slug>` unless
  `/disk` moved worktrees to an always-attached external drive. Resolve it once when you create a
  worktree, and use the absolute path from then on. Claude Code's own agent worktrees follow the
  same rule through the `WorktreeCreate` hook, so take a unit's path from what the Agent tool
  returns.
- **Address a worktree by its path.** Git work goes through `git -C <worktree>`, and files are read and written at the worktree's absolute path. The orchestrator's own working directory stays at the primary checkout. Switching branches is allowed only inside a worktree the session or agent created itself.
- **Point other agents only at the integration worktree.** A path given to another agent (a tool to run, a dossier to read, research to build on) names `.claude/worktrees/swarm-<plan_id>`, never a unit's own worktree: unit worktrees are removed at merge, and an agent still holding that path then fails or reads nothing. When an agent must read a unit's work before it merges, record which agent holds that path, and repoint it to the integration worktree before removing the unit's worktree. (Swarm 051 removed a worktree three times while a running agent was reading from it: a tool, two county dossiers, the final reviewer's input.)
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

## Phase files — read before acting

Each phase's steps live in their own file in this skill's folder. Once the phase is inferred (or the argument names it), **Read its files BEFORE taking any action in that phase**: before writing a file, touching the brain, dispatching an agent or messaging anyone. Read them whole; this file holds only what every phase shares.

| Phase / argument | Read first |
|---|---|
| **Setup** (no `swarm_runs` row) | `<this skill's folder>/setup.md`, `<this skill's folder>/run-rules.md` (S4 copies it into SWARM.md), `<this skill's folder>/machine-budget.md`; plus `<this skill's folder>/pr-mode.md` when the plan carries `**Mode:** pr` |
| **Remainder setup** (`done` / `aborted` with unfinished units, once the owner says yes) | `<this skill's folder>/setup.md` (its **Remainder Setup** section runs S1–S5 again), plus the other Setup files |
| **Run** (`ready`) and **Resume** (`running`) | `<this skill's folder>/run.md`, `<this skill's folder>/run-rules.md`, `<this skill's folder>/machine-budget.md`, the plan skill's `autopilot.md` (`../plan/autopilot.md`); plus `<this skill's folder>/pr-mode.md` for a PR-mode plan, or when a review is announced or its handoff arrives; plus `<this skill's folder>/land.md` before a PR-mode run enters **Landing** after R4 |
| **Landing** (`land`, or a `done` PR-mode row with units still `shipped` or stacked) | `<this skill's folder>/land.md`, `<this skill's folder>/pr-mode.md`, `<this skill's folder>/machine-budget.md` |
| `review` | `<this skill's folder>/review.md` |
| `status`, `abort` | `<this skill's folder>/status.md`; `abort` also `<this skill's folder>/machine-budget.md` |
| `report` | nothing more: the **Input** line above says what to do |

**Where each section lives.** The files cite each other by bold section name. When a step relies on a section whose file is not loaded yet, Read that file first.

| Section | File |
|---|---|
| **Branches live in worktrees**, **Input**, **Brain schema**, **Model tiers** (with **Escalation**, **Checking what was served**, **When the tiers are missing**), **Global rules**, **Project overrides** | this file |
| **Setup Flow** (S1–S5), **Remainder Setup** | `<this skill's folder>/setup.md` |
| **Run Flow** (R1–R4), **Resume** | `<this skill's folder>/run.md` |
| **Run rules** (the agent protocol) | `<this skill's folder>/run-rules.md` |
| **Machine budget** | `<this skill's folder>/machine-budget.md` |
| **Team repositories** (with **Where the code lives** and the batch look) | `<this skill's folder>/pr-mode.md` |
| **Landing** | `<this skill's folder>/land.md` |
| **Review flow** (V1–V9) | `<this skill's folder>/review.md` |
| **Status flow**, **Abort flow** | `<this skill's folder>/status.md` |

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

## Model tiers

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
