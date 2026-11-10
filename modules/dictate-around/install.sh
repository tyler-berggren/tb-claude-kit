#!/bin/bash
# dictate-around installer: press a hotkey to dictate into one text field while you click and
# navigate anywhere else. macOS only. https://github.com/tyler-berggren/dictate-around
#
#   ./install.sh                     install or update (safe to re-run)
#   ./install.sh --mic "<device>"    record from this input ("default": the system input)
#   ./install.sh --hotkey "<spec>"   "double-fn" (default), "double-rightcmd", "double-ctrl", ...
#                                    or a combination: "ctrl+alt+d", "cmd+shift+space", "f13"
#   ./install.sh --duck <level>      turn other audio down while recording: min, mid (default),
#                                    max or off
#   ./install.sh --list-mics         the input devices connected right now
#   ./install.sh --status            what's installed and whether it's listening
#   ./install.sh --uninstall         remove the Hammerspoon hook and the helper (keeps apps,
#                                    the model and your settings)
#
# --mic, --hotkey and --duck can be combined; re-running with any of them just updates the setting.
#
# What it does:
#   - installs Hammerspoon, ffmpeg and whisper.cpp with Homebrew when they're missing
#   - downloads the whisper model (MODEL_URL) to ~/.local/share/whisper/
#   - builds the ducking helper (dictate-around-duck.swift) with swiftc into
#     ~/.local/share/dictate-around/
#   - links ~/.hammerspoon/dictate-around.lua to dictate-around.lua in this folder,
#     so a `git pull` updates it
#   - adds a marked block to ~/.hammerspoon/init.lua that loads it
#   - writes "mic", "hotkey" and "duck" to ~/.config/dictate-around/config.json
# The macOS permissions it can't grant are printed at the end.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_SRC="$HERE/dictate-around.lua"
DUCK_SRC="$HERE/dictate-around-duck.swift"
DUCK_BIN="$HOME/.local/share/dictate-around/dictate-around-duck"
HS_DIR="$HOME/.hammerspoon"
HS_INIT="$HS_DIR/init.lua"
HS_LINK="$HS_DIR/dictate-around.lua"
CONFIG="$HOME/.config/dictate-around/config.json"
OLD_CONFIG="$HOME/.config/claude-kit/dictate-around.json"   # before dictate-around had its own repo
MODEL_DIR="$HOME/.local/share/whisper"
MODEL_URL="${MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin}"
MODEL="$MODEL_DIR/$(basename "$MODEL_URL")"
BEGIN="-- BEGIN:dictate-around (managed by dictate-around install.sh)"
OLD_BEGIN="-- BEGIN:dictate-around (managed by tb-claude-kit scripts/install-dictate-around)"
END="-- END:dictate-around"
BREW_BIN="/opt/homebrew/bin"

