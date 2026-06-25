---
name: research
description: Run web and project research on a topic, producing a numbered report in cowork/research/.
argument-hint: "<topic or question>"
---

## Existing Research
!`sqlite3 -separator ' — ' cowork/brain/BRAIN.db "SELECT '#' || id, title, created_at, json_extract(meta, '$.file') FROM logs WHERE type='note' AND tags LIKE '%research%' AND status = 'done' ORDER BY created_at DESC;" 2>/dev/null || echo "No research reports yet"`

---

# Research Report

Conduct thorough web and project research on a user-provided topic, then write a structured report.

## Input

The user provides a research topic or question as the argument: `$ARGUMENTS`

If no argument is provided, ask the user what they'd like researched.

## Procedure

### Step 1 — Determine the next report number

List files in `cowork/research/` and find the highest `NNN` prefix. The new report gets `NNN + 1` (zero-padded to 3 digits). If the directory is empty or doesn't exist, create it and start at `000`.

### Step 2 — Check for prior research

Before searching the web, scan existing reports in `cowork/research/` for reports on related topics. If prior work exists, note it — build on it rather than re-covering the same ground.

### Step 3 — Assess depth and confirm with the user

Assess the topic and propose a research depth before executing:

- **Quick lookup** (narrow factual question, specific API behavior, current pricing): 2-3 sources, 1-2 page report. Get the answer and confirm it.
- **Standard research** (technology evaluation, how-to, comparison): 4-6 sources, 3-5 page report. Cover the topic from multiple angles.
- **Deep dive** (strategic analysis, competitive landscape, architecture decision): 6-12 sources, 5-15 page report. Multiple search passes, cross-referencing, exhaustive coverage.

Briefly present: the proposed depth, 3-5 search angles you plan to cover, and any relevant prior research found in Step 2. Wait for user confirmation before proceeding. This is the ONE exception to "execute immediately."

### Step 4 — Plan the search

Before using any search tools, decompose the topic into 3-5 distinct research angles. These should be orthogonal — designed to surface *different* source types, not variations of the same query. Common angle dimensions:

- **Mechanism/theory** — How does it work? What are the fundamentals?
- **Practical usage** — Who uses it, how, and why? Real-world examples and case studies.
- **Failure modes/limitations** — What goes wrong? What are the criticisms and tradeoffs?
- **Alternatives/comparisons** — What else exists? How do options compare?
- **Recent developments** — What changed recently? What's the current state?

Formulate one specific search query per angle.

### Step 5 — Conduct parallel web research

Spawn 3-5 sub-agents (using the Agent tool) to search different angles simultaneously. Each agent gets a distinct focus:

- **Agent A** — Official/primary sources and documentation. Use WebSearch with `allowed_domains` targeting official docs, specs, and authoritative references.
- **Agent B** — Community discussion, practitioner perspectives, and real-world evidence. Use Brave Search MCP (`mcp__brave-search__brave_web_search`) — it has an independent index and can surface Reddit content that built-in WebSearch cannot access. Target reddit.com, news.ycombinator.com, blog posts, forums.
- **Agent C** — Conceptual and semantic exploration. Use Exa MCP for neural/semantic search — it finds conceptually related content that keyword search misses. Best for "how do people think about X" and "what's related to Y" queries.
- **Agent D** — Code-level evidence and technical depth. Use `gh search repos`, `gh search issues`, GitHub discussions, and technical references.

Each agent should:
- Pick the right search tool for the job (see **Search Tool Selection** below)
- Use WebFetch with **targeted extraction prompts** (never "summarize this page" — instead: "Extract the specific benchmarks, methodology, and limitations discussed" or "What criticisms and failure modes are described? Include concrete examples")
- Use `allowed_domains` / `blocked_domains` on WebSearch/Brave to focus results
- Return: key findings, source URLs with descriptions, and any new terms/concepts discovered

For quick lookups, a single agent or direct search is sufficient — skip the parallel spawn.

#### Search Tool Selection

Use whatever search tools are available. The skill works with just WebSearch + WebFetch (built-in), but is significantly better with Brave Search and/or Exa MCPs installed.

| Tool | Best for | Limitations | Required? |
|---|---|---|---|
| **WebSearch** (built-in) | Quick factual lookups, official docs | Cannot access Reddit; keyword-only | Always available |
| **WebFetch** (built-in) | Deep extraction from known URLs | Need the URL first | Always available |
| **Brave Search MCP** | Community content (Reddit, HN, forums), news, broad keyword search | Keyword-only, no semantic understanding | Optional |
| **Exa MCP** | Conceptual/semantic queries, finding related work, "how do people think about X" | Less precise for exact keyword matches | Optional |

- **If Brave Search is available**, default to it for most queries — it has the richest result set and can access domains that built-in WebSearch cannot (notably Reddit).
- **If Exa is available**, use it when exploring a concept space or when keyword queries aren't surfacing what you need. Exa's neural search finds semantically related content even without exact keyword matches.
- **If neither MCP is available**, use built-in WebSearch for discovery and WebFetch with targeted extraction prompts to go deep on found URLs. Adjust agent count in Step 5 accordingly (2-3 agents instead of 4-5).
- **Combine tools** within a single agent when appropriate — e.g., Brave for keyword search, then Exa to find conceptually related sources the keywords missed.

### Step 6 — Iterative deepening

After synthesizing initial results from all agents, identify:

- **New terms, projects, or concepts** that appeared in sources but weren't in your original queries. Search for the 1-3 most important ones.
- **Gaps**: Which key questions remain unanswered? Are any perspectives missing? Are quantitative claims unsupported?
- **Contradictions**: Where do sources disagree? Do targeted searches to understand why.

