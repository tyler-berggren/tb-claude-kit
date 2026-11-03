# Plans and swarms

`/plan` turns work into phased files in the repo; `/swarm` finishes a whole plan unattended.

## Plan (`/plan`)

A plan is a numbered, dated markdown file in the repo, worked down phase by phase. What makes it
hold up across sessions is the resume: `/plan NNN` re-reads the plan against the code as it is
now and reports the drift, instead of trusting what the last session said it did.

### Commands

| Command | What it does |
|---|---|
| `/plan <topic>` | Generate a plan from the codebase and the brain, brainstormed with you. It writes the file and stops; building starts with `/plan NNN`. |
| `/plan NNN` | Resume: bind the plan, reconcile it against the current code, then work. |
| `/plan NNN brainstorm` | Flesh out loose phases conversationally before building. |
| `/plan review` | Check your `{{bracketed}}` change proposals for feasibility and coherence, then apply them. |
| `/plan handoff`, `/plan NNN handoff` | Get the plan ready for another agent: bring it current, tidy it, and write in the context that exists only in this conversation. |
| `/plan status` | Where the session's plan stands. |
| `/plan update` | Sweep completed plan items and mark their brain tasks done. |
| `/plan carry` | Sweep unfinished plan items back into the brain. |
| `/plan pr <topic>`, `/plan NNN pr` | PR mode: generate a plan for a team repo, or convert an existing one. |
| `/plan NNN epic` | Publish or sync a PR-mode plan's epic, and its slices as sub-issues, on the team's tracker. |
| `/plan NNN issue <slice>`, `/plan issue <topic>` | Bring one slice's issue current as it starts, or file a standalone issue. |

### Where plans live

`cowork/plans/` by default. `plan.roots` in `kit.json` names more directories (wildcards allowed),
and `for:<scope>` in the argument files a plan under one of them. Numbering is per directory, so a
scoped plan's id carries its scope: `mvp-001`.

A plan with companion documents (an audit, a findings matrix) becomes a directory of the same
name with the plan file inside it. A narrower plan carved out of a bigger one gets a letter and
lives inside its parent: `001a_…`.

### Batches

A batch is any session that works down more than one item: a resumed plan or a swarm run. It asks
the plan's open questions before work starts, then never stops to ask and never waits. Claude
makes each call as a senior developer would, builds it to work and keeps going. At a genuine fork
it still decides, but builds the lean functional version and leaves polish for later, so little
is un-built if you overrule it. Only a critical issue parks. Every call, and anything the UI
checks could not verify, goes into one numbered `## Review` block you read and overrule when you
choose. See [Recommended workflow](workflow.md) for the full rule.

### PR mode

For work that lands in a team repository. The plan is cut into **slices** — one concern, one
session, one small PR that merges the same day (around 20 files or 1,000 changed lines is the
signal to split) — divided by layer so users never see half a change, with wide refactors done
expand–contract.

- **Inside a slice**, UI is verified by code first and a headless browser second. What neither
  can check is noted in the plan and the PR, and the slice ships. The full checks run once, at
  ship time. Draft or ready follows the project's standing ship policy (asked every time when
  there is none).
- **Every body is a decision record.** Such work usually changes code and decisions other people
  made, so every epic, issue and PR body gives each decision's why, its gains and costs, and the
  alternatives not taken. It credits the prior work found by a prior-art sweep (blame of the
  replaced lines, the PRs behind them, open PRs over the same files, decision records), and
  mentions each person it changes with a reason.
- **It reads the remote default branch**, not your checkout, carries decisions with defaults so
  nothing blocks, and stays short enough to travel with each PR for reviewers who have never
  seen your notes.

### Epic and issue modes

`/plan NNN epic` publishes the decision record to the team's tracker before any code, so the
team sees the planned workstream and who it touches while they can still shape it. What goes up
depends on `plan.issues.publish`: `on-start` (the default) publishes the epic alone and each
slice's issue is created when that slice starts; `ahead` publishes one sub-issue per slice up
front, in dependency order, with native sub-issue and blocking links. A re-run syncs the tracker
to the plan.

`/plan NNN issue <slice>` brings one slice's issue current as it starts. `/plan issue <topic>`
files a standalone issue.

