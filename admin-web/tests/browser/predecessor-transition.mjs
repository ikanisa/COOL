// Qualify a packaged React Admin against the two captured 1.2.4+23 installations.
// Both canonical hostnames resolve to an isolated loopback TLS server. The
// account and request fixtures exist only in the temporary browser profile.

import assert from 'node:assert/strict';
import { createHash, X509Certificate } from 'node:crypto';
import { readFile, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';
import { createServer } from 'node:https';
import path from 'node:path';
import { chromium } from 'playwright-core';
const [role, predecessorDirectory, reactDirectory, receiptPath] = process.argv.slice(2);
const origins = {
  production: 'https://platform-admin.collect.ikanisa.com',
  qa: 'https://admin-supabase-qa.collect.ikanisa.com'
};
assert(['production', 'qa'].includes(role) && predecessorDirectory && reactDirectory && receiptPath, 'Use predecessor-transition.mjs <production|qa> <verified-predecessor-directory> <packaged-react-site> <new-result.json>');
const sha256 = b => createHash('sha256').update(b).digest('hex');
const custodyBytes = await readFile(path.join(predecessorDirectory, 'verified.json'));
const custodyHash = sha256(custodyBytes);
assert.equal(custodyHash, 'ec6de0c99b4bf6d2cb8339f2788bbbe05c1ad3441abb37270e83cfdce7d6aaa0');
const custody = JSON.parse(custodyBytes).origins[role];
const load = async name => {
  const data = await readFile(path.join(predecessorDirectory, role + '-' + name + '.json'));
  assert.equal(sha256(data), custody[name + '_sha256']);
  return JSON.parse(data);
};
const restore = await load('restore'),
  observed = await load('public');
const origin = restore.origin,
  hostname = new URL(origin).hostname,
  pendingKey = 'collect.admin.pending-attempts.v1';
assert.equal(origin, origins[role]);
const fixtureOwner = {
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  sessionId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  principalId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  email: 'operator-fixture@example.test',
  role: 'owner',
  assuranceLevel: 1,
  mfaAt: null,
  financialModel: 'canonical_evidence_ledger',
  permissions: ['overview.read', 'admin_users.manage', 'receivers.manage', 'receivers.read']
};
const authHash = sha256(JSON.stringify({
  actor: fixtureOwner.id,
  session: fixtureOwner.sessionId,
  email: fixtureOwner.email,
  role: fixtureOwner.role,
  permissions: JSON.stringify([...fixtureOwner.permissions].sort())
}));
const startedAt = Date.now(),
  collectionId = 'synthetic-savings',
  targetPrincipal = '55555555-5555-4555-8555-555555555555',
  requestId = '66666666-6666-4666-8666-666666666666';
const intent = {
  requestId: requestId,
  adminId: '44444444-4444-4444-8444-444444444444',
  phone: '+250780000002',
  role: 'staff',
  capabilities: ['records.read'],
  active: true,
  expectedVersion: 0,
  collectionId: collectionId,
  principalId: targetPrincipal,
  sharedRole: 'staff'
};
const retainedEnvelope = JSON.stringify({
  version: 1,
  authority: authHash,
  entries: [{
    family: 'burimunsi.operator',
    resource_id: collectionId + ':' + targetPrincipal,
    request_key: requestId,
    permission: 'admin_users.manage',
    intent: Object.fromEntries(Object.entries(intent).sort(([a], [b]) => a.localeCompare(b))),
    created_at: startedAt,
    expires_at: startedAt + 7200000
  }]
});
const management = 'collect.admin.notification-management.' + [fixtureOwner.id, fixtureOwner.sessionId, fixtureOwner.principalId, pendingKey].join('.');
const privacy = 'collect.privacy-review.v1.' + fixtureOwner.principalId + '.' + fixtureOwner.sessionId;
const logout = 'collect.admin.logout-intent.v1.' + sha256('collect.admin.logout.v1:' + fixtureOwner.sessionId);
const mfa = 'collect.admin.mfa-intent.v1';
const fixtures = {
  name: pendingKey,
  holder: retainedEnvelope,
  management,
  privacy,
  logout,
  mfa
};
const certDir = await mkdtemp(path.join(tmpdir(), 'collect-admin-pwa-tls-'));
const certificate = path.join(certDir, 'cert.pem'),
  secret = path.join(certDir, 'key.pem');
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=' + hostname, '-keyout', secret, '-out', certificate], {
  stdio: 'ignore'
});
const [cert, key] = await Promise.all([readFile(certificate), readFile(secret)]);
await rm(certDir, {
  recursive: true
});
const spki = createHash('sha256').update(new X509Certificate(cert).publicKey.export({
  format: 'der',
  type: 'spki'
})).digest('base64');
const reactWorker = await readFile(path.join(reactDirectory, 'custom-sw.js'), 'utf8');
const reactCache = reactWorker.match(/const CACHE_NAME = "([^"]+)"/)[1],
  flutterCache = observed.worker_cache;
