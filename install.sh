#!/bin/bash
set -euo pipefail

# TB Claude Kit — install or update a project
#
# Usage:
#   cd /path/to/your/project
#   bash ~/.claude-kit/install.sh
#
# Modes (recorded in .claude/kit.json):
#
#   outside repo (default) — kit files are SYMLINKS into your kit checkout.
#     Gitignored, never travel with the repo. Edit the kit once, every linked
#     project sees it next session. Requires the kit present on the machine.
#
#   inside repo — kit files are REAL FILES, tracked in git, travelling with
#     the repo. Updated by re-running this script, with drift detection.
#     Choose this if a machine without your kit checkout must be able to use
#     the repo (shared repos, cloud sessions, handing it to someone else).
#
#   Chooser: does a machine without your kit checkout need this repo to work?
#            yes -> inside.  no -> outside.
#
# Flags:
#   --mode inside|outside   Set/convert the project's mode (lossless both ways)
#   --yes                   Auto-update drifted files + enable all integrations
#   --dry-run               Report what would change without touching anything
#   --replace               In outside mode, replace occupied paths with symlinks
#                           (DESTRUCTIVE — commit first; see "occupied" below)
#   --help                  This message
#
# Kit path resolution (where symlinks point), first hit wins:
#   1. $TB_CLAUDE_KIT
#   2. "kitPath" in the project's .claude/kit.json
#   3. ~/.claude-kit
#   4. the directory this script lives in (with a portability warning)
#
# Occupied paths:
#   In outside mode, a kit path that already holds a REAL file or directory is
#   reported as [occupied] and left alone. Resolve it by either adding the path
#   to "fork" in kit.json (the project owns it), or committing the current
#   content and re-running with --replace.
#
# fork vs exclude (both are kit.json arrays of repo-relative paths):
#   "fork"    — the path exists here and the PROJECT owns it. The kit never
#               links, copies, or gitignores it. Use when you need different
#               behaviour from the kit's version.
#   "exclude" — the path has no business existing here at all. Never installed
#               in either mode. Use to install a subset of the kit, e.g. a
#               non-technical user's repo that should not carry dev skills.
#               Excluding does not delete what is already on disk; the script
#               reports leftovers so you can remove them deliberately.

# ============================================================
# FLAGS
# ============================================================

MODE_OVERRIDE=""
INTEGRATION_MODE="prompt"
DRIFT_MODE="prompt"
REPLACE="no"
DRY_RUN="no"

usage() { sed -n '3,45p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)     MODE_OVERRIDE="${2:-}"; shift 2 ;;
    --mode=*)   MODE_OVERRIDE="${1#*=}"; shift ;;
    --yes)      INTEGRATION_MODE="yes"; DRIFT_MODE="update"; shift ;;
    --dry-run|--no-mcps)
                INTEGRATION_MODE="no"; DRIFT_MODE="skip"; DRY_RUN="yes"; shift ;;
    --replace)  REPLACE="yes"; shift ;;
    --help|-h)  usage; exit 0 ;;
    *)          echo "Unknown flag: $1" >&2; echo "Try --help" >&2; exit 1 ;;
  esac
done

if [ -n "$MODE_OVERRIDE" ] && [ "$MODE_OVERRIDE" != "inside" ] && [ "$MODE_OVERRIDE" != "outside" ]; then
  echo "--mode must be 'inside' or 'outside' (got: $MODE_OVERRIDE)" >&2
  exit 1
fi

if [ "$INTEGRATION_MODE" = "prompt" ] && ! [ -t 0 ]; then
  INTEGRATION_MODE="yes"
  DRIFT_MODE="report"
  echo "(Non-interactive shell — drifts reported with diffs. Pass --yes to auto-update.)"
fi

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$(pwd)"
KIT_JSON="$TARGET_DIR/.claude/kit.json"

if [ "$KIT_DIR" = "$TARGET_DIR" ]; then
  echo "Refusing to install the kit into itself." >&2
  echo "cd to your project first, then run: bash $KIT_DIR/install.sh" >&2
  exit 1
fi

# ============================================================
# kit.json READERS
# ============================================================

json_str() {
  # json_str <key> — top-level string value, empty if absent/unreadable
  [ -f "$KIT_JSON" ] || return 0
  python3 -c "
import json,sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
v = d.get(sys.argv[2])
print(v if isinstance(v, str) else '')
" "$KIT_JSON" "$1" 2>/dev/null || true
}

