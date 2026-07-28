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

   Read the optional author override first — it applies to both modes:
   ```bash
   AUTHOR=$(jq -r '.commit.author // empty' .claude/kit.json 2>/dev/null)
   ```

   Default (all uncommitted files):
   ```bash
   git add -A
   [ -n "$AUTHOR" ] && git commit --author="$AUTHOR" -m "<message>" || git commit -m "<message>"
   ```

   With "only" modifier (session files only):
   ```bash
   git add <file1> <file2> ...
   [ -n "$AUTHOR" ] && git commit --author="$AUTHOR" -m "<message>" || git commit -m "<message>"
   ```

## Author override

A project may pin the commit author in `.claude/kit.json`:

```json
{ "commit": { "author": "Jane Dev <jane@example.com>" } }
```

When the key is absent — or there is no `kit.json` at all — commits use the repo's git config as
normal. This is the common case; most projects should not set it.

> **`--author` sets the author only.** The *committer* still comes from git config, so an override
> produces a commit whose two identities differ. That is usually what's wanted. If both must
> match, set `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL` in
> the environment instead — the flag cannot do it.

## Rules

- **No permission required** - Execute immediately without asking
- **Concise messages** - Summarize what changed, not every detail
- **Never be selective** - In default mode, commit everything without question. Do not skip log files, generated files, or any other files. `git add -A` means everything.
- **Never skip hooks** (`--no-verify`)

---

## Project overrides

If `.claude/kit.json` has a `rules."commit"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."commit" // empty' .claude/kit.json 2>/dev/null
```
