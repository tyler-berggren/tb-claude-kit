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