json_list() {
  # json_list <key> — one array element per line
  [ -f "$KIT_JSON" ] || return 0
  python3 -c "
import json,sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
for x in (d.get(sys.argv[2]) or []):
    if isinstance(x, str): print(x)
" "$KIT_JSON" "$1" 2>/dev/null || true
}

# ============================================================
# MODE
# ============================================================

RECORDED_MODE="$(json_str mode)"
if [ -n "$MODE_OVERRIDE" ]; then
  MODE="$MODE_OVERRIDE"
elif [ -n "$RECORDED_MODE" ]; then
  MODE="$RECORDED_MODE"
else
  MODE="outside"
fi

CONVERTING="no"
if [ -n "$RECORDED_MODE" ] && [ "$MODE" != "$RECORDED_MODE" ]; then
  CONVERTING="yes"
fi

# ============================================================
# KIT PATH (symlink target base)
# ============================================================

same_dir() { [ "$(cd "$1" 2>/dev/null && pwd -P)" = "$(cd "$2" 2>/dev/null && pwd -P)" ]; }

same_content() {
  # same_content KIT_SRC TARGET — true if target is byte-identical to the kit's
  # version. Directories compare recursively.
  local a="$1" b="$2"
  [ -e "$a" ] && [ -e "$b" ] || return 1
  if [ -d "$a" ]; then
    [ -d "$b" ] || return 1
    diff -r "$a" "$b" > /dev/null 2>&1
  else
    [ -f "$b" ] || return 1
    diff -q "$a" "$b" > /dev/null 2>&1
  fi
}

LINK_BASE=""
LINK_BASE_NOTE=""
CONFIGURED_KIT_PATH="$(json_str kitPath)"

if [ -n "${TB_CLAUDE_KIT:-}" ] && [ -d "$TB_CLAUDE_KIT" ]; then
  LINK_BASE="$TB_CLAUDE_KIT"
  LINK_BASE_NOTE="\$TB_CLAUDE_KIT"
elif [ -n "$CONFIGURED_KIT_PATH" ] && [ -d "${CONFIGURED_KIT_PATH/#\~/$HOME}" ]; then
  LINK_BASE="${CONFIGURED_KIT_PATH/#\~/$HOME}"
  LINK_BASE_NOTE="kit.json kitPath"
elif [ -d "$HOME/.claude-kit" ]; then
  LINK_BASE="$HOME/.claude-kit"
  LINK_BASE_NOTE="~/.claude-kit"
else
  LINK_BASE="$KIT_DIR"
  LINK_BASE_NOTE="this script's directory"
fi

if [ "$MODE" = "outside" ] && ! same_dir "$LINK_BASE" "$KIT_DIR"; then
  echo "Kit path mismatch:" >&2
  echo "  running from : $KIT_DIR" >&2
  echo "  would link to: $LINK_BASE  ($LINK_BASE_NOTE)" >&2
  echo "These must be the same checkout. Fix \$TB_CLAUDE_KIT / kit.json kitPath / ~/.claude-kit." >&2
  exit 1
fi

echo "Installing Claude kit into: $TARGET_DIR"
echo "Mode: $MODE repo$([ "$CONVERTING" = "yes" ] && echo "  (converting from $RECORDED_MODE)")"
if [ "$MODE" = "outside" ]; then
  echo "Kit:  $LINK_BASE  ($LINK_BASE_NOTE)"
  if [ "$LINK_BASE" = "$KIT_DIR" ] && [ ! -e "$HOME/.claude-kit" ]; then
    echo ""
    echo "  Note: symlinks will use an absolute path to this checkout. For portability"
    echo "        across machines, create the standard pointer once:"
    echo "          ln -s \"$KIT_DIR\" ~/.claude-kit"
  fi
else
  echo "Kit:  $KIT_DIR"
fi
[ "$DRY_RUN" = "yes" ] && echo "(dry run — nothing will be written)"
echo ""

# ============================================================
# MANIFESTS
# ============================================================

# Kit-managed: linkable in outside mode, drift-detected in inside mode.
KIT_PATHS=()
for skill_dir in "$KIT_DIR/.claude/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  KIT_PATHS+=(".claude/skills/$(basename "$skill_dir")")
done
KIT_PATHS+=(
  ".claude/hooks/session-start.sh"
  ".vscode/extensions.json"
  ".vscode/settings.json"
  "cowork/brain/schema.sql"
  "cowork/brain/USAGE.md"
  "cowork/vibe-audit/PROCEDURE.md"
  "cowork/vibe-audit/schema.sql"
  "cowork/architecture/PROCEDURE.md"
  "cowork/architecture/schema.sql"
  "scripts/puppeteer-server.cjs"
  "scripts/artifact-bridge.cjs"
)

