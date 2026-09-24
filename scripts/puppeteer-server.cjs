/**
 * A JSON-over-HTTP bridge to a Chrome driven by Puppeteer. Two modes:
 *
 * Visible (the default): the co-browser. Opens a real Chrome window that the
 * human drives, keeps a persistent profile in ~/.claude-chrome/<profile>, and
 * registers itself in ~/.claude-chrome-registry.json so tools can find its
 * port by profile name (the project directory's name unless --profile says).
 *
 *   node scripts/puppeteer-server.cjs [--profile <name>] [--port <n>] [start-url]
 *
 * Headless (--headless): for a coding agent verifying a UI on its own, without
 * touching the human's browser. Any number can run at once. Each gets a
 * throwaway Chrome profile in a fresh temp directory (deleted on exit), a
 * fixed 1440x900 viewport, and its own port: --port exactly if given (it exits
 * if that port is taken), otherwise one the OS picks. It never reads or writes
 * the registry. Instead it prints exactly one JSON line to stdout once it is
 * listening, which is how the caller learns the port:
 *
 *   node scripts/puppeteer-server.cjs --headless [--port <n>] [start-url]
 *   {"headless":true,"port":54321,"pid":123,"userDataDir":"/.../claude-chrome-headless-123-AbC"}
 *
 * Everything else it says goes to stderr. Stop it with SIGTERM or SIGINT
 * (`kill <pid>`) so it can remove its profile; one killed with -9 leaves the
 * directory behind, and the next headless instance to start removes it.
 *
 * Commands: POST http://127.0.0.1:<port> with a JSON body {"command": ...}.
 * Any response carrying an "error" key is a failure. The interaction commands
 * and `errors` also answer failures with a non-200 status (400 bad request,
 * 404 nothing matched, 408 timed out, 409 matched but unusable, 502 the
 * navigation failed); the older commands answer theirs with 200.
 *
 *   inspect    {selector}                   computed styles and box model
 *   dom        {selector, children?}        outerHTML, attributes, children
 *   screenshot {selector?}                  PNG in the temp dir -> {path}
 *   eval       {expression}                 run JS in the page -> {result}
 *   status     {}           (or GET /status) url, title, viewport, scroll, port
 *   viewport   {width, height?, deviceScaleFactor?, isMobile?} pins a size;
 *              {width: null} follows the window again (headless: back to 1440x900)
 *   console    {filter?, limit?, clear?}  (or GET /console) captured messages
 *   errors     {clear?}                     console errors, uncaught page errors,
 *              and failed or 4xx/5xx requests since the last goto
 *   goto       {url, waitUntil?, timeout?}  -> {url, status, title}
 *   click      {selector} | {text} | {selector, text}  -> {clicked, matches}
 *   type       {selector, text, clear?}     -> {typed, value, into}
 *   press      {key}  e.g. "Escape", "Enter", "Shift+Tab"  -> {pressed, focused}
 *   waitFor    {selector, hidden?, timeout?}  -> {ok: true, ...}
 *
 * The interaction commands (goto, click, type, press) work in both modes;
 * using them on a window the human is driving is the caller's call to avoid.
 */

const http = require('http');
const path = require('path');
const os = require('os');
const fs = require('fs');

// puppeteer is resolved from the invoking PROJECT, not from this file's
// location. In outside-repo mode this script is a symlink into the kit
// checkout, and Node resolves require() against a module's realpath — so a
// bare require('puppeteer') searches the kit for node_modules and fails,
// even though the project that invoked it has puppeteer installed.
// (Callers could pass --preserve-symlinks --preserve-symlinks-main instead,
// but both flags are needed and it is easy to get wrong, so fix it here.)
function requireFromProject(name) {
  const paths = [process.cwd(), __dirname];
  try {
    return require(require.resolve(name, { paths }));
  } catch (err) {
    if (err.code !== 'MODULE_NOT_FOUND') throw err;
    console.error(`Cannot find module '${name}'.`);
    console.error(`Looked in: ${paths.join(', ')}`);
    console.error(`Install it in the project you are running from:  npm i -D ${name}`);
    process.exit(1);
  }
}

