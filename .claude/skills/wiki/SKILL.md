---
name: wiki
description: Create and maintain an organic project wiki — updates pages affected by recent work, scans for gaps and staleness, reconciles the index. Shape emerges from the project, not a template.
argument-hint: "[audit | deploy | init | <page-name>] or empty for hybrid update"
---

## Wiki state
!`if [ -d wiki ]; then echo "wiki/ exists ($(find wiki -name '*.md' | wc -l | tr -d ' ') pages)"; [ -f wiki/README.md ] && echo "Index: wiki/README.md" || echo "Index: MISSING"; [ -f wiki/STYLE.md ] && echo "Style guide: wiki/STYLE.md" || echo "Style guide: not set"; else echo "No wiki/ directory — run /wiki init to create one"; fi`

## Recent changes
!`git diff --stat HEAD~3..HEAD 2>/dev/null | tail -10 || echo "No recent commits"`

---

# Wiki

Maintain an organic project wiki that documents the system as it evolves. The wiki's shape emerges from the work — pages are created as topics arise, not from a fixed template. Every invocation does both targeted updates (what just changed) and a holistic scan (what's stale or missing).

## Input

Optional argument: `$ARGUMENTS`

## Dispatch

| Argument | Behavior |
|---|---|
| _(empty)_ | **Hybrid update** — targeted updates from recent work + gap/staleness scan |
| `audit` | **Deep audit** — full wiki-vs-codebase reconciliation, heavier than the default scan |
| `deploy` | **Deploy** — build static HTML site and deploy to Cloudflare Pages |
| `init` | **Initialize** — create `wiki/` with README.md and optional STYLE.md scaffold |
| `<page-name>` | **Single page** — create or update a specific page by name |

---

## Wiki Location

The wiki lives at `wiki/` in the project root by default. Override with `wiki.root` in
`.claude/kit.json`:

```json
{ "wiki": { "root": "docs/wiki" } }
```

Resolve the wiki root at the start of every invocation:

```bash
WIKI_ROOT=$(jq -r '.wiki.root // "wiki"' .claude/kit.json 2>/dev/null || echo "wiki")
```

---

## Initialize

Usage: `/wiki init`

1. Create the wiki root directory if it doesn't exist.

2. Create `$WIKI_ROOT/README.md` — the table of contents. Start with:
   ```markdown
   # Wiki

   Project documentation. Pages are created and maintained as the project evolves.

   ## Pages

   _(no pages yet)_
   ```

3. Check if a `STYLE.md` scaffold exists in the kit or project:
   - If `$WIKI_ROOT/STYLE.md` already exists, leave it alone
   - If a scaffold source is configured (see Style Guide below), copy it
   - Otherwise, create a minimal default:
     ```markdown
     # Wiki Style Guide

     How to write and maintain this wiki.

     ## Audience

     _Define who reads this wiki and what they need from it._

     ## Voice

     - Write in plain language
     - Explain what things do, not how they're implemented
     - Use the project's own terminology, not developer jargon

     ## Page conventions

     - One topic per page
     - Start each page with a one-sentence summary
     - Use headings to make pages scannable
     - Link between pages when topics connect
     ```

4. Report what was created.

---

## Deploy

Usage: `/wiki deploy`

Build the wiki as a static HTML site and deploy it to Cloudflare Pages.

### Prerequisites

- `wiki/` must exist and contain at least one `.md` file
- `scripts/wiki-build/` must exist (scaffolded by `/repo`)
- Cloudflare credentials must be in `.env` — the script checks for either prefix:
  - `CLOUDFLARE_ACCOUNT_ID` or `CF_ACCOUNT_ID`
  - `CLOUDFLARE_API_TOKEN` or `CF_API_TOKEN`

### Procedure

1. Resolve the wiki root:
   ```bash
   WIKI_ROOT=$(jq -r '.wiki.root // "wiki"' .claude/kit.json 2>/dev/null || echo "wiki")
   ```

2. Verify prerequisites:
   ```bash
   [ -d "$WIKI_ROOT" ] && [ -d scripts/wiki-build ] || exit 1
   ```

