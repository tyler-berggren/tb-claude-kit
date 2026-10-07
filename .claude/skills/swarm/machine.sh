#!/usr/bin/env bash
# machine.sh — keeps a swarm inside the machine it runs on.
#
#   machine.sh run [--label <text>] [--weight <n>|all] -- <command> [args…]
#       Run one HEAVY step (a check, a test run, a build, a browser capture run) through the
#       machine-wide gate: at most N heavy slots are in use at once, across every swarm on this
#       machine. A step takes <weight> slots (default 1; `all` takes every slot, for a step that
#       loads the whole machine: a native app build, a production bundle build). With no --weight,
#       the project's `weights` map decides from the command line. The step waits for its slots and
#       for memory pressure to ease, then runs at lower priority with the project's core budget in
#       its environment. Exits with the command's own exit code.
#   machine.sh serve --tag <name> [--label <text>] -- <command> [args…]
#       Run one LONG-RUNNING server (a dev server, a simulator) under a lease: one holder per tag,
#       at most M servers at once. Holds the lease until the command exits. Exits 75 when the tag
#       or a server slot is still taken after serverWait seconds, and prints who holds it.
#   machine.sh pressure             Print the machine's memory state; exit 0 when there is room,
#                                   1 when memory is short (the gate waits, the orchestrator holds
#                                   new units).
#   machine.sh list                 Show who holds each heavy slot and each server lease.
#   machine.sh sweep <directory>    Stop processes left running from inside <directory> (a unit's
#                                   worktree): dev servers, watchers, browsers. Prints what it stopped.
#
# Settings come from the project's .claude/kit.json, key swarm.machine (all optional):
#   heavySlots   how many heavy slots there are                                (default 2)
#   weights      { "<text in the command line>": <n> | "all" } — slots a matching step takes
#   nice         priority drop for a heavy step, 0–19                          (default 10)
#   waitMax      seconds a step waits for its slots before running anyway      (default 900)
#   minFreePct   below this share of free memory, memory is short              (default 10)
#   memWait      seconds a step waits for memory to ease before running anyway (default 300)
#   serverSlots  how many leased servers may run at once                       (default 2)
#   serverWait   seconds `serve` waits for its tag and a slot                  (default 600)
#   env          { "NAME": "value" } exported to every step, e.g. worker caps
# Environment overrides: SWARM_HEAVY_SLOTS, SWARM_HEAVY_NICE, SWARM_HEAVY_WAIT, SWARM_HEAVY_DIR,
# SWARM_MIN_FREE_PCT, SWARM_MEM_WAIT, SWARM_SERVER_SLOTS, SWARM_SERVER_WAIT,
# SWARM_KIT_JSON (path to the kit.json to read).
#
# The budget exists to keep the machine usable, not to slow the run: with memory to spare the gate
# adds no waiting beyond the slot count. The gate never deadlocks a run: a slot or lease whose holder has died is reclaimed, and a step
# that has waited waitMax (or memWait) runs anyway and says so. Works under macOS bash 3.2.

set -u

here="$(cd "$(dirname "$0")" && pwd)"
# The skill folder is usually a symlink into the kit, so "$here/../.." would resolve inside the kit
# checkout, not the project. Strip the last two path components as text instead.
kit_json="${SWARM_KIT_JSON:-${here%/*/*}/kit.json}"
lock_root="${SWARM_HEAVY_DIR:-${TMPDIR:-/tmp}/swarm-heavy-$(id -u)}"

setting() { # setting <jq path> <default>
  local v=""
  if [ -f "$kit_json" ] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r "$1 // empty" "$kit_json" 2>/dev/null)"
  fi
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

number() { # number <value> <default>: the value when it is a whole number, else the default
  case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac
}

slots="$(number "${SWARM_HEAVY_SLOTS:-$(setting '.swarm.machine.heavySlots' 2)}" 2)"
nice_by="$(number "${SWARM_HEAVY_NICE:-$(setting '.swarm.machine.nice' 10)}" 10)"
wait_max="$(number "${SWARM_HEAVY_WAIT:-$(setting '.swarm.machine.waitMax' 900)}" 900)"
min_free="$(number "${SWARM_MIN_FREE_PCT:-$(setting '.swarm.machine.minFreePct' 10)}" 10)"
mem_wait="$(number "${SWARM_MEM_WAIT:-$(setting '.swarm.machine.memWait' 300)}" 300)"
server_slots="$(number "${SWARM_SERVER_SLOTS:-$(setting '.swarm.machine.serverSlots' 2)}" 2)"
server_wait="$(number "${SWARM_SERVER_WAIT:-$(setting '.swarm.machine.serverWait' 600)}" 600)"
[ "$slots" -lt 1 ] && slots=1
[ "$server_slots" -lt 1 ] && server_slots=1