# Publish KIT_PATHS into the kit checkout so the session-start hook can adopt new
# kit files without re-running this script. The hook globs skills on its own, but
# has no way to know about the fixed paths above — this is that list, shared.
# Best-effort: a read-only or otherwise unwritable kit checkout is not an error.
if [ "$DRY_RUN" = "no" ] && [ -w "$KIT_DIR/.claude" ]; then
  printf '%s\n' "${KIT_PATHS[@]}" > "$KIT_DIR/.claude/kit-manifest.txt" 2>/dev/null || true
fi

# Project-owned scaffolding: copied once if absent, never updated, never linked.
SCAFFOLD_PATHS=(
  "CLAUDE.md"
  ".claude/settings.json"
  ".claude/settings.local.json"
  ".mcp.json"
  "cowork/vibe-audit/GUARDRAILS.md"
  "cowork/vibe-audit/seed.sql"
  "cowork/architecture/seed.sql"
  "cowork/video/caption-dictionary.json"
)

FORK_LIST="$(json_list fork)"
EXCLUDE_LIST="$(json_list exclude)"

is_forked() {
  local rel="$1"
  [ -n "$FORK_LIST" ] || return 1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ "${f%/}" = "${rel%/}" ] && return 0
  done <<< "$FORK_LIST"
  return 1
}

# exclude != fork. fork means "the project owns this path, kit hands it over".
# exclude means "this path has no business existing here" — never linked, never
# copied, never gitignored. Used to install a subset of the kit.
is_excluded() {
  local rel="$1"
  [ -n "$EXCLUDE_LIST" ] || return 1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ "${f%/}" = "${rel%/}" ] && return 0
  done <<< "$EXCLUDE_LIST"
  return 1
}

# ============================================================
# COUNTERS
# ============================================================

ADD_COUNT=0; OK_COUNT=0; UPDATE_COUNT=0; DRIFT_COUNT=0; KEEP_COUNT=0
LINK_COUNT=0; OCCUPIED_COUNT=0; FORK_COUNT=0; MATERIALIZE_COUNT=0; UNTRACK_COUNT=0; EXCLUDE_COUNT=0
STALE_EXCLUDED=()
OCCUPIED_PATHS=()

# ============================================================
# HELPERS
# ============================================================

drift_stats() {
  local added removed
  added=$(diff "$1" "$2" 2>/dev/null | grep -c '^>' || true)
  removed=$(diff "$1" "$2" 2>/dev/null | grep -c '^<' || true)
  echo "+$added/-$removed"
}

handle_drift() {
  local src="$1" dst="$2" label="$3"
  local stats; stats=$(drift_stats "$dst" "$src")

  case "$DRIFT_MODE" in
    update)
      UPDATE_COUNT=$((UPDATE_COUNT + 1))
      echo "  [update] $label ($stats)"
      echo ""; diff -u "$dst" "$src" --label "installed: $label" --label "kit: $label" 2>/dev/null || true; echo ""
      [ "$DRY_RUN" = "no" ] && cp "$src" "$dst"
      ;;
    report)
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
      echo "  [drift] $label ($stats)"
      echo ""; diff -u "$dst" "$src" --label "installed: $label" --label "kit: $label" 2>/dev/null || true; echo ""
      ;;
    skip)
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
      echo "  [drift] $label ($stats -- skipped)"
      ;;
    prompt)
      echo "  [drift] $label ($stats)"
      while true; do
        printf "          [u]pdate  [k]eep  [d]iff ? "
        read -r choice
        case "$choice" in
          u|U) cp "$src" "$dst"; echo "          -> updated"; UPDATE_COUNT=$((UPDATE_COUNT + 1)); break ;;
          k|K) echo "          -> kept"; KEEP_COUNT=$((KEEP_COUNT + 1)); break ;;
          d|D) echo ""; diff -u "$dst" "$src" --label "installed: $label" --label "kit: $label" 2>/dev/null || true; echo "" ;;
          *)   echo "          (enter u, k, or d)" ;;
        esac
      done
      ;;
  esac
}

