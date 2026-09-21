---
name: pbar
description: REQUIRED, unprompted, right after you start any background job (Bash run_in_background, nohup, a long script, a batch or pipeline) you expect to run 5+ minutes — do not wait to be asked. Builds a live terminal progress display and hands back its paste-ready command in a copyable code block, re-printed whenever the user might need to restart it. Also use when the user asks for status on a running job.
argument-hint: "[what to watch — a log file, a job name, or nothing to infer from context]"
---

# pbar — a progress bar for a background job

Long jobs make bad conversation. Without a display the user has to ask "status?" every few
minutes and you have to burn a tool call re-deriving the same numbers. This builds them a
self-contained watcher script and gives them one line to paste.

**The deliverable is the pasted line, not the script.** Finish by printing a single command the
user can copy into any terminal, from any directory. If they have to `cd` first, or edit a path,
or remember a flag, this skill has failed.

## When this is mandatory

**Every time you start a job you expect to run 5 minutes or more, run this skill immediately after
launching it — in the same turn, without being asked.** It does not matter whether the job is a
`run_in_background` Bash call, a `nohup … &`, a script that loops over an API, or a batch you
kicked off some other way. The user should never have to ask for a progress bar, and never have to
ask "status?".

- **Unsure whether it takes 5 minutes? Build it anyway.** An unneeded bar costs one tool call; a
  missing one costs the user a string of status questions.
- **Skip it only when you are confident** the job finishes in under 5 minutes.
- A PostToolUse hook reminds you after each `run_in_background` Bash call. The reminder is only a
  nudge — the rule applies to every long job, however it was started.

## What makes a progress bar possible

A bar needs two things: a **quantity that grows** and a **total it grows toward**. Most of the work
is finding an honest pair. In rough order of preference:

| Signal | Read it with | Good when |
|---|---|---|
| Rows in an output file | `wc -l < f` | The job writes records as it goes |
| Bytes in an output file | `stat -f%z f` (macOS) / `stat -c%s f` (Linux) | Output is not line-oriented |
| A counter the job prints | `tail -1 log \| grep -oE '…'` | The job already reports progress |
| Rows in a database table | a `count(*)` query | The job writes straight to a database |
| Completed items in a directory | `ls dir \| wc -l` | The job writes one file per unit |

**If there is no honest total, say so and do not invent one.** A bar against a guessed
denominator is worse than a plain counter, because it looks authoritative. Fall back to showing
the count, the rate, and elapsed time.

## Procedure

### 1. Find out what is actually running

Do not guess. Establish, with commands:

```bash
# What is running, and what did it write?
pgrep -fl '<job pattern>'
ls -la <output dir>
tail -5 <log file>
```

You need: the **log path**, the **output paths**, the **process pattern** that proves liveness, and
the **totals**. Get totals from the job's own output where possible (a "N features" line, a source
API's count endpoint, a manifest) rather than from memory.

### 2. Copy the template into the PROJECT, not the skill folder

> **`.claude/skills/pbar/` is a SYMLINK to the shared kit checkout.** Kit skills install by
> symlink, so a watcher written there lands in the kit repo and appears in every other project
> that installs it. Generated watchers must go somewhere project-local. `install.sh` only ever
> symlinks paths under `.claude/skills/`, so `.claude/pbar/` is safe.

```bash
mkdir -p .claude/pbar
cp .claude/skills/pbar/template.sh .claude/pbar/watch-<job-name>.sh
```

Then edit the settings block at the top — `JOB`, `LOG`, `DIR`, `PATTERN`, `EXT`, `NAMES`, `TOTAL`.
A second job adds a second `watch-*.sh` rather than overwriting the first.

The **paste line is the absolute path** to that file. Resolve it once and use it verbatim:

```bash
printf '%s/.claude/pbar/watch-<job-name>.sh\n' "$(pwd)"
```

Project-local file, absolute invocation — that is what lets it run from any directory without a
`cd`.

The script must:

