---
name: clear-cache
description: Measure and clear this machine's dev caches (npm, pnpm, uv, pip, Homebrew, extra Puppeteer/Playwright browsers, Docker build cache) to win back internal disk space. `/clear-cache report` measures only; `/clear-cache deep` also offers the costlier cleanups.
user_only: true
---

# Clear Dev Caches

Package managers and browser-automation tools keep a **cache**: a local copy of everything they
ever downloaded, so the next install is instant and works offline. None of it is your work. All
of it can be downloaded again. But nothing ever removes old entries, so on a small internal drive
the caches slowly outgrow the code.

This skill works on the **whole machine**, not just the project it runs from. Caches live in your
home folder and every project shares them.

| Argument | What happens |
|---|---|
| *(none)* | Measure, clear the **safe** tier, measure again, report. No questions asked. |
| `report` | Measure and report only. Changes nothing. |
| `deep` | The safe tier, then list the **deep** tier with sizes and ask which items to clear. |

## Configuration

Optional, in `.claude/kit.json`:

```json
{
  "clearCache": {
    "projectRoots": ["~/dev", "/Volumes/DockDriveA/dev"],
    "staleDays": 30
  }
}
```

- `projectRoots`: where your projects live. The deep tier looks there for stale `node_modules`.
  Default is `~/dev`.
- `staleDays`: a project whose files haven't changed in this many days counts as stale. Default 30.

> **The shell is zsh.** It aborts on a glob that matches nothing and doesn't word-split
> variables. Every block below runs under `bash` for that reason. Keep it that way.

## Procedure

### 1. Measure (every mode)

```bash
bash <<'SH'
shopt -s nullglob
# "-" when the path is missing or unreadable (the Trash needs Full Disk Access).
sz() { local s; s=$(du -sh "$1" 2>/dev/null | cut -f1); echo "${s:--}"; }
echo "Internal drive free: $(df -h /System/Volumes/Data | awk 'NR==2{print $4}')"
printf '%-34s %s\n' \
  "npm cache (~/.npm/_cacache)"      "$(sz ~/.npm/_cacache)" \
  "npx packages (~/.npm/_npx)"       "$(sz ~/.npm/_npx)" \
  "pnpm metadata (Library/Caches)"   "$(sz ~/Library/Caches/pnpm)" \
  "pnpm store ($(pnpm store path 2>/dev/null || echo n/a))" "$(sz "$(pnpm store path 2>/dev/null)")" \
  "uv (~/.cache/uv)"                 "$(sz ~/.cache/uv)" \
  "pip (Library/Caches/pip)"         "$(sz ~/Library/Caches/pip)" \
  "Homebrew downloads"               "$(sz "$(brew --cache 2>/dev/null)")" \
  "Puppeteer browsers"               "$(sz ~/.cache/puppeteer)" \
  "Playwright browsers"              "$(sz ~/Library/Caches/ms-playwright)" \
  "Hugging Face models (report only)" "$(sz ~/.cache/huggingface)" \
  "Trash (report only)"              "$(sz ~/.Trash)"
SH
```

In `report` mode, also run the **find** halves of steps 3 and 4 (never the delete halves) so the
report shows what those tiers would free. Then stop.

### 2. Safe tier: clear without asking

Everything here re-downloads the next time something needs it. Nothing a project is using right
now gets removed.

```bash
bash <<'SH'
# npm: the download cache. Refills itself on the next install.
command -v npm  >/dev/null && npm cache clean --force 2>/dev/null && echo "npm cache cleared"

# pnpm: prune only removes packages that no project links to any more.
# Skip it when the store sits on an external drive that isn't mounted.
if command -v pnpm >/dev/null; then
  store=$(pnpm store path 2>/dev/null)
  if [ -d "$store" ]; then pnpm store prune && echo "pnpm store pruned"
  else echo "pnpm store not reachable ($store) - skipped"; fi
  rm -rf ~/Library/Caches/pnpm && echo "pnpm metadata cache cleared"
fi

# uv: prune drops entries nothing uses. `uv cache clean` (everything) is deep tier.
command -v uv   >/dev/null && uv cache prune && echo "uv cache pruned"
command -v pip3 >/dev/null && pip3 cache purge 2>/dev/null && echo "pip cache purged"

# Homebrew: old formula versions and downloaded bottles.
command -v brew >/dev/null && brew cleanup --prune=all && echo "Homebrew cleaned"
SH
```

### 3. Safe tier: extra copies of Chrome

Every Puppeteer release pins its own Chrome build and downloads it on `npm install`, so each
upgrade used to leave another ~500 MB copy in `~/.cache/puppeteer`. The kit now shares **one**
Chrome across every project (`/look`, and every project skill that starts
`scripts/puppeteer-server.cjs`), managed by `~/.claude-kit/scripts/kit-chrome`. Anything else in
that folder is a leftover.

```bash
~/.claude-kit/scripts/kit-chrome prune     # in `report` mode: ~/.claude-kit/scripts/kit-chrome (status only)
```

If it says there is no shared Chrome yet, delete nothing. Tell the user to run
`~/.claude-kit/scripts/kit-chrome update` once. It installs the shared Chrome, turns off
Puppeteer's downloads in `~/.zshenv`, and removes the other copies.

Playwright keeps its browsers in `~/Library/Caches/ms-playwright`, one folder per build
(`chromium-1228`, `chromium-1234`). Unlike Puppeteer, **each Playwright version needs its exact
build** and never downloads a missing one on its own, so a test run fails outright until someone
runs `npx playwright install`. Keep every build any project's Playwright pins, plus the newest of
each type, and delete only the rest. Playwright MCP servers also keep profiles there
(`mcp-chrome-*`); **never** touch those.

