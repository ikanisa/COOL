import { digest, normalizeEmail, randomToken } from './security.mjs';
import { buildTransactionalEmail } from './emails.mjs';

export class EmailDispatchError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new EmailDispatchError(status, code, message); };
const now = () => Math.floor(Date.now() / 1000);
const q = (env, sql, ...args) => env.ADMIN_DB.prepare(sql).bind(...args);
const auth = `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users u ON u.id=s.user_id WHERE s.token_hash=? AND u.id=? AND s.auth_version=? AND u.auth_version=s.auth_version AND u.status='active' AND u.role=? AND s.expires_at>unixepoch())`;
const authArgs = user => [user.token_hash, user.id, user.auth_version, user.role];
const masked = email => { const parts = (email || '').split('@'); return parts.length === 2 ? `${parts[0].slice(0, 1)}•••@${parts[1]}` : 'Unavailable'; };
const states = ['queued','leased','send_started','accepted','delivered','failed_no_send','uncertain','suppressed'];
const preference = type => ['contribution_posted','contribution_confirmation'].includes(type) ? 'contribution_confirmations'
  : type === 'payment_reminder' ? 'payment_reminders'
  : type === 'security_notice' ? 'security_notices'
  : type === 'user_created' ? null : 'group_updates';

// Only a queued row can be claimed. An expired reservation that never started
// can be reclaimed; once sending starts, loss of proof becomes uncertain.
export async function dispatchEmailBatch(env, maximum = 20) {
  if (env.ENVIRONMENT === 'local' || !env.EMAIL?.send) fail(503, 'email_unavailable', 'Cloudflare Email Service is unavailable.');
  const at = now();
  await env.ADMIN_DB.batch([
    q(env, "UPDATE collect_notification_outbox SET status='queued',lease_token_sha256=NULL,lease_until=NULL,updated_at=? WHERE status='leased' AND lease_until<=?", at, at),
    q(env, "UPDATE collect_notification_outbox SET status='uncertain',lease_token_sha256=NULL,lease_until=NULL,outcome_evidence_key='dispatch:started_lease_expired',updated_at=? WHERE status='send_started' AND lease_until<=?", at, at),
  ]);
  const rows = await q(env, "SELECT id FROM collect_notification_outbox WHERE status='queued' ORDER BY created_at,id LIMIT ?", Math.min(20, Math.max(1, maximum))).all();
  const counts = { accepted: 0, uncertain: 0, suppressed: 0 };
  for (const candidate of rows.results) {
    const lease = await digest(randomToken());
    const item = await q(env, `UPDATE collect_notification_outbox SET status='leased',attempt_count=attempt_count+1,lease_token_sha256=?,lease_until=?,updated_at=? WHERE id=? AND status='queued' RETURNING *`, lease, now() + 120, now(), candidate.id).first();
    if (!item) continue;
    let payload;
    try { payload = JSON.parse(item.payload_json); } catch { payload = null; }
    const to = normalizeEmail(payload?.to);
    let formatted;
    try { formatted = buildTransactionalEmail({ subject: payload?.subject, text: payload?.text }); } catch { /* Suppress invalid content before any send. */ }
    const allowed = item.channel === 'email' && to && to === payload.to && formatted;
    if (!allowed) {
      await q(env, "UPDATE collect_notification_outbox SET status='suppressed',lease_token_sha256=NULL,lease_until=NULL,updated_at=? WHERE id=? AND status='leased' AND lease_token_sha256=?", now(), item.id, lease).run();
      counts.suppressed++; continue;
    }
    const category=preference(item.notification_type);
    const optionalMail=category ? ` AND EXISTS(SELECT 1 FROM member_notification_preferences p WHERE p.user_id=recipient_user_id AND p.${category}=1)` : '';
    const start = await q(env, `UPDATE collect_notification_outbox SET status='send_started',updated_at=? WHERE id=? AND status='leased' AND lease_token_sha256=? AND lease_until>? AND EXISTS(SELECT 1 FROM collect_users u WHERE u.id=recipient_user_id AND u.status='active' AND u.email=?)${optionalMail} RETURNING id`, now(), item.id, lease, now(), to).first();
    if (!start) {
      const result = await q(env, "UPDATE collect_notification_outbox SET status='suppressed',lease_token_sha256=NULL,lease_until=NULL,updated_at=? WHERE id=? AND status='leased' AND lease_token_sha256=?", now(), item.id, lease).run();
      if (result.meta.changes) counts.suppressed++;
      continue;
    }
    try {
      const result = await env.EMAIL.send({ from: { email: 'info@ikanisa.com', name: 'Collect' }, to, subject: payload.subject, ...formatted });
      if (typeof result?.messageId !== 'string' || !result.messageId) throw new Error('Unconfirmed provider acceptance');
      const provider = result.messageId.slice(0, 256);
      const saved = await q(env, "UPDATE collect_notification_outbox SET status='accepted',lease_token_sha256=NULL,lease_until=NULL,provider_reference=?,accepted_at=?,updated_at=? WHERE id=? AND status='send_started' AND lease_token_sha256=?", provider, now(), now(), item.id, lease).run();
      if (saved.meta.changes) counts.accepted++;
      else counts.uncertain++;
    } catch {
      // No secret/provider-error logs and no automatic retry after a send call.
      await q(env, "UPDATE collect_notification_outbox SET status='uncertain',lease_token_sha256=NULL,lease_until=NULL,outcome_evidence_key='dispatch:provider_outcome_unknown',updated_at=? WHERE id=? AND status='send_started' AND lease_token_sha256=?", now(), item.id, lease).run();
      counts.uncertain++;
    }
  }
  return counts;
}