- **Use absolute paths INSIDE the script too.** It lives in the project but will be invoked from
  an unknown directory, so every log and output path it reads must be absolute. Do not rely on
  `$(dirname "$0")` unless you resolve it to an absolute path first.
- **Be strictly read-only.** No writes, no kills, no `set -e` that could exit on a transient
  `wc` failure. The user must be able to Ctrl-C it, close the terminal, or run five copies,
  without touching the job.
- **Show liveness separately from progress.** This is the one that bites: a stalled job and a
  finishing job produce identical bars. Print whether the producer process still exists on every
  redraw. A bar at 47% with `producer: NOT RUNNING` is the single most useful line the display can
  show, and a bar alone can never say it.
- **Exit on its own** when everything is complete, so the terminal comes back.
- **State totals as assumptions.** If they were probed once and hardcoded, say so in a comment —
  a shifted total makes the percentage wrong while the raw count stays honest.

### 3. The rendering details that go wrong

**Bars: slice fixed strings, never loop `seq`.**

```bash
FILL='##############################'   # 30 chars
BLANK='                              '   # 30 chars
bar() { local w=30 f=$(( $1 * 30 / 100 )); printf '[%s%s]' "${FILL:0:$f}" "${BLANK:0:$((w-f))}"; }
```

`printf '%0.s#' $(seq 1 0)` prints **one** `#`, not zero — with an empty argument list printf still
runs its format once. An empty bar renders as `[#…]`. Slicing cannot do that.

**Redraw in place, and clear properly.** `clear` needs a `TERM`; when in doubt use
`printf '\033[H\033[2J'`. Redraw every 2–5s for local files, 15–30s if a poll costs a network
round-trip or a database query.

**Percentages must clamp.** `p=$((n*100/t)); [ $p -gt 100 ] && p=100`. A total probed slightly low
otherwise renders a bar wider than its brackets and wrecks the layout.

**Rate and ETA from observed throughput**, not from a fixed guess — record the first sample and
divide. Show `--` until there is enough signal, rather than a confident wrong number.

**zsh does not word-split unquoted expansions.** Iterate with `echo "$VAR" | while IFS= read -r`,
never `for x in $VAR`.

### 4. Make it executable and hand over the line

```bash
chmod +x .claude/pbar/watch-<job-name>.sh
```

Then print the command **in its own fenced code block, as the last thing in your reply** — the
**absolute** path, so it works from any directory. Always this exact shape:

````
Watch it live (paste into any terminal):

```
/abs/path/to/project/.claude/pbar/watch-<job-name>.sh
```
````

The code block is the point: most terminals and editors give it a one-click copy, and it cannot be
mistaken for prose. **Never** put the command inline in a sentence, inside backticks mid-paragraph,
or in a table. The block holds that one line only — no `$ ` prompt, no `cd`, no comment, no second
command.

Say in one sentence what it shows and that stopping it cannot affect the job. Do not print the
script's source unless asked — they wanted a display, not a code review.

### 4b. Re-print the block whenever the user might need to restart it

The watcher runs in a terminal the user controls. Terminals get closed, tabs get killed, laptops
sleep, and the watcher exits on its own at COMPLETE. Scrolling back through a long session to find
the line is exactly the friction this skill exists to remove. **Re-print the same code block, as
the last thing in your reply, whenever the job is still relevant and any of these is true:**

- You give **any status update** on the job — a Monitor event, a background-task notification,
  an answer to "how's it going?".
- The job was **restarted, resumed, or relaunched** (after a crash, a fix, a rate limit). If its
  outputs, log path or totals changed, rebuild the watcher first, then print the block.
- The job **crashed or stalled** — the user will want to watch the retry.
- The user says the display **stopped, froze, looks wrong, or they closed it**.
- The session **resumed or was compacted** while the job is still running.
- You are **wrapping up a turn** while the job is still running.

When in doubt, print it. A repeated three-line block is cheap; hunting for a lost command is not.
The watcher itself also shows its own restart command at the bottom of every redraw and again on
Ctrl-C, so the line is on screen even when the conversation is not.

