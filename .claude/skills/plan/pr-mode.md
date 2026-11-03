## PR Mode

The default flows assume one developer on one repo: phases, a checkout, commit when done. PR
mode is for work that lands in a **team repository** through pull requests reviewed by other
people, often on a codebase you do not own. The plan stays private (it lives in your own repo),
but its build order is a sequence of clean PRs, and the plan file travels with each PR, so it
has to read well to a reviewer who has never seen your notes. Most of that work changes code
and decisions other people made. So every body records its decisions, credits the prior work,
and tells the people it changes (see P5).

Usage: `pr <topic>` (generate), or `NNN pr` (convert an existing plan, then resume). A PR-mode plan
carries `**Mode:** pr` in its header; Resume detects it and applies these rules automatically.

### What changes from the default flows

| Default | PR mode |
|---|---|
| Build order in phases | Build order in **slices**: each one concern, built in one session, shipped as one PR that merges the same day it was branched — at most ~20 files / ~1,000 changed lines, or the size the team's own review tooling treats as light. Split by layer so users never see half a change. See **How to cut the work** below |
| Proposed phases (Generate, G2) | Proposed **slices**, one line each: what it delivers, what the owner will see, rough size |
| Reads the working tree | Reads the **remote default branch** (`git fetch`, then `git show origin/<default>:<path>`, `git grep <pat> origin/<default> -- <dir>`). A checkout on a feature branch is stale by definition |
| One brain task per phase | One brain task per PR: `Plan <id> PR-k: <title>` |
| Reply header `Plan NNN / Phase X` | `Plan NNN / PR-k` |
| Companion files cited freely | **No references a reviewer cannot follow**: no other plan numbers, no private companion files, no personal notes. Cite the code (path and line on the default branch), issues, PRs and ADRs instead |
| Items may name a phase's work loosely | **The next slice's items are checkable steps with a path**, each small enough that a coding agent with no memory of the conversation can do it, tick it with ` — done: <note>`, and commit. **Later slices stay one line each** (what it delivers, what the owner will see) until they are next — detail written far ahead of the code goes stale and has to be corrected before it can be built |

### How to cut the work: slices that merge the same day

The unit of work in a team repo is a **slice**: one concern, built in one session, shipped as one
PR that merges the same day it was branched. Weigh both costs before choosing fewer, bigger PRs:

- **A PR's fixed cost is usually small and unattended:** one CI run and a review bot, often in
  parallel, that nobody has to watch. Work goes on while they run.
- **A long-lived branch's costs grow with its size and its age.** The default branch moves under
  it, so it rebases again and again and re-verifies after each; features other people merge onto
  the model it is changing have to be ported onto it; a bigger diff draws more findings per review
  round; scope creeps in because the PR is "still open"; and every extra file is conflict surface.
  A dozen small PRs usually land sooner than one big one, and each is easier to review.

The rules:

- **Size signal.** At most ~20 files and ~1,000 changed lines, not counting generated files — or,
  better, the threshold the team's own review tooling uses for its lighter review. When a branch
  passes it, ship what is there and start the next slice. A slice that needs lettered sections is
  probably two slices.
- **Split by layer, not by adopter, when the visible result must land consistently.** Invisible
  plumbing first — the shared library capability, the new component, the additive column — each a
  PR that changes nothing a user sees; then one small PR that switches the visible change on
  everywhere at once. Users never see half a change, and reviewers never see a 200-file diff.
- **Shared code first, adopters after.** A change to a widely used package tends to pull every
  dependent into CI; an adopter-only change usually runs only that adopter's checks.
- **A wide refactor is expand–contract, never a big bang.** Add the new form beside the old so
  nothing breaks; move callers over in batches, each its own green PR; delete the old form once no
  caller remains. Other people's work keeps landing on a codebase that compiles both ways, instead
  of arriving on the old form and having to be ported.
- **Real isolation boundaries still split:** a schema change, a data backfill, anything touching
  auth or money gets its own PR, because a reviewer needs to see it alone.
- **Never hold two open branches over the same files.** Sequence them; the second rebases once,
  after the first merges.
- **Shape each slice for the pipeline.** Learn which paths trigger what in the team's CI. A diff
  confined to docs and agent config often runs a light gate, while build scripts or shared tooling
  pull in extra test groups and invalidate caches — batch those expensive-path changes into one
  slice. The project's `rules.plan` override is where its CI path map belongs.
- **Work that depends on data collected after merge is not a planned PR.** Put it in the close
  phase as a conditional follow-up and open it only if the data says so.

### Inside a slice: verify, test, ship

1. **Build with quick checks only:** type-check the package being edited and run only the tests
   related to the changed files (the test runner's related or changed-files mode, or the files by
   name). Seconds, not minutes. Never a whole suite mid-build, never the whole repo.
2. **Verify the UI yourself, in order, then move on.** Code first: types, tests, the logic that
   renders it. A headless browser of your own second (`/look`, **Headless**), when code cannot
   settle it. What neither can check cheaply is written down as unverified in the plan's review
   block and the PR notes, and the slice goes on without it. Design, layout and wording choices
   are **calls**: make them as a senior developer would and record them (see **Batches**). Nothing
   parks for the owner unless it is critical. New ideas go to a later slice.
