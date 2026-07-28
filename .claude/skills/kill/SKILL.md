---
name: kill
description: Kill all dev processes running on this machine (dev servers, watchers, bundlers) without touching the active Claude Code session.
user_only: true
---

# Kill Dev Processes

Finds and kills all development processes — dev servers, file watchers, bundler instances, etc. Leaves the active Claude Code session untouched.

## Configuration

Ports and extra process patterns come from `.claude/kit.json` when present:

```json
{
  "kill": {
    "ports": [3000, 3001, 5173, 8787],
    "portRanges": [[9615, 9634]],
    "patterns": ["my-custom-watcher"],
    "scopeToProjectPath": true
  }
}
```

Every key is optional, and the whole file is optional — with no `kit.json`, or a `kit.json`
lacking a `kill` key, the built-in defaults below apply. `scopeToProjectPath` additionally kills
node/tsx processes whose command line contains this project's path, for repos that run dev servers
on shared ports.

## Procedure

1. **Find and kill processes listening on dev ports:**

```bash
PORTS=$(jq -r '((.kill.ports // [])[]), ((.kill.portRanges // [])[] | range(.[0]; .[1]+1))' .claude/kit.json 2>/dev/null)
[ -z "$PORTS" ] && PORTS=$(printf '%s\n' 3000 3001 4000 4444 5173 5174 8080 8787 8788 8789; seq 9615 9634)

echo "$PORTS" | while IFS= read -r port; do
  [ -z "$port" ] && continue
  pids=$(lsof -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)
  if [ -n "$pids" ]; then
    echo "Killing port $port: PIDs $pids"
    echo "$pids" | xargs kill 2>/dev/null
  fi
done
```

> **The shell is zsh.** It does not word-split unquoted parameter expansions, so `for port in
> $PORTS` would pass the entire list as a single argument and silently match nothing. Always
> iterate with `echo "$VAR" | while IFS= read -r`. This applies to every `kit.json` array.

2. **Find and kill common dev tool processes:**

```bash
pgrep -f "wrangler dev" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "tsx watch" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "next dev" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "vite" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "nodemon" 2>/dev/null | xargs kill 2>/dev/null

# Project-specific patterns from kit.json
jq -r '(.kill.patterns // [])[]' .claude/kit.json 2>/dev/null | while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  pgrep -f "$pat" 2>/dev/null | xargs kill 2>/dev/null
done

# Processes scoped to this project's path, when kit.json opts in
if [ "$(jq -r '.kill.scopeToProjectPath // false' .claude/kit.json 2>/dev/null)" = "true" ]; then
  pgrep -f "node.*$(pwd).*dev" 2>/dev/null | xargs kill 2>/dev/null
  pgrep -f "tsx watch.*$(pwd)" 2>/dev/null | xargs kill 2>/dev/null
fi
```

3. **Find and kill Puppeteer, Chrome debug, artifact bridge, and clean registry:**

```bash
# Kill all puppeteer server processes
pgrep -f "puppeteer-server" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "chrome.*claude-chrome" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "artifact-bridge" 2>/dev/null | xargs kill 2>/dev/null

# Clear the chrome registry since we killed everything
echo '[]' > ~/.claude-chrome-registry.json 2>/dev/null
```

4. **Verify nothing is left on dev ports:**

```bash
echo "$PORTS" | while IFS= read -r port; do
  [ -z "$port" ] && continue
  pid=$(lsof -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)
  if [ -n "$pid" ]; then
    echo "WARNING: port $port still occupied by PID $pid"
  fi
done
echo "Done."
```

`$PORTS` is still in scope from step 1. If running step 4 standalone, rebuild it with the same
two lines.

5. **Report** what was killed (ports freed, process names). If nothing was running, say so.

## Rules

- **No confirmation needed** — execute immediately
- **Never kill Claude Code** — do not touch processes matching `claude`, `claude-code`, or the current shell's ancestor PIDs
- **Never kill non-dev processes** — only target processes related to dev servers and tools
- **SIGTERM first** — use `kill`, not `kill -9`. Only escalate to `kill -9` if a process survives after 2 seconds
- Exit codes 143/137 from killed background tasks are expected — ignore them

---

## Project overrides

If `.claude/kit.json` has a `rules."kill"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."kill" // empty' .claude/kit.json 2>/dev/null
```
