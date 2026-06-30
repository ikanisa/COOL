#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const root = process.cwd();
const node = process.execPath;
const buildDir = resolve(args.get('--build-dir') ?? 'build/public_web');
const outputDir = resolve(args.get('--output-dir') ?? '.cache/public_visual_evidence/latest');
const chrome = args.get('--chrome') ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const host = args.get('--host') ?? '127.0.0.1';
const portArg = args.get('--port');
const waitMs = Number(args.get('--wait-ms') ?? '3000');
const commandTimeoutMs = Number(args.get('--command-timeout-ms') ?? '45000');
const headlessArg = process.env.CHROME_CDP_HEADLESS_ARG || '--headless';
const viewports = (args.get('--viewports') ?? '390x844,1440x900')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);

if (!existsSync(buildDir)) {
  console.error(`public build directory missing: ${buildDir}`);
  process.exit(2);
}
if (!existsSync(chrome)) {
  console.error(`Chrome/Chromium is required: ${chrome}`);
  process.exit(2);
}
if (!Number.isFinite(waitMs) || waitMs < 0) {
  console.error(`invalid wait-ms: ${waitMs}`);
  process.exit(2);
}
if (!Number.isFinite(commandTimeoutMs) || commandTimeoutMs <= 0) {
  console.error(`invalid command-timeout-ms: ${commandTimeoutMs}`);
  process.exit(2);
}
for (const viewport of viewports) {
  const [width, height] = viewport.split('x').map((value) => Number(value));
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    console.error(`invalid viewport: ${viewport}`);
    process.exit(2);
  }
}

const routes = [
  ['home', '/', '/'],
  ['group-savings', '/group-savings/', '/group-savings/index.html'],
  ['diaspora', '/diaspora/', '/diaspora/index.html'],
  ['credit-readiness', '/credit-readiness/', '/credit-readiness/index.html'],
  ['craas', '/craas/', '/craas/index.html'],
  ['protection', '/protection/', '/protection/index.html'],
  ['insurance', '/insurance/', '/insurance/index.html'],
  ['partners', '/partners/', '/partners/index.html'],
  ['our-partners', '/our-partners/', '/our-partners/index.html'],
  ['privacy', '/privacy/', '/privacy/index.html'],
  ['terms', '/terms/', '/terms/index.html'],
  ['account-deletion', '/account-deletion/', '/account-deletion/index.html'],
  ['data-deletion', '/data-deletion/', '/data-deletion/index.html'],
  ['trust', '/trust/', '/trust/index.html'],
  ['security', '/security/', '/security/index.html'],
];

const reserveFreePort = () =>
  new Promise((resolvePort, reject) => {
    const server = createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, host, () => {
      const address = server.address();
      const selectedPort = typeof address === 'object' && address ? address.port : null;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        if (!Number.isInteger(selectedPort)) {
          reject(new Error('Unable to reserve a local HTTP port.'));
          return;
        }
        resolvePort(selectedPort);
      });
    });
  });

const port = portArg ? Number(portArg) : await reserveFreePort();
if (!Number.isInteger(port) || port <= 0) {
  console.error(`invalid port: ${portArg}`);
  process.exit(2);
}

rmSync(outputDir, { recursive: true, force: true });
mkdirSync(outputDir, { recursive: true });
const capturesJson = `${outputDir}/captures.jsonl`;
writeFileSync(capturesJson, '');

const server = spawn(node, [`${root}/scripts/static_file_server.mjs`, '--host', host, '--port', String(port), '--dir', buildDir], {
  stdio: ['ignore', 'pipe', 'pipe'],
});
let serverStdout = '';
let serverStderr = '';
server.stdout.setEncoding('utf8');
server.stderr.setEncoding('utf8');
server.stdout.on('data', (chunk) => {
  serverStdout += chunk;
});
server.stderr.on('data', (chunk) => {
  serverStderr += chunk;
});

const cleanup = async () => {
  try {
    server.kill('SIGTERM');
  } catch (_) {
    // Already exited.
  }
  await delay(500);
  if (server.exitCode === null && server.signalCode === null) {
    try {
      server.kill('SIGKILL');
    } catch (_) {
      // Already exited.
    }
  }
};

