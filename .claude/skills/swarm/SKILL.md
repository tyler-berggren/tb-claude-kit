---
name: swarm
description: Prep a plan for autonomous parallel execution, then run it with an orchestrated agent swarm. Phase is inferred from brain state — unregistered plan -> Setup, registered ready -> Run, running -> Resume. Also status / abort / report.
argument-hint: "[plan ref | scope NNN | status | abort | report]"
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
| Row with `status = 'done'` / `'aborted'`, unfinished units remain | Report the outcome, then offer **Remainder setup** — a new, smaller run over what's left |
| Row with `status = 'done'`, everything merged | Report the outcome; a re-swarm requires the user to say so explicitly |

**Parallelism is an optimization, not the point.** The skill's promise is that the plan gets completed end-to-end without stopping. A plan that decomposes into a single serial chain still swarms — as a sequence of autonomous units — and setup reports that profile honestly rather than manufacturing fake parallelism.

The intended workflow: `/plan` generates the plan → `/swarm <ref>` (setup) → user reviews + `/commit` → **fresh session** → `/swarm <ref>` (run) → user reads `REPORT.md`.

**The core contract** is `/plan`'s **Batches** standard, applied to a whole run:
- Every question a human must answer is answered during Setup, and written into the plan.
- During Run, no agent stops to ask the user anything, and that includes the orchestrator. Agents make the call, stub what would be expensive to throw away, and flag it.
- Everything the owner must see or decide lands in one numbered review block in the plan, cleared together after the run.

## Input

Optional argument: `$ARGUMENTS`

- `status` → **Status flow** (read-only)
- `abort` → **Abort flow**
- `report` → print the most recent run's `REPORT.md` path and summarize it
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
  notes TEXT
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
  reviewer_model TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','working','review','parked','shipped','merged','failed','skipped')),
  branch TEXT,
  updated_at TEXT,
  result TEXT,
  lane TEXT,
  kind TEXT,
  pr TEXT
);
```

`swarm_runs.status` is what makes phase inference work across sessions — keep it accurate at every transition.

`parked`, `shipped`, `lane`, `kind` and `pr` serve PR-mode runs (see **Team repositories**): `parked`
is built and waiting for the owner's batch look; `shipped` has an open PR on its way through the
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

**Resource tags** name shared mutable state *outside* git that the unit touches: `db:<name>` (a live database it migrates or rewrites), `deploy`, `tiles`, `dev-server`, or anything project-specific. Two units holding the same tag never run concurrently, even with disjoint code. Tag conservatively — a missing tag is a race, an extra tag is just lost parallelism.

Identify **gates**: plan checkpoints that must pass before dependents dispatch (e.g. a parity/measurement phase). A gate is a normal unit whose dependents simply wait on it.

**Assign a model per unit and per reviewer.** Setup decides; the user vetoes in S3. The policy:

| Model | Unit work | Review work |
|---|---|---|
| `opus` | **Default.** Anything with judgment in it: migrations, scorer/algorithm changes, cross-file refactors, gates, anything touching a resource tag | Gate units and units whose failure cascades |
| `sonnet` | Simple, mechanical, well-briefed work: copy/label sweeps, config plumbing, isolated UI tweaks with explicit item lists | **Default reviewer** |
| `haiku` | Never | Only *very* simple reviews — checklist-style verification of a small mechanical unit (files changed match territory, grep-level checks, project checks pass) |

When in doubt, go up a tier — a swarm's cost center is redone work, not tokens. The orchestrator itself always runs on whatever model the run session was started with.

**Compute the parallelism profile.** From the graph: unit count, max useful concurrency, and the critical path as a share of total work. Turn it into a plain-words expectation for S3 — *"6 units, but the migration→scorer→re-score chain is ~70% of the work; expect roughly serial wall-clock with the UI phases riding alongside"*. A fully serial profile is fine — say so and proceed; the run is still autonomous end-to-end, which is the point. Never split a serial chain to make the profile look better.

### Step S3 — Resolve every open question with the user

This is the heart of setup. Collect and present, via AskUserQuestion (batched, with recommendations, each question naming the plan line it comes from, per `/plan`'s **Pointing at a line**):

1. Every open question in the plan's `## Open questions` (see `/plan`, **Batches**), and every item in its Risks section that requires human judgment. Setup is the batch's gate: a question that bites any unit is answered here
2. Every ambiguity or drift found in S1/S2
3. Run policy for THIS swarm: may agents touch the live/prod database? May the swarm deploy, or does the deploy phase get excluded and left for the user? Merge to main at the end, or leave the integration branch for review? (For a PR-mode plan — a team repository — the answer is never "merge to main", and the ship and look policies come from `swarm.ship` / `swarm.look` when kit.json records them; ask only what they leave open. See **Team repositories** below.) Max concurrent agents (default from `.claude/kit.json` `swarm.maxAgents`, else 6)?
4. Show the per-unit model assignments (from the S2 policy table) as part of the setup summary. Only ask about assignments that are genuine judgment calls — a plan that's all-`opus` needs no question, just the table
5. Lead the summary with the parallelism profile and expected wall-clock shape, so the user knows what kind of run they're approving — a wide fan-out or a supervised serial march

