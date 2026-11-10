# Skill reference

The larger skills in detail. `/plan` and `/swarm` have their own page: [plan-and-swarm.md](plan-and-swarm.md).

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

## Cross-artifact (`/cross-artifact`)

People share claude.ai artifacts with the address they know, and that is often not the account your
Claude Code runs as. The Artifact tool only opens what its own account was shared, and for an artifact
someone else owns it gives a summary, not the code. `/cross-artifact` reads them through the other
account instead, live, and saves nothing.

```bash
~/.claude-kit/scripts/cross-artifact sign-in work     # once: sign in in the window that opens
~/.claude-kit/scripts/cross-artifact visit <link>     # Claude opens the artifact in that account's Chrome
~/.claude-kit/scripts/cross-artifact read <link>      # its files, then the page's source
```

- **An account is a Chrome profile**, in `~/.cross-artifact/<name>/`, signed in once by you. The login
  is that profile's own cookie; nothing else stores it, and it survives a quit.
- **The Chrome is an ordinary one**, started behind your other windows with a DevTools port on
  localhost. claude.ai's Cloudflare check refuses automated and headless browsers, so the skill never
  uses one, and when the check does come up it stops and asks you to click it.
- **What it reads:** the artifact's page as served, each script, stylesheet, data file and image it
  loaded (`--file`), and the page after it has run (`--dom`). Not the owner's version history or
  comment threads.
- **Quit that Chrome with Cmd-Q or `cross-artifact quit`**, never a kill, or the sign-in may be lost.
  Its profiles sit outside `~/.claude-chrome`, so `/kill` leaves them alone.
- Needs Google Chrome and Node 22+. macOS is what it was built on; Linux is untested.

## Lid Sleep (`lidsleep`)

A MacBook sleeps when its lid closes, which stops long jobs, downloads and agent runs. `lidsleep`
switches that off and back on. It's a terminal command, not a skill.

```bash
~/.claude-kit/scripts/install-lidsleep   # once per machine: links ~/.local/bin/lidsleep to the kit
lidsleep                                 # current state, then ↑/↓ and Enter to change it (q to cancel)
```

```
Lid sleep: ON — Mac sleeps normally when the lid closes

    Enable lid sleep (normal)
  > Disable lid sleep (stay awake)
    Cancel
```

- **Under the hood** it runs `sudo pmset -a disablesleep 1|0`, so changing it asks for your
  password. The setting survives restarts until you switch it back.
- **The installer makes a link, not a copy**, so pulling the kit updates the command.
  `BIN_DIR=<dir>` installs somewhere else; `--uninstall` removes the link.
- **With lid sleep off, don't put the Mac in a bag.** It can't cool itself there, and on battery
  it drains without ever sleeping.

---

## Dictate Around (`dictate-around`)

macOS Dictation types live into whatever has focus, and a click anywhere ends it. `dictate-around`
lets you talk into one text field while you click, scroll and switch apps: it records while you
move around, then pastes the text where you started. It's a Hammerspoon module, not a skill.

```bash
~/.claude-kit/scripts/install-dictate-around                       # once per machine
~/.claude-kit/scripts/install-dictate-around --list-mics           # inputs connected right now
~/.claude-kit/scripts/install-dictate-around --mic "<device>"       # record from this input
~/.claude-kit/scripts/install-dictate-around --hotkey ctrl+alt+d    # any hotkey (see below)
~/.claude-kit/scripts/install-dictate-around --status              # installed, listening, which mic
```

1. **Press the hotkey** in a text field (double-tap Fn by default). A tink, and 🎙 in the menu
   bar: it's recording.
2. **Move around.** Nothing is typed while you talk, so clicks can't interrupt it.
3. **Press the hotkey again.** A pop and ✍︎ while it transcribes, then the text is pasted into the
   field where you started and your clipboard is put back.

- **Any hotkey.** Two forms:
  - **Double-tap a modifier:** `double-fn` (default), `double-cmd`, `double-alt`, `double-ctrl`,
    `double-shift`, or one side only: `double-rightcmd`, `double-leftalt`, `double-rightshift`...
    A tap only counts if nothing else is pressed with it, so normal shortcuts still work.
  - **A key combination**, pressed once to start and again to stop: `ctrl+alt+d`,
    `cmd+shift+space`, `f13`. Modifiers are `cmd`, `alt` (or `option`), `ctrl`, `shift`, `fn`.

  A spec it can't read shows an alert and `--status` reports the error.
- **Any mic, without changing the system input.** `--mic` records from that device by name while
  everything else keeps the default input. Without it, or with `--mic default`, it records from the
  system input. `--list-mics` prints the exact names.
- **Transcription runs on your Mac** with whisper.cpp (`ggml-large-v3-turbo-q5_0`, about 550 MB,
  in `~/.local/share/whisper/`): no account, no network, about a second for a sentence on Apple
  silicon. Text lands when you stop, not word by word.
