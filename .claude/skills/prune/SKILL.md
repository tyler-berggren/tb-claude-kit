---
name: prune
description: Review a repo's git worktrees and recommend which to remove — merged or abandoned branches, stale ones, and folders already gone — then remove only the ones the user picks. `/prune report` changes nothing. Optional path argument for a repo other than this one.
user_only: true
---

# Prune Worktrees

A **worktree** is a second (or tenth) checkout of the same repo in its own folder, each on its
own branch. Several branches can be open at once without stashing or switching, which is why
agents and `/swarm` use them heavily. They are cheap to make and easy to forget. Each keeps its
own `node_modules` and build output (often 1–3 GB), and after a few weeks most of them hold
branches that were merged long ago.

This skill finds the ones you can let go, explains why for each, and removes only what you pick.

| Argument | What happens |
|---|---|
| *(none)* | Review this repo's worktrees, recommend, ask, then remove what you choose. |
| `report` | Review and recommend only. Changes nothing. |
| `<path>` | Same, for the repo at that path (e.g. a team repo this project wraps). |

## Configuration

Optional, in `.claude/kit.json`:

```json
{
  "prune": {
    "staleDays": 14,
    "keep": ["release-*", "demo"]
  }
}
```

- `staleDays`: no commit and no file change for this many days counts as stale. Default 14.
- `keep`: branch-name globs never recommended for removal.

> **The shell is zsh**, which aborts on unmatched globs and doesn't word-split variables. Every
> block below runs under `bash`.

## Procedure

### 1. Gather the facts

Run from the repo (or `cd` to the path argument first). This only reads, plus one `git fetch
--prune`, which updates what the remote knows and deletes no local work.

```bash
bash <<'SH'
set -u
REPO=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git repo"; exit 1; }
MAIN=$(git worktree list --porcelain | awk 'NR==1{print $2}')
cd "$MAIN"
git fetch --prune --quiet 2>/dev/null || echo "note: fetch failed (offline?); merge status may be stale"
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
STALE=$(jq -r '.prune.staleDays // 14' .claude/kit.json 2>/dev/null); [ -z "$STALE" ] && STALE=14
GH=0; command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && GH=1
# Every process's working directory, once, to spot worktrees something is running in.
CWDS=$(lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
echo "main=$MAIN base=$BASE staleDays=$STALE gh=$GH"
printf 'path\tbranch\tdirty\tunpushed\tmerged\tpr\tlast_commit_days\tlast_touch_days\tsize\tbusy\tflags\n'
git worktree list --porcelain | awk '/^worktree /{p=$2} /^branch /{b=$2} /^detached/{b="(detached)"} /^locked/{l="locked"} /^prunable/{r="prunable"} /^$/{print p"\t"b"\t"l"\t"r; p=b=l=r=""} END{if(p)print p"\t"b"\t"l"\t"r}' |
while IFS=$'\t' read -r path ref locked prunable; do
  [ "$path" = "$MAIN" ] && continue
  br=${ref#refs/heads/}
  if [ -n "$prunable" ] || [ ! -d "$path" ]; then
    printf '%s\t%s\t-\t-\t-\t-\t-\t-\t-\t-\tfolder-gone\n' "$path" "$br"; continue
  fi
  dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$br" = "(detached)" ]; then unpushed=$(git -C "$path" rev-list --count HEAD --not --remotes 2>/dev/null)
  else unpushed=$(git -C "$path" rev-list --count "$br" --not --remotes 2>/dev/null); fi
  merged=no
  if [ "$br" != "(detached)" ]; then
    git merge-base --is-ancestor "$br" "$BASE" 2>/dev/null && merged=yes
    # Squash merges leave no ancestry; git cherry marks commits already upstream with "-".
    [ $merged = no ] && [ -z "$(git cherry "$BASE" "$br" 2>/dev/null | grep '^+')" ] && merged=patches-upstream
    git for-each-ref --format='%(upstream:track)' "refs/heads/$br" | grep -q gone && [ $merged = no ] && merged=upstream-gone
  fi
  pr=-
  [ $GH = 1 ] && [ "$br" != "(detached)" ] && pr=$(gh pr list --head "$br" --state all --limit 1 --json number,state --jq 'if length > 0 then "#\(.[0].number) \(.[0].state)" else "none" end' 2>/dev/null)
  [ -z "$pr" ] && pr=none
  lc=$(( ( $(date +%s) - $(git -C "$path" log -1 --format=%ct 2>/dev/null || echo 0) ) / 86400 ))
  # Newest file edit outside dependency and build folders.
  newest=$(find "$path" \( -name node_modules -o -name .git -o -name .next -o -name .turbo -o -name target -o -name dist \) -prune -o -type f -print0 2>/dev/null | xargs -0 stat -f %m 2>/dev/null | sort -n | tail -1)
  lt=$(( ( $(date +%s) - ${newest:-0} ) / 86400 ))
  size=$(du -sh "$path" 2>/dev/null | cut -f1)
  busy=no; echo "$CWDS" | grep -q "^$path\(/\|$\)" && busy=yes
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$path" "$br" "$dirty" "${unpushed:-?}" "$merged" "$pr" "$lc" "$lt" "$size" "$busy" "${locked:--}"
done
SH
```

