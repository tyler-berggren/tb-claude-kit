#!/bin/bash
set -euo pipefail

# TB Claude Kit — Install or update a project
#
# Usage:
#   cd /path/to/your/project
#   bash /path/to/tb-claude-kit/install.sh
#
# Modes:
#   Remote (kit is external):
#     cd /path/to/your/project
#     bash /path/to/tb-claude-kit/install.sh
#
#   In-place (kit files copied into your repo root):
#     bash install.sh
#
# Flags:
#   --yes       Auto-update drifted kit files + enable all integrations
#   --dry-run   Report drifts without updating + skip integrations (alias: --no-mcps)
#
# Drift detection:
#   Kit-managed files (skills, hooks, schemas, scripts) are compared
#   against the kit version. Drifts are shown as unified diffs.
#   --yes auto-updates these; interactive mode prompts per file.
#
#   Project files (CLAUDE.md, settings.json, .mcp.json, GUARDRAILS.md)
#   are never auto-updated — drifts are reported for manual review.
#
# Non-interactive shells (e.g. Claude Code):
#   Drifts are reported with full diffs. Pass --yes to auto-update.

# ============================================================
# FLAGS & MODE DETECTION
# ============================================================

INTEGRATION_MODE="prompt"
DRIFT_MODE="prompt"
for arg in "$@"; do
  case "$arg" in
    --yes) INTEGRATION_MODE="yes"; DRIFT_MODE="update" ;;
    --dry-run|--no-mcps) INTEGRATION_MODE="no"; DRIFT_MODE="skip" ;;
  esac
done

if [ "$INTEGRATION_MODE" = "prompt" ] && ! [ -t 0 ]; then
  INTEGRATION_MODE="yes"
  DRIFT_MODE="report"
  echo "(Non-interactive shell — drifts reported with diffs. Pass --yes to auto-update kit files.)"
fi

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$(pwd)"

if [ "$KIT_DIR" = "$TARGET_DIR" ]; then
  MODE="inplace"
  echo "Unpacking Claude kit in-place: $TARGET_DIR"
else
  MODE="remote"
  echo "Installing Claude kit into: $TARGET_DIR"
  echo "From: $KIT_DIR"
fi
echo ""

# ============================================================
# COUNTERS
# ============================================================

ADD_COUNT=0
OK_COUNT=0
UPDATE_COUNT=0
DRIFT_COUNT=0
KEEP_COUNT=0

# ============================================================
# HELPERS
# ============================================================

drift_stats() {
  local added removed
  added=$({ diff "$1" "$2" || true; } | grep -c '^>' 2>/dev/null || echo 0)
  removed=$({ diff "$1" "$2" || true; } | grep -c '^<' 2>/dev/null || echo 0)
  echo "+${added}/-${removed}"
}

# Handle a file that differs between kit and installed versions.
# strategy: "kit" (auto-updatable) or "project" (manual review only)
handle_drift() {
  local src="$1" dst="$2" label="$3" strategy="${4:-kit}"
  local stats
  stats=$(drift_stats "$dst" "$src")

  local effective_mode="$DRIFT_MODE"
  if [ "$strategy" = "project" ] && [ "$effective_mode" = "update" ]; then
    effective_mode="report"
  fi

  local note=""
  [ "$strategy" = "project" ] && note=" -- project file"

  case "$effective_mode" in
    update)
      UPDATE_COUNT=$((UPDATE_COUNT + 1))
      echo "  [update] $label ($stats)"
      echo ""
      diff -u "$dst" "$src" --label "installed: $label" --label "kit: $label" 2>/dev/null || true
      echo ""
      cp "$src" "$dst"
      ;;
    report)
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
      echo "  [drift] $label ($stats$note)"
      echo ""
      diff -u "$dst" "$src" --label "installed: $label" --label "kit: $label" 2>/dev/null || true
      echo ""
      ;;
    skip)
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
      echo "  [drift] $label ($stats$note -- skipped)"
      ;;
    prompt)
      echo "  [drift] $label ($stats$note)"
      while true; do
        printf "          [u]pdate  [k]eep  [d]iff ? "
        read -r choice
        case "$choice" in
          u|U)
            cp "$src" "$dst"
            echo "          -> updated"
            UPDATE_COUNT=$((UPDATE_COUNT + 1))
            break
            ;;
          k|K)
            echo "          -> kept"
            KEEP_COUNT=$((KEEP_COUNT + 1))
            break
            ;;
          d|D)
            echo ""
            diff -u "$dst" "$src" --label "installed: $label" --label "kit: $label" 2>/dev/null || true
            echo ""
            ;;
          *)
            echo "          (enter u, k, or d)"
            ;;
        esac
      done
      ;;
  esac
}

