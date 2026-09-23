#!/usr/bin/env bash
# ── pbar template ────────────────────────────────────────────────────────────
# Copy this to `.claude/pbar/watch-<job>.sh` IN THE PROJECT, fill in the five
# settings below, and hand the user its absolute path.
#
# DO NOT generate watchers into `.claude/skills/pbar/` — that directory is a
# SYMLINK to the shared kit checkout, so a project-specific watcher written
# there lands in the kit and shows up in every other project that installs it.
# `.claude/pbar/` is a real project directory; install.sh only ever symlinks
# paths under `.claude/skills/`.
#
# This script is READ-ONLY. Stopping it, closing the terminal, or running five
# copies cannot affect the job it watches.
#
# PBAR_ONCE=1 draws a single frame and exits — check it shows the job's real
# numbers before handing the line to anyone.
# ─────────────────────────────────────────────────────────────────────────────

# ── settings ─────────────────────────────────────────────────────────────────
JOB="my job"                                   # shown in the header
LOG=/abs/path/to/job.log                       # tailed for the last line ("" to skip)
DIR=/abs/path/to/output                        # where the counted files live
PATTERN='[m]y-worker'                          # pgrep -f pattern proving the producer is ALIVE;
                                               # the [x] form stops it matching any shell whose
                                               # command line merely CONTAINS the pattern
EXT=out                                        # extension of the counted files

# One entry per stage, in order. TOTALS ARE AN ASSUMPTION: probe them once from
# the job's own output or the source's count endpoint, and note when. A shifted
# total skews the percentage while the raw count stays honest.
declare -a NAMES=(stage-a stage-b)             # -> $DIR/stage-a.$EXT
declare -a TOTAL=(1000 2000)                   # probed <date>
INTERVAL=5                                     # 2-5s local; 15-30s if a poll costs a network call
# ─────────────────────────────────────────────────────────────────────────────

# Slicing two fixed strings, not looping seq: `printf '%0.s#' $(seq 1 0)` prints
# ONE '#', because printf still runs its format once with an empty argument
# list — which renders an empty bar as "[#...]".
FILL='##############################'   # 30
BLANK='                              '   # 30
bar() { local w=30 f=$(( $1 * 30 / 100 )); printf '[%s%s]' "${FILL:0:$f}" "${BLANK:0:$((w-f))}"; }

# Absolute path to this watcher, shown as the restart command. The user may
# close this terminal and come back hours later — the line to reopen it should
# be on screen, not buried in the Claude conversation.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
trap 'printf "\n  restart this display:\n  %s\n" "$SELF"; exit 0' INT TERM

start=$(date +%s); first=-1
while true; do
  printf '\033[H\033[2J'                # `clear` needs $TERM; this does not
  echo "$JOB — $(date '+%H:%M:%S')"; echo

  now=0; grand=0; done_all=1
  for i in "${!NAMES[@]}"; do
    f="$DIR/${NAMES[$i]}.$EXT"; t=${TOTAL[$i]}
    n=$([ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0)
    p=$(( n * 100 / t )); [ $p -gt 100 ] && p=100   # clamp, or a low total overflows the brackets
    [ "$n" -lt "$t" ] && done_all=0
    now=$(( now + n )); grand=$(( grand + t ))
    printf "  %-16s %s %3d%%  %10d / %d\n" "${NAMES[$i]}" "$(bar $p)" "$p" "$n" "$t"
  done

  [ $first -lt 0 ] && first=$now
  el=$(( $(date +%s) - start ))
  echo
  # Rate from OBSERVED throughput, and only once there is enough signal —
  # a confident wrong ETA is worse than no ETA.
  if [ $el -gt 10 ] && [ $now -gt $first ]; then
    rate=$(( (now - first) / el ))
    if [ $rate -gt 0 ]; then echo "  ~$(( (grand - now) / rate / 60 )) min left  (${rate}/s)"
    else echo "  rate: --"; fi
  else
    echo "  rate: --"
  fi

  # LIVENESS IS NOT PROGRESS. A stalled job and a finishing job draw identical
  # bars; only this line tells them apart. "47%  producer: NOT RUNNING" is the
  # most useful thing this display can say.
  if pgrep -f "$PATTERN" >/dev/null 2>&1; then echo "  producer: running"
  else echo "  producer: NOT RUNNING"; fi

  [ -n "$LOG" ] && tail -1 "$LOG" 2>/dev/null | sed 's/^/  last: /'
  echo; echo "  restart: $SELF"

  [ $done_all -eq 1 ] && { echo; echo "  COMPLETE"; break; }
  [ -n "${PBAR_ONCE:-}" ] && break      # one frame, for checking the settings
  sleep "$INTERVAL"
done
