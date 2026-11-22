#!/usr/bin/env node
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import chromeProcess from './chrome_process.cjs';
import chromeDevTools from './chrome_devtools.cjs';

const { chromeArguments, mobileCaptureFlags, startDebugChrome, chromeProcessDeadline } = chromeProcess;
const { waitForDevTools, openTarget, withTimeout, navigate, prepareMobileCapture } = chromeDevTools;

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
const devtoolsReadyMs = Number(args.get('--devtools-ready-ms') ?? '120000');
const commandTimeoutMs = Number(args.get('--command-timeout-ms') ?? '60000');
const routeTimeoutMs = Number(args.get('--route-timeout-ms') ?? String(Math.max(commandTimeoutMs + waitMs + 5000, 30000)));
const processTimeoutMs = Number(
  args.get('--process-timeout-ms') ??
    String(devtoolsReadyMs + routes.length * routeTimeoutMs + 30000),
);
const headlessArg = process.env.CHROME_CDP_HEADLESS_ARG || '--headless';

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
if (!Number.isFinite(processTimeoutMs) || processTimeoutMs <= 0) {
  console.error(`invalid process timeout: ${processTimeoutMs}`);
  process.exit(2);
}

mkdirSync(outputDir, { recursive: true });
rmSync(profile, { recursive: true, force: true });
mkdirSync(profile, { recursive: true });

const size = { width, height };
const launch = await startDebugChrome(chrome, chromeArguments(profile, {
  headless: headlessArg, viewport: size, extra: [...mobileCaptureFlags, '--remote-allow-origins=*'],
}));
const cancelProcessDeadline = chromeProcessDeadline(launch.process, processTimeoutMs,
  `chrome_cdp_route_matrix exceeded process timeout ${processTimeoutMs}ms`);

try {
  await waitForDevTools(launch, devtoolsReadyMs);
  for (const routeSpec of routes) {
    const { name, route } = routeSpec;
    if (!name || !route) throw new Error(`invalid route spec: ${JSON.stringify(routeSpec)}`);
    const url = `${baseUrl}/#${route}`;
    const output = `${outputDir}/${name}-${viewport}.png`;
    mkdirSync(dirname(output), { recursive: true });
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      let session;
      try {
        session = await openTarget(launch.origin, { timeoutMs: commandTimeoutMs });
        await prepareMobileCapture(session, size);
        const screenshot = await withTimeout(
          (async () => {
            await navigate(session, url);
            await delay(waitMs);
            return session.send('Page.captureScreenshot', {
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
        if (attempt === 3) throw error;
        await delay(1000 * attempt);
      } finally {
        await session?.close();
      }
    }
  }
} finally {
  cancelProcessDeadline();
  await launch.process.stop();
}