# Install a file from kit to target with drift detection.
# Usage: install_file SRC DST LABEL [STRATEGY]
#   strategy: "kit" (default, auto-updatable) or "project" (manual review only)
install_file() {
  local src="$1" dst="$2" label="$3" strategy="${4:-kit}"

  [ -f "$src" ] || return 0
  mkdir -p "$(dirname "$dst")"

  if [ "$src" = "$dst" ]; then
    echo "  [ok]   $label"
    OK_COUNT=$((OK_COUNT + 1))
  elif [ ! -f "$dst" ]; then
    cp "$src" "$dst"
    echo "  [add]  $label"
    ADD_COUNT=$((ADD_COUNT + 1))
  elif diff -q "$src" "$dst" > /dev/null 2>&1; then
    echo "  [ok]   $label"
    OK_COUNT=$((OK_COUNT + 1))
  else
    handle_drift "$src" "$dst" "$label" "$strategy"
  fi
}

add_permission() {
  local perm="$1"
  local settings="$TARGET_DIR/.claude/settings.json"
  if [ -f "$settings" ] && ! grep -q "\"$perm\"" "$settings" 2>/dev/null; then
    python3 -c "
import json
with open('$settings') as f:
    s = json.load(f)
perms = s.setdefault('permissions', {}).setdefault('allow', [])
if '$perm' not in perms:
    perms.append('$perm')
with open('$settings', 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
"
  fi
}

add_mcp_server() {
  local name="$1"
  local json_fragment="$2"
  local mcp="$TARGET_DIR/.mcp.json"
  if [ -f "$mcp" ] && ! grep -q "\"$name\"" "$mcp" 2>/dev/null; then
    python3 -c "
import json
with open('$mcp') as f:
    m = json.load(f)
m.setdefault('mcpServers', {})['$name'] = $json_fragment
with open('$mcp', 'w') as f:
    json.dump(m, f, indent=2)
    f.write('\n')
"
  fi
}

enable_mcp_server() {
  local name="$1"
  local settings_local="$TARGET_DIR/.claude/settings.local.json"
  if [ -f "$settings_local" ]; then
    python3 -c "
import json
with open('$settings_local') as f:
    s = json.load(f)
servers = s.setdefault('enabledMcpjsonServers', [])
if '$name' not in servers:
    servers.append('$name')
with open('$settings_local', 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
"
  fi
}

ask_yn() {
  local prompt="$1"
  if [ "$INTEGRATION_MODE" = "yes" ]; then
    echo "  [auto] $prompt -> yes"
    return 0
  elif [ "$INTEGRATION_MODE" = "no" ]; then
    echo "  [auto] $prompt -> no"
    return 1
  else
    printf "  %s [y/N] " "$prompt"
    read -r answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
  fi
}

# ============================================================
# CORE FILES
# ============================================================

# --- Skills ---
echo "Skills:"
for skill_dir in "$KIT_DIR/.claude/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  install_file \
    "$skill_dir/SKILL.md" \
    "$TARGET_DIR/.claude/skills/$skill_name/SKILL.md" \
    "$skill_name"
done

# --- Hooks ---
echo ""
echo "Hooks:"
install_file \
  "$KIT_DIR/.claude/hooks/session-start.sh" \
  "$TARGET_DIR/.claude/hooks/session-start.sh" \
  "session-start.sh"

# --- Settings ---
echo ""
echo "Settings:"
install_file \
  "$KIT_DIR/.claude/settings.json" \
  "$TARGET_DIR/.claude/settings.json" \
  ".claude/settings.json" \
  "project"

install_file \
  "$KIT_DIR/.claude/settings.local.json" \
  "$TARGET_DIR/.claude/settings.local.json" \
  ".claude/settings.local.json" \
  "project"

# --- MCP ---
echo ""
echo "MCP:"
install_file \
  "$KIT_DIR/.mcp.json" \
  "$TARGET_DIR/.mcp.json" \
  ".mcp.json" \
  "project"

# --- Cowork ---
echo ""
echo "Cowork:"
mkdir -p "$TARGET_DIR/cowork/brain"
mkdir -p "$TARGET_DIR/cowork/plans"
mkdir -p "$TARGET_DIR/cowork/research"
mkdir -p "$TARGET_DIR/cowork/vibe-audit"
mkdir -p "$TARGET_DIR/cowork/setup"

for file in schema.sql USAGE.md; do
  install_file \
    "$KIT_DIR/cowork/brain/$file" \
    "$TARGET_DIR/cowork/brain/$file" \
    "cowork/brain/$file"
done

for file in PROCEDURE.md schema.sql seed.sql; do
  install_file \
    "$KIT_DIR/cowork/vibe-audit/$file" \
    "$TARGET_DIR/cowork/vibe-audit/$file" \
    "cowork/vibe-audit/$file"
done

install_file \
  "$KIT_DIR/cowork/vibe-audit/GUARDRAILS.md" \
  "$TARGET_DIR/cowork/vibe-audit/GUARDRAILS.md" \
  "cowork/vibe-audit/GUARDRAILS.md" \
  "project"

if [ ! -f "$TARGET_DIR/cowork/staged.json" ]; then
  echo '[]' > "$TARGET_DIR/cowork/staged.json"
  echo "  [add]  cowork/staged.json"
  ADD_COUNT=$((ADD_COUNT + 1))
else
  echo "  [ok]   cowork/staged.json"
  OK_COUNT=$((OK_COUNT + 1))
fi

# --- Scripts ---
echo ""
echo "Scripts:"
install_file \
  "$KIT_DIR/scripts/puppeteer-server.cjs" \
  "$TARGET_DIR/scripts/puppeteer-server.cjs" \
  "scripts/puppeteer-server.cjs"

# --- CLAUDE.md ---
echo ""
echo "CLAUDE.md:"
install_file \
  "$KIT_DIR/CLAUDE.md" \
  "$TARGET_DIR/CLAUDE.md" \
  "CLAUDE.md" \
  "project"

# --- Databases ---
echo ""
echo "Brain DB:"
if [ -f "$TARGET_DIR/cowork/brain/BRAIN.db" ]; then
  echo "  [skip] BRAIN.db already exists"
else
  sqlite3 "$TARGET_DIR/cowork/brain/BRAIN.db" < "$TARGET_DIR/cowork/brain/schema.sql"
  echo "  [init] BRAIN.db created from schema"
fi

echo ""
echo "Vibe Audit DB:"
if [ -f "$TARGET_DIR/cowork/vibe-audit/VIBE-AUDIT.db" ]; then
  echo "  [skip] VIBE-AUDIT.db already exists"
else
  sqlite3 "$TARGET_DIR/cowork/vibe-audit/VIBE-AUDIT.db" < "$TARGET_DIR/cowork/vibe-audit/schema.sql"
  sqlite3 "$TARGET_DIR/cowork/vibe-audit/VIBE-AUDIT.db" < "$TARGET_DIR/cowork/vibe-audit/seed.sql"
  echo "  [init] VIBE-AUDIT.db created from schema + seed"
fi

chmod +x "$TARGET_DIR/.claude/hooks/session-start.sh" 2>/dev/null || true

# ============================================================
# OPTIONAL INTEGRATIONS
# ============================================================

echo ""
echo "Optional integrations:"

# --- Exa ---
if grep -q '"exa"' "$TARGET_DIR/.mcp.json" 2>/dev/null; then
  echo "  [ok]   Exa search (already configured)"
elif ask_yn "Enable Exa search? (semantic/neural search for /research)"; then
  add_mcp_server "exa" '{"type": "http", "url": "https://mcp.exa.ai/mcp"}'
  enable_mcp_server "exa"
  add_permission "mcp__exa__*"
  echo "  [add]  Exa search (authenticates via OAuth on first use)"
else
  echo "  [skip] Exa search"
fi

# --- Brave Search ---
if grep -q '"brave-search"' "$TARGET_DIR/.mcp.json" 2>/dev/null; then
  echo "  [ok]   Brave Search (already configured)"
elif ask_yn "Enable Brave Search? (keyword search, Reddit/HN access for /research)"; then
  brave_key="<your-brave-api-key>"
  if [ "$INTEGRATION_MODE" = "prompt" ]; then
    printf "  Brave API key (https://brave.com/search/api/, or Enter to set later): "
    read -r input_key
    if [ -n "$input_key" ]; then
      brave_key="$input_key"
    fi
  fi
  add_mcp_server "brave-search" "{\"type\": \"stdio\", \"command\": \"npx\", \"args\": [\"-y\", \"@modelcontextprotocol/server-brave-search\"], \"env\": {\"BRAVE_API_KEY\": \"$brave_key\"}}"
  enable_mcp_server "brave-search"
  add_permission "mcp__brave-search__*"
  if [ "$brave_key" = "<your-brave-api-key>" ]; then
    echo "  [add]  Brave Search (edit .mcp.json to add your API key)"
  else
    echo "  [add]  Brave Search"
  fi
else
  echo "  [skip] Brave Search"
fi

# --- 1Password ---
if [ -f "$TARGET_DIR/.env" ] && grep -q "op://" "$TARGET_DIR/.env" 2>/dev/null; then
  echo "  [ok]   1Password (op:// references found in .env)"
elif [ -f "$TARGET_DIR/cowork/setup/1password-setup.md" ] && [ -f "$TARGET_DIR/.env.example" ]; then
  echo "  [ok]   1Password (setup guide + .env.example in place)"
elif ask_yn "Enable 1Password credential access? (op:// refs in .env, no secrets in repo)"; then
  mkdir -p "$TARGET_DIR/cowork/setup"
  install_file \
    "$KIT_DIR/cowork/setup/1password-setup.md" \
    "$TARGET_DIR/cowork/setup/1password-setup.md" \
    "cowork/setup/1password-setup.md"
  install_file \
    "$KIT_DIR/.env.example" \
    "$TARGET_DIR/.env.example" \
    ".env.example"
  echo "  [add]  1Password setup guide + .env.example"
  echo "         Run: cp .env.example .env, then fill in op:// paths"
  echo "         See: cowork/setup/1password-setup.md for full setup"
else
  echo "  [skip] 1Password"
fi

# --- Cloudflare ---
if grep -q '"cloudflare@cloudflare"' "$TARGET_DIR/.claude/settings.json" 2>/dev/null; then
  echo "  [ok]   Cloudflare plugin (already enabled)"
elif ask_yn "Enable Cloudflare plugin? (docs, API, bindings, builds, observability)"; then
  python3 -c "
import json
with open('$TARGET_DIR/.claude/settings.json') as f:
    s = json.load(f)
s.setdefault('enabledPlugins', {})['cloudflare@cloudflare'] = True
with open('$TARGET_DIR/.claude/settings.json', 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
"
  for pair in \
    "cloudflare-docs:https://docs.mcp.cloudflare.com/mcp" \
    "cloudflare-api:https://mcp.cloudflare.com/mcp" \
    "cloudflare-bindings:https://bindings.mcp.cloudflare.com/mcp" \
    "cloudflare-builds:https://builds.mcp.cloudflare.com/mcp" \
    "cloudflare-observability:https://observability.mcp.cloudflare.com/mcp"; do
    name="${pair%%:*}"
    url="${pair#*:}"
    add_mcp_server "$name" "{\"type\": \"http\", \"url\": \"$url\"}"
  done
  echo "  [add]  Cloudflare plugin + 5 MCP servers"
else
  echo "  [skip] Cloudflare plugin"
fi

# ============================================================
# CLEANUP (in-place mode)
# ============================================================

if [ "$MODE" = "inplace" ]; then
  echo ""
  echo "Cleanup:"
  if [ -f "$TARGET_DIR/README.md" ] && head -1 "$TARGET_DIR/README.md" | grep -q "TB Claude Kit"; then
    rm "$TARGET_DIR/README.md"
    echo "  [rm]   README.md (kit docs — not needed in project)"
  fi
  echo "  [keep] install.sh (re-run to check for updates)"
fi

# ============================================================
# SUMMARY
# ============================================================

echo ""
echo "---"
parts=()
[ $ADD_COUNT -gt 0 ] && parts+=("$ADD_COUNT added")
[ $UPDATE_COUNT -gt 0 ] && parts+=("$UPDATE_COUNT updated")
[ $OK_COUNT -gt 0 ] && parts+=("$OK_COUNT unchanged")
[ $DRIFT_COUNT -gt 0 ] && parts+=("$DRIFT_COUNT drifted")
[ $KEEP_COUNT -gt 0 ] && parts+=("$KEEP_COUNT kept")

IFS=", "; echo "${parts[*]}"; unset IFS

if [ $DRIFT_COUNT -gt 0 ]; then
  case "$DRIFT_MODE" in
    report|skip)
      echo "  Kit files: re-run with --yes to auto-update"
      echo "  Project files: review diffs above and merge manually"
      ;;
    update)
      echo "  Project files drifted — review diffs above and merge manually"
      ;;
  esac
fi

if [ $ADD_COUNT -gt 0 ]; then
  echo ""
  echo "Next steps:"
  echo "  1. Edit CLAUDE.md — describe your project"
  echo "  2. Edit cowork/vibe-audit/GUARDRAILS.md — customize for your architecture"
  echo "  3. Edit .claude/skills/kill/SKILL.md — set your dev ports"
  echo "  4. Run 'git add .claude/ cowork/ CLAUDE.md .mcp.json scripts/' to commit"
fi
