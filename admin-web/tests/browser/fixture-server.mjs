// Local, read-only synthetic browser fixture. Never use for a deployed Admin.
import {createServer} from 'node:http';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import {versionedStatic} from '../../../deploy/platform-admin/src/static-recovery.js';

const root = path.resolve(process.argv[2] ?? '');
if (!process.argv[2] || !(await fs.stat(root)).isDirectory()) throw new Error('Provide a candidate directory.');
const port = Number(process.env.COLLECT_FIXTURE_PORT ?? 4173);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid fixture port.');
const origin = `http://127.0.0.1:${port}`;
const counts = {users: 4, groups: 2, active_members: 4, payees: 2, transactions: 1, app_users: 3,
  direct_users: 1, admin_users: 1, staff_users: 1, active_payees: 2, unallocated_transactions: 1,
  ledger_entries: 0, reversed_entries: 0, payment_evidence: 1};
const amounts = {total_recorded_rwf: '5000', total_reconciled_rwf: '0', total_unallocated_rwf: '5000', total_net_contributions_rwf: '0'};
const labels = {users: 'Users', groups: 'Groups', active_members: 'Active members', payees: 'Payees',
  transactions: 'Transactions', app_users: 'App users', direct_users: 'Direct users', admin_users: 'Admin users',
  staff_users: 'Staff users', active_payees: 'Active payees', unallocated_transactions: 'Unallocated transactions',
  ledger_entries: 'Ledger entries', reversed_entries: 'Reversal entries', payment_evidence: 'Retained payment evidence',
  total_recorded_rwf: 'Recorded evidence amount', total_reconciled_rwf: 'Reconciled evidence amount',
  total_unallocated_rwf: 'Unallocated evidence amount', total_net_contributions_rwf: 'Net recorded contributions'};
const overview = {contract_version: 2, model: 'canonical_evidence_ledger', country_code: 'RW',
  measured_at: '2026-11-16T12:00:00.000Z', counts, amounts, contribution_basis: 'reconciled_evidence_entries',
  collected_basis: 'retained_received_evidence', reconciliations_available: true,
  metrics: Object.entries(labels).map(([key, label]) => ({key, label, status: 'measured', value: String(counts[key] ?? amounts[key])}))};
const user = {id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', email: 'fixture@example.test', role: 'owner',
  sessionId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', principalId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  financialModel: 'canonical_evidence_ledger', assuranceLevel: 1, mfaAt: null,
  permissions: ['overview.read', 'collections.read', 'users.read', 'receivers.read', 'payments.read', 'ledger.read',
    'reconciliations.read', 'sms.read', 'gateway.read', 'email.read', 'account.manage', 'admin_users.read']};
