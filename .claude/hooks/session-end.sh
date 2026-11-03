#!/bin/bash
# SessionEnd: stamp ended_at on this session's row in the brain.
#
# The row is found by the session_id Claude Code passes on stdin, the same id
# session-start.sh recorded. (The old inline command matched on $$, which is a
# different shell for every hook, so it never matched anything.)
DB="cowork/brain/BRAIN.db"
[ -f "$DB" ] || exit 0
SESSION_ID=$(python3 -c '
import json, re, sys
try: d = json.load(sys.stdin)
except Exception: d = {}
print(re.sub(r"[^A-Za-z0-9-]", "", str(d.get("session_id") or "")))' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0
sqlite3 "$DB" "UPDATE sessions SET ended_at = datetime('now', 'localtime') WHERE session_id = '$SESSION_ID' AND ended_at IS NULL;" 2>/dev/null
exit 0
