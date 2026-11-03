#!/bin/bash
DB="cowork/brain/BRAIN.db"

# --- Kit sync: adopt kit files that shipped upstream since the last install ---
# Outside mode symlinks every kit path in, so file *content* is always current
# already. What does not follow automatically is a path that is NEW upstream —
# it needs a link plus a .gitignore line. This adds those, and only those.
#
# ADD-ONLY, deliberately. A link whose target vanished is reported, never
# removed: the hook cannot distinguish "deleted upstream" from "kit checkout is
# mid-rebase" or "external volume not mounted", and the safe reading of an
# ambiguous signal is to do nothing.
KIT_NOTICE=""

# Rewrite .gitignore with the managed block's repeated lines dropped, and ADD (if
# given) inserted just before the block's end. Lines outside the block are never
# touched. Only rewrites when something would change.
kit_gitignore_rewrite() {
  local gi=".gitignore" add="$1" tmp
  tmp=$(mktemp) || return 1
  awk -v add="$add" -v b="# BEGIN:tb-claude-kit" -v e="# END:tb-claude-kit" '
    $0 == b { inblock = 1 }
    $0 == e { if (add != "" && !(add in seen)) print add; inblock = 0 }
    inblock && $0 != b { if ($0 in seen) next; seen[$0] = 1 }
    { print }' "$gi" > "$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$gi"; then rm -f "$tmp"; else mv "$tmp" "$gi"; fi
}

# 0 = line added, 2 = already ignored, 1 = no managed block to add it to.
kit_gitignore_add() {
  local gi=".gitignore" rel="$1"
  [ -f "$gi" ] || return 1
  grep -qxF "# END:tb-claude-kit" "$gi" || return 1   # no managed block: install.sh's job
  grep -qxF "/$rel" "$gi" && return 2
  kit_gitignore_rewrite "/$rel"
}

# Two sessions starting together in one project would otherwise both read
# .gitignore, both add, and write over each other: a repeated line, or a lost one.
# mkdir is atomic, so it serves as the lock. A lock older than a minute belongs
# to a hook that died, and is taken over. If the lock can't be had in ~10s, skip
# the sync: the next session start does it.
kit_sync_locked() {
  local lock=".claude/.kit-sync.lock" i
  [ -d .claude ] || return 0
  for i in $(seq 50); do
    mkdir "$lock" 2>/dev/null && break
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rmdir "$lock" 2>/dev/null; continue
    fi
    sleep 0.2
  done
  [ -d "$lock" ] || return 0
  kit_sync
  [ -f .gitignore ] && grep -qxF "# END:tb-claude-kit" .gitignore && kit_gitignore_rewrite ""
  rmdir "$lock" 2>/dev/null
  return 0
}

