#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
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

const port = 40000 + Math.floor(Math.random() * 10000);
mkdirSync(dirname(output), { recursive: true });
rmSync(profile, { recursive: true, force: true });
mkdirSync(profile, { recursive: true });

const chromeProcess = spawn(chrome, [
  '--headless=new',
  '--force-device-scale-factor=1',
  '--disable-gpu',
  '--disable-background-networking',
  '--disable-component-update',
  '--disable-sync',
  '--disable-dev-shm-usage',
  '--no-first-run',
  '--no-default-browser-check',
  `--user-data-dir=${profile}`,
  `--window-size=${width},${height}`,
  `--remote-debugging-port=${port}`,
  '--remote-allow-origins=*',
  'about:blank',
], {
  stdio: ['ignore', 'ignore', 'inherit'],
});

let socket;
try {
  const baseUrl = `http://127.0.0.1:${port}`;
  let version;
  for (let attempt = 0; attempt < 80; attempt += 1) {
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
    throw new Error('Chrome DevTools endpoint did not become ready.');
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
      pending.set(id, { resolve, reject });
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
  const screenshot = await command('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(output, Buffer.from(screenshot.data, 'base64'));
  console.log(`captured ${output} ${width}x${height}`);
} finally {
  if (socket) socket.close();
  chromeProcess.kill('SIGTERM');
  setTimeout(() => chromeProcess.kill('SIGKILL'), 1000).unref();
}
