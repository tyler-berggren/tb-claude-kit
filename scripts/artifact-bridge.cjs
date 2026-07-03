const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.BRIDGE_PORT || '4444', 10);
const ROOT = path.resolve(process.argv[2] || process.cwd());

function safe(rel) {
  const full = path.resolve(ROOT, rel);
  return full.startsWith(ROOT + path.sep) || full === ROOT ? full : null;
}

function json(res, code, data) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function body(req) {
  return new Promise((resolve, reject) => {
    let d = '';
    req.on('data', c => (d += c));
    req.on('end', () => {
      try {
        resolve(JSON.parse(d));
      } catch (e) {
        reject(e);
      }
    });
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  const url = new URL(req.url, `http://localhost:${PORT}`);
  try {
    if (url.pathname === '/status') {
      return json(res, 200, { ok: true, root: ROOT, port: PORT });
    }

    if (url.pathname === '/read' && req.method === 'GET') {
      const p = url.searchParams.get('path');
      if (!p) return json(res, 400, { error: 'path required' });
      const f = safe(p);
      if (!f) return json(res, 403, { error: 'path outside project root' });
      return json(res, 200, { path: p, content: fs.readFileSync(f, 'utf-8') });
    }

    if (url.pathname === '/write' && req.method === 'POST') {
      const { path: p, content } = await body(req);
      if (!p || content == null) return json(res, 400, { error: 'path and content required' });
      const f = safe(p);
      if (!f) return json(res, 403, { error: 'path outside project root' });
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, content, 'utf-8');
      return json(res, 200, { ok: true, path: p });
    }

    json(res, 404, { error: 'not found' });
  } catch (e) {
    json(res, 500, { error: e.message });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Artifact bridge on http://127.0.0.1:${PORT}`);
  console.log(`Root: ${ROOT}`);
});
