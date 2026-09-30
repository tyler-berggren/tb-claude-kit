import { mkdtempSync, rmSync } from 'fs';
import { join, dirname, resolve } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';
import { spawnSync } from 'child_process';

// Builds a wiki site in two steps: parse.mjs turns wiki/*.md into a bundle (wiki.json, search.json,
// images), then a renderer turns the bundle into the site. This is the command /wiki deploy runs.
//
// Usage: node build.mjs <wiki-dir> <out-dir> [--title "Wiki title"] [--access file] [--renderer "command"]
//   --title     the wiki's name (default: the README's first heading)
//   --access    Cloudflare Access settings for restricted folders (default: .claude/wiki-access.json)
//   --renderer  a command that renders the bundle instead of the plain renderer (kit.json
//               "wiki.renderer"). It is run from the current directory with two arguments added:
//               the bundle directory and the output directory.
const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
function takeFlag(name) {
  const i = args.indexOf(name);
  return i === -1 ? null : args.splice(i, 2)[1] ?? null;
}
const renderer = takeFlag('--renderer');
const passFlags = ['--title', '--access'].flatMap(f => {
  const v = takeFlag(f);
  return v === null ? [] : [f, v];
});
const wikiDir = resolve(args[0] || 'wiki');
const outDir = resolve(args[1] || join(dirname(wikiDir), '_wiki-site'));
const quote = s => `'${String(s).replace(/'/g, `'\\''`)}'`;

const bundleDir = mkdtempSync(join(tmpdir(), 'wiki-bundle-'));
let status = spawnSync(process.execPath, [join(here, 'parse.mjs'), wikiDir, bundleDir, ...passFlags], { stdio: 'inherit' }).status;
if (status === 0) {
  status = renderer
    ? spawnSync(`${renderer} ${quote(bundleDir)} ${quote(outDir)}`, { stdio: 'inherit', shell: true }).status
    : spawnSync(process.execPath, [join(here, 'render.mjs'), bundleDir, outDir], { stdio: 'inherit' }).status;
}
rmSync(bundleDir, { recursive: true, force: true });
process.exit(status ?? 1);
