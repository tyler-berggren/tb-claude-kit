# TB Claude Kit

A reusable project kit to give Claude Code a brain, eyes, and a brainstorm/research > plan > implement workflow

Developed through ongoing trial and error by [Tyler Berggren](https://github.com/tyler-berggren).

## What's Included

### Skills (9)

| Skill | Purpose |
|---|---|
| `/brain` | Project knowledge DB — decisions, tasks, questions, insights, milestones. Single source of truth. |
| `/brainstorm` | Conversational idea development with live brain DB capture. |
| `/commit` | Stage all files and commit with auto-generated message. |
| `/kill` | Kill dev processes (servers, watchers) without touching Claude. |
| `/look` | Inspect Chrome viewport via Puppeteer — DOM-first, not screenshot-first. |
| `/plan` | Multi-phased project planning with fresh-eyes reconciliation. |
| `/push` | Commit and push to remote. |
| `/research` | Web research with parallel agents (Brave, Exa, WebSearch). Numbered reports. |
| `/vibe-audit` | Codebase health + security audit with self-learning Bayesian pattern tracking. |

### Infrastructure

- **Session hooks** — Brain DB state loaded on start, session timestamps on end
- **MCP servers** — Exa (semantic search) + Brave Search (keyword + Reddit/HN access)
- **Cowork structure** — Brain DB, plans, research, vibe-audit databases
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

### Shorter variants

Not every task needs the full loop:

- **Quick feature:** `/plan` → implement → `/commit`
- **Exploratory question:** `/brainstorm` (done — insights saved to brain)
- **Technology decision:** `/research` → `/brainstorm` (discuss findings) → decision logged
- **Bug fix:** just fix it → `/commit`

### What ties it together

The **brain DB** is the connective tissue. `/brainstorm` writes decisions and questions into it. `/research` indexes reports in it. `/plan` reads from it. Session hooks load the current state on startup. Nothing is lost between sessions — context accumulates instead of resetting.

Plans and research reports are numbered, dated markdown files (`cowork/plans/001_2025-06-20_auth-redesign.md`, `cowork/research/002_2025-06-22_oauth-providers.md`) that live in the repo alongside your code. They travel with the project through git — any collaborator or future Claude session can read them for full context on why something was built the way it was.

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

1. Edit `.mcp.json` — add your Brave API key
2. Edit `CLAUDE.md` — describe your project
3. Edit `cowork/vibe-audit/GUARDRAILS.md` — customize for your architecture
4. Edit `.claude/skills/kill/SKILL.md` — set your dev server ports

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
  research/           # Numbered research reports (NNN_YYYY-MM-DD_topic.md)
  vibe-audit/
    VIBE-AUDIT.db     # Self-learning audit database
    PROCEDURE.md      # Full audit procedure
    GUARDRAILS.md     # Architecture checklist (customize per project)
    schema.sql        # Audit DB schema
    seed.sql          # Builtin scan patterns
  staged.json         # Changelog entries awaiting release
```

## "Look" Co-Browser (`/look`)

A shared Chrome viewport that Claude can inspect programmatically while you see the same browser window. You drive — navigating pages, setting mobile viewports via Chrome's device toolbar. Claude inspects — reading computed styles, DOM structure, and box models through a local HTTP API.

### How it works

The co-browser is a Puppeteer server (`scripts/puppeteer-server.cjs`) that launches a headed Chrome instance and exposes an HTTP API on `localhost:9615`. Claude uses the `/look` skill to query this API with `curl` commands — no MCP server or browser extension needed.

```
You (Chrome window)          Claude (terminal)
    │                            │
    ├── navigate, scroll,        │
    │   set mobile viewport      │
    │                            ├── curl :9615/status
    │                            ├── curl :9615 -d '{"command":"inspect","selector":".nav"}'
    │                            ├── edit source file
    │                            ├── (hot reload)
    │                            └── curl :9615 -d '{"command":"inspect","selector":".nav"}'
    │                                 └── verify fix
```

### Starting the co-browser

Launch manually, or build a `/dev` skill (see Customization section) that starts your dev server + the co-browser together:

```bash
# Launch with a starting URL
node scripts/puppeteer-server.cjs http://localhost:3000

# Or launch without — navigate manually in the Chrome window
node scripts/puppeteer-server.cjs
```

Chrome opens with a separate user data dir (`~/.claude-chrome-debug`) so it doesn't interfere with your normal browser profile.

### API

All commands are POST requests to `http://127.0.0.1:9615` with a JSON body. There's also a GET `/status` endpoint.

| Command | Purpose | Example |
|---------|---------|---------|
| `inspect` | Computed styles + box model for a selector | `{"command":"inspect","selector":".hero"}` |
| `dom` | HTML structure + child elements | `{"command":"dom","selector":".hero","children":true}` |
| `screenshot` | Viewport or element capture (saves PNG) | `{"command":"screenshot","selector":".hero"}` |
| `eval` | Run arbitrary JS in page context | `{"command":"eval","expression":"document.querySelectorAll('.card').length"}` |
| `status` | Current URL, viewport size, scroll position | GET `/status` |

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

## Customization

### MCP Servers

The installer can configure these MCP servers for `/research` and general web access. Both are optional — the kit works without them, but research quality improves significantly with at least one.

**Exa (semantic search)**
- HTTP transport: `https://mcp.exa.ai/mcp`
- Authentication via Exa account (OAuth on first use)
- Best for: conceptual exploration, finding related work

**Brave Search (keyword search)**
- stdio transport via `@modelcontextprotocol/server-brave-search`
- Requires API key in `.mcp.json`
- Best for: Reddit/HN content, news, community discussions
- Get a key at: https://brave.com/search/api/

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
- Launch a Puppeteer server on port 9615 pointing at the dev server URL
- Both processes run in the background — the skill returns after confirming both are up
- Pairs with `/kill` (to tear down) and `/look` (to inspect)

**Flow:**
1. Check if the dev port is already in use — kill if so (restart case)
2. Start the dev server: `cd <project-dir> && npm run dev` (background)
3. Wait for the server to respond (curl health check)
4. Kill any stale Puppeteer server on 9615
5. Launch Puppeteer server pointed at the dev URL (background)
6. Wait for Puppeteer to be ready
7. Report both URLs (dev server + Puppeteer)

**Puppeteer server:** Included at `scripts/puppeteer-server.cjs`. Requires `npm install puppeteer` in your project. Launches headed Chrome with a separate user data dir, accepts an optional URL argument, and exposes an HTTP API on `localhost:9615` with commands: `inspect` (computed styles + box model), `dom` (HTML structure), `screenshot` (viewport/element capture), `eval` (JS execution), and GET `/status` (current URL, viewport, scroll).

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
   lsof -iTCP:9615 -sTCP:LISTEN -t 2>/dev/null | xargs /bin/kill 2>/dev/null; sleep 1
   node scripts/puppeteer-server.cjs http://localhost:3000
   \`\`\`

6. Wait for Puppeteer:
   \`\`\`bash
   for i in 1 2 3 4 5 6 7 8 9 10; do curl -s http://127.0.0.1:9615/status > /dev/null 2>&1 && break; sleep 1; done
   \`\`\`

7. Report:
   - Dev server: http://localhost:3000
   - Puppeteer: http://127.0.0.1:9615
   - Chrome is open with a debug profile — set mobile viewport via Chrome's device toolbar

## Rules
- No confirmation needed — execute immediately
- If the port is in use, kill and restart
- Exit codes 143/144 from killed background tasks are expected
```

**Customization points:**
- Dev port (3000, 4747, 5173, 8080, etc.)
- Dev command (`npm run dev`, `npx vite`, `npx next dev`, `npx wrangler dev`, etc.)
- Puppeteer server script path
- Whether to pass a URL argument to Puppeteer or let the user navigate manually

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