Anything the user delegates back ("you decide") gets a committed default written down. **Where answers go:**
- A question about **what gets built** is answered in the plan itself, per `/plan`'s **Batches**. The answer goes into its **Answer:** line, then becomes one of the plan's numbered decisions.
- A **run-policy** answer (database, deploy, merge target, concurrency) goes into SWARM.md.

Log the material answers as brain `decision` entries (normal `/brainstorm` conventions, tagged `swarm`). **A question that survives setup unanswered is a setup failure** — either get it answered or write the decision rule an agent will apply.

### Step S4 — Write the swarm package

Create `cowork/swarm/<plan_id>/SWARM.md` (own directory — never inside a plan root, where it would pollute `/plan` numbering):

- **Run config** — plan path, merge target, policy answers from S3, max agents, the checks contract (exact commands reviewers run), and the parallelism profile
- **Decision record** — the run-policy answers and delegated defaults, numbered (`D1`, `D2`…) so briefs can cite them. Decisions about what gets built live in the plan, and briefs cite them by the plan's own numbers
- **Unit graph** — table: unit key, title, plan phases, depends_on, resources, territory, model, reviewer model; plus a short dispatch-order narrative
- **Per-unit briefs** — one section per unit, fully self-contained (`### Unit U3 — <title>`): objective, the plan items it owns (copied, not referenced by number alone), file territory, what it must NOT touch, its verification criteria from the plan, relevant decisions (`per D4: …`), and known landmines from S1
- **The agent protocol** (copied verbatim into the file so briefs can reference it — see **Run rules** below)

Then:
- Insert the `swarm_runs` row (`status = 'ready'`, `swarm_dir`, `plan_id`, `plan_path`) and one `swarm_units` row per unit
- Add one line under the plan's title: `> **Swarm:** prepared YYYY-MM-DD — see cowork/swarm/<plan_id>/SWARM.md`
- Beyond the answers S3 wrote into it, do not rewrite the plan — it stays the source of truth for *what*; SWARM.md owns *who and in what order*

### Step S5 — Hand off

Tell the user: review `SWARM.md` (especially the decision record), giving the line range of the decision record, the unit graph and each brief, then commit (`/commit`), then start a **fresh session** and invoke `/swarm <ref>` — and that starting that session with `/rc` gives remote monitoring of the run. **Never start the run in the setup session** — the run deserves a full context window.

### Team repositories (PR-mode plans)

A plan carrying `**Mode:** pr` lands in a repository other people own, through reviewed pull
requests. The swarm still completes the plan without stopping, but three things change: the unit
of shipping is the plan's **slice**, a slice is finished when **the team** merges its PR, and the
owner's judgment on anything user-facing arrives **in one batch**, not slice by slice.

**Units are slices; lanes are the parallelism.** Read each slice's lane and *waits on* line from
the plan. A **lane** is a chain of slices over the same files — usually one adopter or one
package — and its slices run in order, while lanes that share no files run side by side. Never
split a slice's files across two agents. A slice may **stack** on its lane's previous slice
(branch from that branch) so the lane never stalls behind a review, CI or a look; once the
earlier slice's squash merge lands, the later one replays only its own commits
(`git rebase --onto origin/<default> <earlier-branch-head>`).

**Every unit carries a `kind`**, which decides whether it waits for the owner:

| kind | means | ships |
|---|---|---|
| `invisible` | nothing a user can see changes: plumbing, a shared package, config | as soon as its checks and review pass |
| `fix` | restores intended behaviour, with no design choice in it | the same, and it still gets a look item in the review block so the owner can confirm it |
| `user-facing` | a change a person will see or feel | only after the owner's batch look (below) |

