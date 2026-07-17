---
name: research
description: Run web and project research on a topic, producing a numbered report in cowork/research/.
argument-hint: "<topic or question>"
---

## Existing Research
!`sqlite3 -separator ' — ' cowork/brain/BRAIN.db "SELECT '#' || id, title, created_at, json_extract(meta, '$.folder') FROM logs WHERE type='note' AND tags LIKE '%research%' AND status = 'done' ORDER BY created_at DESC;" 2>/dev/null || echo "No research reports yet"`

---

# Research Report

Conduct thorough web and project research on a user-provided topic, then write a structured report.

## Input

The user provides a research topic or question as the argument: `$ARGUMENTS`

If no argument is provided, ask the user what they'd like researched.

## Procedure

### Step 1 — Determine the next report number and create the run folder

List entries in `cowork/research/` and find the highest `NNN` prefix. The new report gets `NNN + 1` (zero-padded to 3 digits). If the directory is empty or doesn't exist, create it and start at `000`.

Create the run folder: `cowork/research/NNN_YYYY-MM-DD_topic/` (use today's actual date, short kebab-case topic slug). All output for this research run — subagent reports and the final summary — goes into this folder.

### Step 2 — Check for prior research

Before searching the web, scan existing reports in `cowork/research/` for reports on related topics. If prior work exists, note it — build on it rather than re-covering the same ground.

### Step 3 — Assess depth and confirm with the user

Assess the topic and propose a research depth before executing:

- **Quick lookup** (narrow factual question, specific API behavior, current pricing): 2-3 sources, 1-2 page report. Single agent or direct search.
- **Standard research** (technology evaluation, how-to, comparison): 4-6 sources, 3-5 page report. 3 parallel agents.
- **Deep dive** (strategic analysis, competitive landscape, architecture decision): 6-12 sources, 5-15 page report. Scout + 4-5 parallel agents + iterative deepening.

Briefly present: the proposed depth, 3-5 search angles you plan to cover, and any relevant prior research found in Step 2. Wait for user confirmation before proceeding. This is the ONE exception to "execute immediately."

### Step 4 — Scout pass (deep dive only)

For deep dives, run a single Perplexity query first to orient on the topic. This surfaces key concepts, major players, terminology, and the shape of the landscape before decomposing into research angles.

If Perplexity MCP is available, use `perplexity_search` or `perplexity_reason` with a broad framing of the topic. Save the scout output as `agent-scout.md` in the run folder.

If Perplexity is unavailable, do a quick WebSearch + WebFetch pass on the most authoritative source you can find. The scout phase is additive — skip it gracefully if tools are missing.

Use scout findings to refine the research angles from Step 3.

### Step 5 — Plan the research angles

Decompose the topic into 3-5 distinct research angles. Each angle is a specific *question to answer*, not a tool to use. Angles should be orthogonal — designed to surface different perspectives, not variations of the same query. Common dimensions:

- **Mechanism/theory** — How does it work? What are the fundamentals?
- **Practical usage** — Who uses it, how, and why? Real-world examples and case studies.
- **Community experience** — What do practitioners report? Reddit, HN, blog posts. What actually works vs what sounds good?
- **Failure modes/limitations** — What goes wrong? What are the criticisms and tradeoffs?
- **Alternatives/comparisons** — What else exists? How do options compare?
- **Recent developments** — What changed recently? What's the current state?

### Step 6 — Conduct parallel web research

Spawn 3-5 sub-agents (using the Agent tool) to search different angles simultaneously. Each agent gets:

1. **A research angle** — the specific question to answer
2. **The full tool stack** — every agent can use any tool (see Tool Stack below)
3. **Tool selection guidance** — advisory notes on which tools work best for what (see below)
4. **A file path** — the agent writes its own report directly to `cowork/research/NNN_YYYY-MM-DD_topic/agent-{label}.md`

**Each agent MUST write its own report file directly using the Write tool.** The orchestrator does NOT write agent reports. Subagents are capable of writing files — this is non-negotiable. If an agent fails to write its file, note it in the summary but do not rewrite the agent's findings.

Each agent's report should follow this structure:

```markdown
# {Angle Title}

## Search Approach
{What tools were used, what queries were run}

## Key Findings
{Numbered findings with confidence signals: HIGH/MEDIUM/LOW}

## Detailed Analysis
{Deeper analysis organized by subtopic}

## Sources
{Numbered list with URLs and what each source contributed}
```

Each agent should:
- Use multiple search tools — start broad, then extract deep from the best results
- Do all searching itself — do NOT spawn sub-agents of its own
- Follow the extraction cascade: WebFetch first (free) → Tavily extract (free tier) → Firecrawl (paid credits, only for JS-rendered/complex pages)
- Use **targeted extraction prompts** (never "summarize this page" — instead: "Extract the specific benchmarks, methodology, and limitations discussed")
- Use `allowed_domains` / `blocked_domains` on WebSearch/Brave to focus results
- Load MCP tool schemas via ToolSearch before first use

For quick lookups, a single agent or direct search is sufficient — skip the parallel spawn, but still save findings to the run folder.

### Step 7 — Iterative deepening

After all agents complete, read their reports and identify:

- **New terms, projects, or concepts** that appeared in sources but weren't in the original angles. Search for the 1-3 most important ones.
- **Gaps**: Which key questions remain unanswered? Are any perspectives missing? Are quantitative claims unsupported?
- **Contradictions**: Where do agents' findings disagree? Do targeted searches to understand why.

If significant gaps remain, spawn 1-2 focused follow-up agents. One good source that fills a gap is worth more than three more sources confirming what you already know.

### Step 8 — Conduct project research

Search the codebase and project files for anything relevant to the topic — existing code, configs, docs, patterns, prior decisions. Query `cowork/brain/BRAIN.db` for related decisions and insights. This grounds the report in the project's actual state.

### Step 9 — Write the final summary report

Write to `cowork/research/NNN_YYYY-MM-DD_topic/SUMMARY.md` — this is the main deliverable, synthesized from all subagent reports in the same folder.

**Synthesis rules — avoid "silent consensus hallucination":**
- Read every subagent report before writing. Reference which agent found what.
- Preserve specific numbers, quotes, and data points verbatim from agent reports (verbatim anchoring).
- Flag contradictions between agents explicitly — do NOT silently pick one version.
- Signal confidence levels: state facts as facts, qualify consensus, flag contested claims, label inferences.
- Note what was NOT found — gaps matter as much as findings.
- Minority findings from a single agent should be preserved, not dropped because the majority didn't mention them.

Use this structure:

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

{Numbered list of concrete, actionable next steps based on findings. Each should be specific enough to act on.}

## Sources

{Numbered list. Annotate each with type and role:}

1. [Title](URL) — **Official docs.** Used for: {what this source provided}
2. [Title](URL) — **Blog post.** Used for: {what this source provided}
3. [Title](URL) — **GitHub issue.** Used for: {what this source provided}
```

If prior research is relevant, reference it in the body: "See also: `015_2026-04-07_topic/SUMMARY.md`"

### Step 10 — Register in brain DB

After writing the report, create a BRAIN.db entry to catalog it:

```sql
INSERT INTO logs (type, title, body, tags, status, pillar, importance, meta, created_at)
VALUES ('note', '{Report Title}', '{10-word summary}', 'research', 'done', '{relevant pillar}', 5,
  json('{"folder": "cowork/research/NNN_YYYY-MM-DD_topic/", "summary": "cowork/research/NNN_YYYY-MM-DD_topic/SUMMARY.md"}'), '{ISO 8601 timestamp}');
```

### Step 11 — Report back

Report back with the file path and a 2-3 sentence summary of what was found.

If findings are significant enough to inform future project decisions, also add a brain entry via:
```sql
INSERT INTO logs (type, title, body, tags, importance)
VALUES ('insight', '<title>', '<key finding summary>', 'research', <importance>);
```

---

## Tool Stack

Every research agent has access to the full tool stack. Tools are listed in order of preference for each capability.

### Search Tools (discovery)

| Tool | What It Does | Best For | Load With |
|---|---|---|---|
| **Brave Search** | Keyword search with independent 30B+ page index | Reddit, HN, forums, community content, news. Default for most keyword queries. | `ToolSearch("select:mcp__brave-search__brave_web_search")` |
| **Exa** | Neural/semantic search | Conceptual queries, finding related work, "how do people think about X", discovering content keywords miss. 60% pass rate on semantic queries vs 38% for keyword search. | `ToolSearch("+exa")` |
| **Tavily** | Agent-native keyword search, 187ms avg latency | Fast factual lookups, clean agent-ready responses. Use when you need speed or Brave is unavailable. | `ToolSearch("+tavily")` |
| **Perplexity** | Pre-synthesized answers with citations | Scout/orientation on new topics, quick synthesis of 10-15 sources. Too slow (1.4s+) for tight loops. | `ToolSearch("+perplexity")` |
| **WebSearch** | Built-in keyword search | Quick factual lookups, official docs. Cannot access Reddit. | Always available |
| **GitHub CLI** | `gh search repos/issues/code` | Adoption signals, real-world problems, implementation examples | Always available |

### Extraction Tools (getting content from URLs)

**Follow this cascade — cheapest/fastest first:**

1. **WebFetch** (built-in, free) — Try first for any URL. Works for static pages, docs, blog posts. Use **targeted extraction prompts** (never "summarize this page"). 
2. **Tavily extract** (free tier) — Use when WebFetch returns garbage, incomplete, or truncated content. Handles more complex pages.
3. **Firecrawl scrape** (paid credits) — Reserve for pages that genuinely need it: JavaScript-rendered SPAs, pages behind cookie banners, structured data extraction with JSON schemas, complex layouts. Use `firecrawl_crawl` to spider an entire docs site when comprehensive coverage is needed.

**Firecrawl costs real money.** Only escalate to it when WebFetch and Tavily extract fail or when you specifically need JS rendering, browser interaction, or structured extraction.

### Tool Failure Modes (know before you search)

- **Firecrawl**: 0% success on social media (LinkedIn, Twitter, Instagram). 67% overall success rate. Anti-bot-protected sites frequently fail. Unpredictable credit consumption.
- **Exa**: Coverage gaps on long-tail/niche queries. Smaller index than Brave/Google. Pair with keyword search for completeness.
- **Brave**: Coverage gaps on niche technical topics. Best community content access of any tool (Reddit, HN).
- **Perplexity**: Hidden cost inflation — cited web page text is counted as input tokens (20x cost surprises reported). Structured output fragility. No free tier.
- **WebFetch**: Cannot render JavaScript. Fails on complex layouts, paywalls, SPAs.
- **WebSearch**: Cannot access Reddit. Keyword-only.

### When to use which search tool

- **"What do practitioners think about X?"** → Brave Search (Reddit/HN access)
- **"What's conceptually related to X?"** → Exa (semantic search)
- **"Quick factual answer"** → Tavily (fastest) or WebSearch
- **"Orient me on a new topic"** → Perplexity (pre-synthesized)
- **"Official docs for X"** → WebSearch with `allowed_domains`
- **"GitHub repos/issues for X"** → `gh search repos/issues/code`
- **"Full content of this URL"** → WebFetch → Tavily extract → Firecrawl (cascade)

## Search Technique Reference

**Domain targeting (WebSearch and Brave):**
- `allowed_domains: ["reddit.com", "news.ycombinator.com"]` — community signal (use Brave for Reddit — built-in WebSearch is blocked)
- `allowed_domains: ["github.com"]` — code-level evidence, issues, discussions
- `allowed_domains: ["arxiv.org"]` — academic papers
- `blocked_domains` — exclude content farms identified in initial results

**Recency:**
- Fast-moving topics (AI, frameworks, APIs): include the current year in at least one query
- Stable topics (algorithms, protocols): prioritize authoritative sources over recent ones

**WebFetch prompt engineering:**
- Bad: "Summarize this page"
- Good: "Extract the specific performance benchmarks, test methodology, and hardware specs"
- Good: "What are the criticisms and failure modes discussed? Include concrete examples and data points"
- Good: "List all pricing tiers, what's included in each, and any usage limits mentioned"
- Tailor each prompt to what *that specific source* likely has that others didn't provide

**PDF sources:**
- The Read tool supports PDFs via the `pages` parameter (max 20 pages per request)
- For long PDFs: read abstract/intro (pages 1-3) and conclusion first

**Source quality heuristic:**
- High Trust: official docs, peer-reviewed papers, framework maintainer blogs
- Medium Trust: engineering blogs, conference talks, established tech publications
- Low Trust: SEO content farms, affiliate pages, AI-generated content. Actively avoid these.

## Rules

- **Confirm depth first** — Propose depth + angles, wait for user confirmation, then execute
- **Agents write their own reports** — Each subagent writes its report directly. The orchestrator writes ONLY the SUMMARY.md synthesis.
- **Use today's actual date** for the filename, not a hardcoded date
- **Topic slug** in the folder name should be short kebab-case (e.g., `css-cascade-layers`, `static-site-generators`)
- **Extraction cascade** — WebFetch (free) → Tavily (free tier) → Firecrawl (paid). Never start with Firecrawl.
- **Be thorough** — This is a research tool, not a quick answer. Dig into multiple sources and synthesize.
- **Cite sources** — Every claim should be traceable to a source. Annotate sources with type and role.
- **Signal confidence** — Distinguish facts from consensus from contested claims from inferences
- **Flag contradictions** — When sources disagree, say so explicitly. Don't silently pick one version.
- **Source diversity** — Aim for 2-3+ different source types (official docs, blogs, community, GitHub, academic)
- **No silent consensus hallucination** — The synthesis must reflect what agents actually found, not what the orchestrator thinks should be true.
- **Project context matters** — Always include how findings relate to this project
- **Plain markdown** — No Obsidian-specific syntax (no frontmatter tags, wikilinks, or callout blocks)