```bash
bash <<'SH'
shopt -s nullglob
roots=$(jq -r '(.clearCache.projectRoots // ["~/dev"])[]' .claude/kit.json 2>/dev/null); [ -z "$roots" ] && roots="~/dev"
# Every build a project pins, from each installed playwright-core (npm and pnpm layouts).
# -L follows links, so a project linked into ~/dev from another drive (ha-platform) is seen too.
pinned=$(echo "$roots" | while IFS= read -r r; do
  r="${r/#\~/$HOME}"; [ -d "$r" ] || continue
  find -L "$r" -maxdepth 8 -path '*playwright-core/browsers.json' -not -path '*/.git/*' 2>/dev/null
done | sort -u | while IFS= read -r f; do
  jq -r '.browsers[] | "\(.name | gsub("-"; "_"))-\(.revision)"' "$f" 2>/dev/null
done | sort -u)
cd ~/Library/Caches/ms-playwright 2>/dev/null || exit 0
for d in *-[0-9]*; do
  case "$d" in mcp-*) continue ;; esac
  type=${d%-*}
  newest=$(ls -d "$type"-[0-9]* | sort -t- -k2 -n | tail -1)
  [ "$d" = "$newest" ] && continue
  echo "$pinned" | grep -qx "$d" && { echo "keep $d (a project pins it)"; continue; }
  echo "remove $d ($(du -sh "$d" | cut -f1))"
  rm -rf "$d"            # in `report` mode: print only, skip this line
done
SH
```

A project on an external drive that isn't linked into a project root is invisible to this scan,
so list it in `clearCache.projectRoots`. If a test later reports a missing browser, run
`npx playwright install chromium` in that project.

> **Playwright's installer removes browsers too.** After installing, it deletes every build that
> no *registered* Playwright needs. A Playwright registers only by running `playwright install`
> itself (the list is in `ms-playwright/.links`). So restoring one project's build can delete
> another's. After restoring, run `playwright install chromium` in **each** project that uses
> Playwright, so all of them are registered and the next install keeps every build.

### 4. Deep tier: list, then ask (only with `deep`)

Each of these costs something you'd notice: a slow first run, a re-download, or a reinstall.
Measure each one, show a numbered list with sizes and the cost, then clear only what the user picks.

| Item | How to find it | How to clear it | What it costs |
|---|---|---|---|
| **npx packages** `~/.npm/_npx` | size | `rm -rf ~/.npm/_npx` | MCP servers started with `npx` download again on their next start. **Close other Claude sessions first**, since their servers run from this folder. |
| **Whole uv cache** | size of `~/.cache/uv` | `uv cache clean` | Every Python tool and venv rebuilds from the network. |
| **Docker build cache and dangling images** | `docker system df` (skip if no daemon answers) | `docker builder prune -f && docker image prune -f` | The next image build starts cold. **Never** prune volumes (`--volumes`, `system prune -a`), because volumes hold databases. |
| **Stale `node_modules`** | see below | `rm -rf <path>` | `npm install` / `pnpm install` in that project before using it again. |
| **Rust `target/` in stale projects** | same scan, `target` beside a `Cargo.toml` | `cargo clean` in that folder | A full rebuild next time. |

Finding stale dependency folders:

```bash
bash <<'SH'
days=$(jq -r '.clearCache.staleDays // 30' .claude/kit.json 2>/dev/null); [ -z "$days" ] && days=30
roots=$(jq -r '(.clearCache.projectRoots // ["~/dev"])[]' .claude/kit.json 2>/dev/null); [ -z "$roots" ] && roots="~/dev"
echo "$roots" | while IFS= read -r r; do
  r="${r/#\~/$HOME}"; [ -d "$r" ] || continue
  find "$r" -maxdepth 4 \( -name node_modules -o -name target \) -type d -prune 2>/dev/null |
  while IFS= read -r d; do
    proj=$(dirname "$d")
    [ "$(basename "$d")" = target ] && [ ! -f "$proj/Cargo.toml" ] && continue
    # Stale = no file in the project (outside dependency/build folders) changed within $days days.
    recent=$(find "$proj" -maxdepth 3 \( -name node_modules -o -name target -o -name .git \) -prune \
             -o -type f -mtime -"$days" -print -quit 2>/dev/null)
    [ -z "$recent" ] && echo "$(du -sh "$d" | cut -f1)	$d"
  done
done | sort -rh
SH
```

### 5. Report

Measure again with step 1's block, then give a short before/after table: each cache, its size
before and after, the total freed, and internal free space before and after. Call out anything
skipped and why (store not mounted, Docker not running, tool not installed).

## Rules

- **Never touch these, in any mode:** the Trash, `~/.cache/huggingface` (models are big and slow to
  download again), Docker volumes, Playwright `mcp-chrome-*` profiles, anything inside a project
  except the stale `node_modules` / `target` folders the user picked in `deep`.
- **Never `sudo`.** Every cache here belongs to the user.
- **External drives:** if a cache or project root is on an unmounted volume, skip it and say so.
  Never create a folder under `/Volumes/`, because it would sit on the internal drive where the
  missing volume should be mounted.
- **`report` changes nothing.**

---

## Project overrides

If `.claude/kit.json` has a `rules."clear-cache"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."clear-cache" // empty' .claude/kit.json 2>/dev/null
```