3. Load Cloudflare credentials from `.env`:
   ```bash
   set -a; . ./.env; set +a
   CF_ACCT="${CLOUDFLARE_ACCOUNT_ID:-$CF_ACCOUNT_ID}"
   CF_TOKEN="${CLOUDFLARE_API_TOKEN:-$CF_API_TOKEN}"
   ```
   If neither variable is set, stop and tell the user to add CF credentials to `.env`.

4. Resolve the CF Pages project name. Check `kit.json` first, then derive from the repo
   directory name:
   ```bash
   PROJECT=$(jq -r '.wiki.pagesProject // empty' .claude/kit.json 2>/dev/null)
   if [ -z "$PROJECT" ]; then
     PROJECT="$(basename "$(pwd)")-reinstall-work-wiki"
   fi
   ```

5. Resolve the client name for the sidebar title. Check `kit.json`, then fall back to the
   repo directory name (title-cased):
   ```bash
   CLIENT_NAME=$(jq -r '.wiki.clientName // empty' .claude/kit.json 2>/dev/null)
   ```
   If not set, derive from the repo directory name — convert kebab-case to title case
   (e.g. `land-advisors` → `Land Advisors`).

6. Run the build:
   ```bash
   cd scripts/wiki-build && npm install --silent && node build.mjs "../../$WIKI_ROOT" ../../_wiki-site --name "$CLIENT_NAME"
   ```

7. Deploy to Cloudflare Pages:
   ```bash
   cd ../..
   CLOUDFLARE_ACCOUNT_ID="$CF_ACCT" CLOUDFLARE_API_TOKEN="$CF_TOKEN" \
     npx wrangler pages deploy _wiki-site --project-name="$PROJECT" --branch=main
   ```
   The first deploy auto-creates the Pages project.

8. Clean up the build output:
   ```bash
   rm -rf _wiki-site
   ```

9. Report the live URL: `https://<project-name>.pages.dev`

---

## Hybrid Update (default)

Usage: `/wiki` (no arguments)

This is the core procedure — every invocation runs both halves.

### Phase 1 — Context gathering

1. **Read the style guide** if `$WIKI_ROOT/STYLE.md` exists. All writing in this invocation
   follows it.

2. **Assess recent work.** Gather what changed:
   ```bash
   git diff --name-only HEAD~3..HEAD 2>/dev/null
   git log --oneline -5 2>/dev/null
   ```
   Also consider the current conversation — what was just built, fixed, or changed.

3. **Read the wiki index** (`$WIKI_ROOT/README.md`) and scan existing page filenames:
   ```bash
   find "$WIKI_ROOT" -name '*.md' -not -name 'README.md' -not -name 'STYLE.md' | sort
   ```

4. **Read all existing wiki pages.** The wiki should be small enough to read in full.
   If it exceeds 30 pages, read only the index and pages likely affected by recent changes.

### Phase 2 — Targeted updates

For each area touched by recent work:

1. **Does a wiki page already cover this area?**
   - Yes → Read it. Is it still accurate after the changes? Update if not.
   - No → Should this area have a page? Not everything deserves one. A page earns its
     place when a reader would look for it — a major component, an integration, a
     workflow, a data model. Minor utilities and internal helpers usually don't.

2. **Write or update the page.** Follow the style guide. Key principles:
   - Write from the reader's perspective, not the developer's
   - Explain *what* and *why*, not implementation details that change
   - Use the project's own vocabulary — if the codebase calls it a "pipeline," don't
     call it a "workflow" in the wiki
   - Link to other wiki pages when topics connect (standard markdown links)
   - Start each page with a one-sentence summary of what this page covers

3. **Don't over-document.** A wiki page that restates what the code already says is
   noise. Pages should explain things the code *can't* tell you: why something exists,
   how components relate, what the business context is, what decisions were made.

### Phase 3 — Gap and staleness scan

Walk the project and compare against wiki coverage:

1. **Scan the codebase for major components.** Look at:
   - Top-level directories and their purpose
   - Configuration files (what services, integrations, infrastructure)
   - Database schemas (what data exists)
   - API routes / endpoints (what the system exposes)
   - Key dependencies (what external services it connects to)

2. **Compare against the wiki.** For each major component:
   - Is it documented? → Note the gap
   - Is the documentation current? → Check for renamed files, removed features,
     changed integrations, updated schemas

