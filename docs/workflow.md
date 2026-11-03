# Working with the kit

How the skills chain together, how batches run without you, and how work lands in someone else's repo.

## Recommended workflow

The skills chain in a natural sequence: **understand → plan → build**.

```
/brainstorm  →  /research  →  /plan  →  /plan N (build)  →  /commit
```

Start with `/brainstorm` to explore the problem conversationally; decisions and questions are
captured automatically. When you need outside evidence — how an API behaves, what the tradeoffs
are, what others hit — `/research` returns a sourced report.

Once the shape is clear, `/plan` generates a phased plan grounded in both the codebase and the
brain DB, so it reflects what you've already worked through. Then build. `/plan N` resumes with a
fresh-eyes reconciliation pass, re-reading the plan against the current code to catch the gap
between what was planned and what actually got built.

**Your attention goes at the start of a batch, and after it only if you want.** A batch is any
session that works down more than one item: a resumed plan or a swarm run. Before it starts, the
plan's `## Open questions` that bite it are put to you in one round, and your answers are written
into the plan. During it, nothing stops to ask you anything and nothing waits for you. Claude makes
each call as a senior developer would, builds it to work, keeps going, and records it. At a genuine
fork, where it is truly unclear which way is best, it still decides but builds lean: functional end to
end, follow-on work kept to a minimum, polish left for a later pass, so little is un-built if you
overrule it. Only a **critical** issue parks: an irreversible or outward-facing action you haven't
pre-approved, a security, privacy or permissions exposure, money, or reversing a decision you made. UI is verified by code first and a headless browser
second; what neither can check cheaply is written down as unverified, and the work moves on. Critical
parks, calls (each with the alternatives and what switching would cost) and unverified items land in
one numbered `## Review` block in the plan. Only the critical parks wait on you. An overruled call
becomes a fix item.

**Everything you are pointed to comes with its line.** Plans and research reports grow long.
So every question, review item, finding or resume point Claude hands you names its file and
line, as a link you click straight through. The number is looked up just before the message
goes out, because the file keeps changing during a session. Inside the files themselves, parts
are named by stable ids (`Q3`, review item `#4`, a slice id, a report's finding number), since
the next edit would move any line number written there.

**When the code lands in someone else's repo** — a team's, an employer's, an open-source
project's — use `/plan pr <topic>`. The build order becomes slices: one concern, one session,
one small PR that merges the same day, split by layer so users never see half a change. The next
slice's items are steps a cold coding agent can tick off, and the plan travels with each PR.
Every body opens with the goal, the summary, and every decision with its trade-offs and the
alternatives not taken. It credits the work it builds on and mentions the people whose code or
decisions it changes, from a prior-art sweep run before the body is written. Before building, `/plan NNN epic` puts the
plan on the team's tracker — the epic and, if the project publishes ahead, a sub-issue per slice
with its blocking edges — so the team sees the workstream first; `/plan NNN issue <slice>` brings
each slice's issue current as it starts. A project's `kit.json` `rules.plan` names the team's ship
command and policy, branch conventions, priority tiers, CI path map and sweep agent, and
`plan.issues` its tracker settings, so the kit stays generic.

**When the plan should complete itself,** hand it to `/swarm` instead of implementing phase by
phase:

```
/plan  →  /swarm (setup)  →  /commit  →  fresh session: /swarm (run)  →  read REPORT.md
```

Setup resolves every open question with you up front; the run session then executes the whole
plan — parallel agents where the dependency graph allows, serial where it doesn't — without
stopping to ask anything. See [Swarm](plan-and-swarm.md#swarm-swarm) in the reference.

**Not everything needs the full loop:**

- **Quick feature** — `/plan` → `/plan N` to build it → `/commit`
- **Whole plan, hands-off** — `/plan` → `/swarm` → commit → fresh session `/swarm` → read the report
- **Exploratory question** — `/brainstorm`, and you're done; insights are saved
- **Technology decision** — `/research` → `/brainstorm` the findings → decision logged
- **Bug fix** — just fix it → `/commit`

**Proposing plan changes offline.** Wrap edits in `{{double curly braces}}` directly in the plan
file, then run `/plan review`. Claude checks each one for feasibility and coherence with the rest
of the plan before applying it.

```
- [ ] **API design** — {{use GraphQL instead of REST for the query layer}}
```

**Handing a plan to another agent.** Before a session ends, or before a teammate, a cloud session
or `/swarm` picks the plan up, run `/plan handoff`. It ticks off what is done (checked against the
code, not memory), tidies the file, and writes what exists only in the current conversation into
a `## Handoff` section under the title: the user's instructions, decisions and why, dead ends,
gotchas, uncommitted or half-applied state, and open questions. Then it reads the plan cold, the
way the next agent will, and fills the gaps it finds. The next session resumes with `/plan N` as
usual and reads that section first.
