#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { dirname } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const chrome = args.get('--chrome');
const url = args.get('--url');
const output = args.get('--output');
const profile = args.get('--profile');
const viewport = args.get('--viewport') ?? '390x844';
const waitMs = Number(args.get('--wait-ms') ?? '9000');
const devtoolsReadyMs = Number(args.get('--devtools-ready-ms') ?? '120000');
const commandTimeoutMs = Number(args.get('--command-timeout-ms') ?? '60000');
const headlessArg = process.env.CHROME_CDP_HEADLESS_ARG || '--headless';

if (!chrome || !url || !output || !profile) {
  console.error(
    'usage: chrome_cdp_screenshot.mjs --chrome PATH --url URL --output PNG --profile DIR [--viewport 390x844] [--wait-ms 9000]',
  );
  process.exit(2);
}

const [width, height] = viewport.split('x').map((value) => Number(value));
if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
  console.error(`invalid viewport: ${viewport}`);
  process.exit(2);
}
if (!Number.isFinite(devtoolsReadyMs) || devtoolsReadyMs <= 0) {
  console.error(`invalid DevTools readiness timeout: ${devtoolsReadyMs}`);
  process.exit(2);
}
if (!Number.isFinite(commandTimeoutMs) || commandTimeoutMs <= 0) {
  console.error(`invalid CDP command timeout: ${commandTimeoutMs}`);
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
mkdirSync(dirname(output), { recursive: true });
rmSync(profile, { recursive: true, force: true });
mkdirSync(profile, { recursive: true });

const chromeArgs = [
  headlessArg,
  '--force-device-scale-factor=1',
  '--disable-gpu',
  '--disable-background-networking',
  '--disable-component-update',
  '--disable-sync',
  '--disable-dev-shm-usage',
  '--disable-extensions',
  '--disable-crash-reporter',
  '--no-sandbox',
  '--no-first-run',
  '--no-default-browser-check',
  `--user-data-dir=${profile}`,
  `--window-size=${width},${height}`,
  '--remote-debugging-address=127.0.0.1',
  `--remote-debugging-port=${port}`,
  '--remote-allow-origins=*',
  'about:blank',
];
const chromeProcess = spawn(chrome, chromeArgs, {
  stdio: ['ignore', 'pipe', 'pipe'],
});

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

const chromeDiagnostics = () => {
  const parts = [
    `Chrome path: ${chrome}`,
    `Chrome args: ${chromeArgs.join(' ')}`,
  ];
  if (chromeExit) {
    parts.push(`Chrome exit: code=${chromeExit.code ?? 'null'} signal=${chromeExit.signal ?? 'null'}`);
  }
  if (chromeStdout.trim()) {
    parts.push(`Chrome stdout:\n${chromeStdout.trim().slice(-4000)}`);
  }
  if (chromeStderr.trim()) {
    parts.push(`Chrome stderr:\n${chromeStderr.trim().slice(-4000)}`);
  }
  return parts.join('\n');
};

async function captureWithBuiltInScreenshot(reason) {
  if (socket) {
    socket.close();
    socket = null;
  }
  chromeProcess.kill('SIGTERM');
  await delay(1000);
  if (!chromeExit) {
    chromeProcess.kill('SIGKILL');
    await delay(500);
  }

  const fallbackProfile = `${profile}-fallback`;
  rmSync(fallbackProfile, { recursive: true, force: true });
  mkdirSync(fallbackProfile, { recursive: true });
  rmSync(output, { force: true });

  const fallbackArgs = [
    headlessArg,
    '--force-device-scale-factor=1',
    '--disable-gpu',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
    '--disable-dev-shm-usage',
    '--disable-extensions',
    '--disable-crash-reporter',
    '--no-sandbox',
    '--no-first-run',
    '--no-default-browser-check',
    `--user-data-dir=${fallbackProfile}`,
    `--window-size=${width},${height}`,
    '--run-all-compositor-stages-before-draw',
    `--virtual-time-budget=${Math.max(waitMs, 8000)}`,
    `--screenshot=${output}`,
    url,
  ];
  const fallback = spawn(chrome, fallbackArgs, {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  fallback.stdout.setEncoding('utf8');
  fallback.stderr.setEncoding('utf8');
  fallback.stdout.on('data', (chunk) => {
    stdout += chunk;
  });
  fallback.stderr.on('data', (chunk) => {
    stderr += chunk;
  });

  const deadline = Date.now() + commandTimeoutMs;
  while (Date.now() < deadline) {
    if (existsSync(output) && statSync(output).size > 0) {
      break;
    }
    if (fallback.exitCode !== null || fallback.signalCode !== null) {
      break;
    }
    await delay(250);
  }

  if (fallback.exitCode === null && fallback.signalCode === null) {
    fallback.kill('SIGTERM');
    await delay(1000);
  }
  if (fallback.exitCode === null && fallback.signalCode === null) {
    fallback.kill('SIGKILL');
  }
  rmSync(fallbackProfile, { recursive: true, force: true });

  if (!existsSync(output) || statSync(output).size === 0) {
    throw new Error(
      [
        `Chrome CDP capture failed, and built-in screenshot fallback did not create ${output}.`,
        `CDP failure: ${reason.message}`,
        `Fallback args: ${fallbackArgs.join(' ')}`,
        stdout.trim() ? `Fallback stdout:\n${stdout.trim().slice(-4000)}` : '',
        stderr.trim() ? `Fallback stderr:\n${stderr.trim().slice(-4000)}` : '',
      ].filter(Boolean).join('\n'),
    );
  }

  console.warn(
    [
      `CDP capture failed; used Chrome built-in screenshot fallback for ${output}.`,
      `CDP failure: ${reason.message}`,
      stderr.trim() ? `Fallback stderr:\n${stderr.trim().slice(-1200)}` : '',
    ].filter(Boolean).join('\n'),
  );
}

let socket;
try {
  const baseUrl = `http://127.0.0.1:${port}`;
  let version;
  const devtoolsAttempts = Math.ceil(devtoolsReadyMs / 100);
  for (let attempt = 0; attempt < devtoolsAttempts; attempt += 1) {
    if (chromeExit) {
      throw new Error(`Chrome exited before DevTools became ready.\n${chromeDiagnostics()}`);
    }
    try {
      const response = await fetch(`${baseUrl}/json/version`);
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
    await captureWithBuiltInScreenshot(
      new Error(`Chrome DevTools endpoint did not become ready.\n${chromeDiagnostics()}`),
    );
    process.exit(0);
  }

  const newTarget = await fetch(`${baseUrl}/json/new?${encodeURIComponent('about:blank')}`, {
    method: 'PUT',
  });
  if (!newTarget.ok) {
    throw new Error(`Chrome target creation failed: ${newTarget.status}`);
  }
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
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) {
        reject(new Error(`${message.error.message}: ${message.error.data ?? ''}`));
      } else {
        resolve(message.result ?? {});
      }
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
      timeout.unref?.();
      const settle = (callback) => (value) => {
        clearTimeout(timeout);
        callback(value);
      };
      pending.set(id, {
        resolve: settle(resolve),
        reject: settle(reject),
      });
      socket.send(JSON.stringify({ id, method, params }));
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
  await command('Page.navigate', { url });
  await delay(waitMs);
  const bootDeadline = Date.now() + commandTimeoutMs;
  while (Date.now() < bootDeadline) {
    const bootState = await command('Runtime.evaluate', {
      expression: `(() => {
        const hasFlutterSurface = Boolean(document.querySelector('flt-glass-pane, flutter-view, flt-scene-host, canvas'));
        const hasMainBundle = Array.from(document.scripts).some((script) => script.src.endsWith('/main.dart.js'));
        return {
          readyState: document.readyState,
          bodyChildren: document.body ? document.body.children.length : 0,
          hasFlutterSurface,
          hasMainBundle,
        };
      })()`,
      returnByValue: true,
    });
    const value = bootState.result?.value;
    if (
      value?.readyState === 'complete' &&
      value?.hasFlutterSurface &&
      value?.hasMainBundle &&
      value?.bodyChildren > 2
    ) {
      break;
    }
    await delay(250);
  }
  const screenshot = await command('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(output, Buffer.from(screenshot.data, 'base64'));
  console.log(`captured ${output} ${width}x${height}`);
} catch (error) {
  await captureWithBuiltInScreenshot(error);
} finally {
  if (socket) socket.close();
  chromeProcess.kill('SIGTERM');
  await delay(1000);
  if (!chromeExit) {
    chromeProcess.kill('SIGKILL');
  }
}

process.exit(0);
