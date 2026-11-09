# Autopilot: keep working ahead

The default for every resumed plan and every swarm run. The owner should never have to ask "what can
we work on next?". A session bound to a plan keeps the plan moving until nothing in it can move
without the owner, and says so.

A project turns it off with `rules."plan"` in `.claude/kit.json` containing `autopilot: off` (or
`autopilot: ask`, which keeps the queue below but asks before each new item). Absent means on.

## The standing approval

The owner's one confirmation at Resume's R3 (or a swarm's setup) approves the plan's whole build order,
not only the batch in front of it: every open item in the plan, in its order, under the plan's own
decisions. The **Batches** rules apply to all of it: calls are made and recorded, and only a
**critical** item parks. Work the plan already names as needing the owner (a release, a spend, a
production write it marks as theirs, an open question that bites the item) stays theirs.

## The work-ahead queue

Every plan in autopilot carries a short ranked section, `## Work ahead`, directly under the RESUME
banner's phase (or under `## Review` when there is no phase): the next items that can run now, each
one line with its plan line and what it waits on, if anything.

```markdown
## Work ahead
1. <item> (<plan>:<line>) — runs now
2. <item> (<plan>:<line>) — runs now, beside <the long job>
3. <item> (<plan>:<line>) — after <what it waits on>
```

- **Filled from the plan,** in this order: the build order's next open items; items the current run
  unblocks; the plan's improvement lists and retro boxes; Review items marked call or unverified that
  can be settled by work rather than by the owner. Never invented scope: an item outside the plan is
  added to the plan first, as **New items** says, and only when it serves the plan's goal.
- **Kept current:** an item leaves when it is done or becomes the owner's; items that surfaced during
  the work are added as they surface. Five to eight lines at most. It is a baton, like the rest of the
  plan.

## While something waits

A long job (a load, a deploy, a CI run, a batch of agents) is never a reason to end the session idle.

1. **Hand over its watcher** (`/pbar`) as usual.
2. **Take the top runnable item from Work ahead** that does not touch what the job is using (its
   files, its database rows, its machines, its deploy target). Start it in the same turn.
3. **Fan out within the session's size guideline.** Independent items may run as background agents
   in worktrees, together with the job: up to the project's agent cap (the swarm's concurrency cap, or
   eight when none is set). A whole swarm's worth of work is a `/swarm` run, not ad-hoc agents.
4. **When everything runnable is done and only waits remain,** keep the session awake: a background
   heartbeat (`sleep 1800`, `run_in_background`; restarted on each wake) or, inside `/loop`, a
   `ScheduleWakeup` of 1200 to 1800 s. Each wake reads the jobs, advances whatever they unblocked,
   refills the queue, and runs the goal check when one is due.

## The goal check

Autopilot keeps work moving; the goal check keeps it pointed at the goal. Every plan carries a
`## Goal` block (goal, finish line, measure, pace), and an agent with none of the session's context
reads the plan's record against it: at each milestone, before a new Work ahead item when the last
check is over four hours old, at least daily (the heartbeat runs it), and when the owner asks. The
session writes its verdict in the plan, reorders Work ahead by it and leads the next status with it.
The full rules and the agent's brief are in `goal-check.md`.

## Ending a turn

A turn ends with a short status: the last goal check's verdict when one ran since the last status, what moved, what is running (with its watcher), and what is next
from the queue. Never a question asking the owner what to work on. The only questions are the
plan's open questions and critical parks, asked as **Batches** says.

## When autopilot stops

It stops, says why in one line and sends a push notification when:
- every remaining item is the owner's (a critical park, an open question, a step the plan reserves
  for them), or the plan is done;
- a failure repeats after two honest fixes (the swarm's two-cycle rule applies here too);
- the owner says stop.

On stopping, run the Handoff flow's short form: the plan's banner, Work ahead and Review current, so
the next session resumes in a minute.