No issue is created and nobody is mentioned without your go. Refreshing the body of an issue that
already exists does not wait.

### Configuration

```json
{
  "plan": {
    "roots": ["cowork/plans", "cowork/projects/*/plans"],
    "issues": {
      "publish": "ahead",
      "repo": "your-org/your-repo",
      "assignee": "your-login",
      "labels": ["P2"],
      "neverLabels": ["agent-queue"],
      "check": "node scripts/check-body.mjs {file} --kind {kind}",
      "sweep": "prior-art"
    }
  },
  "rules": { "plan": "Ship with `npm run ship`. Branches are <login>/<issue>-<slug>." }
}
```

- **`roots`** — directories plans may live in. Subdirectories are found automatically.
- **`issues.publish`** — `on-start` (default) or `ahead`, as above.
- **`issues.repo`** — the tracker's repository, when it is not the session's own.
- **`issues.assignee`**, **`issues.labels`** — applied to every issue created.
- **`issues.neverLabels`** — labels the team's automation acts on (an agent queue, an auto-close
  rule); never applied.
- **`issues.check`** — a command that lints a body file before it is posted.
- **`issues.sweep`** — the project's prior-art sweep agent or script, when it has one.
- **`rules.plan`** — the team's ship command and policy, branch conventions, priority tiers and
  CI path map, so the kit stays generic.

The tracker is reached through `gh`. When a key is absent, the mode asks rather than guesses.

## Swarm (`/swarm`)

Hand `/swarm` a plan and it completes the whole thing — end to end, without stopping to ask you
anything. Parallel agents where the dependency graph allows it, a supervised serial march where it
doesn't. The point is not parallelism for its own sake; it's that the plan finishes while you're
away, with every judgment call either answered by you up front or made autonomously and written
down for your review afterwards.

### The two-session lifecycle

```
/plan 021                          # generate the plan as usual
/swarm 021                         # SETUP — conversational, in this session
  → decomposes the plan into a dependency graph of units
  → asks you every question the run could possibly need answered
  → writes cowork/swarm/021/SWARM.md, registers the run in the brain
/commit                            # the package travels with the repo

# fresh session (start it with /rc to monitor remotely)
/swarm 021                         # RUN — autonomous, no questions
  → dispatches worktree-isolated agents wave by wave
  → reviews every unit before merging it
  → writes cowork/swarm/021/REPORT.md, notifies you when done

# only when something is parked as critical, or you want to walk the calls, in ANOTHER session
/swarm review                      # REVIEW — an optional batch look, while the run keeps going
```

You never say "setup" or "run" — the skill infers the phase from the brain: no registered run
means setup, a `ready` run means run, a `running` run means resume after an interruption. The
same inference gives you `/swarm status` (read-only), `/swarm abort`, and `/swarm report`.
`/swarm review` is the one you name, and you always run it in a second session, never the run's own.

### Setup — front-loading every human decision

Setup does a fresh-eyes reconciliation of the plan against the current code, then slices it into
**units** — the chunk of work one agent completes in one git worktree. The slicing rule that
matters most: **serial chains that share files become one unit.** Splitting a
migration → rewrite → re-measure chain across three agents just manufactures merge conflicts;
real parallelism comes from disjoint file territories. Each unit gets dependencies, a file
territory, and **resource tags** naming shared mutable state outside git — a live database, a
deploy, a tile pipeline. Two units holding the same tag never run concurrently, even when their
code doesn't overlap.

Setup then batches every open question to you in one pass, each naming the plan line it comes from: the plan's own open questions,
anything reconciliation surfaced, and run policy — may agents touch the live DB? may the swarm
deploy? merge to main at the end, or leave the integration branch for review? Answers about what
gets built go into the plan, as its own numbered decisions. Run-policy answers become a numbered
decision record in `SWARM.md`. Agent briefs cite both. Anything you delegate back gets a committed
default, written down. A question that survives setup unanswered is a setup failure.

Setup also verifies the project's checks pass on the current baseline (a swarm can't tell its own
failures from inherited ones), reads retro insights from previous runs, proposes a tier per unit,
and reports the **parallelism profile** honestly — "6 units, but one chain is 70% of the work" —
so you know whether you're approving a wide fan-out or an autonomous serial run. Both are fine;
manufactured parallelism is not.

