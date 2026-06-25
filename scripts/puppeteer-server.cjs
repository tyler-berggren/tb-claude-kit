const http = require('http');
const puppeteer = require('puppeteer');
const path = require('path');
const os = require('os');

const PORT = 9615;
const USER_DATA_DIR = path.join(os.homedir(), '.claude-chrome-debug');
const DEFAULT_URL = process.argv[2] || null;

let browser = null;
let page = null;

async function launchBrowser() {
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
      // Target might not be up yet — that's fine, user will navigate
    }
  }

  browser.on('disconnected', () => {
    console.log('Browser disconnected, shutting down.');
    process.exit(0);
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

    default:
      return { error: `Unknown command: ${command}. Available: inspect, dom, screenshot, eval, status` };
  }
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json');

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

async function shutdown() {
  console.log('Shutting down...');
  server.close();
  if (browser) {
    try { await browser.close(); } catch {}
  }
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

(async () => {
  await launchBrowser();
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`Puppeteer server listening on http://127.0.0.1:${PORT}`);
    console.log(`Chrome launched with debug profile at ${USER_DATA_DIR}`);
  });
})();
