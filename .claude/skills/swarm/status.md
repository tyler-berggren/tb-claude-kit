## Status Flow

Read-only. Load the run and units, print: run status, the integration worktree's path, unit table (key, title, status, branch — and for a PR-mode run, lane, kind and PR), live agents (`ListAgents`), open review holds (`swarm_holds`, with their holder), and what's blocking what. Parked slices waiting on the owner are listed with the count of open items in the plan's `## Review` block and its line range. Then the repo's worktrees from `~/.claude-kit/scripts/worktree-sweep <primary>`:
how many and how many GB, and the ones it would remove now. Do not start or resume work.

## Abort Flow

Confirm with the user unless the session is non-interactive. Then: stop live agents (`TaskStop`), sweep each one's worktree and stop the standing resources they held (**Machine budget**), set run `aborted` with a note, mark in-flight units `failed`. **Keep** worktrees, branches, and the integration branch for inspection — deleting work is the user's call. Send a push notification with the abort summary, and report what was merged, what was in flight, and that `/swarm <ref>` now offers Remainder setup over what's left.
