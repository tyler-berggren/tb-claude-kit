import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'fs';
import { join, dirname, resolve } from 'path';
import { fileURLToPath } from 'url';
import { workerSource } from './worker.mjs';

// Step 2 of the wiki build, the plain renderer: turns a bundle from parse.mjs into a static site.
//
// Usage: node render.mjs <bundle-dir> <out-dir>
//
// The rule for this renderer is navigation and reading only: a sidebar (grouped links, the open
// page's headings, search), the page, a collapse button (+ Cmd/Ctrl+B) and a phone drawer. It is
// deliberately plain and meant to stay that way; anything fancier belongs in a renderer of your own,
// plugged in with kit.json "wiki.renderer" (see the kit README).
const SUPPORTED_FORMAT = 1;
const here = dirname(fileURLToPath(import.meta.url));
const [bundleArg, outArg] = process.argv.slice(2);
const bundleDir = resolve(bundleArg || '_wiki-bundle');
const outDir = resolve(outArg || '_wiki-site');

const wiki = JSON.parse(readFileSync(join(bundleDir, 'wiki.json'), 'utf-8'));
if (wiki.format !== SUPPORTED_FORMAT) {
  console.error(`wiki.json is format ${wiki.format}; this renderer reads format ${SUPPORTED_FORMAT}`);
  process.exit(1);
}
const search = JSON.parse(readFileSync(join(bundleDir, 'search.json'), 'utf-8'));
const hasProjects = wiki.nav.some(g => g.name);
const hasRestricted = wiki.nav.some(g => g.restricted);

const escapeHtml = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const chevron = cls => `<svg class="${cls}" width="${cls === 'toc-chevron-icon' ? 14 : 12}" height="${cls === 'toc-chevron-icon' ? 14 : 12}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${cls === 'toc-chevron-icon' ? 2 : 2.5}" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>`;

// "Last updated" in the builder's local time, e.g. 9/30/26 2:05pm.
function formatDate(iso) {
  const date = new Date(iso);
  const h = date.getHours();
  const min = String(date.getMinutes()).padStart(2, '0');
  return `${date.getMonth() + 1}/${date.getDate()}/${String(date.getFullYear()).slice(2)} ${h % 12 || 12}:${min}${h >= 12 ? 'pm' : 'am'}`;
}

