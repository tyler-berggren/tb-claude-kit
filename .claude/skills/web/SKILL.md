---
name: web
description: Audit and repair a static site's SEO/AEO assets — metadata, structured data, sitemap, robots, llms.txt, markdown mirrors. Checks they are present, correct, and still current against the pages they describe.
argument-hint: "[live|report] or empty to scan and fix"
---

## Site root
!`ROOTS=$(jq -r '.web.roots[]?' .claude/kit.json 2>/dev/null); [ -z "$ROOTS" ] && ROOTS="web public dist site build _site out sitemd/site"; for r in $ROOTS; do [ -d "$r" ] && ls "$r"/*.html >/dev/null 2>&1 && echo "$r ($(find "$r" -name '*.html' -not -path '*/.*' | wc -l | tr -d ' ') html files)" && break; done || echo "No site directory found — set web.roots in .claude/kit.json"`

## Base URL
!`jq -r '.web.baseUrl // "not set — set web.baseUrl in .claude/kit.json for canonical and sitemap checks"' .claude/kit.json 2>/dev/null || echo "no kit.json"`

## Asset inventory
!`ROOT=$(jq -r '.web.roots[0]? // empty' .claude/kit.json 2>/dev/null); [ -z "$ROOT" ] && for r in web public dist site build _site out sitemd/site; do [ -d "$r" ] && ROOT="$r" && break; done; for a in robots.txt sitemap.xml llms.txt llms-full.txt _headers; do [ -f "$ROOT/$a" ] && echo "  present  $a" || echo "  MISSING  $a"; done 2>/dev/null`

---

# Web — SEO/AEO asset audit

Static sites accumulate two kinds of rot. Assets go **missing** (no llms.txt, no
structured data, no snippet directives), and — more insidiously — assets go
**stale**: the sitemap still claims a page was last touched in March, the
markdown mirror describes a service you renamed, the FAQ schema answers a
question the page no longer asks. The second kind is worse than having nothing,
because it feeds confident wrong answers to the engines reading it.

This skill scans for both, fixes what has one right answer, and asks about
anything that involves words a human would recognize as their own voice.

## Dispatch

| Argument | Behavior |
|---|---|
| _(empty)_ | Scan, auto-fix mechanical findings, propose the rest |
| `report` | Scan and report only — write nothing |
| `live` | Scan plus probe the deployed site, then fix as normal |
| `live report` | Probe and report, write nothing |

## Procedure

### Step 1 — Scan

```bash
python3 .claude/skills/web/scan.py --json
```

Add `--live` when the argument asks for it. The scanner reads `web.roots` and
`web.baseUrl` from `.claude/kit.json`; pass `--root` / `--base-url` to override.

It writes nothing, ever. Output is JSON: `{root, baseUrl, pages, counts, findings}`,
each finding carrying `severity`, `check`, `file`, `line`, `message`, `detail`,
and `fix` (`auto` or `manual`).

If the scanner reports it cannot find a site directory, ask which directory holds
the built site and offer to record it in `.claude/kit.json` rather than passing
`--root` every run.

### Step 2 — Triage before touching anything

Read every finding before you fix any of them. The scanner is deliberate about
severity but it cannot see intent:

- A `noindex` page with no Open Graph tags is **correct**, not a gap. The scanner
  already suppresses this — if you see it flagged, the page's robots meta is not
  what you assumed.
- `mirror-missing-section` on a heading the mirror deliberately rewords is a
  judgment call, not a defect.
- `schema-price-mismatch` may mean the page copy changed and the schema is now
  lying, **or** that the page says "starting at $5,000" while the schema
  correctly uses `minPrice`. Read both before deciding which one is wrong.

Never fix a finding you have not looked at in its source file.

### Step 3 — Auto-fix the mechanical findings

Findings marked `"fix": "auto"` have exactly one correct answer. Apply them
directly, no confirmation:

| Check | Fix |
|---|---|
| `sitemap-stale-lastmod` | Set `<lastmod>` to the page's real last-modified date |
| `sitemap-missing-page` | Add the `<url>` entry |
| `sitemap-orphan` | Remove the entry, or note it if the page is deploy-generated |
| `sitemap-no-lastmod` | Add `<lastmod>` |
| `open-graph` | Add the missing tag, mirroring existing values on the page |
| `og-image-relative` | Make the URL absolute against `baseUrl` |
| `twitter-card` | Add `summary_large_image` when an `og:image` exists, else `summary` |
| `snippet-directives` | Add `max-snippet:-1, max-image-preview:large, max-video-preview:-1` |
| `canonical`, `canonical-relative`, `canonical-mismatch` | Point at the absolute page URL |
| `headers-content-type` | Add a `Content-Type` rule for the asset |
| `robots-no-sitemap`, `robots-no-llms` | Add the reference |
| `favicon`, `apple-touch-icon`, `viewport`, `lang` | Add, reusing assets already in the project |
| `llms-full-stale` | Regenerate from the current mirrors |

Match the file's existing formatting — indentation, attribute order, quote style,
whether tags are one-per-line or wrapped. A fix that reformats surrounding lines
is a bad fix.

### Step 4 — Propose everything else

Findings marked `"fix": "manual"` touch words, structure, or claims. Show the
user what is wrong and what you would write, then wait.

This especially covers **anything a human would recognize as their own voice** —
meta descriptions, `llms.txt` prose, FAQ answers, page copy. Many projects hold
the rule that the human writes all customer-facing language; machine-facing text
like `llms.txt` still counts, because it is the text an answer engine is most
likely to paraphrase when describing them.

Present them grouped, with the actual before/after:

```
NEEDS YOUR CALL

  faq-answer-drift — web/index.html
    Page:   "Nope. For right now, it's just me."
    Schema: "Nope. For right now it's just me."
    → The schema is stale. Update it to match the page? [y/n]

  description-length — web/index.html (179 chars, aim ≤165)
    Current:  "I handle all of your tech so you can focus..."
    Proposed: "..."
    → Your copy. Rewrite, or leave it? [y/n/edit]
```

For content drift, the page is almost always the source of truth and the derived
asset (schema, mirror, `llms-full.txt`) is what is stale. Say which direction you
propose to sync and why, because occasionally it is the other way round.

### Step 5 — Re-scan

Run the scanner again. Confirm the count dropped and that you introduced nothing
new. Report the before/after counts honestly — if something is still failing,
say so rather than describing the run as clean.

### Step 6 — Record, if the project has a brain

When `cowork/brain/BRAIN.db` exists, log a milestone summarizing the run, and log
any finding the user declined to fix now as a task so it is not silently dropped:

```sql
INSERT INTO logs (type, title, body, tags, importance)
VALUES ('milestone', 'Web audit: <n> fixed, <n> deferred', '<what changed>', 'aeo,seo,website', 5);
```

Normalize tags: split on comma, trim, lowercase, sort, dedupe, rejoin.

## What gets checked

**Per page** — `lang`, title presence and length, meta description presence and
length, viewport, canonical (present, absolute, matches the page URL), robots
snippet directives, the Open Graph set, Twitter card, favicon and
apple-touch-icon, exactly one `h1`, heading-level skips, `img` alt text, JSON-LD
parses, and JSON-LD `@id` references resolving to a node that exists.

**Site-wide** — `robots.txt` exists and does not block the site, points at a
sitemap, mentions `llms.txt` when one exists; `sitemap.xml` is valid XML, lists
every indexable page, lists no page that does not exist, lists no `noindex` page,
and carries `lastmod` on each entry; `llms.txt` follows the llmstxt.org shape and
every link in it resolves on disk; `_headers` declares a `Content-Type` for
`.md` assets when `nosniff` is set.

**Currency** — this is the part that catches rot rather than absence:

- `sitemap-stale-lastmod` — `<lastmod>` older than the page's real last change,
  taken from git when the file is committed and clean, filesystem mtime otherwise
- `mirror-drift` / `mirror-missing-section` — a markdown mirror declared via
  `<link rel="alternate" type="text/markdown">` no longer matching its HTML page
- `llms-full-stale` — the concatenated corpus missing a mirror's current content
- `faq-count-mismatch` / `faq-question-mismatch` / `faq-answer-drift` — `FAQPage`
  structured data disagreeing with the `<details>` blocks actually rendered
- `schema-price-mismatch` — a price asserted in structured data that appears
  nowhere in the visible copy
- `llms-txt-dead-link` — `llms.txt` pointing at a file that does not exist

**Live** (`--live` only) — served `Content-Type` for `.md` and `.txt` assets,
canonical `Link` headers on markdown mirrors, HTTP status for every page and
asset, and redirect chains. This is the only way to catch deploy-config drift,
where the local `_headers` looks right and production ignores it.

## Configuration

```json
{
  "web": {
    "roots": ["web"],
    "baseUrl": "https://example.com",
    "ignore": [
      {
        "check": "mirror-missing-section",
        "file": "web/index.md",
        "match": "Hi, I’m Tyler",
        "note": "the mirror deliberately uses a descriptive heading for machine readers"
      }
    ]
  }
}
```

`roots` is a list of candidate directories; the first that exists and contains
HTML wins. Absent, the scanner tries `web`, `public`, `dist`, `site`, `build`,
`_site`, `out`, `sitemd/site`, then the project root.

`baseUrl` is the canonical origin. Without it, canonical-URL and sitemap-URL
checks are skipped and `--live` cannot run — everything else still works.

`ignore` records divergences the project has decided are correct, so a re-run
does not re-litigate them. Each rule needs `check`; `file` and `match` (a
substring of the finding's message) narrow it; `note` explains the decision and
is printed back whenever the rule fires.

Suppressed findings are counted in every run's header and listed under
`--show-suppressed`, and they stay in the JSON under `suppressed`. They are never
silently dropped — a suppression you cannot see is indistinguishable from a check
that stopped working.

**Only add an ignore rule when the user has decided the current state is right.**
Never silence a finding to make a run look clean. A rule with no `note` is a
rule nobody will be able to evaluate in six months.

## Rules

- **Scan before speaking.** Never characterize the site's SEO/AEO state from
  reading a file or two. Run the scanner.
- **The scanner never writes.** All repair goes through Claude's edits, so it is
  reviewable and matches each file's house style.
- **Auto means auto.** Findings marked `auto` are applied without asking. Do not
  pad the conversation by confirming a missing `og:site_name`.
- **Manual means ask.** Never rewrite a meta description, FAQ answer, or
  `llms.txt` paragraph and mention it afterwards. Propose, then wait.
- **The page is the source of truth.** When derived assets disagree with rendered
  copy, sync the asset to the page — unless the user says the page is the thing
  that is wrong.
- **Verify by re-scanning.** A fix is not done because the edit applied. Re-run
  and confirm the finding is gone.
- **Report failures plainly.** If findings remain, say which and why. Never
  describe a run as clean when it is not.
- **Do not invent assets the project has not opted into.** If a site has no
  markdown mirrors, their absence is not a finding — mirrors are only checked
  when a page declares one.

---

## Project overrides

If `.claude/kit.json` has a `rules."web"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."web" // empty' .claude/kit.json 2>/dev/null
```