### 5. Arm a notification too

A display only helps while someone is looking at it. Also set a watch that fires once, on
**either** outcome:

```
Monitor(persistent: true) with a poll loop that emits one line and exits when the job
completes OR when the producer process disappears.
```

Covering only success is the classic mistake — the monitor then stays silent through a crash, and
silence is indistinguishable from "still working". Ask yourself: *if this job died right now, would
anything fire?*

## Template

`template.sh` in this folder is the working starting point — copy it as described in step 2 and
edit its settings block. It already handles the bar rendering, clamping, observed-rate ETA, the
liveness line and self-exit. The listing below is that same script, for reference when adapting it
to a job whose progress is not "rows in files" (a database count, a directory of finished items, a
counter the job prints).

Multi-stage jobs get one row per stage; single-stage jobs get one bar plus rate and ETA.

```bash
#!/usr/bin/env bash
# Live progress for <job>. Read-only: stopping this cannot affect the job.
# Totals probed <date> — a shifted total skews the %, the raw count stays honest.
LOG=/abs/path/to/job.log
DIR=/abs/path/to/output
PATTERN='<pgrep pattern proving the producer is alive>'
declare -a NAMES=(stage-a stage-b)
declare -a TOTAL=(1000 2000)

FILL='##############################'
BLANK='                              '
bar() { local w=30 f=$(( $1 * 30 / 100 )); printf '[%s%s]' "${FILL:0:$f}" "${BLANK:0:$((w-f))}"; }
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"   # shown as the restart command
trap 'printf "\n  restart this display:\n  %s\n" "$SELF"; exit 0' INT TERM

start=$(date +%s); first=-1
while true; do
  printf '\033[H\033[2J'
  echo "<job> — $(date '+%H:%M:%S')"; echo
  total_now=0; grand=0; done_all=1
  for i in "${!NAMES[@]}"; do
    f="$DIR/${NAMES[$i]}.out"; t=${TOTAL[$i]}
    n=$([ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0)
    p=$(( n * 100 / t )); [ $p -gt 100 ] && p=100
    [ "$n" -lt "$t" ] && done_all=0
    total_now=$(( total_now + n )); grand=$(( grand + t ))
    printf "  %-14s %s %3d%%  %9d / %d\n" "${NAMES[$i]}" "$(bar $p)" "$p" "$n" "$t"
  done
  [ $first -lt 0 ] && first=$total_now
  el=$(( $(date +%s) - start ))
  echo
  if [ $el -gt 10 ] && [ $total_now -gt $first ]; then
    rate=$(( (total_now - first) / el ))
    [ $rate -gt 0 ] && echo "  ~$(( (grand - total_now) / rate / 60 )) min left  (${rate}/s)"
  fi
  # Liveness is NOT progress — a stalled bar looks exactly like a finishing one.
  if pgrep -f "$PATTERN" >/dev/null; then echo "  producer: running"; else echo "  producer: NOT RUNNING"; fi
  tail -1 "$LOG" 2>/dev/null | sed 's/^/  last: /'
  echo; echo "  restart: $SELF"
  [ $done_all -eq 1 ] && { echo; echo "  COMPLETE"; break; }
  sleep 5
done
```

## Rules

- **No confirmation needed** — build it and hand over the line.
- **Read-only, always.** The watcher may never write, kill, or lock anything the job touches.
- **Never fabricate a total.** No honest denominator means no bar — show count, rate and elapsed.
- **Liveness on every redraw.** Without it the display cannot distinguish stalled from finishing.
- **Mandatory for 5+ minute jobs.** Build it right after launch, unprompted.
- **One line at the end, in its own fenced code block.** Absolute path, no `cd`, no arguments, no
  editing, never inline in prose.
- **Re-print the block** on every status update, restart, crash, resume, or turn that ends with the
  job still running.

---

## Project overrides

If `.claude/kit.json` has a `rules."pbar"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."pbar" // empty' .claude/kit.json 2>/dev/null
```
