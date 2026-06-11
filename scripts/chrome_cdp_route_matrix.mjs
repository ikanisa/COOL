#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { dirname } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const chrome = args.get('--chrome');
const baseUrl = args.get('--base-url');
const outputDir = args.get('--output-dir');
const profile = args.get('--profile');
const routes = JSON.parse(args.get('--routes-json') ?? '[]');
const viewport = args.get('--viewport') ?? '390x844';
const waitMs = Number(args.get('--wait-ms') ?? '9000');
const devtoolsReadyMs = Number(args.get('--devtools-ready-ms') ?? '30000');
const commandTimeoutMs = Number(args.get('--command-timeout-ms') ?? '45000');
const routeTimeoutMs = Number(args.get('--route-timeout-ms') ?? String(Math.max(commandTimeoutMs + waitMs + 5000, 30000)));

if (!chrome || !baseUrl || !outputDir || !profile || !Array.isArray(routes)) {
  console.error(
    'usage: chrome_cdp_route_matrix.mjs --chrome PATH --base-url URL --output-dir DIR --profile DIR --routes-json JSON',
  );
  process.exit(2);
}

const [width, height] = viewport.split('x').map((value) => Number(value));
if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
  console.error(`invalid viewport: ${viewport}`);
  process.exit(2);
}

const reserveFreePort = () =>
  new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : null;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        if (!Number.isInteger(port)) {
          reject(new Error('Unable to reserve a local DevTools port.'));
          return;
        }
        resolve(port);
      });
    });
  });

const port = await reserveFreePort();
mkdirSync(outputDir, { recursive: true });
rmSync(profile, { recursive: true, force: true });
mkdirSync(profile, { recursive: true });

const chromeArgs = [
  '--headless=new',
  '--force-device-scale-factor=1',
  '--disable-gpu',
  '--disable-background-networking',
  '--disable-component-update',
  '--disable-sync',
  '--disable-dev-shm-usage',
  '--disable-extensions',
  '--disable-crash-reporter',
  '--no-first-run',
  '--no-default-browser-check',
  `--user-data-dir=${profile}`,
  `--window-size=${width},${height}`,
  '--remote-debugging-address=127.0.0.1',
  `--remote-debugging-port=${port}`,
  '--remote-allow-origins=*',
  'about:blank',
];

const chromeProcess = spawn(chrome, chromeArgs, { stdio: ['ignore', 'pipe', 'pipe'] });
let chromeStdout = '';
let chromeStderr = '';
let chromeExit;
chromeProcess.stdout.setEncoding('utf8');
chromeProcess.stderr.setEncoding('utf8');
chromeProcess.stdout.on('data', (chunk) => {
  chromeStdout += chunk;
});
chromeProcess.stderr.on('data', (chunk) => {
  chromeStderr += chunk;
});
chromeProcess.on('exit', (code, signal) => {
  chromeExit = { code, signal };
});

const diagnostics = () => {
  const parts = [`Chrome path: ${chrome}`, `Chrome args: ${chromeArgs.join(' ')}`];
  if (chromeExit) parts.push(`Chrome exit: code=${chromeExit.code ?? 'null'} signal=${chromeExit.signal ?? 'null'}`);
  if (chromeStdout.trim()) parts.push(`Chrome stdout:\n${chromeStdout.trim().slice(-4000)}`);
  if (chromeStderr.trim()) parts.push(`Chrome stderr:\n${chromeStderr.trim().slice(-4000)}`);
  return parts.join('\n');
};

let socket;
try {
  const devtoolsUrl = `http://127.0.0.1:${port}`;
  let version;
  for (let attempt = 0; attempt < Math.ceil(devtoolsReadyMs / 100); attempt += 1) {
    if (chromeExit) throw new Error(`Chrome exited before DevTools became ready.\n${diagnostics()}`);
    try {
      const response = await fetch(`${devtoolsUrl}/json/version`);
      if (response.ok) {
        version = await response.json();
        break;
      }
    } catch (_) {
      // Chrome is still starting.
    }
    await delay(100);
  }
  if (!version?.webSocketDebuggerUrl) {
    throw new Error(`Chrome DevTools endpoint did not become ready.\n${diagnostics()}`);
  }

  const newTarget = await fetch(`${devtoolsUrl}/json/new?${encodeURIComponent('about:blank')}`, {
    method: 'PUT',
  });
  if (!newTarget.ok) throw new Error(`Chrome target creation failed: ${newTarget.status}`);
  const target = await newTarget.json();
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });

  let nextId = 1;
  const pending = new Map();
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (!message.id || !pending.has(message.id)) return;
    const { resolve, reject, timeout } = pending.get(message.id);
    pending.delete(message.id);
    clearTimeout(timeout);
    if (message.error) {
      reject(new Error(`${message.error.message}: ${message.error.data ?? ''}`));
    } else {
      resolve(message.result ?? {});
    }
  });

  const command = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = nextId;
      nextId += 1;
      const timeout = setTimeout(() => {
        if (!pending.has(id)) return;
        pending.delete(id);
        reject(new Error(`${method} timed out after ${commandTimeoutMs}ms`));
      }, commandTimeoutMs);
      pending.set(id, { resolve, reject, timeout });
      socket.send(JSON.stringify({ id, method, params }));
    });

  const withTimeout = (promise, ms, label) =>
    new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error(`${label} timed out after ${ms}ms`));
      }, ms);
      promise.then(
        (value) => {
          clearTimeout(timeout);
          resolve(value);
        },
        (error) => {
          clearTimeout(timeout);
          reject(error);
        },
      );
    });

  await command('Page.enable');
  await command('Runtime.enable');
  await command('Emulation.setDeviceMetricsOverride', {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: true,
    screenWidth: width,
    screenHeight: height,
    positionX: 0,
    positionY: 0,
  });
  await command('Emulation.setTouchEmulationEnabled', { enabled: true });

  for (const routeSpec of routes) {
    const { name, route } = routeSpec;
    if (!name || !route) throw new Error(`invalid route spec: ${JSON.stringify(routeSpec)}`);
    const url = `${baseUrl}/#${route}`;
    const output = `${outputDir}/${name}-${viewport}.png`;
    mkdirSync(dirname(output), { recursive: true });
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const screenshot = await withTimeout(
          (async () => {
            await command('Page.navigate', { url });
            await delay(waitMs);
            return command('Page.captureScreenshot', {
              format: 'png',
              fromSurface: true,
              captureBeyondViewport: false,
            });
          })(),
          routeTimeoutMs,
          `${name} ${route}`,
        );
        writeFileSync(output, Buffer.from(screenshot.data, 'base64'));
        console.log(`captured ${name} ${route}`);
        break;
      } catch (error) {
        console.error(`[${name}] attempt ${attempt}: ${error.message}`);
        try {
          await command('Page.stopLoading');
        } catch (_) {
          // Continue to retry; the next navigation may still recover the page.
        }
        if (attempt === 3) throw error;
        await delay(1000 * attempt);
      }
    }
  }
} finally {
  if (socket) socket.close();
  chromeProcess.kill('SIGTERM');
  await delay(1000);
  if (!chromeExit) chromeProcess.kill('SIGKILL');
}

process.exit(0);