If significant gaps remain, do a focused second pass. One good source that fills a gap is worth more than three more sources confirming what you already know.

### Step 7 — Conduct project research

Search the codebase and project files for anything relevant to the topic — existing code, configs, docs, patterns, prior decisions. Query `cowork/brain/BRAIN.db` for related decisions and insights. This grounds the report in the project's actual state.

### Step 8 — Write the report

Write to `cowork/research/NNN_YYYY-MM-DD_topic.md` using this structure:

```markdown
# {Title}

> **Date:** {YYYY-MM-DD}
> **Topic:** {brief topic description}

## Summary

{2-4 sentence executive summary of findings}

## Key Findings

{Numbered list of the most important discoveries, insights, or facts. Signal confidence:
- State facts as facts ("X costs $79/month")
- Qualify consensus ("The general consensus among practitioners is...")
- Flag contested claims ("Sources disagree — [A] claims X while [B] claims Y")
- Label inferences ("Based on [evidence], it appears that...")}

## Detail

{Deeper analysis organized by subtopic. Use ### subheadings as needed.}

## Open Questions

{Important questions this research could NOT conclusively answer. For each: what the question is, why it remains open (insufficient sources, conflicting info, topic too new), and how it might be resolved.}

## Project Relevance & Next Steps

{How findings relate to this project. Reference existing brain entries, decisions, or code.}

### Recommended Actions

{Numbered list of concrete, actionable next steps based on findings. Each should be specific enough to act on — "Evaluate library X for the caching layer" not "Consider caching options."}

## Sources

{Numbered list. Annotate each with type and role:}

1. [Title](URL) — **Official docs.** Used for: {what this source provided}
2. [Title](URL) — **Blog post.** Used for: {what this source provided}
3. [Title](URL) — **GitHub issue.** Used for: {what this source provided}
```

If prior research is relevant, reference it in the body: "See also: `015_2026-04-07_topic.md`"

### Step 9 — Register in brain DB

After writing the report, create a BRAIN.db entry to catalog it:

```sql
INSERT INTO logs (type, title, body, tags, status, pillar, importance, meta, created_at)
VALUES ('note', '{Report Title}', '{10-word summary}', 'research', 'done', '{relevant pillar}', 5,
  json('{"file": "cowork/research/NNN_YYYY-MM-DD_topic.md"}'), '{ISO 8601 timestamp}');
```

### Step 10 — Report back

Report back with the file path and a 2-3 sentence summary of what was found.

If findings are significant enough to inform future project decisions, also add a brain entry via:
```sql
INSERT INTO logs (type, title, body, tags, importance)
VALUES ('insight', '<title>', '<key finding summary>', 'research', <importance>);
```

## Search Technique Reference

These are guidelines for effective searching, not mandatory steps for every report.

**Tool selection (use what's available):**
- **Built-in WebSearch** — always available. Supports `allowed_domains`/`blocked_domains` for domain targeting.
- **Built-in WebFetch** — always available. Deep extraction from specific URLs with targeted prompts.
- **Brave Search MCP** (optional) — `mcp__brave-search__brave_web_search`. Independent index, surfaces Reddit/HN content that built-in WebSearch blocks.
- **Exa MCP** (optional) — neural/semantic search. Use when keyword queries aren't surfacing the right results.
- Load MCP tool schemas via ToolSearch before first use: `ToolSearch("select:mcp__brave-search__brave_web_search")` or search for exa tools.

**Domain targeting (WebSearch and Brave):**
- `allowed_domains: ["reddit.com", "news.ycombinator.com"]` — community signal (use Brave for Reddit — built-in WebSearch is blocked)
- `allowed_domains: ["github.com"]` — code-level evidence, issues, discussions
- `allowed_domains: ["arxiv.org"]` — academic papers
- `blocked_domains` — exclude content farms identified in initial results

**Recency:**
- Fast-moving topics (AI, frameworks, APIs): include the current year in at least one query
- Stable topics (algorithms, protocols): prioritize authoritative sources over recent ones

**GitHub CLI:**
- `gh search repos "topic" --sort=stars` — adoption signals
- `gh search issues "error message" --repo=org/repo` — real-world problems
- `gh search code "pattern" --language=typescript` — implementation examples

**PDF sources:**
- The Read tool supports PDFs via the `pages` parameter (max 20 pages per request)
- For long PDFs: read abstract/intro (pages 1-3) and conclusion first

**WebFetch prompt engineering:**
- Bad: "Summarize this page"
- Good: "Extract the specific performance benchmarks, test methodology, and hardware specs"
- Good: "What are the criticisms and failure modes discussed? Include concrete examples and data points"
- Good: "List all pricing tiers, what's included in each, and any usage limits mentioned"
- Tailor each prompt to what *that specific source* likely has that others didn't provide

## Rules

- **Confirm depth first** — Propose depth + angles, wait for user confirmation, then execute
- **Use today's actual date** for the filename, not a hardcoded date
- **Topic slug** in the filename should be short kebab-case (e.g., `css-cascade-layers`, `static-site-generators`)
- **Be thorough** — This is a research tool, not a quick answer. Dig into multiple sources and synthesize.
- **Cite sources** — Every claim should be traceable to a source. Annotate sources with type and role.
- **Signal confidence** — Distinguish facts from consensus from contested claims from inferences
- **Flag contradictions** — When sources disagree, say so explicitly. Don't silently pick one version.
- **Source diversity** — Aim for 2-3+ different source types (official docs, blogs, community, GitHub, academic)
- **Project context matters** — Always include how findings relate to this project
- **Plain markdown** — No Obsidian-specific syntax (no frontmatter tags, wikilinks, or callout blocks)
