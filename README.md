# TB Claude Kit

**Claude Code forgets everything when the session ends.** Every new session starts by
re-explaining the same architecture, re-litigating the same decisions, re-discovering the same
constraints. This kit fixes that, then builds on top of it.

It gives Claude a **persistent brain** (a SQLite knowledge base that survives restarts), a
**planning loop** that reconciles itself against the real codebase on every resume, a **research
system** that runs parallel agents under an anti-fabrication contract, and **eyes** — a live
browser it can inspect the DOM of rather than squint at screenshots.

Developed through ongoing trial and error by [Tyler Berggren](https://github.com/tyler-berggren).

---

## Quick start

```bash
# 1. Clone the kit and create the standard pointer (once per machine)
git clone https://github.com/tyler-berggren/tb-claude-kit.git ~/dev/tb-claude-kit
ln -s ~/dev/tb-claude-kit ~/.claude-kit

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

> **A note on permissions.** This kit ships with Claude Code's permission prompts bypassed, so
> Claude can work without stopping to ask. That means tool calls — including shell commands —
> execute without confirmation. It's a reasonable default for a repo you own and trust, and a bad
> one otherwise. To restore prompting, delete the `permissions` block from
> `.claude/settings.json`. The pre-configured MCP servers in `.mcp.json` are covered by the same
> setting.

---

## The skills

Thirteen skills, grouped by what they do for you.

**Memory — so context accumulates instead of resetting**

| | |
|---|---|
| `/brain` | The knowledge base. Decisions, open questions, insights, tasks, milestones — queryable, tiered by relevance, and loaded into every new session automatically. |
| `/brainstorm` | Think an idea through conversationally. Decisions and questions that emerge are captured as you go, not reconstructed afterwards. Includes a `hater` mode that pressure-tests an idea like a skeptical investor would. |

**Thinking — so work survives being interrupted**

| | |
|---|---|
| `/plan` | Phased plans that live in the repo as markdown. Resuming re-reads the plan against the current code and reports drift, rather than trusting what the last session claimed. Supports `{{bracketed}}` change proposals you write offline. |
| `/research` | Parallel agents across a six-tool stack (Brave, Exa, Firecrawl, Tavily, Perplexity, WebFetch). Each writes its own report under an anti-fabrication contract with a mandatory "what I could not verify" section; the orchestrator only synthesizes. Reports accumulate as sourced, dated folders. |

**Seeing — so Claude can check its own work**

| | |
|---|---|
| `/look` | A shared Chrome window Claude inspects DOM-first — computed styles, box models, console logs — instead of guessing from screenshots. |
| `/cto` | Architecture observatory. Scans the codebase into a SQLite model and generates an HTML document with Mermaid C4 diagrams. Re-running shows what drifted. |
| `/vibe-audit` | Health and security audit tuned for vibe-engineered code, with Bayesian pattern tracking that gets more precise each run. |
| `/web` | SEO/AEO audit for a static site. Checks metadata, structured data, sitemap, robots, and llms.txt are present and correct — then checks they are still *current*, catching sitemaps with stale lastmod, markdown mirrors that drifted from their pages, and FAQ schema answering questions the page no longer asks. |
| `/bridge` | A local server that lets HTML artifacts read and write real project files. |

**Doing — the small stuff, done consistently**

| | |
|---|---|
| `/commit` `/push` | Stage, write a real commit message, push. Regenerates SQLite NDJSON sidecars if configured. |
| `/kill` | Kill dev servers, watchers, and browser instances without touching your Claude session. |
| `/parse` | Local documents — contracts, decks, spreadsheets, scanned PDFs — converted to markdown Claude can actually read. Point it at a file, a glob, or a directory; the `.md` lands beside the original. |
| `/video-editor` | Transcript-driven video editing — transcribe, script, cut, caption. |

---

## How it works

The **brain DB** is the connective tissue. `/brainstorm` writes decisions and questions into it.
`/research` indexes reports in it. `/plan` reads from it. Session hooks load the current state on
startup, so a fresh Claude opens already knowing where things stand.

Everything else is a file in your repo, readable by a human or a future session:

- **Plans** are numbered, dated markdown — `cowork/plans/001_2026-06-20_auth-redesign.md`
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
/brainstorm  →  /research  →  /plan  →  implement  →  /commit
```

Start with `/brainstorm` to explore the problem conversationally; decisions and questions are
captured automatically. When you need outside evidence — how an API behaves, what the tradeoffs
are, what others hit — `/research` returns a sourced report.

Once the shape is clear, `/plan` generates a phased plan grounded in both the codebase and the
brain DB, so it reflects what you've already worked through. Then build. `/plan N` resumes with a
fresh-eyes reconciliation pass, re-reading the plan against the current code to catch the gap
between what was planned and what actually got built.

**Not everything needs the full loop:**

- **Quick feature** — `/plan` → implement → `/commit`
- **Exploratory question** — `/brainstorm`, and you're done; insights are saved
- **Technology decision** — `/research` → `/brainstorm` the findings → decision logged
- **Bug fix** — just fix it → `/commit`

**Proposing plan changes offline.** Wrap edits in `{{double curly braces}}` directly in the plan
file, then run `/plan review`. Claude checks each one for feasibility and coherence with the rest
of the plan before applying it.

```
- [ ] **API design** — {{use GraphQL instead of REST for the query layer}}
```

---

## Two ways to install

The kit can either **travel with your repo** or **live outside it**. This is the main thing to
understand before adopting it across several projects.

| | **outside repo** (default) | **inside repo** |
|---|---|---|
| Kit files are | symlinks into `~/.claude-kit` | real files in your project |
| Git | gitignored — never committed | tracked — travel with the repo |
| Updating | instant; edit the kit once, every project sees it | re-run `install.sh`, with drift detection |
| Needs the kit present? | yes | no |

**Choose with one question: does a machine without your kit checkout need this repo to work?**
If yes — a repo you hand to someone else, a cloud session, CI — use `inside`. Otherwise `outside`,
and stop thinking about propagation entirely.

```bash
bash ~/.claude-kit/install.sh                  # uses the mode in kit.json (default: outside)
bash ~/.claude-kit/install.sh --mode inside    # convert to vendored files
bash ~/.claude-kit/install.sh --mode outside   # convert back to symlinks
bash ~/.claude-kit/install.sh --dry-run        # report what would change, touch nothing
bash ~/.claude-kit/install.sh --yes            # auto-update drifted files, enable integrations
```

Conversion is lossless in both directions.

**Adopting an existing project.** Paths already holding real files are reported as `[occupied]`
and left alone — the installer never silently deletes your work. Content that's byte-identical to
the kit converts automatically. For anything that genuinely differs, either add it to `fork` (see
below) or commit it and re-run with `--replace`.

**On another machine.** Clone the kit anywhere, run `ln -s <path> ~/.claude-kit`, then
`bash ~/.claude-kit/install.sh` in each project. Nothing in any repo hardcodes a checkout location.

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
  "plan":     { "roots": ["cowork/plans", "cowork/clients/*/projects/*/plans"] },
  "research": { "roots": ["cowork/research"] },

  "rules": {
    "push": "If the post-commit hook reports undeployed changes, ask before pushing."
  }
}
```

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

A standalone script at `scripts/sqlite-sidecar.sh` can also be run directly outside of `/commit`.

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
3. **A procedure** → a project-owned skill with its own name, sitting alongside the kit's. Your
   own skills in `.claude/skills/` are never touched by the installer.
4. **`fork`** → last resort, when the kit's own behavior has to change

The ordering matters: JSON keeps overrides deliberately small, and a rule that won't fit
comfortably in a string is usually a sign it belongs in its own skill — or upstream in the kit.

---

## What's in a project after install

```
.claude/
  kit.json            # mode + configuration (yours)
  skills/             # kit skills, plus any you add
  hooks/              # session-start: loads brain state, heals schema drift
  settings.json       # model, permissions, hooks (yours)
