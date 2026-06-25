---
name: vibe-audit
description: Codebase health + security audit for vibe-engineered projects. Scans code, checks architecture guardrails, reviews threat model. Findings brainstormed with user before committing to brain.
argument-hint: "[security|monolith|shell|deps] or empty for full audit"
---

## Last Vibe Audit
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, created_at, substr(body, 1, 150) FROM logs WHERE type = 'milestone' AND tags LIKE '%vibe-audit%' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null || echo "No prior vibe-audit found"`

## Pattern Effectiveness
!`sqlite3 -separator ' | ' cowork/vibe-audit/VIBE-AUDIT.db "SELECT slug, tp || 'tp/' || fp || 'fp', effectiveness_grade FROM v_pattern_effectiveness WHERE tp + fp > 0 ORDER BY precision DESC LIMIT 10;" 2>/dev/null || echo "No pattern data yet — first run will establish baseline"`

## Last 3 Runs
!`sqlite3 -separator ' | ' cowork/vibe-audit/VIBE-AUDIT.db "SELECT '#' || id, started_at, scope, summary FROM runs ORDER BY started_at DESC LIMIT 3;" 2>/dev/null || echo "No prior runs"`

## Open Audit Findings
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, type, title FROM logs WHERE tags LIKE '%vibe-audit%' AND type IN ('task', 'question') AND status = 'active' ORDER BY importance DESC, created_at DESC LIMIT 10;" 2>/dev/null || echo "None"`

## Threat Model Entries
!`sqlite3 -separator ' | ' cowork/brain/BRAIN.db "SELECT '#' || id, title FROM logs WHERE tags LIKE '%threat-model%' AND status = 'active' ORDER BY importance DESC;" 2>/dev/null || echo "None"`

---

Read `cowork/vibe-audit/PROCEDURE.md` for the full audit procedure — three phases (scan, brainstorm, commit), scan categories, VIBE-AUDIT.db integration.

Read `cowork/vibe-audit/GUARDRAILS.md` for the architecture guardrails checklist.

## Key paths

- **VIBE-AUDIT.db**: `cowork/vibe-audit/VIBE-AUDIT.db` — self-learning audit database with Bayesian pattern tracking
- **Schema**: `cowork/vibe-audit/schema.sql` — recreate DB if missing
- **Seed data**: `cowork/vibe-audit/seed.sql` — builtin patterns and suppressions
- **Procedure**: `cowork/vibe-audit/PROCEDURE.md` — full scan/brainstorm/commit procedure
- **Guardrails**: `cowork/vibe-audit/GUARDRAILS.md` — architecture checklist

## Rules

- **No permission needed for the scan** — Phase 1 executes immediately.
- **Always brainstorm before committing** — Phase 2 is mandatory. Never write findings to the brain without user discussion and confirmation.
- **Speed over perfection** — The scan is a quick health check, not a penetration test. Use grep/wc/bash. Target under 90 seconds for Phase 1.
- **Be smart about intentional patterns** — Read surrounding context before flagging. Don't flag patterns that are explicitly mitigated.
- **Severity must be justified** — Critical = actively dangerous or harmful to productivity. Warning = address soon. Info = worth noting, no action yet.
- **Concrete recommendations** — Every Critical/Warning finding needs a specific, actionable fix (not "consider improving").
- **No false courage** — If you can't determine whether a pattern is safe, flag it as Warning with a note for manual review.
- **Normalize tags** — Split by comma, trim, lowercase, sort alphabetically, deduplicate, rejoin.
- **The brain is the report** — Findings are brain entries. The milestone is the summary. VIBE-AUDIT.db tracks scan mechanics and learning — it's the skill's memory, not the project's knowledge base.
- **VIBE-AUDIT.db is the skill's memory** — Every run creates a record, every finding gets a fingerprint and disposition. Patterns learn from feedback. Suppressions accumulate. The skill gets smarter each run.