alive() { kill -0 "$1" 2>/dev/null; }

drop_lock() { # drop_lock <directory>: remove one lock directory and what this script wrote in it
  rm -f "$1/pid" "$1/label" "$1/since" 2>/dev/null
  rmdir "$1" 2>/dev/null
}

# ---- memory ---------------------------------------------------------------------------------
# "Swap used" is a high-water mark and says nothing about now, so it is never the signal. The
# signals are the kernel's pressure level, the share of memory free, and swap GROWING between two
# readings a short time apart.
swap_used_mb() {
  if sysctl -n vm.swapusage >/dev/null 2>&1; then
    sysctl -n vm.swapusage 2>/dev/null | sed -n 's/.*used = \([0-9][0-9]*\).*/\1/p'
  elif [ -r /proc/meminfo ]; then
    awk '/^SwapTotal:/ {t=$2} /^SwapFree:/ {f=$2} END {if (t > 0) printf "%d\n", (t - f) / 1024}' /proc/meminfo
  fi
}

mem_state="" # set by read_pressure: "free=NN% level=N swap=NNNNM(+NNN)"
read_pressure() { # returns 0 when there is room, 1 when memory is short
  local free="" level="" swap="" grew=0 last="" last_at="" now short=0
  if command -v memory_pressure >/dev/null 2>&1; then
    free="$(memory_pressure 2>/dev/null | sed -n 's/.*free percentage: *\([0-9][0-9]*\)%.*/\1/p' | tail -1)"
    level="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)"
  elif [ -r /proc/meminfo ]; then
    free="$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if (t > 0) printf "%d\n", a * 100 / t}' /proc/meminfo)"
  fi
  free="$(number "$free" "")"
  level="$(number "$level" "")"
  swap="$(number "$(swap_used_mb)" "")"
  now="$(date +%s)"
  mkdir -p "$lock_root" 2>/dev/null
  if [ -n "$swap" ]; then
    if [ -f "$lock_root/swap-sample" ]; then
      last="$(number "$(sed -n 1p "$lock_root/swap-sample" 2>/dev/null)" "")"
      last_at="$(number "$(sed -n 2p "$lock_root/swap-sample" 2>/dev/null)" "")"
    fi
    if [ -z "$last" ] || [ -z "$last_at" ]; then
      printf '%s\n%s\n' "$swap" "$now" > "$lock_root/swap-sample" 2>/dev/null
    else
      # Compare with a reading 20 seconds to 5 minutes old. A newer one is left to age; an older
      # one is replaced and says nothing.
      if [ $((now - last_at)) -ge 20 ] && [ $((now - last_at)) -le 300 ]; then
        grew=$((swap - last))
      fi
      if [ $((now - last_at)) -ge 20 ]; then
        printf '%s\n%s\n' "$swap" "$now" > "$lock_root/swap-sample" 2>/dev/null
      fi
    fi
  fi
  [ -n "$level" ] && [ "$level" -ge 2 ] && short=1
  [ -n "$free" ] && [ "$free" -lt "$min_free" ] && short=1
  [ "$grew" -ge 512 ] && short=1
  mem_state="free=${free:-?}% level=${level:-?} swap=${swap:-?}M(+${grew})"
  return "$short"
}

cmd_pressure() {
  if read_pressure; then
    echo "ok    $mem_state"
    return 0
  fi
  echo "short $mem_state   (short: level 2 or more, free under ${min_free}%, or swap grew 512M+ since the last reading)"
  return 1
}

wait_for_memory() { # wait_for_memory <what is about to run>
  local waited=0 said=0
  until read_pressure; do
    if [ "$waited" -ge "$mem_wait" ]; then
      echo "machine.sh: memory still short after ${waited}s ($mem_state); running $1 anyway" >&2
      return 0
    fi
    if [ "$said" -eq 0 ]; then
      echo "machine.sh: memory is short ($mem_state); waiting…" >&2
      said=1
    fi
    sleep 10
    waited=$((waited + 10))
  done
  [ "$said" -eq 1 ] && echo "machine.sh: memory eased after ${waited}s ($mem_state)" >&2
  return 0
}