copy_file() {
  # copy_file SRC DST LABEL — drift-detecting copy of a single file
  local src="$1" dst="$2" label="$3"
  [ -f "$src" ] || return 0
  [ "$DRY_RUN" = "no" ] && mkdir -p "$(dirname "$dst")"
  if [ ! -e "$dst" ]; then
    [ "$DRY_RUN" = "no" ] && cp "$src" "$dst"
    echo "  [add]  $label"; ADD_COUNT=$((ADD_COUNT + 1))
  elif diff -q "$src" "$dst" > /dev/null 2>&1; then
    echo "  [ok]   $label"; OK_COUNT=$((OK_COUNT + 1))
  else
    handle_drift "$src" "$dst" "$label"
  fi
}

copy_tree() {
  # copy_tree REL — drift-detecting copy of every file under a kit directory
  local rel="$1"
  local src="$KIT_DIR/$rel" dst="$TARGET_DIR/$rel"
  local f name
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    copy_file "$f" "$dst/$name" "$rel/$name"
  done
}

materialize() {
  # Replace a symlink with real content (outside -> inside conversion)
  local rel="$1"
  local dst="$TARGET_DIR/$rel" src="$KIT_DIR/$rel"
  if [ -L "$dst" ]; then
    if [ "$DRY_RUN" = "no" ]; then
      rm "$dst"
      mkdir -p "$(dirname "$dst")"
      cp -R "$src" "$dst"
    fi
    echo "  [real] $rel"; MATERIALIZE_COUNT=$((MATERIALIZE_COUNT + 1))
    return 0
  fi
  return 1
}

link_path() {
  # link_path REL — symlink a kit-managed path, with the occupied-path guard
  local rel="$1"
  local src="$LINK_BASE/$rel" dst="$TARGET_DIR/$rel"

  [ -e "$KIT_DIR/$rel" ] || return 0

  if is_forked "$rel"; then
    echo "  [fork] $rel — project-owned, left alone"
    FORK_COUNT=$((FORK_COUNT + 1)); return 0
  fi

  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      untrack_if_tracked "$rel"
      echo "  [ok]   $rel"; OK_COUNT=$((OK_COUNT + 1))
    else
      [ "$DRY_RUN" = "no" ] && { rm "$dst"; ln -s "$src" "$dst"; }
      untrack_if_tracked "$rel"
      echo "  [link] $rel — repointed"; LINK_COUNT=$((LINK_COUNT + 1))
    fi
    return 0
  fi

  if [ -e "$dst" ]; then
    # A real file or directory is in the way. NEVER delete it implicitly:
    # `ln -s target existing_dir/` silently creates the link *inside* the
    # directory, which looks like success and is not.
    #
    # Exception: if the real content is byte-identical to the kit's, there is
    # nothing to lose, so convert it without demanding --replace. This is the
    # common case when adopting an existing project or converting back from
    # inside mode.
    if same_content "$KIT_DIR/$rel" "$dst"; then
      [ "$DRY_RUN" = "no" ] && { rm -rf "$dst"; mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; }
      untrack_if_tracked "$rel"
      echo "  [link] $rel — was an identical copy"
      LINK_COUNT=$((LINK_COUNT + 1)); return 0
    fi
    if [ "$REPLACE" = "yes" ]; then
      [ "$DRY_RUN" = "no" ] && { rm -rf "$dst"; mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; }
      untrack_if_tracked "$rel"
      echo "  [replace] $rel — real content removed, symlinked"
      LINK_COUNT=$((LINK_COUNT + 1))
    else
      echo "  [occupied] $rel — real file/dir present, not touched"
      OCCUPIED_COUNT=$((OCCUPIED_COUNT + 1)); OCCUPIED_PATHS+=("$rel")
    fi
    return 0
  fi

  [ "$DRY_RUN" = "no" ] && { mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; }
  untrack_if_tracked "$rel"
  echo "  [link] $rel"; LINK_COUNT=$((LINK_COUNT + 1))
}

untrack_if_tracked() {
  # .gitignore has NO effect on files git already tracks. Converting a tracked
  # regular file into a symlink stages a typechange (T) that sails straight
  # past the managed ignore block — committing an absolute machine path.
  # So every path we link must also be dropped from the index.
  local rel="$1"
  [ "$DRY_RUN" = "yes" ] && return 0
  git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$TARGET_DIR" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || return 0
  git -C "$TARGET_DIR" rm --cached -r --quiet -- "$rel" 2>/dev/null || return 0
  UNTRACK_COUNT=$((UNTRACK_COUNT + 1))
}

