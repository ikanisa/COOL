#!/usr/bin/env node
import { existsSync, mkdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import chromeProcess from './chrome_process.cjs';
import chromeDevTools from './chrome_devtools.cjs';

const { chromeArguments, mobileCaptureFlags, startChrome, startDebugChrome, chromeProcessDeadline } = chromeProcess;
const { waitForDevTools, openTarget, navigate, prepareMobileCapture } = chromeDevTools;

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
const processTimeoutMs = Number(
  args.get('--process-timeout-ms') ?? String(devtoolsReadyMs + commandTimeoutMs + waitMs + 15000),
);
const headlessArg = process.env.CHROME_CDP_HEADLESS_ARG || '--headless';

if (!chrome || !url || !output || !profile) {
  console.error(
    'usage: chrome_cdp_capture.mjs --chrome PATH --url URL --output PNG --profile DIR [--viewport 390x844] [--wait-ms 9000]',
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
if (!Number.isFinite(processTimeoutMs) || processTimeoutMs <= 0) {
  console.error(`invalid process timeout: ${processTimeoutMs}`);
  process.exit(2);
}

mkdirSync(dirname(output), { recursive: true });
rmSync(profile, { recursive: true, force: true });
mkdirSync(profile, { recursive: true });

const size = { width, height };
const launch = await startDebugChrome(chrome, chromeArguments(profile, {
  headless: headlessArg, viewport: size, extra: [...mobileCaptureFlags, '--remote-allow-origins=*'],
}));
let fallback;
const cancelProcessDeadline = chromeProcessDeadline({
  async stop() {
    await Promise.all([launch.process.stop(), fallback?.stop()]);
  },
}, processTimeoutMs, `chrome_cdp_capture exceeded process timeout ${processTimeoutMs}ms for ${url}`);

async function captureWithBuiltInScreenshot(reason) {
  await session?.close();
  session = null;
  await launch.process.stop();

  const fallbackProfile = `${profile}-fallback`;
  rmSync(fallbackProfile, { recursive: true, force: true });
  mkdirSync(fallbackProfile, { recursive: true });
  rmSync(output, { force: true });

  const fallbackArgs = chromeArguments(fallbackProfile, {
    headless: headlessArg, viewport: size, extra: [
      ...mobileCaptureFlags,
      '--run-all-compositor-stages-before-draw',
      `--virtual-time-budget=${Math.max(waitMs, 8000)}`,
      `--screenshot=${output}`,
      url,
    ],
  });
  fallback = startChrome(chrome, fallbackArgs);
  try {
    const deadline = Date.now() + commandTimeoutMs;
    while (Date.now() < deadline && fallback.running) {
      if (existsSync(output) && statSync(output).size > 0) break;
      await delay(250);
    }
  } finally {
    await fallback.stop();
    rmSync(fallbackProfile, { recursive: true, force: true });
  }

  if (!existsSync(output) || statSync(output).size === 0) {
    throw new Error(
      [
        `Chrome CDP capture failed, and built-in screenshot fallback did not create ${output}.`,
        `CDP failure: ${reason.message}`,
        `Fallback args: ${fallbackArgs.join(' ')}`,
        fallback.stdout ? `Fallback stdout:\n${fallback.stdout}` : '',
        fallback.stderr ? `Fallback stderr:\n${fallback.stderr}` : '',
      ].filter(Boolean).join('\n'),
    );
  }

  console.warn(
    [
      `CDP capture failed; used Chrome built-in screenshot fallback for ${output}.`,
      `CDP failure: ${reason.message}`,
      fallback.stderr ? `Fallback stderr:\n${fallback.stderr.slice(-1200)}` : '',
    ].filter(Boolean).join('\n'),
  );
}

let session;
try {
  await waitForDevTools(launch, devtoolsReadyMs);
  session = await openTarget(launch.origin, { timeoutMs: commandTimeoutMs });
  await prepareMobileCapture(session, size);
  await navigate(session, url);
  await delay(waitMs);
  const bootDeadline = Date.now() + commandTimeoutMs;
  while (Date.now() < bootDeadline) {
    const bootState = await session.send('Runtime.evaluate', {
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
  const screenshot = await session.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(output, Buffer.from(screenshot.data, 'base64'));
  console.log(`captured ${output} ${width}x${height}`);
} catch (error) {
  await captureWithBuiltInScreenshot(error);
} finally {
  cancelProcessDeadline();
  await session?.close();
  await launch.process.stop();
}