cowork/
  brain/
    BRAIN.db          # knowledge base (SQLite + FTS5)
    BRAIN.md          # auto-generated readable export
    MANTRA.md         # Claude's self-authored context
  plans/              # NNN_YYYY-MM-DD_topic.md
  research/           # NNN_YYYY-MM-DD_topic/ — agent-*.md + SUMMARY.md
  architecture/       # CTO.db, generated architecture.html, dated summaries
  vibe-audit/         # VIBE-AUDIT.db, GUARDRAILS.md (yours)
  video/              # transcripts, scripts, caption-dictionary.json (yours)
CLAUDE.md             # project documentation + mantra block (yours)
.mcp.json             # research MCP servers (yours — holds API keys)
```

Files marked *(yours)* are created once and never overwritten. Everything else is kit-managed.

### The brain DB

SQLite with FTS5 full-text search at `cowork/brain/BRAIN.db`.

**Entry types** — `note`, `decision` (permanent; supersede rather than edit), `question`,
`insight`, `task`, `milestone`.

**Tiers**, computed rather than set by hand:

- **hot** — focus items and plan-linked tasks with momentum
- **warm** — importance ≥ 6, or created in the last 14 days
- **cold** — everything else still active
- **archived** — done, dropped, or superseded

---

# Reference

Everything below is detail for when you need it — skip it on a first read.

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

Launch manually, or build a `/dev` skill (see Customization section) that starts your dev server + the co-browser together:

```bash
# Launch with a starting URL — profile auto-names from cwd basename
node scripts/puppeteer-server.cjs http://localhost:3000