GITIGNORE_BEGIN="# BEGIN:tb-claude-kit (managed by install.sh — do not edit)"
GITIGNORE_END="# END:tb-claude-kit"

write_gitignore_block() {
  local gi="$TARGET_DIR/.gitignore"
  local tmp; tmp="$(mktemp)"

  if [ -f "$gi" ]; then
    awk -v b="$GITIGNORE_BEGIN" -v e="$GITIGNORE_END" '
      $0 == b {skip=1} !skip {print} $0 == e {skip=0}
    ' "$gi" > "$tmp"
  fi

  if [ "$MODE" = "outside" ]; then
    [ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp")" ] && echo "" >> "$tmp"
    {
      echo "$GITIGNORE_BEGIN"
      local rel
      for rel in "${KIT_PATHS[@]}"; do
        is_forked "$rel" && continue
        is_excluded "$rel" && continue
        [ -e "$KIT_DIR/$rel" ] || continue
        # No trailing slash, ever. In outside mode every one of these is a
        # SYMLINK, which git treats as a file — a "dir/" pattern would not
        # match it, and the link would be committed with its absolute path.
        echo "/$rel"
      done
      echo "$GITIGNORE_END"
    } >> "$tmp"
  fi

  if [ "$DRY_RUN" = "no" ]; then
    if [ -s "$tmp" ]; then mv "$tmp" "$gi"; else rm -f "$tmp" "$gi"; fi
  else
    rm -f "$tmp"
  fi

  if [ "$MODE" = "outside" ]; then
    echo "  [gitignore] managed block written ($(printf '%s\n' "${KIT_PATHS[@]}" | wc -l | tr -d ' ') paths)"
  else
    echo "  [gitignore] managed block removed (inside mode tracks kit files)"
  fi
}

write_kit_json() {
  [ "$DRY_RUN" = "yes" ] && { echo "  [kit.json] would write mode=$MODE"; return 0; }
  mkdir -p "$TARGET_DIR/.claude"
  python3 -c "
import json, os, sys
path, mode = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path))
except Exception:
    d = {'kitVersion': 1, 'fork': []}
d['mode'] = mode
d.setdefault('kitVersion', 1)
d.setdefault('fork', [])
json.dump(d, open(path, 'w'), indent=2)
open(path, 'a').write('\n')
" "$KIT_JSON" "$MODE"
  echo "  [kit.json] mode=$MODE"
}

add_permission() {
  local perm="$1" settings="$TARGET_DIR/.claude/settings.json"
  if [ -f "$settings" ] && ! grep -q "\"$perm\"" "$settings" 2>/dev/null; then
    python3 -c "
import json,sys
p=sys.argv[1]; perm=sys.argv[2]
s=json.load(open(p))
a=s.setdefault('permissions',{}).setdefault('allow',[])
if perm not in a: a.append(perm)
json.dump(s,open(p,'w'),indent=2); open(p,'a').write('\n')
" "$settings" "$perm"
  fi
}

add_mcp_server() {
  local name="$1" frag="$2" mcp="$TARGET_DIR/.mcp.json"
  if [ -f "$mcp" ] && ! grep -q "\"$name\"" "$mcp" 2>/dev/null; then
    python3 -c "
import json,sys
p,name,frag=sys.argv[1],sys.argv[2],sys.argv[3]
m=json.load(open(p))
m.setdefault('mcpServers',{})[name]=json.loads(frag)
json.dump(m,open(p,'w'),indent=2); open(p,'a').write('\n')
" "$mcp" "$name" "$frag"
  fi
}

enable_mcp_server() {
  local name="$1" sl="$TARGET_DIR/.claude/settings.local.json"
  if [ -f "$sl" ]; then
    python3 -c "
import json,sys
p,name=sys.argv[1],sys.argv[2]
s=json.load(open(p))
v=s.setdefault('enabledMcpjsonServers',[])
if name not in v: v.append(name)
json.dump(s,open(p,'w'),indent=2); open(p,'a').write('\n')
" "$sl" "$name"
  fi
}

ask_yn() {
  local prompt="$1"
  if [ "$INTEGRATION_MODE" = "yes" ]; then echo "  [auto] $prompt -> yes"; return 0
  elif [ "$INTEGRATION_MODE" = "no" ]; then echo "  [auto] $prompt -> no"; return 1
  else
    printf "  %s [y/N] " "$prompt"; read -r answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
  fi
}

