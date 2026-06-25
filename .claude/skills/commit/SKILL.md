---
name: commit
description: Commit changes with an auto-generated message. Stages all uncommitted files and commits with a concise summary.
argument-hint: "[only]"
---

# Commit Changes

Commits uncommitted files with an auto-generated commit message.

## Modifiers

- **`/commit`** — Default. Stages and commits **all** uncommitted files in the project.
- **`/commit only`** — Stages and commits only files modified during the **current session**.

## Input

Optional argument: `$ARGUMENTS`

## Procedure

1. **Determine scope** based on modifier (default = all, "only" = session files)

2. **Run `git status`** to see what's uncommitted

3. **Generate commit message** summarizing the changes

4. **Stage and commit**

   Default (all uncommitted files):
   ```bash
   git add -A
   git commit -m "<message>"
   ```

   With "only" modifier (session files only):
   ```bash
   git add <file1> <file2> ...
   git commit -m "<message>"
   ```

## Rules

- **No permission required** - Execute immediately without asking
- **Concise messages** - Summarize what changed, not every detail
- **Never be selective** - In default mode, commit everything without question. Do not skip log files, generated files, or any other files. `git add -A` means everything.
- **Never skip hooks** (`--no-verify`)