const report = {
  role,
  origin,
  implementation: 'isolated-chromium-loopback-https',
  predecessorCustody: custodyHash,
  predecessorRestore: custody.restore_sha256,
  predecessorWorker: restore.entries['/custom-sw.js'].sha256,
  reactWorker: sha256(reactWorker),
  reactIndex: sha256(await readFile(path.join(reactDirectory, 'index.html'))),
  reactVersion: sha256(await readFile(path.join(reactDirectory, 'version.json'))),
  when_utc: new Date().toISOString(),
  checks: []
};
try {
  const packageBytes = await readFile(reactDirectory + '.json'),
    manifest = JSON.parse(packageBytes);
  assert.equal(manifest.format, 'collect.react-admin.build.v1');
  assert.equal(manifest.source.clean, true);
  for (const [file, expected] of manifest.files) {
    assert(!path.isAbsolute(file) && !file.split('/').includes('..'));
    assert.equal(sha256(await readFile(path.join(reactDirectory, file))), expected, file);
  }
  report.reactPackageManifest = sha256(packageBytes);
  report.reactCommit = manifest.source.commit;
} catch (error) {
  if (error.code !== 'ENOENT' || error.path !== reactDirectory + '.json') throw error;
}
const oldManifest = JSON.parse(await readFile(path.join(predecessorDirectory, 'sha256', restore.entries['/manifest.json'].sha256)));
const newManifest = JSON.parse(await readFile(path.join(reactDirectory, 'manifest.json')));
assert.equal(new URL(oldManifest.id ?? oldManifest.start_url, origin).href, new URL(newManifest.id ?? newManifest.start_url, origin).href);
const passed = (id, value = true) => {
  assert.ok(value, id);
  report.checks.push(id);
  console.log('PASS', id);
};
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml'
};
let serving = 'prior',
  serveObserved404s = false;
const requests = [],
  writes = [],
  missing = new Set();
