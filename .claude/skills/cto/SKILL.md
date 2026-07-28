---
name: cto
description: Re-runnable architecture observatory — scans the codebase, maps components and relationships into a SQLite DB, generates a self-contained HTML document with Mermaid diagrams at multiple C4 levels. Delta tracking across runs reveals architectural drift.
argument-hint: "[full|scan|output|delta] or empty for full run"
---

## Last Run
!`sqlite3 -separator ' | ' cowork/architecture/CTO.db "SELECT '#' || id, started_at, git_sha, substr(summary, 1, 150) FROM runs ORDER BY started_at DESC LIMIT 1;" 2>/dev/null || echo "No prior runs — first run will establish baseline"`

## Subsystem Summary
!`sqlite3 -separator ' | ' cowork/architecture/CTO.db "SELECT subsystem, component_count || ' components', total_loc || ' LOC' FROM v_subsystem_summary LIMIT 10;" 2>/dev/null || echo "No data yet"`

## Complexity Hotspots (Top 5)
!`sqlite3 -separator ' | ' cowork/architecture/CTO.db "SELECT path, loc || ' LOC', CAST(complexity_score AS INTEGER) || ' score' FROM v_complexity_hotspots WHERE loc > 0 LIMIT 5;" 2>/dev/null || echo "No data yet"`

## Recent Drift
!`sqlite3 -separator ' | ' cowork/architecture/CTO.db "SELECT path, drift_type, loc_delta FROM v_architectural_drift LIMIT 5;" 2>/dev/null || echo "No drift data — need 2+ runs"`

---

Read `cowork/architecture/PROCEDURE.md` for the full scan/synthesize/output procedure.

## Key paths

- **CTO.db**: `cowork/architecture/CTO.db` — structured architecture data across runs
- **Schema**: `cowork/architecture/schema.sql` — recreate DB if missing
- **Seed data**: `cowork/architecture/seed.sql` — project-specific context (edit per project)
- **Procedure**: `cowork/architecture/PROCEDURE.md` — full three-phase procedure
- **HTML output**: `cowork/architecture/architecture.html` — self-contained HTML with Mermaid diagrams
- **Summaries**: `cowork/architecture/YYYY-MM-DD_architecture-summary.md` — dated markdown summaries (git-diffable, visible in Obsidian)

## Rules

- **No permission needed** — Execute immediately.
- **Fully automated** — No interactive brainstorm phase (unlike vibe-audit). Scan → synthesize → output.
- **Idempotent** — Running twice on the same SHA produces the same output. Delta tracking handles the rest.
- **Subagent fan-out for synthesis** — Each subsystem gets its own subagent for summarization. Keeps context windows clean.
- **Mermaid for diagrams** — C4 levels: Context (L0), Container (L1), Component (L2). All rendered client-side via Mermaid.js CDN.
- **HTML is the deliverable** — `architecture.html` is self-contained, dark-themed, and shareable. Opens in any browser.
- **DB is the memory** — CTO.db accumulates data across runs. Component history tracks first/last seen, LOC drift, role changes.
- **Seed data is project-specific** — Edit `seed.sql` to define your project's subsystems and patterns. The scan discovers everything else automatically.

---

## Project overrides

If `.claude/kit.json` has a `rules."cto"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."cto" // empty' .claude/kit.json 2>/dev/null
```
