---
name: sync
description: Propagate kit skill/hook/schema changes to downstream projects. Diffs each file, preserves project customizations, merges intelligently.
argument-hint: "[project-name]"
---

# Sync Kit to Downstream Projects

Propagate changes from this kit (the canonical source) to downstream projects listed in `downstream.json`.

## Input

Optional argument: `$ARGUMENTS`

If a project name or path is given, sync only that project. Otherwise sync all projects in `downstream.json`.

## File Categories

Two categories determine how diffs are handled:

### Kit-managed files (auto-updatable)
These originate in the kit. Downstream projects may customize them, but the kit version is the canonical base. Changes require intelligent merging.

- `.claude/skills/*/SKILL.md` (and any other files in skill directories)
- `.claude/hooks/session-start.sh`
- `cowork/brain/schema.sql`
- `cowork/brain/USAGE.md`
- `cowork/vibe-audit/PROCEDURE.md`
- `cowork/vibe-audit/schema.sql`
- `cowork/vibe-audit/seed.sql`
- `scripts/puppeteer-server.cjs`

### Project files (report only)
These are heavily customized per-project. Never auto-update — only report diffs for awareness.

- `CLAUDE.md`
- `.claude/settings.json`
- `.claude/settings.local.json`
- `.mcp.json`
- `cowork/vibe-audit/GUARDRAILS.md`

## Procedure

1. **Load downstream.json** from this skill's directory (`.claude/skills/sync/downstream.json`). If the file doesn't exist, tell the user to create it from `downstream.example.json` in the same directory and stop.

2. **Filter projects** if an argument was given (match on directory basename or full path).

3. **For each project**, diff every kit-managed file:

   ```bash
   diff -u "<project>/<file>" "<kit>/<file>" --label "project: <file>" --label "kit: <file>"
   ```

   Categorize each file into one of:
   - **Identical** — no diff, skip silently
   - **Kit-only change** — project file matches a prior kit version, kit has been updated. Safe to apply directly.
   - **Project-only change** — project has customizations the kit doesn't have. Report but don't touch.
   - **Both changed** — project has customizations AND the kit has new changes. Requires merge.
   - **Missing in project** — file exists in kit but not in project. Offer to install.
   - **Missing in kit** — file exists in project but not in kit (e.g. project-specific skills). Skip silently.

4. **Report a summary table** for the project before making changes:
   ```
   Project: /path/to/project
   ─────────────────────────
   [apply]  .claude/hooks/session-start.sh — kit updated, no project customizations
   [merge]  .claude/skills/brain/SKILL.md — both sides changed
   [skip]   .claude/skills/commit/SKILL.md — project customized, kit unchanged
   [ok]     .claude/skills/plan/SKILL.md — identical
   ```

5. **Apply changes:**
   - **Kit-only changes** (`[apply]`): Copy the kit version directly.
   - **Both changed** (`[merge]`): Read both versions fully. Write a merged version that incorporates the kit's new changes while preserving the project's customizations. Use your judgment — the kit change is the intent, the project customization is the context. Show the user what you're writing.
   - **Project-only changes** (`[skip]`): Leave alone. Mention them in case the project should upstream the change back to the kit.
   - **Missing** (`[new]`): Copy from kit.

6. **Report project files** that differ (CLAUDE.md, settings.json, etc.) as an FYI section at the end. Don't modify them, but flag if they're missing sections that the kit now expects (like a `<!-- BEGIN:mantra -->` block).

7. **After all projects**, print a final summary:
   ```
   Sync complete
   ─────────────
   reinstall-work: 3 applied, 1 merged, 2 skipped
   deesil-cowork-kit: 2 applied, 0 merged, 4 skipped
   ```

## Rules

- **Never blindly overwrite.** Always diff first, categorize, then act.
- **Preserve project customizations.** When merging, the project's additions/modifications take priority over the kit's defaults where they conflict. The kit's *new* changes (things the project doesn't have yet) get added.
- **Show your work on merges.** For `[merge]` files, explain what you're keeping from each side before writing.
- **Read before writing.** Always read the full content of both versions before attempting a merge.
- **One project at a time.** Finish one project completely before moving to the next.
- **Commit nothing.** The user will review and commit separately.
