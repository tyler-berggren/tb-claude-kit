# TB Claude Kit

**A Claude Code harness for professional vibecoders:** people who ship real software for clients,
employers and their own products, with Claude writing most of the code.

Claude Code is a strong engine. Out of the box it is also a forgetful one. Every session starts
from zero, it stops to ask about every judgment call, it can't see the page it just changed, and
it has no idea what the last session learned the hard way. That's fine for a weekend project. It
falls apart when you're running five codebases, a client is waiting, and the plan is 40 steps long.

This kit is the harness around the engine: skills, hooks and scripts that install into any project
with one command and stay shared across all of them. Improve it once, and every project gets the
improvement at its next session.

Built and used daily by [Tyler Berggren](https://github.com/tyler-berggren) across client work,
products and personal projects. It's opinionated, and every opinion came from something that went
wrong.

---

## What it changes

| Without the harness | With it |
|---|---|
| Each session starts cold. | A **brain** (SQLite) loads focus, tasks, open questions and recent decisions into every session. A **mantra** in CLAUDE.md carries Claude's own notes to the next session: the traps, the momentum, the things nobody wrote down. |
| Long work dies when the session does. | **Plans** are numbered files in the repo. Resuming one re-reads it against the code and reports drift, instead of trusting what the last session claimed. |
| You babysit every step. | **Batches run without you.** Questions are asked once, up front. During the run Claude decides as a senior engineer would and records each call for you to overrule. Only critical issues stop it: irreversible actions, security, money, or reversing your decisions. |
| You keep asking "what next?" while a long job runs. | **Autopilot** keeps the plan moving. Each plan has a ranked `## Work ahead` queue; while a load, deploy or agent batch runs, Claude starts the next item that doesn't touch it, wakes itself every half hour when only waits remain, and stops only when everything left needs you. |
| A long session drifts into side tasks and loses the goal. | **Goal check.** Each plan carries a `## Goal` block (goal, finish line, measure, pace). At each milestone and at least daily, an agent with none of the session's context reads the plan's record and the measure, says where the time went (on the goal, supporting it, off it) and gives a verdict; the session reorders its queue by it and leads its status with it. |
| One agent, one thing at a time. | **`/swarm`** finishes a whole plan with parallel agents in isolated worktrees. Each runs on a model tier matched to its task, and every unit is reviewed before it merges. |
| "Done" means "it compiled". | **Claude checks its own work.** It inspects a real browser through the DOM, each agent gets a private headless browser, and audits cover code health, architecture drift and SEO. |
| Research means plausible-sounding guesses. | **`/research`** runs parallel agents under an anti-fabrication contract. Each one writes down what it could *not* verify. |
| Your laptop is a mess. | Secrets stay out of repos and transcripts, several Claude accounts sit side by side, and caches and worktrees get cleared before they pile up. |

---

## Quick start

```bash
# Once per machine: clone the kit and create the standard pointer
git clone https://github.com/tyler-berggren/tb-claude-kit.git ~/dev/tb-claude-kit
ln -s ~/dev/tb-claude-kit ~/.claude-kit
~/.claude-kit/scripts/kit-chrome update     # the shared Chrome that /look drives

# Once per project
cd /path/to/your/project
bash ~/.claude-kit/install.sh
```

Open the project in Claude Code. Then:

1. **Write `CLAUDE.md`.** What the project is, how to run and test it, its traps. Keep it short;
   every line loads into every session. The kit's own conventions are injected for you.
2. **Tune `.claude/kit.json`** if you need to: dev ports for `/kill`, plan and research folders,
   one-line rules per skill. Every key is optional; [`kit.example.json`](kit.example.json)
   documents all of them.
3. **Add API keys to `.mcp.json`** for the research stack (Brave, Firecrawl, Perplexity; Exa and
   Tavily sign in with OAuth).

> **Permissions.** The kit turns off Claude Code's permission prompts in VS Code, so Claude
> works without stopping to ask, and shell commands and MCP tools run without confirmation.
> That's the right call for repos you own, and the wrong one anywhere else. The setting is
> `claudeCode.initialPermissionMode` in `.vscode/settings.json`. To keep prompts in one project,
> add that file to `fork` in `kit.json` and remove the line from your copy.

---

## The loop

```
/brainstorm  →  /research  →  /plan  →  /plan N  (or /swarm N)  →  /commit
```

**Understand.** `/brainstorm` works an idea through in conversation; every decision and open
question lands in the brain as it happens. `/research` brings outside evidence, with sources.

**Plan.** `/plan` writes a phased plan grounded in the code and the brain. The open questions go
at the top, and you answer them in one round.

**Build.** `/plan N` works through the plan, re-checking it against the code first. `/swarm N`
does the same with parallel agents, and you can leave. Either way, your calls are written into a
`## Review` block in the plan file, with each item linked to its file and line.

**Autopilot.** On by default. Your one confirmation when a plan resumes approves its whole build
order, not just the next batch. The plan keeps a short ranked `## Work ahead` queue of what can run
now. While something long runs, Claude takes the top item that doesn't touch it, fanning out to
background agents in worktrees within the agent cap. For repeated pipelines (a county, a city, a
release after another) it keeps two batches of prep ahead of the cloud run, so a long run never
leaves agent slots idle. When only waits remain, a background
heartbeat wakes the session every 30 minutes (or `/loop`'s own wake-ups) to advance whatever
finished. A swarm fills idle slots from the same queue and carries on into the plan when its run
ends. Turns end with a status, never "what should we work on next?". It stops, and sends a push
notification, only when everything left is yours: a critical item, an open question, a spend or
release the plan reserves for you. Turn it off per project with `autopilot: off` (or
`autopilot: ask`, which asks before each new item) in `rules."plan"` in `.claude/kit.json`. The
rules are in [`.claude/skills/plan/autopilot.md`](.claude/skills/plan/autopilot.md).

**Goal check.** Autopilot keeps work moving; the goal check keeps it pointed at the goal. Every plan
carries a `## Goal` block: the goal in your words, the finish line, how to measure progress, and the
pace so far. At each milestone, before a new queue item when the last check is over four hours old,
and at least once a day, Claude hands the plan's record to a fresh agent that knows nothing of the
session's reasoning. It runs the measure itself, says where the time went since the last check (on
the goal, supporting it, or off it), names queue items that no longer serve the goal, and gives a
verdict: on track, drifting or stalled. Claude writes it in the plan's `## Goal checks`, reorders the
queue by it, and leads its next status with it; two drifting verdicts in a row come to you as a
question. The rules and the agent's brief are in
[`.claude/skills/plan/goal-check.md`](.claude/skills/plan/goal-check.md).

**Ship.** `/commit` and `/push`. In someone else's repo, `/plan pr` cuts the work into small
pull requests that merge the same day. Each PR body is a decision record that credits prior work
and names the people it affects.

The full workflow, including batches and team repos: [docs/workflow.md](docs/workflow.md).

---

## Skills

Twenty-three skills. Claude Code lists them in every session, so no project needs to.

**Memory**

| | |
|---|---|
| `/brain` | The knowledge base: decisions, questions, insights, tasks, milestones. Searchable, tiered by relevance, loaded into every session. `/brain mantra` rewrites Claude's notes to the next session. |
| `/brainstorm` | Think an idea through in conversation; outputs are logged as you go. `hater` mode pressure-tests an idea like a skeptical investor. |

**Planning and building**

| | |
|---|---|
| `/plan` | Phased plans in the repo, reconciled against the code on every resume. PR mode for team repos, epics and issues on the team's tracker, and handoff to another agent. [More](docs/plan-and-swarm.md) |
| `/swarm` | Finishes a plan unattended with parallel, reviewed, worktree-isolated agents, within a machine budget so your laptop stays usable. [More](docs/plan-and-swarm.md#swarm-swarm) |
| `/research` | Parallel agents across six search tools. Each writes its own sourced report, including a "could not verify" section. [More](docs/skills.md#research-system-research) |
| `/parse` | Contracts, decks, spreadsheets and scanned PDFs become markdown Claude can read. [More](docs/skills.md#document-parsing-parse) |

**Verification**

| | |
|---|---|
| `/look` | A shared Chrome that Claude inspects DOM-first, plus a private headless browser for each agent. [More](docs/skills.md#look-co-browser-look) |
| `/vibe-audit` | Health and security audit for AI-written code, with pattern tracking that gets sharper each run. |
| `/cto` | Architecture observatory: the codebase becomes Mermaid C4 diagrams, and re-runs show drift. [More](docs/skills.md#architecture-observatory-cto) |
| `/web` | SEO and AEO audit for a static site. It checks that metadata, structured data, sitemaps and llms.txt are present, correct and still current. |

**Explaining**

| | |
|---|---|
| `/wiki` | A project wiki that grows with the code; `/wiki deploy` publishes it as a searchable site. [More](docs/skills.md#wiki-wiki) |
| `/report` | A plain-language progress report for managers and clients: outcomes and measured results, never commit counts. |

**Everyday**

| | |
|---|---|
| `/commit` `/push` | Real commit messages; snapshots tracked SQLite databases (the brain included) as readable NDJSON; pushes subtrees. |
| `/kill` | Stops dev servers, watchers and browsers without touching your Claude session. |
| `/pbar` | A live progress display for any job over five minutes, including whether the process is still alive. Claude starts it on its own. |
| `/bridge` | Lets HTML artifacts read and write project files. |
| `/video-editor` | Transcript-driven video editing: transcribe, script, cut, caption. [More](docs/skills.md#video-editing-video-editor) |

**The machine**

| | |
|---|---|
| `/1password` | Secrets out of repos and transcripts: one read-only service account per vault, `.env` files converted to `op://` references. [More](docs/skills.md#secrets-1password) |
| `/claude-switcher` | Several Claude accounts on one machine, each one a VS Code profile switch away. [More](docs/skills.md#claude-switcher-claude-switcher) |
| `/cross-artifact` | Read claude.ai artifacts that were shared with your *other* Claude account, live. [More](docs/skills.md#cross-artifact-cross-artifact) |
| `/clear-cache` | Wins back disk from npm, pnpm, uv, pip, Homebrew and stale browser copies. |
| `/prune` | Reviews a repo's worktrees and removes only the ones you pick. |
| `lidsleep` | A terminal toggle for sleep-on-lid-close, so long jobs survive a closed laptop. [More](docs/skills.md#lid-sleep-lidsleep) |

---

## How it works

**One kit, many projects.** By default every kit file is a symlink into your kit checkout, kept out
of git. Change a skill once and every project has it next session. New skills are linked in
automatically at session start. If a repo has to work on a machine without the kit, install it in
*inside* mode instead, which copies real files and detects drift. [docs/install.md](docs/install.md)

**The session-start hook** does the wiring:
- links any kit files that are new since the last session;
- heals schema drift in the brain;
- loads focus, tasks, open questions and recent entries;
- lists what the previous session added, so Claude can check it against the mantra;
- injects the kit's conventions from [`.claude/KIT.md`](.claude/KIT.md), and your writing rules: named
  sets for how Claude writes in each context, kept in a repo of yours ([docs/customization.md](docs/customization.md#writing-rules)).

That last step is why kit-wide rules don't have to be copied into each project's CLAUDE.md.

**The brain** is one SQLite file per project, `cowork/brain/BRAIN.db`. It is the only copy: there
is no markdown export to fall out of date. It stays out of git; `/commit` writes its `logs`
table as NDJSON next to it, so git keeps readable diffs and a fresh clone rebuilds the DB on its
first session.

**The mantra** is the last section of CLAUDE.md, Claude's notes to the next session, about 4,000
characters at most. At each session start Claude checks it against the previous session's work
and rewrites it if something worth knowing came up. It loads with CLAUDE.md, and git is its
history.

**Compound lessons.** Before a substantive session ends, Claude asks itself whether a reusable
lesson came out of it. If one did, it's saved as a brain insight tagged `lesson`. Inspired by the
compound step in [Every's Compound Engineering](https://github.com/everyinc/compound-engineering-plugin).

**Memory in the repo.** Claude Code's auto-memory for each project moves into `.claude/memory`
and is committed, so it isn't lost with the machine. Public GitHub repos are skipped unless you
opt in.

---

## Docs

| | |
|---|---|
| [docs/workflow.md](docs/workflow.md) | The loop in depth: batches, decide-and-continue, the review block, team repos |
| [docs/install.md](docs/install.md) | Modes, automatic adoption, `.gitignore`, memory, every `kit.json` key, the brain DB, a project's layout after install |
| [docs/plan-and-swarm.md](docs/plan-and-swarm.md) | `/plan` and `/swarm` in full: PR mode, epics, model tiers, machine budget, reviews mid-run |
| [docs/skills.md](docs/skills.md) | Research, parse, look, cto, wiki, video, 1Password, Claude switcher, cross-artifact, lidsleep |
| [docs/customization.md](docs/customization.md) | Writing rules, extra MCP servers, and per-project skills worth adding |

---

## License

[MIT](LICENSE)
