## Landing

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

