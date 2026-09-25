import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, existsSync, statSync } from 'fs';
import { join, dirname, basename, resolve, relative, extname } from 'path';
import { marked } from 'marked';

// Usage: node build.mjs <wiki-dir> <out-dir> [--title "Sidebar title"] [--access path/to/access.json]
//   --title   text at the top of the sidebar (default: the README's first heading)
//   --access  Cloudflare Access settings for restricted folders (default: .claude/wiki-access.json in the cwd)
const args = process.argv.slice(2);
function takeFlag(name) {
  const i = args.indexOf(name);
  return i === -1 ? null : args.splice(i, 2)[1] ?? null;
}
const siteTitleFlag = takeFlag('--title');
const accessFlag = takeFlag('--access');

const wikiDir = resolve(args[0] || join(dirname(new URL(import.meta.url).pathname), '..', '..', 'wiki'));
const outDir = resolve(args[1] || join(dirname(wikiDir), '_wiki-site'));

if (!existsSync(wikiDir)) {
  console.error(`Wiki directory not found: ${wikiDir}`);
  process.exit(1);
}

const SKIP = new Set(['STYLE.md']);

// Pages can sit in project folders (e.g. wiki/billing/, wiki/onboarding/). Paths are kept
// relative to the wiki root, and the built site mirrors the same folders.
function listPages(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const rel = prefix + entry.name;
    if (entry.isDirectory()) return listPages(join(dir, entry.name), rel + '/');
    return entry.name.endsWith('.md') && !SKIP.has(entry.name) ? [rel] : [];
  });
}
const mdFiles = listPages(wikiDir);

// A project folder holding RESTRICTED.txt sits behind its own Cloudflare Access rule
// (only the people it lists). Its pages build as usual but stay out of the shared
// sidebar, search and Home page. The people on its allow list get its sidebar group and
// search entries from /private/nav.json, served by _worker.js (see the end of this file).
const restrictedDirs = new Set(
  readdirSync(wikiDir, { withFileTypes: true })
    .filter(e => e.isDirectory() && existsSync(join(wikiDir, e.name, 'RESTRICTED.txt')))
    .map(e => e.name)
);
const isRestricted = f => f.includes('/') && restrictedDirs.has(f.split('/')[0]);
const PRIVATE_NAV = 'private/nav.json';

if (!mdFiles.length) {
  console.error('No markdown files found in wiki directory');
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });

// Parse README.md for wiki title and nav links
const readmeContent = existsSync(join(wikiDir, 'README.md'))
  ? readFileSync(join(wikiDir, 'README.md'), 'utf-8')
  : '';

const titleMatch = readmeContent.match(/^#\s+(.+)$/m);
const wikiTitle = titleMatch ? titleMatch[1].trim() : 'Wiki';

// Extract nav links from README — lines like "- [Title](file.md)" — grouped under the
// "## Heading" they sit beneath. Each heading is a project (one folder of pages) and
// becomes a collapsible group in the sidebar; links above the first heading stay ungrouped.
const navGroups = [{ name: null, links: [] }];
for (const line of readmeContent.split('\n')) {
  const heading = line.match(/^##\s+(.+)$/);
  if (heading) {
    navGroups.push({ name: heading[1].trim(), links: [] });
    continue;
  }
  for (const match of line.matchAll(/\[([^\]]+)\]\(([^)]+\.md)\)/g)) {
    const [, label, href] = match;
    if (!SKIP.has(href)) {
      navGroups[navGroups.length - 1].links.push({ label, href: href.replace(/\.md$/, '.html') });
    }
  }
}
for (const g of navGroups) g.restricted = g.links.length > 0 && g.links.every(l => isRestricted(l.href));
const navSections = navGroups.filter(g => g.links.length);
const hasProjects = navSections.some(g => g.name);
const hasRestricted = navSections.some(g => g.restricted);
const restrictedNames = new Set(navSections.filter(g => g.restricted).map(g => g.name));