const puppeteer = requireFromProject('puppeteer');

const REGISTRY_PATH = path.join(os.homedir(), '.claude-chrome-registry.json');
const BASE_PORT = 9615;
const MAX_PORT_SCAN = 20;
const CONSOLE_MAX = 500;
const consoleLogs = [];

// Headless has no window for the page to follow, so it holds a fixed size.
const HEADLESS_VIEWPORT = { width: 1440, height: 900 };
const HEADLESS_DIR_PREFIX = 'claude-chrome-headless-';
const GOTO_TIMEOUT = 30000;
const WAIT_TIMEOUT = 10000;
const MAX_TIMEOUT = 120000;
const WAIT_UNTIL = ['load', 'domcontentloaded', 'networkidle0', 'networkidle2'];

// What `errors` reports besides console errors. Those are not copied here:
// `errors` reads them out of consoleLogs, from errorsSince onwards.
const pageErrors = [];
const networkErrors = [];
let errorsSince = Date.now();

let browser = null;
let page = null;
let assignedPort = null;

// A failure to report to the caller, with the HTTP status its response goes
// out with. The interaction commands throw these; the older commands return
// {error} objects, which still go out as 200s.
class CommandError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

function parseArgs(argv) {
  const args = { port: null, profile: null, url: null, headless: false };
  let i = 2;
  while (i < argv.length) {
    if (argv[i] === '--headless') {
      args.headless = true;
      i++;
    } else if (argv[i] === '--port' && argv[i + 1]) {
      args.port = parseInt(argv[i + 1], 10);
      i += 2;
    } else if (argv[i] === '--profile' && argv[i + 1]) {
      args.profile = argv[i + 1];
      i += 2;
    } else if (!argv[i].startsWith('--')) {
      args.url = argv[i];
      i++;
    } else {
      i++;
    }
  }
  return args;
}

function readRegistry() {
  try {
    const data = fs.readFileSync(REGISTRY_PATH, 'utf8');
    const entries = JSON.parse(data);
    return entries.filter(e => {
      try { process.kill(e.pid, 0); return true; } catch { return false; }
    });
  } catch {
    return [];
  }
}

function writeRegistry(entries) {
  fs.writeFileSync(REGISTRY_PATH, JSON.stringify(entries, null, 2));
}

function registerInstance(entry) {
  const entries = readRegistry().filter(e => e.profile !== entry.profile);
  entries.push(entry);
  writeRegistry(entries);
}

function unregisterInstance(profile) {
  const entries = readRegistry().filter(e => e.profile !== profile);
  writeRegistry(entries);
}

function isPortFree(port) {
  return new Promise(resolve => {
    const s = require('net').createServer();
    s.once('error', () => resolve(false));
    s.once('listening', () => { s.close(); resolve(true); });
    s.listen(port, '127.0.0.1');
  });
}

async function findFreePort(preferred) {
  if (preferred && await isPortFree(preferred)) return preferred;
  for (let offset = 0; offset < MAX_PORT_SCAN; offset++) {
    const p = BASE_PORT + offset;
    if (await isPortFree(p)) return p;
  }
  throw new Error(`No free port found in range ${BASE_PORT}-${BASE_PORT + MAX_PORT_SCAN - 1}`);
}

function defaultProfile() {
  return path.basename(process.cwd());
}

function removeDir(dir) {
  try { fs.rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 50 }); } catch {}
}

// An instance killed with -9 cannot clean up after itself, so each new
// headless instance removes the profiles of instances whose process is gone.
// The directory name carries the owner's pid for exactly this.
function sweepStaleProfiles() {
  let names = [];
  try { names = fs.readdirSync(os.tmpdir()); } catch { return; }
  for (const name of names) {
    if (!name.startsWith(HEADLESS_DIR_PREFIX)) continue;
    const pid = parseInt(name.slice(HEADLESS_DIR_PREFIX.length), 10);
    if (!pid) continue;
    try { process.kill(pid, 0); } catch (e) {
      if (e.code === 'ESRCH') removeDir(path.join(os.tmpdir(), name));
    }
  }
}