const baseUrl = `http://${host}:${port}`;
try {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}/`);
      if (response.ok) break;
    } catch (_) {
      // Server still starting.
    }
    await delay(250);
    if (attempt === 119) throw new Error(`public static server did not become ready at ${baseUrl}`);
  }

  for (const viewport of viewports) {
    const [width, height] = viewport.split('x').map((value) => Number(value));
    for (const [name, logicalRoute, capturePath] of routes) {
      const shotName = `public-${name}-${viewport}`;
      const png = `${outputDir}/${shotName}.png`;
      const profile = `${outputDir}/${shotName}-profile`;
      rmSync(profile, { recursive: true, force: true });
      mkdirSync(profile, { recursive: true });
      rmSync(png, { force: true });
      const url = `${baseUrl}${capturePath}`;
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
        '--run-all-compositor-stages-before-draw',
        `--virtual-time-budget=${Math.max(waitMs, 3000)}`,
        `--screenshot=${png}`,
        url,
      ];
      const child = spawn(chrome, chromeArgs, { stdio: ['ignore', 'pipe', 'pipe'] });
      let stdout = '';
      let stderr = '';
      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      child.stdout.on('data', (chunk) => {
        stdout += chunk;
      });
      child.stderr.on('data', (chunk) => {
        stderr += chunk;
      });
      const deadline = Date.now() + commandTimeoutMs;
      while (Date.now() < deadline) {
        if (existsSync(png) && statSync(png).size > 0) break;
        if (child.exitCode !== null || child.signalCode !== null) break;
        await delay(200);
      }
      if (child.exitCode === null && child.signalCode === null) {
        child.kill('SIGTERM');
        await delay(1000);
      }
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
      writeFileSync(`${outputDir}/${shotName}.stdout`, stdout);
      writeFileSync(`${outputDir}/${shotName}.stderr`, stderr);
      rmSync(profile, { recursive: true, force: true });
      if (!existsSync(png) || statSync(png).size === 0) {
        throw new Error(`Chrome built-in screenshot did not create ${png} for ${url}`);
      }
      const check = spawn(node, [`${root}/scripts/png_capture_check.mjs`, png, viewport, shotName, logicalRoute, url, capturesJson], {
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      let checkStdout = '';
      let checkStderr = '';
      check.stdout.setEncoding('utf8');
      check.stderr.setEncoding('utf8');
      check.stdout.on('data', (chunk) => {
        checkStdout += chunk;
      });
      check.stderr.on('data', (chunk) => {
        checkStderr += chunk;
      });
      await new Promise((resolveCheck) => check.on('exit', resolveCheck));
      writeFileSync(`${outputDir}/${shotName}.check.stdout`, checkStdout);
      writeFileSync(`${outputDir}/${shotName}.check.stderr`, checkStderr);
      if (check.exitCode !== 0) {
        throw new Error(`PNG check failed for ${png}\n${checkStderr}`);
      }
      console.log(`captured ${shotName}`);
    }
  }

  const captures = readFileSync(capturesJson, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
  const summary = {
    status: captures.length === routes.length * viewports.length ? 'pass' : 'partial',
    generated_at: new Date().toISOString(),
    capture_runtime: 'static_public_chrome_builtin_screenshot',
    base_url: baseUrl,
    route_count: new Set(captures.map((item) => item.route)).size,
    screenshot_count: captures.length,
    expected_screenshot_count: routes.length * viewports.length,
    viewports,
    screenshots: captures.map((item) => item.path),
    captures,
    privacy:
      'Static public screenshots contain no secrets, sessions, raw SMS, OTPs, PINs, service-role keys, or production customer records.',
  };
  writeFileSync(`${outputDir}/summary.json`, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(JSON.stringify({ ...summary, captures: undefined }, null, 2));
  process.exitCode = summary.status === 'pass' ? 0 : 1;
} catch (error) {
  writeFileSync(`${outputDir}/server.stdout`, serverStdout);
  writeFileSync(`${outputDir}/server.stderr`, serverStderr);
  console.error(error.stack ?? error.message);
  process.exitCode = 1;
} finally {
  await cleanup();
}