// Page source, except that the shared Home page loses restricted projects' sections.
function pageSource(mdFile) {
  const src = readFileSync(join(wikiDir, mdFile), 'utf-8');
  if (mdFile !== 'README.md' || !restrictedNames.size) return src;
  let skipping = false;
  return src.split('\n').filter(line => {
    const h = line.match(/^##\s+(.+)$/);
    if (h) skipping = restrictedNames.has(h[1].trim());
    return !skipping;
  }).join('\n');
}
const projectChevron = '<svg class="nav-project-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>';

// Track images referenced in markdown
const images = new Set();
// Folder of the page currently being parsed, so image paths resolve relative to that page.
let currentPageDir = '.';

function slugify(text) {
  return text.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^\w\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-').trim();
}

// Rewrite .md links to .html, track image references, add heading anchors
marked.use({
  renderer: {
    heading({ tokens, depth }) {
      if (depth > 3) {
        const text = this.parser.parseInline(tokens);
        return `<h${depth}>${text}</h${depth}>\n`;
      }
      const text = this.parser.parseInline(tokens);
      const id = slugify(text.replace(/<[^>]+>/g, ''));
      return `<h${depth} id="${id}">${text}</h${depth}>\n`;
    },
    link({ href, title, tokens }) {
      if (href && !href.startsWith('http') && /\.md(#.*)?$/.test(href)) {
        href = href
          .replace(/(^|\/)README\.md(?=#|$)/, '$1index.html')
          .replace(/\.md(?=#|$)/, '.html');
      }
      const text = this.parser.parseInline(tokens);
      let out = `<a href="${href}"`;
      if (title) out += ` title="${title}"`;
      out += `>${text}</a>`;
      return out;
    },
    image({ href, title, text }) {
      if (href && !href.startsWith('http')) {
        images.add(join(currentPageDir, href));
      }
      let out = `<img src="${href}" alt="${text || ''}"`;
      if (title) out += ` title="${title}"`;
      out += '>';
      return out;
    }
  }
});

function htmlFilename(mdFile) {
  return mdFile === 'README.md' ? 'index.html' : mdFile.replace(/\.md$/, '.html');
}

// Build search index — plain text per page with title and URL
const searchIndex = [];

function stripHtml(html) {
  return html
    .replace(/<[^>]+>/g, ' ')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&mdash;/g, '—')
    .replace(/&ndash;/g, '–').replace(/&hellip;/g, '…').replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

function formatDate(date) {
  const m = date.getMonth() + 1;
  const d = date.getDate();
  const y = String(date.getFullYear()).slice(2);
  let h = date.getHours();
  const min = String(date.getMinutes()).padStart(2, '0');
  const ampm = h >= 12 ? 'pm' : 'am';
  h = h % 12 || 12;
  return `${m}/${d}/${y} ${h}:${min}${ampm}`;
}

function extractHeadings(html) {
  const headings = [];
  const re = /<h([23])\s+id="([^"]+)">(.+?)<\/h[23]>/g;
  let match;
  while ((match = re.exec(html)) !== null) {
    headings.push({ depth: Number(match[1]), id: match[2], text: match[3].replace(/<[^>]+>/g, '') });
  }
  return headings;
}

function buildToc(headings) {
  if (headings.length <= 1) return '';
  const sections = [];
  for (const h of headings) {
    if (h.depth === 2) {
      sections.push({ ...h, children: [] });
    } else if (sections.length) {
      sections[sections.length - 1].children.push(h);
    }
  }
  const chevron = '<svg class="toc-chevron-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>';
  let inner = '';
  sections.forEach((s, i) => {
    if (s.children.length) {
      inner += `<div class="toc-section">
            <div class="toc-heading">
              <a href="#${s.id}" class="toc-link">${s.text}</a>
              <button class="toc-chevron" aria-expanded="false" data-toc="${i}">${chevron}</button>
            </div>
            <div class="toc-children" id="toc-sub-${i}" hidden>
              ${s.children.map(c => `<a href="#${c.id}" class="toc-link toc-h3">${c.text}</a>`).join('\n              ')}
            </div>
          </div>\n          `;
    } else {
      inner += `<a href="#${s.id}" class="toc-link">${s.text}</a>\n          `;
    }
  });
  return `<div class="toc-inline">\n          ${inner}</div>`;
}

function buildPage(mdFile, searchIndexJson) {
  const src = pageSource(mdFile);
  const mtime = statSync(join(wikiDir, mdFile)).mtime;
  currentPageDir = dirname(mdFile);
  const content = marked.parse(src);
  const currentHref = htmlFilename(mdFile);
  // Sidebar, Home and search links are written from the wiki root; a page in a
  // project folder needs "../" in front of them.
  const root = '../'.repeat(mdFile.split('/').length - 1);

  const pageTitle = src.match(/^#\s+(.+)$/m)?.[1]?.trim()
    || basename(mdFile, '.md');

  const headings = extractHeadings(content);
  const tocHtml = buildToc(headings);
  const isIndex = currentHref === 'index.html';

  const navLink = ({ label, href }) => {
    const active = href === currentHref ? ' class="active"' : '';
    const link = `<a href="${root}${href}"${active}>${label}</a>`;
    return (href === currentHref && tocHtml) ? link + '\n          ' + tocHtml : link;
  };
  const nav = navSections.filter(g => !g.restricted || isRestricted(mdFile)).map(group => {
    const links = group.links.map(navLink).join('\n            ');
    if (!group.name) return links;
    // Top-level project groups start open so every page is in view; readers can collapse any
    // of them. (Only groups: a page's own heading table of contents keeps its own behaviour.)
    const open = true;
    return `<div class="nav-project">
          <button class="nav-project-toggle" aria-expanded="${open}">${projectChevron}<span>${group.name}</span></button>
          <div class="nav-project-links"${open ? '' : ' hidden'}>
            ${links}
          </div>
        </div>`;
  }).join('\n          ');

  // With project groups, Home's own headings would just repeat the group names.
  const indexToc = isIndex && !hasProjects ? tocHtml : '';
  const lastUpdated = formatDate(mtime);
  const loadPrivate = hasRestricted && !isRestricted(mdFile);
  return template(wikiTitle, pageTitle, nav, content, isIndex, searchIndexJson, lastUpdated, indexToc, root, loadPrivate);
}

function escapeHtmlText(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function template(wikiTitle, pageTitle, nav, content, isIndex, searchIndexJson, lastUpdated, indexToc, root, loadPrivate) {
  const title = isIndex ? wikiTitle : `${pageTitle} — ${wikiTitle}`;
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>${title}</title>
  <script>try { if (localStorage.getItem('wiki-sidebar') === 'collapsed') document.documentElement.classList.add('sidebar-collapsed'); } catch (e) {}</script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #fff;
      color: #1a1a1a;
      line-height: 1.7;
      font-size: 16px;
      -webkit-font-smoothing: antialiased;
    }

    .layout {
      display: flex;
      min-height: 100vh;
    }

    /* Sidebar */
    .sidebar {
      width: 260px;
      flex-shrink: 0;
      border-right: 1px solid #e5e5e5;
      padding: 2rem 1.5rem;
      position: sticky;
      top: 0;
      height: 100vh;
      overflow-y: auto;
    }

    .sidebar-title {
      font-size: 0.875rem;
      font-weight: 600;
      color: #737373;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin-bottom: 1.25rem;
    }

    .sidebar > a, .nav-project-links > a {
      display: block;
      padding: 0.375rem 0.75rem;
      margin: 0.125rem 0;
      color: #525252;
      text-decoration: none;
      font-size: 0.9375rem;
      border-radius: 6px;
      transition: background 0.15s, color 0.15s;
    }

    .sidebar > a:hover, .nav-project-links > a:hover {
      background: #f5f5f5;
      color: #1a1a1a;
    }

    .sidebar > a.active, .nav-project-links > a.active {
      background: #f0f0f0;
      color: #1a1a1a;
      font-weight: 500;
    }

    /* Project groups (accordion) */
    .nav-project { margin-top: 0.75rem; }

    .nav-project-toggle {
      display: flex;
      align-items: center;
      gap: 0.375rem;
      width: 100%;
      background: none;
      border: none;
      cursor: pointer;
      font-family: inherit;
      text-align: left;
      padding: 0.375rem 0.5rem;
      border-radius: 6px;
      font-size: 0.75rem;
      font-weight: 600;
      letter-spacing: 0.05em;
      text-transform: uppercase;
      color: #737373;
    }

    .nav-project-toggle:hover { background: #f5f5f5; color: #1a1a1a; }

    .nav-project-chevron { flex-shrink: 0; transition: transform 0.15s ease; }

    .nav-project-toggle[aria-expanded="true"] .nav-project-chevron { transform: rotate(90deg); }

    .nav-project-links {
      margin-left: 0.625rem;
      padding-left: 0.25rem;
      border-left: 1px solid #e5e5e5;
    }

    /* Table of contents (accordion) */
    .toc-inline {
      margin-left: 0.75rem;
      padding-left: 0.5rem;
      border-left: 1px solid #e5e5e5;
      margin-top: 0.125rem;
      margin-bottom: 0.25rem;
    }

    .toc-section { margin: 0; }

    .toc-heading {
      display: flex;
      align-items: center;
    }

    .toc-heading .toc-link { flex: 1; }

    .toc-chevron {
      display: flex;
      align-items: center;
      justify-content: center;
      background: none;
      border: none;
      padding: 0.25rem;
      cursor: pointer;
      color: #a3a3a3;
      border-radius: 4px;
      flex-shrink: 0;
    }

    .toc-chevron:hover { color: #525252; }

    .toc-chevron-icon {
      transition: transform 0.15s ease;
    }

    .toc-chevron[aria-expanded="true"] .toc-chevron-icon {
      transform: rotate(90deg);
    }

    .toc-children {
      margin-left: 0.5rem;
      padding-left: 0.5rem;
      border-left: 1px solid #e5e5e5;
    }

    .toc-link {
      display: block;
      padding: 0.25rem 0.75rem;
      color: #525252;
      text-decoration: none;
      font-size: 0.8125rem;
      line-height: 1.4;
      border-radius: 4px;
      transition: color 0.15s;
      font-weight: 500;
    }

    .toc-link:hover { color: #1a1a1a; }

    .toc-h3 {
      font-size: 0.75rem;
      color: #a3a3a3;
    }

    .toc-h3:hover { color: #525252; }

    /* Search */
    .search-wrap {
      position: relative;
      margin-bottom: 1rem;
    }

    .search-input {
      width: 100%;
      padding: 0.5rem 0.75rem;
      font-family: inherit;
      font-size: 0.875rem;
      border: 1px solid #e5e5e5;
      border-radius: 6px;
      background: #fafafa;
      color: #1a1a1a;
      outline: none;
      transition: border-color 0.15s;
    }

    .search-input::placeholder { color: #a3a3a3; }
    .search-input:focus { border-color: #a3a3a3; background: #fff; }

    .search-results {
      position: absolute;
      top: calc(100% + 4px);
      left: 0;
      right: 0;
      background: #fff;
      border: 1px solid #e5e5e5;
      border-radius: 6px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.08);
      max-height: 280px;
      overflow-y: auto;
      z-index: 50;
      display: none;
    }

    .search-results.open { display: block; }

    .search-result {
      display: block;
      padding: 0.5rem 0.75rem;
      text-decoration: none;
      color: #1a1a1a;
      font-size: 0.875rem;
      border-bottom: 1px solid #f5f5f5;
    }

    .search-result:last-child { border-bottom: none; }
    .search-result:hover, .search-result.focused { background: #f5f5f5; }

    .search-result-title { font-weight: 500; }

    .search-result-snippet {
      font-size: 0.8125rem;
      color: #737373;
      margin-top: 2px;
      line-height: 1.4;
    }

    .search-result-snippet mark {
      background: #fef08a;
      color: inherit;
      border-radius: 2px;
      padding: 0 1px;
    }

    .search-empty {
      padding: 0.75rem;
      font-size: 0.8125rem;
      color: #a3a3a3;
      text-align: center;
    }

    /* Desktop sidebar collapse (bottom-left corner) */
    .sidebar { padding-bottom: 4.5rem; }
    .sidebar-collapse {
      position: fixed;
      left: 1rem;
      bottom: 1rem;
      z-index: 100;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 2.25rem;
      height: 2.25rem;
      background: #fff;
      border: 1px solid #e5e5e5;
      border-radius: 8px;
      color: #737373;
      cursor: pointer;
      box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    .sidebar-collapse:hover { color: #1a1a1a; background: #f5f5f5; }
    .sidebar-collapse .icon-expand { display: none; }
    html.sidebar-collapsed .sidebar-collapse .icon-collapse { display: none; }
    html.sidebar-collapsed .sidebar-collapse .icon-expand { display: block; }
    @media (min-width: 769px) {
      html.sidebar-collapsed .sidebar { display: none; }
    }

    /* Mobile nav toggle */
    .nav-toggle {
      display: none;
      position: fixed;
      top: 1rem;
      left: 1rem;
      z-index: 100;
      background: #fff;
      border: 1px solid #e5e5e5;
      border-radius: 8px;
      padding: 0.5rem 0.75rem;
      font-size: 0.875rem;
      font-family: inherit;
      cursor: pointer;
      box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    }

    /* Content */
    .content {
      flex: 1;
      min-width: 0;
      padding: 3rem 2rem;
      display: flex;
      justify-content: center;
    }

    .prose {
      max-width: 70ch;
      width: 100%;
    }

    .prose h1 {
      font-size: 2rem;
      font-weight: 700;
      line-height: 1.2;
      margin-bottom: 0.5rem;
      color: #0a0a0a;
    }

    .last-updated {
      font-size: 0.8125rem;
      color: #a3a3a3;
      margin-bottom: 2rem;
    }

    .prose h2 {
      font-size: 1.5rem;
      font-weight: 600;
      line-height: 1.3;
      margin-top: 3rem;
      margin-bottom: 1rem;
      color: #0a0a0a;
    }

    .prose h3 {
      font-size: 1.175rem;
      font-weight: 600;
      line-height: 1.4;
      margin-top: 2.25rem;
      margin-bottom: 0.75rem;
      color: #1a1a1a;
    }

    .prose h4 {
      font-size: 1rem;
      font-weight: 600;
      line-height: 1.5;
      margin-top: 1.75rem;
      margin-bottom: 0.5rem;
      color: #1a1a1a;
    }

    .prose p {
      margin-bottom: 1.25rem;
    }

    .prose a {
      color: #2563eb;
      text-decoration: underline;
      text-underline-offset: 2px;
    }

    .prose a:hover {
      color: #1d4ed8;
    }

    .prose ul, .prose ol {
      margin-bottom: 1.25rem;
      padding-left: 1.5rem;
    }

    .prose li {
      margin-bottom: 0.375rem;
    }

    .prose li > ul, .prose li > ol {
      margin-top: 0.375rem;
      margin-bottom: 0;
    }

    .prose strong {
      font-weight: 600;
      color: #0a0a0a;
    }

    .prose code {
      font-family: 'SF Mono', 'Fira Code', 'Fira Mono', Menlo, monospace;
      font-size: 0.875em;
      background: #f5f5f5;
      padding: 0.15em 0.35em;
      border-radius: 4px;
    }

    .prose pre {
      background: #fafafa;
      border: 1px solid #e5e5e5;
      border-radius: 8px;
      padding: 1rem 1.25rem;
      overflow-x: auto;
      margin-bottom: 1.5rem;
    }

    .prose pre code {
      background: none;
      padding: 0;
      font-size: 0.8125rem;
      line-height: 1.6;
    }

    .prose blockquote {
      border-left: 3px solid #d4d4d4;
      padding-left: 1rem;
      color: #525252;
      margin-bottom: 1.25rem;
    }

    .prose table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 1.5rem;
      font-size: 0.9375rem;
      overflow-x: auto;
      display: block;
    }

    .prose th, .prose td {
      padding: 0.625rem 0.875rem;
      text-align: left;
      border-bottom: 1px solid #e5e5e5;
    }

    .prose th {
      font-weight: 600;
      color: #0a0a0a;
      border-bottom: 2px solid #d4d4d4;
    }

    .prose hr {
      border: none;
      border-top: 1px solid #e5e5e5;
      margin: 2.5rem 0;
    }

    .prose img {
      max-width: 100%;
      height: auto;
      border-radius: 8px;
      margin: 1rem 0;
    }

    /* Mobile */
    @media (max-width: 768px) {
      .nav-toggle { display: block; }
      .sidebar-collapse { display: none; }

      .sidebar {
        position: fixed;
        left: -280px;
        top: 0;
        width: 280px;
        height: 100vh;
        background: #fff;
        z-index: 99;
        transition: left 0.25s ease;
        box-shadow: none;
        padding-top: 4rem;
      }

      .sidebar.open {
        left: 0;
        box-shadow: 4px 0 24px rgba(0,0,0,0.1);
      }

      .overlay {
        display: none;
        position: fixed;
        inset: 0;
        background: rgba(0,0,0,0.3);
        z-index: 98;
      }

      .overlay.open { display: block; }

      .content {
        padding: 4rem 1.25rem 2rem;
      }
    }
  </style>
</head>
<body>
  <button class="nav-toggle" aria-label="Toggle navigation">Menu</button>
  <!-- Lucide panel-left (collapse) / panel-right (expand) -->
  <button class="sidebar-collapse" id="sidebar-collapse" aria-controls="sidebar" aria-expanded="true" aria-label="Collapse sidebar" title="Collapse sidebar"><svg class="icon-collapse" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/></svg><svg class="icon-expand" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/></svg></button>
  <div class="overlay" id="overlay"></div>
  <div class="layout">
    <nav class="sidebar" id="sidebar">
      <div class="sidebar-title">${escapeHtmlText(siteTitleFlag || wikiTitle)}</div>
      <div class="search-wrap">
        <input type="text" class="search-input" id="search" placeholder="Search..." autocomplete="off">
        <div class="search-results" id="search-results"></div>
      </div>
      <a href="${root}index.html"${isIndex ? ' class="active"' : ''}>Home</a>
      ${indexToc}
      ${nav}
    </nav>
    <main class="content">
      <article class="prose">
        ${content.replace(/<\/h1>/, `</h1>\n        <div class="last-updated">Last updated ${lastUpdated}</div>`)}
      </article>
    </main>
  </div>
  <script>
    const toggle = document.querySelector('.nav-toggle');
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('overlay');
    function closeSidebar() { sidebar.classList.remove('open'); overlay.classList.remove('open'); }
    toggle.addEventListener('click', () => {
      sidebar.classList.toggle('open');
      overlay.classList.toggle('open');
    });
    overlay.addEventListener('click', closeSidebar);

    // Desktop: collapse/expand the sidebar, remembered per browser. The <head> script applies a saved
    // "collapsed" before first paint, so there is no flash of the sidebar on load.
    const collapseBtn = document.getElementById('sidebar-collapse');
    function syncCollapse() {
      const collapsed = document.documentElement.classList.contains('sidebar-collapsed');
      const label = collapsed ? 'Expand sidebar' : 'Collapse sidebar';
      collapseBtn.setAttribute('aria-expanded', String(!collapsed));
      collapseBtn.setAttribute('aria-label', label);
      collapseBtn.title = label;
    }
    collapseBtn.addEventListener('click', () => {
      const collapsed = document.documentElement.classList.toggle('sidebar-collapsed');
      try { localStorage.setItem('wiki-sidebar', collapsed ? 'collapsed' : 'expanded'); } catch (e) {}
      syncCollapse();
    });
    syncCollapse();

    // Search
    const searchIndex = ${searchIndexJson};
    const ROOT = '${root}';
    const LOAD_PRIVATE = ${loadPrivate ? 'true' : 'false'};
    const CHEVRON = ${JSON.stringify(projectChevron)};
    const searchInput = document.getElementById('search');
    const searchResults = document.getElementById('search-results');
    let focusIdx = -1;

    function escapeHtml(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

    function getSnippet(text, query) {
      const i = text.indexOf(query);
      if (i === -1) return '';
      const start = Math.max(0, i - 40);
      const end = Math.min(text.length, i + query.length + 60);
      let snippet = (start > 0 ? '...' : '') + text.slice(start, end) + (end < text.length ? '...' : '');
      const escaped = escapeHtml(snippet);
      const safe = query.replace(/[-\\/\\\\^$*+?.()|[\\]{}]/g, '\\\\$&');
      return escaped.replace(new RegExp('(' + safe + ')', 'gi'), '<mark>$1</mark>');
    }

    function doSearch() {
      const q = searchInput.value.trim().toLowerCase();
      if (q.length < 2) { searchResults.classList.remove('open'); return; }
      const hits = searchIndex
        .filter(p => p.title.toLowerCase().includes(q) || p.text.includes(q))
        .slice(0, 8);
      if (!hits.length) {
        searchResults.innerHTML = '<div class="search-empty">No results</div>';
      } else {
        searchResults.innerHTML = hits.map((h, i) =>
          '<a class="search-result" href="' + ROOT + h.href + '">' +
            '<div class="search-result-title">' + escapeHtml(h.title) + '</div>' +
            '<div class="search-result-snippet">' + getSnippet(h.text, q) + '</div>' +
          '</a>'
        ).join('');
      }
      focusIdx = -1;
      searchResults.classList.add('open');
    }

    searchInput.addEventListener('input', doSearch);
    searchInput.addEventListener('focus', () => { if (searchInput.value.trim().length >= 2) doSearch(); });
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.search-wrap')) searchResults.classList.remove('open');
    });

    searchInput.addEventListener('keydown', (e) => {
      const items = searchResults.querySelectorAll('.search-result');
      if (!items.length) return;
      if (e.key === 'ArrowDown') { e.preventDefault(); focusIdx = Math.min(focusIdx + 1, items.length - 1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); focusIdx = Math.max(focusIdx - 1, 0); }
      else if (e.key === 'Enter' && focusIdx >= 0) { e.preventDefault(); items[focusIdx].click(); return; }
      else if (e.key === 'Escape') { searchResults.classList.remove('open'); return; }
      else return;
      items.forEach((el, i) => el.classList.toggle('focused', i === focusIdx));
    });

    // Project groups accordion, delegated so groups added after load work too
    sidebar.addEventListener('click', e => {
      const btn = e.target.closest('.nav-project-toggle');
      if (!btn) return;
      const expanded = btn.getAttribute('aria-expanded') === 'true';
      btn.setAttribute('aria-expanded', String(!expanded));
      btn.nextElementSibling.hidden = expanded;
    });

    // Restricted projects: the site's worker answers this only for readers on a restricted
    // project's allow list. Everyone else gets 404, and nothing is added.
    if (LOAD_PRIVATE) {
      fetch(ROOT + '${PRIVATE_NAV}', { credentials: 'same-origin', redirect: 'manual', cache: 'no-store' })
        .then(r => (r.ok && (r.headers.get('content-type') || '').includes('json')) ? r.json() : null)
        .then(extra => {
          if (!extra) return;
          for (const g of extra.groups) {
            const div = document.createElement('div');
            div.className = 'nav-project';
            div.innerHTML = '<button class="nav-project-toggle" aria-expanded="true">' + CHEVRON +
              '<span>' + escapeHtml(g.name) + '</span></button><div class="nav-project-links">' +
              g.links.map(l => '<a href="' + ROOT + l.href + '">' + escapeHtml(l.label) + '</a>').join('') +
              '</div>';
            sidebar.appendChild(div);
          }
          searchIndex.push(...extra.search);
        })
        .catch(() => {});
    }

    // TOC accordion
    document.querySelectorAll('.toc-chevron').forEach(btn => {
      btn.addEventListener('click', e => {
        e.preventDefault();
        const expanded = btn.getAttribute('aria-expanded') === 'true';
        btn.setAttribute('aria-expanded', String(!expanded));
        const children = btn.closest('.toc-section').querySelector('.toc-children');
        if (children) children.hidden = expanded;
      });
    });
  </script>
</body>
</html>`;
}

// Two-pass build: first pass populates the search index, second writes pages with the index
for (const mdFile of mdFiles) {
  const src = pageSource(mdFile);
  currentPageDir = dirname(mdFile);
  const content = marked.parse(src);
  const pageTitle = src.match(/^#\s+(.+)$/m)?.[1]?.trim() || basename(mdFile, '.md');
  searchIndex.push({ title: pageTitle, href: htmlFilename(mdFile), text: stripHtml(content).toLowerCase(), restricted: isRestricted(mdFile) });
}

const withoutFlag = ({ restricted, ...entry }) => entry;
const searchIndexJson = JSON.stringify(searchIndex.filter(e => !e.restricted).map(withoutFlag));
const fullSearchIndexJson = JSON.stringify(searchIndex.map(withoutFlag));

for (const mdFile of mdFiles) {
  const html = buildPage(mdFile, isRestricted(mdFile) ? fullSearchIndexJson : searchIndexJson);
  const dest = join(outDir, htmlFilename(mdFile));
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, html);
  console.log(`  ${mdFile} → ${htmlFilename(mdFile)}`);
}

// Copy referenced images
for (const img of images) {
  const src = join(wikiDir, img);
  if (existsSync(src)) {
    const dest = join(outDir, img);
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(src, dest);
    console.log(`  ${img} (image)`);
  }
}

// Write robots.txt
writeFileSync(join(outDir, 'robots.txt'), 'User-agent: *\nDisallow: /\n');


// Cloudflare Pages redirects: pages moved into project folders on 2026-09-11, so links
// made before then (bookmarks, links from other apps) still land.
// Pages serves "/page.html" as "/page", so both old forms are redirected.
const rootNames = new Set(mdFiles.filter(f => !f.includes('/')).map(f => basename(f, '.md')));
const redirects = mdFiles
  .filter(f => f.includes('/') && !isRestricted(f) && !rootNames.has(basename(f, '.md')))
  .flatMap(f => {
    const name = basename(f, '.md');
    const target = '/' + f.replace(/\.md$/, '');
    return [`/${name} ${target} 301`, `/${name}.html ${target} 301`];
  });
if (redirects.length) {
  writeFileSync(join(outDir, '_redirects'), redirects.join('\n') + '\n');
  console.log(`  _redirects (${redirects.length} rules for pages moved into project folders)`);
}

// Restricted projects: the site's _worker.js serves their sidebar groups and search
// entries at /private/nav.json, and only to readers whose Cloudflare Access sign-in token
// verifies and whose email is on the project's allow list (the "allow:" lines in its
// RESTRICTED.txt). Anyone else gets 404. It runs behind the wiki-wide Access rules,
// so the reader's token is already there; a separate Access rule on /private would
// need a second sign-in that a background request cannot complete.
// The worker also applies the redirects above, whichever way Pages treats _redirects
// when a worker is present.
function workerSource(redirectMap, privateGroups, access) {
  return `// Generated by scripts/wiki-build/build.mjs. Do not edit; rebuild the wiki instead.
const REDIRECTS = ${JSON.stringify(redirectMap)};
const PRIVATE = ${JSON.stringify(privateGroups)};
const ACCESS = ${JSON.stringify({ team: access.team, auds: access.auds })};
let certs = null;

const bytes = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '=')), c => c.charCodeAt(0));
const decode = s => JSON.parse(new TextDecoder().decode(bytes(s)));

// The email in the reader's Access token, only if the token is signed by our Access
// team, issued for this wiki, and unexpired.
async function verifiedEmail(request) {
  const token = request.headers.get('cf-access-jwt-assertion');
  const [h, p, sig] = (token || '').split('.');
  if (!sig) return null;
  const header = decode(h);
  const payload = decode(p);
  const auds = [].concat(payload.aud || []);
  if (payload.iss !== ACCESS.team || !auds.some(a => ACCESS.auds.includes(a)) || !(payload.exp * 1000 > Date.now())) return null;
  for (let attempt = 0; attempt < 2; attempt++) {
    if (!certs || attempt) certs = (await (await fetch(ACCESS.team + '/cdn-cgi/access/certs')).json()).keys;
    const jwk = certs.find(k => k.kid === header.kid);
    if (!jwk) continue;
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, bytes(sig), new TextEncoder().encode(h + '.' + p));
    return ok ? String(payload.email || '').toLowerCase() : null;
  }
  return null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const to = REDIRECTS[url.pathname];
    if (to) return Response.redirect(new URL(to, url).toString(), 301);
    if (url.pathname === '/private/nav.json') {
      const email = await verifiedEmail(request).catch(() => null);
      const mine = email ? PRIVATE.filter(g => g.allow.includes(email)) : [];
      if (!mine.length) return new Response('Not found', { status: 404 });
      return new Response(JSON.stringify({ groups: mine.map(g => g.group), search: mine.flatMap(g => g.search) }), {
        headers: { 'content-type': 'application/json', 'cache-control': 'private, no-store' },
      });
    }
    if (url.pathname.startsWith('/private/')) return new Response('Not found', { status: 404 });
    return env.ASSETS.fetch(request);
  },
};
`;
}

if (hasRestricted) {
  // Per-project settings live with the project, not beside this (shared) script.
  const accessPath = resolve(accessFlag || join('.claude', 'wiki-access.json'));
  if (!existsSync(accessPath)) {
    console.error(`Restricted projects need ${accessPath} ({ "team": ..., "auds": [...] }), or pass --access <file>`);
    process.exit(1);
  }
  const access = JSON.parse(readFileSync(accessPath, 'utf-8'));
  const privateGroups = navSections.filter(g => g.restricted).map(g => {
    const dir = g.links[0].href.split('/')[0];
    const allow = [...readFileSync(join(wikiDir, dir, 'RESTRICTED.txt'), 'utf-8').matchAll(/^allow:\s*(\S+@\S+)\s*$/gmi)]
      .map(m => m[1].toLowerCase());
    if (!allow.length) {
      console.error(`${dir}/RESTRICTED.txt has no "allow:" lines`);
      process.exit(1);
    }
    return {
      allow,
      group: { name: g.name, links: g.links },
      search: searchIndex.filter(e => e.restricted && e.href.startsWith(dir + '/')).map(withoutFlag),
    };
  });
  const redirectMap = Object.fromEntries(redirects.map(r => r.split(' ').slice(0, 2)));
  writeFileSync(join(outDir, '_worker.js'), workerSource(redirectMap, privateGroups, access));
  console.log(`  _worker.js (serves /private/nav.json for: ${privateGroups.map(g => `${g.group.name} → ${g.allow.join(', ')}`).join('; ')})`);
}

console.log(`\nBuilt ${mdFiles.length} pages → ${outDir}`);
