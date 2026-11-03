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
3. Run policy for THIS swarm: may agents touch the live/prod database? May the swarm deploy, or does the deploy phase get excluded and left for the user? Merge to main at the end, or leave the integration branch for review? (For a PR-mode plan — a team repository — the answer is never "merge to main", and the ship and look policies come from `swarm.ship` / `swarm.look` when kit.json records them; ask only what they leave open. See **Team repositories** (`pr-mode.md`).) Max concurrent agents (default from `.claude/kit.json` `swarm.maxAgents`, else 6)?
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
- **The agent protocol** (copied verbatim into the file so briefs can reference it — see **Run rules**, `run-rules.md`)

Then:
- Insert the `swarm_runs` row (`status = 'ready'`, `swarm_dir`, `plan_id`, `plan_path`) and one `swarm_units` row per unit
- Add one line under the plan's title: `> **Swarm:** prepared YYYY-MM-DD — see cowork/swarm/<plan_id>/SWARM.md`
- Beyond the answers S3 wrote into it, do not rewrite the plan — it stays the source of truth for *what*; SWARM.md owns *who and in what order*

### Step S5 — Hand off

Tell the user: review `SWARM.md` (especially the decision record), giving the line range of the decision record, the unit graph and each brief, then commit (`/commit`), then start a **fresh session** and invoke `/swarm <ref>` — and that starting that session with `/rc` gives remote monitoring of the run. **Never start the run in the setup session** — the run deserves a full context window.

---

## Remainder Setup

The salvage path. When `/swarm <ref>` hits a `done` or `aborted` run with unmerged units, report the outcome, then offer to set up a remainder run. On yes:

1. **Diff reality against the plan.** What actually merged (integration branch history, plan checkboxes, REPORT.md) vs. what the failed/skipped units owned. Salvageable commits on surviving unit branches are noted — a failed unit's partial work can seed a fresh brief rather than being redone blind.
2. **Re-run Setup over only the remainder** — same S1–S5, but smaller: the decision record carries forward from the prior SWARM.md (copied, then extended — prior answers are not re-asked), and the plan's uncleared review items are cleared with the owner first, as S3 items, now that a human is present. New failures get fresh root-cause attention in the briefs: a unit that failed review twice needs a better brief or a different slicing, not a third identical attempt.
3. Register as a **new** `swarm_runs` row (the old one is history, never reopened), with `notes` linking back to the prior run id. The new SWARM.md lives in the same `cowork/swarm/<plan_id>/` directory as `SWARM-2.md` / `REPORT-2.md`, suffix incrementing.
4. Hand off as usual: review, commit, fresh session, `/swarm <ref>`.