### Run — the orchestrator session

The run session reads the registered graph and becomes an orchestrator. Each unit agent works in
its own **git worktree** on its own branch, from a brief that is fully self-contained. Agents are
bound by a no-questions protocol with a decision ladder: the plan → the decision record → brain
decisions → smallest reasonable interpretation, committed to, built to work and recorded (built lean at a genuine fork). They
verify UI by code first and in a headless browser of their own second, never touch yours or open a
visible one, and note
what neither can check instead of fighting it. The one thing that stops a unit (never the run) is a
critical issue. Their only channel out is a structured final report: done / calls / unverified /
critical / blocked. The orchestrator copies the calls, unverified items and critical parks into the
plan's `## Review` block.

Nothing merges unreviewed. Every completed unit gets an independent **reviewer agent** that runs
the project's checks (from `swarm.checks`, verbatim — reviewers never guess) and the unit's
verification criteria from the plan. Failures get up to two fix cycles, the second always on the
top tier (Opus · high); then the unit is marked failed, its dependents are skipped, and everything else
continues — **failures degrade the run, never halt it**. The orchestrator merges passing units
into an integration branch (`swarm/<plan_id>`), resolving conflicts itself: it's the only mind
that has seen every brief. A final integration gate — the plan's full verification table plus a
whole-diff review — stands between the integration branch and your main branch.

**Your IDE's checkout is never touched.** The run never switches the branch your IDE has open, so
you can keep working on main throughout. Every swarm branch lives in its own worktree under
`.claude/worktrees/`:

- the integration branch at `.claude/worktrees/swarm-<plan_id>`;
- each unit in the worktree the Agent tool creates there, branched from the integration tip;
- any branch a review needs to serve.

The plan, `SWARM.md` and `REPORT.md` stay in your main checkout. The orchestrator edits them there,
next to your own edits, so the plan it updates is the one you mark, and every `path:line` it gives
you opens in your IDE. It doesn't commit mid-run. At the end it commits only those files, leaving
anything else you have staged untouched. At the end, the run merges your main into the
integration branch and then fast-forwards main, so your commits from during the run are kept. If
that would overwrite uncommitted work, the run leaves the branch unmerged and tells you why.
`/plan` follows the same rule: your IDE holds main, and a PR-mode slice or any other branch gets a
worktree.

Three things keep an unattended run honest:

- **A stall watchdog** — a hung agent never sends a completion signal, so a background timer
  checks for units with no state change in ~30 minutes and re-dispatches or fails them.
- **Mid-run steering** — the no-questions rule binds agents, not you. A message you send mid-run
  (typically via `/rc` from your phone) becomes a timestamped amendment to the decision record,
  applied to everything not yet dispatched.
- **Push notifications** — sent when the run completes, fails or is aborted, when something parks
  as critical, and when a review is ready for you. Nothing else interrupts you.

### Model tiers

Every agent a run spawns (builder, fixer or reviewer) goes out on one of five **tiers**. Each tier is
an agent definition the kit ships in `.claude/agents/`, and it sets both the model and the reasoning
effort. The Agent tool can't set effort per call, so an agent definition is the only way to control it.

| Tier | Model · effort | For a task that is… |
|---|---|---|
| `swarm-sonnet-low` | Sonnet · low | Very simple: a copy sweep, config plumbing, an explicit item list |
| `swarm-sonnet-medium` | Sonnet · medium | **Default.** Typical and well defined: named files and items, an existing pattern, concrete checks |
| `swarm-sonnet-high` | Sonnet · high | Slightly above average: more moving parts under a clear spec |
| `swarm-opus-medium` | Opus · medium | Two notches above: exactly one judgment signal, or a narrow high-stakes unit with no pattern to copy |
| `swarm-opus-high` | Opus · high | Three notches above: a high-stakes signal with reach (dependents, several packages, an open fork), or two or more signals |

