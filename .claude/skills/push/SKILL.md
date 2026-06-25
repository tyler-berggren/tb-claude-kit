---
name: push
description: Commit all changes and push to remote.
---

# Push Changes

Stages all files, commits with an auto-generated message, and pushes to remote.

## Input

Optional argument: `$ARGUMENTS`

## Procedure

1. Run `git status` to see what's uncommitted
2. If there are uncommitted changes, stage and commit: `git add -A && git commit -m "<message>"`
3. Push: `git push`

## Rules

- **No permission required** — Execute immediately without asking
- **Concise messages** — Summarize what changed, not every detail
- **Never skip hooks** (`--no-verify`)
- **Include all files** — `git add -A`, never be selective
- **If nothing to commit** — Just push existing commits
