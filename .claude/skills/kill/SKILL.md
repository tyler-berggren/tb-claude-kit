---
name: kill
description: Kill all dev processes running on this machine (dev servers, watchers, bundlers) without touching the active Claude Code session.
user_only: true
---

# Kill Dev Processes

Finds and kills all development processes — dev servers, file watchers, bundler instances, etc. Leaves the active Claude Code session untouched.

## Procedure

1. **Find and kill processes listening on common dev ports:**

```bash
# Common dev server ports — customize this list per project
for port in 3000 3001 4000 4444 5173 5174 8080 8787 8788 8789 $(seq 9615 9634); do
  pids=$(lsof -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)
  if [ -n "$pids" ]; then
    echo "Killing port $port: PIDs $pids"
    echo "$pids" | xargs kill 2>/dev/null
  fi
done
```

2. **Find and kill common dev tool processes:**

```bash
# Bundler/watcher processes — add project-specific patterns as needed
pgrep -f "wrangler dev" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "tsx watch" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "next dev" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "vite" 2>/dev/null | xargs kill 2>/dev/null
pgrep -f "nodemon" 2>/dev/null | xargs kill 2>/dev/null
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
for port in 3000 3001 4000 4444 5173 5174 8080 8787 8788 8789 $(seq 9615 9634); do
  pid=$(lsof -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)
  if [ -n "$pid" ]; then
    echo "WARNING: port $port still occupied by PID $pid"
  fi
done
echo "Done."
```

5. **Report** what was killed (ports freed, process names). If nothing was running, say so.

## Rules

- **No confirmation needed** — execute immediately
- **Never kill Claude Code** — do not touch processes matching `claude`, `claude-code`, or the current shell's ancestor PIDs
- **Never kill non-dev processes** — only target processes related to dev servers and tools
- **SIGTERM first** — use `kill`, not `kill -9`. Only escalate to `kill -9` if a process survives after 2 seconds
- Exit codes 143/137 from killed background tasks are expected — ignore them
