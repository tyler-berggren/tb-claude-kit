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

**The scout's job is landscape and terminology — not substantive claims.** Use it to learn what the concepts are called, who the players are, and where the boundaries of the topic sit. Do not treat its specific assertions as findings.

**Validate before you use it.** Pre-synthesized answer tools sometimes return a confident, internally consistent answer whose citations do not support it — the model answering from training data and presenting it in cited form. Before writing any agent prompt, spot-check **two or three of the scout's citations against the claims they supposedly support**:

- If they check out, proceed and use the scout to refine the angles from Step 3.
- If they do not, **discard the scout entirely.** Keep the file for the record, but open it with a prominent provenance warning and do not carry its claims into agent prompts.

A wrong hypothesis is worse than no hypothesis — it anchors agents and costs them effort to unwind. If you do pass scout claims forward, label them explicitly as unverified hypotheses to check, never as background fact.

### Step 5 — Plan the research angles

Decompose the topic into 3-5 distinct research angles. Each angle is a specific *question to answer*, not a tool to use. Angles should be orthogonal — designed to surface different perspectives, not variations of the same query. Common dimensions:

- **Mechanism/theory** — How does it work? What are the fundamentals?
- **Practical usage** — Who uses it, how, and why? Real-world examples and case studies.
- **Community experience** — What do practitioners report? Reddit, HN, blog posts. What actually works vs what sounds good?
- **Failure modes/limitations** — What goes wrong? What are the criticisms and tradeoffs?
- **Alternatives/comparisons** — What else exists? How do options compare?
- **Recent developments** — What changed recently? What's the current state?

**If the user drops an angle**, note it in the remaining agents' prompts as *"out of scope for this run, but flag it prominently if it surfaces in your search."* Descoped questions have a habit of turning out to matter, and the agent already reading the sources is the cheapest place to catch that.

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
{What tools were used, what queries were run, what failed and how you worked around it}

## Key Findings
{Numbered findings with confidence signals: HIGH/MEDIUM/LOW}

## Detailed Analysis
{Deeper analysis organized by subtopic}

## What I Could NOT Verify
{Required. See the anti-fabrication contract below.}

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
- Read `SOURCE-NOTES.md` in this skill's directory first, and report anything new worth adding to it

**Include this anti-fabrication contract verbatim in every agent prompt.** It is the single highest-value addition to an agent's instructions — it reliably catches invented citations, misremembered figures, and numbers that secondary sources have quietly corrupted:

> **ANTI-FABRICATION RULE.** Every specific claim you report — a figure, a quote, a name, a date, a technical detail — must come from a source you actually retrieved this session, and you must give its URL. Do NOT reconstruct facts, quotes, or numbers from memory, and do not restate a claim you only saw summarized somewhere else without going to the original. If you cannot verify something, say so explicitly rather than omitting it or softening it into a hedge. **Absence of evidence is itself a reportable finding** — "I searched for X specifically and found nothing" is valuable output. Include a required **"What I Could NOT Verify"** section listing: claims you could not confirm, sources you could not retrieve and why, and anything you found only on low-quality or apparently auto-generated pages. Where a widely-repeated number conflicts with the primary source, report both and say which governs.

Where accuracy is load-bearing, also tell agents to prefer the **primary artifact** over any secondary description of it — the actual spec, filing, dataset, opinion, or release notes rather than an article about it. Secondary sources are for finding primaries, not for quoting.

For quick lookups, a single agent or direct search is sufficient — skip the parallel spawn, but still save findings to the run folder.

### Step 7 — Iterative deepening

After all agents complete, read their reports and identify:

- **New terms, projects, or concepts** that appeared in sources but weren't in the original angles. Search for the 1-3 most important ones.
- **Gaps**: Which key questions remain unanswered? Are any perspectives missing? Are quantitative claims unsupported?
- **Contradictions**: Where do agents' findings disagree? Do targeted searches to understand why.

If significant gaps remain, spawn 1-2 focused follow-up agents. One good source that fills a gap is worth more than three more sources confirming what you already know.

### Step 8 — Conduct project research

Search the codebase and project files for anything relevant to the topic — existing code, configs, docs, patterns, prior decisions. Query `cowork/brain/BRAIN.db` for related decisions and insights. This grounds the report in the project's actual state.

**Also check whether the findings CONTRADICT anything already recorded.** Search the brain for entries the research touches:

```sql
SELECT id, type, title, substr(body,1,300) FROM logs
WHERE status='active' AND (title LIKE '%<keyword>%' OR body LIKE '%<keyword>%');
```

If a finding overturns a prior decision or insight, say so in the report's "Project Relevance" section and supersede the old entry in Step 10. A research system that cannot correct its own earlier conclusions accumulates errors — and prior entries are exactly what future sessions will read and trust.

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

**Supersede anything the research overturned** (from Step 8). Do not edit the old entry — write a new one that replaces it, so the change of mind stays visible:

```sql
INSERT INTO logs (type, title, body, tags, supersedes)
VALUES ('insight', 'CORRECTION to #<old>: <what changed>', '<what the old entry claimed, what the research found, and why>', 'research', <old_id>);
UPDATE logs SET superseded_by = last_insert_rowid(), status = 'superseded' WHERE id = <old_id>;
```

### Step 11 — Report back

Report back with the file path and a 2-3 sentence summary of what was found.

