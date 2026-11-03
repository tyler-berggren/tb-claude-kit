## Team repositories (PR-mode plans)

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
