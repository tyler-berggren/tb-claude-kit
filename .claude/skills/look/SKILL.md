---
name: look
description: Inspect the shared Chrome viewport — DOM queries, computed styles, box model. Screenshots only when explicitly asked.
user_only: true
---

# Look — Chrome Viewport Inspection

Inspect elements in the shared Chrome browser that both you and the user are looking at. The user drives the browser (navigating, setting mobile viewport via Chrome's device toolbar). You inspect programmatically via a Puppeteer server on `localhost:9615`.

**DOM-first, not screenshot-first.** Always use `inspect` or `dom` commands to get exact values. Only take a screenshot when the user explicitly asks for one.

## Prerequisites

The Puppeteer server must be running. Check with:

```bash
curl -s http://127.0.0.1:9615/status
```

If this fails, **launch the cobrowser automatically** — don't ask the user:

```bash
# Kill any stale puppeteer server
lsof -iTCP:9615 -sTCP:LISTEN -t 2>/dev/null | xargs /bin/kill 2>/dev/null; sleep 1

# Launch puppeteer server — adjust path to your project's server script
node scripts/puppeteer-server.cjs
```

Run this command **in the background** — it's a long-running process.

Then wait for it to be ready:

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do curl -s http://127.0.0.1:9615/status > /dev/null 2>&1 && break; sleep 1; done
```

If `/look` is called with a URL argument (e.g. `/look http://localhost:3000`), pass it to the server:

```bash
node scripts/puppeteer-server.cjs <URL>
```

## Commands

All commands are POST requests to `http://127.0.0.1:9615` with a JSON body.

### inspect — Computed styles + box model (use this most)

```bash
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"inspect","selector":".hero-section"}'
```

Returns: computed styles (display, position, width, height, padding, margin, font-size, line-height, overflow, flex properties, gap, z-index, colors), bounding rect, tag/class/id, child count, text content.

### dom — HTML structure + children

```bash
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"dom","selector":".hero-section","children":true}'
```

Returns: outerHTML, attributes, child elements (tag, class, id, text). Use `children: true` to see immediate children.

### screenshot — Viewport or element capture (only when user asks)

```bash
# Full viewport
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"screenshot"}'

# Specific element
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"screenshot","selector":".hero-section"}'
```

Returns: `{ "path": "/tmp/puppeteer-screenshot-<ts>.png" }`. Read the file to view it.

**Only use this when the user explicitly asks to see a screenshot.** DOM inspection is always the default.

### eval — Run JS in page context

```bash
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"eval","expression":"document.querySelectorAll(\".card\").length"}'
```

Returns: `{ "result": "6" }`. Use for queries that don't fit inspect/dom.

### status — Current page state

```bash
curl -s http://127.0.0.1:9615/status
```

Returns: URL, title, viewport width/height, device pixel ratio, scroll position, document height. Use to confirm what viewport the user has set.

## Procedure

When the user says "look at X":

1. **Always check status first** — call the `/status` endpoint to confirm which page the user is on (URL), the current viewport dimensions, and scroll position. Do NOT assume you know which page or element the user is referencing — the status response is the ground truth. If the user's request references text or an element, confirm it exists on the page shown in the status URL before proceeding.
2. **Inspect the element** — use the `inspect` command with the selector the user mentioned (or derive the selector from their description)
3. **Reason from the data** — use the computed styles, box model, and bounding rect to understand the layout. Report findings concisely: what the values are, what they mean for the layout issue
4. **If you need more context** — use `dom` to see the HTML structure, or inspect parent/sibling elements to understand the layout context
5. **Edit the source** — make the CSS/HTML fix in the appropriate source file
6. **Re-inspect to verify** — after the dev server hot-reloads (~1-2 seconds), inspect the same element again to confirm the computed values changed as expected

## Common Inspection Patterns

### Overflow detection
```bash
# Check if element is wider than viewport
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"eval","expression":"const el = document.querySelector(\".container\"); const rect = el.getBoundingClientRect(); JSON.stringify({width: rect.width, viewportWidth: window.innerWidth, overflows: rect.width > window.innerWidth})"}'
```

### Flex layout debugging
Inspect the flex container to see `flex-direction`, `flex-wrap`, `justify-content`, `align-items`, `gap`. Then inspect individual flex children to see their computed `width`, `flex-basis`, `flex-grow`, `flex-shrink`.

### Spacing issues
Inspect the element — check `padding-*`, `margin-*`, `gap` in computed styles. Check parent and siblings if spacing comes from the container.

### Media query state
Use `status` to get current viewport width, then check what CSS values apply at that width by inspecting the element. The computed styles reflect the active media queries.

### Finding the right selector
```bash
# Count how many elements match
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"eval","expression":"document.querySelectorAll(\".hero-section\").length"}'

# Get children to find the right sub-element
curl -s -X POST http://127.0.0.1:9615 -d '{"command":"dom","selector":".hero-section","children":true}'
```

## Rules

- **No confirmation needed** — execute immediately
- **DOM-first** — never screenshot unless the user explicitly asks. Inspect is always the default.
- **Re-inspect after edits** — always verify your fix by re-inspecting the element after the dev server reloads
- **Report concisely** — don't dump raw JSON at the user. Summarize the relevant values and what they mean for the issue
- **Viewport is the user's** — never resize or navigate the browser. The user controls Chrome directly.