// A fresh profile per headless instance: Chrome locks a profile while it
// runs, so sharing the project's would collide with the visible browser and
// with every other headless instance.
function makeThrowawayProfile() {
  sweepStaleProfiles();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `${HEADLESS_DIR_PREFIX}${process.pid}-`));
  // 'exit' fires on every way out that still runs JS: our own process.exit,
  // puppeteer's SIGINT handler (which exits 130), a crash, or a clean drain.
  // Chrome is killed first so it cannot recreate files under the rm.
  process.on('exit', () => {
    const proc = browser && browser.process();
    if (proc && proc.pid && proc.exitCode === null && proc.signalCode === null) {
      try { process.kill(-proc.pid, 'SIGKILL'); } catch {
        try { proc.kill('SIGKILL'); } catch {}
      }
    }
    removeDir(dir);
  });
  return dir;
}

const cliArgs = parseArgs(process.argv);
const HEADLESS = cliArgs.headless;
// A headless instance has no profile name: it is never registered, and its
// Chrome data is thrown away with it.
const PROFILE = HEADLESS ? null : (cliArgs.profile || defaultProfile());
const USER_DATA_DIR = HEADLESS ? makeThrowawayProfile() : path.join(os.homedir(), '.claude-chrome', PROFILE);
const DEFAULT_URL = cliArgs.url || null;
// Headless keeps stdout for its one JSON line; everything else goes to stderr.
const log = (...args) => (HEADLESS ? console.error : console.log)(...args);

function pushCapped(list, entry) {
  list.push(entry);
  if (list.length > CONSOLE_MAX) list.shift();
}

function resetErrors() {
  errorsSince = Date.now();
  pageErrors.length = 0;
  networkErrors.length = 0;
}

async function launchBrowser() {
  fs.mkdirSync(USER_DATA_DIR, { recursive: true });

  const args = [
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-default-apps',
  ];
  browser = await puppeteer.launch(HEADLESS
    // pipe: Chrome talks over stdio rather than a DevTools port, so a
    // headless instance opens no port besides ours, and Chrome exits with
    // this process even when it is killed with -9.
    ? { headless: true, pipe: true, defaultViewport: HEADLESS_VIEWPORT, userDataDir: USER_DATA_DIR, args }
    : { headless: false, defaultViewport: null, userDataDir: USER_DATA_DIR, args });

  const pages = await browser.pages();
  page = pages[0] || await browser.newPage();

  // Capture before the start URL loads, so its errors are not missed.
  const setupCapture = (p) => {
    p.on('console', (msg) => {
      pushCapped(consoleLogs, { type: msg.type(), text: msg.text(), ts: Date.now() });
    });
    p.on('pageerror', (err) => {
      const stack = err && err.stack ? String(err.stack).split('\n').slice(0, 6).join('\n') : undefined;
      pushCapped(pageErrors, { message: err && err.message ? err.message : String(err), stack, ts: Date.now() });
    });
    p.on('requestfailed', (req) => {
      const failure = (req.failure() && req.failure().errorText) || 'failed';
      // Cancellations, not failures: a navigation cancels the old page's
      // in-flight requests, and apps abort fetches on purpose.
      if (failure === 'net::ERR_ABORTED') return;
      pushCapped(networkErrors, {
        method: req.method(), url: req.url(), failure, resourceType: req.resourceType(), ts: Date.now(),
      });
    });
    p.on('response', (res) => {
      if (res.status() < 400) return;
      pushCapped(networkErrors, {
        method: res.request().method(), url: res.url(), status: res.status(), statusText: res.statusText(),
        resourceType: res.request().resourceType(), ts: Date.now(),
      });
    });
  };
  setupCapture(page);
  browser.on('targetcreated', async (target) => {
    if (target.type() === 'page') {
      const newPage = await target.page();
      if (newPage) setupCapture(newPage);
    }
  });

  if (DEFAULT_URL) {
    try {
      await page.goto(DEFAULT_URL, { waitUntil: 'domcontentloaded', timeout: 5000 });
    } catch {
      // Target might not be up yet — user will navigate
    }
  }

  browser.on('disconnected', () => {
    log('Browser disconnected, shutting down.');
    shutdown();
  });
}

