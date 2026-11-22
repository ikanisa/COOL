#!/usr/bin/env node
import { createReadStream, realpathSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, resolve, sep } from 'node:path';
import { pipeline } from 'node:stream';

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const host = args.get('--host') ?? '127.0.0.1';
const port = Number(args.get('--port'));
const root = realpathSync(resolve(args.get('--dir') ?? '.'));

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
  const parsed = new URL(url, 'http://127.0.0.1');
  const requested = parsed.pathname === '/' ? '/index.html' : decodeURIComponent(parsed.pathname);
  return resolve(root, '.' + requested);
}

function insideRoot(file) {
  return file === root || file.startsWith(root.endsWith(sep) ? root : root + sep);
}

function reject(response, code, message) {
  response.writeHead(code);
  response.end(message);
}

const server = createServer((request, response) => {
  let requested;
  try {
    requested = fileForRequest(request.url ?? '/');
  } catch {
    return reject(response, 400, 'invalid request path');
  }
  if (!insideRoot(requested)) return reject(response, 403, 'forbidden');

  let filePath;
  let fileStat;
  try {
    filePath = realpathSync(requested);
    if (!insideRoot(filePath)) return reject(response, 403, 'forbidden');
    fileStat = statSync(filePath);
  } catch {
    return reject(response, 404, 'not found');
  }
  if (!fileStat.isFile()) return reject(response, 404, 'not found');

  response.writeHead(200, {
    'content-length': fileStat.size,
    'content-type': contentTypes.get(extname(requested)) ?? 'application/octet-stream',
    'cache-control': 'no-store',
  });
  if (request.method === 'HEAD') {
    response.end();
    return;
  }
  pipeline(createReadStream(filePath), response, () => {});
});

server.listen(port, host, () => {
  console.log(`serving ${root} at http://${host}:${port}`);
});