# ---- heavy slots ----------------------------------------------------------------------------
held="" # newline-separated slot directories this process holds

release_slots() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && drop_lock "$d"
  done <<SLOTS
$held
SLOTS
  held=""
}

# A step that needs several slots announces itself, so single-slot steps stop slipping in ahead.
wide_mine() { [ "$(cat "$lock_root/wide-wait/pid" 2>/dev/null)" = "$$" ]; }
wide_clear() { wide_mine && drop_lock "$lock_root/wide-wait"; return 0; }
wide_other() { # true when ANOTHER live process is waiting for several slots
  local w
  w="$(cat "$lock_root/wide-wait/pid" 2>/dev/null)"
  [ -n "$w" ] || return 1
  [ "$w" = "$$" ] && return 1
  if alive "$w"; then return 0; fi
  drop_lock "$lock_root/wide-wait"
  return 1
}

release() {
  release_slots
  wide_clear
}

try_acquire() { # try_acquire <label> <need>; sets $held on success (all <need> slots, or none)
  local i=1 d holder got=0 need="${2:-1}"
  mkdir -p "$lock_root" 2>/dev/null
  wide_other && return 1
  if [ "$need" -gt 1 ] && mkdir "$lock_root/wide-wait" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_root/wide-wait/pid"
  fi
  while [ "$i" -le "$slots" ] && [ "$got" -lt "$need" ]; do
    d="$lock_root/slot-$i"
    if mkdir "$d" 2>/dev/null; then
      printf '%s\n' "$$" > "$d/pid"
      printf '%s\n' "$1" > "$d/label"
      date -u +%H:%M:%SZ > "$d/since"
      held="${held}${d}
"
      got=$((got + 1))
      i=$((i + 1))
      continue
    fi
    holder="$(cat "$d/pid" 2>/dev/null)"
    # A slot directory with no pid yet is being written by its new holder; leave it alone.
    if [ -n "$holder" ] && ! alive "$holder"; then
      drop_lock "$d"
      continue # retry this slot
    fi
    i=$((i + 1))
  done
  if [ "$got" -ge "$need" ]; then
    wide_clear
    return 0
  fi
  # Not all of them: give back what was taken. The wide-wait marker stays, so the next try wins.
  release_slots
  return 1
}

weight_for() { # weight_for <command line>: the weight the project's map gives it, or 1
  local line="$1" key val tab
  tab="$(printf '\t')"
  if [ -f "$kit_json" ] && command -v jq >/dev/null 2>&1; then
    while IFS="$tab" read -r key val; do
      [ -n "$key" ] || continue
      case "$line" in *"$key"*) printf '%s\n' "$val"; return 0 ;; esac
    done <<WEIGHTS
$(jq -r '(.swarm.machine.weights // {}) | to_entries[] | "\(.key)\t\(.value)"' "$kit_json" 2>/dev/null)
WEIGHTS
  fi
  echo 1
}

export_project_env() { # the project's core budget, exported to this step only
  local pair
  if [ -f "$kit_json" ] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r pair; do
      [ -n "$pair" ] && export "$pair"
    done <<PAIRS
$(jq -r '(.swarm.machine.env // {}) | to_entries[] | "\(.key)=\(.value)"' "$kit_json" 2>/dev/null)
PAIRS
  fi
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
  echo "servers: up to $server_slots at once"
  for d in "$lock_root"/server-*; do
    [ -d "$d" ] || continue
    echo "  ${d##*/server-}  pid=$(cat "$d/pid" 2>/dev/null)  since=$(cat "$d/since" 2>/dev/null)  $(cat "$d/label" 2>/dev/null)"
  done
  if read_pressure; then echo "memory: ok    $mem_state"; else echo "memory: short $mem_state"; fi
}

