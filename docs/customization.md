# Customizing

Writing rules, extra MCP servers, and per-project skills worth adding on top of the kit.

### Writing rules

Named sets of rules for what Claude writes, each scoped to where it applies: one for client Slack messages
and emails, another for wiki pages, and so on. The kit ships the mechanism, never anyone's rules. The
session-start hook adds every active set to the session beside `KIT.md` (`scripts/writing-rules`).

A set is one Markdown file:

```markdown
---
name: client-messages
applies: Slack messages, emails, support replies and issue comments a client reads
---
- One main point per message, stated first.
- No thanks, greetings or pleasantries.
```

Sets come from two places:

- **Yours**, across every project: a folder at `~/.claude/writing`, or wherever `$TB_CLAUDE_KIT_WRITING`
  points. Make it a link to a folder in a repo you own, so your rules are versioned without shipping
  with the kit. `install.sh` asks for that folder once a machine and makes the link (Enter for none is
  remembered in `~/.claude/writing.none`); by hand it is `ln -s ~/dev/<your-repo>/.claude/writing
  ~/.claude/writing`. On a new machine, a link whose folder is not cloned yet is named at every session
  start until it is.
- **The project's**: `.claude/writing/*.md`. A set with one of your sets' names replaces it here; any
  other name is a set for this project alone.

Small changes need no file: `writing` in `.claude/kit.json` adjusts a set by name.

```json
"writing": {
  "client-messages": { "add": "- This client prefers bullets to paragraphs." },
  "wiki": { "applies": "the engagement wiki only" },
  "release-notes": { "off": true }
}
```

`~/.claude-kit/scripts/writing-rules --list` prints the sets active in the current project, where each
came from and what it applies to.

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

This is **lane 3** from [Configuration](install.md#where-project-specific-behavior-belongs): a project-owned
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

**Puppeteer server:** Included at `scripts/puppeteer-server.cjs`. Requires `npm install puppeteer` in your project. Launches headed Chrome with an isolated profile per project (`~/.claude-chrome/<profile>/`), auto-assigns a free port in the 9615-9634 range, and exposes an HTTP API (commands are listed in the [`/look` reference](skills.md#look-co-browser-look)).

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