async function getActivePage() {
  const pages = await browser.pages();
  return pages[pages.length - 1] || page;
}

async function handleInspect(selector) {
  const p = await getActivePage();
  const result = await p.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return { error: `No element found for selector: ${sel}` };

    const computed = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();

    const props = [
      'display', 'position', 'width', 'height', 'min-width', 'min-height',
      'max-width', 'max-height', 'padding-top', 'padding-right', 'padding-bottom',
      'padding-left', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
      'font-size', 'line-height', 'font-weight', 'font-family',
      'overflow', 'overflow-x', 'overflow-y',
      'flex-direction', 'flex-wrap', 'justify-content', 'align-items', 'gap',
      'grid-template-columns', 'grid-template-rows',
      'z-index', 'opacity', 'visibility',
      'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width',
      'box-sizing', 'text-align', 'white-space', 'word-break',
      'background-color', 'color',
    ];

    const styles = {};
    for (const prop of props) {
      const val = computed.getPropertyValue(prop);
      if (val && val !== 'none' && val !== 'normal' && val !== 'auto' && val !== '0px'
          && val !== 'visible' && val !== 'static' && val !== 'start') {
        styles[prop] = val;
      }
    }

    styles['display'] = computed.getPropertyValue('display');
    styles['position'] = computed.getPropertyValue('position');
    styles['width'] = computed.getPropertyValue('width');
    styles['height'] = computed.getPropertyValue('height');
    styles['overflow'] = computed.getPropertyValue('overflow');
    styles['overflow-x'] = computed.getPropertyValue('overflow-x');
    styles['overflow-y'] = computed.getPropertyValue('overflow-y');

    return {
      selector: sel,
      tagName: el.tagName.toLowerCase(),
      className: el.className,
      id: el.id || undefined,
      boundingRect: {
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      },
      computedStyles: styles,
      childCount: el.children.length,
      textContent: el.textContent?.substring(0, 200)?.trim() || '',
    };
  }, selector);

  return result;
}

async function handleDom(selector, options = {}) {
  const p = await getActivePage();
  const result = await p.evaluate((sel, opts) => {
    const el = document.querySelector(sel);
    if (!el) return { error: `No element found for selector: ${sel}` };

    const data = {
      selector: sel,
      tagName: el.tagName.toLowerCase(),
      id: el.id || undefined,
      className: el.className,
      attributes: {},
      childCount: el.children.length,
      textContent: el.textContent?.substring(0, 500)?.trim() || '',
      outerHTML: el.outerHTML.substring(0, 2000),
    };

    for (const attr of el.attributes) {
      if (attr.name !== 'class' && attr.name !== 'id') {
        data.attributes[attr.name] = attr.value.substring(0, 200);
      }
    }

    if (opts.children) {
      data.children = Array.from(el.children).map(child => ({
        tagName: child.tagName.toLowerCase(),
        id: child.id || undefined,
        className: child.className,
        textContent: child.textContent?.substring(0, 100)?.trim() || '',
      }));
    }

    return data;
  }, selector, options);

  return result;
}

async function handleScreenshot(selector) {
  const p = await getActivePage();
  const timestamp = Date.now();
  const filePath = path.join(os.tmpdir(), `puppeteer-screenshot-${timestamp}.png`);

  if (selector) {
    const el = await p.$(selector);
    if (!el) return { error: `No element found for selector: ${selector}` };
    await el.screenshot({ path: filePath });
  } else {
    await p.screenshot({ path: filePath });
  }

  return { path: filePath };
}

async function handleEval(expression) {
  const p = await getActivePage();
  const result = await p.evaluate((expr) => {
    try {
      const val = eval(expr);
      return { result: typeof val === 'object' ? JSON.stringify(val) : String(val) };
    } catch (e) {
      return { error: e.message };
    }
  }, expression);

  return result;
}

