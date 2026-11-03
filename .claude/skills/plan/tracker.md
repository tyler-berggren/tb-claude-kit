## Epic Mode

Publish a PR-mode plan's workstream to the team's tracker **before building it**, so the people
it touches see the plan, its decisions and its order while they can still shape them. The unit
is the **epic** — the parent issue describing the whole workstream — and, when the project
publishes ahead (see **Issue policy**), **one sub-issue per slice**, wired together by their
blocking edges so the tracker shows the same dependency graph as the plan.

Usage: `NNN epic` publishes the first time and syncs every time after. The plan must be in PR
mode; convert it first (`NNN pr`) if it is not.

A plan may carry more than one epic's work — two workstreams sharing one build order because
they touch the same files. Each slice then names its epic, and each epic is published on its own:
its own body, its own sub-issues, its own people. Nothing about one epic appears in the other's
issues except a real dependency, stated as one.

### Step E1 — Load

Resolve, read and bind the plan as in R1, and read **Issue policy**. For each epic the plan
names, collect what already exists: the epic's issue (if any), its sub-issues from the host's
native listing, and each slice's recorded issue (the slice table's issue column, or the brain
task's `meta.issue`). **Nothing is created twice:** an issue that exists is synced (E5), never
duplicated.

### Step E2 — Sweep

Run the prior-art sweep (P1's) over the plan's areas: one run per lane or area, not one per
slice. It supplies each decision's prior record — what it builds on, changes or reverses, linked,
author named — and, for each person, the stake that earns a mention. Use the project's sweep agent
when it names one.

### Step E3 — Draft

Write every body to a file before anything is posted.

- **The epic** — P5's decision record at workstream scale: **Goal**; **Summary** in plain
  language; **Decisions**, each with why, what it gains and costs, the alternatives not taken,
  its prior record, and whose call it was; **The slices**, as a table — slice, what a user will
  see, blocked by; **Who this touches**, one `@mention` each with what changes for them; and how
  to reach the owner.
  **If the epic already exists,** its body is not where new people are told: a mention edited
  into a body is not reliably notified. Draft a **new comment** carrying the slice table and the
  mentions, and refresh the body separately without adding any.
- **Each slice** — **Goal** in a sentence or two; **What a user will see** ("nothing — plumbing"
  is an answer); the **Decisions** that bite in this slice, in the same shape; **Prior work**,
  credited by link and **by name without the @** (the epic and the slice's PR do the tagging —
  once per concern); **Blocked by**; the epic; and a status line, `Planned — not started`.
  Describe the area rather than line numbers: a planned issue is read weeks before its slice
  starts, and line numbers will have moved.
- Run the project's body check on every file, when it names one, and fix what it reports.

Titles follow the team's convention; the project override names it.

### Step E4 — Preview, then publish on the owner's word

Posting notifies people and cannot be taken back, so show it first: how many issues will be
created, updated and closed; the epic's body or comment in full; two representative slice
bodies; every person mentioned, with the reason. **Publish only on the owner's go.**

Then publish in **dependency order**, blockers first, so every blocked-by can name a real issue:

- attach each slice to its parent with the host's **native sub-issue** relationship, and add the
  host's **native blocking links** where it has them; where it has none, the body's Blocked by
  line carries the numbers;
- apply the project's assignee and labels, and **never a label the project lists as one its
  automation acts on** — a planned issue that lands in an agent queue gets built by somebody
  else;
- record each issue number in the plan's slice table and in its brain task (`meta.issue`), and
  commit the plan.

### Step E5 — Sync on every re-run

`NNN epic` after the plan changed brings the tracker back in line with it:

- a new slice gets a new sub-issue, in its place in the graph;
- a slice that has **not started**, whose one-liner, decisions or blockers changed, gets its body
  updated — with no mention added by the edit; anyone newly touched gets a comment;
- a slice merged into another, or dropped, has its issue **closed with a comment** saying where the
  work went;
- a slice that has started belongs to **Issue Mode**, and is left alone here.

Report what was created, updated and closed, with links.

---

## Issue Mode

Create, or bring current, **one** issue.

- **`NNN issue <slice>`** — the slice is about to start, or its scope just changed. Bring its
  issue current: the slice's checkable items become its acceptance criteria, its decisions and
  blockers are refreshed, and its status line becomes `In progress`. When it has no issue yet —
  the project publishes on start, or the slice was added after publishing — create it, attached
  to its epic with its blocking links, exactly as E4 does for one slice. In a project that works
  issue-first this runs before the slice's first commit.
- **`issue <topic>`** — a standalone issue: a defect found mid-work, an idea parked for later, a
  follow-up a review surfaced. The same decision record at issue scale: what, and why it matters;
  the evidence (steps to reproduce, the route, what right looks like); the prior work, credited;
  and — because no epic or PR will tag anyone for it — `@mentions` for the people with a stake.
  Attach it to an epic when one applies. With a plan bound, add it to the plan (a new slice, or a
  follow-up under *Out of Scope*) and link it both ways.

Either way: sweep the issue's area, draft to a file, run the body check, and show the body and the
mentions. **Creating an issue, or posting anything that mentions a person, waits for the owner's
go**; an agent running a plan unattended gets that go once, up front, for the issues it will
create. Refreshing the body of an issue that already exists, with no mention added, does not.

---

## Issue policy

Epic and Issue modes read the project's tracker settings from `.claude/kit.json`:

```json
{
  "plan": {
    "issues": {
      "publish": "ahead",
      "repo": "your-org/your-repo",
      "assignee": "your-login",
      "labels": ["P2"],
      "neverLabels": ["agent-queue"],
      "check": "node scripts/check-body.mjs {file} --kind {kind}",
      "sweep": "prior-art"
    }
  }
}
```

- **`publish`** — `ahead`: Epic mode publishes every slice as a sub-issue before building starts.
  `on-start` (the default): Epic mode publishes the epic alone, and each slice's issue is created
  by Issue mode when that slice starts.
- **`repo`** — the tracker's repository, when it is not the session's own.
- **`assignee`**, **`labels`** — applied to every issue created.
- **`neverLabels`** — labels the team's automation acts on (an agent queue, an auto-close rule);
  never applied by this skill.
- **`check`** — a command that lints a body file before it is posted; `{file}` and `{kind}`
  (`epic`, `issue`, `pr` or `comment`) are filled in.
- **`sweep`** — the prior-art sweep agent or script, when the project has one.

The tracker is reached through the host's CLI (`gh` for GitHub, including its sub-issue and
issue-dependency APIs). When a key is absent, the mode asks rather than guesses.
