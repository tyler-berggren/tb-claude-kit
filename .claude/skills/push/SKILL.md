---
name: push
description: Commit all changes and push to remote.
argument-hint: "[sub <name>]"
---

# Push Changes

Stages all files, commits with an auto-generated message, and pushes to remote.

## Modifiers

- **`/push`** — Default. Stages, commits, and pushes to the monorepo remote (origin).
- **`/push sub <name>`** — Stages, commits, pushes to origin, **and** pushes the named subtree to its deploy repo.

## Input

Optional argument: `$ARGUMENTS`

## Procedure

1. Run `git status` to see what's uncommitted

2. **Regenerate SQLite sidecars** (if configured)

   Before staging, run the sidecar script if `sqlite_tracking` is configured in `.claude/kit.json`:

   ```bash
   bash ~/.claude-kit/scripts/sqlite-sidecar.sh
   ```

   The script is a no-op if no `sqlite_tracking` is configured in `.claude/kit.json`.

3. If there are uncommitted changes, stage and commit: `git add -A && git commit -m "<message>"`

4. Push to origin: `git push`

5. **Subtree push** (only with `sub` modifier)

   After pushing to origin, push the named subtree to its deploy repo. Read the subtree config
   from `.claude/kit.json`:

   ```json
   {
     "subtrees": {
       "landtrack": {
         "prefix": "landtrack",
         "remote": "landtrack",
         "branch": "main"
       }
     }
   }
   ```

   Resolve the subtree name from the argument:
   ```bash
   PREFIX=$(jq -r ".subtrees.\"$NAME\".prefix" .claude/kit.json)
   REMOTE=$(jq -r ".subtrees.\"$NAME\".remote" .claude/kit.json)
   BRANCH=$(jq -r ".subtrees.\"$NAME\".branch // \"main\"" .claude/kit.json)
   ```

   If the name is not found in `subtrees`, list available names and ask the user.

   Then push:
   ```bash
   git subtree push --prefix="$PREFIX" "$REMOTE" "$BRANCH"
   ```

   Report success and the remote URL.

## Rules

- **No permission required** — Execute immediately without asking
- **Concise messages** — Summarize what changed, not every detail
- **Never skip hooks** (`--no-verify`)
- **Include all files** — `git add -A`, never be selective
- **If nothing to commit** — Just push existing commits

---

## Project overrides

If `.claude/kit.json` has a `rules."push"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."push" // empty' .claude/kit.json 2>/dev/null
```