Also check for a **running swarm**, whose worktrees must never be touched:

```bash
sqlite3 cowork/brain/BRAIN.db "select plan_id, status from swarm_runs where status in ('running','ready')" 2>/dev/null
```

### 2. Sort each worktree into one of four groups

Apply the first rule that fits, top to bottom:

| Group | Rule | Why |
|---|---|---|
| **Keep** | `busy=yes`, `locked`, the current session's own folder, a branch of a running swarm, or a branch matching `prune.keep` | Something is using it, or you said so. |
| **Keep** | `dirty` > 0 or `unpushed` > 0 | It holds work that exists nowhere else. Say which files or commits, so the user can decide to push or discard them first. |
| **Keep** | PR is `OPEN`, or last touched within `staleDays` | Still in play. |
| **Remove** | `folder-gone` | The folder was deleted by hand; git still lists it. Costs nothing to clean. |
| **Remove** | `merged` is `yes` / `patches-upstream`, or PR is `MERGED` | The work is in the main branch. The branch and folder are leftovers. |
| **Ask** | PR is `CLOSED` (not merged), or `merged=upstream-gone` with no PR | Abandoned or merged in a way git cannot prove. Everything is pushed, so nothing is lost locally, but the user decides. |
| **Ask** | Everything else older than `staleDays` | Pushed, not merged, not recently touched: probably forgotten, maybe paused. |

### 3. Show the recommendation, then ask

Show one numbered table per group, largest first, in plain words. Include the branch, what
happened to it ("merged 12 days ago as PR #812", "PR closed without merging", "no activity for
23 days"), its size, and for **Keep** the reason. End with the total size of **Remove**.

Then ask which to remove, with an **AskUserQuestion**:

- "Remove the N recommended (X GB)" (recommended)
- "Remove the recommended ones and the ones marked Ask"
- "Let me pick" (then take a list of numbers)
- "Nothing for now"

In `report` mode, show the tables and stop.

### 4. Remove what was picked

For each chosen worktree, in the main checkout:

```bash
git worktree remove "<path>"                     # never --force
```

`git worktree remove` refuses a folder with uncommitted or untracked changes. That refusal is
the safety net: report it, and never retry with `--force`. `node_modules` and other ignored build
output do not block it and go with the folder.

Then deal with the branch:

- Merged by ancestry: `git branch -d <branch>` (git confirms it is merged).
- Merged as a squash PR (`MERGED` on GitHub, or `patches-upstream`): `git branch -D <branch>`.
  Git cannot see a squash merge, so `-d` would refuse. GitHub's MERGED state is the proof.
- `Ask` group: keep the branch unless the user said to delete it too. Removing the folder alone
  is fully reversible: `git worktree add <path> <branch>` brings it back.
- Never delete a remote branch.

Finish with `git worktree prune`, which clears records of folders that are already gone.

### 5. Report

List what was removed and the space freed. Recount with `git worktree list` rather than
trusting the plan. Name anything that refused to go and why, plus the one command that brings
each removed worktree back (`git worktree add <path> <branch>`).

## Rules

- **Never remove without the user's pick**, not even the obvious ones. `report` changes nothing.
- **Never `--force`**, never `git clean`, never `reset`. If git refuses, report it.
- **Never touch the main checkout**, the session's own worktree, a locked worktree, a running
  swarm's worktrees, or one with a process running in it.
- **Never delete a remote branch.** Local cleanup only.
- **Uncommitted or unpushed work is always Keep.** Tell the user what it is. If they then want
  it gone, they push it or discard it themselves, and `/prune` runs again.

---

## Project overrides

If `.claude/kit.json` has a `rules."prune"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."prune" // empty' .claude/kit.json 2>/dev/null
```