# ============================================================
# DIRECTORIES
# ============================================================

if [ "$DRY_RUN" = "no" ]; then
  mkdir -p "$TARGET_DIR"/.claude/{skills,hooks} "$TARGET_DIR"/.vscode "$TARGET_DIR"/scripts
  # Always needed: brain state and the two output directories.
  mkdir -p "$TARGET_DIR"/cowork/{brain,plans,research,setup}
  # Feature directories — only create one if something will actually land in it,
  # so an excluded feature leaves no empty directory behind.
  needs_dir() {
    local d="$1" rel
    for rel in "${KIT_PATHS[@]}" "${SCAFFOLD_PATHS[@]}"; do
      case "$rel" in
        "$d"/*) is_excluded "$rel" || return 0 ;;
      esac
    done
    return 1
  }
  for d in cowork/vibe-audit cowork/architecture cowork/video; do
    needs_dir "$d" && mkdir -p "$TARGET_DIR/$d"
  done
fi

# ============================================================
# KIT-MANAGED FILES
# ============================================================

echo "Kit files ($MODE repo):"

if [ "$CONVERTING" = "yes" ] && [ "$MODE" = "inside" ]; then
  for rel in "${KIT_PATHS[@]}"; do
    is_forked "$rel" && continue
    is_excluded "$rel" && continue
    materialize "$rel" || true
  done
fi

for rel in "${KIT_PATHS[@]}"; do
  [ -e "$KIT_DIR/$rel" ] || continue
  if is_excluded "$rel"; then
    echo "  [exclude] $rel — not installed in this project"
    EXCLUDE_COUNT=$((EXCLUDE_COUNT + 1))
    [ -e "$TARGET_DIR/$rel" ] && STALE_EXCLUDED+=("$rel")
    continue
  fi
  if [ "$MODE" = "outside" ]; then
    link_path "$rel"
  else
    if is_forked "$rel"; then
      echo "  [fork] $rel — project-owned, left alone"
      FORK_COUNT=$((FORK_COUNT + 1)); continue
    fi
    if [ -L "$TARGET_DIR/$rel" ]; then materialize "$rel" || true; fi
    if [ -d "$KIT_DIR/$rel" ]; then copy_tree "$rel"; else copy_file "$KIT_DIR/$rel" "$TARGET_DIR/$rel" "$rel"; fi
  fi
done

# ============================================================
# PROJECT-OWNED SCAFFOLDING (both modes — copied once, never updated)
# ============================================================

echo ""
echo "Project files (created if missing, never overwritten):"
for rel in "${SCAFFOLD_PATHS[@]}"; do
  [ -f "$KIT_DIR/$rel" ] || continue
  if is_excluded "$rel"; then
    echo "  [exclude] $rel — not installed in this project"
    EXCLUDE_COUNT=$((EXCLUDE_COUNT + 1))
    [ -e "$TARGET_DIR/$rel" ] && STALE_EXCLUDED+=("$rel")
    continue
  fi
  if [ -e "$TARGET_DIR/$rel" ]; then
    echo "  [ok]   $rel"; OK_COUNT=$((OK_COUNT + 1))
  else
    [ "$DRY_RUN" = "no" ] && { mkdir -p "$(dirname "$TARGET_DIR/$rel")"; cp "$KIT_DIR/$rel" "$TARGET_DIR/$rel"; }
    echo "  [add]  $rel"; ADD_COUNT=$((ADD_COUNT + 1))
  fi
done

if [ ! -f "$TARGET_DIR/cowork/staged.json" ]; then
  [ "$DRY_RUN" = "no" ] && echo '[]' > "$TARGET_DIR/cowork/staged.json"
  echo "  [add]  cowork/staged.json"; ADD_COUNT=$((ADD_COUNT + 1))
fi

# ============================================================
# CONFIG + GITIGNORE
# ============================================================

echo ""
echo "Config:"
write_kit_json
write_gitignore_block

# ============================================================
# DATABASES
# ============================================================

echo ""
echo "Databases:"
init_db() {
  local db="$1" schema="$2" seed="${3:-}" label="$4"
  if [ -f "$TARGET_DIR/$db" ]; then
    echo "  [ok]   $label (exists)"
  elif [ ! -f "$TARGET_DIR/$schema" ]; then
    # schema excluded or not installed — the DB does not belong in this project
    echo "  [skip] $label (no schema installed)"
  elif [ "$DRY_RUN" = "yes" ]; then
    echo "  [init] $label (would create)"
  else
    sqlite3 "$TARGET_DIR/$db" < "$TARGET_DIR/$schema"
    [ -n "$seed" ] && [ -f "$TARGET_DIR/$seed" ] && sqlite3 "$TARGET_DIR/$db" < "$TARGET_DIR/$seed"
    echo "  [init] $label"
  fi
}
init_db "cowork/brain/BRAIN.db"            "cowork/brain/schema.sql"        ""                              "BRAIN.db"
init_db "cowork/vibe-audit/VIBE-AUDIT.db"  "cowork/vibe-audit/schema.sql"   "cowork/vibe-audit/seed.sql"    "VIBE-AUDIT.db"
init_db "cowork/architecture/CTO.db"       "cowork/architecture/schema.sql" "cowork/architecture/seed.sql"  "CTO.db"

[ "$DRY_RUN" = "no" ] && chmod +x "$TARGET_DIR/.claude/hooks/session-start.sh" 2>/dev/null || true

# ============================================================
# OPTIONAL INTEGRATIONS
# ============================================================

echo ""
echo "Optional integrations:"

if grep -q '"exa"' "$TARGET_DIR/.mcp.json" 2>/dev/null; then
  echo "  [ok]   Exa search (already configured)"
elif ask_yn "Enable Exa search? (semantic/neural search for /research)"; then
  add_mcp_server "exa" '{"type": "http", "url": "https://mcp.exa.ai/mcp"}'
  enable_mcp_server "exa"; add_permission "mcp__exa__*"
  echo "  [add]  Exa search (authenticates via OAuth on first use)"
else
  echo "  [skip] Exa search"
fi

if grep -q '"brave-search"' "$TARGET_DIR/.mcp.json" 2>/dev/null; then
  echo "  [ok]   Brave Search (already configured)"
elif ask_yn "Enable Brave Search? (keyword search, Reddit/HN access for /research)"; then
  brave_key="<your-brave-api-key>"
  if [ "$INTEGRATION_MODE" = "prompt" ]; then
    printf "  Brave API key (https://brave.com/search/api/, or Enter to set later): "
    read -r input_key
    [ -n "$input_key" ] && brave_key="$input_key"
  fi
  add_mcp_server "brave-search" "{\"type\": \"stdio\", \"command\": \"npx\", \"args\": [\"-y\", \"@modelcontextprotocol/server-brave-search\"], \"env\": {\"BRAVE_API_KEY\": \"$brave_key\"}}"
  enable_mcp_server "brave-search"; add_permission "mcp__brave-search__*"
  if [ "$brave_key" = "<your-brave-api-key>" ]; then
    echo "  [add]  Brave Search (edit .mcp.json to add your API key)"
  else
    echo "  [add]  Brave Search"
  fi
else
  echo "  [skip] Brave Search"
fi

if [ -f "$TARGET_DIR/.env" ] && grep -q "op://" "$TARGET_DIR/.env" 2>/dev/null; then
  echo "  [ok]   1Password (op:// references found in .env)"
elif [ -f "$TARGET_DIR/cowork/setup/1password-setup.md" ] && [ -f "$TARGET_DIR/.env.example" ]; then
  echo "  [ok]   1Password (setup guide + .env.example in place)"
elif ask_yn "Enable 1Password credential access? (op:// refs in .env, no secrets in repo)"; then
  if [ "$DRY_RUN" = "no" ]; then
    mkdir -p "$TARGET_DIR/cowork/setup"
    cp "$KIT_DIR/cowork/setup/1password-setup.md" "$TARGET_DIR/cowork/setup/1password-setup.md"
    cp "$KIT_DIR/.env.example" "$TARGET_DIR/.env.example"
  fi
  echo "  [add]  1Password setup guide + .env.example"
  echo "         Run: cp .env.example .env, then fill in op:// paths"
else
  echo "  [skip] 1Password"
fi

if grep -q '"cloudflare@cloudflare"' "$TARGET_DIR/.claude/settings.json" 2>/dev/null; then
  echo "  [ok]   Cloudflare plugin (already enabled)"
elif ask_yn "Enable Cloudflare plugin? (docs, API, bindings, builds, observability)"; then
  if [ "$DRY_RUN" = "no" ]; then
    python3 -c "
import json,sys
p=sys.argv[1]; s=json.load(open(p))
s.setdefault('enabledPlugins',{})['cloudflare@cloudflare']=True
json.dump(s,open(p,'w'),indent=2); open(p,'a').write('\n')
" "$TARGET_DIR/.claude/settings.json"
    for pair in \
      "cloudflare-docs:https://docs.mcp.cloudflare.com/mcp" \
      "cloudflare-api:https://mcp.cloudflare.com/mcp" \
      "cloudflare-bindings:https://bindings.mcp.cloudflare.com/mcp" \
      "cloudflare-builds:https://builds.mcp.cloudflare.com/mcp" \
      "cloudflare-observability:https://observability.mcp.cloudflare.com/mcp"; do
      add_mcp_server "${pair%%:*}" "{\"type\": \"http\", \"url\": \"${pair#*:}\"}"
    done
  fi
  echo "  [add]  Cloudflare plugin + 5 MCP servers"
else
  echo "  [skip] Cloudflare plugin"
fi

# ============================================================
# SUMMARY
# ============================================================

echo ""
echo "---"
parts=()
[ $LINK_COUNT -gt 0 ]        && parts+=("$LINK_COUNT linked")
[ $MATERIALIZE_COUNT -gt 0 ] && parts+=("$MATERIALIZE_COUNT materialized")
[ $ADD_COUNT -gt 0 ]         && parts+=("$ADD_COUNT added")
[ $UPDATE_COUNT -gt 0 ]      && parts+=("$UPDATE_COUNT updated")
[ $OK_COUNT -gt 0 ]          && parts+=("$OK_COUNT unchanged")
[ $DRIFT_COUNT -gt 0 ]       && parts+=("$DRIFT_COUNT drifted")
[ $KEEP_COUNT -gt 0 ]        && parts+=("$KEEP_COUNT kept")
[ $FORK_COUNT -gt 0 ]        && parts+=("$FORK_COUNT forked")
[ $EXCLUDE_COUNT -gt 0 ]     && parts+=("$EXCLUDE_COUNT excluded")
[ $UNTRACK_COUNT -gt 0 ]     && parts+=("$UNTRACK_COUNT untracked")
[ $OCCUPIED_COUNT -gt 0 ]    && parts+=("$OCCUPIED_COUNT occupied")
[ ${#parts[@]} -eq 0 ] && parts+=("nothing to do")
( IFS=","; echo "${parts[*]}" ) | sed 's/,/, /g'

if [ $OCCUPIED_COUNT -gt 0 ]; then
  echo ""
  echo "$OCCUPIED_COUNT path(s) hold real files where a symlink belongs:"
  for p in "${OCCUPIED_PATHS[@]}"; do echo "    $p"; done
  echo ""
  echo "  This is expected the first time you convert an existing project."
  echo "  For each path, choose one:"
  echo "    - The project owns it -> add it to \"fork\" in .claude/kit.json"
  echo "    - The kit owns it     -> git rm -r the path, commit, then re-run with --replace"
  echo ""
  echo "  Commit before using --replace. It deletes the real content."
fi

if [ ${#STALE_EXCLUDED[@]} -gt 0 ]; then
  echo ""
  echo "${#STALE_EXCLUDED[@]} excluded path(s) still present on disk:"
  for p in "${STALE_EXCLUDED[@]}"; do echo "    $p"; done
  echo "  Excluding a path stops it being installed; it does not delete what is"
  echo "  already there. Remove them yourself (git rm -r) if that is the intent."
fi

if [ $DRIFT_COUNT -gt 0 ]; then
  echo "  Re-run with --yes to auto-update drifted kit files."
fi

if [ $ADD_COUNT -gt 0 ]; then
  echo ""
  echo "Next steps:"
  echo "  1. Edit CLAUDE.md — describe your project"
  echo "  2. Edit .claude/kit.json — dev ports for /kill, plan/research roots, per-skill rules"
  echo "     (see kit.example.json in the kit for every supported key)"
  echo "  3. Edit cowork/vibe-audit/GUARDRAILS.md — customize for your architecture"
  echo "  4. Edit cowork/architecture/seed.sql — define your subsystems for /cto"
  if [ "$MODE" = "outside" ]; then
    echo "  5. Commit .claude/kit.json and .gitignore — the symlinks are ignored on purpose"
  else
    echo "  5. Commit .claude/ cowork/ CLAUDE.md .mcp.json scripts/"
  fi
fi