async function handleStatus() {
  const p = await getActivePage();
  const viewport = p.viewport();
  const result = await p.evaluate(() => ({
    url: window.location.href,
    title: document.title,
    viewportWidth: window.innerWidth,
    viewportHeight: window.innerHeight,
    devicePixelRatio: window.devicePixelRatio,
    scrollX: Math.round(window.scrollX),
    scrollY: Math.round(window.scrollY),
    documentHeight: document.documentElement.scrollHeight,
  }));

  return {
    ...result,
    profile: PROFILE,
    port: assignedPort,
    puppeteerViewport: viewport,
    ...(HEADLESS ? { headless: true, userDataDir: USER_DATA_DIR } : {}),
  };
}

/**
 * Set (or clear) an explicit viewport, for checking a responsive layout at a
 * width nobody's monitor is. `{ width: null }` hands the page back to the real
 * window, which is how the browser normally runs here (`defaultViewport: null`).
 */
async function handleViewport(body) {
  const p = await getActivePage();
  if (body.width === null && HEADLESS) {
    await p.setViewport(HEADLESS_VIEWPORT);
    return { viewport: p.viewport(), note: 'headless default restored' };
  }
  if (body.width === null) {
    await p.setViewport(null);
    return { viewport: null, note: 'following the window again' };
  }
  const width = Number(body.width);
  const height = Number(body.height ?? 844);
  if (!Number.isFinite(width) || width < 200) {
    return { error: 'viewport requires a width of at least 200, or width: null to reset' };
  }
  await p.setViewport({
    width,
    height,
    deviceScaleFactor: Number(body.deviceScaleFactor ?? 2),
    isMobile: !!body.isMobile,
    hasTouch: !!body.isMobile,
  });
  return { viewport: p.viewport() };
}

