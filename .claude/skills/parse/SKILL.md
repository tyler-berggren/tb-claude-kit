---
name: parse
description: Convert local documents (docx, pdf, xlsx, pptx, rtf, odt, epub, csv, html) to markdown via Firecrawl parse. Takes a file, a glob, or a directory and writes .md alongside the originals.
argument-hint: "<file|dir|glob> [--formats markdown,summary] [--out <dir>] [--stdout] [--redact]"
---

# Parse — local documents to markdown

Firecrawl's `/v2/parse` endpoint turns a local binary document into clean
markdown. It is the counterpart to `/scrape`: scrape is for public URLs, parse
is for files on this machine that no URL points at — signed contracts, client
decks, exported spreadsheets, scanned PDFs.

Docs: https://docs.firecrawl.dev/features/parse

## Input

`$ARGUMENTS` — a path, then optional flags.

| Token | Meaning |
|---|---|
| _first token_ | File, directory, or glob. A directory means every supported file directly inside it — not recursive unless the user asks. |
| `--formats` | Comma-separated: `markdown` (default), `html`, `rawHtml`, `links`, `images`, `summary`, `json`. |
| `--out <dir>` | Write outputs here instead of alongside the originals. |
| `--stdout` | Print the markdown into the conversation, write nothing. |
| `--redact` | Set `redactPII: true` — strips personal identifiers from returned content. |
| `--pages <n>` | PDFs only: cap at `pdfOptions.maxPages`. |

If the path is missing or matches nothing, list the supported extensions and stop.

**Supported:** `.pdf .docx .doc .docm .odt .rtf .html .htm .xhtml .xlsx .xls .xlsm .xlsb .ods .pptx .ppt .pptm .odp .epub .csv`

A public document URL is not this skill — use `firecrawl_scrape` instead.

## Credentials

Resolve a Firecrawl API key from the first source that has one, and **never
print it** — assign to a variable, reference the variable:

1. `$FIRECRAWL_API_KEY` already in the environment
2. `.env` in the project root (`set -a; . ./.env; set +a`)
3. `.mcp.json` → `mcpServers.firecrawl.env.FIRECRAWL_API_KEY`
4. `~/.claude.json` → the same path, under this project or globally

If none has one, say so and point at https://firecrawl.dev — do not guess at a
key or fall back to keyless mode, which does not cover parse.

## Method

Prefer the MCP tool; fall back to curl.

**1. `mcp__firecrawl__firecrawl_parse`** with `filePath` and `formats`. This
works only when the firecrawl MCP server has **`FIRECRAWL_API_URL` set** — the
local-mode handler hard-requires it and otherwise throws
`requires FIRECRAWL_API_URL to be set to a self-hosted Firecrawl API instance`.
It never checks that the URL *is* self-hosted, so setting it to
`https://api.firecrawl.dev` satisfies the guard and routes to the cloud API.
The kit's `.mcp.json` template sets this. If the tool throws that error here,
the project's `.mcp.json` predates it: add the variable, mention that MCP
servers only pick it up on session restart, and use curl for now.

**2. Fallback — curl.** Use this when the tool errors, when the MCP server is
unavailable, or when parsing several files (one request each, run in parallel).

```bash
curl -sS -X POST https://api.firecrawl.dev/v2/parse \
  -H "Authorization: Bearer $KEY" \
  -F "file=@<path>" \
  -F 'options={"formats":["markdown"]};type=application/json'
```

Response is `{success, data:{markdown, ...}}`. On `success: false`, report the
error verbatim rather than retrying blind. Parse the JSON with python, not
`jq`-into-shell-quoting — document markdown is full of characters that break
shell interpolation. Write the output file from python too.

## Output

Default: `<original-basename>.md` next to the source, originals untouched. Never
overwrite an existing `.md` without saying so first — check, and if one exists,
ask unless the user passed an explicit `--out`.

Report a table of file → output → size. Then **spot-check the conversion** and
say what you found:

- Tables are where docx and pdf conversion degrades — open any output with
  fee schedules, phase plans, or line items and confirm the columns survived.
- Multi-column PDFs can interleave text across columns.
- Headers, footers, and page numbers often land mid-document.
- Signature blocks and form underscores usually survive as literal `\_\_\_`.

Do not claim the parse is clean without having looked at the output.

## Constraints

- **50 MB** per file, one file per request, no batch endpoint.
- Default timeout 30s, max 300s. Long PDFs: bound with `--pages`.
- Parse consumes Firecrawl credits per file.
- **Parsing uploads the file to Firecrawl's API.** For anything confidential —
  contracts, client data, anything under NDA — say so plainly before the first
  request. If the user already named the files, that is authorization; note it
  and proceed rather than blocking. Offer `--redact` when the documents contain
  personal information.

## Project configuration

Read `.claude/kit.json` → `rules.parse` if present and apply it. Use it for
project-specific filing conventions — where parsed documents belong, whether
they get committed, whether a parsed contract should also be logged to the
brain.

Absent a rule: keep the `.md` beside its original so the pair travels together,
and offer a brain entry for documents worth remembering rather than assuming one.