# Launch without a URL — navigate manually in the Chrome window
node scripts/puppeteer-server.cjs

# Explicit profile name (useful for monorepos or shared directories)
node scripts/puppeteer-server.cjs --profile my-project http://localhost:3000

# Explicit port (otherwise auto-assigns from 9615-9634)
node scripts/puppeteer-server.cjs --port 9620 http://localhost:3000
```

Each instance gets its own Chrome user data directory at `~/.claude-chrome/<profile>/` — fully isolated cookies, storage, and extensions per project.

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

The `/look` skill automatically resolves the correct port by matching `basename(cwd)` against the registry. No manual port configuration needed.

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
| `console` | Browser console log buffer (filter, limit, clear) | `{"command":"console","filter":"error","limit":20}` or GET `/console` |
| `status` | Current URL, viewport size, scroll position, profile, port | GET `/status` |

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

- **DOM-first, not screenshot-first.** Claude reads computed values via `inspect` and `dom`. Screenshots are only taken when explicitly requested — they're expensive, slow, and Claude can extract more useful information from structured style data.
- **User drives the browser.** Claude never navigates or resizes the viewport. You control the page state; Claude observes and edits source files.
- **Inspect-edit-verify loop.** After editing a source file, Claude waits for hot reload (~1-2s) and re-inspects the same element to confirm the computed values changed as expected.

### Requirements

- `puppeteer` installed in your project (`npm install puppeteer`)
- The server script at `scripts/puppeteer-server.cjs` (included in the kit)

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
- **Audio and video fades are separate concerns.** Video opacity fades (6-8 frames) create visual scene transitions. Audio volume fades (4-6 frames) prevent clicks/pops at cut points. Different durations, different purpose.
- **The script catches bad edits before they happen.** Reading "So we're going to get all this data pulled out of" immediately reveals a mid-sentence cut that would sound terrible — but only if you see it as text before it's applied to the timeline.

### Dependencies

**Palmier Pro** (required) — AI-native video editor for macOS with a built-in MCP server. Open source, YC-backed.
- Install: https://github.com/palmier-io/palmier-pro
- Must be running with its MCP server connected before using the skill
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

## Architecture Observatory (`/cto`)

A re-runnable skill that scans your codebase, maps its architecture into a SQLite database, and generates a self-contained HTML document with Mermaid C4 diagrams. Running it again produces a delta report showing what changed — new components, removed files, LOC growth, shifting complexity hotspots.

### How it works

Three automated phases, no interaction required:

1. **Scan** — Structural analysis via grep/regex. Discovers subsystems from directory structure and deploy configs, parses import graphs, computes complexity metrics (LOC, fan-in/fan-out), gathers git history (change frequency, code age). All data goes into `CTO.db`.

2. **Synthesize** — Fans out subagents per subsystem. Each reads key files and produces a 2-3 sentence description. Generates Mermaid diagrams at C4 levels (Context, Container, Component).

3. **Output** — Generates `cowork/architecture/architecture.html` (dark-themed, self-contained, Mermaid.js from CDN) and `cowork/architecture/YYYY-MM-DD_architecture-summary.md` (git-diffable, accumulates over runs).

### First run

```
/cto
```

On first run, CTO.db is created from `schema.sql` and `seed.sql`. Edit `seed.sql` first to define your project's subsystems — the scan discovers files automatically, but subsystem descriptions help Claude classify and summarize what it finds.

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

Edit `cowork/architecture/seed.sql` to define subsystems and patterns:

```sql
INSERT INTO context (key, value, source) VALUES
  ('subsystem.api', 'Backend API — REST endpoints, auth, database.', 'user'),
  ('subsystem.web', 'Frontend SPA — React with TypeScript.', 'user'),
  ('subsystem.shared', 'Shared types and utilities.', 'user');
