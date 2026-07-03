---
name: bridge
description: Start the artifact bridge server for HTML artifacts to read/write project files.
user_only: true
---

# Artifact Bridge

Starts a lightweight localhost HTTP server that lets HTML artifacts (opened in a browser) read and write project files via fetch.

**Endpoints:**
- `GET /status` — health check, returns project root
- `GET /read?path=relative/path` — read a file
- `POST /write` `{ path, content }` — write a file

All paths are relative to project root and cannot escape it.

## Procedure

1. **Kill any existing bridge on port 4444:**

```bash
lsof -iTCP:4444 -sTCP:LISTEN -t 2>/dev/null | xargs kill 2>/dev/null
sleep 1
```

2. **Start the bridge server in background:**

```bash
node scripts/artifact-bridge.cjs "$(pwd)"
```

Run this command **in the background** — it's a long-running process.

3. **Wait for the server to be ready:**

```bash
for i in 1 2 3 4 5; do
  curl -s http://127.0.0.1:4444/status > /dev/null 2>&1 && break
  sleep 1
done
```

4. **Report:**

```
Artifact bridge: http://127.0.0.1:4444
Root: <project root>
```

## Rules

- **No confirmation needed** — execute immediately
- Port 4444, bound to 127.0.0.1 only
- Files scoped to project root — no path traversal outside project

## Artifact Integration

HTML artifacts can connect to the bridge with this pattern:

```javascript
var BRIDGE = 'http://127.0.0.1:4444';

// Check connection
fetch(BRIDGE + '/status').then(r => r.json())

// Read a file
fetch(BRIDGE + '/read?path=src/example.ts').then(r => r.json())

// Write a file
fetch(BRIDGE + '/write', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ path: 'src/example.ts', content: '...' })
})
```

Add a status indicator in the artifact header to show bridge connectivity:
```javascript
setInterval(function() {
  fetch(BRIDGE + '/status').then(r => { connected = r.ok; })
    .catch(() => { connected = false; });
}, 5000);
```
