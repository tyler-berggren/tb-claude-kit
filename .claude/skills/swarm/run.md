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
     dispatch loop, or release its slot when the project has a pool. First check no running agent was handed a path
     inside it (**Point other agents only at the integration worktree**); if one was, message it the integration
     path and remove the worktree once it reports. The plan edits stay uncommitted in the primary checkout;
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