If findings are significant enough to inform future project decisions, also add a brain entry via:
```sql
INSERT INTO logs (type, title, body, tags, importance)
VALUES ('insight', '<title>', '<key finding summary>', 'research', <importance>);
```

**Update `SOURCE-NOTES.md`** in this skill's directory with anything the run learned about the tools themselves — sources that blocked or failed, workarounds that got past them, source types that proved unexpectedly high-value, and any content farms worth blocking next time. This file is append-only across runs and is what makes each research pass cheaper than the last.

---

## Tool Stack

Every research agent has access to the full tool stack. Tools are listed in order of preference for each capability.

### Search Tools (discovery)

| Tool | What It Does | Best For | Load With |
|---|---|---|---|
| **Brave Search** | Keyword search with independent 30B+ page index | Reddit, HN, forums, community content, news. Default for most keyword queries. | `ToolSearch("select:mcp__brave-search__brave_web_search")` |
| **Exa** | Neural/semantic search | Conceptual queries, finding related work, "how do people think about X", discovering content keywords miss. 60% pass rate on semantic queries vs 38% for keyword search. **Reach for it after 2-3 empty keyword queries, not at the end** — it finds things keyword search structurally cannot. | `ToolSearch("+exa")` |
| **Tavily** | Agent-native keyword search, 187ms avg latency | Fast factual lookups, clean agent-ready responses. Use when you need speed or Brave is unavailable. | `ToolSearch("+tavily")` |
| **Perplexity** | Pre-synthesized answers with citations | Landscape/terminology orientation only. **Validate its citations before using anything it says** — see Step 4. Not a source of findings. Too slow (1.4s+) for tight loops. | `ToolSearch("+perplexity")` |
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
- **Perplexity**: Hidden cost inflation — cited web page text is counted as input tokens (20x cost surprises reported). Structured output fragility. No free tier. **Observed failure mode: returns a confident, internally consistent answer with a citation list that does not support any of its claims.** Always spot-check citations against claims.
- **WebFetch**: Cannot render JavaScript. Fails on complex layouts, paywalls, SPAs.
- **WebSearch**: Cannot access Reddit. Keyword-only.

### Four modes — pick the mode first, then the tool

Most tool-selection mistakes come from treating every query as "search." These are four different jobs:

**1. DISCOVERY — you don't know what exists.**
- Conceptual: *"has anyone solved a problem shaped like this?"* → **Exa**. Keyword search structurally cannot answer questions where you don't know the name of the thing. Reach for Exa **as soon as two or three keyword queries come back empty** — not as a last resort. In practice this is where the highest-value finds come from, and it is the most commonly skipped tool in the stack.
- Practitioner reality: *"what do people who actually do this say?"* → **Brave** (best Reddit/HN/forum access).
- Landscape orientation: → **Perplexity**, with the Step 4 caveats.

**2. TARGETED RETRIEVAL — you know what you want and roughly where it lives.**
- → **WebSearch or Brave with `allowed_domains`** scoped to the authoritative domain, or a direct URL + **WebFetch**.
- → **`gh search repos/issues/code`** for code-level evidence.

**3. RESCUE — something blocked you.**
- Cascade: **WebFetch → Tavily extract → Firecrawl**. Tavily extract is the workhorse here; it gets past a large share of 403s, empty returns, and awkward PDFs, and it is free-tier.
- For PDFs that extract badly: `pdftotext` via Bash, or the Read tool's PDF mode page by page. Authoritative material (specs, filings, standards, papers, government documents) is disproportionately PDF-first, and search tools handle it worst.
- Check `SOURCE-NOTES.md` before improvising — the workaround may already be recorded.

**4. VERIFICATION — you have a claim and need to know if it's true.**
- → **Fetch the primary artifact directly.** Never verify a claim against another secondary source; that is how a corrupted figure propagates.
- Widely-repeated numbers are the highest-risk category. When a round, oft-quoted figure and a primary source disagree, the primary governs and both belong in the report.
- This mode is what makes the anti-fabrication contract enforceable rather than aspirational.

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
- **Extraction cascade** — WebFetch (free) → Tavily (free tier) → Firecrawl (paid). Never start with Firecrawl. State this in agent prompts; agents left to themselves sometimes invert it and burn paid credits on work the free tier handles.
- **Anti-fabrication contract in every agent prompt** — verbatim, per Step 6. Retrieved URLs for every specific claim, a required "What I Could NOT Verify" section, no reconstruction from memory, and absence of evidence reported as a finding.
- **Verify against primaries** — Never confirm a claim using a second secondary source. Go to the artifact.
- **Be thorough** — This is a research tool, not a quick answer. Dig into multiple sources and synthesize.
- **Cite sources** — Every claim should be traceable to a source. Annotate sources with type and role.
- **Signal confidence** — Distinguish facts from consensus from contested claims from inferences
- **Flag contradictions** — When sources disagree, say so explicitly. Don't silently pick one version.
- **Source diversity** — Aim for 2-3+ different source types (official docs, blogs, community, GitHub, academic)
- **No silent consensus hallucination** — The synthesis must reflect what agents actually found, not what the orchestrator thinks should be true.
- **Project context matters** — Always include how findings relate to this project
- **Plain markdown** — No Obsidian-specific syntax (no frontmatter tags, wikilinks, or callout blocks)
