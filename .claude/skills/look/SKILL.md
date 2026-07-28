---
name: look
description: Inspect the shared Chrome viewport — DOM queries, computed styles, box model. Screenshots only when explicitly asked.
user_only: true
---

# Look — Chrome Viewport Inspection

Inspect elements in the shared Chrome browser that both you and the user are looking at. The user drives the browser (navigating, setting mobile viewport via Chrome's device toolbar). You inspect programmatically via a Puppeteer server.

**DOM-first, not screenshot-first.** Always use `inspect` or `dom` commands to get exact values. Only take a screenshot when the user explicitly asks for one.

## Multi-profile support

Each project gets its own Chrome instance with an isolated profile. Instances self-register in `~/.claude-chrome-registry.json` with their profile name, port, and PID. The profile name defaults to the project directory basename (e.g. `my-project`).

### Resolve the port for this project

Before any command, resolve the port from the registry:

```bash
LOOK_PORT=$(node -e "
  const fs = require('fs'), path = require('path'), os = require('os');
  const reg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude-chrome-registry.json'), 'utf8') || '[]');
  const profile = path.basename(process.cwd());
  const entry = reg.find(e => e.profile === profile) || reg[0];
  if (entry) { try { process.kill(entry.pid, 0); console.log(entry.port); } catch { console.log(''); } }
  else console.log('');
" 2>/dev/null)
```

If `$LOOK_PORT` is empty, the server isn't running — launch it (see below). Use `$LOOK_PORT` in place of a hardcoded port in all curl commands.

## Prerequisites

Check if a server is already running for this project:

```bash
LOOK_PORT=$(node -e "
  const fs = require('fs'), path = require('path'), os = require('os');
  const reg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude-chrome-registry.json'), 'utf8') || '[]');
  const profile = path.basename(process.cwd());
  const entry = reg.find(e => e.profile === profile) || reg[0];
  if (entry) { try { process.kill(entry.pid, 0); console.log(entry.port); } catch { console.log(''); } }
  else console.log('');
" 2>/dev/null)
curl -s http://127.0.0.1:${LOOK_PORT}/status 2>/dev/null
```

If this fails, **launch the cobrowser automatically** — don't ask the user:

```bash
# Launch puppeteer server for this project
node scripts/puppeteer-server.cjs
```

Run this command **in the background** — it's a long-running process.

Then wait for it to be ready and capture the port:

```bash
sleep 2
LOOK_PORT=$(node -e "
  const fs = require('fs'), path = require('path'), os = require('os');
  const reg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude-chrome-registry.json'), 'utf8') || '[]');
  const profile = path.basename(process.cwd());
  const entry = reg.find(e => e.profile === profile);
  if (entry) console.log(entry.port); else console.log('');
" 2>/dev/null)
for i in 1 2 3 4 5 6 7 8 9 10; do curl -s http://127.0.0.1:${LOOK_PORT}/status > /dev/null 2>&1 && break; sleep 1; done
```

If `/look` is called with a URL argument (e.g. `/look http://localhost:3000`), pass it to the server:

```bash
node scripts/puppeteer-server.cjs <URL>
```

To launch with a specific profile name:

```bash
node scripts/puppeteer-server.cjs --profile my-other-project http://localhost:3000
```

## Commands

All commands are POST requests to `http://127.0.0.1:${LOOK_PORT}` with a JSON body.

### inspect — Computed styles + box model (use this most)

```bash
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"inspect","selector":".hero-section"}'
```

Returns: computed styles (display, position, width, height, padding, margin, font-size, line-height, overflow, flex properties, gap, z-index, colors), bounding rect, tag/class/id, child count, text content.

### dom — HTML structure + children

```bash
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"dom","selector":".hero-section","children":true}'
```

Returns: outerHTML, attributes, child elements (tag, class, id, text). Use `children: true` to see immediate children.

### screenshot — Viewport or element capture (only when user asks)

```bash
# Full viewport
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"screenshot"}'

# Specific element
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"screenshot","selector":".hero-section"}'
```

Returns: `{ "path": "/tmp/puppeteer-screenshot-<ts>.png" }`. Read the file to view it.

**Only use this when the user explicitly asks to see a screenshot.** DOM inspection is always the default.

### eval — Run JS in page context

```bash
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"eval","expression":"document.querySelectorAll(\".card\").length"}'
```

Returns: `{ "result": "6" }`. Use for queries that don't fit inspect/dom.

### status — Current page state

```bash
curl -s http://127.0.0.1:${LOOK_PORT}/status
```

Returns: URL, title, viewport width/height, device pixel ratio, scroll position, document height, profile name, port. Use to confirm what viewport the user has set.

## Procedure

When the user says "look at X":

1. **Resolve the port** — run the registry lookup to get `$LOOK_PORT` for this project
2. **Always check status first** — call the `/status` endpoint to confirm which page the user is on (URL), the current viewport dimensions, and scroll position. Do NOT assume you know which page or element the user is referencing — the status response is the ground truth. If the user's request references text or an element, confirm it exists on the page shown in the status URL before proceeding.
3. **Inspect the element** — use the `inspect` command with the selector the user mentioned (or derive the selector from their description)
4. **Reason from the data** — use the computed styles, box model, and bounding rect to understand the layout. Report findings concisely: what the values are, what they mean for the layout issue
5. **If you need more context** — use `dom` to see the HTML structure, or inspect parent/sibling elements to understand the layout context
6. **Edit the source** — make the CSS/HTML fix in the appropriate source file
7. **Re-inspect to verify** — after the dev server hot-reloads (~1-2 seconds), inspect the same element again to confirm the computed values changed as expected

## Common Inspection Patterns

### Overflow detection
```bash
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"eval","expression":"const el = document.querySelector(\".container\"); const rect = el.getBoundingClientRect(); JSON.stringify({width: rect.width, viewportWidth: window.innerWidth, overflows: rect.width > window.innerWidth})"}'
```

### Flex layout debugging
Inspect the flex container to see `flex-direction`, `flex-wrap`, `justify-content`, `align-items`, `gap`. Then inspect individual flex children to see their computed `width`, `flex-basis`, `flex-grow`, `flex-shrink`.

### Spacing issues
Inspect the element — check `padding-*`, `margin-*`, `gap` in computed styles. Check parent and siblings if spacing comes from the container.

### Media query state
Use `status` to get current viewport width, then check what CSS values apply at that width by inspecting the element. The computed styles reflect the active media queries.

### Finding the right selector
```bash
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"eval","expression":"document.querySelectorAll(\".hero-section\").length"}'
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"dom","selector":".hero-section","children":true}'
```

## Rules

- **No confirmation needed** — execute immediately
- **DOM-first** — never screenshot unless the user explicitly asks. Inspect is always the default.
- **Re-inspect after edits** — always verify your fix by re-inspecting the element after the dev server reloads
- **Report concisely** — don't dump raw JSON at the user. Summarize the relevant values and what they mean for the issue
- **Viewport is the user's** — never resize or navigate the browser. The user controls Chrome directly.

---

## Project overrides

If `.claude/kit.json` has a `rules."look"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."look" // empty' .claude/kit.json 2>/dev/null
```