function timeoutFrom(value, fallback) {
  const n = Number(value);
  if (value == null || !Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(n, MAX_TIMEOUT);
}

// Absolute URLs pass through; a path resolves against the current page.
function resolveUrl(url, base) {
  if (/^[a-z][a-z\d+.-]*:/i.test(url)) return url;
  if (!/^https?:/i.test(base)) {
    throw new CommandError(`"${url}" is relative and the page has no http(s) URL to resolve it against`);
  }
  return new URL(url, base).href;
}

async function handleGoto(body) {
  if (!body.url || typeof body.url !== 'string') throw new CommandError('goto requires a url');
  const waitUntil = body.waitUntil || 'networkidle2';
  if (!WAIT_UNTIL.includes(waitUntil)) throw new CommandError(`waitUntil must be one of: ${WAIT_UNTIL.join(', ')}`);
  const timeout = timeoutFrom(body.timeout, GOTO_TIMEOUT);
  const p = await getActivePage();
  const url = resolveUrl(body.url, p.url());

  resetErrors();
  let response;
  try {
    response = await p.goto(url, { waitUntil, timeout });
  } catch (e) {
    if (e.name === 'TimeoutError') {
      throw new CommandError(`goto timed out after ${timeout}ms waiting for ${waitUntil} (page is at ${p.url()}); `
        + 'a page that holds connections open may need waitUntil "load"', 408);
    }
    throw new CommandError(`goto ${url} failed: ${e.message}`, 502);
  }
  return { url: p.url(), status: response ? response.status() : null, title: await p.title() };
}

// Runs in the page. Finds the element `click` and `type` act on and returns
// {el, visible, total}. A selector alone means its first visible match. A
// text means the innermost element whose text, aria-label or button-input
// value contains it (case and whitespace ignored), lifted to its nearest
// clickable ancestor, so {text: "Save"} lands on the <button> rather than the
// <span> inside it or the <main> around it; an exact match beats a partial
// one. With both, each selector match is a scope to look for the text in.
function pickTarget(selector, text) {
  const CLICKABLE = 'a[href], button, input, select, textarea, summary, label, [onclick], '
    + '[role=button], [role=link], [role=menuitem], [role=menuitemcheckbox], [role=menuitemradio], '
    + '[role=option], [role=tab], [role=checkbox], [role=radio], [role=switch], [role=treeitem]';
  const norm = (s) => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const want = norm(text);
  const labels = (el) => [
    el.textContent,
    el.getAttribute('aria-label'),
    el.matches('input[type=button], input[type=submit], input[type=reset]') ? el.value : null,
  ];
  const contains = (el) => labels(el).some((s) => norm(s).includes(want));
  const equals = (el) => labels(el).some((s) => norm(s) === want);
  const isVisible = (el) => {
    const r = el.getBoundingClientRect();
    if (!r.width || !r.height) return false;
    return !el.checkVisibility || el.checkVisibility({ visibilityProperty: true, checkVisibilityCSS: true });
  };

  const roots = selector ? Array.from(document.querySelectorAll(selector)) : [document.documentElement];
  let found = roots;
  if (want) {
    found = [];
    for (const root of roots) {
      for (const el of [root, ...root.querySelectorAll('*')]) {
        if (el.closest('head, script, style, noscript, template')) continue;
        if (!contains(el) || Array.from(el.children).some(contains)) continue;
        const up = el.closest(CLICKABLE);
        found.push(up && root.contains(up) ? up : el);
      }
    }
    found = Array.from(new Set(found));
  }
  const shown = found.filter(isVisible);
  const el = (want && shown.find(equals)) || shown[0] || null;
  return { el, visible: shown.length, total: found.length };
}

// Runs in the page: a short account of one element, for responses.
function describeElement(n) {
  if (!n || n.nodeType !== 1) return null;
  const out = { tag: n.tagName.toLowerCase() };
  if (n.id) out.id = n.id;
  const role = n.getAttribute('role');
  if (role) out.role = role;
  const text = String(n.innerText || n.getAttribute('aria-label')
    || (typeof n.value === 'string' ? n.value : '') || n.getAttribute('placeholder') || '')
    .replace(/\s+/g, ' ').trim();
  if (text) out.text = text.length > 80 ? `${text.slice(0, 77)}...` : text;
  if (n.disabled || n.getAttribute('aria-disabled') === 'true') out.disabled = true;
  return out;
}

async function describeHandle(handle) {
  try { return await handle.evaluate(describeElement); } catch { return null; }
}

async function findTarget(p, selector, text) {
  let found;
  try {
    found = await p.evaluateHandle(pickTarget, selector || null, text || null);
  } catch (e) {
    throw new CommandError(e.message); // an invalid selector lands here
  }
  const el = (await found.getProperty('el')).asElement();
  const visible = await (await found.getProperty('visible')).jsonValue();
  const total = await (await found.getProperty('total')).jsonValue();
  await found.dispose();
  if (!el) {
    const what = [selector && `selector ${JSON.stringify(selector)}`, text && `text ${JSON.stringify(text)}`]
      .filter(Boolean).join(' and ');
    throw new CommandError(total ? `${total} element(s) match ${what}, but none is visible` : `Nothing matches ${what}`, 404);
  }
  return { el, visible };
}

async function handleClick(body) {
  const { selector, text } = body;
  if (!selector && !text) throw new CommandError('click requires a selector, a text, or both');
  if (text != null && !String(text).trim()) throw new CommandError('click text is empty');
  const p = await getActivePage();
  const { el, visible } = await findTarget(p, selector, text);
  const clicked = await describeHandle(el);

  await el.scrollIntoView();
  let point;
  try {
    point = await el.clickablePoint();
  } catch (e) {
    throw new CommandError(`Matched ${JSON.stringify(clicked)} but it has no clickable point: ${e.message}`, 409);
  }
  const result = { clicked, matches: visible };
  // A real mouse click lands on whatever is on top at that point. Say so when
  // that is not the element asked for: an overlay, a scrim, a toast.
  const hit = await p.evaluateHandle((x, y) => {
    let e = document.elementFromPoint(x, y);
    while (e && e.shadowRoot) {
      const inner = e.shadowRoot.elementFromPoint(x, y);
      if (!inner || inner === e) break;
      e = inner;
    }
    return e;
  }, point.x, point.y);
  if (await el.evaluate((n, h) => !!h && !n.contains(h), hit)) result.coveredBy = await describeHandle(hit);
  await hit.dispose();

  await p.mouse.click(point.x, point.y);
  return result;
}

async function handleType(body) {
  if (!body.selector) throw new CommandError('type requires a selector');
  if (typeof body.text !== 'string') throw new CommandError('type requires a text string');
  const p = await getActivePage();
  const { el } = await findTarget(p, body.selector, null);

  await el.focus();
  // Strict: a wrapper whose child already had focus would pass a contains()
  // check while the keys went to that child. (A shadow host that delegates
  // focus is its own document.activeElement, so it still passes.)
  const focused = await el.evaluate((n) => n === document.activeElement);
  if (!focused) {
    throw new CommandError(`${JSON.stringify(await describeHandle(el))} does not take focus; target the input itself`, 409);
  }
  if (body.clear) {
    // Select everything and delete it with a real key, so frameworks that
    // track input events (React's controlled inputs) see the change.
    await el.evaluate((n) => {
      if (typeof n.select === 'function') { n.select(); return; }
      const range = document.createRange();
      range.selectNodeContents(n);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    });
    await p.keyboard.press('Backspace');
  } else {
    // focus() leaves the caret at the start of a field it had not been in, so
    // move it to the end: without clear, text is appended.
    await el.evaluate((n) => {
      try {
        if (typeof n.setSelectionRange === 'function') { n.setSelectionRange(n.value.length, n.value.length); return; }
      } catch { return; } // email and number inputs have no caret API
      if (n.isContentEditable) {
        const range = document.createRange();
        range.selectNodeContents(n);
        range.collapse(false);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
    });
  }
  await p.keyboard.type(body.text);
  const value = await el.evaluate((n) => (typeof n.value === 'string' ? n.value : n.innerText));
  return { typed: body.text.length, value, into: await describeHandle(el) };
}

async function handlePress(body) {
  if (!body.key || typeof body.key !== 'string') {
    throw new CommandError('press requires a key, e.g. "Escape", "Enter" or "Shift+Tab"');
  }
  const p = await getActivePage();
  // "Shift+Tab" style chords: hold the modifiers, press the last key.
  const modifiers = body.key === '+' ? [] : body.key.split('+');
  const key = body.key === '+' ? '+' : modifiers.pop();
  try {
    for (const m of modifiers) await p.keyboard.down(m);
    await p.keyboard.press(key);
  } catch (e) {
    throw new CommandError(e.message); // e.g. Unknown key: "Esc"
  } finally {
    for (const m of modifiers.reverse()) await p.keyboard.up(m).catch(() => {});
  }
  // The key may have navigated; a focus report is a nicety, not a failure.
  let focused = null;
  try { focused = await describeHandle(await p.evaluateHandle(() => document.activeElement)); } catch {}
  return { pressed: body.key, focused };
}

async function handleWaitFor(body) {
  if (!body.selector) throw new CommandError('waitFor requires a selector');
  const hidden = !!body.hidden;
  const timeout = timeoutFrom(body.timeout, WAIT_TIMEOUT);
  const p = await getActivePage();
  const started = Date.now();
  try {
    await p.waitForSelector(body.selector, hidden ? { hidden: true, timeout } : { visible: true, timeout });
  } catch (e) {
    if (e.name === 'TimeoutError') {
      throw new CommandError(`waitFor timed out after ${timeout}ms: ${JSON.stringify(body.selector)} `
        + `never ${hidden ? 'went away' : 'became visible'}`, 408);
    }
    throw new CommandError(e.message);
  }
  return { ok: true, selector: body.selector, hidden, ms: Date.now() - started };
}

function handleErrors(body) {
  if (body.clear) { resetErrors(); return { cleared: true }; }
  const consoleErrors = consoleLogs
    .filter((l) => l.type === 'error' && l.ts >= errorsSince)
    .map(({ text, ts }) => ({ text, ts }));
  return {
    since: new Date(errorsSince).toISOString(),
    count: consoleErrors.length + pageErrors.length + networkErrors.length,
    console: consoleErrors,
    pageErrors: pageErrors.slice(),
    network: networkErrors.slice(),
  };
}

async function handleCommand(body) {
  const { command, selector, expression, children } = body;

  switch (command) {
    case 'inspect':
      if (!selector) return { error: 'inspect requires a selector' };
      return handleInspect(selector);

    case 'dom':
      if (!selector) return { error: 'dom requires a selector' };
      return handleDom(selector, { children: !!children });

    case 'screenshot':
      return handleScreenshot(selector);

    case 'eval':
      if (!expression) return { error: 'eval requires an expression' };
      return handleEval(expression);

    case 'status':
      return handleStatus();

    case 'viewport':
      return handleViewport(body);

    case 'console': {
      const filter = body.filter || '';
      const limit = body.limit || 50;
      let logs = consoleLogs;
      if (filter) logs = logs.filter(l => l.text.includes(filter));
      if (body.clear) { consoleLogs.length = 0; return { cleared: true }; }
      return { logs: logs.slice(-limit) };
    }

    case 'errors':
      return handleErrors(body);

    case 'goto':
      return handleGoto(body);

    case 'click':
      return handleClick(body);

    case 'type':
      return handleType(body);

    case 'press':
      return handlePress(body);

    case 'waitFor':
      return handleWaitFor(body);

    default:
      return { error: `Unknown command: ${command}. Available: inspect, dom, screenshot, eval, status, viewport, console, `
        + 'errors, goto, click, type, press, waitFor' };
  }
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json');

  if (req.method === 'GET' && req.url.startsWith('/console')) {
    const url = new URL(req.url, `http://127.0.0.1`);
    const filter = url.searchParams.get('filter') || '';
    const limit = parseInt(url.searchParams.get('limit') || '50', 10);
    let logs = consoleLogs;
    if (filter) logs = logs.filter(l => l.text.includes(filter));
    res.end(JSON.stringify({ logs: logs.slice(-limit) }));
    return;
  }

  if (req.method === 'GET' && req.url === '/status') {
    try {
      const result = await handleStatus();
      res.end(JSON.stringify(result));
    } catch (e) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: e.message }));
    }
    return;
  }

  if (req.method !== 'POST') {
    res.statusCode = 405;
    res.end(JSON.stringify({ error: 'POST required' }));
    return;
  }

  let body = '';
  req.on('data', chunk => { body += chunk; });
  req.on('end', async () => {
    try {
      const parsed = JSON.parse(body);
      const result = await handleCommand(parsed);
      res.end(JSON.stringify(result, null, 2));
    } catch (e) {
      res.statusCode = e.status || 400;
      res.end(JSON.stringify({ error: e.message }));
    }
  });
});

