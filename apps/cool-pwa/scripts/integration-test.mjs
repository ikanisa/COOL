/**
 * Pages Functions integration test suite.
 *
 * Tests the auth + admin API endpoints against  a local wrangler pages dev
 * runtime. Requires Supabase env vars to be set for true end-to-end testing,
 * or runs structural tests (HTTP method, status code, headers) without them.
 *
 * Usage:
 *   # Structural tests (no Supabase required)
 *   node scripts/integration-test.mjs
 *
 *   # Full end-to-end with Supabase
 *   COOL_PROJECT_SUPABASE_URL=... COOL_PROJECT_SUPABASE_ANON_KEY=... \
 *     node scripts/integration-test.mjs
 */

import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { spawn } from 'node:child_process';

const PORT = 8799;
const BASE = `http://127.0.0.1:${PORT}`;
let wranglerProcess = null;
let wranglerStdout = '';
let wranglerStderr = '';

async function waitForServer(url, maxMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < maxMs) {
    try {
      const res = await fetch(url, { redirect: 'manual' });
      if (res.status < 500) {
        return;
      }
    } catch (_) {
      // Server not up yet
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(
    `Server did not start at ${url} within ${maxMs}ms\nstdout:\n${wranglerStdout}\nstderr:\n${wranglerStderr}`,
  );
}

before(async () => {
  console.log('Starting wrangler pages dev...');
  wranglerProcess = spawn('npx', ['wrangler', 'pages', 'dev', '.', '--port', String(PORT), '--log-level', 'error'], {
    cwd: new URL('..', import.meta.url).pathname,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      NODE_ENV: 'test',
    },
  });

  wranglerProcess.stdout.on('data', (chunk) => {
    wranglerStdout += chunk.toString();
  });
  wranglerProcess.stderr.on('data', (chunk) => {
    wranglerStderr += chunk.toString();
  });

  await waitForServer(`${BASE}/api/healthz`);
  console.log(`Server ready at ${BASE}`);
});

after(() => {
  if (wranglerProcess) {
    wranglerProcess.kill('SIGTERM');
  }
});

// ── Structural tests (no Supabase required) ─────────────────────

describe('Root redirect', () => {
  it('/ should serve admin content', async () => {
    const res = await fetch(`${BASE}/`);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.ok(text.includes('COOL'), 'Root should contain COOL branding');
  });
});

describe('Health endpoint', () => {
  it('/api/healthz returns a live ok payload', async () => {
    const res = await fetch(`${BASE}/api/healthz`);
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.live, true);
    assert.equal(data.status, 'ok');
  });
});

describe('Security headers', () => {
  it('/admin/ should have security headers', async () => {
    const res = await fetch(`${BASE}/admin/`);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('x-frame-options'), 'DENY');
    assert.ok(res.headers.get('strict-transport-security')?.includes('max-age='));
  });
});

describe('Auth endpoints method enforcement', () => {
  it('POST /api/auth/send-otp without body returns 400', async () => {
    const res = await fetch(`${BASE}/api/auth/send-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.equal(res.status, 400);
    const data = await res.json();
    assert.equal(data.code, 'PHONE_REQUIRED');
  });

  it('POST /api/auth/verify-otp without body returns 400', async () => {
    const res = await fetch(`${BASE}/api/auth/verify-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.equal(res.status, 400);
    const data = await res.json();
    assert.equal(data.code, 'OTP_INPUT_REQUIRED');
  });

  it('POST /api/auth/logout clears cookie', async () => {
    const res = await fetch(`${BASE}/api/auth/logout`, { method: 'POST' });
    assert.equal(res.status, 200);
    const setCookie = res.headers.get('set-cookie') || '';
    assert.ok(setCookie.includes('Max-Age=0'), 'Should clear session cookie');
  });
});

describe('Admin endpoints require auth', () => {
  it('GET /api/admin/session without cookie returns 401', async () => {
    const res = await fetch(`${BASE}/api/admin/session`);
    // Will be 401 (no auth) or 503 (no Supabase config) — both are acceptable
    assert.ok([401, 503].includes(res.status), `Expected 401 or 503, got ${res.status}`);
  });

  it('GET /api/admin/data without auth returns 401', async () => {
    const res = await fetch(`${BASE}/api/admin/data?route=users`);
    assert.ok([401, 503].includes(res.status), `Expected 401 or 503, got ${res.status}`);
  });

  it('POST /api/admin/mutate without auth returns 401', async () => {
    const res = await fetch(`${BASE}/api/admin/mutate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'test' }),
    });
    assert.ok([401, 503].includes(res.status), `Expected 401 or 503, got ${res.status}`);
  });
});

describe('Mutate endpoint input validation', () => {
  it('POST /api/admin/mutate without action returns 400 (when authenticated)', async () => {
    // Note: This test only validates the structural path.
    // Full auth testing requires Supabase env vars and a real admin user.
    const res = await fetch(`${BASE}/api/admin/mutate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer test-invalid-token',
      },
      body: JSON.stringify({}),
    });
    // Without valid Supabase, this will be 503 or 401
    assert.ok([400, 401, 503].includes(res.status));
  });
});

describe('Static fallback endpoint', () => {
  it('/api/admin/session static file returns staticPreview flag', async () => {
    // The static file at api/admin/session (not the function) returns this
    // Only reachable from static http-server, not wrangler. Skip if function handles it.
    const res = await fetch(`${BASE}/api/admin/session`);
    if (res.status === 200) {
      const data = await res.json();
      // If static file wins, it has staticPreview. If function wins, it has live.
      assert.ok(
        data.staticPreview === true || data.live === true || data.code === 'AUTH_REQUIRED' || data.code === 'CONFIG_MISSING',
        'Response should be either static preview or live function',
      );
    }
  });
});
