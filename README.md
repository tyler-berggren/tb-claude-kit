# TB Claude Kit

A reusable project kit to give Claude Code a brain, eyes, research superpowers, and other meta skills to make Claude feel like an extremely capable coworker.

Developed through ongoing trial and error by [Tyler Berggren](https://github.com/tyler-berggren).

## What's Included

### Skills (13)

| Skill | Purpose |
|---|---|
| `/brain` | Project knowledge DB — decisions, tasks, questions, insights, milestones. Single source of truth. |
| `/brainstorm` | Conversational idea development with live brain DB capture. |
| `/bridge` | Start artifact bridge server for HTML artifacts to read/write project files. |
| `/commit` | Stage all files and commit with auto-generated message. |
| `/cto` | Architecture observatory — scans codebase, maps components/relationships into SQLite, generates HTML with Mermaid C4 diagrams. Delta tracking across runs. |
| `/kill` | Kill dev processes (servers, watchers, bridge) without touching Claude. |
| `/look` | Inspect Chrome viewport via Puppeteer — DOM-first, not screenshot-first. Console log capture. |
| `/plan` | Multi-phased project planning with fresh-eyes reconciliation. Supports `review` mode for `{{bracketed}}` change proposals. |
| `/push` | Commit and push to remote. |
| `/research` | Deep web research with parallel agents, 6-tool stack (Brave, Exa, Firecrawl, Tavily, Perplexity, WebFetch). Subagents write their own reports under an anti-fabrication contract; orchestrator writes synthesis only. Accumulates source knowledge across runs. |
| `/sync` | Propagate kit changes to downstream projects. Diffs, preserves project customizations, merges intelligently. Kit-only — not installed to downstream projects. |
| `/vibe-audit` | Codebase health + security audit with self-learning Bayesian pattern tracking. |
| `/video-editor` | Transcript-based video editing via Palmier Pro MCP. Transcribe, script, cut, caption. |

### Infrastructure

- **Zero-config defaults** — VS Code recommends the Claude Code extension on open, permissions are set to bypass prompts, and Opus 4.6 is the default model. Clone and go.
- **Session hooks** — On start: loads brain state (focus, tasks, questions, mantra), cleans up stale sessions, loads last session's work for context continuity, prompts Claude to review and update the mantra if warranted. On end: records session timestamp.
- **MCP servers** — 5 research tools (Brave, Exa, Firecrawl, Tavily, Perplexity) pre-configured in `.mcp.json`
- **Cowork structure** — Brain DB, plans, research, architecture observatory, vibe-audit databases
- **CLAUDE.md template** — Project documentation with mantra block

## Recommended Workflow

The skills are designed to chain together in a natural sequence: **understand → plan → build**.

### The full loop

```
/brainstorm  →  /research  →  /plan  →  implement  →  /commit
```

Start with `/brainstorm` to explore the problem space conversationally. Decisions, questions, and insights that emerge are captured in the brain DB automatically. If you need external evidence — how an API works, what the tradeoffs are between libraries, what others have done — run `/research` to get a sourced report.

Once the shape of the work is clear, `/plan` generates a phased implementation plan grounded in the codebase. It reads brain DB context (decisions, open questions, prior brainstorms) so the plan reflects what you've already worked through rather than starting from scratch.

Then build. The plan tracks progress, and `/plan N` resumes with a fresh-eyes reconciliation — re-reading the plan against the current state of the code to catch drift between what was planned and what was actually built.

### Reviewing plan changes

Plans are collaborative — you can propose changes directly in the plan file by wrapping edits in `{{double curly braces}}`, then running `/plan review`. Claude reviews each bracketed change for clarity, feasibility, and coherence with the rest of the plan, then applies the approved edits and removes the markers.

```
# In your plan file, add/edit with brackets:
- [ ] **API design** — {{use GraphQL instead of REST for the query layer}}

# Then run:
/plan review
```

This is useful when you've been thinking about the plan offline and want to batch-update it with Claude validating that nothing conflicts or needs downstream changes.

### Shorter variants

Not every task needs the full loop:

- **Quick feature:** `/plan` → implement → `/commit`
- **Exploratory question:** `/brainstorm` (done — insights saved to brain)
- **Technology decision:** `/research` → `/brainstorm` (discuss findings) → decision logged
- **Bug fix:** just fix it → `/commit`

### Compound lessons

At the end of substantive sessions, the session-start hook prompts Claude to consider whether a reusable lesson or pattern emerged. If one did, it's written as a brain insight tagged `lesson` — one sentence stating the rule, then why it matters and how to apply it. If nothing novel was learned, the step is skipped entirely. Over time, these accumulate into a searchable catalog of meta-learning: not just what happened, but what to do differently next time.

Inspired by the "compound step" from [Every Inc's Compound Engineering](https://github.com/everyinc/compound-engineering-plugin) methodology.

### What ties it together

The **brain DB** is the connective tissue. `/brainstorm` writes decisions and questions into it. `/research` indexes reports in it. `/plan` reads from it. Session hooks load the current state on startup. Nothing is lost between sessions — context accumulates instead of resetting.

Plans are numbered, dated markdown files (`cowork/plans/001_2025-06-20_auth-redesign.md`). Research runs are numbered, dated **folders** (`cowork/research/002_2025-06-22_oauth-providers/`) containing individual agent reports (`agent-official-docs.md`, `agent-community.md`, etc.) and a synthesized `SUMMARY.md`. Both live in the repo alongside your code — any collaborator or future Claude session can read them for full context on why something was built the way it was.

## Installation

### New project

```bash
cd /path/to/your/project
bash /path/to/tb-claude-kit/install.sh
```

### Existing project

Same command — the installer detects drifted files and prompts you to update, keep, or view the diff.

### Updating

To pull updates from the kit into an existing project, re-run the installer. It detects drifted files and shows unified diffs. In an interactive terminal, you're prompted per file (`[u]pdate / [k]eep / [d]iff`). Non-interactive shells (e.g. Claude Code) get full diffs in the output.

**Kit-managed files** (skills, hooks, schemas, scripts) can be auto-updated with `--yes`. **Project files** (CLAUDE.md, settings.json, .mcp.json, GUARDRAILS.md) are never auto-updated — diffs are shown for manual review.

```bash
# Interactive — prompt per drifted file
bash /path/to/tb-claude-kit/install.sh

# Auto-update kit files + enable integrations
bash /path/to/tb-claude-kit/install.sh --yes

# Report drifts without changing anything
bash /path/to/tb-claude-kit/install.sh --dry-run
```

### Post-install

1. Edit `CLAUDE.md` — describe your project
2. Edit `.mcp.json` — add your API keys for Brave, Firecrawl, and Perplexity (Exa and Tavily use OAuth, no keys needed)
3. Edit `cowork/vibe-audit/GUARDRAILS.md` — customize for your architecture
4. Edit `cowork/architecture/seed.sql` — define your project's subsystems for `/cto`
5. Edit `.claude/skills/kill/SKILL.md` — set your dev server ports

## Brain DB

The brain is a SQLite database at `cowork/brain/BRAIN.db` with FTS5 full-text search.

### Entry types
- `note` — general observations, brainstorm summaries
- `decision` — choices with rationale (permanent — supersede, don't edit)
- `question` — open questions to resolve (resolve into decisions)
- `insight` — patterns or realizations worth preserving
- `task` — work items with pillar, priority, plan linking
- `milestone` — significant project events

### Tier system (computed, not manual)
- **hot** — focus items + plan-linked tasks with momentum
- **warm** — importance >= 6, or created within 14 days
- **cold** — everything else that's active
- **archived** — done, dropped, or superseded

### Mantra
Claude's self-authored context — what Claude thinks is important that CLAUDE.md doesn't say. Updated during `/brain audit` and `/brain done`. Synced to `cowork/brain/MANTRA.md` and optionally to a `<!-- BEGIN:mantra -->` block in CLAUDE.md.

## Cowork Directory

```
cowork/
  brain/
    BRAIN.db          # Knowledge database (SQLite + FTS5)
    BRAIN.md          # Auto-generated readable export
    MANTRA.md         # Claude's self-authored context
    schema.sql        # DB schema for initialization
    USAGE.md          # Schema reference and common queries
  plans/              # Numbered plan files (NNN_YYYY-MM-DD_topic.md)
  research/           # Numbered research folders (NNN_YYYY-MM-DD_topic/)
                      #   agent-*.md      — individual subagent reports
                      #   SUMMARY.md      — synthesized final report
  architecture/
    CTO.db            # Architecture observatory database (created on first /cto run)
    PROCEDURE.md      # Full scan/synthesize/output procedure
    schema.sql        # CTO.db schema
    seed.sql          # Project-specific context (edit per project)
    architecture.html # Generated HTML with Mermaid diagrams (output)
    YYYY-MM-DD_*.md   # Dated markdown summaries (accumulate over runs)
  vibe-audit/
    VIBE-AUDIT.db     # Self-learning audit database
    PROCEDURE.md      # Full audit procedure
    GUARDRAILS.md     # Architecture checklist (customize per project)
    schema.sql        # Audit DB schema
    seed.sql          # Builtin scan patterns
  video/              # Video editing projects (transcripts, scripts, artifacts)
  staged.json         # Changelog entries awaiting release
```

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

The skill ships with `caption-dictionary.json` in the skill folder (`.claude/skills/video-editor/caption-dictionary.json`). Customize it for your project:

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
4. **Firecrawl** — sign up at https://firecrawl.dev, get API key, add to `.mcp.json`
5. **Perplexity** — sign up at https://perplexity.ai, get API key from settings, add to `.mcp.json`

The skill works with any subset of these tools — it gracefully adapts when tools are missing. But the full stack gives the best results: keyword search (Brave) + semantic search (Exa) + fast lookup (Tavily) + orientation (Perplexity) + deep extraction (Firecrawl) + free fallback (WebFetch).

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

These skills were intentionally excluded from the kit because they're deeply project-specific. Use the patterns below as templates when building them for your project.

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

