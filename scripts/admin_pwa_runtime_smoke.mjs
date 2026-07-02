#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import net from 'node:net';

const [targetUrl, evidenceDir] = process.argv.slice(2);

if (!targetUrl || !evidenceDir) {
  console.error('usage: admin_pwa_runtime_smoke.mjs <url> <evidence-dir>');
  process.exit(2);
}

function findChrome() {
  if (process.env.ADMIN_PWA_CHROME && existsSync(process.env.ADMIN_PWA_CHROME)) {
    return process.env.ADMIN_PWA_CHROME;
  }

  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
  ];
  return candidates.find((candidate) => existsSync(candidate));
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchJson(url, options = {}) {
  let response;
  try {
    response = await fetch(url, options);
  } catch (error) {
    throw new Error(`${options.method || 'GET'} ${url} failed: ${error.message}`);
  }
  if (!response.ok) {
    throw new Error(`${options.method || 'GET'} ${url} returned HTTP ${response.status}`);
  }
  return response.json();
}

async function waitForDevTools(baseUrl) {
  let lastError;
  const timeoutMs = Number.parseInt(process.env.ADMIN_PWA_RUNTIME_DEVTOOLS_READY_MS || '120000', 10);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      return await fetchJson(`${baseUrl}/json/version`);
    } catch (error) {
      lastError = error;
      await sleep(250);
    }
  }
  throw lastError || new Error('Chrome DevTools endpoint did not start');
}

async function createPageTarget(baseUrl) {
  const encoded = encodeURIComponent('about:blank');
  try {
    return await fetchJson(`${baseUrl}/json/new?${encoded}`, { method: 'PUT' });
  } catch (_) {
    return fetchJson(`${baseUrl}/json/new?${encoded}`);
  }
}

class CdpClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.nextId = 1;
    this.pending = new Map();
    this.waiters = new Map();
    this.logs = [];
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.wsUrl);
      this.ws.addEventListener('open', () => resolve());
      this.ws.addEventListener('error', (event) => reject(new Error(String(event.message || event.type))));
      this.ws.addEventListener('message', (event) => this.handleMessage(event.data));
    });
  }

  handleMessage(raw) {
    const message = JSON.parse(String(raw));
    if (message.id && this.pending.has(message.id)) {
      const { resolve, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) {
        reject(new Error(message.error.message || JSON.stringify(message.error)));
      } else {
        resolve(message.result || {});
      }
      return;
    }

    if (message.method === 'Runtime.consoleAPICalled') {
      this.logs.push({
        level: message.params.type,
        text: message.params.args.map((arg) => arg.value ?? arg.description ?? arg.type).join(' '),
      });
    }
    if (message.method === 'Runtime.exceptionThrown') {
      this.logs.push({
        level: 'error',
        text: message.params.exceptionDetails?.text || 'Runtime exception thrown',
      });
    }
    if (message.method === 'Log.entryAdded') {
      this.logs.push({
        level: message.params.entry.level,
        text: message.params.entry.text,
        url: message.params.entry.url,
      });
    }

    const eventWaiters = this.waiters.get(message.method);
    if (eventWaiters) {
      for (const waiter of eventWaiters.splice(0)) {
        clearTimeout(waiter.timeout);
        waiter.resolve(message.params || {});
      }
    }
  }

  send(method, params = {}) {
    const id = this.nextId;
    this.nextId += 1;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }

  waitFor(method, timeoutMs) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        const eventWaiters = this.waiters.get(method) || [];
        this.waiters.set(
          method,
          eventWaiters.filter((waiter) => waiter.resolve !== resolve),
        );
        reject(new Error(`Timed out waiting for ${method}`));
      }, timeoutMs);
      const eventWaiters = this.waiters.get(method) || [];
      eventWaiters.push({ resolve, timeout });
      this.waiters.set(method, eventWaiters);
    });
  }

  close() {
    if (this.ws) {
      this.ws.close();
    }
  }
}

async function evaluateRuntime(cdp) {
  const expression = String.raw`
    (async () => {
      const requiredCacheUrls = [
        './index.html',
        './flutter_bootstrap.js',
        './main.dart.js',
        './manifest.json',
      ];
      const timeout = (ms, label) => new Promise((resolve) => setTimeout(() => resolve({ __timeout: label }), ms));
      const result = {
        href: location.href,
        title: document.title,
        serviceWorkerSupported: 'serviceWorker' in navigator,
        cacheSupported: 'caches' in window,
        registrationScope: null,
        activeScriptURL: null,
        activeState: null,
        controlled: Boolean(navigator.serviceWorker && navigator.serviceWorker.controller),
        cacheKeys: [],
        cached: {},
        requiredCacheUrls,
      };

      if (!result.serviceWorkerSupported || !result.cacheSupported) {
        result.ok = false;
        return result;
      }

      let registration = await navigator.serviceWorker.getRegistration();
      if (!registration) {
        const ready = await Promise.race([navigator.serviceWorker.ready, timeout(5000, 'serviceWorker.ready')]);
        if (!ready.__timeout) {
          registration = ready;
        }
      }

      result.registrationScope = registration && registration.scope;
      result.activeScriptURL = registration && registration.active && registration.active.scriptURL;
      result.activeState = registration && registration.active && registration.active.state;
      result.controlled = Boolean(navigator.serviceWorker.controller);
      result.cacheKeys = await caches.keys();

      for (const url of requiredCacheUrls) {
        result.cached[url] = Boolean(await caches.match(url, { ignoreSearch: true }));
      }

      result.ok = Boolean(
        result.title === 'Collect Admin' &&
        result.activeScriptURL &&
        result.activeScriptURL.includes('/custom-sw.js') &&
        result.activeState === 'activated' &&
        result.cacheKeys.some((key) => key.startsWith('collect-admin-')) &&
        requiredCacheUrls.every((url) => result.cached[url] === true)
      );
      return result;
    })()
  `;

  const response = await cdp.send('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
    timeout: 15000,
  });

  if (response.exceptionDetails) {
    throw new Error(response.exceptionDetails.text || 'Runtime.evaluate failed');
  }
  return response.result.value;
}

