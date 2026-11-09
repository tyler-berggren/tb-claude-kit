---
name: disk
description: See where this Mac's disk space went across every drive, internal and external, and win it back. Says what created each big item, then clears it, redirects the tool that makes it, moves it to another drive, or archives a dormant project whose remote is current, only what the user picks. `/disk setup` maps the drives once; `/disk report` changes nothing.
user_only: true
---

# Disk

A small internal drive fills up from things nobody chose to keep: caches, build output, leftover
agent worktrees, a project untouched since spring. Most of it either comes back on its own or has a
better home on another drive. This skill works across the **whole machine** and every drive attached
to it, and it never deletes or moves anything the user didn't pick.

| Argument | What happens |
|---|---|
| `setup` | Map this machine's drives: which is for what, how much free space each must keep. Run once, and again when a drive is added. |
| *(none)* | Report, then offer the recommended actions and carry out the ones the user picks. Runs `setup` first when there is no config. |
| `report` | Measure and recommend only. Changes nothing. |

## The machine config

Drive layout belongs to the machine, not to a project, so it lives outside every repository:
`~/.config/claude-kit/disk.json` (or `$CLAUDE_KIT_DISK_CONFIG`). `~/.claude-kit/scripts/disk` reads
and writes it. Edit it through that script, not by hand.

```json
{
  "drives": [
    { "uuid": "58CF…", "label": "Macintosh HD", "role": "hot",  "floorGB": 40, "alwaysAttached": true },
    { "uuid": "65EF…", "label": "External",     "role": "warm", "floorGB": 50, "alwaysAttached": true }
  ],
  "projectRoots": ["~/dev"],
  "warmAfterDays": 60,
  "coldAfterDays": 365,
  "archiveDir": null,
  "worktreeDir": null,
  "knownItems": []
}
```

- **Drives are keyed by volume UUID.** Names change and collide; the UUID doesn't.
- **`role`:**
  - `hot` is for active work. It is usually the internal drive.
  - `warm` takes dormant projects, caches and tool data moved off a hot drive.
  - `archive` holds archives of projects dropped from disk.
  A machine with one external drive gives it `warm`. It then holds archives too.
- **`floorGB`:** the free space this drive must keep. The session-start hook warns below it.
- **`alwaysAttached`:** true for a drive that never leaves the machine (a desktop's dock or a
  second internal disk). Only an always-attached drive takes tool data, caches or worktrees,
  because anything pointed at a missing drive breaks. For a drive that comes and goes (a laptop's
  USB disk), recently touched projects stay on the internal drive.
- **`projectRoots`:** where git projects live, on any drive. `/clear-cache` reads it too.
- **`warmAfterDays` / `coldAfterDays`:** a project untouched this long is a candidate to move to a
  warm drive / to drop from disk (remote only, after its archive).
- **`archiveDir`:** where dropped projects' archives go. Default: `disk-archive/` on the first
  `archive` drive, else on the first `warm` drive.
- **`worktreeDir`:** where git worktrees go. Default: `worktrees/` on the first always-attached
  `warm` drive.
- **`knownItems`:** this user's additions to the skill's knowledge file (see **Known items**).

> **The shell is zsh.** It aborts on a glob that matches nothing and doesn't word-split variables.
> Every block below runs under `bash` for that reason.

## Setup

1. List the drives and any existing config:
   ```bash
   ~/.claude-kit/scripts/disk drives
   ~/.claude-kit/scripts/disk config
   ```
   `drives` lists the internal data volume and every browsable, writable volume under `/Volumes`.
   Network shares and disk images are left out.

2. Interview the user in **one round** with the question tool: one question per drive. When a
   config exists, recommend the values it already holds.
   - **The internal drive** is `hot`, and always attached. Ask only for its floor. Recommend 15%
     of its size, rounded to 5 GB, and at least 20 GB.
   - **Each external drive:**
     - Ask its role. Recommend `warm` for the first one; for a second one, `archive` when it is
       slower or larger, else `warm`.
     - Ask whether it is always attached. A Mac mini, Studio or iMac suggests yes; a laptop
       suggests no. Run `sysctl -n hw.model` to see which.
     - Ask its floor. Recommend 5% of its size, rounded to 5 GB.
   - **Where projects live.** Suggest `~/dev`, plus any folder on an external drive that holds
     git repositories. Find those with
     `find /Volumes/<name> -maxdepth 3 -name .git -prune 2>/dev/null | head`.

3. Write the answers:
   ```bash
   ~/.claude-kit/scripts/disk set-drive <uuid> --role hot --floor 40 --attached yes
   ~/.claude-kit/scripts/disk set-drive <uuid> --role warm --floor 50 --attached yes
   ~/.claude-kit/scripts/disk set projectRoots '["~/dev", "/Volumes/External/dev"]'
   ```

4. **Worktrees off the internal drive.** Skip this step unless a `warm` drive is always attached.
   Each git worktree Claude Code makes (`--worktree`, `EnterWorktree`, subagents with worktree
   isolation) is a full checkout, often with its own `node_modules`. They pile up inside the repo.
   Claude Code has no setting that moves them, and it refuses a symlinked `.claude/worktrees`, so
   moving them takes a `WorktreeCreate`/`WorktreeRemove` hook pair.
   - Offer to register the pair in `~/.claude/settings.json`:
     - `wt-create` puts each worktree at `<worktreeDir>/<repo>-<hash>/<name>`. It copies
       `.worktreeinclude` files such as `.env`, and falls back to the repo when the drive isn't
       mounted.
     - `wt-remove` keeps a worktree that has uncommitted changes, and keeps a branch that isn't
       merged.
   - On yes, register them, then check the result with `jq '.hooks' ~/.claude/settings.json`:
   ```bash
   bash <<'SH'
   f=~/.claude/settings.json; [ -f "$f" ] || echo '{}' > "$f"
   cp "$f" "$f.bak-disk-$(date +%Y%m%d%H%M%S)"
   tmp=$(mktemp)
   jq --arg c "$HOME/.claude-kit/scripts/wt-create" --arg r "$HOME/.claude-kit/scripts/wt-remove" \
     '.hooks = ((.hooks // {}) + {WorktreeCreate: [{hooks: [{type: "command", command: $c}]}],
                                  WorktreeRemove: [{hooks: [{type: "command", command: $r}]}]})' \
     "$f" > "$tmp" && jq empty "$tmp" && mv "$tmp" "$f"
   SH
   ```
   If a `WorktreeCreate` hook is already there and isn't the kit's, don't replace it. Say so and
   leave it.

5. Show `~/.claude-kit/scripts/disk status` as a short table: each drive's role, free space and
   floor. Then say what the setup turned on: the session-start warning below each floor, and the
   worktree hooks when registered.

## Rules

- **Nothing is deleted or moved without the user picking it.** `report` changes nothing.
- **Never `sudo`.**
- **An unmounted drive is skipped, and the report says so.** Never create a folder under `/Volumes/`.
  It would land on the internal drive, at the path where the missing drive should be mounted.
- **Never write the config, a cache or a report inside a repository.**

---

## Project overrides

If `.claude/kit.json` has a `rules."disk"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."disk" // empty' .claude/kit.json 2>/dev/null
```