3. **Check for dead pages.** Does any wiki page describe something that no longer exists?
   - Removed feature → Delete the page
   - Renamed/moved feature → Update the page
   - Significantly changed → Rewrite the relevant sections

4. **Prioritize.** Don't try to fill every gap in one pass. Address:
   - Stale pages first (wrong documentation is worse than missing documentation)
   - Then the most important gaps (core components, integrations, data models)
   - Note remaining gaps at the end for future passes

### Phase 4 — Reconcile the index

Update `$WIKI_ROOT/README.md`:
- List every page with a one-line description
- Group pages logically (by area, not alphabetically, unless the project is small)
- Remove entries for deleted pages
- Add entries for new pages

The index is the table of contents. A reader should be able to scan it and find what
they need in under 10 seconds.

### Phase 5 — Report

Summarize what happened:
- Pages created (with one-line descriptions)
- Pages updated (with what changed)
- Pages deleted (with why)
- Gaps noted but not yet filled (if any)

---

## Deep Audit

Usage: `/wiki audit`

A heavier version of the hybrid update. Use when you suspect the wiki has drifted
significantly, or periodically as a health check.

Same as the hybrid update, but with these differences:

1. **Phase 1 expands.** Instead of looking at recent changes, audit the entire codebase.
   Read every source file's purpose, every config, every schema.

2. **Phase 3 is exhaustive.** Don't prioritize — address every gap and every stale page.
   Create all missing pages, update all stale ones, delete all dead ones.

3. **Style consistency pass.** After all content updates, re-read every page and check
   for consistency: terminology, voice, depth, formatting. Fix inconsistencies.

4. **Cross-reference check.** Verify all inter-page links work. Check that pages that
   should reference each other do.

---

## Single Page

Usage: `/wiki <page-name>`

Create or update a specific page.

1. Resolve the page: check if `$WIKI_ROOT/<page-name>.md` exists.
   If not, check for partial matches (e.g., "auth" matches "authentication.md").

2. If the page exists, read it and the relevant code/config, then update it.

3. If the page doesn't exist, assess whether it should. Read the relevant area of the
   codebase, then write the page.

4. Update the index to reflect any changes.

---

## Style Guide

The style guide at `$WIKI_ROOT/STYLE.md` controls how wiki pages are written. It is
optional but recommended. When present, every wiki write follows it.

The style guide itself is organic — it can be updated as the project evolves. Common
things to specify:

- **Audience** — Who reads this wiki? Technical level? Role?
- **Voice** — Tone, perspective, terminology preferences
- **Page conventions** — Structure, heading levels, how to handle code examples
- **Terminology** — Project-specific terms and their definitions
- **What not to document** — Things that belong in code comments, not the wiki

### Style Guide Scaffolding

Projects can configure a scaffold source in `.claude/kit.json`:

```json
{ "wiki": { "styleScaffold": "path/to/STYLE-TEMPLATE.md" } }
```

When `/wiki init` runs and no `STYLE.md` exists, it copies from this path. This lets
an organization maintain a standard starting point while allowing per-project evolution.

---

## Rules

- **No permission needed** — Execute immediately without asking.
- **Follow the style guide** — If `STYLE.md` exists, every write follows it. If it doesn't,
  use sensible defaults (plain language, reader's perspective, one topic per page).
- **Organic shape** — Never impose a fixed page structure. Pages emerge from the project.
  Don't create placeholder pages for areas that haven't been built yet.
- **Don't over-document** — A wiki page earns its place when a reader would look for it.
  Not every file, function, or config needs a page.
- **Delete fearlessly** — A dead page is worse than a missing page. If something was
  removed from the project, remove its wiki page.
- **Plain markdown** — No framework-specific syntax, no frontmatter, no special tooling.
  The wiki should be readable in any markdown viewer (GitHub, Obsidian, VS Code, raw text).
- **Index is the entry point** — `README.md` is always current, always scannable.
  A reader who only opens the index should understand what the project is and where to
  find what they need.

---

## Project overrides

If `.claude/kit.json` has a `rules."wiki"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."wiki" // empty' .claude/kit.json 2>/dev/null
```