function isIgnorableBrowserRequest(entry) {
  const text = `${entry.text || ''} ${entry.url || ''}`;
  return /favicon\.ico/i.test(text);
}

const chrome = findChrome();
if (!chrome) {
  console.error('[admin-pwa-runtime][FAIL] Chrome/Chromium is required for Admin PWA runtime smoke.');
  process.exit(1);
}

await mkdir(evidenceDir, { recursive: true });

const remotePort = await freePort();
const remoteBaseUrl = `http://127.0.0.1:${remotePort}`;
const chromeProfile = await mkdtemp(join(tmpdir(), 'collect-admin-pwa-'));
const chromeLogPath = join(evidenceDir, 'pwa-runtime-chrome.log');
const chromeLog = await import('node:fs').then((fs) => fs.createWriteStream(chromeLogPath));

const chromeProcess = spawn(chrome, [
  '--headless=new',
  '--force-device-scale-factor=1',
  '--disable-gpu',
  '--disable-background-networking',
  '--disable-component-update',
  '--disable-sync',
  '--disable-dev-shm-usage',
  '--no-sandbox',
  '--no-first-run',
  '--no-default-browser-check',
  `--user-data-dir=${chromeProfile}`,
  '--remote-debugging-address=127.0.0.1',
  `--remote-debugging-port=${remotePort}`,
  'about:blank',
], {
  stdio: ['ignore', 'pipe', 'pipe'],
});
chromeProcess.stdout.pipe(chromeLog);
chromeProcess.stderr.pipe(chromeLog);

let cdp;
let summary;
try {
  await waitForDevTools(remoteBaseUrl);
  const pageTarget = await createPageTarget(remoteBaseUrl);
  cdp = new CdpClient(pageTarget.webSocketDebuggerUrl);
  await cdp.connect();
  await cdp.send('Page.enable');
  await cdp.send('Runtime.enable');
  await cdp.send('Log.enable').catch(() => {});

  const loadPromise = cdp.waitFor('Page.loadEventFired', 30000);
  await cdp.send('Page.navigate', { url: targetUrl });
  await loadPromise;

  let runtime = null;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    runtime = await evaluateRuntime(cdp);
    if (runtime.ok) {
      break;
    }
    await sleep(500);
  }

  const errors = cdp.logs.filter(
    (entry) => ['error', 'assert'].includes(entry.level) && !isIgnorableBrowserRequest(entry),
  );
  const warnings = cdp.logs.filter((entry) => ['warning', 'warn'].includes(entry.level));

  summary = {
    status: runtime.ok && errors.length === 0 ? 'pass' : 'fail',
    url: targetUrl,
    runtime,
    console: {
      errors,
      warnings,
    },
  };
} catch (error) {
  summary = {
    status: 'fail',
    url: targetUrl,
    error: error.message,
    console: {
      errors: cdp
        ? cdp.logs.filter(
          (entry) => ['error', 'assert'].includes(entry.level) && !isIgnorableBrowserRequest(entry),
        )
        : [],
      warnings: cdp ? cdp.logs.filter((entry) => ['warning', 'warn'].includes(entry.level)) : [],
    },
  };
} finally {
  if (cdp) {
    cdp.close();
  }
  if (chromeProcess.exitCode === null && chromeProcess.signalCode === null) {
    chromeProcess.kill('SIGTERM');
    await Promise.race([
      new Promise((resolve) => chromeProcess.once('exit', resolve)),
      sleep(2000),
    ]);
  }
  await rm(chromeProfile, { recursive: true, force: true });
}

await writeFile(join(evidenceDir, 'pwa-runtime.json'), `${JSON.stringify(summary, null, 2)}\n`);

if (summary.status === 'pass') {
  console.log(`[admin-pwa-runtime] pass evidence=${join(evidenceDir, 'pwa-runtime.json')}`);
  process.exit(0);
}

console.error(`[admin-pwa-runtime][FAIL] see ${join(evidenceDir, 'pwa-runtime.json')}`);
console.error(await readFile(join(evidenceDir, 'pwa-runtime.json'), 'utf8'));
process.exit(1);
