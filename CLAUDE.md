# Project

<!-- Replace this section with your project description -->

## Skills

This project uses Claude Code skills for structured workflows:

- `/brain` — Project knowledge management (decisions, tasks, questions, insights). Single source of truth in `cowork/brain/BRAIN.db`.
- `/brainstorm` — Conversational idea development. All outputs logged to brain DB with parent linking.
- `/commit` — Stage all files and commit with auto-generated message.
- `/kill` — Kill dev processes (servers, watchers) without touching Claude Code.
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

- **SessionStart:** Loads brain state (focus, tasks, questions, mantra) into context. Recalculates tiers.
- **SessionEnd:** Records session end timestamp.

<!-- BEGIN:mantra -->
<!-- Mantra will be inserted here by /brain audit or /brain mantra -->
<!-- END:mantra -->
