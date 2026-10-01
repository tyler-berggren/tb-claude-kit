# TB Claude Kit

**One person, many projects, Claude Code doing most of the building.** This kit is the set of
skills, hooks and scripts that makes that work. It installs into any project with one command and
is shared across all of them, so an improvement made once shows up everywhere.

Out of the box, Claude Code forgets everything when a session ends, stops to ask about every
judgment call, can't see the page it just changed, and knows nothing about the machine it runs
on. The kit closes those gaps:

| | |
|---|---|
| **It remembers** | A SQLite brain holds decisions, open questions, tasks and lessons, and loads them into every new session. Claude keeps its own notes on the project, and its memories live in the repo. |
| **It plans, then finishes** | Plans are files in the repo, re-checked against the code on every resume. A swarm of parallel agents can complete a whole plan unattended. Your attention goes in at the start, and every call made in your absence is written down for you to overrule. |
| **It works in other people's repos** | Small pull requests that merge the same day, each one a decision record that credits prior work and names who it affects, with the plan on the team's tracker before any code. |
| **It checks its own work** | A real browser it inspects through the DOM, a private headless one for each agent, and audits for code health, architecture drift and SEO. |
| **It researches without inventing** | Parallel agents under an anti-fabrication contract, each stating what it could not verify. Local documents become markdown it can read. |
| **It explains itself** | A wiki that grows with the codebase and publishes as a searchable site. |
| **It looks after the machine** | Secrets kept out of repos and transcripts, several Claude accounts side by side, and caches, worktrees and Chrome copies kept from piling up. |

