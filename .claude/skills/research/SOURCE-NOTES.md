# Source Notes — kit baseline

**Read-only.** This file ships with the kit and is shared by every project that
installs it. Do not append run findings here — they go in the project-local
`<research root>/SOURCE-NOTES.md`. See **Source notes** in `SKILL.md`.


Accumulated knowledge about **sources and retrieval** — not about any research topic. Every research run reads this before searching and appends to it afterward, so each pass is cheaper than the last.

**Read this first.** Most of it is a minute saved somewhere an earlier run lost twenty.

**Append, don't rewrite.** Entries stay until they're proven wrong. If a workaround stops working, edit it in place and date it rather than deleting — knowing that a route *used* to work is itself useful. Keep entries one line where possible.

---

## Blocked, broken, or unreliable

Sources that failed and how they failed. Knowing the failure mode saves the retry.

| Source | Failure | Do this instead |
|---|---|---|
| `eCFR.gov` | 302-redirects to an "unblock" gateway; unusable via WebFetch | Cornell LII (`law.cornell.edu`) mirrors the same text |
| `justia.com` | 403 to WebFetch | Tavily extract returns the raw text fine |
| CourtListener | Opinion API requires auth | The **search** API is open — use it to confirm citations and dockets |
| `leagle.com` | Paywalls after the first paragraph | Usually enough for a case caption and docket number; find the full text elsewhere |
| `govinfo.gov` | XML endpoints 404 | The direct PDF package URL works — construct it and use `pdftotext` |
| `theguardian.com` | Not directly fetchable | Mirrors worked |
| Social media (LinkedIn, X, Instagram) | Firecrawl ~0% success | Don't try; find the content quoted elsewhere |
| Image-heavy slide decks (conference PDFs) | WebFetch returns nothing useful | `pdftotext` via Bash recovers the text layer |

## Retrieval workarounds that worked

- **`pdftotext` via Bash** is the most reliable path for any PDF that extraction tools mangle — court opinions, regulatory filings, conference decks, standards documents. Convert, then grep or read.
- **Read tool PDF mode, page by page** works well for long structured documents when you know roughly where the answer sits.
- **Tavily extract is the workhorse rescue tier.** It has repeatedly recovered pages where WebFetch returned 403 or empty. Try it before ever reaching for Firecrawl.
- **Firecrawl has gone entirely unused in runs where the cascade was followed properly.** Treat "I need Firecrawl" as a signal to double-check that Tavily extract was actually tried.
- When a site blocks you, try the **institution that mirrors it** rather than a different search engine.

## Source types that punch above their weight

Non-obvious places where genuinely primary material is free and retrievable:

- **SEC EDGAR full-text search** — real executed contracts filed as exhibits, and professional-services opinions (legal, tax, valuation) filed as exhibits by the firms that wrote them. Correctly cited, current, and free. Almost nobody searches EDGAR for analysis rather than financials.
- **Regulator and standards-body sites** — model rules, comment letters, and issues papers are written without commercial interest, which makes them better than vendor or consultancy material on the same subject.
- **Trade-body and conference decks (PDF)** — associations often present their own proprietary data publicly in slides while gating the underlying report.
- **Litigation and enforcement records** — where otherwise-confidential commercial terms enter the public record.
- **Vendor documentation and published price pages** — for any claim about what something costs or does, the vendor's own current page beats every article about it.

## Content classes to distrust

- **Auto-generated SEO content dressed as industry research.** Tells: a very recent date in the title, "complete guide" or "everything you need to know" framing, confident aggregate statistics attributed to well-known research firms with no retrievable underlying report, and a domain that exists to sell an adjacent service. Multiple runs have independently wasted effort here.
- **Round, widely-repeated figures.** When a number appears identically across many secondary sources, that is evidence of copying, not of accuracy. Runs have found the primary source saying something materially different.
- **Any single confident source with mechanically precise detail and no verifiable citation.** The precision is the warning sign, not the reassurance.
- **Commercial formation/incorporation/comparison sites** — frequently wrong on the specifics they exist to explain.

## Blocklist

Pass to `blocked_domains` when a run is in a domain these pollute. Add as you find them.

*(none recorded yet — add entries as runs identify them)*

---

## Adding to source notes

Append to the **project-local** `<research root>/SOURCE-NOTES.md`, not to this
file. At the end of a run, record anything that would have saved time if you'd
known it at the start:

- A source that blocked you, and what worked instead
- A source type that turned out to be unexpectedly primary or unexpectedly good
- A content farm or auto-generated class that wasted searches
- A tool that solved something the others couldn't, and the shape of query it solved

Keep it about **sources and retrieval**. Topic findings belong in the research report and the brain DB, not here.
