import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const port = await findAvailablePort();
const baseUrl = `http://127.0.0.1:${port}`;
const auditUrl = `${baseUrl}/index.html`;

async function findAvailablePort() {
  return await new Promise((resolve, reject) => {
    const probe = createServer();
    probe.unref();
    probe.on('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const address = probe.address();
      if (!address || typeof address === 'string') {
        probe.close(() => reject(new Error('Failed to acquire an open port.')));
        return;
      }
      const openPort = address.port;
      probe.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(openPort);
      });
    });
  });
}

async function waitForServer() {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(baseUrl, { cache: 'no-store' });
      const html = await response.text();
      if (response.ok && html.includes('COOL PWA')) {
        return;
      }
    } catch (_) {
      // Retry.
    }
    await delay(250);
  }
  throw new Error('Local PWA server failed to start for Lighthouse.');
}

function startServer() {
  return spawn(
    process.platform === 'win32' ? 'npx.cmd' : 'npx',
    ['http-server', '.', '-p', String(port), '-c-1', '--silent'],
    {
      cwd: root,
      stdio: 'ignore',
    },
  );
}

const outputDir = resolve(root, '../../output/lighthouse');
const reportBase = resolve(outputDir, 'cool-pwa-home');
const reportPath = `${reportBase}.report.json`;
mkdirSync(outputDir, { recursive: true });

const server = startServer();

try {
  await waitForServer();

  await new Promise((resolve, reject) => {
    const child = spawn(
      process.platform === 'win32' ? 'npx.cmd' : 'npx',
      [
        'lighthouse',
        auditUrl,
        '--chrome-flags=--headless=new --no-sandbox',
        '--only-categories=performance,accessibility,best-practices,seo',
        '--output=json',
        '--output=html',
        `--output-path=${reportBase}`,
      ],
      {
        cwd: root,
        stdio: 'inherit',
      },
    );
    child.on('exit', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Lighthouse exited with code ${code}`));
      }
    });
  });

  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (existsSync(reportPath)) {
      break;
    }
    await delay(250);
  }

  if (!existsSync(reportPath)) {
    throw new Error(`Lighthouse report was not written to ${reportPath}`);
  }

  const report = JSON.parse(readFileSync(reportPath, 'utf8'));
  const categories = report.categories;

  assert.ok(categories.performance.score >= 0.85, `Performance score too low: ${categories.performance.score}`);
  assert.ok(categories.accessibility.score >= 0.9, `Accessibility score too low: ${categories.accessibility.score}`);
  assert.ok(categories['best-practices'].score >= 0.9, `Best practices score too low: ${categories['best-practices'].score}`);
  assert.ok(categories.seo.score >= 0.9, `SEO score too low: ${categories.seo.score}`);
} finally {
  server.kill('SIGTERM');
}
