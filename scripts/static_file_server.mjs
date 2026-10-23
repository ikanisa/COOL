#!/usr/bin/env node
import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const host = args.get('--host') ?? '127.0.0.1';
const port = Number(args.get('--port'));
const root = resolve(args.get('--dir') ?? '.');

if (!Number.isInteger(port) || port <= 0) {
  console.error('usage: static_file_server.mjs --host 127.0.0.1 --port PORT --dir DIR');
  process.exit(2);
}

const contentTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.svg', 'image/svg+xml'],
  ['.png', 'image/png'],
  ['.wasm', 'application/wasm'],
  ['.txt', 'text/plain; charset=utf-8'],
]);

function fileForRequest(url) {
  const parsed = new URL(url, `http://${host}:${port}`);
  const requested = parsed.pathname === '/' ? '/index.html' : parsed.pathname;
  const normalized = normalize(decodeURIComponent(requested)).replace(/^(\.\.(\/|\\|$))+/, '');
  const fullPath = resolve(join(root, normalized));
  if (fullPath !== root && !fullPath.startsWith(root + sep)) {
    return null;
  }
  return fullPath;
}

const server = createServer((request, response) => {
  const filePath = fileForRequest(request.url ?? '/');
  if (!filePath) {
    response.writeHead(403);
    response.end('forbidden');
    return;
  }

  let fileStat;
  try {
    fileStat = statSync(filePath);
  } catch (_) {
    response.writeHead(404);
    response.end('not found');
    return;
  }

  if (!fileStat.isFile()) {
    response.writeHead(404);
    response.end('not found');
    return;
  }

  response.writeHead(200, {
    'content-length': fileStat.size,
    'content-type': contentTypes.get(extname(filePath)) ?? 'application/octet-stream',
    'cache-control': 'no-store',
  });
  if (request.method === 'HEAD') {
    response.end();
    return;
  }
  createReadStream(filePath).pipe(response);
});

server.listen(port, host, () => {
  console.log(`serving ${root} at http://${host}:${port}`);
});
