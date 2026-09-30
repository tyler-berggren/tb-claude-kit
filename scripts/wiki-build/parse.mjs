import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, existsSync, statSync } from 'fs';
import { join, dirname, basename, resolve } from 'path';
import { marked } from 'marked';

// Step 1 of the wiki build: read wiki/*.md and write a "bundle" that any renderer can turn into a site.
//
// Usage: node parse.mjs <wiki-dir> <bundle-dir> [--title "Wiki title"] [--access path/to/access.json]
//   --title   the wiki's name (default: the README's first heading)
//   --access  Cloudflare Access settings for restricted folders (default: .claude/wiki-access.json in the cwd)
//
// The bundle holds wiki.json (every page as HTML, the sidebar, redirects, restricted folders),
// search.json (plain text of every page) and files/ (the images pages use). The format is
// documented in the kit README ("wiki.json format") and versioned by FORMAT below: bump it on any
// change a renderer could trip over, so renderers can refuse a format they don't know.
export const FORMAT = 1;

const args = process.argv.slice(2);
function takeFlag(name) {
  const i = args.indexOf(name);
  return i === -1 ? null : args.splice(i, 2)[1] ?? null;
}
const titleFlag = takeFlag('--title');
const accessFlag = takeFlag('--access');
const wikiDir = resolve(args[0] || 'wiki');
const bundleDir = resolve(args[1] || '_wiki-bundle');

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
if (!mdFiles.length) {
  console.error('No markdown files found in wiki directory');
  process.exit(1);
}

// A top-level folder holding RESTRICTED.txt is only for the people it lists ("allow:" lines).
// Its pages are flagged restricted; what a renderer does with that is the renderer's business.
const restrictedDirs = new Set(
  readdirSync(wikiDir, { withFileTypes: true })
    .filter(e => e.isDirectory() && existsSync(join(wikiDir, e.name, 'RESTRICTED.txt')))
    .map(e => e.name)
);
const isRestricted = f => f.includes('/') && restrictedDirs.has(f.split('/')[0]);

