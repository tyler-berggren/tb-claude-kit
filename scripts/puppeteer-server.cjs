const http = require('http');
const puppeteer = require('puppeteer');
const path = require('path');
const os = require('os');
const fs = require('fs');

const REGISTRY_PATH = path.join(os.homedir(), '.claude-chrome-registry.json');
const BASE_PORT = 9615;
const MAX_PORT_SCAN = 20;
const CONSOLE_MAX = 500;
const consoleLogs = [];

function parseArgs(argv) {
  const args = { port: null, profile: null, url: null };
  let i = 2;
  while (i < argv.length) {
    if (argv[i] === '--port' && argv[i + 1]) {
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

const cliArgs = parseArgs(process.argv);
const PROFILE = cliArgs.profile || defaultProfile();
const USER_DATA_DIR = path.join(os.homedir(), '.claude-chrome', PROFILE);
const DEFAULT_URL = cliArgs.url || null;

let browser = null;
let page = null;
let assignedPort = null;

async function launchBrowser() {
  fs.mkdirSync(USER_DATA_DIR, { recursive: true });

  browser = await puppeteer.launch({
    headless: false,
    defaultViewport: null,
    userDataDir: USER_DATA_DIR,
    args: [
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-default-apps',
    ],
  });

  const pages = await browser.pages();
  page = pages[0] || await browser.newPage();

  if (DEFAULT_URL) {
    try {
      await page.goto(DEFAULT_URL, { waitUntil: 'domcontentloaded', timeout: 5000 });
    } catch {
      // Target might not be up yet — user will navigate
    }
  }

  const setupConsoleCapture = (p) => {
    p.on('console', (msg) => {
      const entry = { type: msg.type(), text: msg.text(), ts: Date.now() };
      consoleLogs.push(entry);
      if (consoleLogs.length > CONSOLE_MAX) consoleLogs.shift();
    });
  };
  setupConsoleCapture(page);
  browser.on('targetcreated', async (target) => {
    if (target.type() === 'page') {
      const newPage = await target.page();
      if (newPage) setupConsoleCapture(newPage);
    }
  });

  browser.on('disconnected', () => {
    console.log('Browser disconnected, shutting down.');
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

    case 'console': {
      const filter = body.filter || '';
      const limit = body.limit || 50;
      let logs = consoleLogs;
      if (filter) logs = logs.filter(l => l.text.includes(filter));
      if (body.clear) { consoleLogs.length = 0; return { cleared: true }; }
      return { logs: logs.slice(-limit) };
    }

    default:
      return { error: `Unknown command: ${command}. Available: inspect, dom, screenshot, eval, status` };
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
      res.statusCode = 400;
      res.end(JSON.stringify({ error: e.message }));
    }
  });
});

let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log('Shutting down...');
  unregisterInstance(PROFILE);
  server.close();
  if (browser) {
    try { await browser.close(); } catch {}
  }
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

(async () => {
  assignedPort = await findFreePort(cliArgs.port);
  await launchBrowser();

  server.listen(assignedPort, '127.0.0.1', () => {
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