```

The scan adapts to your project's language automatically — the procedure includes patterns for TypeScript, Python, Go, and Rust.

### What it produces

The HTML document has 7 sections:

1. **Executive Summary** — stats grid, one-paragraph overview
2. **System Context** — Mermaid C4 Level 0 diagram (system boundary + external actors)
3. **Architecture Overview** — per-subsystem cards with descriptions and LOC
4. **Deploy Topology** — what ships where, service bindings
5. **Complexity Hotspots** — top 15 files by composite score (LOC × 0.4 + fan_out × 50 + change_frequency × 10)
6. **Git Intelligence** — most-changed files in the last 90 days
7. **Delta Report** — changes since last run

## Research System (`/research`)

The research skill runs deep, multi-agent web research with a 6-tool stack. Each research run produces a numbered folder in `cowork/research/` containing individual subagent reports and an orchestrator-written synthesis.

### Architecture

```
/research "topic"
  → Scout pass (Perplexity orientation, deep dives only) — citations spot-checked before use
  → Decompose into 3-5 research angles
  → Spawn parallel subagents (one per angle, each under the anti-fabrication contract)
  → Each agent searches, extracts, writes its own report + "What I Could NOT Verify"
  → Orchestrator reads all reports, writes SUMMARY.md
  → Supersede any brain entries the findings overturned; append to SOURCE-NOTES.md