**A stub never ships unconfirmed.** A team repository often merges and deploys a green pull
request on its own. So a unit of any kind whose report carries a **stubbed call** the owner has
not confirmed parks like a user-facing one, and its dependents stack on its branch. A call that is
cheap to undo and needs no stub ships, and it goes into the review block for confirmation.

**Resource tags come from the project's map.** A team repository usually shares one local stack
across every worktree: dev servers bound to fixed ports, one local database, one package
install. `swarm.resources` in `.claude/kit.json` maps path globs to tags, so setup tags each unit
by the territory it touches instead of guessing. Two units holding a tag never run at once.

**Where the code lives.** When the plan's code is a checkout other than the session's own repo —
a sibling clone, a symlinked repository, a submodule — the Agent tool's `isolation: "worktree"`
isolates the **wrong** repository. Each unit then creates its own worktree in the target
checkout (the create and bootstrap commands come from `swarm.worktree` in kit.json), works only
there, and removes it once its slice has merged.

**Standing policies are read, not re-asked.** A project may record two in kit.json; setup reads
them and asks (S3) only what they leave open:

- `swarm.ship` — how a finished slice's PR goes up. `ready`: the owner has pre-approved ready
  PRs, and a slice is a draft only on their word. `draft`: every PR opens as a draft. `ask`
  (the default): the ship command asks, which an unattended run cannot do, so the slice parks
  with the question.
- `swarm.look` — when the owner reviews user-facing work. `batch` (the default): one session for
  everything parked. `per-slice`: each user-facing slice parks and notifies on its own. `none`:
  the project reviews user-facing work some other way.

**The run, per slice:**

1. **Build** in the unit's worktree with the project's quick checks, and check every changed page
   on a local run in a headless browser of the agent's own (`/look`, **Headless**). A passing check
   is not a running app, and the owner's shared browser is never the agent's to drive.
2. **Invisible and fix slices ship:** write their tests, then run the project's ship command
   (`rules.plan` names it) under the `swarm.ship` policy.
3. **User-facing slices park** (`status = 'parked'`), and so do slices holding an unconfirmed
   stub. They are built and checked headless by the agent, but get no ship-time checks and no UI
   tests yet, because a change of mind in the look would throw both away. Their looks and calls go
   into the plan's review block.
4. **The team's own review tool is the reviewer** when `swarm.review` names one — a review bot
   whose verdict the team's merge honours. It runs against the pushed head and replaces the
   swarm's reviewer agent for that unit; a second review would be duplicate spend. A blocking
   finding is fixed and re-reviewed, two cycles at most, then `failed`.
5. **Watch CI; fix on red at once.** Each open PR (`status = 'shipped'`, `pr` recorded) gets a
   watcher. When a CI group fails, push the fix as soon as it is ready — that run is already
   lost, and waiting only lets the default branch move under the PR. A PR the host reports as
   conflicting is re-synced by merging the default branch in, once reviewers have seen its
   history.
6. **`merged` means the team merged it.** When the PR lands on the default branch, the lane's
   next slice rebases (replaying only its own commits if it stacked) and continues.

**Never merge anything into the team's default branch locally.**

**The batch look.** When user-facing slices are parked and nothing else is in flight, or when
the owner asks, the orchestrator:

1. starts what the parked slices need — one worktree per lane, the lane's latest branch, which
   carries every stacked slice in it — and requests every page itself first, headless;
2. tidies the plan's `## Review` block (`/plan`, **Batches**) into one numbered list for all of
   them: each look with its URL, what changed, what to try, what right looks like and the widths,
   and each call with its options and switching cost;
3. sends a push notification that the review is ready — the one mid-run interruption worth
   sending;
4. clears the items with the owner, one by one, each by its number and plan line; the owner opens
   each URL in the shared browser themselves. Their
   feedback is one amendment (D-numbered in SWARM.md; a product or design answer also becomes a
   plan decision), applied across the slices it touches. Only what changed is shown again, then
   each approved slice writes its tests and ships.

A run whose remaining work is parked slices waiting on the owner is **waiting, not stalled**: the
status says so, and the stall watchdog leaves it alone.

---

## Run Flow

The orchestrator session. It dispatches, reviews, merges, and reports. It writes the plan file, SWARM.md, REPORT.md, and the brain; agents never do.

### Step R1 — Load and preflight

