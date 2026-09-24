---
name: look
description: Inspect the shared Chrome viewport — DOM queries, computed styles, box model to diagnose; one screenshot to confirm a visual change landed, otherwise only when asked. Headless mode gives a coding agent its own private browser to check that a UI works — navigate, click, type, collect errors — without touching the user's window.
user_only: true
---

# Look — Chrome Viewport Inspection

Inspect elements in the shared Chrome browser that both you and the user are looking at. The user drives the browser (navigating, setting mobile viewport via Chrome's device toolbar). You inspect programmatically via a Puppeteer server.

**DOM-first to diagnose, eyes to confirm.** Use `inspect` or `dom` for exact values when diagnosing a known problem — computed styles answer "why is this 40px too wide" better than a picture does. But a measurement only reports on the elements you chose to measure, and a layout regression usually lands somewhere else. So **after making a visual change, take one screenshot of the affected area and look at it before calling the change done.** Otherwise, screenshot only when the user asks.

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

### screenshot — Viewport or element capture (to confirm a visual change, or when the user asks)

```bash
# Full viewport
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"screenshot"}'

# Specific element
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"screenshot","selector":".hero-section"}'
```

Returns: `{ "path": "/tmp/puppeteer-screenshot-<ts>.png" }`. Read the file to view it.

Use it for two things only: **confirming a visual change you just made** (one capture of the affected area, looked at before you say it works), and when the user asks. Diagnosis stays DOM-first.

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

### viewport — Pin a width, to check a responsive layout

```bash
# A phone-sized viewport
curl -s -X POST http://127.0.0.1:${LOOK_PORT} \
  -d '{"command":"viewport","width":390,"height":844,"isMobile":true}'

# Hand it back to the real window — ALWAYS do this when finished
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"viewport","width":null}'
```

The browser runs with `defaultViewport: null`, so the page normally follows the real window
and there is no way to hold a fixed width without this. `window.resizeTo` does not do it —
it moves the outer frame while `innerWidth` stays put, so a layout check against it is
measuring nothing.

`height` defaults to 844 and `deviceScaleFactor` to 2; `isMobile` also turns on touch. A
width under 200 is refused.

**Ask before using it, and always reset afterwards.** It changes what the user sees on their
own screen — see the viewport rule below.

## Headless — an agent's own browser

The shared window is the user's. When an agent needs to check that a UI **works** — while
building, inside a batch, or as a swarm unit — it runs its own headless Chrome instead. That
browser has:
- its own port;
- a throwaway profile, deleted on exit;
- no entry in the registry.

Several can run at once, and none of them can touch the user's window. **Whether the UI looks
right** — design, layout, wording, a design choice — is not the agent's call. It goes to the
plan's review block (`/plan`, **Batches**) with the page's URL, for the user to open in the
shared window themselves.

### Start and stop

From the project root, start it in the background with its one stdout line going to a file:

```bash
HL_OUT="$(mktemp)"   # or a file in your scratch directory
node scripts/puppeteer-server.cjs --headless > "$HL_OUT"     # run in the background
```

```bash
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$HL_OUT" ] && break; sleep 0.5; done
HL_PORT=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).port)" "$HL_OUT")
HL_PID=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).pid)" "$HL_OUT")
```

The line reads `{"headless":true,"port":57736,"pid":10072,"userDataDir":"…"}`. The OS picks the
port; `--port <n>` asks for one exactly and exits if it is busy, rather than driving someone
else's server. **Always stop it when done:** `kill $HL_PID`. That removes Chrome and its profile.

Commands are the same POST requests as the shared window's, to `http://127.0.0.1:${HL_PORT}`. The
viewport is a fixed 1440×900 until you change it.

### Commands only headless should use

These work in both modes, but on the shared window they would move the user's browser, which is
never yours to do.

| Command | Body | Returns |
|---|---|---|
| `goto` | `{url, waitUntil?, timeout?}` — waits for `networkidle2`, 30 s by default | `{url, status, title}`; clears the error log |
| `click` | `{selector}`, `{text}`, or both (the text searched within each selector match) | `{clicked, matches}`, plus `coveredBy` when another element sat on top |
| `type` | `{selector, text, clear?}` — appends, or replaces with `clear: true` | `{typed, value, into}` |
| `press` | `{key}` — `"Escape"`, `"Enter"`, `"Shift+Tab"` | `{pressed, focused}` |
| `waitFor` | `{selector, hidden?, timeout?}` — 10 s by default | `{ok, ms}`, or a 408 on timeout |
| `errors` | `{clear?}` | `{count, console, pageErrors, network}` since the last `goto` |

- **Failure** is an `error` key in the response. The new commands also answer with a non-200
  status:
  - 400 — bad input;
  - 404 — nothing visible matched;
  - 408 — timeout;
  - 409 — the element matched but can't be used, e.g. it can't take focus;
  - 502 — navigation failed.
- **Selectors** are plain CSS. `click {text}` matches visible text, `aria-label` or a button's
  value, prefers an exact match, and clicks the nearest clickable ancestor. To target one overlay,
  scope it: `{selector: "[role=dialog]", text: "Close"}`.
- **`errors`** lists each failed request twice: once in `network` with its URL and status, and
  once as Chrome's own "Failed to load resource" console line. Judge from `network`.
- **Set the viewport before `goto`.** Changing `isMobile` reloads the page and loses its state,
  such as an open dialog.

### Checking a changed page

For each changed page, at each width the project checks (desktop, and a phone width such as 390):

1. `viewport`, then `goto` the page. Expect status 200 and the right title.
2. `errors`: expect nothing new in `pageErrors` or `network`.
3. Find the changed control the way a person would, by its text or role (`waitFor`, `click {text}`).
4. Drive the change: open it, fill it, `press Escape`, `waitFor … hidden: true`. If it saves
   something, `goto` the page again and confirm it stuck.
5. Check for overflow:
   `{"command":"eval","expression":"document.documentElement.scrollWidth > innerWidth"}` should be
   `false`.
6. Take one `screenshot` and look at it **for breakage only**: a blank page, overlapping or
   clipped controls, an error screen. A measurement only answers the question you asked.
7. Record a **look** item for the review block:
   - the URL;
   - what changed;
   - what to try;
   - what right looks like;
   - the widths;
   - what this check confirmed.

   Then `kill $HL_PID`.

How to reach the app — its base URL, and how a fresh profile gets signed in — is project-specific;
read it from `rules."look"` (below).

## Procedure

When the user says "look at X":

1. **Resolve the port** — run the registry lookup to get `$LOOK_PORT` for this project
2. **Always check status first** — call the `/status` endpoint to confirm which page the user is on (URL), the current viewport dimensions, and scroll position. Do NOT assume you know which page or element the user is referencing — the status response is the ground truth. If the user's request references text or an element, confirm it exists on the page shown in the status URL before proceeding.
3. **Inspect the element** — use the `inspect` command with the selector the user mentioned (or derive the selector from their description)
4. **Reason from the data** — use the computed styles, box model, and bounding rect to understand the layout. Report findings concisely: what the values are, what they mean for the layout issue
5. **If you need more context** — use `dom` to see the HTML structure, or inspect parent/sibling elements to understand the layout context
6. **Edit the source** — make the CSS/HTML fix in the appropriate source file
7. **Re-inspect to verify** — after the dev server hot-reloads (~1-2 seconds), inspect the same element again to confirm the computed values changed as expected
8. **Look at it** — for a change to how something looks, take one screenshot of the affected region and check the whole area, not just the element you measured. Numbers that are right in isolation can sit beside a neighbour the change broke

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

### Scope queries to the open overlay
Popovers, dialogs and menus usually portal their content to the end of `<body>`, and a page that renders several instances of a component puts the first one first in document order. A bare `document.querySelector` then reads a closed or different instance — and can produce a convincing false confirmation. Find the open overlay first and query inside it:
```bash
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"eval","expression":"const d = document.querySelector(\"[role=dialog], [data-state=open]\"); d ? d.querySelectorAll(\"button\").length : \"no open overlay\""}'
```

### Finding the right selector
```bash
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"eval","expression":"document.querySelectorAll(\".hero-section\").length"}'
curl -s -X POST http://127.0.0.1:${LOOK_PORT} -d '{"command":"dom","selector":".hero-section","children":true}'
```

## Rules

- **No confirmation needed** — execute immediately
- **DOM-first to diagnose; one screenshot to confirm a visual change** — inspect is the default for finding a problem; after changing how something looks, look at it before saying it works. Otherwise screenshot only when asked.
- **Re-inspect after edits** — always verify your fix by re-inspecting the element after the dev server reloads
- **Report concisely** — don't dump raw JSON at the user. Summarize the relevant values and what they mean for the issue
- **Viewport is the user's** — do not navigate the browser, and do not resize it on your own
  initiative. The user controls Chrome directly. `goto`, `click`, `type` and `press` are for your
  own headless instance only. In an end-of-session review the user opens each item's URL in this
  window themselves, and tells you which item they are on. The one exception is checking a responsive
  layout, which cannot be done any other way: ask first, use the `viewport` command, and hand
  the width back with `{"width": null}` as soon as you have the answer. Never leave a session
  pinned to a width the user did not choose.

---

## Project overrides

If `.claude/kit.json` has a `rules."look"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.
It is where a project names what a headless agent needs: the base URL pages are reached through,
how a fresh profile gets signed in, the widths to check, and any page quirks.

```bash
jq -r '.rules."look" // empty' .claude/kit.json 2>/dev/null
```