Developed through ongoing trial and error by [Tyler Berggren](https://github.com/tyler-berggren).

---

## Quick start

```bash
# 1. Clone the kit and create the standard pointer (once per machine)
git clone https://github.com/tyler-berggren/tb-claude-kit.git ~/dev/tb-claude-kit
ln -s ~/dev/tb-claude-kit ~/.claude-kit
~/.claude-kit/scripts/kit-chrome update   # one shared Chrome for /look (see "One Chrome for every project")

# 2. Install into any project
cd /path/to/your/project
bash ~/.claude-kit/install.sh
```

That's it. Open the project in Claude Code and the skills are available.

**Then:**

1. Edit `CLAUDE.md` — describe your project
2. Edit `.claude/kit.json` — dev ports for `/kill`, plan/research directories, per-skill rules
   (see [`kit.example.json`](kit.example.json) for every supported key)
3. Edit `.mcp.json` — API keys for Brave, Firecrawl, Perplexity (Exa and Tavily use OAuth)
4. Edit `cowork/vibe-audit/GUARDRAILS.md` and `cowork/architecture/seed.sql` — describe your
   architecture so `/vibe-audit` and `/cto` know what they're looking at

> **A note on permissions.** This kit ships with Claude Code's permission prompts bypassed in VS
> Code, so Claude can work without stopping to ask. That means tool calls — including shell
> commands and the pre-configured MCP servers — execute without confirmation. It's a reasonable
> default for a repo you own and trust, and a bad one otherwise. The setting is
> `claudeCode.initialPermissionMode` in `.vscode/settings.json`, a file the kit manages. To
> restore prompting in one project, add `.vscode/settings.json` to `fork` in `.claude/kit.json`
> and keep your own copy without that line.

---

## The skills

Twenty-one skills, grouped by what they do for you. The bigger ones link to their section in the
[Reference](#reference).

**Remembering — so context accumulates instead of resetting**

| | |
|---|---|
| `/brain` | The knowledge base. Decisions, open questions, insights, tasks, milestones — queryable, tiered by relevance, and loaded into every new session automatically. |
| `/brainstorm` | Think an idea through conversationally. Decisions and questions that emerge are captured as you go, not reconstructed afterwards. Includes a `hater` mode that pressure-tests an idea like a skeptical investor would. |

**Planning and building — so work survives being interrupted, and finishes without you**

| | |
|---|---|
| `/plan` | Phased plans that live in the repo as markdown. Resuming re-reads the plan against the current code and reports drift, rather than trusting what the last session claimed. PR mode cuts work for a team repo into small pull requests that merge the same day. [More](#plan-plan) |
| `/swarm` | Completes an entire plan unattended. Parallel agents in isolated worktrees, each on a model tier matched to its task, every unit reviewed before it merges, and every call made in your absence written down for you. [More](#swarm-swarm) |
| `/research` | Parallel agents across a six-tool search stack. Each writes its own sourced report with a mandatory "what I could not verify" section; the orchestrator only synthesizes. [More](#research-system-research) |
| `/parse` | Local documents — contracts, decks, spreadsheets, scanned PDFs — converted to markdown Claude can actually read. Point it at a file, a glob, or a directory; the `.md` lands beside the original. [More](#document-parsing-parse) |

**Checking — so Claude can verify its own work**

| | |
|---|---|
| `/look` | A shared Chrome window Claude inspects DOM-first — computed styles, box models, console logs — then confirms a visual change by actually looking at it. A **headless** mode gives each coding agent a private browser to click through a page without ever touching yours. [More](#look-co-browser-look) |
| `/vibe-audit` | Health and security audit tuned for vibe-engineered code, with Bayesian pattern tracking that gets more precise each run. |
| `/cto` | Architecture observatory. Scans the codebase into a SQLite model and generates an HTML document with Mermaid C4 diagrams. Re-running shows what drifted. [More](#architecture-observatory-cto) |
| `/web` | SEO/AEO audit for a static site. Checks metadata, structured data, sitemap, robots, and llms.txt are present and correct — then checks they are still *current*, catching sitemaps with stale lastmod, markdown mirrors that drifted from their pages, and FAQ schema answering questions the page no longer asks. |

**Explaining — so the project documents itself**

| | |
|---|---|
| `/wiki` | A project wiki that grows with the codebase: every run updates what just changed and scans for what is stale or missing. `/wiki deploy` publishes it to Cloudflare Pages as a searchable site. [More](#wiki-wiki) |

**Everyday — the small stuff, done consistently**

| | |
|---|---|
| `/commit` `/push` | Stage, write a real commit message, push. Regenerates SQLite NDJSON sidecars if configured, and `sub <name>` pushes a subtree to its own repo. |
| `/kill` | Kill dev servers, watchers, and browser instances without touching your Claude session. |
| `/pbar` | A live progress display for a job that will run for a while. Hands you one path to paste into any terminal: a bar per stage, an ETA from measured throughput, and — the part a bar alone can never tell you — whether the process is still alive. Read-only, so stopping it cannot disturb the job. Claude runs it on its own whenever it starts a job that may take 5+ minutes. |
| `/bridge` | A local server that lets HTML artifacts read and write real project files. |
| `/video-editor` | Transcript-driven video editing — transcribe, review a script, then cut, fade and caption. [More](#video-editing-video-editor) |

**The machine — these work on the whole computer, not one project**

| | |
|---|---|
| `/1password` | Secrets out of your repo and your transcripts. Bootstraps one read-only service account per vault, converts plaintext `.env` files to `op://` references, verifies resolution, and diagnoses failures. [More](#secrets-1password) |
| `/claude-switcher` | Several Claude accounts on one machine — a personal plan and an employer's, or a second account for when the first runs out — each one a VS Code profile switch away. Shows who is signed in where and what is off; `add <name>` sets up a new one. [More](#claude-switcher-claude-switcher) |
| `/clear-cache` | Win back disk space from the caches every project shares: npm, pnpm, uv, pip, Homebrew, and extra copies of Chrome and Playwright browsers. Shows sizes before and after. `report` changes nothing; `deep` also offers npx packages, Docker build cache, and `node_modules` in projects you haven't touched in a month. |
| `/prune` | Review a repo's worktrees and clean up the ones you're done with. Each gets a plain-words verdict: **remove** (merged, or its folder is already gone), **ask** (PR closed without merging, or untouched for two weeks) or **keep** (uncommitted or unpushed work, an open PR, something running in it). Nothing is removed until you pick, never with `--force`, and remote branches are never touched. `report` changes nothing. |

---

## How it works

The **brain DB** is the connective tissue. `/brainstorm` writes decisions and questions into it.
`/research` indexes reports in it. `/plan` reads from it. `/swarm` registers its execution state
in it — which is how a fresh session knows whether to set a swarm up or run one. Session hooks
load the current state on startup, so a fresh Claude opens already knowing where things stand.

Everything else is a file in your repo, readable by a human or a future session:

- **Plans** are numbered, dated markdown — `cowork/plans/001_2026-06-20_auth-redesign.md`. A plan with
  companions becomes a directory of the same name; a narrower plan carved out of one is `001a_…` inside it
- **Research runs** are numbered, dated *folders* —
  `cowork/research/002_2026-06-22_oauth-providers/` holding each agent's report plus a synthesized
  `SUMMARY.md`

Both sit alongside your code, so anyone can read why something was built the way it was.

### The mantra

Claude maintains its own notes about your project — the non-obvious patterns, the tricky areas,
the working assumptions that `CLAUDE.md` doesn't cover. It reviews and updates them on session
start, unprompted. This is the part people tend to underestimate: it's Claude telling the next
Claude what actually matters.

### Compound lessons

At the end of substantive sessions, Claude considers whether a reusable lesson emerged. If one
did, it's written as a brain insight tagged `lesson` — the rule, why it matters, how to apply it.
If nothing novel happened, the step is skipped. Over time these accumulate into a searchable
catalog of what to do differently next time.

Inspired by the "compound step" from
[Every Inc's Compound Engineering](https://github.com/everyinc/compound-engineering-plugin).

---

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
stopping to ask anything. See [Swarm](#swarm-swarm) in the reference.

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

---

## Two ways to install

The kit can either **travel with your repo** or **live outside it**. This is the main thing to
understand before adopting it across several projects.

| | **outside repo** (default) | **inside repo** |
|---|---|---|
| Kit files are | symlinks into `~/.claude-kit` | real files in your project |
| Git | meant to stay out of git — the installer prints the `.gitignore` lines, and [never writes them](#gitignore-is-yours) | tracked — travel with the repo |
| Updating | instant; edit the kit once, every project sees it. New kit files are [adopted on next session start](#automatic-adoption-of-new-kit-files) | re-run `install.sh`, with drift detection |
| Needs the kit present? | yes | only for the kit's own scripts in `~/.claude-kit/scripts/` (`oprun`, `sqlite-sidecar.sh`, `kit-chrome`, `claude-switcher`) |

**Choose with one question: does a machine without your kit checkout need this repo to work?**
If yes — a repo you hand to someone else, a cloud session, CI — use `inside`. Otherwise `outside`,
and stop thinking about propagation entirely.

```bash
bash ~/.claude-kit/install.sh                  # uses the mode in kit.json (default: outside)
bash ~/.claude-kit/install.sh --mode inside    # convert to vendored files
bash ~/.claude-kit/install.sh --mode outside   # convert back to symlinks
bash ~/.claude-kit/install.sh --dry-run        # report what would change, touch nothing
bash ~/.claude-kit/install.sh --yes            # auto-update drifted files, enable integrations
bash ~/.claude-kit/install.sh --replace        # outside mode: replace occupied paths with links (commit first)
bash ~/.claude-kit/install.sh --help
```

**Optional integrations.** An interactive run offers three: the Exa and Brave Search MCP servers
(it asks for the Brave key) and the Cloudflare plugin with its MCP servers. Saying yes adds
entries to `.mcp.json` and `.claude/settings.json`. With `--yes`, or when no one is at the
keyboard (an agent running it), all three are enabled without asking and drifted files are
reported with their diffs, not updated.

Conversion is lossless in both directions.

**Adopting an existing project.** Paths already holding real files are reported as `[occupied]`
and left alone — the installer never silently deletes your work. Content that's byte-identical to
the kit converts automatically. For anything that genuinely differs, either add it to `fork` (see
below) or commit it and re-run with `--replace`.

**On another machine.** Clone the kit anywhere, run `ln -s <path> ~/.claude-kit`, then
`bash ~/.claude-kit/install.sh` in each project. Nothing in any repo hardcodes a checkout location.
The installer finds the kit by `$TB_CLAUDE_KIT`, then `kitPath` in `kit.json`, then `~/.claude-kit`,
then the folder the script itself is in.

### Automatic adoption of new kit files

In outside mode, kit files are symlinks — so editing a skill in the kit is live everywhere
immediately. What never followed automatically was a *new* file: a skill that didn't exist when
you last installed needs a symlink and a `.gitignore` line, which meant re-running `install.sh`
in every project each time the kit grew.

The session-start hook now does that itself. On every session it compares the project against the
kit and links anything missing, and adds the new path to the kit's managed `.gitignore` block when
the project has one (see below). New skills are usable in the session that adopts them, and you're
told what happened:

```
🧰 Kit sync: linked .claude/skills/parse and updated .gitignore. Available this session.
```

It finds the kit without any configuration: in outside mode the hook is *itself* a symlink into
the kit, so it resolves its own path. No `$TB_CLAUDE_KIT`, no `kitPath`, nothing to keep in sync.
The list of what to adopt comes from `.claude/kit-manifest.txt`, which `install.sh` publishes on
every run so both sides work from one list.

**It only ever adds.** A symlink whose target disappeared upstream is reported, never deleted —
the hook can't tell "removed from the kit" from "checkout mid-rebase" or "external volume not
mounted", and deleting on an ambiguous signal is how you lose work. Removal is yours to do by
hand: delete the dangling link. `install.sh` never removes anything either; it reports leftovers.
The hook also heals a kit link that's missing its line in the managed `.gitignore` block, the
drift that otherwise shows up as a mystery untracked file.

It stays out of the way where it should: `fork` and `exclude` are honored, forked paths are never
given an ignore line, inside-mode projects are skipped entirely (their hook is a real file, so it
self-disables), and a missing or unparseable `kit.json` makes it bail rather than guess.

Re-running `install.sh` is still what you want for converting modes, updating project-owned
scaffolding, and drift detection.

### `.gitignore` is yours

`install.sh` never writes `.gitignore`. It used to, and one project found seventeen tracked skill
paths silently dropped from its index by an installer it ran to add one skill. Whether kit links
belong in git is a project decision, so the installer prints the lines an outside-mode project
needs and leaves the file alone.

To have the hook keep them current, put those lines between two marker lines,
`# BEGIN:tb-claude-kit` and `# END:tb-claude-kit`. From then on every newly adopted kit file gets
its line added inside that block. Without the block, a newly linked skill shows up as an
untracked file until you ignore it.

### Claude's memories live in the repo

Claude Code's auto-memory normally sits in the machine's config folder
(`~/.claude/projects/<path>/memory/`), in no repo, so it is lost with the machine and never
reaches your other machines. The kit keeps it in the project instead, at **`.claude/memory/`**,
committed and pushed with everything else:

- **The setting.** `.claude/settings.local.json` gets `autoMemoryDirectory`, pointing at that
  folder. That file is per machine and ignored by git. Claude Code honours the key there for a
  trusted project, and ignores it in the checked-in `settings.json`.
- **The migration.** Memories already in the config folder are copied across without overwriting
  anything. The old folder is kept, renamed `memory.moved-<time>`, beside a link to the new one.
  The config folder is `$CLAUDE_CONFIG_DIR` when you route accounts per folder, and `~/.claude`
  otherwise.
- **When it runs.** `install.sh` sets it up in both modes. The session-start hook adopts it for an
  outside-mode project on its next session and tells you in one line:
  `🧠 Memory: moved 12 memories into .claude/memory — commit them.` When everything is already
  in place it costs a few milliseconds and says nothing.
- **Public repos are left alone.** Memories hold personal notes, so when the repo's origin is a
  **public** GitHub repo, the kit sets nothing up and says why. It checks once, through `gh`, with
  a 5-second limit; if `gh` is missing or cannot answer, the repo is treated as not public. Opt in
  with `"memory": { "inRepo": true }`.
- **Turning it off.** Set `"memory": { "inRepo": false }`. That stops enforcing it and never undoes
  a setup; `install.sh` says what to remove by hand.
- **Cases it skips:**
  - a linked worktree, which shares its main checkout's memory;
  - a tracked `settings.local.json`, since it would carry this machine's path;
  - an inside-mode repo at session start (a collaborator's session should not move their memories
    into a shared repo — `install.sh` is the explicit way).

---

## Configuration — `.claude/kit.json`

One file per project holds both its mode and its customizations. Every key is optional; skills
fall back to sensible defaults when the file or a key is missing. See
[`kit.example.json`](kit.example.json) for the annotated full reference.

```json
{
  "kitVersion": 1,
  "mode": "outside",
  "fork": [],
  "exclude": [],

  "kill": {
    "ports": [3000, 5173, 8787],
    "portRanges": [[9615, 9634]],
    "patterns": ["my-custom-watcher"],
    "scopeToProjectPath": true
  },
  "commit": { "author": "Jane Dev <jane@example.com>" },
  "plan":     { "roots": ["cowork/plans", "cowork/projects/*/plans"],
                "issues": { "publish": "ahead", "assignee": "jane-dev", "neverLabels": ["agent-queue"] } },
  "research": { "roots": ["cowork/research"] },
  "swarm":    { "maxAgents": 6, "checks": ["npm run check"] },
  "memory":   { "inRepo": null },

  "rules": {
    "push": "If the post-commit hook reports undeployed changes, ask before pushing."
  }
}
```

Other keys are documented with the skill that reads them: `plan.issues` under [Plan](#plan-plan),
`swarm.*` under [Swarm](#swarm-swarm), `wiki.*` under [Wiki](#wiki-wiki), `secrets` under
[Secrets](#secrets-1password). Smaller ones:

- **`clearCache`** — `projectRoots` (where your projects live, default `~/dev`) and `staleDays`
  (default 30), for `/clear-cache`'s deep tier.
- **`prune`** — `staleDays` (default 14) and `keep` (branch-name globs `/prune` never offers to remove).
- **`web`** — `roots` (where the built site is), `baseUrl` (the canonical origin) and `ignore`, for `/web`.
- **`subtrees`** — `{ "<name>": { "prefix": "app", "remote": "app", "branch": "main" } }`. With it,
  `/commit sub <name>` and `/push sub <name>` push that folder to its own repo after committing.
- **`kitPath`** — where this project's kit checkout is, when it is not `~/.claude-kit`.

### `sqlite_tracking` — Git-friendly SQLite change tracking

Track changes to SQLite databases through git using the [AirSQLite](https://github.com/AirSQLite/AirSQLite) sidecar layout — a `{dbname}.airsqlite/` folder next to each `.db` file containing per-table snapshot files. One JSON line per row (including `_rowid`), sorted by rowid. Git tracks lines, not binary blobs, so each row change produces a clean, readable diff. The format is compatible with the AirSQLite VS Code/Cursor extension, which can read these snapshots for between-session reconciliation.

```json
{
  "sqlite_tracking": [
    {
      "db": "cowork/prospecting/PROSPECTS.db",
      "tables": ["prospects", "rejected", "contact_attempts"]
    }
  ]
}
```

- **`db`** — path to the `.db` file (relative to project root)
- **`tables`** — which tables to track (omit to track all non-internal tables)
- **`exclude`** — table-name globs to leave out, such as `["logs_fts*"]`

Sidecars are regenerated by `/commit` before staging, so `git add -A` picks them up naturally. Not a git hook — hooks don't clone, and a stale sidecar fails silently.

**Layout on disk:**
```
PROSPECTS.db
PROSPECTS.airsqlite/
  prospects.snapshot.ndjson
  rejected.snapshot.ndjson
  contact_attempts.snapshot.ndjson
```

**What it buys:**
- `git log -p -- PROSPECTS.airsqlite/prospects.snapshot.ndjson` — what each run found, what changed
- `git blame PROSPECTS.airsqlite/prospects.snapshot.ndjson` — when each record entered and which run found it
- Enrichment passes land as their own commits, so "where did this data come from" is answerable
- Compatible with AirSQLite's sidecar system — snapshots are readable by the extension for reconciliation

**When it fits:** tiny databases (hundreds to low thousands of rows), batch writes (1-3x/week), append-dominant patterns. The sidecar adds ~12% repo size overhead — negligible at this scale.

The script behind it, `~/.claude-kit/scripts/sqlite-sidecar.sh`, can also be run directly outside of `/commit`. It needs `jq`.

### `fork` vs `exclude`

Easy to confuse, and they do opposite things:

- **`fork`** — the path exists here and **your project owns it**. The kit never links, copies, or
  gitignores it. Use it when you need genuinely different behavior from the kit's version.
- **`exclude`** — the path **has no business existing here at all**. Never installed, in either
  mode. Use it to install a subset — say, a repo for a non-technical collaborator that shouldn't
  carry developer tooling. Excluding doesn't delete what's already there; the installer reports
  leftovers so removal stays deliberate.

### Where project-specific behavior belongs

In order of preference — reach for the first one that fits:

1. **A value** → `kit.json` (dev ports, commit author, plan directories)
2. **A short rule** → `kit.json` `rules.<skill>`, applied whenever that skill runs
3. **A procedure** → a project-owned skill with its own name, sitting alongside the kit's, or a
   project-owned subagent in `.claude/agents/` that a kit skill's rule points at (for example,
   the prior-art sweep `/plan`'s PR mode runs before a body is written). The installer never
   touches your own skills or agents.
4. **`fork`** → last resort, when the kit's own behavior has to change

The ordering matters: JSON keeps overrides deliberately small, and a rule that won't fit
comfortably in a string is usually a sign it belongs in its own skill — or upstream in the kit.

---

## What's in a project after install

```
.claude/
  kit.json            # mode + configuration (yours)
  skills/             # kit skills, plus any you add
  agents/             # kit agent definitions (the /swarm tiers), plus any you add
  hooks/              # session-start: loads brain state, heals schema drift
                      # background-pbar: nudges /pbar after background Bash calls
  settings.json       # model (pinned to Opus with 1M context), permissions, hooks (yours)
  settings.local.json # this machine only: points Claude's memory at .claude/memory (yours, not in git)
  memory/             # Claude's memories for this project, committed with it
.vscode/              # settings.json, extensions.json — kit-managed (permission mode lives here)
cowork/
  brain/
    BRAIN.db          # knowledge base (SQLite + FTS5)
    BRAIN.md          # auto-generated readable export
    MANTRA.md         # Claude's self-authored context
  plans/              # NNN_YYYY-MM-DD_topic.md
  research/           # NNN_YYYY-MM-DD_topic/ — agent-*.md + SUMMARY.md
  swarm/              # <plan_id>/ — SWARM.md + REPORT.md per swarmed plan (created by /swarm)
  architecture/       # CTO.db, generated architecture.html, dated summaries
  vibe-audit/         # VIBE-AUDIT.db, GUARDRAILS.md (yours)
  video/              # transcripts, scripts, caption-dictionary.json (yours)
wiki/                 # organic project documentation (yours, maintained by /wiki)
  README.md           # table of contents
  STYLE.md            # writing guide (yours — controls voice, audience, conventions)
scripts/
  wiki-build/         # static-site builder used by /wiki deploy (linked from the kit)
  puppeteer-server.cjs, artifact-bridge.cjs   # /look co-browser, /bridge server
CLAUDE.md             # project documentation + mantra block (yours)
.mcp.json             # research MCP servers (yours — holds API keys)
```

Files marked *(yours)* are created once and never replaced. A later install may add a hook, a
permission or an MCP server entry to `settings.json` and `.mcp.json`; it leaves the rest of them
alone. Everything else is kit-managed.

### The brain DB

SQLite with FTS5 full-text search at `cowork/brain/BRAIN.db`.

**Entry types** — `note`, `decision` (permanent; supersede rather than edit), `question`,
`insight`, `task`, `milestone`.

**Tiers**, computed rather than set by hand:

- **hot** — focus items and plan-linked tasks with momentum
- **warm** — importance ≥ 6, or created in the last 14 days
- **cold** — everything else still active
- **archived** — done, dropped, superseded, or importance set to 0

Four more tables (`swarm_runs`, `swarm_units`, `swarm_unit_events`, `swarm_holds`) hold `/swarm`
execution state. `/swarm` adds any that are missing on its first run — see
[Swarm](#swarm-swarm).

---

# Reference

Everything below is detail for when you need it — skip it on a first read.

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
choose. See [Recommended workflow](#recommended-workflow) for the full rule.

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

The tier definitions reach existing projects through [automatic adoption](#automatic-adoption-of-new-kit-files).
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

## Research System (`/research`)

The research skill runs deep, multi-agent web research with a 6-tool stack. Each research run produces a numbered folder in `cowork/research/` containing individual subagent reports and an orchestrator-written synthesis. `research.roots` in `kit.json` names more directories, and `/research for:<scope> <topic>` files a run under one of them.

### Architecture

```
/research "topic"
  → Check prior research and the brain; propose a depth and 3-5 angles; wait for your go
  → Scout pass (Perplexity orientation, deep dives only) — citations spot-checked before use
  → Decompose into 3-5 research angles
  → Spawn parallel subagents (one per angle, each under the anti-fabrication contract)
  → Each agent searches, extracts, writes its own report + "What I Could NOT Verify"
  → Orchestrator reads all reports, writes SUMMARY.md
  → Supersede any brain entries the findings overturned; append to the project's SOURCE-NOTES.md
```

**Key design principles:**

- **Angle-based, not tool-based.** Each subagent gets a research *question* and the full tool stack. The agent picks the right tools for its question — not the other way around.
- **Subagents write their own reports.** Each agent writes directly to `agent-{label}.md` in the run folder. The orchestrator never rewrites agent findings — it only writes `SUMMARY.md` as a synthesis layer. This prevents "silent consensus hallucination" (the orchestrator inventing positions no agent actually found) and preserves the raw research for drill-down.
- **Cost-aware extraction cascade.** For getting content from URLs, agents follow: WebFetch (free) → Tavily extract (free tier) → Firecrawl (paid credits). Firecrawl is reserved for pages that genuinely need JS rendering or structured extraction.
- **Anti-fabrication contract.** Every agent prompt carries a verbatim rule: retrieved URLs for every specific claim, no reconstruction from memory, a required "What I Could NOT Verify" section, and absence of evidence reported as a finding. This is what catches invented citations, misremembered figures, and numbers that secondary sources have quietly corrupted — including the pre-synthesized scout's own output, whose citations are spot-checked before anything it says is carried forward.
- **Pointed at the line.** A run leaves a long `SUMMARY.md` and a report per agent. So whenever Claude mentions part of one to you — a finding, a contradiction between agents, an open question, a recommended action, a passage of earlier research — it gives the file and line as a link you click straight through, looked up just before the message goes out. Inside the reports, one points at another by file and finding number instead, since a later edit would move any line written there.
- **Accumulating source knowledge.** `SOURCE-NOTES.md` records what blocked, what worked around it, which source types proved unexpectedly primary, and which content classes wasted searches. There are two: a curated baseline that ships with the skill and is never written to, and the project's own at `<research root>/SOURCE-NOTES.md`, which each run appends to. Agents read them before searching. Research gets cheaper over time instead of rediscovering the same dead ends.

### Tool Stack

The skill uses 6 search/extraction tools, each filling a distinct niche (plus Claude Code's built-in WebSearch and `gh search`):

| Tool | Type | Role | Best For |
|---|---|---|---|
| **Brave Search** | MCP (stdio) | Keyword discovery | Reddit, HN, forums, community content, news. Broadest independent index (30B+ pages). |
| **Exa** | MCP (HTTP/OAuth) | Semantic discovery | Conceptual queries, finding related work, "how do people think about X." Neural search finds what keywords miss. |
| **Tavily** | MCP (HTTP/OAuth) | Fast agent-native search | Quick factual lookups (187ms avg latency), clean agent-ready responses. Also provides page extraction. |
| **Perplexity** | MCP (stdio) | Scout/orientation | Pre-synthesized answers with citations. Orients on terminology and landscape — **not a source of findings**; its citations are spot-checked before use. |
| **Firecrawl** | MCP (stdio) | Deep extraction | JS-rendered pages, cookie banners, structured schema extraction, site crawling. The only tool that replaces WebFetch for complex pages. |
| **WebFetch** | Built-in | Fallback extraction | Simple/static pages. Free, fast, always available. First choice in the extraction cascade. |

### Tool Selection Guide

Agents pick the **mode** first, then the tool. Most tool-selection mistakes come from treating every query as "search" when these are four different jobs:

- **Discovery** (you don't know what exists) → **Exa** for concepts, **Brave** for practitioner reality. Reach for Exa after 2-3 empty keyword queries, not as a last resort — it finds what keyword search structurally cannot.
- **Targeted retrieval** (you know what and roughly where) → **WebSearch/Brave with `allowed_domains`**, or a direct URL + **WebFetch**.
- **Rescue** (something blocked you) → **Tavily extract**, then **Firecrawl**, then `pdftotext` for PDFs that extract badly.
- **Verification** (you have a claim and need to know if it's true) → fetch the **primary artifact** directly. Never verify a claim against a second secondary source.

### Research Depth Levels

| Depth | When | Agents | Tool Usage |
|---|---|---|---|
| **Quick lookup** | Narrow factual question, pricing, API behavior | 1 (or direct search) | Minimal |
| **Standard** | Technology evaluation, comparison, how-to | 3 parallel | Full stack |
| **Deep dive** | Strategic analysis, competitive landscape, architecture decision | Scout + 4-5 parallel + follow-up | Full stack + iterative deepening |

### Output Structure

```
cowork/research/005_2026-07-10_ai-research-methodology/
  agent-scout.md              # Perplexity orientation (deep dives)
  agent-architectures.md      # Subagent report (written by agent)
  agent-community.md          # Subagent report (written by agent)
  agent-pricing.md            # Subagent report (written by agent)
  agent-alternatives.md       # Subagent report (written by agent)
  SUMMARY.md                  # Orchestrator synthesis (the main deliverable)
```

### Anti-Hallucination Measures

The synthesis step is the primary failure point in multi-agent research. The skill encodes specific defenses:

- **Verbatim anchoring** — preserve specific numbers, quotes, and data points from agent reports
- **Conflict flagging** — when agents disagree, flag it explicitly rather than silently picking one version
- **Minority preservation** — findings from a single agent are kept, not dropped because the majority didn't mention them
- **Confidence signaling** — facts stated as facts, consensus qualified, contested claims flagged, inferences labeled
- **Gap reporting** — what was NOT found is noted alongside what was

### Pricing & Free Tiers

| Tool | Free Tier | Paid | Recommendation |
|---|---|---|---|
| **Brave Search** | 2,000 queries/mo | $5/1K queries | Stay free |
| **Exa** | 1,000 searches/mo | $5-7/1K | Stay free |
| **Tavily** | 1,000 credits/mo | $0.008/credit | Stay free |
| **Perplexity** | None | ~$5-15/1K requests | Pay-as-you-go (1 call per deep-dive run) |
| **Firecrawl** | 500 credits/mo | $16/mo (3,000 credits) | Consider Hobby tier |

Firecrawl is the only tool worth upgrading — its free tier is tight (500 credits/mo) and it's the only tool that handles JS-rendered pages. The extraction cascade (WebFetch → Tavily → Firecrawl) minimizes credit burn.

### Setup

All 5 MCP servers are pre-configured in the `.mcp.json` a fresh install creates. A project that already had one is only offered Exa and Brave; add the others by hand. After installing the kit:

1. **Brave Search** — get a free API key at https://brave.com/search/api/ and add it to `.mcp.json`
2. **Exa** — no key needed. Uses OAuth via HTTP transport (authenticates on first use)
3. **Tavily** — no key needed. Uses OAuth via HTTP transport (authenticates on first use)
4. **Firecrawl** — sign up at https://firecrawl.dev, get API key, add to `.mcp.json`. Leave the `FIRECRAWL_API_URL` alongside it in place — [`/parse`](#document-parsing-parse) needs it
5. **Perplexity** — sign up at https://perplexity.ai, get API key from settings, add to `.mcp.json`

The skill works with any subset of these tools — it gracefully adapts when tools are missing. But the full stack gives the best results: keyword search (Brave) + semantic search (Exa) + fast lookup (Tavily) + orientation (Perplexity) + deep extraction (Firecrawl) + free fallback (WebFetch).

## Document Parsing (`/parse`)

Research reaches the public web. `/parse` handles the other half — the documents
already on your disk that no URL points at. Signed contracts, slide decks,
exported spreadsheets, scanned PDFs: the files that carry the actual terms of
your work and that Claude otherwise cannot open.

It wraps Firecrawl's `/v2/parse` endpoint, the local-file counterpart to the
`/scrape` used by `/research`.

```
/parse contracts/msa.docx                 # one file → msa.md beside it
/parse ~/Downloads/kickoff-docs           # every supported file directly in a directory
/parse decks/*.pptx --out notes/          # glob, outputs collected elsewhere
/parse scan.pdf --pages 20 --stdout       # first 20 pages, printed not written
```

**Supported:** PDF, Word (`.docx .doc .docm`), OpenDocument, RTF, Excel,
PowerPoint, EPUB, CSV, HTML.

| Flag | Effect |
|---|---|
| `--formats` | `markdown` (default), `html`, `rawHtml`, `links`, `images`, `summary`, `json` |
| `--out <dir>` | Collect outputs in one directory instead of beside the originals |
| `--stdout` | Print into the conversation, write nothing |
| `--redact` | Strip personally identifiable information from the returned content |
| `--pages <n>` | Cap PDF parsing at N pages |

### Setup

Needs the same Firecrawl API key as `/research` — keyless mode does not cover
parse. The skill looks for it in `$FIRECRAWL_API_KEY`, `.env`, `.mcp.json`, then
`~/.claude.json`, and never prints it.

One non-obvious requirement: **`FIRECRAWL_API_URL` must be set** or the MCP
server's `firecrawl_parse` throws `requires FIRECRAWL_API_URL to be set to a
self-hosted Firecrawl API instance`. Despite the message, self-hosting is not
required — the handler only checks that the variable is non-empty, then reads
your file and posts it to whatever URL it names. The kit's `.mcp.json` sets it
to `https://api.firecrawl.dev`, which satisfies the check and routes to the
cloud API. Projects installed before this was added need the variable added by
hand; MCP servers only pick it up on session restart, and the skill falls back
to a direct `curl` against the REST endpoint until then.

### Output

Parsed markdown lands as `<name>.md` beside its source (`msa.docx` becomes `msa.md`), originals untouched,
existing `.md` files never overwritten silently. The skill reports what it wrote
and then spot-checks the result rather than declaring success — tables are where
docx and PDF conversion actually degrades, multi-column PDFs can interleave, and
page furniture tends to land mid-document. Set `rules.parse` in `.claude/kit.json`
if a project files parsed documents somewhere specific.

**Limits:** 50 MB per file, one file per request, credits consumed per file.
Parsing uploads the file to Firecrawl's API — the skill says so before the first
request when the documents are confidential, and offers `--redact` for PII.

## "Look" Co-Browser (`/look`)

A shared Chrome viewport that Claude can inspect programmatically while you see the same browser window. You drive — navigating pages, setting mobile viewports via Chrome's device toolbar. Claude inspects — reading computed styles, DOM structure, and box models through a local HTTP API.

Supports **multiple concurrent instances** — run separate Chrome windows for different projects on the same machine, each with its own profile, port, and cookie/storage isolation.

### How it works

The co-browser is a Puppeteer server (`scripts/puppeteer-server.cjs`) that launches a headed Chrome instance and exposes an HTTP API. Claude uses the `/look` skill to query this API with `curl` commands — no MCP server or browser extension needed.

Each instance self-registers in `~/.claude-chrome-registry.json` with its profile name, port, and PID. The `/look` skill reads this registry to find the right instance for the current project.

```
You (Chrome window)          Claude (terminal)
    │                            │
    ├── navigate, scroll,        ├── read registry → resolve port
    │   set mobile viewport      │
    │                            ├── curl :PORT/status
    │                            ├── curl :PORT -d '{"command":"inspect","selector":".nav"}'
    │                            ├── edit source file
    │                            ├── (hot reload)
    │                            └── curl :PORT -d '{"command":"inspect","selector":".nav"}'
    │                                 └── verify fix
```

### Starting the co-browser

`/look` starts the co-browser itself when none is running, and `/look <URL>` opens that page. You can also launch it by hand, or build a `/dev` skill (see Customization) that starts your dev server and the co-browser together:

```bash
# Launch with a starting URL — profile auto-names from cwd basename
node scripts/puppeteer-server.cjs http://localhost:3000

# Launch without a URL — navigate manually in the Chrome window
node scripts/puppeteer-server.cjs

# Explicit profile name (useful for monorepos or shared directories)
node scripts/puppeteer-server.cjs --profile my-project http://localhost:3000

# Preferred port (falls back to the first free one in 9615-9634 if it is busy)
node scripts/puppeteer-server.cjs --port 9620 http://localhost:3000
```

Each instance gets its own Chrome user data directory at `~/.claude-chrome/<profile>/` — fully isolated cookies, storage, and extensions per project.

### One Chrome for every project

Each Puppeteer release pins its own Chrome build and downloads it on `npm install`. So every
project, and every Puppeteer upgrade, used to add another ~500 MB copy of Chrome to
`~/.cache/puppeteer`. One machine collected ten. Once `kit-chrome update` has run, the co-browser
launches **one shared Chrome for Testing**, whatever version a project's Puppeteer pins. Puppeteer drives any recent
Chrome; the pin only decides what it downloads.

```bash
~/.claude-kit/scripts/kit-chrome           # which Chrome is shared, and any other copies taking up space
~/.claude-kit/scripts/kit-chrome update    # move to the current stable Chrome and remove every other copy
~/.claude-kit/scripts/kit-chrome prune     # remove every copy except the shared one (/clear-cache runs this)
~/.claude-kit/scripts/kit-chrome path      # print the shared Chrome's executable
```

`update` points `~/.cache/claude-kit/chrome` at the shared version, and adds a marked block to
`~/.zshenv` with two settings. `PUPPETEER_SKIP_DOWNLOAD=true` means `npm install` never downloads
a browser again. `PUPPETEER_EXECUTABLE_PATH` points at the link, so any other code that calls
`puppeteer.launch()` (tests, scripts) also uses the shared Chrome. The link's path never changes,
so a later `update` only moves the link. `puppeteer-server.cjs` finds the link itself too, so the
co-browser works even from a process that never read `~/.zshenv`.

### Multiple projects

Run Claude Code sessions in two different project directories and each gets its own Chrome window:

```
# Terminal 1 — in ~/dev/project-a
node scripts/puppeteer-server.cjs http://localhost:3000
# → Profile: project-a, Port: 9615

# Terminal 2 — in ~/dev/project-b
node scripts/puppeteer-server.cjs http://localhost:4000
# → Profile: project-b, Port: 9616
```

The `/look` skill automatically resolves the correct port by matching `basename(cwd)` against the registry, and uses the first running instance when nothing matches. No manual port configuration needed.

### Registry

Running instances are tracked in `~/.claude-chrome-registry.json`:

```json
[
  {
    "profile": "project-a",
    "port": 9615,
    "pid": 12345,
    "userDataDir": "/Users/you/.claude-chrome/project-a",
    "launchedAt": "2025-07-10T15:30:00.000Z"
  }
]
```

Dead PIDs are automatically pruned on read. Entries are removed on clean shutdown (SIGTERM/SIGINT). The `/kill` skill resets the registry when killing all instances.

### API

All commands are POST requests with a JSON body. There's also a GET `/status` endpoint.

| Command | Purpose | Example |
|---------|---------|---------|
| `inspect` | Computed styles + box model for a selector | `{"command":"inspect","selector":".hero"}` |
| `dom` | HTML structure + child elements | `{"command":"dom","selector":".hero","children":true}` |
| `screenshot` | Viewport or element capture (saves PNG) | `{"command":"screenshot","selector":".hero"}` |
| `eval` | Run arbitrary JS in page context | `{"command":"eval","expression":"document.querySelectorAll('.card').length"}` |
| `viewport` | Pin a width to check a responsive layout; `{"width":null}` hands the size back to you | `{"command":"viewport","width":390,"isMobile":true}` |
| `console` | Browser console log buffer (`filter` matches message text; limit, clear) | `{"command":"console","filter":"error","limit":20}` or GET `/console` |
| `status` | Current URL, viewport size, scroll position, profile, port | GET `/status` |

### Headless — an agent's own browser

`node scripts/puppeteer-server.cjs --headless` starts a private, invisible Chrome for a coding
agent that needs to check a UI **works** without touching your window. Each instance gets:
- a port the OS picks (or exactly `--port <n>`);
- a fixed 1440×900 viewport;
- a throwaway profile, deleted when it stops (one killed with `-9` is cleaned up by the next
  headless instance to start);
- no registry entry, so the shared-window lookup can never pick it up.

It prints one line, `{"headless":true,"port":…,"pid":…,"userDataDir":…}`, and several can run at once. This is
how agents inside a batch or a swarm check pages: they load the page, collect errors, drive the
interaction, check for overflow at a phone width, and screenshot for breakage. What the page
*looks like* is left for you, as an item with its URL in the plan's review block.

Commands the headless browser adds (they also work on the shared window, but the skill never
moves your browser with them):

| Command | Purpose | Example |
|---------|---------|---------|
| `goto` | Navigate; returns the HTTP status and title, and resets the error log | `{"command":"goto","url":"http://localhost:3000/settings"}` |
| `click` | Click by selector, by visible text or label, or text within a selector | `{"command":"click","selector":"[role=dialog]","text":"Close"}` |
| `type` | Type into a field, appending or replacing (`clear: true`) | `{"command":"type","selector":"#name","text":"Ada","clear":true}` |
| `press` | Press a key or combination | `{"command":"press","key":"Escape"}` |
| `waitFor` | Wait for an element to appear, or disappear with `hidden: true` | `{"command":"waitFor","selector":"[role=dialog]","hidden":true}` |
| `errors` | Console errors, uncaught page errors and failed requests since the last `goto` | `{"command":"errors"}` |

The new commands answer failures with an `error` key and a non-200 status (400, 404, 408, 409,
502). A project's `rules.look` names what a fresh profile needs: the base URL and how it signs in.

### What `inspect` returns

The most-used command. Returns the computed values that matter for layout debugging:

- **Layout:** `display`, `position`, `width`, `height`, `min/max-width/height`, `box-sizing`
- **Spacing:** `padding-*`, `margin-*`, `gap`
- **Flex/Grid:** `flex-direction`, `flex-wrap`, `justify-content`, `align-items`, `grid-template-*`
- **Typography:** `font-size`, `line-height`, `font-weight`, `font-family`, `text-align`, `white-space`
- **Visual:** `background-color`, `color`, `opacity`, `visibility`, `z-index`, `border-*-width`
- **Overflow:** `overflow`, `overflow-x`, `overflow-y`
- **Bounding rect:** `x`, `y`, `width`, `height` (viewport-relative)

Default values (`0px`, `auto`, `static`, `visible`, `normal`, `none`, `start`) are filtered out — you only see what's actively set.

### Design principles

- **DOM-first to diagnose, eyes to confirm.** Claude reads computed values via `inspect` and `dom`, which answer "why is this 40px too wide" better than a picture does. After a visual change it takes one screenshot of the affected area to confirm it landed, because a measurement only reports on the elements you chose to measure. Otherwise screenshots are taken only when asked.
- **User drives the browser.** Claude never navigates your window. You control the page state; Claude observes and edits source files. The one exception is a responsive check: it asks first, pins a width with `viewport`, and always hands the size back. When Claude needs to drive a page itself, it uses a headless browser of its own.
- **Inspect-edit-verify loop.** After editing a source file, Claude waits for hot reload (~1-2s) and re-inspects the same element to confirm the computed values changed as expected.

### Requirements

- `puppeteer` installed in your project (`npm install puppeteer`)
- The server script at `scripts/puppeteer-server.cjs` (included in the kit)

## Architecture Observatory (`/cto`)

A re-runnable skill that scans your codebase, maps its architecture into a SQLite database, and generates a self-contained HTML document with Mermaid C4 diagrams. Running it again produces a delta report showing what changed — new components, removed files, LOC growth, shifting complexity hotspots.

### How it works

Three automated phases, no interaction required:

1. **Scan** — Structural analysis via grep/regex. Discovers subsystems from directory structure and deploy configs, parses import graphs, computes complexity metrics (LOC, fan-in/fan-out), gathers git history (change frequency, code age). All data goes into `CTO.db`.

2. **Synthesize** — Fans out subagents per subsystem. Each reads key files and produces a 2-3 sentence description. Generates Mermaid diagrams at C4 levels (Context, Container, Component).

3. **Output** — Generates `cowork/architecture/architecture.html` (dark-themed, self-contained, Mermaid.js from CDN) and `cowork/architecture/YYYY-MM-DD_architecture-summary.md` (git-diffable, accumulates over runs).

### First run

| Command | What it does |
|---|---|
| `/cto` or `/cto full` | All three phases |
| `/cto scan` | Phase 1 only: analyze and fill the database |
| `/cto output` | Phase 3 only: regenerate the HTML from the existing database |
| `/cto delta` | The delta report from the last two runs, with no new scan |

`install.sh` creates `CTO.db` from `schema.sql` and `seed.sql`. The scan discovers files on its own, but subsystem descriptions help Claude classify and summarize what it finds. The seed is only read when the database doesn't exist yet, so after editing `seed.sql`, delete `CTO.db` and let the next run rebuild it (or edit the `context` table directly).

### Re-running

Each run creates a new entry in the `runs` table with the current git SHA. The delta report shows:
- **New** components (files added since last run)
- **Removed** components (files deleted since last run)
- **Changed** components (LOC delta, with ↑↓ indicators)
- **Subsystem growth** (LOC trends per subsystem)

### Output

| File | Purpose |
|---|---|
| `cowork/architecture/CTO.db` | Structured data — components, relationships, metrics, history |
| `cowork/architecture/architecture.html` | Visual artifact — open in any browser, share with collaborators |
| `cowork/architecture/YYYY-MM-DD_architecture-summary.md` | Dated markdown — git-diffable, visible in Obsidian |

### Customizing for your project

Edit `cowork/architecture/seed.sql` to define subsystems and patterns, then delete `CTO.db` as above:

```sql
INSERT INTO context (key, value, source) VALUES
  ('subsystem.api', 'Backend API — REST endpoints, auth, database.', 'user'),
  ('subsystem.web', 'Frontend SPA — React with TypeScript.', 'user'),
  ('subsystem.shared', 'Shared types and utilities.', 'user');
```

The scan adapts to your project's language automatically — the procedure includes patterns for TypeScript, Python, Go, and Rust.

### What it produces

The HTML document has 7 parts:

1. **Header** — project name, run date, git SHA, run number
2. **Executive Summary** — the system context diagram, a one-paragraph overview, key numbers
3. **Architecture Overview** — the container diagram and per-subsystem cards
4. **Deploy Topology** — what ships where, service bindings
5. **Complexity Hotspots** — top 15 files by composite score (LOC × 0.4 + fan_out × 50 + change_frequency × 10)
6. **Git Intelligence** — most-changed files in the last 90 days, code age, contributor concentration
7. **Delta Report** — changes since last run

## Wiki (`/wiki`)

An organic project wiki that Claude maintains as the codebase evolves. Pages are created as topics arise from the work, not from a fixed template — the shape reflects the project.

### How it works

Every `/wiki` invocation runs a hybrid procedure:

1. **Targeted updates** — assess what changed recently (git diff, conversation context), update or create wiki pages for affected areas
2. **Holistic scan** — walk the codebase, compare against wiki coverage, catch stale pages, dead references, and undocumented components
3. **Reconcile** — update the `wiki/README.md` index to reflect current state

### Commands

| Command | What it does |
|---|---|
| `/wiki` | Hybrid update — targeted changes + gap/staleness scan |
| `/wiki audit` | Deep audit — exhaustive wiki-vs-codebase reconciliation |
| `/wiki init` | Create `wiki/` with `README.md` and an optional `STYLE.md` scaffold |
| `/wiki <page>` | Create or update a single page by name |
| `/wiki deploy` | Build the wiki into a static site and publish it to Cloudflare Pages |

### Publishing

`/wiki deploy` builds the committed pages with the kit's `scripts/wiki-build/` (linked into every project by
`install.sh`, so a builder change reaches every wiki on its next deploy) and publishes them to Cloudflare Pages.
The site has in-browser search, per-page contents, a sidebar grouped by the index's `## Headings` with
`### Headings` nested inside them (groups start expanded), and a bottom-left button (or Cmd+B / Ctrl+B) that
collapses the sidebar on desktop. It tells search engines not to index it. A top-level folder holding
`RESTRICTED.txt` is left out of the site by the plain renderer (see Configuration).

Deploying needs Cloudflare credentials in `.env` (`CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`), read
through `oprun` when the project keeps secrets in 1Password. The Pages project is created on the first deploy.
Set the Pages project and the wiki's title in `kit.json`:

```json
{ "wiki": { "pagesProject": "my-project-wiki", "title": "My Project Wiki" } }
```

The build is two steps: **parse**, which turns the pages into a bundle, then a **renderer**, which turns the
bundle into the site. The kit's plain renderer covers navigation and reading, and deliberately stays that way.
For anything more (your own branding, sign-in menus, app features), write a renderer of your own and point
`wiki.renderer` at it; it reads the bundle described below.

#### wiki.json format

`/wiki deploy` runs `node scripts/wiki-build/build.mjs <wiki-dir> <out-dir> [--title …] [--access …] [--renderer …]`,
which parses into a temporary bundle and renders it. To keep the bundle, run the first step yourself:
`node scripts/wiki-build/parse.mjs <wiki-dir> <bundle-dir> [--title …] [--access …]` writes a bundle directory:

- **`wiki.json`** — the whole wiki, versioned by `format` (currently `1`; bumped on any change a renderer could
  trip over, and renderers should refuse a format they don't know):
  - `title` — the wiki's name (`--title`, else the index's first heading).
  - `generatedAt` — ISO timestamp.
  - `pages[]` — `source` (the `.md` path), `href` (the `.html` path, relative to the site root), `title`, `html`
    (the rendered page: `.md` links already point at `.html`, h1–h3 have `id`s), `headings[]` (`depth` 2 or 3,
    `id`, `text`), `updated` (ISO, from the file), `restricted`.
  - `nav[]` — the sidebar, in index order: `name` (the `## Heading`, or `null` for links above the first one),
    `links[]` (`label`, `href`), `restricted` (every link is in a restricted folder). A `### Heading` group
    also has `parent`, the name of the `##` group it sits inside; a renderer may ignore it and show the group
    beside the others.
  - `redirects[]` — `from`, `to`: old addresses of pages that moved into folders.
  - `restricted[]` — `folder`, `allow[]` (emails from its `RESTRICTED.txt`).
  - `access` — `{ team, auds }` from the Access settings file, or `null`.
  - `assets[]` — image paths used by pages, relative to the wiki root.
- **`search.json`** — `[{ title, href, text, restricted }]`, `text` lowercased plain text.
- **`files/`** — the images, at their `assets` paths.

A renderer is run as `<wiki.renderer> <bundle-dir> <out-dir>` from the project root, and must write a complete
site into `<out-dir>`. What it does with restricted pages is its responsibility. The plain renderer leaves
them out of the site altogether.

### Style guide

`wiki/STYLE.md` controls how pages are written — audience, voice, terminology, conventions. It's optional but recommended. When present, every wiki write follows it.

Projects can configure a scaffold source so `/wiki init` copies a standard starting point:

```json
{ "wiki": { "styleScaffold": "path/to/STYLE-TEMPLATE.md" } }
```

The style guide itself is organic — it travels with the project and evolves as the project's needs change.

### Configuration

```json
{
  "wiki": {
    "root": "wiki",
    "styleScaffold": "templates/STYLE.md",
    "pagesProject": "my-project-wiki",
    "title": "My Project Wiki",
    "renderer": null
  }
}
```

- **`root`** — wiki directory (default: `wiki/`)
- **`styleScaffold`** — path to a `STYLE.md` template that `/wiki init` copies when creating a new wiki
- **`pagesProject`** — the Cloudflare Pages project `/wiki deploy` publishes to (default: `<repo-name>-wiki`)
- **`title`** — the wiki's name: the top of the sidebar and the end of every tab title (default: the index's first heading)
- **`renderer`** — a command that renders the parsed bundle instead of the plain renderer (see "wiki.json format")

A top-level folder containing `RESTRICTED.txt` (one `allow: person@example.com` line per reader) is for those
readers only. **The plain renderer doesn't publish it at all**: its pages, images, menu and search entries are
left out of the site, and the build says how many pages it skipped. Showing a folder to some readers and not
others needs a server, so that is a job for a renderer of your own (`wiki.renderer`): the bundle carries each
folder's allow list (`restricted[]`) and, when `.claude/wiki-access.json` exists, the site's Cloudflare Access
settings (`access`) for it to check a reader against:

```json
{ "team": "https://<team>.cloudflareaccess.com", "auds": ["<Access application AUD tag>"] }
```

Put Cloudflare Access in front of a new Pages project (its production hostname and `*.<project>.pages.dev`
previews) **before** its first deploy, unless the wiki is meant to be public.

Per-project behavior adjustments go in `rules.wiki`:

```json
{ "rules": { "wiki": "Write for a non-technical ops team. Use the team's own terminology." } }
```

## Video Editing (`/video-editor`)

Transcript-based video editing that lets Claude edit videos with clean sentence-boundary cuts, fades, and burned-in captions — all driven from a reviewable markdown script.

### How it works

The skill uses a **script-first** approach: no edits touch the timeline until you review and approve a markdown document showing exactly what will be kept and cut.

```
/video-editor ~/Downloads/my-recording.mp4
  → Transcribes with mlx-whisper (accurate word-level timestamps)
  → Generates cowork/video/<project>/script.md
  → STOPS — you review and edit the script

/video-editor apply
  → Parses your approved script
  → Executes cuts, fades, and captions in Palmier Pro
  → Runs caption cleanup (brand names, filler removal)

/video-editor cleanup
  → Re-runs caption cleanup only (after you edit captions by hand)
```

### The pipeline

1. **Transcribe** — mlx-whisper (large-v3-turbo) runs locally on Apple Silicon. Produces word-level timestamps with real silence gaps between phrases. This is critical — Palmier's built-in transcription reports 0ms gaps between adjacent words, making it unusable for determining where to cut.

2. **Script** — The transcript is parsed into numbered sentences with gap data. Claude selects sentences that tell the story, groups them into scenes, and writes a markdown script. Every scene starts and ends on a complete sentence — no mid-word or mid-sentence cuts.

3. **Edit** — The script is parsed back into frame ranges. Cuts are executed via Palmier's `ripple_delete_ranges`. Video opacity fades (133ms in, 67ms out) and audio volume fades (67ms in, 100ms out) are applied to every clip independently — video fades create visual transitions, audio fades prevent clicks at cut points.

4. **Polish** — Captions are auto-generated, then cleaned up using a `caption-dictionary.json` that handles brand name capitalization (e.g., "brand" → "Brand"), phrase corrections (e.g., "air table" → "Airtable"), and filler word removal ("um", "uh").

### Best practices (backed by research)

These are encoded into the skill's procedure, derived from analysis of 17 sources including video-use (11.6K stars), auto-editor, Descript community, and peer-reviewed linguistics research:

- **Cut at sentence boundaries, not silence boundaries.** Silence-based cutting breaks phrases. Sentence boundaries from the transcript are the only reliable cut points.
- **Padding absorbs timestamp drift.** Whisper timestamps are ~50-120ms off from actual word boundaries. The skill adds 83ms lead padding and up to 300ms tail padding (capped at the gap to the next word minus a safety margin).
- **600ms is the most natural pause duration** between joined segments (PMC/NIH linguistics research). Below 200ms feels rushed; above 2400ms feels awkward.
- **Audio and video fades are separate concerns.** Video opacity fades (4-8 frames) create visual scene transitions. Audio volume fades (4-6 frames) prevent clicks/pops at cut points. Different durations, different purpose.
- **The script catches bad edits before they happen.** Reading "So we're going to get all this data pulled out of" immediately reveals a mid-sentence cut that would sound terrible — but only if you see it as text before it's applied to the timeline.

### Dependencies

**Palmier Pro** (required) — AI-native video editor for macOS with a built-in MCP server. Open source, YC-backed.
- Install: https://github.com/palmier-io/palmier-pro
- Must be running with its MCP server connected before using the skill
- The source video must already be imported into Palmier and on the timeline
- Add to your project: `claude mcp add --transport http palmier-pro http://127.0.0.1:19789/mcp`

**mlx-whisper** (auto-installed) — Apple Silicon-optimized Whisper for accurate word-level transcription. The skill creates a Python venv on first run and installs mlx-whisper automatically (~3 minutes, cached for future sessions). Requires Python 3.

**Why not Palmier's built-in transcription?** Palmier uses on-device speech recognition that assigns timestamps with zero gaps between adjacent words — every word's end timestamp equals the next word's start timestamp. This makes it impossible to identify natural pauses for cut-point decisions. mlx-whisper with forced alignment captures real silence gaps (100ms–3000ms+) between phrases.

### Caption dictionary

The dictionary lives at `cowork/video/caption-dictionary.json` and is **project-owned** — the kit
installs an empty template once and never overwrites it. It sits outside the skill folder on
purpose: in outside-repo mode the skill directory is shared across every project, and your brand
terms must not be. Customize it freely:

```json
{
  "replacements": {
    "mug.org": "mug.work",
    "air table": "Airtable"
  },
  "capitalize": ["Mug", "Airtable", "Claude"],
  "remove_fillers": ["uh,", "um,", "Uh,", "Um,"]
}
```

- **replacements** — exact phrase swaps (whisper often mis-transcribes brand names)
- **capitalize** — case-insensitive whole-word matching (e.g., any "mug" becomes "Mug")
- **remove_fillers** — standalone filler captions deleted entirely

### Output

All artifacts land in `cowork/video/<project-name>/`:
- `whisper-transcript.json` — raw word-level timestamps
- `sentences.txt` — sentence index with gap data
- `script.md` — the reviewable/editable cut script

## Secrets (`/1password`)

Each project (or group of related projects) gets its own 1Password vault, and a 1Password service account's
vault list **cannot be changed after it is created**. So instead of one machine-wide token that has to be
rebuilt every time a vault is added, the kit keeps **one read-only service account per vault** and lets the repo say
which vault it belongs to:

```json
"secrets": { "vault": "my-project", "account": "my.1password.com" }
```

`/1password` sets this up, checks it, and migrates a plaintext `.env`. Underneath are two scripts in
`~/.claude-kit/scripts/`:

- **`op-sa-bootstrap <vault> [--write]`** — once per vault, at the keyboard (Touch ID). Creates a
  service account named `<vault>-ro-<date>` with `read_items` on that one vault (`--write` adds
  `write_items` and names it `-rw-`), verifies it sees exactly
  that vault, and stores the token in the macOS Keychain as `op-sa-<vault>`. Tokens do not expire
  unless `--expires-in` is given. `--rotate` replaces one; revoke the old account with
  `op user delete <uuid>` (service accounts are users of type `SERVICE_ACCOUNT`; find the uuid
  with `op user list`).
- **`oprun -- <command>`** — runs a command with the repo's `.env` resolved through that token.
  `oprun op <args>` runs any `op` command with the same token, so an agent with a `--write`
  service account can move a secret into the vault or rename a field (`op item create`, `op item edit`).
  `oprun get VAR` prints one resolved value for shell scripts. `oprun --no-env` resolves only
  references already in the process environment — the shape an MCP server launch needs, where
  `.mcp.json` sets `"command": "…/oprun"`, `"args": ["--vault", "<vault>", "--no-env", "--no-masking", "--", "npx", …]`
  and the server's `env` block carries `op://` values (masking must be off for stdio protocols).
  `.env` mixes plain values with `op://vault/item/field` references; only the references are
  resolved, and `op run` masks them in output. Every `.env` from the repo root down to the working
  directory is layered, nearest last. `oprun check` shows what the token can see;
  `oprun read op://…` prints one value (avoid in agent sessions — it lands in the transcript).
  With no Keychain token for the vault, or with `OPRUN_AUTH=desktop`, `oprun` falls back to the
  1Password desktop app (Touch ID), which is how a collaborator with vault access uses the same repo.

Rules the scripts enforce, learned the hard way:

- **Never export `OP_SERVICE_ACCOUNT_TOKEN` from a shell rc file.** It silently overrides the
  desktop-app (Touch ID) path for every `op` call, so a dead token breaks `op` for the human too.
  `oprun` passes the token to one child process and nowhere else.
- **Every preflight and read call runs under a `perl -e 'alarm N'`** — macOS has no `timeout`,
  and on macOS 26 the service-account path can block forever on a TCC dialog (op-js #216).
- **`op whoami` is a readiness check only on the service-account path.** On the desktop-app path
  it says "not signed in" while real calls succeed.
- Family and Individual plans allow about 1,000 requests a day across all service accounts;
  reference items by ID (`op://vault/<item-id>/field`) to spend one request per read instead of three.

## Claude Switcher (`/claude-switcher`)

Claude Code keeps one login per config folder, so a second account normally means signing out
and in again, and losing track of which one a window is on. This makes an account a **VS Code
profile**: switch profile, reload the window, and that project is on the other account.

### How it works

- **An account is a folder.** `~/.claude` is the default; `~/.claude-<name>` is another, with its
  own login, settings and session history. `CLAUDE_CONFIG_DIR` picks the folder.
- **A profile picks the folder.** Two settings in the profile's own `settings.json`:
  `claudeCode.environmentVariables` for the Claude panel, and `terminal.integrated.env.<os>` for
  `claude` typed in the VS Code terminal.
- **VS Code remembers a profile per folder**, so a project reopens on the account it was last on.

```bash
~/.claude-kit/scripts/claude-switcher                    # every account, who is signed in, which profile and folders use it
~/.claude-kit/scripts/claude-switcher add work           # create ~/.claude-work and point the "work" profile at it
~/.claude-kit/scripts/claude-switcher login work         # sign in (run it in a real terminal)
~/.claude-kit/scripts/claude-switcher run work           # start claude on that account from any terminal
```

`add` takes `--profile "<Name>"` when the profile is not named after the account, and
`--share-history <account>` to give two accounts **one** session list and the same memories, for
a second account doing the same work. Leave it off when the accounts must not see each other's
work. A new account starts from a copy of the default account's `settings.json`
(`--copy-settings <account>` picks another); after that each account's settings, plugins and MCP
sign-ins are its own. The script stores nothing of its own; it reads the folders and VS Code's files each time,
and is safe to re-run.

### Setting one up

1. In VS Code: `Profiles: Create Profile`, copy from the profile you normally use.
2. `~/.claude-kit/scripts/claude-switcher add <name> --profile "<Profile>"`
3. In a terminal: `~/.claude-kit/scripts/claude-switcher login <name>`
4. In the project's window: `Profiles: Switch Profile`, then `Developer: Reload Window`.

Or run `/claude-switcher add <name>` and Claude walks through it and checks the result.

### Things that go wrong

- **Sign in from a terminal, never the VS Code panel.** The panel's login can land in the default
  account's folder and replace that login. The status flags one email signed in to two accounts.
- **Switch the profile in the project's own window.** The session list is per folder; a new
  empty window on the profile shows the home folder's sessions.
- **Reload after switching.** A running Claude keeps the account it started on.
- **One folder, one window.** For two accounts side by side, open the folder in one profile and
  the project's `.code-workspace` file in the other.
- **Hidden and archived sessions are per profile**, even with shared history.
- **A terminal outside VS Code knows nothing about profiles** and uses the default account. Use
  `claude-switcher run <name>` there.
- **A profile whose settings file has comments is left alone.** `add` prints the two settings to
  paste in by hand.

## Customization

### Additional MCP Servers

Beyond the research stack above, you may want these project-specific MCP servers:

**Palmier Pro (video editing)**
- HTTP transport: `http://127.0.0.1:19789/mcp`
- Requires Palmier Pro running locally (macOS only)
- Best for: `/video-editor` — transcript-based video cutting, fades, captions
- Install: https://github.com/palmier-io/palmier-pro
- Add: `claude mcp add --transport http palmier-pro http://127.0.0.1:19789/mcp`

### Per-project skills to add

These were intentionally left out of the kit because they're deeply project-specific. Use the
patterns below as templates when building your own.

This is **lane 3** from [Configuration](#where-project-specific-behavior-belongs): a project-owned
skill with its own name, living in `.claude/skills/` alongside the kit's. The installer never
touches skills it doesn't ship, so yours are safe in either mode — no `fork` entry needed.

---

### `/stage` — Track user-facing changes for release

Accumulates changelog entries between releases. Entries persist in `cowork/staged.json` until a ship/release command consumes them.

**Key design:**
- File: `cowork/staged.json` — JSON array of staged entries
- Entry schema: `{ "type": "feature|improvement|fix|breaking", "text": "user-facing description", "components": ["area1", "area2"] }`
- Subcommands: `add` (default), `list`, `edit <n>`, `remove <n>`
- Customer-facing only — don't stage internal tooling, dev workflow, or documentation changes
- Auto-detect `type` and `components` from recent commits and changed files

**Customization points:**
- `components` array values — define your project's areas (e.g., `["api", "frontend", "mobile", "cli"]`)
- `type` values — add project-specific types if needed (e.g., `deprecation`, `security`)

**Example SKILL.md frontmatter:**
```yaml
---
name: stage
description: Stage a change for the next release — tracks user-facing improvements between ship runs.
argument-hint: '[description | list | edit <n> | remove <n>]'
---
```

**Example staged.json:**
```json
[
  { "type": "feature", "text": "Budget alerts deliver to Slack via webhook", "components": ["api"] },
  { "type": "fix", "text": "Deploy command prints success confirmation", "components": ["cli"] }
]
```

---

### `/ship` — Release orchestration

Unified release process — deploy, version bump, publish, changelog, notifications. The most project-specific skill because it ties together your deployment pipeline.

**Key design:**
- **Preflight checks** — branch check, type-check, test pass (gate on these, don't skip)
- **Auto-detect mode** — read deployment state (e.g., `.deploy-shas`, git log) to determine what changed since last release
- **Modes** — platform-only, CLI release, library publish, full release (varies per project)
- **Changelog generation** — consume `cowork/staged.json`, write changelog entry, clear staged entries
- **Version bumping** — analyze commits for semver (breaking -> major, features -> minor, fixes -> patch)
- **Guard rails** — confirm destructive actions (npm publish, deploy, push to external repos), stop on failure

**Flow template:**
1. Preflight (branch, types, tests)
2. Auto-detect what changed since last release
3. Present detection to user, confirm before proceeding
4. Deploy/publish (project-specific steps)
5. Write changelog entry from staged entries
6. Create git tag / GitHub release
7. Clear `cowork/staged.json`
8. Commit release artifacts

**Customization points:**
- Deployment targets — Cloudflare Workers, Vercel, AWS, Docker, npm, etc.
- Credential management — 1Password, env vars, GitHub secrets
- Multi-repo coordination — if your project spans multiple repos
- Changelog format — JSON, markdown, HTML, wherever your changelog lives
- Notification channels — Slack, email, GitHub release notes

**Example SKILL.md frontmatter:**
```yaml
---
name: ship
description: Unified release process — deploy, publish, and write changelog entries. Auto-detects what changed.
argument-hint: "[component]"
---
```

---

### `/dev` — Launch dev server with Puppeteer co-browsing

Starts your project's dev server and opens a headed Chrome instance for co-browsing via the `/look` skill. This is the bridge between `/look` (which inspects) and your actual dev environment.

**Key design:**
- Kill any existing process on the dev port, then start the dev server in the background
- Launch a Puppeteer server pointed at the dev server URL — port auto-assigned, profile auto-named from cwd
- Both processes run in the background — the skill returns after confirming both are up
- Pairs with `/kill` (to tear down) and `/look` (to inspect)

**Flow:**
1. Check if the dev port is already in use — kill if so (restart case)
2. Start the dev server: `cd <project-dir> && npm run dev` (background)
3. Wait for the server to respond (curl health check)
4. Launch Puppeteer server pointed at the dev URL (background) — it auto-registers in `~/.claude-chrome-registry.json`
5. Wait for Puppeteer to be ready (read port from registry)
6. Report both URLs (dev server + Puppeteer)

**Puppeteer server:** Included at `scripts/puppeteer-server.cjs`. Requires `npm install puppeteer` in your project. Launches headed Chrome with an isolated profile per project (`~/.claude-chrome/<profile>/`), auto-assigns a free port in the 9615-9634 range, and exposes an HTTP API (commands are listed in the [`/look` reference](#look-co-browser-look)).

**Example SKILL.md:**
```yaml
---
name: dev
description: Launch the dev server with Puppeteer co-browsing for /look inspection.
user_only: true
---
```

```markdown
# Dev Server

## Procedure

1. Check if dev port is in use:
   \`\`\`bash
   lsof -iTCP:3000 -sTCP:LISTEN -t 2>/dev/null
   \`\`\`

2. If occupied, kill and wait:
   \`\`\`bash
   lsof -iTCP:3000 -sTCP:LISTEN -t 2>/dev/null | xargs /bin/kill 2>/dev/null; sleep 1
   \`\`\`

3. Start the dev server (background):
   \`\`\`bash
   npm run dev
   \`\`\`

4. Verify it's up:
   \`\`\`bash
   for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ | grep -q 200 && break; sleep 1; done
   \`\`\`

5. Start Puppeteer co-browsing server (background):
   \`\`\`bash
   node scripts/puppeteer-server.cjs http://localhost:3000
   \`\`\`

6. Wait for Puppeteer and resolve port:
   \`\`\`bash
   sleep 2
   LOOK_PORT=$(node -e "
     const fs = require('fs'), path = require('path'), os = require('os');
     const reg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude-chrome-registry.json'), 'utf8') || '[]');
     const profile = path.basename(process.cwd());
     const entry = reg.find(e => e.profile === profile);
     if (entry) console.log(entry.port); else console.log('');
   " 2>/dev/null)
   for i in 1 2 3 4 5 6 7 8 9 10; do curl -s http://127.0.0.1:${LOOK_PORT}/status > /dev/null 2>&1 && break; sleep 1; done
   \`\`\`

7. Report:
   - Dev server: http://localhost:3000
   - Puppeteer: http://127.0.0.1:${LOOK_PORT}
   - Chrome is open with an isolated profile — set mobile viewport via Chrome's device toolbar

## Rules
- No confirmation needed — execute immediately
- If the port is in use, kill and restart
- Exit codes 143/144 from killed background tasks are expected
```

**Customization points:**
- Dev port (3000, 4747, 5173, 8080, etc.)
- Dev command (`npm run dev`, `npx vite`, `npx next dev`, `npx wrangler dev`, etc.)
- Puppeteer server script path
- Profile name (`--profile <name>`) if cwd basename isn't unique across projects

---

### `/deploy` — Deploy services with credential management

Deploys one or all services to your hosting provider. Most useful in monorepos or multi-service projects where each service has its own deploy command and you want a single entry point.

**Key design:**
- **Target table** — named targets mapping to directories, deploy commands, and service names
- **`all` mode** — deploys every target in dependency order (e.g., API gateway first since other services depend on it)
- **Credential management** — wraps deploy commands with credential injection (1Password `op run`, env vars, etc.)
- **SHA tracking** — records deployed git SHAs in `.deploy-shas` so `/ship` can detect what changed since last deploy
- **Fail-fast** — if one service fails, stop immediately (don't continue deploying downstream services)

**Flow:**
1. If no target given, print the target table and ask
2. Type-check the service if it has a `tsconfig.json`
3. Run the deploy command with credentials injected
4. Update `.deploy-shas` with the current git SHA
5. Report success/failure

**Customization points:**
- Hosting provider — Cloudflare Workers, Vercel, AWS, Fly.io, Docker, etc.
- Deploy command — `wrangler deploy`, `vercel --prod`, `fly deploy`, etc.
- Credential injection — 1Password `op run`, `aws-vault exec`, env vars, etc.
- Target list — one row per deployable service/app
- Deploy order for `all` mode — dependency-aware ordering
- SHA tracking — which services to track, where to store SHAs

**Example SKILL.md frontmatter:**
```yaml
---
name: deploy
description: Deploy services. Requires a target — a service name or "all".
user_only: true
---
```

**Example target table:**

| Target | Directory | Service |
|--------|-----------|---------|
| `api` | `services/api/` | my-api |
| `web` | `apps/web/` | my-web |
| `worker` | `services/worker/` | my-worker |
| `all` | all of the above, in order | — |

---