say()  { printf '%s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

# Settings used to live in ~/.config/claude-kit/dictate-around.json. Move them (or the symlink
# pointing at them) to the new place once.
migrate_config() {
  if [ ! -e "$CONFIG" ] && [ ! -L "$CONFIG" ] && { [ -e "$OLD_CONFIG" ] || [ -L "$OLD_CONFIG" ]; }; then
    mkdir -p "$(dirname "$CONFIG")"
    mv "$OLD_CONFIG" "$CONFIG"
    say "Moved your settings: $OLD_CONFIG -> $CONFIG"
  fi
}

list_inputs() {
  # ffmpeg exits non-zero after listing devices; that's expected.
  local out
  out="$("$BREW_BIN/ffmpeg" -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true)"
  printf '%s\n' "$out" | sed -n '/audio devices/,$p' | sed -n 's/.*\] \[[0-9]*\] //p'
}

config_get() {  # config_get <key>  → value, or empty
  [ -f "$CONFIG" ] || return 0
  /usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' "$CONFIG" "$1" 2>/dev/null || true
}

config_set() {  # config_set <key> <value>; value "default" removes the key
  mkdir -p "$(dirname "$CONFIG")"
  /usr/bin/python3 -I - "$CONFIG" "$1" "$2" <<'PY'
import json, os, sys
path, key, value = sys.argv[1:4]
real = os.path.realpath(path)  # write through a symlink, e.g. to a dotfiles repo
cfg = json.load(open(real)) if os.path.exists(real) else {}
if value == "default":
    cfg.pop(key, None)
else:
    cfg[key] = value
with open(real, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
}

remove_block() {
  [ -f "$HS_INIT" ] || return 0
  /usr/bin/awk -v b="$BEGIN" -v o="$OLD_BEGIN" -v e="$END" '
    $0 == b || $0 == o { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip' "$HS_INIT" > "$HS_INIT.tmp" && mv "$HS_INIT.tmp" "$HS_INIT"
}

reload_hammerspoon() {
  if pgrep -x Hammerspoon >/dev/null; then
    "$BREW_BIN/hs" -t 5 -c 'hs.timer.doAfter(0.2, hs.reload)' >/dev/null 2>&1 || { killall Hammerspoon; sleep 1; open -a Hammerspoon; }
  else
    open -a Hammerspoon
  fi
}

fn_setting() {
  case "$(defaults read com.apple.HIToolbox AppleFnUsageType 2>/dev/null || echo unset)" in
    0) echo "Do Nothing (ok)" ;;
    1) echo "Change Input Source (conflicts)" ;;
    2) echo "Emoji (conflicts)" ;;
    3) echo "Start Dictation (conflicts)" ;;
    *) echo "unset = Emoji (conflicts)" ;;
  esac
}

uses_fn() {
  local hk; hk="$(config_get hotkey)"; hk="$(printf '%s' "${hk:-double-fn}" | tr '[:upper:]' '[:lower:]')"
  case "$hk" in double*fn|double*globe) return 0 ;; *) return 1 ;; esac
}

migrate_config
MIC=""; HOTKEY=""; DUCK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --status)
      [ -L "$HS_LINK" ] && say "module:   $HS_LINK -> $(readlink "$HS_LINK")" || say "module:   not linked"
      grep -qxF -e "$BEGIN" "$HS_INIT" 2>/dev/null && say "init.lua: hooked" || say "init.lua: not hooked"
      [ -f "$CONFIG" ] && say "config:   $(tr -d '\n' < "$CONFIG" | tr -s ' ')" || say "config:   none (double-fn, system input)"
      [ -f "$MODEL" ] && say "model:    $MODEL" || say "model:    missing ($MODEL)"
      uses_fn && say "fn key:   $(fn_setting)"
      if pgrep -x Hammerspoon >/dev/null; then
        say "running:  $("$BREW_BIN/hs" -t 5 -c 'return package.loaded["dictate-around"] and package.loaded["dictate-around"].status() or "module not loaded"' 2>&1)"
      else
        say "running:  Hammerspoon is not running"
      fi
      exit 0 ;;
    --list-mics)
      list_inputs; exit 0 ;;
    --uninstall)
      remove_block
      [ -L "$HS_LINK" ] && rm "$HS_LINK"
      rm -f "$DUCK_BIN"
      pgrep -x Hammerspoon >/dev/null && reload_hammerspoon
      say "Removed the dictate-around hook and module link."
      say "Left in place: Hammerspoon, ffmpeg, whisper-cpp, $MODEL, $CONFIG."
      exit 0 ;;
    --mic)    MIC="${2:?--mic needs a device name, or \"default\"}"; shift 2 ;;
    --hotkey) HOTKEY="${2:?--hotkey needs a spec, e.g. double-fn or ctrl+alt+d}"; shift 2 ;;
    --duck)
      DUCK="${2:?--duck needs min, mid, max, off or default}"
      case "$DUCK" in min|mid|max|off|default) ;; *) warn "--duck takes min, mid, max, off or default"; exit 1 ;; esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