export async function handleEmailAdmin(request, env, user) {
  const url = new URL(request.url); const path = url.pathname.slice('/api/admin/email'.length);
  const access = await q(env, `SELECT ${auth} AS allowed`, ...authArgs(user)).first();
  if (access?.allowed !== 1) fail(401, 'unauthenticated', 'Sign in again to continue.');
  if (request.method === 'GET' && path === '/events') {
    if ([...url.searchParams.keys()].some(key => !['limit','offset','status'].includes(key))) fail(400, 'invalid_request', 'Unsupported filter.');
    const limit = Number(url.searchParams.get('limit') || 25); const offset = Number(url.searchParams.get('offset') || 0); const status = url.searchParams.get('status');
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset < 0 || (status && !states.includes(status))) fail(400, 'invalid_request', 'Invalid email filter.');
    const filter = status ? 'WHERE status=?' : ''; const args = status ? [status] : [];
    const [access, count, list] = await env.ADMIN_DB.batch([
      q(env, `SELECT ${auth} AS allowed`, ...authArgs(user)),
      q(env, `SELECT count(*) AS n FROM collect_notification_outbox ${filter}`, ...args),
      q(env, `SELECT id,notification_type,status,attempt_count,created_at,updated_at,accepted_at,delivered_at,json_extract(payload_json,'$.to') AS recipient FROM collect_notification_outbox ${filter} ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?`, ...args, limit, offset),
    ]);
    if (access.results[0].allowed !== 1) fail(401, 'unauthenticated', 'Sign in again to continue.');
    return { rows: list.results.map(({ recipient, ...row }) => ({ ...row, recipient_masked: masked(recipient) })), total: count.results[0].n, limit, offset };
  }
  if (request.method !== 'POST' || path !== '/dispatch') fail(404, 'not_found', 'Email action not found.');
  if (!['owner','admin'].includes(user.role)) fail(403, 'permission_denied', 'Only administrators can dispatch emails.');
  if (env.ENVIRONMENT === 'local' || !env.EMAIL?.send) fail(503, 'email_unavailable', 'Cloudflare Email Service is unavailable.');
  const key = request.headers.get('Idempotency-Key');
  if (!/^[A-Za-z0-9_.-]{8,200}$/.test(key || '')) fail(400, 'invalid_request', 'A valid request key is required.');
  if (!request.headers.get('Content-Type')?.startsWith('application/json') || Number(request.headers.get('Content-Length') || 0) > 2048) fail(400, 'invalid_request', 'Send a small JSON request.');
  const reader=request.body?.getReader();if(!reader)fail(400,'invalid_request','Send a JSON request.');
  const decoder=new TextDecoder();let raw='',size=0;
  while(true){const chunk=await reader.read();if(chunk.done)break;size+=chunk.value.byteLength;if(size>2048){await reader.cancel();fail(413,'request_too_large','Request is too large.');}raw+=decoder.decode(chunk.value,{stream:true});}
  raw+=decoder.decode();
  let data; try { data = JSON.parse(raw); } catch { fail(400, 'invalid_request', 'Send a JSON request.'); }
  if (!data || Object.keys(data).some(key => key !== 'reason') || typeof data.reason !== 'string' || data.reason.trim().length < 8 || data.reason.length > 1000) fail(400, 'invalid_request', 'Enter a reason of 8 to 1000 characters.');
  const hash = await digest(`POST:/api/admin/email/dispatch:${data.reason.trim()}`); const id = crypto.randomUUID(); const at = now();
  const result = await env.ADMIN_DB.batch([
    q(env, `INSERT INTO collect_mutation_guards(id,passed) VALUES(?,CASE WHEN ${auth} THEN 1 ELSE 0 END)`, id, ...authArgs(user)),
    q(env, "INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'email_dispatch',?,?,?) ON CONFLICT(actor_admin_id,idempotency_key) DO NOTHING RETURNING id", id, user.id, key, hash, at),
    q(env, `INSERT INTO collect_operations_audit(id,actor_admin_id,operation_request_id,action,subject_type,subject_id,evidence_json,occurred_at) SELECT ?,?,?,'email_dispatch_requested','email_dispatch',?,json_object('reason',?),? WHERE EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)`, crypto.randomUUID(), user.id, id, id, data.reason.trim(), at, id),
    q(env, 'DELETE FROM collect_mutation_guards WHERE id=?', id),
  ]).catch(error => {
    if (String(error).includes('collect_operation_guard_failed')) fail(401, 'unauthenticated', 'Sign in again to continue.');
    throw error;
  });
  if (!result[1].meta.changes) {
    const previous = await q(env, 'SELECT * FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key).first();
    if (previous?.request_sha256 !== hash) fail(409, 'idempotency_conflict', 'This request key was used for another action.');
    if (previous.status === 'pending') fail(409, 'dispatch_pending', 'This dispatch is still unresolved. Check the email events before taking another action.');
    return JSON.parse(previous.response_json);
  }
  const counts = await dispatchEmailBatch(env);
  const receipt = { request_id: id, resource_type: 'email_dispatch', resource_id: id, version: 1, status: 'succeeded', ...counts };
  await q(env, "UPDATE collect_operation_requests SET status='succeeded',response_json=?,completed_at=? WHERE id=? AND status='pending'", JSON.stringify(receipt), now(), id).run();
  return receipt;
}