const server = createServer({
  key,
  cert
}, async (req, res) => {
  try {
    if (req.headers.host !== hostname) {
      res.writeHead(421);
      return res.end();
    }
    const p = new URL(req.url, origin).pathname;
    if (p.startsWith('/api/') || p.startsWith('/v1/') || p.startsWith('/functions/')) {
      requests.push([serving, req.method, p]);
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        writes.push(p);
        res.writeHead(405);
        return res.end();
      }
      const api = p.split('/api/admin/')[1];
      const cookie = serving === 'prior' || role === 'qa' ? 'fixture_prior=1' : 'fixture_managed=1';
      const user = req.headers.cookie?.includes(cookie) ? fixtureOwner : null;
      let value;
      if (api === 'auth/session') {
        value = {
          user,
          csrfToken: user ? 'f'.repeat(64) : null,
          expiresAt: user ? new Date(startedAt + 7200000).toISOString() : null,
          ownerEmail: user?.email ?? null
        };
        if (user && req.headers['x-collect-owner-identity-version'] === '1') value.ownerIdentity = {
          schemaVersion: 1,
          adminId: fixtureOwner.id,
          principalId: fixtureOwner.principalId,
          email: fixtureOwner.email
        };
      } else if (user && api === 'auth/email-verification') value = {
        contractVersion: 1,
        sessionId: fixtureOwner.sessionId,
        emailVerifiedAt: new Date(startedAt - 1000).toISOString()
      };else if (user && api === 'momo/native-setup') value = {
        contractVersion: 1,
        collections: [{
          id: collectionId,
          title: 'Synthetic savings',
          receiverNetwork: 'mtn_momo',
          receiverNumber: '0788123456',
          version: 1
        }],
        accounts: [],
        scopes: [{
          collectionId: collectionId,
          receivingAccountId: 'synthetic-receiver',
          enabled: true,
          version: 2,
          bindingId: 'synthetic-binding',
          bindingVersion: 1,
          paired: true,
          receiverKeyId: 'synthetic-key',
          receiverInstallationId: '77777777-7777-4777-8777-777777777777',
          pendingReplacement: null
        }],
        installations: []
      };else if (user && api === 'burimunsi/operators/requests/' + requestId && new URL(req.url, origin).searchParams.get('collectionId') === collectionId) value = {
        contractVersion: 1,
        collectionId: collectionId,
        found: true,
        receipt: {
          contractVersion: 1,
          requestId: requestId,
          principalId: targetPrincipal,
          version: 1,
          active: true,
          applied: true
        }
      };
      res.writeHead(value ? 200 : 404, {
        'content-type': 'application/json',
        'cache-control': 'no-store'
      });
      return res.end(JSON.stringify(value ?? {
        error: {
          code: 'synthetic_unavailable'
        }
      }));
    }
    let asset = p;
    if (p === '/' || req.headers['sec-fetch-mode'] === 'navigate' && !path.extname(p)) asset = '/index.html';
    let bytes;
    if (serving === 'prior') {
      const index = asset === '/index.html' ? '/' : asset,
        entry = restore.entries[index];
      if (!entry || serveObserved404s && observed.entries[index].status !== 'public_hash_match') {
        if (entry) missing.add(index);
        res.writeHead(404);
        return res.end();
      }
      bytes = await readFile(path.join(predecessorDirectory, 'sha256', entry.sha256));
      assert.equal(sha256(bytes), entry.sha256);
    } else {
      if (!/^\/[a-zA-Z0-9._/-]+$/.test(asset) || asset.includes('..')) {
        res.writeHead(404);
        return res.end();
      }
      bytes = await readFile(path.join(reactDirectory, asset));
    }
    res.writeHead(200, {
      'content-type': types[path.extname(asset)] ?? 'application/octet-stream',
      'cache-control': 'no-store',
      'service-worker-allowed': '/',
      'x-content-type-options': 'nosniff'
    });
    res.end(bytes);
  } catch (e) {
    res.writeHead(e.code === 'ENOENT' ? 404 : 500);
    res.end();
  }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const browser = await chromium.launch({
  executablePath: process.env.ADMIN_PWA_CHROME,
  headless: true,
  args: ['--no-proxy-server', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-application-cache', '--host-resolver-rules=MAP ' + hostname + ':443 127.0.0.1:' + port + ', MAP * ~NOTFOUND, EXCLUDE 127.0.0.1', '--ignore-certificate-errors-spki-list=' + spki]
});
const context = await browser.newContext({
  serviceWorkers: 'allow'
});
let originalTab = await context.newPage();
report.browser = browser.version();
const errors = [];
originalTab.on('pageerror', e => errors.push(e.name));
async function label(page) {
  return page.evaluate(() => ({
    flutter: !!document.querySelector('script[src*="flutter_bootstrap"]'),
    react: !!document.querySelector('script[src*="admin-entry"]'),
    path: location.pathname
  }));
}
async function controlled(page) {
  await page.evaluate(() => Promise.race([navigator.serviceWorker.ready, new Promise((_, rej) => setTimeout(() => rej(Error('worker not ready')), 55000))]).then(() => true));
  if (!(await page.evaluate(() => !!navigator.serviceWorker.controller))) await page.reload({
    waitUntil: 'domcontentloaded'
  });
  await page.waitForFunction(() => navigator.serviceWorker.controller?.state === 'activated', null, {
    timeout: 30000
  });
}
async function pending(page) {
  return page.evaluate(key => sessionStorage.getItem(key), pendingKey);
}
async function upgrade(page) {
  await page.evaluate(async () => {
    const r = await navigator.serviceWorker.getRegistration();
    await r.update();
    const deadline = Date.now() + 55000;
    while (!r.waiting && Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    if (!r.waiting) throw Error('candidate did not reach waiting');
  });
}
async function neutral(page) {
  await page.goto('about:blank', {
    waitUntil: 'commit'
  });
}
async function offlineShell(flavor) {
  const tab = await context.newPage();
  await tab.goto(origin + '/');
  await controlled(tab);
  try {
    await context.setOffline(true);
    await tab.goto(origin + '/admin/groups');
    assert((await label(tab))[flavor]);
    assert(await tab.evaluate(async () => {
      try {
        await fetch('/api/admin/auth/session');
        return false;
      } catch {
        return true;
      }
    }));
  } finally {
    await context.setOffline(false);
    await tab.close();
  }
}
async function originalForms(tab) {
  await tab.goto(origin + '/admin/burimunsi');
  await tab.getByRole('button', {
    name: 'Check verification and load groups'
  }).click({
    timeout: 11000
  });
  await tab.getByRole('option', {
    name: 'Synthetic savings'
  }).waitFor({
    state: 'attached'
  });
}
async function expectFailedInstallation(tab, initial = false) {
  return tab.evaluate(async initial => {
    const registration = initial ? await navigator.serviceWorker.register('/custom-sw.js', {
      updateViaCache: 'none'
    }) : await navigator.serviceWorker.getRegistration();
    if (!initial) await registration.update();
    const sw = registration.installing;
    if (!sw) return !registration.waiting && (initial ? registration.active === null : registration.active?.state === 'activated');
    return new Promise(resolve => {
      const check = () => {
        if (['redundant', 'activated', 'installed'].includes(sw.state)) resolve(sw.state === 'redundant');
      };
      sw.addEventListener('statechange', check);
      check();
    });
  }, initial);
}
async function returnTo(page, mode) {
  const wanted = mode === 'react' ? reactCache : flutterCache;
  // Inspect worker storage without opening a new controlled window.
  const deadline = Date.now() + 30000;
  let names = [];
  while (Date.now() < deadline) {
    for (const w of context.serviceWorkers()) {
      try {
        names = await w.evaluate(() => caches.keys());
        break;
      } catch {/* A replaced worker target may disappear. */}
    }
    if (names.includes(wanted) && !names.includes(mode === 'react' ? flutterCache : reactCache)) break;
    await delay(50);
  }
  assert(names.includes(wanted) && !names.includes(mode === 'react' ? flutterCache : reactCache), JSON.stringify(names));
  await page.goto(origin + '/admin', {
    waitUntil: 'domcontentloaded'
  });
  await controlled(page);
  assert((await label(page))[mode === 'react' ? 'react' : 'flutter']);
}
try {
  if (role === 'production') {
    serveObserved404s = true;
    await originalTab.goto(origin + '/', {
      waitUntil: 'domcontentloaded'
    });
    // A first-time install cannot satisfy the exact production worker's 137-response manifest.
    const rejected = await expectFailedInstallation(originalTab, true);
    passed('fresh_install_rejects_three_missing_production_assets', rejected && missing.size === 3);
    serveObserved404s = false;
  }
  const cookie = name => ({
    name,
    value: '1',
    url: origin,
    httpOnly: true,
    secure: true,
    sameSite: 'Strict'
  });
  await context.addCookies([cookie('fixture_prior')]);
  await originalTab.goto(origin + '/', {
    waitUntil: 'domcontentloaded'
  });
  await originalTab.evaluate(() => navigator.serviceWorker.register('/custom-sw.js', {
    updateViaCache: 'none'
  }).then(() => true));
  await controlled(originalTab);
  passed('exact_predecessor_worker_activated', (await label(originalTab)).flutter);
  await originalTab.waitForFunction(() => !!document.querySelector('flutter-view,flt-glass-pane,flt-semantics-host'), null, {
    timeout: 30000
  });
  passed('exact_flutter_application_rendered');
  await offlineShell('flutter');
  passed('original_offline_bookmark_bypasses_account_requests');
  const other = await context.newPage();
  await other.goto(origin + '/', {
    waitUntil: 'domcontentloaded'
  });
  await controlled(other);
  await originalTab.evaluate(({
    name,
    holder,
    management,
    privacy
  }) => {
    sessionStorage.setItem(name, holder);
    sessionStorage.setItem(management, 'synthetic-management-checkpoint');
    localStorage.setItem(privacy, 'synthetic-privacy-checkpoint');
    window.syntheticOpenEditor = 'unsaved';
  }, fixtures);
  await other.evaluate(() => sessionStorage.setItem('synthetic.tab.identity', 'second'));
  passed('separate_original_tabs', (await pending(other)) === null);
  serving = 'react';
  await upgrade(originalTab);
  passed('old_dom_and_inmemory_editor_remain_until_operator_leaves', (await originalTab.evaluate(() => window.syntheticOpenEditor === 'unsaved')) && (await label(originalTab)).flutter);
  passed('same_tab_original_pending_before_cutover', (await pending(originalTab)) === retainedEnvelope);
  await neutral(originalTab);
  passed('second_open_client_keeps_flutter_worker_waiting', await other.evaluate(async () => !!(await navigator.serviceWorker.getRegistration())?.waiting));
  if (role === 'production') await other.evaluate(({
    mfa
  }) => sessionStorage.setItem(mfa, 'synthetic-old-mfa-intent'), fixtures);
  await neutral(other);
  await returnTo(originalTab, 'react');
  if (role === 'production') {
    await originalTab.getByRole('heading', {
      name: 'Welcome to Collect'
    }).waitFor({
      timeout: 12000
    });
    passed('anonymous_managed_start_preserves_unmarked_original', (await pending(originalTab)) === retainedEnvelope);
    passed('reconciliation_notice_reveals_no_operator_data', (await originalTab.getByRole('note').filter({
      hasText: 'previous Admin service'
    }).isVisible()) && !(await originalTab.locator('body').innerText()).includes(requestId));
    await originalTab.evaluate(logout => localStorage.setItem(logout, '1'), logout);
    // The two mock databases deliberately return identical identifiers.
    await context.addCookies([cookie('fixture_managed')]);
    await originalTab.reload();
  }
  await originalTab.getByRole('button', {
    name: /^Account:/
  }).waitFor({
    timeout: 12000
  });
  passed('react_operates_in_the_original_tab_and_scope', (await label(originalTab)).react);
  passed('original_account_bound_receipt_preserved_on_return', (await pending(originalTab)) === retainedEnvelope);
  passed('origin_journals_and_http_only_cookie_preserved', (await originalTab.evaluate(({
    management,
    privacy
  }) => sessionStorage.getItem(management) === 'synthetic-management-checkpoint' && localStorage.getItem(privacy) === 'synthetic-privacy-checkpoint' && !document.cookie.includes('fixture_prior'), fixtures)) && (await context.cookies(origin)).some(x => x.name === 'fixture_prior'));
  await other.goto(origin + '/admin', {
    waitUntil: 'domcontentloaded'
  });
  await controlled(other);
  await other.getByRole('button', {
    name: /^Account:/
  }).waitFor({
    timeout: 12000
  });
  passed('second_tab_cannot_read_first_tabs_pending_state', (await pending(other)) === null && (await other.evaluate(() => sessionStorage.getItem('synthetic.tab.identity') === 'second')));
  if (role === 'production') {
    passed('old_mfa_and_logout_not_consumed_or_cleared', await other.evaluate(({
      mfa,
      logout
    }) => sessionStorage.getItem(mfa) === 'synthetic-old-mfa-intent' && localStorage.getItem(logout) === '1', fixtures));
    await originalForms(originalTab);
    passed('coincident_managed_actor_cannot_import_or_query_previous_approval', (await originalTab.getByRole('heading', {
      name: 'Original approval request'
    }).count()) === 0 && (await pending(originalTab)) === retainedEnvelope && !requests.some(([mode,, p]) => mode === 'react' && p.endsWith('/' + requestId)));
    // Finish synthetic auth-marker scenario before testing restoration of the previous runtime.
    await other.evaluate(({
      mfa,
      logout
    }) => {
      sessionStorage.removeItem(mfa);
      localStorage.removeItem(logout);
    }, fixtures);
  } else {
    // QA did not ship the BuriMunsi approval form. Inject a separate, same-realm
    // source-format approval to qualify the React compatibility code explicitly.
    await other.evaluate(({
      name,
      holder
    }) => sessionStorage.setItem(name, holder), fixtures);
    await originalForms(other);
    await other.getByRole('button', {
      name: 'Check original request'
    }).click();
    await other.getByText('The original operator approval was recorded.', {
      exact: true
    }).waitFor();
    passed('same_realm_source_format_approval_settled_only_after_explicit_receipt_read', (await pending(other)) === null && (await pending(originalTab)) === retainedEnvelope && requests.some(([mode, method, p]) => mode === 'react' && method === 'GET' && p.endsWith('/' + requestId)));
  }
  await offlineShell('react');
  passed('react_offline_bookmark_bypasses_account_requests');
  passed('no_account_response_in_new_cache', await originalTab.evaluate(async n => (await (await caches.open(n)).keys()).every(r => !new URL(r.url).pathname.startsWith('/api/')), reactCache));
  serving = 'prior';
  if (role === 'production') {
    serveObserved404s = true;
    missing.clear();
    passed('incomplete_predecessor_rollback_keeps_react_active', (await expectFailedInstallation(originalTab)) && missing.size === 3 && (await label(originalTab)).react);
    serveObserved404s = false;
  }
  await upgrade(originalTab);
  passed('react_tabs_stay_on_react_during_rollback', (await label(originalTab)).react);
  await neutral(other);
  await neutral(originalTab);
  await returnTo(originalTab, 'prior');
  await originalTab.waitForFunction(() => !!document.querySelector('flutter-view,flt-glass-pane,flt-semantics-host'), null, {
    timeout: 30000
  });
  passed('rollback_restores_exact_flutter_in_same_tab', (await label(originalTab)).flutter);
  passed('original_per_tab_record_survives_round_trip', (await pending(originalTab)) === retainedEnvelope);
  passed('no_business_submission_dispatched', writes.length === 0);
  report.requests = [...new Set(requests.map(r => r.join(' ')))];
  report.pageErrorKinds = [...new Set(errors)];
  report.staticOnly = true;
  report.scratch = true;
  await writeFile(receiptPath, JSON.stringify(report, null, 2) + '\n', {
    flag: 'wx'
  });
  console.log('RESULT', report.checks.length);
} finally {
  await browser.close();
  await new Promise(r => server.close(r));
}