1. Load the `swarm_runs` row, `SWARM.md`, and the plan. Ensure `status = 'ready'`.
2. Preflight: working tree clean; on the merge-target branch; `git worktree list` shows no leftover `swarm/` worktrees. If commits landed since setup, do a fast delta check — if they invalidate unit briefs, stop and tell the user to re-run setup; don't guess.
3. Create the integration branch `swarm/<plan_id>` from HEAD and check it out. Record `base_commit`, `integration_branch`, `started_at`; set status `running`.
4. Announce the dispatch order in one short message (this is what `/rc` monitoring sees first).

### Step R2 — Dispatch loop

Event-driven, until every unit is terminal (`merged`, `failed`, or `skipped`):

1. **Ready set** = pending units whose `depends_on` are all `merged` and whose `resources` collide with no unit currently `working`/`review`.
2. Dispatch every ready unit up to the concurrency cap, in a single message: `Agent` tool, `run_in_background: true`, `isolation: "worktree"`, `model` = the unit's assigned model from the graph. The prompt is the unit's brief from SWARM.md plus the agent protocol, plus: unit key, integration branch name, and required branch name `swarm/<plan_id>-<unit_key>`. Mark units `working`. When the plan's code lives in a checkout other than the session's repo, dispatch without `isolation` and have the brief create the unit's worktree in the target checkout with `swarm.worktree`'s commands (see **Team repositories**).
3. On a completion notification: spawn a **reviewer agent** (read-only, background, `model` = the unit's assigned reviewer model) with the unit brief, the worktree path, the unit's verification criteria, and the checks contract from SWARM.md (exact commands — reviewers never guess). It inspects the diff, runs those checks in the worktree, and returns PASS or FAIL with findings. Mark the unit `review`.
4. **Reviewer PASS** → merge the unit branch into the integration branch. The orchestrator resolves any conflicts itself — it holds every brief and both sides of the conflict; agents never see each other's work. Then:
   - mark plan items `- [x]` with progress notes (per `/plan` conventions);
   - append the unit's **Looks** and **Calls** to the plan's `## Review` block (`/plan`, **Batches**) — the orchestrator is its only writer;
   - update `swarm_units` (`merged`, `result` = one-line summary);
   - commit plan + brain on the integration branch and remove the worktree;
   - loop back to 1, because a merge may unblock dependents.
5. **Reviewer FAIL** → spawn a fix agent in the same worktree with the findings, on the unit's model; the **second** fix cycle always escalates to `opus` regardless of assignment. Max **two** fix cycles; then mark the unit `failed`, record why, and continue — everything not depending on it still runs. Dependents of a failed unit become `skipped`.
6. Post a one-line progress note as each unit changes state. Between events there is nothing to poll — background agents re-invoke the session when they finish.

**Stall watchdog.** A hung agent never sends a completion notification, and a remote-monitored run that silently stalls defeats the system. Keep a background timer alive whenever units are in flight (a background `sleep 1800` re-invokes the session when it exits; restart it each cycle). On each wake: any unit in `working`/`review` with no state change for ~30 minutes gets investigated — `ListAgents` to see if its agent is alive. Dead agent, no commits → reset the unit to `pending` and re-dispatch. Dead agent, commits present → send to review. Alive and progressing → leave it, reset the timer. Two watchdog re-dispatches on the same unit → mark it `failed` and move on.

**Mid-run steering.** The no-questions rule binds agents, not the user. A user message arriving mid-run (typically via `/rc`) is an **amendment**: append it to the SWARM.md decision record, timestamped, continuing the D-numbering; one that decides what gets built also becomes a plan decision, and clears any review item it answers. Amendments apply to not-yet-dispatched units immediately; in-flight units are unaffected unless the user explicitly says to stop one (then `TaskStop` it and re-dispatch under the amended brief, or skip it, per their instruction). Every amendment and its effect is listed in REPORT.md. Never pause the swarm to wait for possible steering — amendments are applied when they arrive, not solicited.

### Step R3 — Integration gate

When all units are terminal:

1. Run the plan's Verification table end-to-end on the integration branch, plus the project's standard checks.
2. Spawn a final reviewer over the integration branch's full diff against `base_commit`: cross-unit coherence, plan coverage, nothing half-merged. Always `opus` — this is the last line of defense, never economized.
3. Fix findings directly (orchestrator or a fix agent). This is the last line of defense before the merge target.

### Step R4 — Finalize

1. Merge the integration branch into the merge target per the setup decision (default: merge to main locally, no push; or leave the branch if that was the decision — then say so prominently). A PR-mode plan merges nothing into the default branch: each slice's branch is left for the ship command, per **Team repositories**.
2. Update the plan: `**Status:** done` on completed phases, RESUME WORK HERE banner on the first failed/skipped item if any. Mark linked brain tasks done (per `/plan` update conventions).
3. **Tidy the plan's `## Review` block** (`/plan`, **Batches**): every look and call the run produced, deduplicated, each URL requested again, numbered 1…N in click-through order. It is the review surface that replaces mid-run questions, and the owner clears it with the next session, item by item.
4. Write `cowork/swarm/<plan_id>/REPORT.md` — **the user's morning-after read**:
   - Outcome summary: units merged / failed / skipped, wall-clock, phases done
   - **Waiting on you** — the count of review items and a pointer to the plan's `## Review` block. The block is the one list; the report never keeps a second one
   - Verification results (actual output, including anything that failed)
   - Follow-ups and loose ends, routed like `/plan carry` would
5. **Retro to the brain.** Log 2–4 `insight` entries tagged `swarm-retro`: which unit slicings merge-conflicted despite disjoint territories, whether sub-`opus` assignments survived review, actual wall-clock vs. the setup profile, anything that would change the next setup's slicing. This is what S1 reads next time — the heuristics improve from your runs, not from guesses.
6. Set run status `done` (`completed_at`), commit, remove remaining worktrees, delete merged unit branches, keep the integration branch.
7. **Notify.** Send a push notification (`PushNotification`) with the one-line outcome — "Swarm 021: 5/6 units merged, U4 failed, 7 items waiting on you (see the plan's Review)". The user designed this to run while they're away; completion and failure are the two interruptions worth sending. Also notify on a hard mid-run stop (baseline drift, aborted run).
8. Final message: outcome first, then how many review items wait on the owner, with the line range of the plan's `## Review` block, and where the report is. If anything failed, say so plainly — never bury a failed unit in a success narrative.

### Resume (status = 'running')

An interrupted run. Reconcile before touching anything: `ListAgents` for still-live agents, `git worktree list` + branch state vs `swarm_units` rows. A unit `working` with no live agent and no commits → back to `pending`; with commits → send it to review. Then re-enter the dispatch loop.

---

## Run rules (the agent protocol)

Copied into SWARM.md at setup; binding for every spawned agent.

- **Never ask the user anything.** Blocked on a judgment call? Think like a senior engineer and product manager, and apply the decision protocol: (1) the plan and its decisions are authoritative → (2) the SWARM.md decision record → (3) brain DB decisions → (4) choose the smallest reasonable interpretation consistent with codebase conventions. Commit to it and record it in your final report under `Calls`. A decision you can reverse later beats a stalled swarm.
- **Stub what would be expensive to throw away.** When the options each cost real work, pick the best one and build the seam in full, then the behaviour behind it minimally. The seam is the types, exports, schema, routes and contracts other units consume, and no unit waiting on yours should be blocked by the stub. The owner may change course in the review, so keep the discarded work small.
- **The one exception to "never ask"** is an action not pre-approved in SWARM.md that is irreversible or outward-facing (deleting shared data, notifying people, spending money, touching production), or a security or data-exposure risk. Do not take it and do not wait: finish what does not depend on it, and report it under `Blocked`. The orchestrator parks the unit and notifies the owner.
- **Check UI in your own headless browser** (`/look`, **Headless**): the page loads without errors, the changed control is there, the interaction works, nothing overflows at a phone width, and one screenshot per page per width shows nothing broken. Never drive the owner's shared browser. How it looks (design, layout, wording, a design choice) is the owner's: report it under `Looks`.
- **Stay in your territory.** Read anything; edit only your unit's files. Never edit the plan file, `cowork/**` (brain, plans, swarm files), or `.claude/**` — your worktree's copies would conflict on merge. The orchestrator owns all bookkeeping.
- **Commit your work** on your assigned branch, in coherent chunks with real messages. Never stage `cowork/` paths.
- **Verify before reporting done.** Run your brief's verification criteria and the project's checks yourself. Report honestly: what passed, what you couldn't verify, what you decided, what a human should look at. The structured final report is your only channel out, and it has five sections:
  - `Done`
  - `Calls`: each with the options, why this one, what is stubbed (paths), what switching would cost, and what depends on it
  - `Looks`: each with the URL, what changed, what to try, what right looks like, the widths, and what your headless check confirmed
  - `Blocked`
  - `Unverified`

  The orchestrator copies `Calls` and `Looks` into the plan's review block. Anything else worth a human's eyes is a `Call` or a `Look`.
- **Respect resource tags.** If your brief carries none, do not touch shared external state (live DBs, deploys) at all.

Orchestrator-side:

- **Only the orchestrator merges, and only after review.** No unit branch reaches the integration branch unreviewed.
- **Resource locks are absolute** — never dispatch into a held tag, even if the code territories are disjoint.
- **Keep `swarm_runs` / `swarm_units` current at every transition** — it's what a resume session reconstructs the world from.
- **Failures degrade, never halt.** One failed unit skips its dependents and the rest of the swarm continues. The report tells the user what's left.

---

## Remainder Setup

The salvage path. When `/swarm <ref>` hits a `done` or `aborted` run with unmerged units, report the outcome, then offer to set up a remainder run. On yes:

1. **Diff reality against the plan.** What actually merged (integration branch history, plan checkboxes, REPORT.md) vs. what the failed/skipped units owned. Salvageable commits on surviving unit branches are noted — a failed unit's partial work can seed a fresh brief rather than being redone blind.
2. **Re-run Setup over only the remainder** — same S1–S5, but smaller: the decision record carries forward from the prior SWARM.md (copied, then extended — prior answers are not re-asked), and the plan's uncleared review items are cleared with the owner first, as S3 items, now that a human is present. New failures get fresh root-cause attention in the briefs: a unit that failed review twice needs a better brief or a different slicing, not a third identical attempt.
3. Register as a **new** `swarm_runs` row (the old one is history, never reopened), with `notes` linking back to the prior run id. The new SWARM.md lives in the same `cowork/swarm/<plan_id>/` directory as `SWARM-2.md` / `REPORT-2.md`, suffix incrementing.
4. Hand off as usual: review, commit, fresh session, `/swarm <ref>`.

---

## Status Flow

Read-only. Load the run and units, print: run status, unit table (key, title, status, branch — and for a PR-mode run, lane, kind and PR), live agents (`ListAgents`), and what's blocking what. Parked slices waiting on the owner are listed with the count of open items in the plan's `## Review` block and its line range. Do not start or resume work.

## Abort Flow

Confirm with the user unless the session is non-interactive. Then: stop live agents (`TaskStop`), set run `aborted` with a note, mark in-flight units `failed`. **Keep** worktrees, branches, and the integration branch for inspection — deleting work is the user's call. Send a push notification with the abort summary, and report what was merged, what was in flight, and that `/swarm <ref>` now offers Remainder setup over what's left.

---

## Global rules

- **Phase inference is silent.** Never ask "setup or run?" — the brain state answers it.
- **Setup is conversational, run is autonomous.** All human judgment is front-loaded into S3.
- **The plan file remains the source of truth for what** (and its `## Review` block for what waits on the owner); SWARM.md for who/when; REPORT.md for what actually happened.
- **One swarm per plan at a time.** A `ready` or `running` row blocks a second setup for the same plan.
- **Point at the line.** Every message to the owner that mentions part of the plan, `SWARM.md` or `REPORT.md` cites its path and line, looked up just before sending (`/plan`, **Pointing at a line**). The files themselves name parts by stable ids (unit keys, D-numbers, review item numbers), never by line.

## Project overrides

`.claude/kit.json` — `swarm.maxAgents` (default 6) caps concurrency; `swarm.checks` is the project's verification command list (reviewers run these verbatim; when absent, setup determines and records them in SWARM.md); `rules."swarm"` applies as an additional instruction. For PR-mode plans (see **Team repositories**):

| Key | What it holds |
|---|---|
| `swarm.worktree` | `{ "create": "<command>", "remove": "<command>" }` for a target checkout outside the session's repo; `<slug>` and `<branch>` are substituted. Include the repo's own bootstrap in `create` |
| `swarm.resources` | `{ "<path glob>": "<tag>" }` — shared local state a unit touching that path holds: a fixed-port dev server, the one local database, the package install |
| `swarm.review` | The team's review tool, run against a pushed PR (`<pr>` is substituted); it replaces the swarm's reviewer agent |
| `swarm.ship` | `ready` \| `draft` \| `ask` (default `ask`) — the owner's standing ship policy |
| `swarm.look` | `batch` \| `per-slice` \| `none` (default `batch`) — when the owner reviews user-facing slices |

```bash
jq -r '.swarm.maxAgents // 6, ((.swarm.checks // []) | join(" && ")), (.swarm.ship // "ask"), (.swarm.look // "batch"), (.rules."swarm" // empty)' .claude/kit.json 2>/dev/null
```
