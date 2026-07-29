#!/usr/bin/env python3
"""
SEO/AEO asset scanner for static sites.

Detection only — this script never writes to the site. It emits JSON findings
that the /web skill reads and acts on, because inserting a meta tag idiomatically
depends on each project's formatting and that judgment belongs to Claude, not to
a regex in here.

Stdlib only: no pip installs, no node_modules, runs anywhere python3 does.

Usage:
  scan.py [--root DIR] [--base-url URL] [--live] [--json]

Exit codes: 0 clean or warnings only, 1 critical findings, 2 could not scan.
"""

import argparse
import difflib
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path

# Directories that commonly hold built static output, most specific first.
ROOT_GUESSES = ["web", "public", "dist", "site", "build", "_site", "out", "sitemd/site"]

VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input",
             "link", "meta", "param", "source", "track", "wbr"}

# Text-bearing tags whose content is not page copy.
SKIP_TEXT = {"script", "style", "template", "noscript", "svg"}


class Page(HTMLParser):
    """Collects the handful of things an SEO/AEO audit cares about."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang = None
        self.title = None
        self.metas = []          # list of (name_or_property, content)
        self.links = []          # list of dict(rel, href, type, sizes)
        self.headings = []       # list of (level, text, line)
        self.images = []         # list of dict(src, alt, line)
        self.ldjson = []         # list of (raw, line)
        self.details = []        # list of dict(summary, body) — FAQ accordions
        self._stack = []
        self._buf = []
        self._title_open = False
        self._ld_open = False
        self._heading_open = False
        self._heading_level = 0
        self._heading_line = 0
        self._ld_line = 0
        self._detail = None
        self._summary_open = False
        self.text_parts = []
        self._in_main = False
        self.has_main = False

    # -- helpers ---------------------------------------------------------
    def _attr(self, attrs, key):
        for k, v in attrs:
            if k.lower() == key:
                return v
        return None

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        line = self.getpos()[0]
        if tag not in VOID_TAGS:
            self._stack.append(tag)

        if tag == "html":
            self.lang = self._attr(attrs, "lang")
        elif tag == "title":
            self._title_open = True
            self._buf = []
        elif tag == "meta":
            key = self._attr(attrs, "name") or self._attr(attrs, "property")
            self.metas.append((key.lower() if key else None,
                               self._attr(attrs, "content")))
        elif tag == "link":
            self.links.append({
                "rel": (self._attr(attrs, "rel") or "").lower(),
                "href": self._attr(attrs, "href"),
                "type": (self._attr(attrs, "type") or "").lower(),
                "sizes": self._attr(attrs, "sizes"),
            })
        elif tag == "script":
            if (self._attr(attrs, "type") or "").lower() == "application/ld+json":
                self._ld_open = True
                self._ld_line = line
                self._buf = []
        elif re.fullmatch(r"h[1-6]", tag):
            self._buf = []
            self._heading_open = True
            self._heading_level = int(tag[1])
            self._heading_line = line
        elif tag == "img":
            self.images.append({"src": self._attr(attrs, "src"),
                                "alt": self._attr(attrs, "alt"),
                                "line": line})
        elif tag == "main":
            self._in_main = True
            self.has_main = True
        elif tag == "details":
            self._detail = {"summary": "", "body": []}
        elif tag == "summary":
            self._summary_open = True
            self._buf = []

    def handle_endtag(self, tag):
        tag = tag.lower()
        if self._stack and tag in self._stack:
            while self._stack and self._stack.pop() != tag:
                pass

        text = "".join(self._buf).strip()
        if tag == "title" and self._title_open:
            self.title = re.sub(r"\s+", " ", text)
            self._title_open = False
            self._buf = []
        elif tag == "script" and self._ld_open:
            self.ldjson.append((text, self._ld_line))
            self._ld_open = False
            self._buf = []
        elif re.fullmatch(r"h[1-6]", tag):
            self.headings.append((self._heading_level,
                                  re.sub(r"\s+", " ", text),
                                  self._heading_line))
            self._heading_open = False
            self._buf = []
        elif tag == "summary" and self._summary_open:
            if self._detail is not None:
                self._detail["summary"] = re.sub(r"\s+", " ", text)
            self._summary_open = False
            self._buf = []
        elif tag == "details" and self._detail is not None:
            self._detail["body"] = re.sub(r"\s+", " ", " ".join(self._detail["body"])).strip()
            self.details.append(self._detail)
            self._detail = None
        elif tag == "main":
            self._in_main = False

    def handle_data(self, data):
        if self._title_open or self._ld_open or self._summary_open:
            self._buf.append(data)
            return
        if self._heading_open:
            # Anywhere inside the heading, so nested <em>/<span>/<a> text is kept.
            self._buf.append(data)
        if any(t in SKIP_TEXT for t in self._stack):
            return
        if self._detail is not None and not self._summary_open:
            self._detail["body"].append(data)
        if data.strip():
            self.text_parts.append(data)

    # -- derived ---------------------------------------------------------
    def meta(self, key):
        for k, v in self.metas:
            if k == key:
                return v
        return None

    def link(self, rel, type_=None):
        for l in self.links:
            if rel in l["rel"].split() and (type_ is None or l["type"] == type_):
                return l
        return None

    def body_text(self):
        return re.sub(r"\s+", " ", " ".join(self.text_parts)).strip()


class Scanner:
    def __init__(self, root: Path, base_url: str, project: Path, ignore=None):
        self.root = root
        self.base_url = (base_url or "").rstrip("/")
        self.project = project
        self.findings = []
        self.suppressed = []
        self.ignore = ignore or []
        self.pages = {}          # rel_url -> (path, Page)
        self.notes = []

    def _suppressed_by(self, finding):
        """Return the matching ignore rule, or None.

        A rule needs `check`; `file` and `match` narrow it further. Deliberately
        conservative — a bare check name silences that check everywhere, so rules
        should usually name a file too.
        """
        for rule in self.ignore:
            if not isinstance(rule, dict):
                rule = {"check": str(rule)}
            if rule.get("check") and rule["check"] != finding["check"]:
                continue
            if rule.get("file") and rule["file"] != (finding.get("file") or ""):
                continue
            if rule.get("match") and rule["match"] not in (finding.get("message") or ""):
                continue
            return rule
        return None

    def add(self, severity, check, message, file=None, line=None,
            fix="manual", detail=None):
        finding = {
            "severity": severity, "check": check, "message": message,
            "file": file, "line": line, "fix": fix, "detail": detail,
        }
        rule = self._suppressed_by(finding)
        if rule:
            # Kept and counted, never silently dropped.
            finding["suppressedBy"] = rule.get("note") or "web.ignore"
            self.suppressed.append(finding)
            return
        self.findings.append(finding)

    # -- discovery -------------------------------------------------------
    def html_files(self):
        out = []
        for p in sorted(self.root.rglob("*.html")):
            if any(part.startswith(".") or part in ("node_modules",) for part in p.parts):
                continue
            out.append(p)
        return out

    def rel_url(self, path: Path):
        rel = path.relative_to(self.root).as_posix()
        if rel == "index.html":
            return "/"
        if rel.endswith("/index.html"):
            return "/" + rel[: -len("index.html")]
        return "/" + rel

    def load_pages(self):
        for path in self.html_files():
            raw = path.read_text(encoding="utf-8", errors="replace")
            pg = Page()
            try:
                pg.feed(raw)
            except Exception as e:
                self.add("critical", "html-parse", f"HTML failed to parse: {e}",
                         file=str(path.relative_to(self.project)))
                continue
            pg.raw = raw
            self.pages[self.rel_url(path)] = (path, pg)

    def is_indexable(self, pg):
        robots = (pg.meta("robots") or "").lower()
        return "noindex" not in robots

    # -- per-page checks -------------------------------------------------
    def check_page(self, url, path, pg):
        f = str(path.relative_to(self.project))
        indexable = self.is_indexable(pg)

        if not pg.lang:
            self.add("warning", "lang", "<html> has no lang attribute", file=f, fix="auto")

        if not pg.title:
            self.add("critical", "title", "No <title>", file=f, fix="manual")
        elif not (10 <= len(pg.title) <= 65):
            self.add("info", "title-length",
                     f"Title is {len(pg.title)} chars (aim 10–65 so it is not truncated)",
                     file=f, fix="manual", detail=pg.title)

        desc = pg.meta("description")
        if not desc and indexable:
            self.add("critical", "description", "No meta description", file=f, fix="manual")
        elif desc and not (50 <= len(desc) <= 165):
            self.add("info", "description-length",
                     f"Meta description is {len(desc)} chars (aim 50–165)",
                     file=f, fix="manual", detail=desc)

        if not pg.meta("viewport"):
            self.add("warning", "viewport", "No viewport meta", file=f, fix="auto")

        canon = pg.link("canonical")
        if not canon:
            if indexable:
                self.add("warning", "canonical", "No canonical link", file=f, fix="auto")
        else:
            href = canon["href"] or ""
            if not href.startswith("http"):
                self.add("warning", "canonical-relative",
                         f"Canonical is relative ({href}); use an absolute URL",
                         file=f, fix="auto")
            elif self.base_url and not href.startswith(self.base_url):
                self.add("warning", "canonical-host",
                         f"Canonical {href} does not match base URL {self.base_url}",
                         file=f, fix="auto")
            elif self.base_url:
                expected = self.base_url + url
                if href.rstrip("/") != expected.rstrip("/"):
                    self.add("warning", "canonical-mismatch",
                             f"Canonical is {href}, page resolves to {expected}",
                             file=f, fix="auto")

        if indexable:
            robots = (pg.meta("robots") or "")
            if "max-snippet" not in robots:
                self.add("warning", "snippet-directives",
                         "No max-snippet/max-image-preview directives — search and answer "
                         "engines will cap how much of this page they can quote",
                         file=f, fix="auto")

        # Open Graph. A noindex page (404, thank-you, staging) is not a share
        # target, so absent cards there are correct, not a gap.
        if indexable:
            og_required = {
                "og:title": "critical", "og:description": "warning", "og:url": "warning",
                "og:type": "warning", "og:image": "warning", "og:site_name": "info",
            }
            for key, sev in og_required.items():
                if not pg.meta(key):
                    self.add(sev, "open-graph", f"Missing {key}", file=f, fix="auto")
            img = pg.meta("og:image")
            if img and not img.startswith("http"):
                self.add("warning", "og-image-relative",
                         f"og:image must be an absolute URL (found {img})", file=f, fix="auto")
            if img and not pg.meta("og:image:alt"):
                self.add("info", "og-image-alt", "og:image has no og:image:alt",
                         file=f, fix="auto")
            if not pg.meta("twitter:card"):
                self.add("info", "twitter-card", "No twitter:card", file=f, fix="auto")

        # Icons
        if not pg.link("icon"):
            self.add("warning", "favicon", "No favicon link", file=f, fix="auto")
        else:
            svg_only = all(l["type"] == "image/svg+xml"
                           for l in pg.links if "icon" in l["rel"].split())
            if svg_only:
                self.add("info", "favicon-raster",
                         "Only an SVG favicon — add a PNG fallback for clients that skip SVG",
                         file=f, fix="manual")
        if not pg.link("apple-touch-icon"):
            self.add("info", "apple-touch-icon", "No apple-touch-icon", file=f, fix="auto")

        # Headings
        h1s = [h for h in pg.headings if h[0] == 1]
        if not h1s:
            self.add("warning", "h1-missing", "No <h1>", file=f, fix="manual")
        elif len(h1s) > 1:
            self.add("info", "h1-multiple", f"{len(h1s)} <h1> elements", file=f, fix="manual")
        prev = 0
        for level, text, line in pg.headings:
            if prev and level > prev + 1:
                self.add("info", "heading-skip",
                         f"Heading jumps h{prev} → h{level} ({text[:50]!r})",
                         file=f, line=line, fix="manual")
            prev = level

        # Images
        for im in pg.images:
            if im["alt"] is None:
                self.add("warning", "img-alt",
                         f"<img> has no alt attribute ({(im['src'] or '?')[:60]})",
                         file=f, line=im["line"], fix="manual")

        # Structured data
        if not pg.ldjson and indexable:
            self.add("warning", "no-structured-data",
                     "No JSON-LD on an indexable page", file=f, fix="manual")
        for raw, line in pg.ldjson:
            try:
                data = json.loads(raw)
            except Exception as e:
                self.add("critical", "ldjson-parse",
                         f"JSON-LD does not parse: {e}", file=f, line=line, fix="manual")
                continue
            nodes = data.get("@graph", [data]) if isinstance(data, dict) else data
            if not isinstance(nodes, list):
                nodes = [nodes]
            declared = {n.get("@id") for n in nodes if isinstance(n, dict) and n.get("@id")}
            # Nested @ids count as declared too.
            declared |= set(re.findall(r'"@id":\s*"([^"]+)"', raw))
            refs = set()
            def walk(o):
                if isinstance(o, dict):
                    if set(o.keys()) == {"@id"}:
                        refs.add(o["@id"])
                    for v in o.values():
                        walk(v)
                elif isinstance(o, list):
                    for v in o:
                        walk(v)
            walk(nodes)
            for r in sorted(refs - declared):
                # Cross-page references to the site's own entities are normal.
                if self.base_url and r.startswith(self.base_url):
                    continue
                self.add("warning", "ldjson-dangling-ref",
                         f"JSON-LD references {r} which is not defined anywhere",
                         file=f, line=line, fix="manual")
            pg.ld_nodes = nodes

    # -- site-level assets -----------------------------------------------
    def check_robots(self):
        p = self.root / "robots.txt"
        if not p.exists():
            self.add("critical", "robots-missing", "No robots.txt",
                     file=str(p.relative_to(self.project)), fix="auto")
            return
        txt = p.read_text(encoding="utf-8", errors="replace")
        f = str(p.relative_to(self.project))
        if not re.search(r"(?im)^\s*sitemap:", txt):
            self.add("warning", "robots-no-sitemap",
                     "robots.txt does not point at a sitemap", file=f, fix="auto")
        if re.search(r"(?im)^\s*disallow:\s*/\s*$", txt):
            self.add("critical", "robots-disallow-all",
                     "robots.txt contains 'Disallow: /' — the site is blocked", file=f, fix="manual")
        if not re.search(r"(?i)llms\.txt", txt) and (self.root / "llms.txt").exists():
            self.add("info", "robots-no-llms",
                     "llms.txt exists but robots.txt does not mention it", file=f, fix="auto")

    def check_sitemap(self):
        p = self.root / "sitemap.xml"
        f = str(p.relative_to(self.project))
        if not p.exists():
            self.add("critical", "sitemap-missing", "No sitemap.xml", file=f, fix="auto")
            return
        try:
            tree = ET.parse(p)
        except Exception as e:
            self.add("critical", "sitemap-invalid", f"sitemap.xml is not valid XML: {e}",
                     file=f, fix="manual")
            return
        ns = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
        entries = {}
        for url in tree.getroot().findall("s:url", ns):
            loc = url.findtext("s:loc", default="", namespaces=ns).strip()
            lastmod = url.findtext("s:lastmod", default=None, namespaces=ns)
            entries[loc] = lastmod

        listed = set()
        for loc in entries:
            if self.base_url and loc.startswith(self.base_url):
                listed.add(loc[len(self.base_url):] or "/")
            else:
                listed.add(loc)

        indexable = {u for u, (pth, pg) in self.pages.items() if self.is_indexable(pg)}
        for missing in sorted(indexable - listed):
            self.add("critical", "sitemap-missing-page",
                     f"{missing} is indexable but not in sitemap.xml", file=f, fix="auto")
        for orphan in sorted(listed - set(self.pages.keys())):
            self.add("warning", "sitemap-orphan",
                     f"sitemap lists {orphan} but no such page exists", file=f, fix="auto")
        for u, (pth, pg) in self.pages.items():
            if u in listed and not self.is_indexable(pg):
                self.add("warning", "sitemap-noindex",
                         f"{u} is in sitemap.xml but marked noindex", file=f, fix="auto")

        for loc, lastmod in entries.items():
            path_url = loc[len(self.base_url):] if self.base_url and loc.startswith(self.base_url) else loc
            path_url = path_url or "/"
            if not lastmod:
                self.add("warning", "sitemap-no-lastmod",
                         f"{path_url} has no <lastmod>", file=f, fix="auto")
                continue
            entry = self.pages.get(path_url)
            if not entry:
                continue
            src_date = self.last_modified(entry[0])
            if src_date and lastmod[:10] < src_date:
                self.add("critical", "sitemap-stale-lastmod",
                         f"{path_url} lastmod is {lastmod[:10]} but the page changed {src_date}",
                         file=f, fix="auto")

    def last_modified(self, path: Path):
        """Git commit date if tracked and clean, else filesystem mtime."""
        try:
            r = subprocess.run(
                ["git", "-C", str(self.project), "log", "-1", "--format=%ad",
                 "--date=short", "--", str(path.relative_to(self.project))],
                capture_output=True, text=True, timeout=10)
            dirty = subprocess.run(
                ["git", "-C", str(self.project), "status", "--porcelain", "--",
                 str(path.relative_to(self.project))],
                capture_output=True, text=True, timeout=10)
            if dirty.stdout.strip() or not r.stdout.strip():
                import datetime
                return datetime.date.fromtimestamp(path.stat().st_mtime).isoformat()
            return r.stdout.strip()
        except Exception:
            return None

    def check_llms(self):
        llms = self.root / "llms.txt"
        if not llms.exists():
            self.add("warning", "llms-txt-missing",
                     "No llms.txt — no curated entry point for LLM consumers",
                     file=str((self.root / "llms.txt").relative_to(self.project)), fix="manual")
            return
        txt = llms.read_text(encoding="utf-8", errors="replace")
        f = str(llms.relative_to(self.project))
        if not txt.lstrip().startswith("#"):
            self.add("warning", "llms-txt-format",
                     "llms.txt should open with an H1 title per the llmstxt.org format",
                     file=f, fix="manual")
        if not re.search(r"^\s*>", txt, re.M):
            self.add("info", "llms-txt-summary",
                     "llms.txt has no '>' blockquote summary line", file=f, fix="manual")
        # Every link in llms.txt should resolve to something on disk.
        for label, href in re.findall(r"\[([^\]]+)\]\(([^)]+)\)", txt):
            if href.startswith("mailto:"):
                continue
            if self.base_url and href.startswith(self.base_url):
                rel = href[len(self.base_url):]
            elif href.startswith("/"):
                rel = href
            else:
                continue
            target = self.root / rel.lstrip("/")
            if rel.endswith("/"):
                target = target / "index.html"
            if not target.exists():
                self.add("critical", "llms-txt-dead-link",
                         f"llms.txt links to {href} which does not exist on disk",
                         file=f, fix="manual")

    def check_headers(self):
        p = self.root / "_headers"
        if not p.exists():
            return
        txt = p.read_text(encoding="utf-8", errors="replace")
        f = str(p.relative_to(self.project))
        nosniff = re.search(r"(?i)X-Content-Type-Options:\s*nosniff", txt)
        if not nosniff:
            return
        # With nosniff on, assets served without an explicit type download instead
        # of rendering. Only .md needs the rule — .txt and .xml map to sane types
        # on every host, .md is the extension that gets served as octet-stream.
        for asset in sorted(self.root.glob("*.md")):
            name = "/" + asset.name
            block = re.search(re.escape(name) + r"\s*\n((?:\s+\S.*\n)+)", txt)
            if not block or not re.search(r"(?i)content-type:", block.group(1)):
                self.add("warning", "headers-content-type",
                         f"{name} has no Content-Type in _headers, but nosniff is set — "
                         f"it will download instead of render",
                         file=f, fix="auto")

    # -- currency / drift -------------------------------------------------
    def check_mirrors(self):
        """Markdown mirrors must still match the HTML they mirror."""
        for url, (path, pg) in sorted(self.pages.items()):
            alt = pg.link("alternate", "text/markdown")
            if not alt:
                continue
            href = alt["href"] or ""
            mirror = self.root / href.lstrip("/")
            f = str(path.relative_to(self.project))
            if not mirror.exists():
                self.add("critical", "mirror-missing",
                         f"{url} declares a markdown mirror at {href} which does not exist",
                         file=f, fix="manual")
                continue

            md = mirror.read_text(encoding="utf-8", errors="replace")
            md = re.sub(r"(?s)^<!--.*?-->", "", md)
            md_flat = " ".join(self._words(re.sub(r"[#*_`>\[\]()!-]", " ", md)))
            md_words = md_flat.split()
            html_words = self._words(pg.body_text())
            if not html_words:
                continue
            mf = str(mirror.relative_to(self.project))

            # Precise signal: every heading rendered on the page should appear in
            # the mirror. Catches "added a section, forgot the mirror" exactly,
            # which a whole-document ratio is too coarse to see.
            for level, text, line in pg.headings:
                if level > 3 or not text.strip():
                    continue
                key = " ".join(self._words(text))
                if key and key not in md_flat:
                    # Warning, not critical: a mirror may legitimately reword a
                    # heading for machine readers. Missing *content* is the real
                    # failure, and the ratio check below catches that.
                    self.add("warning", "mirror-missing-section",
                             f"{href} does not contain the {url} heading {text!r}",
                             file=mf, fix="manual")

            # Coarse signal: overall divergence. A healthy mirror sits high; the
            # mirror legitimately carries extra front-matter lines the HTML lacks,
            # so this is deliberately loose and only backs up the heading check.
            ratio = difflib.SequenceMatcher(None, html_words, md_words).quick_ratio()
            missing = [w for w in set(html_words) - set(md_words) if len(w) > 6][:12]
            detail = ("In the page but not the mirror: " + ", ".join(sorted(missing))) if missing else None
            if ratio < 0.75:
                self.add("critical", "mirror-drift",
                         f"{href} has drifted badly from {url} (similarity {ratio:.0%})",
                         file=mf, fix="manual", detail=detail)
            elif ratio < 0.85:
                self.add("warning", "mirror-drift",
                         f"{href} may have drifted from {url} (similarity {ratio:.0%})",
                         file=mf, fix="manual", detail=detail)

        full = self.root / "llms-full.txt"
        if full.exists():
            corpus = full.read_text(encoding="utf-8", errors="replace")
            for url, (path, pg) in sorted(self.pages.items()):
                alt = pg.link("alternate", "text/markdown")
                if not alt:
                    continue
                mirror = self.root / (alt["href"] or "").lstrip("/")
                if not mirror.exists():
                    continue
                body = re.sub(r"(?s)^<!--.*?-->", "", mirror.read_text(encoding="utf-8", errors="replace")).strip()
                head = "\n".join(body.splitlines()[:6]).strip()
                if head and head not in corpus:
                    self.add("warning", "llms-full-stale",
                             f"llms-full.txt does not contain the current {mirror.name} — regenerate it",
                             file=str(full.relative_to(self.project)), fix="auto")
                    break

    def _words(self, s):
        return re.findall(r"[a-z0-9$,.]+", s.lower())

    def check_schema_vs_dom(self):
        """Structured data must not contradict what the page actually says."""
        for url, (path, pg) in sorted(self.pages.items()):
            f = str(path.relative_to(self.project))
            nodes = getattr(pg, "ld_nodes", [])
            body = pg.body_text()

            for n in nodes:
                if not isinstance(n, dict):
                    continue
                if n.get("@type") == "FAQPage":
                    qs = n.get("mainEntity") or []
                    if pg.details and len(qs) != len(pg.details):
                        self.add("critical", "faq-count-mismatch",
                                 f"FAQPage schema has {len(qs)} questions but the page renders "
                                 f"{len(pg.details)}",
                                 file=f, fix="manual")
                    dom_summaries = {d["summary"].strip().lower() for d in pg.details}
                    for q in qs:
                        if not isinstance(q, dict):
                            continue
                        name = (q.get("name") or "").strip().lower()
                        if dom_summaries and name and name not in dom_summaries:
                            self.add("critical", "faq-question-mismatch",
                                     f"FAQPage question {q.get('name')!r} is not on the page",
                                     file=f, fix="manual")
                        ans = ((q.get("acceptedAnswer") or {}).get("text") or "")
                        if ans:
                            key = " ".join(self._words(ans)[:8])
                            if key and key not in " ".join(self._words(body)):
                                self.add("warning", "faq-answer-drift",
                                         f"FAQPage answer for {q.get('name')!r} does not match "
                                         f"the page copy",
                                         file=f, fix="manual")

            # Prices asserted in schema should appear in the visible copy.
            prices = set()
            def find_prices(o):
                if isinstance(o, dict):
                    for k, v in o.items():
                        if k in ("price", "minPrice", "maxPrice") and isinstance(v, (str, int, float)):
                            prices.add(str(v))
                        else:
                            find_prices(v)
                elif isinstance(o, list):
                    for v in o:
                        find_prices(v)
            find_prices(nodes)
            body_nums = set(re.sub(r"[,\s]", "", n) for n in re.findall(r"\$[\d,]+", body))
            for p in sorted(prices):
                if not body_nums:
                    continue
                if ("$" + p) not in body_nums and ("$" + p + ".00") not in body_nums:
                    self.add("warning", "schema-price-mismatch",
                             f"Structured data claims price {p} but that figure does not appear "
                             f"in the page copy",
                             file=f, fix="manual")

    # -- live probe -------------------------------------------------------
    def check_live(self):
        import urllib.request
        import urllib.error
        if not self.base_url:
            self.add("warning", "live-no-base-url",
                     "--live needs a base URL; set web.baseUrl in .claude/kit.json", fix="manual")
            return
        targets = sorted(self.pages.keys())
        for extra in ("robots.txt", "sitemap.xml", "llms.txt", "llms-full.txt"):
            if (self.root / extra).exists():
                targets.append("/" + extra)
        for asset in sorted(self.root.glob("*.md")):
            targets.append("/" + asset.name)

        for t in targets:
            url = self.base_url + t
            req = urllib.request.Request(url, method="GET",
                                         headers={"User-Agent": "tb-claude-kit-web-scan/1"})
            try:
                with urllib.request.urlopen(req, timeout=15) as r:
                    status = r.status
                    ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip()
                    link = r.headers.get("Link") or ""
                    final = r.url
            except urllib.error.HTTPError as e:
                self.add("critical", "live-status",
                         f"{url} returned HTTP {e.code}", fix="manual")
                continue
            except Exception as e:
                self.add("warning", "live-unreachable", f"{url} could not be fetched: {e}",
                         fix="manual")
                continue

            expected = {".md": "text/markdown", ".txt": "text/plain",
                        ".xml": ("application/xml", "text/xml")}
            ext = os.path.splitext(t)[1]
            if ext in expected:
                want = expected[ext]
                want = (want,) if isinstance(want, str) else want
                if ctype not in want:
                    self.add("critical", "live-content-type",
                             f"{url} is served as {ctype or 'no type'}, expected {want[0]} — "
                             f"deploy headers are not applying",
                             fix="manual")
            if ext == ".md" and "canonical" not in link:
                self.add("warning", "live-mirror-canonical",
                         f"{url} has no canonical Link header — it can compete with the HTML page "
                         f"in search",
                         fix="manual")
            if final.rstrip("/") != url.rstrip("/"):
                self.add("info", "live-redirect",
                         f"{url} redirected to {final}", fix="manual")

    # -- run --------------------------------------------------------------
    def run(self, live=False):
        self.load_pages()
        if not self.pages:
            self.add("critical", "no-pages", f"No HTML files found under {self.root}")
            return
        for url, (path, pg) in sorted(self.pages.items()):
            self.check_page(url, path, pg)
        self.check_robots()
        self.check_sitemap()
        self.check_llms()
        self.check_headers()
        self.check_mirrors()
        self.check_schema_vs_dom()
        if live:
            self.check_live()


def detect_root(project: Path, configured):
    if configured:
        for c in configured:
            p = project / c
            if p.is_dir():
                return p
        return None
    for guess in ROOT_GUESSES:
        p = project / guess
        if p.is_dir() and any(p.glob("*.html")):
            return p
    # Fall back to the project root if it holds HTML directly.
    if any(project.glob("*.html")):
        return project
    return None


def read_config(project: Path):
    cfg = project / ".claude" / "kit.json"
    if not cfg.exists():
        return {}
    try:
        data = json.loads(cfg.read_text())
    except Exception:
        return {}
    return data.get("web", {}) or {}


def main():
    ap = argparse.ArgumentParser(description="SEO/AEO asset scanner")
    ap.add_argument("--root", help="site directory (default: from kit.json or autodetect)")
    ap.add_argument("--base-url", help="canonical origin, e.g. https://example.com")
    ap.add_argument("--project", default=".", help="project root (default: cwd)")
    ap.add_argument("--live", action="store_true", help="also probe the deployed site")
    ap.add_argument("--show-suppressed", action="store_true",
                    help="list findings silenced by web.ignore")
    ap.add_argument("--json", action="store_true", help="emit JSON only")
    args = ap.parse_args()

    project = Path(args.project).resolve()
    cfg = read_config(project)
    roots = [args.root] if args.root else (cfg.get("roots") or [])
    root = detect_root(project, roots)
    if not root:
        print(json.dumps({"error": "Could not find a site directory. Set web.roots in "
                                   ".claude/kit.json or pass --root."}), file=sys.stderr)
        return 2
    base_url = args.base_url or cfg.get("baseUrl") or ""

    sc = Scanner(root, base_url, project, ignore=cfg.get("ignore") or [])
    sc.run(live=args.live)

    order = {"critical": 0, "warning": 1, "info": 2}
    sc.findings.sort(key=lambda f: (order.get(f["severity"], 3), f["check"], f.get("file") or ""))
    counts = {s: sum(1 for f in sc.findings if f["severity"] == s)
              for s in ("critical", "warning", "info")}
    counts["suppressed"] = len(sc.suppressed)
    out = {
        "root": str(root.relative_to(project)),
        "baseUrl": base_url,
        "pages": sorted(sc.pages.keys()),
        "counts": counts,
        "findings": sc.findings,
        "suppressed": sc.suppressed,
    }

    if args.json:
        print(json.dumps(out, indent=2))
    else:
        print(f"Scanned {len(sc.pages)} page(s) under {out['root']}"
              + (f" — live probe against {base_url}" if args.live else ""))
        line = (f"{counts['critical']} critical / {counts['warning']} warning / "
                f"{counts['info']} info")
        if sc.suppressed:
            line += f" ({len(sc.suppressed)} suppressed by web.ignore)"
        print(line + "\n")
        for sev in ("critical", "warning", "info"):
            group = [f for f in sc.findings if f["severity"] == sev]
            if not group:
                continue
            print(sev.upper())
            for f in group:
                loc = f.get("file") or ""
                if f.get("line"):
                    loc += f":{f['line']}"
                tag = " [auto]" if f["fix"] == "auto" else ""
                print(f"  {f['check']}{tag}  {loc}")
                print(f"    {f['message']}")
                if f.get("detail"):
                    print(f"    ↳ {f['detail']}")
            print()

        if args.show_suppressed and sc.suppressed:
            print("SUPPRESSED")
            for f in sc.suppressed:
                print(f"  {f['check']}  {f.get('file') or ''}")
                print(f"    {f['message']}")
                print(f"    ↳ {f['suppressedBy']}")
            print()

    return 1 if counts["critical"] else 0


if __name__ == "__main__":
    sys.exit(main())