```

**Key design principles:**

- **Angle-based, not tool-based.** Each subagent gets a research *question* and the full tool stack. The agent picks the right tools for its question — not the other way around.
- **Subagents write their own reports.** Each agent writes directly to `agent-{label}.md` in the run folder. The orchestrator never rewrites agent findings — it only writes `SUMMARY.md` as a synthesis layer. This prevents "silent consensus hallucination" (the orchestrator inventing positions no agent actually found) and preserves the raw research for drill-down.
- **Cost-aware extraction cascade.** For getting content from URLs, agents follow: WebFetch (free) → Tavily extract (free tier) → Firecrawl (paid credits). Firecrawl is reserved for pages that genuinely need JS rendering or structured extraction.
- **Anti-fabrication contract.** Every agent prompt carries a verbatim rule: retrieved URLs for every specific claim, no reconstruction from memory, a required "What I Could NOT Verify" section, and absence of evidence reported as a finding. This is what catches invented citations, misremembered figures, and numbers that secondary sources have quietly corrupted — including the pre-synthesized scout's own output, whose citations are spot-checked before anything it says is carried forward.
- **Accumulating source knowledge.** `SOURCE-NOTES.md` in the skill directory records what blocked, what worked around it, which source types proved unexpectedly primary, and which content classes wasted searches. Agents read it before searching; each run appends. Research gets cheaper over time instead of rediscovering the same dead ends.

### Tool Stack

The skill uses 6 search/extraction tools, each filling a distinct niche:

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

Legacy quick reference:

- **"What do practitioners think about X?"** → Brave Search (Reddit/HN access)
- **"What's conceptually related to X?"** → Exa (semantic search)
- **"Quick factual answer"** → Tavily (fastest) or WebSearch
- **"Orient me on a new topic"** → Perplexity (landscape only — validate its citations)
- **"Official docs for X"** → WebSearch with `allowed_domains`
- **"Full content of this URL"** → WebFetch → Tavily extract → Firecrawl (cascade)

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
| **Perplexity** | None | ~$5-15/1K requests | Pay-as-you-go (1 call per run) |
| **Firecrawl** | 500 credits/mo | $16/mo (3,000 credits) | Consider Hobby tier |

Firecrawl is the only tool worth upgrading — its free tier is tight (500 credits/mo) and it's the only tool that handles JS-rendered pages. The extraction cascade (WebFetch → Tavily → Firecrawl) minimizes credit burn.

### Setup

All 5 MCP servers are pre-configured in `.mcp.json`. After installing the kit:

1. **Brave Search** — get a free API key at https://brave.com/search/api/ and add it to `.mcp.json`
2. **Exa** — no key needed. Uses OAuth via HTTP transport (authenticates on first use)
3. **Tavily** — no key needed. Uses OAuth via HTTP transport (authenticates on first use)
4. **Firecrawl** — sign up at https://firecrawl.dev, get API key, add to `.mcp.json`. Leave the `FIRECRAWL_API_URL` alongside it in place — [`/parse`](#document-parsing-parse) needs it
5. **Perplexity** — sign up at https://perplexity.ai, get API key from settings, add to `.mcp.json`

The skill works with any subset of these tools — it gracefully adapts when tools are missing. But the full stack gives the best results: keyword search (Brave) + semantic search (Exa) + fast lookup (Tavily) + orientation (Perplexity) + deep extraction (Firecrawl) + free fallback (WebFetch).

## Document Parsing (`/parse`)

Research reaches the public web. `/parse` handles the other half — the documents
already on your disk that no URL points at. Signed contracts, client decks,
exported spreadsheets, scanned PDFs: the files that carry the actual terms of
your work and that Claude otherwise cannot open.

It wraps Firecrawl's `/v2/parse` endpoint, the local-file counterpart to the
`/scrape` used by `/research`.

```
/parse contracts/msa.docx                 # one file → msa.md beside it
/parse ~/Downloads/kickoff-docs           # every supported file in a directory
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

Parsed markdown lands as `<original>.md` beside its source, originals untouched,
existing `.md` files never overwritten silently. The skill reports what it wrote
and then spot-checks the result rather than declaring success — tables are where
docx and PDF conversion actually degrades, multi-column PDFs can interleave, and
page furniture tends to land mid-document. Set `rules.parse` in `.claude/kit.json`
if a project files parsed documents somewhere specific.

**Limits:** 50 MB per file, one file per request, credits consumed per file.
Parsing uploads the file to Firecrawl's API — the skill says so before the first
request when the documents are confidential, and offers `--redact` for PII.

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

**Puppeteer server:** Included at `scripts/puppeteer-server.cjs`. Requires `npm install puppeteer` in your project. Launches headed Chrome with an isolated profile per project (`~/.claude-chrome/<profile>/`), auto-assigns a free port in the 9615-9634 range, and exposes an HTTP API with commands: `inspect` (computed styles + box model), `dom` (HTML structure), `screenshot` (viewport/element capture), `eval` (JS execution), and GET `/status` (current URL, viewport, scroll, profile, port).

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