3. **Then the tests,** pinning what was built. Data-layer logic — queries, predicates,
   permission rules — is the exception: prove it against a real engine as it is written. It does
   not depend on taste, and it is where the serious bugs hide.
4. **Ship through the project's ship command:** rebase once, run the team's scoped checks once
   with the prior-art sweep beside them (see P5), then the team's review bot locally if it has one.
   Then ship ready or as a draft, as the project's ship policy says.
5. **While CI runs, start the next slice.** When a CI group fails, push the fix as soon as it is
   ready: that run is already lost, and waiting for the rest of the verdict only gives the default
   branch time to move under the PR.

Keep the full output of every check in a log and search it — never re-run a check just to see
more of its output. Do not rebase mid-build: rebase once at ship time, when the host reports a
conflict, or when the slice needs something that just landed.

### Step P1 — Investigate on the default branch (Phase 0 of the plan)

Before proposing anything, inventory what exists: the components that already do the job, every
place the thing is implemented differently, the team's own recorded decisions (ADRs, decision
logs, issue threads, contract docs), open issues that already cover parts of the work, and any
priority tiers the team uses (release waves, milestones). Cite a path and line for every claim.
This phase is marked done in the plan with its findings summarised **in plain terms** under
Context; the evidence detail can live in a companion file for you, but the plan must stand
without it.

**Record who is behind each finding**: who built the component, wrote the decision record,
opened the issue, or has an open pull request over the same files. Most team-repo work
changes something someone else built or decided. P2 credits those people, and P5 tells them
what changes. Run this sweep in a fresh subagent when one is available, so its reading stays
out of the planning context. The project's `rules."plan"` may name a dedicated sweep agent or
script. Blame the lines the work will replace, read the pull requests they came from, and
search the host's issues and pull requests by concept, not only by file.

### Step P2 — Decide, with defaults

Two tables in the plan, before Build Order:

- **The new standard** (when the plan standardises something): each existing component the
  plan names as *the* one, where it lives, and **why that one** over the alternatives found in P1.
  Reviewers accept "we chose X" far more readily when the table shows what else existed.
- **Decisions**: every decision, its **owner**, the **default the plan proceeds on**, and
  where in the build order it bites. Record for each one:
  - **why** it was made;
  - the **alternatives**, with what each would have gained and cost;
  - the **prior record** it builds on, changes or reverses (linked, author named);
  - **who it affects**.

  This is what every body in P5 draws from, so write it once here, tersely. A missing decision
  never blocks a PR. The default ships, and the PR body flags it and tells the people it
  affects. Record answers in a **Decisions taken** table as they arrive. A decision that is the
  plan owner's to make, and that bites before building starts, is an **open question** instead
  (see **Batches**): it is answered before the batch that needs it.

### Step P3 — Write the plan (PR mode template)

Same top-level sections as the default (`Source`, `Context`, `Build Order`, `Out of Scope`,
`Verification`), plus these, in this order after the header:

1. **The short version** — what ships, in which slices, for someone who reads nothing else —
   and a small **Status** block: where the work is, what is next. The whole plan stays short:
   goal, decisions, the slice list, status. History belongs in commits and PR bodies.
   **Review** and **Open questions** (see **Batches**) sit with it, near the top, when they
   hold anything; both are the owner's and stay out of any copy that travels with a PR.
2. **The new standard** and **Decisions** (P2).
3. **Priority tiers**, if the team has them: which adopters get full work and which are
   "wire only" (pointed at the standard, listed with a reason, never optimised). Put the tier
   next to every adopter that appears later.
4. **PR conventions for this plan**: how every body opens (see P5), who gets told what
   changes, how the plan file travels with the PR, and any preview-before-ship rule the
   project has.
5. **Handoff: ground rules for whoever codes this** — the reading list in order (the team's
   agent/contributor rules first), where and how to work (package manager, runtime, the slice's
   worktree at `.claude/worktrees/<slug>` in the team repo, never a branch switch in its primary
   checkout, branch naming copied from the team's history, issue-first if the team requires it, one
   commit per section), the **stay-current steps** (fetch; fast-forward the primary checkout's
   default branch in place with `git -C <primary> merge --ff-only origin/<default>`, skipping it
   when that checkout is on another branch; read the log of the surface since the last session —
   and do not rebase a feature branch on a schedule: once, at ship time, in its worktree), the
   quick check for building and the full
   check for shipping, the ship command, and what to do when the plan turns out to be wrong.
6. **Build Order, by slice.** Each slice has: a `**Status:** open · **Waits on:** …` line; an
   **In plain terms** paragraph (what it does and why, for a non-engineer); for the NEXT slice,
   its checkable items, and for later slices one line (what it delivers, what the owner will see,
   rough size) until they are next; and an **Exit** line. Once the slices are published (see
   **Epic Mode**), each row also carries its issue number. A rollout is **one slice per adopter**,
   under a shared recipe so each stays short. The `RESUME WORK HERE` banner sits on the first
   open item, as always.