Unit briefs are self-contained and fully specified, which is the narrow, pre-specified work Sonnet
does well. So Sonnet is the default, and a unit goes to Opus only for a reason you can name. When a
unit sits between two tiers, the lower one wins: a wrong low pick costs one review cycle, a wrong
high pick costs time and tokens on everything it touches. A high-stakes unit (security, permissions,
an algorithm, concurrency) that is narrow and copies an existing pattern builds on Sonnet · high and
gets an Opus · high reviewer; anything holding a live database or a deploy, and any gate, stays on
Opus. The
tiers name models by alias (`sonnet`, `opus`), so they always run the newest model your Claude Code
knows, and the kit never needs editing when a new version ships.

- **Who decides.** Setup proposes a tier for each unit, and you can pin any of them. The orchestrator
  makes the final call at dispatch, using what the run has shown so far. It records the tier and its
  reason on the unit.
- **Reviewers** use the same tiers. Sonnet · medium is the default. Opus · high reviews gates, units
  others depend on, a narrow high-stakes unit built on Sonnet, and always the final integration review.
- **Escalation.** A fix for a judgment mistake runs on Opus. The second fix cycle is always Opus ·
  high. If two Sonnet units fail review on judgment, the rest of the run moves up a tier.
- **Verified, not trusted.** Some Claude Code versions have ignored a requested subagent model. The
  run probes a tier before dispatching anything. After each unit, it reads the model and effort the
  API actually served from the agent's transcript, and the report lists any mismatch.
- **Run the orchestrator on Opus.** It makes the tier calls and resolves merge conflicts, and the run
  says so when it isn't on Opus.