[ "$(uname)" = "Darwin" ] || { warn "dictate-around is macOS only."; exit 1; }
command -v brew >/dev/null || { warn "Homebrew is required: https://brew.sh"; exit 1; }
[ -f "$MODULE_SRC" ] || { warn "Missing $MODULE_SRC"; exit 1; }

# 1. Apps and tools
[ -d /Applications/Hammerspoon.app ] || brew install --cask hammerspoon
if ! "$BREW_BIN/ffmpeg" -hide_banner -version >/dev/null 2>&1; then
  if [ -e "$BREW_BIN/ffmpeg" ]; then
    warn "$BREW_BIN/ffmpeg is installed but won't run (often a library Homebrew upgraded under it)."
    warn "Fix it with: brew reinstall \$(brew list --formula | grep -x 'ffmpeg\\(-full\\)\\?' | head -1)"
    exit 1
  fi
  brew install ffmpeg
fi
[ -x "$BREW_BIN/whisper-cli" ] || brew install whisper-cpp

# 2. Model
if [ ! -f "$MODEL" ]; then
  mkdir -p "$MODEL_DIR"
  say "Downloading $(basename "$MODEL") (about 550 MB)..."
  curl -fL --retry 3 --progress-bar -o "$MODEL.part" "$MODEL_URL"
  mv "$MODEL.part" "$MODEL"
fi

# 3. Ducking helper (rebuilt when its source is newer)
if [ ! -x "$DUCK_BIN" ] || [ "$DUCK_SRC" -nt "$DUCK_BIN" ]; then
  if xcrun --find swiftc >/dev/null 2>&1; then
    mkdir -p "$(dirname "$DUCK_BIN")"
    xcrun swiftc -O -o "$DUCK_BIN" "$DUCK_SRC" || warn "Couldn't build the ducking helper; dictation works, without ducking."
  else
    warn "No Swift compiler, so no ducking. Install it with: xcode-select --install, then re-run."
  fi
fi

# 4. Module link and init.lua hook
mkdir -p "$HS_DIR"
if [ -e "$HS_LINK" ] && [ ! -L "$HS_LINK" ] && ! cmp -s "$MODULE_SRC" "$HS_LINK"; then
  warn "$HS_LINK exists and differs from this folder's version. Move it aside and re-run."
  exit 1
fi
ln -sfn "$MODULE_SRC" "$HS_LINK"
remove_block
printf '%s\ndictateAround = require("dictate-around")\n%s\n' "$BEGIN" "$END" >> "$HS_INIT"

# 5. Settings
if [ -n "$MIC" ]; then
  config_set mic "$MIC"
  if [ "$MIC" != "default" ] && ! list_inputs | grep -qxF -e "$MIC"; then
    warn "No input device named \"$MIC\" right now. Connected inputs:"
    list_inputs | sed 's/^/    /' >&2
  fi
fi
[ -n "$HOTKEY" ] && config_set hotkey "$HOTKEY"
[ -n "$DUCK" ] && config_set duck "$DUCK"

reload_hammerspoon

# 6. What only you can do
HK="$(config_get hotkey)"; HK="${HK:-double-fn}"
say ""
say "dictate-around is installed (hotkey: $HK, mic: $(config_get mic | sed 's/^$/system input/'))."
say "Finish in System Settings:"
if uses_fn && [ "$(defaults read com.apple.HIToolbox AppleFnUsageType 2>/dev/null || echo unset)" != "0" ]; then
  say "  - Keyboard: set \"Press 🌐 key to\" to Do Nothing, and turn the Dictation shortcut off."
  say "    (Unset means Emoji, which opens on every Fn tap.)"
fi
say "  - Privacy & Security > Accessibility: turn on Hammerspoon, then Reload Config from its menu."
say "  - The first use asks for microphone access for Hammerspoon: Allow."
say "  - Hammerspoon > Preferences: Launch Hammerspoon at login."
say ""
say "Check it any time: $0 --status"