cmd_run() {
  local label="" weight=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --label) label="${2:-}"; shift 2 ;;
      --weight) weight="${2:-}"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if [ $# -eq 0 ]; then
    echo "machine.sh run: no command given" >&2
    return 2
  fi
  [ -z "$label" ] && label="$*"
  [ -z "$weight" ] && weight="$(weight_for "$*")"
  local need
  if [ "$weight" = "all" ]; then need="$slots"; else need="$(number "$weight" 1)"; fi
  [ "$need" -lt 1 ] && need=1
  [ "$need" -gt "$slots" ] && need="$slots"
  label="$(printf '%s' "$label" | cut -c1-120)  [$(basename "$(pwd)")]"
  [ "$need" -gt 1 ] && label="$label  (x$need)"

  trap 'release' EXIT
  trap 'release; exit 130' INT
  trap 'release; exit 143' TERM

  local waited=0 said=0
  until try_acquire "$label" "$need"; do
    if [ "$waited" -ge "$wait_max" ]; then
      echo "machine.sh: $need of $slots heavy slots not free after ${waited}s; running anyway" >&2
      wide_clear
      break
    fi
    if [ "$said" -eq 0 ]; then
      echo "machine.sh: waiting for $need of $slots heavy slots…" >&2
      said=1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  [ "$said" -eq 1 ] && [ -n "$held" ] && echo "machine.sh: slot free after ${waited}s" >&2

  # The slot is held while waiting for memory, so nothing else piles in behind a short machine.
  wait_for_memory "this step"
  export_project_env

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

# ---- server leases --------------------------------------------------------------------------
lease="" # the server lease directory this process holds
child="" # the server's process id, while it runs

release_lease() {
  [ -n "$lease" ] && [ -d "$lease" ] && drop_lock "$lease"
  lease=""
}

stop_server() {
  [ -n "$child" ] && kill -TERM "$child" 2>/dev/null
  release_lease
}

live_servers() { # how many leases have a live holder; dead ones are reclaimed on the way
  local d holder n=0
  for d in "$lock_root"/server-*; do
    [ -d "$d" ] || continue
    holder="$(cat "$d/pid" 2>/dev/null)"
    if [ -n "$holder" ] && ! alive "$holder"; then
      drop_lock "$d"
      continue
    fi
    n=$((n + 1))
  done
  echo "$n"
}

try_lease() { # try_lease <tag> <label>; sets $lease on success
  local d="$lock_root/server-$1" holder
  mkdir -p "$lock_root" 2>/dev/null
  holder="$(cat "$d/pid" 2>/dev/null)"
  if [ -n "$holder" ] && ! alive "$holder"; then drop_lock "$d"; fi
  [ -d "$d" ] && return 1
  [ "$(live_servers)" -ge "$server_slots" ] && return 1
  mkdir "$d" 2>/dev/null || return 1
  printf '%s\n' "$$" > "$d/pid"
  printf '%s\n' "$2" > "$d/label"
  date -u +%H:%M:%SZ > "$d/since"
  lease="$d"
  # Two tags can pass the count at the same moment; the one that finds too many backs off.
  if [ "$(live_servers)" -gt "$server_slots" ]; then
    release_lease
    return 1
  fi
  return 0
}

cmd_serve() {
  local label="" tag=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --label) label="${2:-}"; shift 2 ;;
      --tag) tag="${2:-}"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if [ -z "$tag" ] || [ $# -eq 0 ]; then
    echo "usage: machine.sh serve --tag <name> [--label <text>] -- <command…>" >&2
    return 2
  fi
  tag="$(printf '%s' "$tag" | tr -c 'A-Za-z0-9._-' '_')"
  [ -z "$label" ] && label="$*"
  label="$(printf '%s' "$label" | cut -c1-120)  [$(basename "$(pwd)")]"

  trap 'release_lease' EXIT
  trap 'stop_server; exit 130' INT
  trap 'stop_server; exit 143' TERM

  local waited=0 said=0
  until try_lease "$tag" "$label"; do
    if [ "$waited" -ge "$server_wait" ]; then
      echo "machine.sh serve: '$tag' or a server slot is still taken after ${waited}s:" >&2
      cmd_list | sed -n '/^servers:/,$p' >&2
      trap - EXIT INT TERM
      return 75
    fi
    if [ "$said" -eq 0 ]; then
      echo "machine.sh serve: waiting for '$tag' and one of $server_slots server slots…" >&2
      said=1
    fi
    sleep 5
    waited=$((waited + 5))
  done

  wait_for_memory "this server"
  export_project_env

  local code=0
  "$@" &
  child=$!
  wait "$child" || code=$?
  child=""
  release_lease
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
  serve) cmd_serve "$@" ;;
  pressure) cmd_pressure ;;
  list) cmd_list ;;
  sweep) cmd_sweep "$@" ;;
  *)
    echo "usage: machine.sh run [--label <text>] [--weight <n>|all] -- <command…> | serve --tag <name> -- <command…> | pressure | list | sweep <directory>" >&2
    exit 2
    ;;
esac