// The open page's headings under its sidebar link: h2s, each with a collapsible list of its h3s.
function buildToc(headings) {
  if (headings.length <= 1) return '';
  const sections = [];
  for (const h of headings) {
    if (h.depth === 2) sections.push({ ...h, children: [] });
    else if (sections.length) sections[sections.length - 1].children.push(h);
  }
  let inner = '';
  sections.forEach((s, i) => {
    if (s.children.length) {
      inner += `<div class="toc-section">
            <div class="toc-heading">
              <a href="#${s.id}" class="toc-link">${s.text}</a>
              <button class="toc-chevron" aria-expanded="false" data-toc="${i}">${chevron('toc-chevron-icon')}</button>
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

function buildNav(page, root, tocHtml) {
  const navLink = ({ label, href }) => {
    const link = `<a href="${root}${href}"${href === page.href ? ' class="active"' : ''}>${label}</a>`;
    return href === page.href && tocHtml ? link + '\n          ' + tocHtml : link;
  };
  // Restricted groups show only on restricted pages; everyone else gets them from the worker.
  // Groups start open so every page is in view; readers can collapse any of them.
  // A "###" group (it has `parent`) is drawn inside its "##" group, after that group's own links.
  const shown = wiki.nav.filter(g => !g.restricted || page.restricted);
  const names = new Set(shown.map(g => g.name));
  const drawGroup = group => {
    const children = shown.filter(c => c.parent && c.parent === group.name).map(drawGroup);
    const links = [...group.links.map(navLink), ...children].join('\n            ');
    if (!group.name) return links;
    return `<div class="nav-project">
          <button class="nav-project-toggle" aria-expanded="true">${chevron('nav-project-chevron')}<span>${group.name}</span></button>
          <div class="nav-project-links">
            ${links}
          </div>
        </div>`;
  };
  // A sub-group whose parent isn't shown here (e.g. a hidden restricted parent) is drawn on its own.
  return shown.filter(g => !g.parent || !names.has(g.parent)).map(drawGroup).join('\n          ');
}

function renderPage(page) {
  // Sidebar, Home and search links are written from the wiki root; a page in a folder needs "../".
  const root = '../'.repeat(page.href.split('/').length - 1);
  const isIndex = page.href === 'index.html';
  const tocHtml = buildToc(page.headings);
  const nav = buildNav(page, root, tocHtml);
  // With project groups, Home's own headings would just repeat the group names.
  const indexToc = isIndex && !hasProjects ? tocHtml : '';
  const privateNav = !hasRestricted ? null : page.restricted ? 'search' : 'all';
  const title = isIndex ? wiki.title : `${page.title} · ${wiki.title}`;
  const content = page.html.replace(/<\/h1>/, `</h1>\n        <div class="last-updated">Last updated ${formatDate(page.updated)}</div>`);
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>${escapeHtml(title)}</title>
  <script>try { if (localStorage.getItem('wiki-sidebar') === 'collapsed') document.documentElement.classList.add('sidebar-collapsed'); } catch (e) {}</script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="${root}wiki.css">
</head>
<body>
  <button class="nav-toggle" aria-label="Toggle navigation">Menu</button>
  <!-- Lucide panel-left (collapse) / panel-right (expand) -->
  <button class="sidebar-collapse" id="sidebar-collapse" aria-controls="sidebar" aria-expanded="true" aria-label="Collapse sidebar" title="Collapse sidebar"><svg class="icon-collapse" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/></svg><svg class="icon-expand" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/></svg></button>
  <div class="overlay" id="overlay"></div>
  <div class="layout">
    <nav class="sidebar" id="sidebar">
      <div class="sidebar-title">${escapeHtml(wiki.title)}</div>
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
        ${content}
      </article>
    </main>
  </div>
  <script>window.WIKI = ${JSON.stringify({ root, privateNav })};</script>
  <script src="${root}wiki.js"></script>
</body>
</html>`;
}

const write = (rel, text) => {
  const dest = join(outDir, rel);
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, text);
};

for (const page of wiki.pages) {
  write(page.href, renderPage(page));
  console.log(`  ${page.source} → ${page.href}`);
}
for (const img of wiki.assets) {
  mkdirSync(dirname(join(outDir, img)), { recursive: true });
  copyFileSync(join(bundleDir, 'files', img), join(outDir, img));
  console.log(`  ${img} (image)`);
}
copyFileSync(join(here, 'wiki.css'), join(outDir, 'wiki.css'));
copyFileSync(join(here, 'wiki.js'), join(outDir, 'wiki.js'));
const withoutFlag = ({ restricted, ...entry }) => entry;
write('search.json', JSON.stringify(search.filter(e => !e.restricted).map(withoutFlag)));
write('robots.txt', 'User-agent: *\nDisallow: /\n');

if (wiki.redirects.length) {
  write('_redirects', wiki.redirects.map(r => `${r.from} ${r.to} 301`).join('\n') + '\n');
  console.log(`  _redirects (${wiki.redirects.length} rules for pages moved into project folders)`);
}

// Restricted folders: the pages are published (a path-scoped Access app guards them) and the
// worker serves their menus and search entries to the people on the allow list only.
if (hasRestricted) {
  if (!wiki.access) {
    console.error('Restricted folders need Access settings: .claude/wiki-access.json ({ "team": ..., "auds": [...] }), or parse with --access <file>');
    process.exit(1);
  }
  const privateGroups = wiki.nav.filter(g => g.restricted).map(g => {
    const folder = g.links[0].href.split('/')[0];
    return {
      allow: wiki.restricted.find(r => r.folder === folder)?.allow ?? [],
      group: { name: g.name, links: g.links },
      search: search.filter(e => e.restricted && e.href.startsWith(folder + '/')).map(withoutFlag),
    };
  });
  const redirectMap = Object.fromEntries(wiki.redirects.map(r => [r.from, r.to]));
  write('_worker.js', workerSource(redirectMap, privateGroups, wiki.access));
  console.log(`  _worker.js (serves /private/nav.json for: ${privateGroups.map(g => `${g.group.name} → ${g.allow.join(', ')}`).join('; ')})`);
}

console.log(`\nBuilt ${wiki.pages.length} pages → ${outDir}`);
