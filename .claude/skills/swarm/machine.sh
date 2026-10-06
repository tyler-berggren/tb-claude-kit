#!/usr/bin/env bash
# machine.sh — keeps a swarm inside the machine it runs on.
#
#   machine.sh run [--label <text>] -- <command> [args…]
#       Run one HEAVY step (a check, a test run, a cold dev-server start, a browser capture run)
#       through the machine-wide gate: at most N heavy steps at once, across every swarm on this
#       machine. The step waits for a free slot, then runs at lower priority with the project's
#       core budget in its environment. Exits with the command's own exit code.
#   machine.sh list                 Show who holds each slot.
#   machine.sh sweep <directory>    Stop processes left running from inside <directory> (a unit's
#                                   worktree): dev servers, watchers, browsers. Prints what it stopped.
#
# Settings come from the project's .claude/kit.json, key swarm.machine (all optional):
#   heavySlots  how many heavy steps may run at once            (default 2)
#   nice        priority drop for a heavy step, 0–19            (default 10)
#   waitMax     seconds to wait for a slot before running anyway (default 900)
#   env         { "NAME": "value" } exported to every heavy step, e.g. worker caps
# Environment overrides: SWARM_HEAVY_SLOTS, SWARM_HEAVY_NICE, SWARM_HEAVY_WAIT, SWARM_HEAVY_DIR,
# SWARM_KIT_JSON (path to the kit.json to read).
#
# The gate never deadlocks a run: a slot whose holder has died is reclaimed, and a step that has
# waited waitMax runs anyway and says so. Works under macOS bash 3.2.

set -u

here="$(cd "$(dirname "$0")" && pwd)"
kit_json="${SWARM_KIT_JSON:-$here/../../kit.json}"
lock_root="${SWARM_HEAVY_DIR:-${TMPDIR:-/tmp}/swarm-heavy-$(id -u)}"

setting() { # setting <jq path> <default>
  local v=""
  if [ -f "$kit_json" ] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r "$1 // empty" "$kit_json" 2>/dev/null)"
  fi
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

slots="${SWARM_HEAVY_SLOTS:-$(setting '.swarm.machine.heavySlots' 2)}"
nice_by="${SWARM_HEAVY_NICE:-$(setting '.swarm.machine.nice' 10)}"
wait_max="${SWARM_HEAVY_WAIT:-$(setting '.swarm.machine.waitMax' 900)}"
case "$slots" in ''|*[!0-9]*) slots=2 ;; esac
[ "$slots" -lt 1 ] && slots=1
case "$nice_by" in ''|*[!0-9]*) nice_by=10 ;; esac
case "$wait_max" in ''|*[!0-9]*) wait_max=900 ;; esac

alive() { kill -0 "$1" 2>/dev/null; }

held="" # the slot directory this process holds

release() {
  if [ -n "$held" ] && [ -d "$held" ]; then
    rm -f "$held/pid" "$held/label" "$held/since" 2>/dev/null
    rmdir "$held" 2>/dev/null
  fi
  held=""
}

try_acquire() { # try_acquire <label>; sets $held on success
  local i=1 d holder
  mkdir -p "$lock_root" 2>/dev/null
  while [ "$i" -le "$slots" ]; do
    d="$lock_root/slot-$i"
    if mkdir "$d" 2>/dev/null; then
      printf '%s\n' "$$" > "$d/pid"
      printf '%s\n' "$1" > "$d/label"
      date -u +%H:%M:%SZ > "$d/since"
      held="$d"
      return 0
    fi
    holder="$(cat "$d/pid" 2>/dev/null)"
    # A slot directory with no pid yet is being written by its new holder; leave it alone.
    if [ -n "$holder" ] && ! alive "$holder"; then
      rm -f "$d/pid" "$d/label" "$d/since" 2>/dev/null
      rmdir "$d" 2>/dev/null
      continue # retry this slot
    fi
    i=$((i + 1))
  done
  return 1
}

cmd_list() {
  local i=1 d
  echo "heavy slots: $slots   (locks in $lock_root)"
  while [ "$i" -le "$slots" ]; do
    d="$lock_root/slot-$i"
    if [ -d "$d" ]; then
      echo "  slot-$i  held  pid=$(cat "$d/pid" 2>/dev/null)  since=$(cat "$d/since" 2>/dev/null)  $(cat "$d/label" 2>/dev/null)"
    else
      echo "  slot-$i  free"
    fi
    i=$((i + 1))
  done
}

cmd_run() {
  local label=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --label) label="${2:-}"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if [ $# -eq 0 ]; then
    echo "machine.sh run: no command given" >&2
    return 2
  fi
  [ -z "$label" ] && label="$*"
  label="$(printf '%s' "$label" | cut -c1-120)  [$(basename "$(pwd)")]"

  local waited=0 said=0
  until try_acquire "$label"; do
    if [ "$waited" -ge "$wait_max" ]; then
      echo "machine.sh: no heavy slot free after ${waited}s; running anyway" >&2
      break
    fi
    if [ "$said" -eq 0 ]; then
      echo "machine.sh: waiting for one of $slots heavy slots…" >&2
      said=1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  [ "$said" -eq 1 ] && [ -n "$held" ] && echo "machine.sh: slot free after ${waited}s" >&2

  trap 'release' EXIT
  trap 'release; exit 130' INT
  trap 'release; exit 143' TERM

  # The project's core budget, exported to this step only.
  if [ -f "$kit_json" ] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r pair; do
      [ -n "$pair" ] && export "$pair"
    done <<EOF
$(jq -r '(.swarm.machine.env // {}) | to_entries[] | "\(.key)=\(.value)"' "$kit_json" 2>/dev/null)
EOF
  fi

  local code=0
  if [ "$nice_by" -gt 0 ]; then
    nice -n "$nice_by" "$@" || code=$?
  else
    "$@" || code=$?
  fi
  release
  trap - EXIT INT TERM
  return "$code"
}

cmd_sweep() {
  local dir="${1:-}"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo "machine.sh sweep: give the directory of a finished unit's worktree" >&2
    return 2
  fi
  dir="$(cd "$dir" && pwd -P)"
  case "$dir" in
    /|"$HOME"|"$HOME/") echo "machine.sh sweep: refusing to sweep $dir" >&2; return 2 ;;
  esac
  command -v lsof >/dev/null 2>&1 || { echo "machine.sh sweep: lsof not found" >&2; return 0; }

  # Every process of this user whose working directory is inside <dir>.
  local pid="" cwd="" stopped=0 line
  while IFS= read -r line; do
    case "$line" in
      p*) pid="${line#p}" ;;
      n*)
        cwd="${line#n}"
        case "$cwd" in
          "$dir"|"$dir"/*)
            if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ] && alive "$pid"; then
              echo "  stopping $pid  $(ps -o comm= -p "$pid" 2>/dev/null | awk -F/ '{print $NF}')  ($cwd)"
              kill -TERM "$pid" 2>/dev/null && stopped=$((stopped + 1))
            fi
            ;;
        esac
        ;;
    esac
  done <<EOF
$(lsof -u "$(id -u)" -a -d cwd -Fpn 2>/dev/null)
EOF
  echo "machine.sh sweep: stopped $stopped process(es) under $dir"
}

sub="${1:-}"
[ $# -gt 0 ] && shift
case "$sub" in
  run) cmd_run "$@" ;;
  list) cmd_list ;;
  sweep) cmd_sweep "$@" ;;
  *)
    echo "usage: machine.sh run [--label <text>] -- <command…> | list | sweep <directory>" >&2
    exit 2
    ;;
esac
