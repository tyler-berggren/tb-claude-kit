# Project

<!-- Replace this section with your project description -->

## Skills

This project uses Claude Code skills for structured workflows:

- `/brain` — Project knowledge management (decisions, tasks, questions, insights). Single source of truth in `cowork/brain/BRAIN.db`.
- `/brainstorm` — Conversational idea development. All outputs logged to brain DB with parent linking.
- `/bridge` — Start artifact bridge server (port 4444) for HTML artifacts to read/write project files.
- `/commit` — Stage all files and commit with auto-generated message.
- `/cto` — Architecture observatory — scans codebase, maps components into SQLite, generates HTML with Mermaid C4 diagrams.
- `/kill` — Kill dev processes (servers, watchers, bridge) without touching Claude Code.
- `/look` — Inspect shared Chrome viewport via Puppeteer (DOM-first, not screenshot-first).
- `/plan` — Multi-phased project planning with fresh-eyes reconciliation on every resume.
- `/push` — Commit and push to remote.
- `/research` — Web and project research with numbered reports in `cowork/research/`.
- `/vibe-audit` — Codebase health and security audit with self-learning pattern database.
- `/video-editor` — Transcript-based video editing via Palmier Pro MCP. Transcribe, script, cut, caption.

## Brain System

All project knowledge lives in `cowork/brain/BRAIN.db` — a SQLite database with FTS5 search.

- **DB is truth, markdown is view.** Never read from `BRAIN.md` to determine state — always query the DB.
- **Entry types:** note, decision, question, insight, task, milestone
- **Tier system:** hot (focus/momentum) > warm (important/recent) > cold (active) > archived (done)
- **Tags:** always normalized (comma-split, trimmed, lowercase, alpha-sorted, deduped)
- **Plans:** numbered files in `cowork/plans/` linked via `meta.plan_id`
- **Research:** numbered reports in `cowork/research/` indexed in brain DB

### Session hooks

- **SessionStart:** Loads brain state (focus, tasks, questions, mantra) and last session's work into context. Recalculates tiers. Instructs Claude to review the last session and update the mantra if warranted.
- **SessionEnd:** Records session end timestamp.

### Mantra
The mantra is Claude's self-authored evolving context — patterns, non-obvious knowledge, tricky areas, current momentum, and working assumptions that CLAUDE.md doesn't cover. It lives in three synced locations:
1. `mantra` table in BRAIN.db (source of truth)
2. `cowork/brain/MANTRA.md` (readable export for Obsidian)
3. `<!-- BEGIN:mantra -->` block in this file (inline for fresh sessions)

**Automatic review-on-start:** The session-start hook loads the last session's logs, journal, and summary. At the start of each session, review this context against the current mantra. If the last session surfaced something a fresh session would need — update the mantra silently (all three locations). If it was routine, skip. No user action required.

**How to update:** `UPDATE mantra SET content = '...', updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime');` (or INSERT if empty). Then write `cowork/brain/MANTRA.md` and update the BEGIN:mantra block in CLAUDE.md.

<!-- BEGIN:mantra -->
<!-- END:mantra -->
