#!/bin/bash
# PostToolUse hook on Bash: after any run_in_background call, remind Claude to
# build a /pbar progress display if the job may run 5+ minutes.
#
# Why: /pbar used to fire only when the user asked for a progress bar, and nobody
# asks at launch time — they end up asking "status?" every few minutes instead.
# This fires at the exact moment a job starts. It cannot know how long the job
# will take, so it hands that judgment back to Claude rather than guessing.
#
# Silent (no output) for every foreground Bash call.

input=$(cat)
bg=$(printf '%s' "$input" | python3 -c '
import sys, json
try: print(str(json.load(sys.stdin).get("tool_input", {}).get("run_in_background", False)).lower())
except Exception: print("false")
')
[ "$bg" = "true" ] || exit 0

cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"You just started a background job. If it may run 5+ minutes, invoke the /pbar skill NOW, before anything else, and end your reply with its command: one absolute path, alone in its own fenced code block. Re-print that block on every later status update, restart, crash, or resume. Skip only if you are confident this job finishes in under 5 minutes. If you also wait or poll for the job to end, never pgrep -f a pattern your own poll command contains: it matches itself and never exits. Wait on the PID, on a done-file the job writes, or write the pattern as [p]attern."}}
EOF