- **Settings** are in `~/.config/claude-kit/dictate-around.json`, every key optional: `hotkey`,
  `mic`, `model`, `language`, `returnToCurrent` (after pasting, go back to where you were; default
  off), `tapMax` and `doubleTapWindow` (double-tap timing). `--mic` and `--hotkey` write it for you
  and reload; edit it by hand and use Hammerspoon's Reload Config. Keep the file in your config repo
  with `kit-config` if you want it on every machine.
- **What only you can do**, which the installer prints: turn on Hammerspoon under Privacy &
  Security > Accessibility, allow the microphone on first use, and tick *Launch Hammerspoon at
  login*. With an Fn hotkey, also set Keyboard > *Press 🌐 key to* to **Do Nothing** (unset means
  Emoji, which opens on every tap) and turn the Dictation shortcut off.
- **If it can't get back to the original app**, it leaves the text on your clipboard and says so,
  rather than pasting somewhere else.
- **The installer makes a link, not a copy**, so pulling the kit updates the module. It adds
  Hammerspoon, ffmpeg and whisper-cpp with Homebrew when they're missing, and a marked block to
  `~/.hammerspoon/init.lua`. `--uninstall` removes the block and the link and leaves the rest.

---

## Disk (`/disk`)

`/disk` shows where your Mac's disk space went, on every drive, internal and external. It says what
created each big item, then wins the space back the way that lasts. Nothing is deleted or moved
unless you pick it.

### How it works

- **One map per machine.** `/disk setup` asks a few questions about each drive and writes
  `~/.config/claude-kit/disk.json`:
  - its role: `hot` for active work, `warm` for things moved off a hot drive, `archive`;
  - the free space it must keep (its floor);
  - whether it is always attached, like a desktop's dock drive, or comes and goes.

  Drives are keyed by volume UUID, so renaming one changes nothing. It is not a project setting,
  so it never sits in a repo. Keep it in your [own config repo](install.md#your-own-config-one-private-repo-every-machine)
  to carry it between machines.
- **A known-items list.** `.claude/skills/disk/known-items.json` names about 50 things that fill
  Macs. For each one it says what creates it, whether it comes back on its own, and its best
  action:
  - development caches;
  - Xcode, simulators, Docker and Colima;
  - model caches;
  - app caches;
  - leftover device-restore files;
  - worktrees.

  Add your own entries under `knownItems` in `disk.json`. One with the same `id` replaces the
  shipped entry.
- **`/disk report`** changes nothing. It lists:
  - each drive's free space against its floor;
  - recommendations grouped by drive, with the drive under the most pressure first;
  - things that are yours to judge (browser profiles, app data, Downloads);
  - big folders the list doesn't know, named by app;
  - worktrees in every project.
- **`/disk`** shows the report, then carries out the recommendations you pick. In order of
  preference:
  1. Delete what regenerates.
  2. Redirect the tool that makes it to the warm drive (an env var or the tool's own setting).
  3. Move a folder there with a symlink left in its place.
- **A warning at session start.** When a drive drops below its floor, the next session says so in
  one line and names the biggest win from the last report. It costs about 30 ms and is silent
  otherwise.

### Worktrees on an external drive

Every git worktree an agent makes is a full checkout, usually with its own `node_modules`. A long
swarm leaves dozens behind. When a `warm` drive is always attached, `/disk setup` offers to put
every worktree there:
- **Claude Code's own** (`--worktree`, subagents with `isolation: "worktree"`): through a
  `WorktreeCreate`/`WorktreeRemove` hook pair, since Claude Code has no setting for the location
  and refuses a symlinked `.claude/worktrees`.
- **The kit's own** (`/plan` and `/swarm`): through `scripts/wt-path`.

Both go to `<drive>/worktrees/<repo>-<hash>/<name>`, and both fall back to the repo when the drive
isn't mounted.

`scripts/worktree-sweep` holds the cleanup rules that `/prune`, `/swarm` and `/disk` share. A
worktree is removed only when all of these hold:
- its work has landed, whether by merge, cherry-pick or rebase;
- it has no uncommitted changes;
- nothing is running in it;
- it has been idle for 2 hours;
- it is not held by a live session's lock.

Worktrees named `slot-*` or `pool-*`, pools a project's own tooling reuses, are never removed.
Change that with `worktreeKeep` in `disk.json`.

### Commands

```bash
~/.claude-kit/scripts/disk status                   # drives, free space, floors
~/.claude-kit/scripts/disk report                   # the full report (a few minutes on a full disk)
~/.claude-kit/scripts/disk env HF_HOME /Volumes/External/caches/huggingface   # one marked block in ~/.zshenv
~/.claude-kit/scripts/disk move ~/Movies --dry-run  # copy, verify, symlink; --dry-run first
~/.claude-kit/scripts/worktree-sweep [repo]         # what can go, and why; --apply removes it
```

### Setup notes

- **Full Disk Access.** Mail, Messages and some app containers can't be measured without it. The
  report marks those folders. To measure them, give your terminal or editor Full Disk Access in
  System Settings → Privacy & Security.
- **`projectRoots`** in `disk.json` lists where your projects live, on any drive.
  `/clear-cache` and `worktree-sweep` read it too, and it takes precedence over
  `clearCache.projectRoots` in a project's `kit.json`.
