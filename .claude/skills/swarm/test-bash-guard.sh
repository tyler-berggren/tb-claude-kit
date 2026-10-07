#!/usr/bin/env bash
# test-bash-guard.sh — asserts what bash-guard.py refuses and what it lets through.
# Run after changing the guard: bash <this skill's folder>/test-bash-guard.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/bash-guard.py"
export CLAUDE_PROJECT_DIR="${TMPDIR:-/tmp}/bash-guard-test-$$"
fails=0

verdict() { # verdict <command> → prints the refused names, or "ok"
  python3 - "$1" <<'PY' | python3 "$guard" | python3 -c 'import json,sys
raw=sys.stdin.read().strip()
print("deny" if raw and json.loads(raw)["hookSpecificOutput"]["permissionDecision"]=="deny" else "ok")'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
PY
}

expect() { # expect <deny|ok> <command>
  local got
  got="$(verdict "$2")"
  if [ "$got" != "$1" ]; then
    echo "FAIL: expected $1, got $got: $2"
    fails=$((fails + 1))
  fi
}

# Refused
expect deny 'cd /repo && git status'
expect deny 'cd /repo; gh pr create --fill'
expect deny 'pushd /repo && pnpm install && git add -A'
expect deny 'FOO=1 cd /repo && git push'
expect deny 'git -C /repo commit -m "$(cat msg.txt)"'
expect deny 'echo `date`'
expect deny 'diff <(sort a) <(sort b)'
expect deny 'cat > f.txt <<EOF
hi
EOF'
expect deny 'eval "$CMD"'
expect deny "bash -c 'cd /repo && git status'"

# Let through
expect ok 'git -C /repo status'
expect ok 'gh pr view 12 --repo owner/name'
expect ok 'cd /repo'
expect ok 'cd /repo && pnpm exec tsc --noEmit'
expect ok 'env -C /repo pnpm exec vitest related src/a.ts'
expect ok 'git -C /repo log --oneline | head -5'
expect ok 'git -C /repo commit -m "cd into the folder; git does the rest"'
expect ok "git -C /repo commit -m 'use \$(x) and \`y\` literally'"
expect ok 'echo $((1 + 2))'
expect ok 'grep -c "<<" file.txt'
expect ok 'cat file.txt <<< "x"'
expect ok 'HA_REPO=/repo/.worktrees/slot-1 /abs/ha-quick-check.sh --since origin/main'

# Opt-outs
got="$(SWARM_BASH_GUARD=off verdict 'cd /repo && git status')"
[ "$got" = ok ] || { echo "FAIL: SWARM_BASH_GUARD=off did not turn the guard off"; fails=$((fails + 1)); }
got="$(SWARM_BASH_GUARD_ALLOW=subst verdict 'echo $(date)')"
[ "$got" = ok ] || { echo "FAIL: SWARM_BASH_GUARD_ALLOW=subst did not allow substitution"; fails=$((fails + 1)); }

# A non-Bash tool and bad input never block
got="$(echo '{"tool_name":"Read","tool_input":{}}' | python3 "$guard")"
[ -z "$got" ] || { echo "FAIL: guard answered for a non-Bash tool"; fails=$((fails + 1)); }
got="$(echo 'not json' | python3 "$guard"; echo "exit=$?")"
[ "$got" = "exit=0" ] || { echo "FAIL: guard did not fail open on bad input"; fails=$((fails + 1)); }

rm -rf "$CLAUDE_PROJECT_DIR"
if [ "$fails" -eq 0 ]; then echo "bash-guard: all assertions passed"; else echo "bash-guard: $fails failed"; exit 1; fi