// Synthetic captures for reviewing the SMS layout; these never represent real
// messages, extracted facts, confirmed payments or provider settlement.
const smsCaptures = [
  ['11111111-1111-4111-8111-111111111111', '123456', 'Demo member A', 'received', '2026-11-16T10:00:00+02:00'],
  ['22222222-2222-4222-8222-222222222222', '234567', 'Demo member B', 'under_review', '2026-11-16T09:20:00+02:00'],
  ['33333333-3333-4333-8333-333333333333', '345678', 'Demo member C', 'received', '2026-11-15T17:45:00+02:00'],
].map(([id, public_id, display_name, status, received_at_device]) => {
  const received_at = Date.parse(received_at_device) / 1000;
  return {source_kind: 'capture', id, user_id: user.id, payee_id: null, source_sha256: 'a'.repeat(64), status, version: 1,
    received_at, created_at: received_at, public_id, display_name, transaction_id: null, evidence_level: 'client_received',
    source_fact_id: null, parser_version: null, extraction_status: 'not_extracted', source_body_sha256: null, source_payload_sha256: null,
    parsed_at: null, payer_name: null, payer_phone: null, payer_masked_phone: null, payer_last3: null, payee_momo_number: null,
    payee_momo_code: null, momo_transaction_reference: null, momo_timestamp_local: null, momo_timezone_offset: null, amount_rwf: null,
    wallet_balance_rwf: null, network: null, direction: null, is_payment: null, transaction_reference: null,
    duplicate_reference_count: 0, conflicting_reference_count: 0, provider_confirmation: false, settlement_status: 'not_asserted',
    timezone_known: false, payer_last3_known: false, source_content_reveal_required: true, received_at_device};
});
const useCookieSignIn = process.env.COLLECT_FIXTURE_SIGN_IN === '1';
const csrfToken = 'c'.repeat(64);
const cookieKey = 'collect_fixture_session';
const sessionCookie = `${cookieKey}=signed-in`;
const mime = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.ttf': 'font/ttf', '.txt': 'text/plain; charset=utf-8'};
function json(response, status, body, extraHeaders = {}) {
  response.writeHead(status, {'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extraHeaders});
  response.end(JSON.stringify(body));
}

createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', origin);
  if (url.origin !== origin) return json(response, 403, {error: {code: 'fixture_origin_denied'}});
  if (process.env.COLLECT_FIXTURE_MISSING_ENTRY === '1' && /^\/_build\/[a-f0-9]{64}\/assets\/admin-entry\.js$/.test(url.pathname)) {
    const recovery = await versionedStatic(new Request(url, {method: request.method}), {fetch: async () =>
      new Response('<html>synthetic SPA fallback</html>', {headers: {'Content-Type': 'text/html'}})});
    response.writeHead(recovery.status, Object.fromEntries(recovery.headers));
    return response.end(await recovery.text());
  }
  if (url.pathname.startsWith('/api/')) {
    const signedIn = !useCookieSignIn || request.headers.cookie?.split(';').some(cookie => cookie.trim() === sessionCookie);
    if (useCookieSignIn && request.method === 'POST' && ['/api/admin/auth/otp', '/api/admin/auth/verify'].includes(url.pathname)) {
      let payload;
      try {const chunks = []; for await (const part of request) chunks.push(part); payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));} catch {return json(response, 400, {error: {code: 'invalid_fixture'}});}
      if (payload.email !== user.email) return json(response, 400, {error: {code: 'invalid_fixture'}});
      if (url.pathname.endsWith('/otp')) return json(response, 200, {challenge_id: 'synthetic-fixture', retry_after: 60, expires_in: 300, delivery_status: 'accepted'});
      if (payload.challenge_id !== 'synthetic-fixture' || payload.code !== '123456') return json(response, 401, {error: {code: 'invalid_credentials'}});
      return json(response, 200, {user, expiresAt: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(), csrfToken},
        {'Set-Cookie': `${sessionCookie}; Path=/; HttpOnly; SameSite=Strict`});
    }
    if (useCookieSignIn && request.method === 'POST' && url.pathname === '/api/admin/auth/logout') {
      if (!signedIn || request.headers['x-collect-csrf'] !== csrfToken) return json(response, 401, {error: {code: 'fixture_unauthorized'}});
      return json(response, 200, {ok: true}, {'Set-Cookie': `${cookieKey}=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict`});
    }
    if (request.method !== 'GET') return json(response, 405, {error: {code: 'fixture_read_only'}});
    if (url.pathname === '/api/admin/auth/session') {
      if (!signedIn) return json(response, 200, {user: null, expiresAt: null, csrfToken: null, ownerEmail: null});
      const lifetime = process.env.COLLECT_FIXTURE_LONG_EXPIRY === '1' ? 40 * 24 * 60 * 60 * 1000 : 2 * 60 * 60 * 1000;
      return json(response, 200, {user, expiresAt: new Date(Date.now() + lifetime).toISOString(), csrfToken, ownerEmail: null});
    }
    if (!signedIn) return json(response, 401, {error: {code: 'fixture_unauthorized'}});
    if (url.pathname === '/api/admin/auth/email-verification') {
      return json(response, 200, {contractVersion: 1, sessionId: user.sessionId, emailVerifiedAt: null});
    }
    if (url.pathname === '/api/admin/core/overview') return json(response, 200, overview);
    if (url.pathname === '/api/admin/sms/receipts') {
      const offset = Number(url.searchParams.get('offset') ?? 0), limit = Number(url.searchParams.get('limit') ?? 25);
      if (!Number.isSafeInteger(offset) || offset < 0 || limit !== 25) return json(response, 400, {error: {code: 'invalid_fixture'}});
      const search = (url.searchParams.get('search') ?? '').toLowerCase(), status = url.searchParams.get('status') ?? '', kind = url.searchParams.get('source_kind') ?? '';
      const all = smsCaptures.filter(row => (!kind || row.source_kind === kind) && (!status || row.status === status) &&
        (!search || `${row.id} ${row.public_id} ${row.display_name}`.toLowerCase().includes(search)));
      const rows = all.slice(offset, offset + limit);
      return json(response, 200, {rows, total: all.length, limit, offset, next_offset: offset + rows.length < all.length ? offset + rows.length : null});
    }
    const smsDetail = url.pathname.match(/^\/api\/admin\/sms\/receipts\/capture\/([a-f0-9-]+)$/);
    if (smsDetail) {
      const row = smsCaptures.find(item => item.id === smsDetail[1]);
      if (!row) return json(response, 404, {error: {code: 'fixture_not_found'}});
      const offset = Number(url.searchParams.get('offset') ?? 0);
      if (!Number.isSafeInteger(offset) || offset < 0) return json(response, 400, {error: {code: 'invalid_fixture'}});
      return json(response, 200, {resource_type: 'sms_receipts', resource: row, current_actor_id: user.id, can_extract: false,
        related: {duplicate_references: {rows: [], total: 0, limit: 25, offset, next_offset: null}}});
    }
    if (/^\/api\/admin\/core\/(?:groups|users|members|payees|transactions|ledgers)$/.test(url.pathname) || url.pathname === '/api/admin/operations/requests') {
      return json(response, 200, {contract_version: 2, model: 'canonical_evidence_ledger', rows: [], total: 0});
    }
    return json(response, 404, {error: {code: 'fixture_not_found'}});
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {response.writeHead(405); return response.end();}
  let relative;
  try {relative = decodeURIComponent(url.pathname).replace(/^\/+/, '');} catch {response.writeHead(400); return response.end();}
  if (!relative || relative === 'index.html' || /^admin(?:\/[^.]*)?$/.test(relative)) relative = 'index.html';
  const target = path.resolve(root, relative);
  if (!target.startsWith(`${root}${path.sep}`)) {response.writeHead(403); return response.end();}
  try {
    const data = await fs.readFile(target);
    response.writeHead(200, {'Content-Type': mime[path.extname(target)] ?? 'application/octet-stream', 'Cache-Control': 'no-store'});
    response.end(request.method === 'HEAD' ? undefined : data);
  } catch {response.writeHead(404, {'Content-Type': 'text/plain'}); response.end('Not found');}
}).listen(port, '127.0.0.1', () => console.log(`Synthetic Admin fixture listening on ${origin}`));