kit_sync() {
  local self="${BASH_SOURCE[0]}"
  # Only outside mode has anything to sync — and there the hook is itself a
  # symlink into the kit, which is also how we find the kit. No env var, no
  # kitPath, no config. Inside mode leaves this a real file and we return here,
  # which is exactly right: those projects deliberately track no kit.
  [ -L "$self" ] || return 0

  local resolved kit
  resolved=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$self" 2>/dev/null) || return 0
  kit=$(cd "$(dirname "$resolved")/../.." 2>/dev/null && pwd) || return 0
  [ -d "$kit/.claude/skills" ] || return 0   # kit unreachable — do nothing, quietly

  # Honor the project's own opt-outs: fork = it owns its copy, exclude = it does
  # not want this at all. Compared as full rel paths, same as install.sh.
  # A missing or unparseable kit.json means this is not a project we understand.
  # install.sh always writes one, so its absence is a signal, not a default —
  # bail rather than guessing "outside, no opt-outs" and linking things in.
  local cfg mode skips
  cfg=$(python3 - .claude/kit.json <<'PY' 2>/dev/null
import json, sys
try: c = json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
print(c.get("mode", "outside"))
for p in list(c.get("fork", [])) + list(c.get("exclude", [])):
    print(p.strip("/"))
PY
) || return 0
  mode=$(printf '%s\n' "$cfg" | head -1)
  [ "$mode" = "outside" ] || return 0
  skips=$(printf '%s\n' "$cfg" | tail -n +2)

  # The same list install.sh builds: every skill folder, agent and hook in the
  # kit, plus the fixed paths in kit-manifest.txt (hand-maintained, read by both).
  local candidates
  candidates=$(cd "$kit" 2>/dev/null && {
    for d in .claude/skills/*/; do [ -d "$d" ] && echo "${d%/}"; done
    for f in .claude/agents/*.md .claude/hooks/*; do [ -f "$f" ] && echo "$f"; done
    grep -v '^[[:space:]]*\(#\|$\)' .claude/kit-manifest.txt 2>/dev/null
  } | sort -u)

  # Prefer the portable ~/.claude-kit pointer when it names this same checkout,
  # so new links match the ones install.sh writes.
  local link_base="$kit"
  if [ -d "$HOME/.claude-kit" ] &&
     [ "$(cd "$HOME/.claude-kit" && pwd -P 2>/dev/null)" = "$(cd "$kit" && pwd -P)" ]; then
    link_base="$HOME/.claude-kit"
  fi

  local added=() healed=0 rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -e "$kit/$rel" ] || continue                    # listed but absent upstream
    # Opt-outs first: a forked path is project-owned and must stay tracked, so it
    # must not pick up an ignore line in the healing branch below.
    printf '%s\n' "$skips" | grep -qxF "$rel" && continue
    # -e is false for a dangling link, so test -L too. Anything already present
    # (live link, dangling link, forked directory) keeps its content untouched...
    if [ -e "$rel" ] || [ -L "$rel" ]; then
      # ...but a kit symlink with no ignore line is drift worth healing: that is
      # exactly how a linked skill ends up showing as untracked in git status.
      if [ -L "$rel" ]; then
        kit_gitignore_add "$rel" && healed=$((healed + 1))
      fi
      continue
    fi
    mkdir -p "$(dirname "$rel")" 2>/dev/null
    ln -s "$link_base/$rel" "$rel" 2>/dev/null || continue
    kit_gitignore_add "$rel"
    added+=("$rel")
  done <<< "$candidates"

  # The brain DB stays out of git; sqlite_tracking snapshots carry it instead.
  local db_ignored=0 db_tracked=0
  if [ -f "cowork/brain/BRAIN.db" ]; then
    kit_gitignore_add "cowork/brain/BRAIN.db*" && db_ignored=1
    git ls-files --error-unmatch -- cowork/brain/BRAIN.db >/dev/null 2>&1 && db_tracked=1
  fi

  # Report-only pass: upstream deletions surface as dangling links.
  local stale=() l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ -L "$l" ] && [ ! -e "$l" ] && stale+=("$l")
  done <<< "$(printf '%s\n%s\n' "$candidates" "$(ls -d .claude/skills/* 2>/dev/null)" | sort -u)"

  [ "$db_ignored" -eq 1 ] && KIT_NOTICE="$KIT_NOTICE 🧰 Kit sync: added cowork/brain/BRAIN.db* to .gitignore (the brain DB stays out of git; see Kit conventions)."
  [ "$db_tracked" -eq 1 ] && KIT_NOTICE="$KIT_NOTICE 🧰 cowork/brain/BRAIN.db is still tracked in git, so it shows as modified after every session. Tell the user and offer to run: git rm --cached cowork/brain/BRAIN.db (add it to sqlite_tracking in .claude/kit.json first if they want its history in git)."
  [ ${#added[@]} -eq 0 ] && [ ${#stale[@]} -eq 0 ] && [ "$healed" -eq 0 ] && return 0
  if [ ${#added[@]} -gt 0 ]; then
    # Claude Code loads agent definitions before this hook runs, so a newly linked
    # agent only appears in the next session; skills and other files work now.
    local now=() next=() a
    for a in "${added[@]}"; do
      case "$a" in .claude/agents/*) next+=("$a") ;; *) now+=("$a") ;; esac
    done
    KIT_NOTICE="$KIT_NOTICE 🧰 Kit sync: linked $(IFS=', '; echo "${added[*]}") and updated .gitignore."
    [ ${#now[@]} -gt 0 ] && [ ${#next[@]} -eq 0 ] && KIT_NOTICE="$KIT_NOTICE Available this session."
    [ ${#next[@]} -gt 0 ] && [ ${#now[@]} -gt 0 ] && KIT_NOTICE="$KIT_NOTICE Skills and files are available this session."
    [ ${#next[@]} -gt 0 ] && KIT_NOTICE="$KIT_NOTICE The agent definitions load at the next session start, since Claude Code reads agents before this hook runs."
  fi
  if [ "$healed" -gt 0 ]; then
    KIT_NOTICE="$KIT_NOTICE Added $healed missing .gitignore line(s) for kit links that were already present."
  fi
  if [ ${#stale[@]} -gt 0 ]; then
    KIT_NOTICE="$KIT_NOTICE Dangling links (gone from the kit, left in place): $(IFS=', '; echo "${stale[*]}") — remove deliberately with install.sh."
  fi
}

# --- Memory in the repo: Claude's auto-memory lives in .claude/memory ---
# By default Claude Code keeps a project's auto-memory in its config folder, at
# <config>/projects/<repo root with every non-alphanumeric turned into ->/memory,
# where it is lost with the machine. The kit keeps it in the repo instead,
# committed with it:
#   - .claude/settings.local.json sets autoMemoryDirectory to <repo>/.claude/memory.
#     Local settings only: Claude Code ignores the key in the checked-in
#     settings.json, and the value is this machine's absolute path. User settings
#     would send every project's memory to one folder.
#   - The default folder becomes a link to the same place, so anything still using
#     it (an untrusted session, or a worktree, which shares the main checkout's
#     default) lands in the repo too. Memories already there are copied across
#     first, never overwriting, and the old folder is kept as memory.moved-<time>.
# kit.json "memory": {"inRepo": false} turns it off: the kit stops enforcing it
# and never undoes it. A PUBLIC GitHub repo is left alone unless inRepo is true,
# since memories hold personal notes; that is checked only while setup is missing.
#
# The hook adopts it for outside-mode projects, as kit_sync adopts new kit files.
# An inside-mode repo is often shared, and a collaborator's session must not move
# their memories into it; install.sh, run by the repo's owner, covers both modes
# with: session-start.sh memory --install [--dry-run]
MEMORY_NOTICE=""
MEM_STATUS=""   # ok | done | would | off | custom | skip | public | blocked
MEM_MSG=""
MEM_TELL="no"   # yes when the hook should say MEM_MSG this session

kit_tilde() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

kit_memory() {
  local dry="${1:-no}" caller="${2:-hook}"
  local root mem settings cfg san def
  MEM_STATUS="skip"; MEM_MSG="nothing to do here"; MEM_TELL="no"
  root=$(pwd -P 2>/dev/null) || return 0
  mem="$root/.claude/memory"
  settings="$root/.claude/settings.local.json"
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; cfg="${cfg%/}"
  # Claude Code truncates a name past 200 characters and adds a hash, and counts
  # UTF-16 units, so for a long or non-ASCII path the link is skipped rather than
  # guessed. The setting alone still moves the memory.
  san=""
  case "$root" in *[![:ascii:]]*) ;; *) san="${root//[^a-zA-Z0-9]/-}" ;; esac
  [ ${#san} -le 200 ] || san=""
  def=""; [ -n "$san" ] && def="$cfg/projects/$san/memory"

  # Cheap check first, so a project already set up costs two greps and a readlink.
  if [ "$caller" = "hook" ] && [ -f "$settings" ] &&
     grep -q '"autoMemoryDirectory"' "$settings" 2>/dev/null; then
    grep -qF "\"$mem\"" "$settings" 2>/dev/null || {   # pointed elsewhere on purpose
      MEM_STATUS="custom"; MEM_MSG="autoMemoryDirectory points elsewhere in .claude/settings.local.json, left alone"
      return 0; }
    if [ -d "$mem" ] && { [ -z "$def" ] || [ "$(readlink "$def" 2>/dev/null)" = "$mem" ]; }; then
      MEM_STATUS="ok"; return 0
    fi
  fi

  # Setup is missing or partial: read kit.json and the current setting exactly.
  local facts mode inrepo sstate cur
  facts=$(python3 - "$root/.claude/kit.json" "$settings" <<'PY' 2>/dev/null
import json, os, sys
try:
    c = json.load(open(sys.argv[1])); kit = "ok"
except Exception:
    c = {}; kit = "missing"
m = c.get("memory") if isinstance(c, dict) else None
v = m.get("inRepo") if isinstance(m, dict) else None
print(kit, c.get("mode", "outside") if isinstance(c, dict) else "outside",
      "true" if v is True else "false" if v is False else "default")
p = sys.argv[2]
if not os.path.exists(p):
    print("none"); print("")
else:
    try:
        s = json.load(open(p))
        if not isinstance(s, dict): raise ValueError
    except Exception:
        print("invalid"); print(""); sys.exit(0)
    d = s.get("autoMemoryDirectory")
    print("set" if isinstance(d, str) else "none"); print(d if isinstance(d, str) else "")
PY
) || return 0
  local kit
  { read -r kit mode inrepo; read -r sstate; IFS= read -r cur; } <<< "$facts"
  # No kit.json: the hook does not know this project. install.sh writes it first,
  # except in a dry run, where the defaults stand in.
  [ "$kit" = "ok" ] || [ "$caller" = "install" ] || {
    MEM_MSG="no .claude/kit.json here, so the hook leaves it alone"; return 0; }
  if [ "$caller" = "hook" ] && [ "$mode" != "outside" ]; then
    MEM_MSG="$mode mode: the hook leaves it to install.sh"; return 0
  fi

  # Is the current setting ours? Only an absolute path counts; Claude Code rejects others.
  local ours="no"
  case "$cur" in "~/"*) cur="$HOME/${cur#\~/}" ;; esac
  while [ "${cur%/}" != "$cur" ]; do cur="${cur%/}"; done
  if [ "$cur" = "$mem" ]; then ours="yes"
  else case "$cur" in /*) [ "$(cd "$cur" 2>/dev/null && pwd -P)" = "$mem" ] && ours="yes" ;; esac
  fi
  local link_ok="no"
  if [ -z "$def" ]; then link_ok="na"
  elif [ -L "$def" ] && { [ "$(readlink "$def")" = "$mem" ] ||
       { [ -d "$mem" ] && [ "$(cd "$def" 2>/dev/null && pwd -P)" = "$mem" ]; }; }; then link_ok="yes"
  fi

  if [ "$inrepo" = "false" ]; then
    MEM_STATUS="off"
    if [ "$ours" = "yes" ] || [ "$link_ok" = "yes" ]; then
      MEM_MSG="off (kit.json memory.inRepo = false), but this machine is still set up for it. To undo by hand:"
      [ "$ours" = "yes" ] && MEM_MSG="$MEM_MSG
remove \"autoMemoryDirectory\" from .claude/settings.local.json"
      [ "$link_ok" = "yes" ] && MEM_MSG="$MEM_MSG
replace the link $(kit_tilde "$def") with a copy of .claude/memory: rm it, then cp -R .claude/memory to that path"
    else
      MEM_MSG="off (kit.json memory.inRepo = false): memory stays in $(kit_tilde "$cfg")"
    fi
    return 0
  fi
  if [ "$sstate" = "set" ] && [ "$ours" = "no" ]; then
    MEM_STATUS="custom"; MEM_MSG="autoMemoryDirectory already points at $cur, left alone"; return 0
  fi
  if [ "$sstate" = "invalid" ]; then
    MEM_STATUS="blocked"; MEM_TELL="yes"; MEM_MSG="not set up: .claude/settings.local.json is not valid JSON. Fix it, then start a new session"
    return 0
  fi

  # Git facts in one call. A linked worktree shares the main checkout's default
  # folder, so the main checkout's link already covers it. A kit installed below
  # the git root gets the setting but no link: Claude Code keys the default on the
  # git root, which is not this project's alone.
  local in_git="no" top="" gd="" gc="" rel=""
  local gitfacts; gitfacts=$(git -C "$root" rev-parse --show-toplevel --git-dir --git-common-dir 2>/dev/null)
  if [ -n "$gitfacts" ]; then
    in_git="yes"
    { IFS= read -r top; IFS= read -r gd; IFS= read -r gc; } <<< "$gitfacts"
    top=$(cd "$top" 2>/dev/null && pwd -P)
    gd=$(cd "$root" && cd "$gd" 2>/dev/null && pwd -P)
    gc=$(cd "$root" && cd "$gc" 2>/dev/null && pwd -P)
    if [ -n "$gd" ] && [ "$gd" != "$gc" ]; then
      MEM_STATUS="skip"; MEM_MSG="a linked worktree: it uses the main checkout's memory, so set it up there"
      return 0
    fi
    if [ "$top" != "$root" ]; then def=""; link_ok="na"; rel="${root#"$top"/}/"; fi
  fi

  if [ "$ours" = "no" ]; then
    if [ "$in_git" = "yes" ] &&
       git -C "$root" ls-files --error-unmatch -- .claude/settings.local.json >/dev/null 2>&1; then
      MEM_STATUS="blocked"; MEM_TELL="yes"
      MEM_MSG="not set up: .claude/settings.local.json is tracked in git, and the setting holds this machine's path. Untrack it (git rm --cached .claude/settings.local.json), then start a new session"
      return 0
    fi
    # Public check, only while setup is missing. The hook asks once per clone: the
    # answer is kept in the git dir, and install.sh asks again.
    if [ "$inrepo" != "true" ]; then
      local marker="" url vis=""
      [ -n "$gc" ] && marker="$gc/claude-kit-memory-public"
      if [ "$caller" = "hook" ] && [ -n "$marker" ] && [ -f "$marker" ]; then
        MEM_STATUS="public"   # said once already, so quiet
        MEM_MSG="left in the config folder: origin was found to be a PUBLIC GitHub repo (install.sh checks again). To keep memories in .claude/memory anyway, set \"memory\": {\"inRepo\": true} in .claude/kit.json"
        return 0
      fi
      url=$(git -C "$root" config --get remote.origin.url 2>/dev/null)
      case "$url" in
        *github.com[:/]*)
          if command -v gh >/dev/null 2>&1; then
            # Bounded, and any failure reads as unknown, never as public.
            vis=$(GH_PROMPT_DISABLED=1 python3 - "$url" <<'PY' 2>/dev/null
import re, subprocess, sys
m = re.search(r"github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?/*$", sys.argv[1])
if m:
    try:
        r = subprocess.run(["gh", "repo", "view", m.group(1), "--json", "visibility", "-q", ".visibility"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0: print(r.stdout.strip())
    except Exception:
        pass
PY
)
          fi ;;
      esac
      if [ "$vis" = "PUBLIC" ]; then
        MEM_STATUS="public"; MEM_TELL="yes"
        MEM_MSG="left in the config folder: origin is a PUBLIC GitHub repo, and memories hold personal notes. To keep them in .claude/memory anyway, set \"memory\": {\"inRepo\": true} in .claude/kit.json"
        [ "$dry" = "no" ] && [ -n "$marker" ] && { date +%Y-%m-%d > "$marker"; } 2>/dev/null
        return 0
      fi
      [ "$dry" = "no" ] && [ -n "$marker" ] && rm -f "$marker" 2>/dev/null
    fi
  fi

  # --- act (or, in a dry run, say what would happen) ---
  local moved=0 failed=0 aside="" linked="no" wrote="no" notes=""
  MEM_MSG=""
  if [ ! -d "$mem" ] && [ "$dry" = "no" ]; then
    mkdir -p "$mem" 2>/dev/null || {
      MEM_STATUS="blocked"; MEM_TELL="yes"; MEM_MSG="not set up: could not create .claude/memory"; return 0; }
  fi

  if [ "$link_ok" = "no" ]; then
    if [ -d "$def" ]; then
      # Copy every memory the repo lacks (no overwrite; a MEMORY.md index present on
      # both sides gains the old one's entries for files it does not list yet).
      local counts
      counts=$(python3 - "$def" "$mem" "$dry" <<'PY' 2>/dev/null
import os, re, shutil, sys
src, dst, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "yes"
moved = failed = 0
for d, dirs, files in os.walk(src):
    dirs[:] = [x for x in dirs if not x.startswith(".")]
    for f in files:
        if f.startswith("."): continue
        r = os.path.normpath(os.path.join(os.path.relpath(d, src), f)); t = os.path.join(dst, r)
        try:
            if r == "MEMORY.md" and os.path.exists(t):
                have = open(t, encoding="utf-8", errors="replace").read()
                add = []
                for line in open(os.path.join(d, f), encoding="utf-8", errors="replace").read().splitlines():
                    if not line.startswith("- "): continue
                    k = re.search(r"\]\x28([^\x29]+)\x29", line)
                    if (k.group(1) if k else line) not in have: add.append(line)
                if add and not dry:
                    with open(t, "a", encoding="utf-8") as fh:
                        fh.write(("" if have.endswith("\n") or not have else "\n") + "\n".join(add) + "\n")
                continue
            if os.path.lexists(t): continue
            if f.endswith(".md") and r != "MEMORY.md": moved += 1
            if not dry:
                os.makedirs(os.path.dirname(t), exist_ok=True); shutil.copy2(os.path.join(d, f), t)
        except Exception:
            failed += 1
print(moved, failed)
PY
) || counts="0 1"
      read -r moved failed <<< "$counts"
      if [ "${failed:-1}" != "0" ]; then
        MEM_STATUS="blocked"; MEM_TELL="yes"
        MEM_MSG="not set up: could not copy every memory from $(kit_tilde "$def") into .claude/memory. Nothing was moved; check the folder, then start a new session"
        return 0
      fi
    fi
    if [ "$dry" = "no" ]; then
      if [ -d "$def" ] && [ ! -L "$def" ] && rmdir "$def" 2>/dev/null; then
        :   # an empty folder: nothing to keep
      elif [ -e "$def" ] || [ -L "$def" ]; then
        aside="$def.moved-$(date +%Y%m%d-%H%M%S)"
        { [ -e "$aside" ] || [ -L "$aside" ]; } && aside="$aside-$$"
        mv "$def" "$aside" 2>/dev/null || {
          MEM_STATUS="blocked"; MEM_TELL="yes"; MEM_MSG="not set up: could not move $(kit_tilde "$def") aside"; return 0; }
      fi
      mkdir -p "$(dirname "$def")" 2>/dev/null && ln -s "$mem" "$def" 2>/dev/null && linked="yes"
    else
      linked="yes"
      { [ -e "$def" ] || [ -L "$def" ]; } && aside="$def.moved-<time>"
    fi
  fi

  if [ "$ours" = "no" ]; then
    if [ "$dry" = "no" ]; then
      python3 - "$settings" "$mem" <<'PY' 2>/dev/null || {
import json, os, shutil, sys, tempfile
p, d = sys.argv[1], sys.argv[2]
s = json.load(open(p)) if os.path.exists(p) else {}
s["autoMemoryDirectory"] = d
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p))
with os.fdopen(fd, "w") as fh:
    json.dump(s, fh, indent=2, ensure_ascii=False); fh.write("\n")
if os.path.exists(p): shutil.copymode(p, tmp)
os.replace(tmp, p)
PY
        MEM_STATUS="blocked"; MEM_TELL="yes"; MEM_MSG="not set up: could not write .claude/settings.local.json"; return 0; }
    fi
    wrote="yes"
    # The file now holds this machine's path: keep it out of git. Claude Code adds a
    # global ignore rule for it, but only once it has written the file itself.
    if [ "$in_git" = "yes" ] && ! git -C "$root" check-ignore -q .claude/settings.local.json 2>/dev/null; then
      if [ "$dry" = "no" ]; then
        mkdir -p "$gc/info" 2>/dev/null && printf '/%s.claude/settings.local.json\n' "$rel" >> "$gc/info/exclude"
      fi
      notes="$notes .claude/settings.local.json $([ "$dry" = "yes" ] && echo "would be" || echo "is now") ignored in .git/info/exclude."
    fi
    if [ "$in_git" = "yes" ] && git -C "$root" check-ignore -q .claude/memory/probe.md 2>/dev/null; then
      notes="$notes Note: .claude/memory is gitignored here, so memories are not committed until that rule goes."
    fi
  fi

  local noun="memories" them="them"; [ "$moved" = "1" ] && noun="memory" && them="it"
  if [ "$dry" = "yes" ]; then
    if [ "$moved" -gt 0 ]; then MEM_MSG="would move $moved $noun into .claude/memory and point Claude there"
    elif [ "$wrote" = "yes" ]; then MEM_MSG="would point Claude's memories at .claude/memory"
    elif [ "$linked" = "yes" ]; then MEM_MSG="would link $(kit_tilde "$def") to .claude/memory"
    fi
    [ -n "$aside" ] && MEM_MSG="$MEM_MSG, keeping the old folder as $(kit_tilde "$aside")"
    [ -n "$MEM_MSG" ] && MEM_MSG="$MEM_MSG.$notes"
    MEM_STATUS="would"; [ -n "$MEM_MSG" ] || MEM_STATUS="ok"
  else
    if [ "$moved" -gt 0 ]; then MEM_MSG="moved $moved $noun into .claude/memory — commit $them."
    elif [ "$wrote" = "yes" ]; then MEM_MSG="Claude's memories for this project now go to .claude/memory; commit them with the repo."
    elif [ "$linked" = "yes" ]; then MEM_MSG="linked $(kit_tilde "$def") to .claude/memory."
    fi
    [ -n "$aside" ] && MEM_MSG="$MEM_MSG Old folder kept as $(kit_tilde "$aside")."
    MEM_MSG="$MEM_MSG$notes"
    MEM_STATUS="done"; MEM_TELL="yes"; [ -n "$MEM_MSG" ] || { MEM_STATUS="ok"; MEM_TELL="no"; }
  fi
  return 0
}

# install.sh's view of kit_memory: one [tag] line, then any detail lines indented.
kit_memory_report() {
  local tag="" first rest=""
  first="${MEM_MSG%%$'\n'*}"
  [ "$first" != "$MEM_MSG" ] && rest="${MEM_MSG#*$'\n'}"
  case "$MEM_STATUS" in
    ok)      tag="[ok]  "; first=".claude/memory (already in place)" ;;
    done)    tag="[add] " ;;
    would)   tag="[add] "; first="$first (dry run)" ;;
    off)     tag="[off] " ;;
    custom)  tag="[keep]" ;;
    *)       tag="[skip]" ;;
  esac
  echo "  $tag memory: $first"
  [ -n "$rest" ] && printf '%s\n' "$rest" | sed 's/^/           /'
  case "$MEM_STATUS" in
    done|would) echo "           config folder: $(kit_tilde "${CLAUDE_CONFIG_DIR:-$HOME/.claude}") (set CLAUDE_CONFIG_DIR if Claude runs this project under another)" ;;
  esac
  return 0
}

# CLI: install.sh (and anyone checking by hand) runs just the memory step.
#   session-start.sh memory [--install] [--dry-run]
# --install applies install.sh's rules: both modes, and the public check re-asked.
if [ "${1:-}" = "memory" ]; then
  mem_dry="no"; mem_caller="hook"
  for mem_arg in "$@"; do
    case "$mem_arg" in --dry-run) mem_dry="yes" ;; --install) mem_caller="install" ;; esac
  done
  kit_memory "$mem_dry" "$mem_caller"
  kit_memory_report
  exit 0
fi

# --- Hook input: Claude Code passes JSON on stdin (session_id, source) ---
# source is startup | resume | clear | compact. The session_id is the only stable
# key a SessionStart and its SessionEnd share: each hook runs in its own shell, so
# a shell PID never matches across them.
HOOK_INPUT=""
[ -t 0 ] || HOOK_INPUT=$(cat)
read -r SESSION_ID SOURCE <<< "$(printf '%s' "$HOOK_INPUT" | python3 -c '
import json, re, sys
try: d = json.load(sys.stdin)
except Exception: d = {}
sid = re.sub(r"[^A-Za-z0-9-]", "", str(d.get("session_id") or ""))
src = re.sub(r"[^a-z]", "", str(d.get("source") or "startup"))
print(sid or "-", src or "startup")' 2>/dev/null)"
[ "${SESSION_ID:-}" = "-" ] && SESSION_ID=""
SOURCE="${SOURCE:-startup}"

kit_sync_locked
KIT_NOTICE="${KIT_NOTICE# }"
kit_memory
[ "$MEM_TELL" = "yes" ] && MEMORY_NOTICE="🧠 Memory: $MEM_MSG"

# --- Kit conventions: .claude/KIT.md, injected here rather than @-imported ---
# CLAUDE.md @imports do not follow a symlink, and in outside mode KIT.md is one.
# Injecting it keeps every linked project on the kit's current wording.
KIT_RULES=""
[ -f .claude/KIT.md ] && KIT_RULES=$(cat .claude/KIT.md)

# --- Writing rules: the owner's named sets and the project's (scripts/writing-rules has the rules) ---
# Injected with the conventions, so both emit paths below carry them.
if [ -x "$HOME/.claude-kit/scripts/writing-rules" ]; then
  WRITING_RULES=$("$HOME/.claude-kit/scripts/writing-rules" . 2>/dev/null)
  [ -n "$WRITING_RULES" ] && KIT_RULES="${KIT_RULES:+$KIT_RULES

}$WRITING_RULES"
fi

# --- Mantra: a block in CLAUDE.md, loaded with it. Here only its health is checked. ---
MANTRA_BUDGET=4000
MANTRA_NOTICE=""
if [ -f CLAUDE.md ]; then
  if grep -qx '<!-- BEGIN:mantra -->' CLAUDE.md && grep -qx '<!-- END:mantra -->' CLAUDE.md; then
    MANTRA_LEN=$(awk '/^<!-- BEGIN:mantra -->$/{f=1;next} /^<!-- END:mantra -->$/{f=0} f' CLAUDE.md | wc -c | tr -d ' ')
    if [ "$MANTRA_LEN" -gt $((MANTRA_BUDGET + MANTRA_BUDGET / 4)) ]; then
      MANTRA_NOTICE="✂️ The mantra in CLAUDE.md is $MANTRA_LEN characters, over its ~$MANTRA_BUDGET budget. Condense it this session (rewrite, keep what a fresh session needs most)."
    fi
  else
    MANTRA_NOTICE="✂️ CLAUDE.md has no mantra block. Add a '## Mantra' section at the end holding the line <!-- BEGIN:mantra --> and the line <!-- END:mantra -->, and keep the mantra between them."
  fi
fi

# --- Legacy brain files: the mantra used to live in the DB and MANTRA.md ---
LEGACY_NOTICE=""
legacy=()
[ -f cowork/brain/MANTRA.md ] && legacy+=("cowork/brain/MANTRA.md")
[ -f cowork/brain/BRAIN.md ] && legacy+=("cowork/brain/BRAIN.md")
if [ -f "$DB" ]; then
  for t in mantra journal; do
    [ -n "$(sqlite3 "$DB" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='$t';" 2>/dev/null)" ] && legacy+=("the $t table")
  done
fi
if [ ${#legacy[@]} -gt 0 ]; then
  LEGACY_NOTICE="🧹 Old brain layout found ($(IFS=', '; echo "${legacy[*]}")). Tell the user, and offer to run: bash ~/.claude-kit/scripts/brain-migrate (it moves the DB mantra into CLAUDE.md, removes the exports, and drops the old tables; --dry-run shows the plan)."
fi

# --- Restore a missing brain from its NDJSON snapshots (fresh clone) ---
# Never in a linked worktree: the brain has one copy, in the main checkout.
RESTORE_NOTICE=""
if [ ! -f "$DB" ] && [ -f cowork/brain/BRAIN.airsqlite/logs.snapshot.ndjson ] && [ -f cowork/brain/schema.sql ] &&
   [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] &&
   [ -x "$HOME/.claude-kit/scripts/sqlite-sidecar.sh" ]; then
  if "$HOME/.claude-kit/scripts/sqlite-sidecar.sh" restore "$DB" cowork/brain/schema.sql >/dev/null 2>&1; then
    RESTORE_NOTICE="♻️ BRAIN.db was missing and was rebuilt from cowork/brain/BRAIN.airsqlite."
  fi
fi

join_notices() {
  local out="" n
  for n in "$@"; do [ -n "$n" ] && out="$out${out:+

}$n"; done
  printf '%s' "$out"
}

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
    "$(printf '%s' "$1" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')"
}

if [ ! -f "$DB" ]; then
  # Still surface the notices and kit conventions in a project with no brain DB.
  emit "$(join_notices "$KIT_NOTICE" "$MEMORY_NOTICE" "$MANTRA_NOTICE" "$LEGACY_NOTICE" "$KIT_RULES")"
  exit 0
fi

# --- Schema integrity guard: auto-migrate drift and SURFACE it (never fail silently) ---
# CREATE TABLE IF NOT EXISTS can add missing *tables* but never missing *columns* on an
# existing table, so an old DB silently drifts and every query below returns empty. This
# heals both and injects a visible notice into the session context when it does.
SCHEMA_NOTICE=""
SCHEMA_FILE="cowork/brain/schema.sql"
if [ -f "$SCHEMA_FILE" ]; then
  HEALED=""
  ensure_col() {
    local table="$1" col="$2" def="$3" cols
    cols=$(sqlite3 "$DB" "PRAGMA table_info($table);" 2>/dev/null | awk -F'|' '{print $2}')
    [ -n "$cols" ] || return 0   # table absent: the schema below creates it whole
    printf '%s\n' "$cols" | grep -qx "$col" && return 0
    sqlite3 "$DB" "ALTER TABLE $table ADD COLUMN $def;" 2>/dev/null && HEALED="$HEALED $table.$col"
  }
  # Columns that a CREATE TABLE IF NOT EXISTS re-apply cannot backfill:
  ensure_col logs     priority      "priority INTEGER"
  ensure_col logs     tier          "tier TEXT NOT NULL DEFAULT 'warm' CHECK (tier IN ('hot','warm','cold','archived'))"
  ensure_col logs     completed_at  "completed_at TEXT"
  ensure_col logs     superseded_by "superseded_by INTEGER REFERENCES logs(id)"
  ensure_col sessions session_id    "session_id TEXT"
  # (re)apply schema to create any missing tables + indexes. Columns are ensured
  # first so index creation (e.g. idx_logs_tier) can't fail.
  SCHEMA_ERR=$(sqlite3 "$DB" < "$SCHEMA_FILE" 2>&1 >/dev/null)
  if [ -n "$HEALED" ] || [ -n "$SCHEMA_ERR" ]; then
    SCHEMA_NOTICE="⚠️ BRAIN.db schema was out of date and auto-migrated at session start."
    [ -n "$HEALED" ] && SCHEMA_NOTICE="$SCHEMA_NOTICE Added missing columns:$HEALED."
    [ -n "$SCHEMA_ERR" ] && SCHEMA_NOTICE="$SCHEMA_NOTICE Remaining errors: $SCHEMA_ERR"
  fi
fi

# --- Session row, keyed by Claude Code's session_id ---
# A resume, /compact or second start of the same session reuses its row. Other
# sessions running in parallel are left alone: nothing here closes them.
NEW_SESSION="no"
PREV_START=""
EXISTING=""
[ -n "$SESSION_ID" ] && EXISTING=$(sqlite3 "$DB" "SELECT id FROM sessions WHERE session_id = '$SESSION_ID' LIMIT 1;")
if [ -n "$EXISTING" ]; then
  sqlite3 "$DB" "UPDATE sessions SET ended_at = NULL WHERE id = $EXISTING;"
else
  PREV_START=$(sqlite3 "$DB" "SELECT started_at FROM sessions ORDER BY id DESC LIMIT 1;")
  if [ -n "$SESSION_ID" ]; then
    sqlite3 "$DB" "INSERT INTO sessions (session_id) VALUES ('$SESSION_ID');"
  else
    sqlite3 "$DB" "INSERT INTO sessions DEFAULT VALUES;"
  fi
  NEW_SESSION="yes"
fi

# Recalculate tiers — Phase 1 (SQL)
sqlite3 "$DB" "
UPDATE logs SET tier = 'archived'
WHERE status IN ('done', 'dropped', 'superseded') OR importance = 0;

UPDATE logs SET tier = 'cold'
WHERE status IN ('active', 'blocked');

UPDATE logs SET tier = 'warm'
WHERE status IN ('active', 'blocked') AND (
  importance >= 6
  OR created_at >= datetime('now', '-14 days', 'localtime')
);

UPDATE logs SET tier = 'hot'
WHERE status IN ('active', 'blocked') AND focus = 1;
"

# Recalculate tiers — Phase 2 (plan momentum)
PLAN_IDS=$(sqlite3 "$DB" "SELECT DISTINCT json_extract(meta, '\$.plan_id') FROM logs WHERE type='task' AND status='active' AND json_extract(meta, '\$.plan_id') IS NOT NULL;")
for PLAN_ID in $PLAN_IDS; do
  case "$PLAN_ID" in *[!A-Za-z0-9_-]*) continue ;; esac
  HAS_COMPLETION=$(sqlite3 "$DB" "SELECT count(*) FROM logs WHERE json_extract(meta, '\$.plan_id') = '$PLAN_ID' AND completed_at >= datetime('now', '-14 days', 'localtime');")
  # Unix seconds straight from git: %aI's offset has a colon ("-07:00") that BSD date's %z cannot
  # parse, which left every plan without file momentum. Plain arithmetic works on macOS and Linux.
  MOD_TS=$(git log -1 --format=%at -- "cowork/plans/*${PLAN_ID}*.md" 2>/dev/null)
  DOMINATED=0
  if [ "$HAS_COMPLETION" -gt 0 ]; then
    DOMINATED=1
  elif [ -n "$MOD_TS" ]; then
    CUTOFF=$(( $(date +%s) - 14 * 86400 ))
    if [ "$MOD_TS" -gt "$CUTOFF" ]; then
      DOMINATED=1
    fi
  fi
  if [ "$DOMINATED" -eq 1 ]; then
    sqlite3 "$DB" "UPDATE logs SET tier = 'hot' WHERE type='task' AND status='active' AND json_extract(meta, '\$.plan_id') = '$PLAN_ID';"
  fi
done

# Query brain state
FOCUS=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, title, pillar FROM logs WHERE focus = 1 AND status = 'active';")
RECENT=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, type, title FROM logs ORDER BY created_at DESC LIMIT 8;")
TASKS=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, title, pillar FROM logs WHERE type = 'task' AND status = 'active' ORDER BY pillar, priority;")
QUESTIONS=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, title FROM logs WHERE type = 'question' AND status = 'active';")

# What the previous session added: the input to the mantra review. Only on a
# genuinely new session — a resume or /compact has already had its review.
SINCE=""
if [ "$NEW_SESSION" = "yes" ] && [ -n "$PREV_START" ] && { [ "$SOURCE" = "startup" ] || [ "$SOURCE" = "clear" ]; }; then
  SINCE=$(sqlite3 -separator ' | ' "$DB" "SELECT '#' || id, type, title FROM logs WHERE created_at >= '$PREV_START' ORDER BY created_at DESC LIMIT 15;")
fi

CTX="## Brain State (auto-loaded at session start)"
NOTICES=$(join_notices "$SCHEMA_NOTICE" "$RESTORE_NOTICE" "$KIT_NOTICE" "$MEMORY_NOTICE" "$LEGACY_NOTICE" "$MANTRA_NOTICE")
[ -n "$NOTICES" ] && CTX="$CTX

$NOTICES"

CTX="$CTX

### Focus Items
${FOCUS:-No focus items set.}

### Active Tasks
${TASKS:-No active tasks.}"

[ -n "$QUESTIONS" ] && CTX="$CTX

### Open Questions
$QUESTIONS"

CTX="$CTX

### Recent Entries
${RECENT:-None yet.}"

if [ -n "$SINCE" ]; then
  CTX="$CTX

### Since the last session (started $PREV_START)
$SINCE

Mantra review: check these against the mantra in CLAUDE.md, per Kit conventions below. Update it or skip, without asking."
fi

[ -n "$KIT_RULES" ] && CTX="$CTX

$KIT_RULES"

emit "$CTX"