The tier definitions reach existing projects through [automatic adoption](install.md#automatic-adoption-of-new-kit-files).
Claude Code loads agent definitions when a session starts, so start a fresh session before a run.
A session that can't see them falls back to the built-in agent with the tier's model, and the effort
follows the orchestrator's.

### The report

`cowork/swarm/<plan_id>/REPORT.md` is the morning-after read: what merged, what failed and why,
how many items wait on you, and verification output. The items themselves live in one place, the
plan's `## Review` block. Every call made autonomously has its alternatives and switching cost,
and every unverified item says what could not be checked, with its URL when there is one. It is
the review surface that replaces mid-run questions. Only critical parks wait on you; a call you
leave unmarked stands as built. After each run the
orchestrator also logs retro insights to the brain (tagged `swarm-retro`) — slicings that
conflicted anyway, tiers that kept escalating or turned out more than needed — which the next setup reads
before slicing. The heuristics improve from your runs, not from guesses.

### When a run doesn't finish clean

`/swarm <ref>` against a finished run with unmerged units offers **remainder setup**: diff what
actually merged against the plan, note salvageable commits on surviving branches, and set up a
new, smaller run over what's left — decision record carried forward, failed units re-briefed with
root-cause attention rather than retried blind. `/swarm abort` stops a live run but keeps every
branch and worktree; deleting work is always your call.

### Team repositories (PR-mode plans)

A plan in `/plan`'s PR mode lands in someone else's repository through reviewed pull requests,
and the swarm adapts to that instead of fighting it:

- **Slices and lanes.** Each slice is a unit; a **lane** is a chain of slices over the same files
  (usually one adopter), run in order, while lanes that share no files run side by side. A slice
  may stack on its lane's previous slice, so a lane never waits on a review or CI.
- **Three kinds of slice, one rule.** `invisible` (nothing a user sees), `fix` (restores intended
  behaviour) and `user-facing` all ship as soon as they are green. A user-facing slice's UI is
  verified by code, then headless, and what could not be verified goes into the PR notes. **Only a
  critical issue parks a slice**, because a team repo often deploys a green PR on its own.
- **An optional batch look, beside the run.** When something is parked as critical, when a project
  opts back into looks (`swarm.look: batch`), or when you ask, the orchestrator tidies the plan's
  `## Review` block into one numbered list. Each look gives:
  - the page's URL;
  - what changed, what to test and what right looks like;
  - the widths to check;
  - what it runs on.

  Each call follows, with its alternatives. The orchestrator then sends one push notification and
  **keeps dispatching**. You run the look in a parallel session with `/swarm review` (below). Your
  feedback comes back as a single amendment. Slices that were parked for the look then write their
  tests and ship; under the default, the rest have already shipped.
- **The team's rules, not the swarm's.** Slices ship through the project's ship command; the
  team's own review tool (`swarm.review`) replaces the swarm's reviewer; a slice is `merged` when
  the team merges it; a red CI group gets its fix pushed at once. Nothing ever merges into the
  team's default branch locally.
- **A repository outside the session.** When the code lives in another checkout (a sibling
  clone, a symlink, a submodule), the Agent tool's worktree isolation would copy the wrong repo, so
  each unit makes its own worktree in the target with `swarm.worktree`'s commands.
- **A worktree pool, for big repositories.** With `swarm.worktree.pool`, units lease a slot
  that was bootstrapped once instead of creating a worktree each: the slot is branched in place,
  handed back once the branch is pushed, reset to a clean default branch with dependencies kept,
  and reused — a lane prefers its last slot, and fix, ship and replay agents reuse their unit's.
  Nothing is removed mid-run.
- **One CI watcher per run.** Shipping agents end at the push. A red caused by CI's
  infrastructure (a process killed for memory, a hung machine, every failing test at 0–1 ms) is
  rerun first, by the project's watcher when `swarm.watch` names one, and gets a fix agent only
  if it repeats on the same head. No agent waits in a foreground poll loop.
- **Shared local state is locked by path.** One local database, dev servers on fixed ports, one
  package install: `swarm.resources` maps path globs to tags, and two units holding a tag never
  run at once.

### Live progress and time estimates

When a run starts, the orchestrator hands you a progress display (`/pbar`) to paste into any
terminal. Besides the counts, it shows time estimates from `eta.py` in the swarm skill folder:
- **each in-flight unit:** time left in its stage (build or land), flagged OVERDUE when past it;
- **each lane:** its finish time;
- **the whole run:** time left, with a clock time and a slow case.

The brain logs every unit's status change through triggers on `swarm_units`
(`swarm_unit_events`), and the estimator learns each stage's duration from that log. It starts
from a prior and moves toward the observed median as units finish, weighting the current run's
samples double, so the numbers get more accurate as the run goes. Time a unit spends parked for
you is never counted as work.

### Reviewing mid-run (`/swarm review`)

A run parks work for you only when it is critical, or on every user-facing slice if the project opts
into looks, and the run shouldn't stop each time you look. `/swarm review` is the batch look run from a
**second session** beside the orchestrator. It
borrows only what your looks need, gives it back as you finish, and hands your verdicts over in
one message.

1. **It finds the run and its orchestrator.** The orchestrator records its session name on the run,
   so the review session can message it.
2. **It plans what to serve.** Every look names what it runs on: the app, and the checkout or branch
   that serves it. The session groups your click-through so each app changes checkout at most once,
   and lanes a working unit is waiting on go first.
3. **It takes a hold, then serves.** It records the resource tags it borrows in `swarm_holds`, such as
   an app's fixed port or the local database your fixtures live in, and tells the orchestrator.
   Running units keep building, and defer only the step that would use held state, such as a page
   check or a database reset. Apps are served from their checkouts one start per checkout at a time,
   because two package installs into one checkout corrupt each other. Every server keeps its full
   log.
4. **You look.** It opens your shared browser and a status display showing which checkout each app
   is serving from. You mark items right in the plan (`[x]`, `[fix]` with a note, or a note under a
   call's option) or just say them. A look checked against the wrong checkout is void and gets
   rechecked.
5. **It releases as you go.** When a group's looks are done, it stops those servers, restores the
   files the dev server rewrote, releases the holds, and tells the orchestrator, so a waiting unit
   can go on.
6. **It hands off.** It reads your marks and asks about any call you left unmarked, since silence
   never counts as approval. It writes one handoff file, releases everything, and messages the
   orchestrator, which applies it as one amendment. Only the orchestrator writes the plan's
   bookkeeping, `SWARM.md` and the unit table.

### Configuration

```json
{
  "swarm": {
    "maxAgents": 6,
    "checks": ["npm run check", "npm test"],
    "ship": "ready",
    "look": "batch",
    "review": "node scripts/review.mjs --pr <pr>",
    "worktree": { "create": "git -C ../app worktree add .claude/worktrees/<slug> -b <branch> origin/main", "remove": "git -C ../app worktree remove .claude/worktrees/<slug>",
                  "pool": { "acquire": "scripts/slot.sh acquire <lane> <branch> <base>", "release": "scripts/slot.sh release <slot>", "list": "scripts/slot.sh list", "size": 8 } },
    "watch": "scripts/ci-watch.mjs (launchd, every 5 min) — reruns infrastructure reds once per head",
    "resources": { "db/schema/**": "db:local", "apps/web/**": "port:web", "package-lock.json": "install" },
    "reviewStack": {
      "shared": "curl -sf http://localhost:8080/health",
      "sharedStart": "npm run proxy",
      "serve": "cd <checkout> && npm run dev -w apps/<app>",
      "port": "jq -r .port <checkout>/apps/<app>/dev.json",
      "tag": "port:<app>",
      "holdAlso": ["db:local"],
      "restore": ["apps/*/next-env.d.ts"],
      "logs": ".claude/state/logs"
    }
  },
  "rules": { "swarm": "Never touch the production database — use the staging branch." }
}
```

- **`maxAgents`** — concurrency cap for unit agents (default 6)
- **`checks`** — the project's verification commands; reviewers run these verbatim on every unit.
  When absent, setup determines the commands itself and records them in `SWARM.md`
- **`rules.swarm`** — free-text instruction applied whenever the skill runs
- **`ship`** — PR-mode ship policy: `ready` (you have pre-approved ready PRs; a draft only on
  your word), `draft`, or `ask` (the default, which an unattended run can only park, so setup
  asks once when it is unset)
- **`look`** — whether user-facing slices wait for you: `none` (the default: they ship, and only
  critical issues park), `batch` (the older flow: every user-facing slice parks for one batch look),
  or `per-slice`
- **`review`** — the team's own review tool, run against a pushed PR; it replaces the swarm's
  reviewer agent
- **`worktree`** — create and remove commands for unit worktrees when the code lives in a
  checkout outside the session's repo; put them at `.claude/worktrees/<slug>` in that repo
- **`worktree.pool`** — acquire, release and list commands plus a size, for a big repository where
  units lease a slot that was bootstrapped once instead of creating a worktree each
- **`watch`** — the project's CI watcher, which reruns a red caused by CI's own infrastructure
  before any fix agent is sent
- **`resources`** — path globs to resource tags for shared local state
- **`reviewStack`** — how `/swarm review` serves a look. It gives:
  - the shared stack's health check and start command;
  - the command that serves one app from one checkout, and the one that prints its port;
  - the tag a served app holds, plus tags the whole review holds;
  - files the dev server rewrites (restored when it stops);
  - where logs go.

  Every key is optional; without them, the review asks once how to start an app.

### State on disk

| Where | What |
|---|---|
| `cowork/swarm/<plan_id>/SWARM.md` | The package: run config, decision record, unit graph, per-unit briefs, agent protocol |
| `cowork/swarm/<plan_id>/REPORT.md` | What actually happened. A remainder run writes `SWARM-2.md` and `REPORT-2.md`, then `-3` |
| The plan's `## Review` block | Critical parks, calls made in your absence and unverified items, numbered. Only the critical ones wait on you |
| `swarm_runs` / `swarm_units` (brain DB) | Execution state — what phase inference and resume reconstruct the world from; `swarm_runs.orchestrator` is the session a review messages |
| `swarm_unit_events` (brain DB) | Every unit status change, logged by triggers; what the time estimates learn from |
| `swarm_holds` (brain DB) | Shared state a `/swarm review` session has borrowed from the live run, open until released |
| `cowork/swarm/<plan_id>/review-YYYY-MM-DD-<n>.md` | A review session's handoff: what was served from where, and every verdict |
| `swarm/<plan_id>` branch | Integration branch; kept after the run for inspection |
| `.claude/worktrees/swarm-<plan_id>` | The integration branch's worktree; removed once merged, kept when the branch is left for review |

The plan file stays the source of truth for *what*; `SWARM.md` owns *who and in what order*;
`REPORT.md` records *what actually happened*. The plan is updated with checkboxes and phase
statuses as units merge, exactly as `/plan` sessions would — a swarmed plan and a hand-worked
plan look the same afterwards.
