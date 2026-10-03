import fs from 'node:fs/promises';
import { writeFileSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import crypto from 'node:crypto';
import { chromium } from '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.mjs';

const output = path.resolve(process.env.COLLECT_ROSTER_BROWSER_PACKET);
const root = path.resolve(process.env.COLLECT_ROSTER_BROWSER_WEB);
const receiptFile = path.resolve(process.env.COLLECT_ROSTER_BROWSER_SQL_RECEIPTS);
if (!process.env.COLLECT_ROSTER_BROWSER_PACKET || !process.env.COLLECT_ROSTER_BROWSER_WEB || !process.env.COLLECT_ROSTER_BROWSER_SQL_RECEIPTS) throw Error('Explicit immutable browser/receipt inputs required');
await fs.mkdir(output, { recursive: true });
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const receiptBytes = await fs.readFile(receiptFile);
const actualLines = receiptBytes.toString().split('\n').filter(s => s.startsWith('ROSTER_FRESH_AUTH_RECEIPT_JSON|'));
if (actualLines.length !== 1) throw Error('Exactly one root-owned SQL149 receipt required');
const actual = JSON.parse(actualLines[0].substring('ROSTER_FRESH_AUTH_RECEIPT_JSON|'.length));
const clone = v => JSON.parse(JSON.stringify(v));
const actor = actual.listing.actor_id;
const ids = { A: '99890000-0000-4000-8000-000000000011', B: actual.listing.destination_session_id };
const session = which => ({ access_token: `e30.${Buffer.from(JSON.stringify({ sub: actor, session_id: ids[which], exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.synthetic`, refresh_token: `synthetic-refresh-${which}`, token_type: 'bearer', expires_in: 3600, user: { id: actor, aud: 'authenticated', app_metadata: {}, user_metadata: {}, created_at: '2026-09-30T00:00:00Z' } });
const requests = [], checks = [], errors = [], adapted = new Set();
let transferRequest = null, loseTransfer = false, staged = new Map();
let transferBody = null, transferEffects = 0;
const lossMode = process.env.COLLECT_ROSTER_LOSS_MODE ?? 'after_headers';
if (!['after_headers', 'before_headers'].includes(lossMode)) throw Error('Unknown response loss fixture mode');
let identityHold = false;
const heldIdentityResponses = [];
const typed = (res, value, status = 200) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(value)); };
const deny = (res, message) => typed(res, { code: '42501', message, details: null, hint: null }, 403);
const lineage = value => { if (value?.recovery_lineage) value.recovery_lineage.transfer_request_id = transferRequest; return value; };
const server = http.createServer(async (req, res) => {
  const pathname = new URL(req.url, 'http://fixture').pathname;
  let body = ''; if (req.method !== 'GET') for await (const part of req) body += part;
  let p = {}; if (body) try { p = JSON.parse(body); } catch { return typed(res, { code: 'bad_json' }, 400); }
  const rpc = pathname.startsWith('/rest/v1/rpc/') ? pathname.split('/').at(-1) : null;
  requests.push({ method: req.method, path: pathname, rpc, sdk_retry_count: req.headers['x-retry-count'] ?? null }); // No tokens, bodies, names or phones.
  if (pathname === '/fixture-control/reset') { transferRequest = null; transferBody = null; staged = new Map(); loseTransfer = false; return typed(res, { ok: true }); }
  if (pathname === '/fixture-control/loss-transfer') { loseTransfer = true; return typed(res, { ok: true }); }
  if (pathname === '/fixture-control/identity-hold') { identityHold = true; return typed(res, { ok: true }); }
  if (pathname === '/fixture-control/identity-release') {
    identityHold = false;
    for (const reply of heldIdentityResponses.splice(0)) typed(reply, { user_id: actor, display_name: 'Synthetic local roster operator', phone_masked: null, roles: ['admin'], permissions: ['collections.moderate', 'users.read'] });
    return typed(res, { ok: true });
  }
  if (pathname.startsWith('/auth/v1/')) {
    if (pathname.endsWith('/logout')) { res.writeHead(204); return res.end(); }
    const which = p.token === 'B' || p.refresh_token === 'synthetic-refresh-B' ? 'B' : 'A';
    return typed(res, session(which));
  }
  if (rpc) {
    let claims; try { claims = JSON.parse(Buffer.from((req.headers.authorization ?? '').split('.')[1], 'base64url')); } catch { return deny(res, 'roster_session_required'); }
    if (claims.sub !== actor || !Object.values(ids).includes(claims.session_id)) return deny(res, 'roster_session_required');
    if (rpc === 'admin_current_user') {
      if (identityHold) { heldIdentityResponses.push(res); return; }
      return typed(res, { user_id: actor, display_name: 'Synthetic local roster operator', phone_masked: null, roles: ['admin'], permissions: ['collections.moderate', 'users.read'] });
    }
    if (claims.session_id !== ids.B) return deny(res, 'roster_fresh_auth_required');
    switch (rpc) {
      case 'admin_list_interrupted_roster_imports': return typed(res, actual.listing);
      case 'admin_inspect_interrupted_roster_import':
        if (p.p_import_id !== actual.inspected.import_id || p.p_etag !== actual.inspected.etag) return deny(res, 'roster_draft_superseded');
        return typed(res, actual.inspected);
      case 'admin_transfer_interrupted_roster_import': {
        if (transferRequest) {
          if (JSON.stringify(p) !== transferBody) return deny(res, 'roster_request_conflict');
          return typed(res, { ...actual.ack, request_id: transferRequest });
        }
        if (p.p_human_affirmed !== true || p.p_import_id !== actual.transfer_request.p_import_id || p.p_etag !== actual.transfer_request.p_etag) return deny(res, 'roster_request_conflict');
        transferRequest = p.p_request_id;
        transferBody = JSON.stringify(p);
        transferEffects++;
        adapted.add('transfer_request_id');
        if (loseTransfer) {
          loseTransfer = false;
          if (lossMode === 'before_headers') return res.destroy();
          // Acknowledged server effect, then loss of an incomplete response.
          // Sending headers distinguishes this from a reused TCP socket reset
          // that Chrome can transparently retransmit before any HTTP response.
          res.writeHead(200, { 'content-type': 'application/json', 'content-length': '8192' });
          res.flushHeaders();
          res.write('{"contract_version":');
          setTimeout(() => res.destroy(), 50);
          return;
        }
        return typed(res, { ...actual.ack, request_id: transferRequest });
      }
      case 'admin_get_roster_transfer_status':
        if (p.p_request_id !== transferRequest) return deny(res, 'roster_request_conflict');
        return typed(res, { ...actual.ack, request_id: transferRequest });
      case 'admin_recover_roster_import': {
        if (p.p_upload_request_id !== actual.ack.destination_reference_id || p.p_pending_request_id !== null) return deny(res, 'roster_recovery_payload_invalid');
        const v = clone(actual.recovered);
        lineage(v.initial_preview); lineage(v.status.preview);
        return typed(res, v);
      }
      case 'admin_stage_roster_import_intent': {
        if (p.p_import_id !== actual.ack.to_import_id || !['review', 'commit'].includes(p.p_kind) || sha(Buffer.from(p.p_payload)) !== p.p_payload_sha256) return deny(res, 'roster_recovery_payload_invalid');
        staged.set(p.p_request_id, clone(p));
        return typed(res, { contract_version: 1, ok: true, import_id: p.p_import_id, request_id: p.p_request_id, kind: p.p_kind, payload_sha256: p.p_payload_sha256, expires_at: actual.ack.expires_at });
      }
      case 'admin_execute_roster_import_intent': {
        const intent = staged.get(p.p_request_id);
        if (!intent || p.p_human_affirmed !== true || intent.p_payload_sha256 !== p.p_payload_sha256) return deny(res, 'roster_confirmation_required');
        const payload = JSON.parse(intent.p_payload);
        if (payload.p_request_id !== p.p_request_id || payload.p_import_id !== actual.ack.to_import_id) return deny(res, 'roster_request_conflict');
        let result;
        if (intent.p_kind === 'review') {
          if (payload.p_parent_revision_id !== actual.ack.initial_revision_id || JSON.stringify(payload.p_rows) !== JSON.stringify(JSON.parse(actual.recovered.draft.payload).rows)) return deny(res, 'roster_rows_invalid');
          result = lineage(clone(actual.reviewed));
        } else {
          if (payload.p_revision_id !== actual.reviewed.revision_id || payload.p_reviewed_rows_sha256 !== actual.reviewed.reviewed_rows_sha256 || payload.p_human_affirmed !== true) return deny(res, 'roster_revision_superseded');
          adapted.add('commit_request_id'); result = { ...actual.commit, request_id: p.p_request_id };
        }
        return typed(res, { contract_version: 1, ok: true, request_id: p.p_request_id, import_id: actual.ack.to_import_id, kind: intent.p_kind, payload_sha256: p.p_payload_sha256, result });
      }
      default: return typed(res, { code: 'unknown_fixture_rpc', message: 'unknown_fixture_rpc' }, 404);
    }
  }
  const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
  if (!file.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
  try {
    const bytes = await fs.readFile(file), ext = path.extname(file);
    res.setHeader('content-type', ({ '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.ttf': 'font/ttf', '.png': 'image/png' })[ext] ?? 'application/octet-stream');
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ executablePath: '/Users/jeanbosco/.cache/selenium/chrome/mac-arm64/151.0.7922.34/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing', headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
await context.addInitScript(() => {
  // Observe fetch dispatches only; never record headers, bodies or credentials.
  window.__rosterFetchDispatches = [];
  const original = window.fetch;
  window.fetch = function(input, options) {
    const url = new URL(typeof input === 'string' ? input : input.url, location.href);
    if (url.pathname.startsWith('/rest/v1/rpc/')) {
      window.__rosterFetchDispatches.push({ method: options?.method ?? input.method ?? 'GET', rpc: url.pathname.split('/').at(-1) });
    }
    return original.apply(this, arguments);
  };
});
await context.route('**/*', route => route.request().url().startsWith(origin) ? route.continue() : route.abort());
const pages = [];
function check(id, pass) {
  checks.push({ id, pass: !!pass });
  writeFileSync(path.join(output, 'checkpoint.json'), JSON.stringify({ phase: id, checks, requests }, null, 2) + '\n');
  if (!pass) throw Error(id);
}
const state = async page => JSON.parse(await page.locator('#roster-fixture-status').textContent());
const fetchDispatches = page => page.evaluate(() => window.__rosterFetchDispatches);
const wait = async (page, conditions) => page.waitForFunction(conditions => {
  const s = JSON.parse(document.querySelector('#roster-fixture-status')?.textContent ?? '{}');
  return Object.entries(conditions).every(([key, value]) => s[key] === value);
}, conditions);
const activate = async (page, name) => { const target = page.getByRole('button', { name, exact: true }); await target.focus(); await page.keyboard.press('Enter'); };
const inspectSaved = async page => {
  const sourceKind = actual.listing.items[0].source_kind.toUpperCase();
  const target = page.getByRole('button', { name: new RegExp('^' + sourceKind + '[\\s\\S]*Interrupted') });
  await target.focus(); await page.keyboard.press('Enter');
};
const open = async () => { const page = await context.newPage(); pages.push(page); page.on('pageerror', () => errors.push('page_runtime_error')); await page.goto(origin); await wait(page, { boot: 'ready' }); return page; };
const storage = async page => page.evaluate(async () => ({ local: { ...localStorage }, session: { ...sessionStorage }, indexed: (await indexedDB.databases()).map(d => d.name), caches: await caches.keys(), cookie: document.cookie }));
const safeStorage = (s, allowBookmark = false) => Object.keys(s.local).length === 0 && Object.keys(s.session).every(k => allowBookmark && k === 'collect.admin.roster.recovery.v1') && s.indexed.length === 0 && s.caches.length === 0 && s.cookie === '' && !JSON.stringify(s).includes('synthetic-refresh') && !JSON.stringify(s).includes('access_token') && !JSON.stringify(s).includes('Private unsaved');
let status = 'running';
try {
  const a = await open(), peer = await open();
  check('production-initialize-starts-signed-out-with-empty-browser-storage', !(await state(a)).authenticated && safeStorage(await storage(a)));
  await activate(a, 'Sign in synthetic A'); await wait(a, { authenticated: true, identity_ready: true });
  check('normal-Supabase-sign-in-is-not-adopted-by-peer', !(await state(peer)).authenticated);
  await activate(a, 'Open production roster'); await wait(a, { dialog: true });
  await a.getByRole('textbox', { name: 'Group name', exact: true }).fill('Private unsaved group');
  await a.getByRole('textbox', { name: /^Reason/ }).fill('Private unsaved reason');
  await a.getByRole('textbox', { name: 'Member roster', exact: true }).fill('Private unsaved member,PRIVATE UNSAVED,+250788989001');
  check('normal-Admin-unsaved-roster-never-enters-browser-storage', safeStorage(await storage(a)));
  await a.reload(); await wait(a, { boot: 'ready', authenticated: false, dialog: false });
  await activate(peer, 'Sign in synthetic A'); await wait(peer, { authenticated: true });
  await activate(peer, 'Refresh synthetic sign-in');
  check('full-reload-and-peer-refresh-cannot-restore-credentials-or-editor', !(await state(a)).authenticated && safeStorage(await storage(a)));
  await activate(a, 'Sign in synthetic B'); await wait(a, { authenticated: true, identity_ready: true });
  await activate(a, 'Open production roster'); await wait(a, { dialog: true });
  await activate(a, 'Find saved imports after fresh sign-in'); await wait(a, { interrupted_count: 1, busy: false });
  check('fresh-lookup-is-read-only', requests.filter(r => r.rpc?.includes('transfer') || r.rpc?.includes('execute')).length === 0);
  await inspectSaved(a);
  await wait(a, { inspected: true, busy: false });
  check('actual-Admin-inspection-keeps-approval-and-submit-disabled', !(await state(a)).fresh_affirmed && !(await state(a)).can_commit);
  await a.getByRole('checkbox', { name: 'Recover this saved editor into my fresh sign-in and review every page again.', exact: true }).check();
  await context.request.post(origin + '/fixture-control/loss-transfer');
  await activate(a, 'Recover saved editor'); await wait(a, { transfer_pending: true, busy: false });
  check('response-loss-leaves-uncertain-transfer-with-no-preview', !(await state(a)).preview && requests.filter(r => r.rpc === 'admin_transfer_interrupted_roster_import').length === 1 && (await fetchDispatches(a)).filter(r => r.rpc === 'admin_transfer_interrupted_roster_import').length === 1 && transferEffects === 1);
  await activate(a, 'Check transfer outcome without repeating it'); await wait(a, { preview: true, busy: false });
  check('status-read-adopts-actual149-lineage-without-repeating-transfer', requests.filter(r => r.rpc === 'admin_transfer_interrupted_roster_import').length === 1);
  check('recovered-editor-resets-review-and-confirmation', (await state(a)).edited && !(await state(a)).can_submit && !(await state(a)).affirmed && !(await state(a)).can_commit);
  const saved = await storage(a), bookmark = JSON.parse(saved.session['collect.admin.roster.recovery.v1']);
  check('production-browser-bookmark-contains-only-versioned-references-and-digests', safeStorage(saved, true) && bookmark.version === 1 && Object.keys(bookmark).every(k => ['version', 'owner_digest', 'upload_request_id', 'source_sha256', 'collection_id', 'import_id', 'checkpoint_id', 'pending_request_id', 'pending_sha256'].includes(k)) && !JSON.stringify(saved).includes('Synthetic149'));
  await activate(a, 'Save reviewed rows'); await wait(a, { edited: false, can_submit: true, busy: false });
  check('new-human-review-is-required-before-confirming-submission', !(await state(a)).affirmed && !(await state(a)).can_commit);
  await a.getByRole('checkbox', { name: /I have reviewed all/ }).check();
  await wait(a, { can_commit: true });
  await activate(a, 'Create group and add members'); await wait(a, { dialog: false, outcome: 'acknowledged' });
  check('production-Admin-dialog-closes-only-after-exact-operation-ACK', staged.size === 2 && requests.filter(r => r.rpc === 'admin_execute_roster_import_intent').length === 2);
  check('acknowledged-completion-clears-browser-recovery-reference', safeStorage(await storage(a)));
  await context.request.post(origin + '/fixture-control/reset');
  await activate(a, 'Open production roster'); await activate(a, 'Find saved imports after fresh sign-in'); await wait(a, { interrupted_count: 1, busy: false });
  await inspectSaved(a); await wait(a, { inspected: true, busy: false });
  await activate(peer, 'Sign in synthetic B'); await wait(peer, { authenticated: true, identity_ready: true }); await activate(peer, 'Sign out synthetic sign-in');
  await wait(a, { authenticated: false, dialog: false, inspected: false, row_count: 0 });
  check('same-session-peer-logout-clears-private-inspection-and-dialog-draft', safeStorage(await storage(a)));
  await a.screenshot({ path: path.join(output, 'revoked-production-dialog.png') });
  await activate(a, 'Sign in synthetic B'); await wait(a, { authenticated: true, identity_ready: true });
  await activate(a, 'Open production roster'); await wait(a, { dialog: true });
  await activate(a, 'Find saved imports after fresh sign-in'); await wait(a, { interrupted_count: 1, busy: false });
  await inspectSaved(a); await wait(a, { inspected: true, busy: false });
  await context.request.post(origin + '/fixture-control/identity-hold');
  await a.locator('#refresh-synthetic-operator-authority').click();
  await wait(a, { authenticated: true, identity_ready: false, dialog: false, inspected: false, row_count: 0 });
  check('production-roster-wrapper-clears-private-state-during-retained-identity-loading', safeStorage(await storage(a)));
  await context.request.post(origin + '/fixture-control/identity-release'); await wait(a, { identity_ready: true, dialog: false });
  check('authority-refresh-cannot-resurrect-old-dialog-or-approval', !(await state(a)).can_commit && !(await state(a)).inspected);
  for (let i = 0; i < pages.length; i++) check(`normal-Supabase-tab${i}-no-persisted-auth-or-private-roster`, safeStorage(await storage(pages[i])));
  check('browser-runtime-completes-without-unhandled-errors', errors.length === 0);
  status = 'pass';
} catch (error) {
  status = 'fail'; errors.push({ kind: 'assertion', message: String(error.message).replace(/e30\.[A-Za-z0-9_-]+\.synthetic/g, '[redacted]') });
  try {
    await fs.writeFile(path.join(output, 'failed-controls.json'), JSON.stringify(await pages[0].locator('[role=button],[role=checkbox],[role=textbox]').evaluateAll(nodes => nodes.map(n => ({ role: n.getAttribute('role'), label: n.getAttribute('aria-label'), checked: n.getAttribute('aria-checked'), disabled: n.getAttribute('aria-disabled') }))), null, 2) + '\n');
  } catch {}
  try { await pages[0]?.screenshot({ path: path.join(output, 'failed-phase.png') }); } catch {}
} finally {
  const applicationFetchDispatches = await Promise.all(pages.map(fetchDispatches));
  await fs.writeFile(path.join(output, 'report.json'), JSON.stringify({ status, origin, kind: 'production_Supabase_initialization_and_actual_Admin_roster_dialog_loopback', sql149_receipt_sha256: sha(receiptBytes), sql149_receipt_unchanged: sha(await fs.readFile(receiptFile)) === sha(receiptBytes), synthetic_transport_adapted_fields: [...adapted], response_loss_mode: lossMode, transfer_effects: transferEffects, application_fetch_dispatches: applicationFetchDispatches, checks, errors, requests, database_calls: 0, hosted_calls: 0, provider_calls: 0, scope: 'Actual production client initialization/gateway/dialog; retained149 PostgreSQL response structures with dynamic request-ID adapters. Synthetic loopback transport does not certify deployed authorization or provider execution.' }, null, 2) + '\n');
  for (const reply of heldIdentityResponses.splice(0)) reply.destroy();
  await context.close(); await browser.close(); await new Promise(r => server.close(r));
}
console.log(JSON.stringify({ status, checks: checks.length, errors: errors.length }));
if (status !== 'pass') process.exitCode = 1;