7. **Verification per PR** and **Risks**, as tables or short lists.

### Step P4 — Register

Brain: one task per PR (`Plan <id> PR-k: …`), `plan_id` and `plan_path` in `meta`; one decision
entry per row of **Decisions taken**; the open decisions as one question entry.

Then the tracker: `NNN epic` publishes the epic and, when the project publishes ahead (see
**Issue policy**), one sub-issue per slice, so the team sees the plan before any code.

### Step P5 — PR bodies, previews, and shipping

- **Every body is a decision record, written for the humans who read it.** This covers the
  epic, each issue and each PR. A PR body opens with, in order:
  - **Goal**: one or two sentences.
  - **Summary**: what changed, in plain language, naming the standard or component it
    introduces.
  - **Decisions**: every one, UI / UX / design first, then data, API and architecture. For
    each: why, what it gains and costs, the alternatives not taken and why, the prior record
    it builds on or changes (linked, author named), and whose call it is.
  - **Who this touches**.

  All of this comes before anything technical, and before the team's own template sections if
  it has any. A decision that changes or reverses someone's recorded decision says so in its
  first line. **The plan travels with the PR:** inline it in a collapsed block when it is
  short. When it is long, or the team keeps plans in the repo, commit it there and link it by
  a **commit-pinned** permalink. A relative link resolves against the default branch, where
  the file does not exist until merge, and hosts cap body size.
- **Credit the work you build on, and tell the people you change.** Most work in a team repo
  changes code or decisions someone else made. Before each body goes up, run the prior-art
  sweep (P1's, re-run on the actual diff for a PR). It covers the blame of the replaced lines,
  the pull requests behind them, open pull requests over the same files, code owners,
  decision records, and issue threads on the same concepts.
  - **Credit** each piece of prior work by link and author name.
  - **Mention** (`@login`) each person with a real stake once, under **Who this touches**,
    with a line saying what changes for them. A real stake means their code is replaced,
    their recorded decision changed, their idea built on directly, or their open work
    overlaps. No reason, no mention.
  - **Leave out:** bots, and a code owner whose only stake is ownership where the host
    already requests their review.
  - **Once per concern.** Tag people on the epic and on the PR that changes their work, not
    on every issue in between. A slice's sub-issue names them by profile link, without the @.
    A standalone issue (no epic, no PR yet) tags like an epic.
  - **Timing.** Mention people when the text is created. A mention edited into a body is not
    reliably notified, so people found later go in a new comment.
  - **Package names.** Keep scoped package names (`@scope/pkg`) in code spans: hosts read a
    bare `@owner/name` as a team mention.
- **Verify, then ship.** A user-facing change is verified by code, then in a headless browser,
  before its tests are written (see **Inside a slice**). It does not wait for the owner. Its calls
  go into the plan's review block, and what could not be verified goes there and into the PR notes
  (see **Batches**).
- **Draft or ready is the project's ship policy** (`swarm.ship` in `.claude/kit.json`, or the
  `rules."plan"` override). The options:
  - `ready`: the owner has approved ready PRs in advance, and a PR is a draft only on their
    word for it.
  - `draft`: every PR opens as a draft.
  - `ask`: the question is put at ship time, every time. This is the default when no policy
    exists.

  Many teams auto-merge a ready PR, so ready is a shipping action. It happens only under a
  standing policy or the owner's explicit choice in that session. **A decision someone else
  owns does not by itself make a PR a draft.** The body records it, says plainly whose call
  it was, and tells the owner. Whether the PR waits for them is the policy's call; many teams
  prefer reacting to live code over debating drafts. A draft that waits on someone needs a
  direct ask to that person, because review requests alone are easy to ignore. Never merge
  from the skill.
- **Ship only through the project's ship command** (the `rules."plan"` override names it); that
  command is where the team's checks, review bot and body template are enforced.

### Behavioral rules in PR mode

- Run the stay-current steps before writing code in any session. Rebase a feature branch once,
  at ship time — not every session, and not because the default branch moved.
- Each slice is built in its own worktree (`.claude/worktrees/<slug>` in the team repo), branched
  from `origin/<default>`, or from the previous slice's branch when it stacks. The team repo's
  primary checkout is never switched (**The IDE holds main**, under **Global rules**).
- Build with quick checks, verify UI by code then headless, and run the full scoped checks once
  at ship time (see **Inside a slice**). Nothing parks for the owner unless it is critical.
- One commit per lettered section; commit the plan file in **your** repo alongside, never into
  the team repo.
- Tick items with ` — done: <note>`; never delete an item; if a step is impossible as written,
  say so in the note and do the nearest correct thing without widening or narrowing scope.
- When a slice grows past the size signal, ship what is there and move the rest to the next
  slice. When a plan proposes one large PR instead, it names why a split by layer cannot work.
- In a project that works issue-first, a slice starts with `NNN issue <slice>`: the slice's issue
  is the team's view of its state, so it is current before the first commit.
- When the team's rules and this skill disagree, the team's rules win, and the plan says so.