// The README is the index. Its first heading names the wiki; its links, grouped under the
// "## Heading" they sit beneath, become the sidebar. Links above the first heading stay ungrouped.
// A "### Heading" is a group inside the "##" group above it: it gets `parent` (that group's name).
// Renderers that don't read `parent` still draw every group, just side by side, so FORMAT stays 1.
const readme = existsSync(join(wikiDir, 'README.md')) ? readFileSync(join(wikiDir, 'README.md'), 'utf-8') : '';
const readmeTitle = readme.match(/^#\s+(.+)$/m)?.[1]?.trim() || 'Wiki';
const navGroups = [{ name: null, links: [] }];
let parentGroup = null;
for (const line of readme.split('\n')) {
  const heading = line.match(/^(###?)\s+(.+)$/);
  if (heading) {
    const name = heading[2].trim();
    if (heading[1] === '##') {
      parentGroup = name;
      navGroups.push({ name, links: [] });
    } else {
      navGroups.push(parentGroup ? { name, parent: parentGroup, links: [] } : { name, links: [] });
    }
    continue;
  }
  for (const [, label, href] of line.matchAll(/\[([^\]]+)\]\(([^)]+\.md)\)/g)) {
    if (!SKIP.has(href)) navGroups[navGroups.length - 1].links.push({ label, href: href.replace(/\.md$/, '.html') });
  }
}
// A "##" group with no links of its own stays when one of its "###" groups has some.
const nav = navGroups
  .filter(g => g.links.length || navGroups.some(c => c.parent === g.name && c.links.length))
  .map(g => ({ ...g, restricted: g.links.every(l => isRestricted(l.href)) }));
const restrictedNames = new Set(nav.filter(g => g.restricted).map(g => g.name));

// Page source, except that the shared Home page loses restricted projects' sections.
function pageSource(mdFile) {
  const src = readFileSync(join(wikiDir, mdFile), 'utf-8');
  if (mdFile !== 'README.md' || !restrictedNames.size) return src;
  let skipping = false;
  let parentSkipping = false; // a "###" section inside a restricted "##" one goes too
  return src.split('\n').filter(line => {
    const h = line.match(/^(###?)\s+(.+)$/);
    if (h && h[1] === '##') skipping = parentSkipping = restrictedNames.has(h[2].trim());
    else if (h) skipping = parentSkipping || restrictedNames.has(h[2].trim());
    return !skipping;
  }).join('\n');
}

function slugify(text) {
  return text.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^\w\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-').trim();
}

// Images referenced in markdown, relative to the wiki root; and the folder of the page being
// parsed, so image paths resolve relative to that page.
const images = new Set();
let currentPageDir = '.';

// Rewrite .md links to .html, track image references, give h1-h3 anchors.
marked.use({
  renderer: {
    heading({ tokens, depth }) {
      const text = this.parser.parseInline(tokens);
      if (depth > 3) return `<h${depth}>${text}</h${depth}>\n`;
      return `<h${depth} id="${slugify(text.replace(/<[^>]+>/g, ''))}">${text}</h${depth}>\n`;
    },
    link({ href, title, tokens }) {
      if (href && !href.startsWith('http') && /\.md(#.*)?$/.test(href)) {
        href = href.replace(/(^|\/)README\.md(?=#|$)/, '$1index.html').replace(/\.md(?=#|$)/, '.html');
      }
      const text = this.parser.parseInline(tokens);
      return `<a href="${href}"${title ? ` title="${title}"` : ''}>${text}</a>`;
    },
    image({ href, title, text }) {
      if (href && !href.startsWith('http')) images.add(join(currentPageDir, href));
      return `<img src="${href}" alt="${text || ''}"${title ? ` title="${title}"` : ''}>`;
    }
  }
});

const htmlFilename = f => (f === 'README.md' ? 'index.html' : f.replace(/\.md$/, '.html'));

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

function extractHeadings(html) {
  return [...html.matchAll(/<h([23])\s+id="([^"]+)">(.+?)<\/h[23]>/g)]
    .map(m => ({ depth: Number(m[1]), id: m[2], text: m[3].replace(/<[^>]+>/g, '') }));
}

const pages = mdFiles.map(mdFile => {
  const src = pageSource(mdFile);
  currentPageDir = dirname(mdFile);
  const html = marked.parse(src);
  return {
    source: mdFile,
    href: htmlFilename(mdFile),
    title: src.match(/^#\s+(.+)$/m)?.[1]?.trim() || basename(mdFile, '.md'),
    html,
    headings: extractHeadings(html),
    updated: statSync(join(wikiDir, mdFile)).mtime.toISOString(),
    restricted: isRestricted(mdFile),
  };
});

const search = pages.map(p => ({ title: p.title, href: p.href, text: stripHtml(p.html).toLowerCase(), restricted: p.restricted }));

// Pages moved into project folders on 2026-09-11, so links made before then (bookmarks, links
// from other apps) still land. Pages hosts serve "/page.html" as "/page", so both old forms redirect.
const rootNames = new Set(mdFiles.filter(f => !f.includes('/')).map(f => basename(f, '.md')));
const redirects = mdFiles
  .filter(f => f.includes('/') && !isRestricted(f) && !rootNames.has(basename(f, '.md')))
  .flatMap(f => {
    const name = basename(f, '.md');
    const to = '/' + f.replace(/\.md$/, '');
    return [{ from: `/${name}`, to }, { from: `/${name}.html`, to }];
  });

// Restricted folders: who may see each one, from its RESTRICTED.txt.
const restricted = [...restrictedDirs].sort().map(folder => {
  const allow = [...readFileSync(join(wikiDir, folder, 'RESTRICTED.txt'), 'utf-8').matchAll(/^allow:\s*(\S+@\S+)\s*$/gmi)]
    .map(m => m[1].toLowerCase());
  if (!allow.length) {
    console.error(`${folder}/RESTRICTED.txt has no "allow:" lines`);
    process.exit(1);
  }
  return { folder, allow };
});

// Access settings travel with the bundle so a renderer can check who a reader is.
// Per-project settings live with the project, not beside this (shared) script.
let access = null;
const accessPath = resolve(accessFlag || join('.claude', 'wiki-access.json'));
if (existsSync(accessPath)) {
  const { team, auds } = JSON.parse(readFileSync(accessPath, 'utf-8'));
  access = { team, auds };
}

mkdirSync(bundleDir, { recursive: true });
const assets = [];
for (const img of images) {
  const from = join(wikiDir, img);
  if (!existsSync(from)) continue;
  const to = join(bundleDir, 'files', img);
  mkdirSync(dirname(to), { recursive: true });
  copyFileSync(from, to);
  assets.push(img);
}

const wiki = {
  format: FORMAT,
  title: titleFlag || readmeTitle,
  generatedAt: new Date().toISOString(),
  pages: pages.map(({ source, ...p }) => ({ ...p, source })),
  nav,
  redirects,
  restricted,
  access,
  assets: assets.sort(),
};
writeFileSync(join(bundleDir, 'wiki.json'), JSON.stringify(wiki, null, 1));
writeFileSync(join(bundleDir, 'search.json'), JSON.stringify(search));
console.log(`Parsed ${pages.length} pages, ${assets.length} images → ${bundleDir}`);