let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  log('Shutting down...');
  // A headless instance never registered, and must not write the registry:
  // writing it also rewrites every other instance's entry.
  if (!HEADLESS) unregisterInstance(PROFILE);
  server.close();
  if (browser) {
    try { await browser.close(); } catch {}
  }
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

(async () => {
  if (HEADLESS) {
    // --port is honoured exactly. Falling back to another port would leave a
    // caller that did not read stdout talking to whatever holds the one it
    // asked for, which may be the human's own browser.
    if (cliArgs.port && !(await isPortFree(cliArgs.port))) {
      console.error(`Port ${cliArgs.port} is in use.`);
      process.exit(1);
    }
    assignedPort = cliArgs.port || 0;
  } else {
    assignedPort = await findFreePort(cliArgs.port);
  }
  await launchBrowser();

  server.listen(assignedPort, '127.0.0.1', () => {
    if (HEADLESS) {
      // Never registered: the shared-browser lookup falls back to the
      // registry's first entry, so a headless entry could be taken for the
      // human's browser. The caller reads the port from this line instead.
      assignedPort = server.address().port;
      process.stdout.write(`${JSON.stringify({
        headless: true, port: assignedPort, pid: process.pid, userDataDir: USER_DATA_DIR,
      })}\n`);
      return;
    }
    registerInstance({
      profile: PROFILE,
      port: assignedPort,
      pid: process.pid,
      userDataDir: USER_DATA_DIR,
      launchedAt: new Date().toISOString(),
    });
    console.log(`Puppeteer server listening on http://127.0.0.1:${assignedPort}`);
    console.log(`Profile: ${PROFILE}`);
    console.log(`Chrome data: ${USER_DATA_DIR}`);
  });
})();
