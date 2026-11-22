import { digest, hex } from './security.mjs';

export const SMS_PARSER_VERSION = 'collect-admin-source-facts-v1';
export class AdminSmsError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new AdminSmsError(status, code, message); };
const invalid = message => fail(400, 'invalid_request', message);
const id = value => { if (typeof value !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value)) invalid('Invalid resource identifier.'); return value; };
const kind = value => { if (!['member', 'receiver'].includes(value)) invalid('Invalid receipt source.'); return value; };
const keyValid = key => typeof key === 'string' && /^[a-zA-Z0-9_.-]{8,200}$/.test(key);
const hashValid = hash => typeof hash === 'string' && /^[a-f0-9]{64}$/.test(hash);
const reasonText = value => { if (typeof value !== 'string' || value.trim().length < 8 || value.trim().length > 1000 || /[\x00-\x1f\x7f]/.test(value)) invalid('Record a review reason of 8 to 1000 characters.'); return value.trim(); };
const canonical = value => JSON.stringify(value, (_, nested) => nested && typeof nested === 'object' && !Array.isArray(nested) ? Object.fromEntries(Object.keys(nested).sort().map(key => [key, nested[key]])) : nested);
const stmt = (env, query, ...values) => env.ADMIN_DB.prepare(query).bind(...values);
const authSql = privileged => `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id
 WHERE s.token_hash=? AND a.id=? AND a.role=? AND a.status='active' AND a.role IN (${privileged ? "'owner','admin'" : "'owner','admin','staff'"})
 AND a.auth_version=s.auth_version AND s.auth_version=? AND s.expires_at>unixepoch())`;
const authArgs = user => [user.token_hash, user.id, user.role, user.auth_version];
async function read(env, user, statements, privileged = false) {
  const [authorization, ...results] = await env.ADMIN_DB.batch([stmt(env, `SELECT ${authSql(privileged)} AS allowed`, ...authArgs(user)), ...statements]);
  if (!authorization.results[0].allowed) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.'); return results;
}
const money = String.raw`([0-9][0-9, .\u00a0]*[0-9]|[0-9])`;
const incomingClause = String.raw`(?:you have received|payment received|received|credited|wakiriye|wahawe)`;
const receivedAmount = new RegExp(String.raw`\b${incomingClause}\s*:?\s*(?:RWF|FRW)\s+${money}(?=\s+(?:from|by|on|at)\b|[.;](?![0-9])|$)|\b${incomingClause}\s*:?\s*${money}\s*(?:RWF|FRW)\b`, 'gi');
const sentAmount = new RegExp(String.raw`\b(?:you have sent|you have paid|payment of)\s*:?\s*(?:(?:RWF|FRW)\s+${money}(?=\s+(?:to|on|at)\b|[.;](?![0-9])|$)|${money}\s*(?:RWF|FRW)\b)`, 'gi');
const balancePattern = new RegExp(String.raw`\b(?:(?:your|new|available|current)\s+)*balance\s*(?:is|:|=)?\s*(?:(?:RWF|FRW)\s+${money}(?=[.;](?![0-9])|$|\s+[A-Za-z])|${money}\s*(?:RWF|FRW)\b)`, 'gi');
const phone = String.raw`(?:\+?250\s*7[2389](?:[\s-]*\d){7}|07[2389](?:[\s-]*\d){7})`;
const namedPayer = new RegExp(String.raw`\bfrom\s+([^()\r\n]{2,120}?)\s*\(\s*(\*{3,}[0-9]{3}|${phone})\s*\)`, 'gi');
const plainPayer = new RegExp(String.raw`\b(?:from|sender|payer)(?:\s+number)?\s*[:#-]?\s*(${phone})(?![\d\s-]*\d)`, 'gi');
const payeeNumber = new RegExp(String.raw`\b(?:to|payee|receiver)(?:\s+(?:number|MoMo(?:\s+number)?))?\s*[:#-]?\s*(${phone})(?![\d\s-]*\d)`, 'gi');
const referencePattern = /(?:financial\s+transaction\s+id|transaction\s+id|txn|txid|reference|ref)\s*[:#-]?\s*([A-Z0-9][A-Z0-9._/-]{3,63})/gi;
const excluded = /\b(?:failed|reversed|reversal|cancelled|pending|declined|cash.?out|withdraw(?:al|n)?|promotion|promo|OTP|verification code|one.time password)\b/i;
const oneMatch = (value, pattern) => { const matches = [...value.matchAll(pattern)]; return matches.length === 1 ? matches[0] : null; };
function integerRwf(value) {
  if (value === undefined) return null; const clean = value.trim().replace(/\u00a0/g, ' ');
  if (!/^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,3}(?: [0-9]{3})+)$/.test(clean)) return null;
  const number = Number(clean.replace(/[, ]/g, '')); return Number.isSafeInteger(number) && number >= 0 ? number : null;
}
const amountFrom = (value, pattern) => { const match = oneMatch(value, pattern); return match ? integerRwf(match[1] ?? match[2]) : null; };
const normalizedPhone = value => value ? value.replace(/[^0-9+]/g, '') : null;
export function parseAdminSmsFacts(sender, body) {
  if (typeof sender !== 'string' || typeof body !== 'string' || body.length < 1 || body.length > 16000) invalid('Invalid preserved SMS source.');
  const networkText = `${sender}\n${body}`, airtel = /airtel/i.test(networkText), mtnBrand = /(?:mtn|m[- ]money)/i.test(networkText);
  const network = airtel && mtnBrand ? null : airtel ? 'airtel_money' : mtnBrand || /(?:momo|mobile[- ]?money)/i.test(networkText) ? 'mtn_momo' : null;
  const incoming = amountFrom(body, receivedAmount), outgoing = amountFrom(body, sentAmount);
  const blocked = excluded.test(body), direction = !blocked && incoming !== null && outgoing === null ? 'incoming' : !blocked && outgoing !== null && incoming === null ? 'outgoing' : null;
  const parsedAmount = direction === 'incoming' ? incoming : direction === 'outgoing' ? outgoing : null;
  const amount = parsedAmount > 0 ? parsedAmount : null;
  const namedMatches = [...body.matchAll(namedPayer)], plainMatches = [...body.matchAll(plainPayer)];
  const singlePayer = namedMatches.length + plainMatches.length === 1;
  const named = singlePayer ? namedMatches[0] : null, plain = singlePayer ? plainMatches[0] : null;
  const rawName = named?.[1]?.trim().replace(/\s+/g, ' ') ?? null;
  const payerName = rawName && /\p{L}/u.test(rawName) && !/\p{Cc}/u.test(rawName) ? rawName : null;
  const masked = named?.[2]?.startsWith('*') ? named[2] : null;
  const payerPhone = masked ? null : normalizedPhone(named?.[2] ?? plain?.[1]);
  const payerLast3 = masked?.slice(-3) ?? payerPhone?.slice(-3) ?? null;
  const receiverPhone = normalizedPhone(oneMatch(body, payeeNumber)?.[1]);
  const payeeCode = oneMatch(body, /\b(?:payee|receiver|merchant|momo)\s+(?:code|pay\s*code)\s*[:#-]?\s*([0-9]{4,9})(?![0-9])/gi)?.[1] ?? null;
  const reference = oneMatch(body, referencePattern)?.[1]?.replace(/[.,;:]+$/, '') ?? null;
  const date = oneMatch(body, /\bat\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})(?:\s*(Z|[+-]\d{2}:?\d{2}))?(?!\d)/gi);
  let local = null, offset = null;
  if (date) { const candidate = `${date[1]}T${date[2]}`, calendar = new Date(`${candidate}Z`);
    if (Number.isFinite(calendar.valueOf()) && calendar.toISOString().slice(0, 19) === candidate) {
      local = candidate; if (date[3]?.toUpperCase() === 'Z') offset = '+00:00';
      else if (date[3] && /^[+-](?:0[0-9]|1[0-4]):?[0-5][0-9]$/.test(date[3]) && !/^[-+]14:?([1-5][0-9]|0[1-9])$/.test(date[3])) offset = date[3].length === 5 ? `${date[3].slice(0, 3)}:${date[3].slice(3)}` : date[3];
    } }
  const isPayment = Boolean(direction && amount && network);
  return { extraction_status: isPayment && reference ? 'parsed' : 'needs_review', payer_name: payerName, payer_phone: payerPhone, payer_masked_phone: masked, payer_last3: payerLast3,
    payee_momo_number: receiverPhone, payee_momo_code: payeeCode, momo_transaction_reference: reference, momo_timestamp_local: local, momo_timezone_offset: offset,
    amount_rwf: amount, wallet_balance_rwf: amountFrom(body, balancePattern), network, direction, is_payment: Number(isPayment) };
}
export function generateTransactionPublicReference({ payer_last3 = null, payee_last3 = null } = {}) {
  for (const value of [payer_last3, payee_last3]) if (value !== null && !/^[0-9]{3}$/.test(value)) invalid('Invalid known reference suffix.');
  let tail = '';
  while (tail.length < 12) for (const byte of crypto.getRandomValues(new Uint8Array(24))) { if (byte < 250 && tail.length < 12) tail += String(byte % 10); }
  return { public_reference: `${payer_last3 ?? '000'}${payee_last3 ?? '000'}${tail}`, payer_last3_known: Number(payer_last3 !== null), payee_last3_known: Number(payee_last3 !== null), random_source: 'crypto_get_random_values' };
}
export const TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL = 'LEFT JOIN collect_transaction_public_references public_reference ON public_reference.transaction_id=t.id';
export const TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL = 'public_reference.public_reference,public_reference.payer_last3_known,public_reference.payee_last3_known,public_reference.source_fact_id AS public_reference_source_fact_id,public_reference.random_source AS public_reference_random_source';
export const transactionPublicReferenceRow = row => ({ transaction_reference: row.public_reference ?? null,
  reference_payer_last3_known: row.payer_last3_known === 1, reference_payee_last3_known: row.payee_last3_known === 1,
  reference_source_fact_id: row.public_reference_source_fact_id ?? null, reference_random_source: row.public_reference_random_source ?? null });
export async function prepareTransactionPublicReference(env, { transaction_id, payee_id, source_fact_id = null, operation_request_id = null }) {
  id(transaction_id); id(payee_id); if (operation_request_id !== null) id(operation_request_id); let payerLast3 = null, payeeLast3 = null;
  if (source_fact_id) {
    id(source_fact_id); const row = await stmt(env, 'SELECT f.payer_last3,y.momo_number_or_code FROM collect_sms_facts f JOIN collect_payees y ON y.id=? WHERE f.id=?', payee_id, source_fact_id).first();
    if (!row) fail(409, 'source_conflict', 'Select preserved receipt facts and the recorded payee.'); payerLast3 = row.payer_last3; payeeLast3 = row.momo_number_or_code.slice(-3);
  }
  const reference = generateTransactionPublicReference({ payer_last3: payerLast3, payee_last3: payeeLast3 });
  // Execute before the caller's INSERT transaction in the SAME D1 batch. Its
  // deferred FK and new transaction trigger validate complete source context.
  const values = { transaction_id, public_reference: reference.public_reference, payer_last3_known: reference.payer_last3_known,
    payee_last3_known: reference.payee_last3_known, source_fact_id, random_source: reference.random_source, created_at: Math.floor(Date.now() / 1000) };
  const guard = operation_request_id === null ? '' : ' WHERE EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)';
  return { reference: { ...reference, source_fact_id }, values, statements: [stmt(env,
    `INSERT INTO collect_transaction_public_references(${Object.keys(values).join(',')}) SELECT ${Object.keys(values).map(() => '?').join(',')}${guard}`,
    ...Object.values(values), ...(operation_request_id === null ? [] : [operation_request_id]))] };
}
// Execute inside the caller's authorized, claim-guarded review/extraction batch.
// Unknown/unparsed observations stay unlinked. Known parsed payment context is
// validated by the immutable lineage trigger, including same-kind recipient.
export function reviewedMemberSmsLinkStatements(env,{submission_id,actor_admin_id,operation_request_id,created_at}) {
  return [stmt(env,`INSERT INTO collect_transaction_sms_sources(transaction_id,source_fact_id,review_id,actor_admin_id,operation_request_id,created_at)
    SELECT r.transaction_id,f.id,r.id,?,?,? FROM collect_member_receipt_reviews r
    JOIN collect_sms_facts f ON f.member_submission_id=r.submission_id AND f.source_kind='member'
    JOIN collect_transaction_public_references public_reference ON public_reference.transaction_id=r.transaction_id
    WHERE r.submission_id=? AND r.outcome='reviewed' AND f.extraction_status='parsed' AND f.direction='incoming' AND f.is_payment=1
      AND public_reference.source_fact_id IS NULL
      AND NOT EXISTS(SELECT 1 FROM collect_transaction_sms_sources previous WHERE previous.transaction_id=r.transaction_id)
      AND EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)`,actor_admin_id,operation_request_id,created_at,submission_id,operation_request_id)];
}
const sources = `SELECT 'member' AS source_kind,s.id,s.user_id,NULL AS payee_id,s.body_hash AS source_sha256,s.status,s.version,s.received_at,s.created_at,
 p.public_id,(CASE WHEN p.display_name_recorded=1 THEN p.display_name END) AS display_name,r.transaction_id,'member_submitted' AS evidence_level FROM member_receipt_submissions s
 LEFT JOIN collect_profiles p ON p.user_id=s.user_id LEFT JOIN collect_member_receipt_reviews r ON r.submission_id=s.id
 UNION ALL SELECT 'receiver',s.id,NULL,s.payee_id,s.payload_sha256,s.parse_status,1,s.received_at,s.received_at,NULL,y.label,s.transaction_id,'receiver_ingress_unverified'
 FROM collect_receipt_ingress s JOIN collect_payees y ON y.id=s.payee_id`;
const factColumns = ['payer_name', 'payer_phone', 'payer_masked_phone', 'payer_last3', 'payee_momo_number', 'payee_momo_code', 'momo_transaction_reference', 'momo_timestamp_local', 'momo_timezone_offset', 'amount_rwf', 'wallet_balance_rwf', 'network', 'direction', 'is_payment'];
export const ADMIN_SMS_RECEIPTS_SELECT_SQL = `SELECT s.*,f.id AS source_fact_id,f.parser_version,COALESCE(f.extraction_status,'not_extracted') AS extraction_status,
 f.source_body_sha256,f.source_payload_sha256,f.parsed_at,${factColumns.map(column => `f.${column}`).join(',')},
 public_reference.public_reference AS transaction_reference,
 (SELECT count(*) FROM collect_sms_facts other WHERE other.id!=f.id AND other.network=f.network AND other.momo_transaction_reference=f.momo_transaction_reference) AS duplicate_reference_count,
 (SELECT count(*) FROM collect_sms_facts other WHERE other.id!=f.id AND other.network=f.network AND other.momo_transaction_reference=f.momo_transaction_reference AND other.source_body_sha256!=f.source_body_sha256) AS conflicting_reference_count
 FROM (${sources}) s LEFT JOIN collect_sms_facts f ON f.source_kind=s.source_kind AND COALESCE(f.member_submission_id,f.receiver_ingress_id)=s.id
 LEFT JOIN collect_transaction_public_references public_reference ON public_reference.transaction_id=s.transaction_id`;
export const adminSmsReceiptRow = row => ({ ...row, provider_confirmation: false, settlement_status: 'not_asserted',
  timezone_known: row.momo_timezone_offset !== null, payer_last3_known: row.payer_last3 !== null,
  source_content_reveal_required: true });
function page(url) {
  const rawLimit = url.searchParams.get('limit') ?? '25', rawOffset = url.searchParams.get('offset') ?? '0';
  if (!/^[1-9][0-9]*$/.test(rawLimit) || !/^(0|[1-9][0-9]*)$/.test(rawOffset)) invalid('Invalid page.');
  const limit = Number(rawLimit), offset = Number(rawOffset); if (!Number.isSafeInteger(limit) || limit > 100 || !Number.isSafeInteger(offset) || offset > 2147483647) invalid('Invalid page.'); return { limit, offset };
}
function filterKeys(url, allowed) { for (const key of url.searchParams.keys()) if (!allowed.includes(key) || url.searchParams.getAll(key).length !== 1) invalid('Unsupported or repeated filter.'); }
const paged = (rows, total, paging) => ({ rows, total, ...paging, next_offset: paging.offset + rows.length < total ? paging.offset + rows.length : null });
async function list(env, user, url) {
  filterKeys(url, ['source_kind', 'status', 'extraction_status', 'search', 'duplicates', 'limit', 'offset']); const paging = page(url), conditions = [], args = [];
  if (url.searchParams.has('source_kind')) { conditions.push('source_kind=?'); args.push(kind(url.searchParams.get('source_kind'))); }
  for (const field of ['status', 'extraction_status']) if (url.searchParams.has(field)) { conditions.push(`${field}=?`); const value = url.searchParams.get(field);
    if (!(field === 'status' ? ['pending', 'parsed', 'parse_failed', 'needs_review', 'rejected', 'reviewed'] : ['not_extracted', 'parsed', 'needs_review']).includes(value)) invalid('Invalid receipt status.'); args.push(value); }
  if (url.searchParams.has('duplicates')) { if (!['all', 'conflicting'].includes(url.searchParams.get('duplicates'))) invalid('Invalid duplicate filter.'); conditions.push(`${url.searchParams.get('duplicates') === 'all' ? 'duplicate_reference_count' : 'conflicting_reference_count'}>0`); }
  const search = url.searchParams.get('search') ?? ''; if (search.length > 200) invalid('Search is too long.');
  if (search) { conditions.push('(instr(lower(COALESCE(display_name,\'\')),lower(?))>0 OR instr(lower(COALESCE(payer_name,\'\')),lower(?))>0 OR instr(COALESCE(momo_transaction_reference,\'\'),?)>0 OR instr(COALESCE(payer_phone,\'\'),?)>0 OR instr(COALESCE(payee_momo_code,\'\'),?)>0)'); args.push(...Array(5).fill(search)); }
  const where = conditions.length ? ` WHERE ${conditions.join(' AND ')}` : '';
  const [count, rows] = await read(env, user, [stmt(env, `SELECT count(*) AS total FROM (${ADMIN_SMS_RECEIPTS_SELECT_SQL})${where}`, ...args),
    stmt(env, `SELECT * FROM (${ADMIN_SMS_RECEIPTS_SELECT_SQL})${where} ORDER BY received_at DESC,source_kind,id LIMIT ? OFFSET ?`, ...args, paging.limit, paging.offset)]);
  return paged(rows.results.map(adminSmsReceiptRow), count.results[0].total, paging);
}
async function detail(env, user, sourceKind, sourceId, url) {
  kind(sourceKind); id(sourceId); filterKeys(url, ['limit', 'offset']); const paging = page(url);
  const [source, count, related] = await read(env, user, [stmt(env, `${ADMIN_SMS_RECEIPTS_SELECT_SQL} WHERE s.source_kind=? AND s.id=?`, sourceKind, sourceId),
    stmt(env, `SELECT count(*) AS total FROM (${ADMIN_SMS_RECEIPTS_SELECT_SQL}) other WHERE other.source_fact_id!=(SELECT id FROM collect_sms_facts WHERE source_kind=? AND COALESCE(member_submission_id,receiver_ingress_id)=?)
     AND other.network=(SELECT network FROM collect_sms_facts WHERE source_kind=? AND COALESCE(member_submission_id,receiver_ingress_id)=?)
     AND other.momo_transaction_reference=(SELECT momo_transaction_reference FROM collect_sms_facts WHERE source_kind=? AND COALESCE(member_submission_id,receiver_ingress_id)=?)`, sourceKind, sourceId, sourceKind, sourceId, sourceKind, sourceId),
    stmt(env, `SELECT * FROM (${ADMIN_SMS_RECEIPTS_SELECT_SQL}) other WHERE other.source_fact_id!=(SELECT id FROM collect_sms_facts WHERE source_kind=? AND COALESCE(member_submission_id,receiver_ingress_id)=?)
     AND other.network=(SELECT network FROM collect_sms_facts WHERE source_kind=? AND COALESCE(member_submission_id,receiver_ingress_id)=?)
     AND other.momo_transaction_reference=(SELECT momo_transaction_reference FROM collect_sms_facts WHERE source_kind=? AND COALESCE(member_submission_id,receiver_ingress_id)=?)
     ORDER BY received_at,source_kind,id LIMIT ? OFFSET ?`, sourceKind, sourceId, sourceKind, sourceId, sourceKind, sourceId, paging.limit, paging.offset)]);
  if (!source.results[0]) fail(404, 'not_found', 'This receipt does not exist.');
  return { resource_type: 'sms_receipts', resource: adminSmsReceiptRow(source.results[0]), current_actor_id: user.id,
    can_extract: ['owner', 'admin'].includes(user.role) && user.permissions.includes('sms.extract'),
    related: { duplicate_references: paged(related.results.map(adminSmsReceiptRow), count.results[0].total, paging) } };
}
async function streamBytes(stream, limit) {
  if (!stream) throw new Error('Missing payload stream'); const reader = stream.getReader(), chunks = []; let size = 0;
  while (true) { const chunk = await reader.read(); if (chunk.done) break; size += chunk.value.byteLength;
    if (size > limit) { await reader.cancel(); throw new Error('Payload limit'); } chunks.push(chunk.value); }
  const bytes = new Uint8Array(size); let offset = 0; for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; } return bytes;
}
async function sourcePayload(env, sourceKind, sourceId) {
  const table = sourceKind === 'member' ? 'member_receipt_submissions' : 'collect_receipt_ingress';
  const stored = await stmt(env, `SELECT * FROM ${table} WHERE id=?`, sourceId).first(); if (!stored) fail(404, 'not_found', 'This receipt does not exist.');
  const bucket = sourceKind === 'member' ? env.MEMBER_MEDIA : env.RECEIPT_PAYLOADS;
  if (!bucket?.get) fail(503, 'receipt_source_unavailable', 'Private receipt storage is unavailable.');
  const source = await bucket.get(stored.payload_object_key); let bytes, content;
  if (!source || !Number.isSafeInteger(source.size) || source.size < 1 || source.size > 131072) fail(503, 'receipt_source_unavailable', 'The original receipt could not be verified.');
  try { bytes = await streamBytes(source.body, 131072); content = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); } catch { fail(503, 'receipt_source_unavailable', 'The original receipt could not be verified.'); }
  if (!content || Object.keys(content).length !== 2 || typeof content.raw_sender !== 'string' || !content.raw_sender.length || content.raw_sender.length > 80 || typeof content.raw_body !== 'string' || !content.raw_body.length || content.raw_body.length > 16000) fail(503, 'receipt_source_mismatch', 'The original receipt envelope is invalid.');
  const bodyHash = await digest(content.raw_body), payloadHash = hex(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)));
  if (sourceKind === 'member' ? bodyHash !== stored.body_hash || content.raw_sender !== stored.raw_sender : payloadHash !== stored.payload_sha256) fail(503, 'receipt_source_mismatch', 'The original receipt does not match its stored evidence digest.');
  return { stored, content, bodyHash, payloadHash, table, sourceHash: sourceKind === 'member' ? bodyHash : payloadHash };
}
async function reveal(request, env, user, sourceKind, sourceId) {
  const reason = reasonText(request.headers.get('X-Collect-Review-Reason')); await read(env, user, [], true);
  const source = await sourcePayload(env, sourceKind, sourceId), guardId = crypto.randomUUID();
  try { await env.ADMIN_DB.batch([stmt(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authSql(true)} THEN 1 ELSE 0 END`, guardId, ...authArgs(user)),
    stmt(env, 'INSERT INTO collect_operations_audit(id,actor_admin_id,action,subject_type,subject_id,evidence_json,occurred_at) VALUES(?,?,?,?,?,?,?)', crypto.randomUUID(), user.id, 'sms.source.reveal', 'sms_receipts', `${sourceKind}/${sourceId}`, JSON.stringify({ reason, source_kind: sourceKind, source_sha256: source.sourceHash }), Math.floor(Date.now() / 1000)),
    stmt(env, 'DELETE FROM collect_mutation_guards WHERE id=?', guardId)]); }
  catch { await read(env, user, [], true); fail(503, 'receipt_audit_unavailable', 'Receipt access could not be recorded. Try again later.'); }
  return { source_kind: sourceKind, source_id: sourceId, ...source.content, source_sha256: source.sourceHash, evidence_level: sourceKind === 'member' ? 'member_submitted' : 'receiver_ingress_unverified', provider_confirmation: false };
}
async function extract(request, env, user, sourceKind, sourceId) {
  const key = request.headers.get('Idempotency-Key'); if (!keyValid(key)) invalid('Supply an Idempotency-Key of 8 to 200 letters, digits, dots, hyphens or underscores.');
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) fail(415, 'invalid_content_type', 'Send a JSON request.');
  let data; try { data = JSON.parse(new TextDecoder().decode(await streamBytes(request.body, 65536))); } catch { invalid('Send bounded valid JSON.'); }
  if (!data || typeof data !== 'object' || Array.isArray(data) || Object.keys(data).some(field => !['reason', 'expected_source_sha256'].includes(field))) invalid('Request has unsupported fields.');
  data.reason = reasonText(data.reason); if (!hashValid(data.expected_source_sha256)) invalid('Select the recorded source digest.');
  const requestHash = await digest(canonical({ path: `sms/receipts/${sourceKind}/${sourceId}/extract`, body: data }));
  const [existing] = await read(env, user, [stmt(env, 'SELECT * FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key)], true);
  if (existing.results[0]) { const row = existing.results[0]; if (row.request_sha256 !== requestHash) fail(409, 'idempotency_conflict', 'This request key belongs to different content.');
    if (row.status !== 'succeeded') fail(409, 'request_pending', 'Check this request receipt before continuing.'); return JSON.parse(row.response_json); }
  const source = await sourcePayload(env, sourceKind, sourceId); if (source.sourceHash !== data.expected_source_sha256) fail(409, 'source_conflict', 'The selected receipt source does not match.');
  const facts = parseAdminSmsFacts(source.content.raw_sender, source.content.raw_body), requestId = crypto.randomUUID(), factId = crypto.randomUUID(), time = Math.floor(Date.now() / 1000);
  const values = { id: factId, source_kind: sourceKind, member_submission_id: sourceKind === 'member' ? sourceId : null, receiver_ingress_id: sourceKind === 'receiver' ? sourceId : null,
    source_body_sha256: source.bodyHash, source_payload_sha256: source.payloadHash, parser_version: SMS_PARSER_VERSION, ...facts, parsed_by_admin_id: user.id, operation_request_id: requestId, parsed_at: time };
  const keys = Object.keys(values), sourceLookup = 'source_kind=? AND COALESCE(member_submission_id,receiver_ingress_id)=?';
  const owned = 'EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)';
  const batch = [stmt(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authSql(true)} THEN 1 ELSE 0 END`, `${requestId}:auth`, ...authArgs(user)),
    stmt(env, 'INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(actor_admin_id,idempotency_key) DO NOTHING', requestId, user.id, 'sms.extract', key, requestHash, time),
    stmt(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND request_sha256=?) THEN 1 ELSE 0 END', `${requestId}:key`, user.id, key, requestHash),
    stmt(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN NOT ${owned} OR EXISTS(SELECT 1 FROM ${source.table} WHERE id=? AND ${sourceKind === 'member' ? 'body_hash' : 'payload_sha256'}=?) THEN 1 ELSE 0 END`, `${requestId}:source`, requestId, sourceId, source.sourceHash),
    stmt(env, `INSERT INTO collect_sms_facts(${keys.join(',')}) SELECT ${keys.map(() => '?').join(',')} WHERE ${owned} AND NOT EXISTS(SELECT 1 FROM collect_sms_facts WHERE ${sourceLookup})`, ...Object.values(values), requestId, sourceKind, sourceId),
    stmt(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN NOT ${owned} OR EXISTS(SELECT 1 FROM collect_sms_facts WHERE ${sourceLookup} AND parser_version=? AND source_body_sha256=?) THEN 1 ELSE 0 END`, `${requestId}:facts`, requestId, sourceKind, sourceId, SMS_PARSER_VERSION, source.bodyHash),
    ...(sourceKind==='member'?reviewedMemberSmsLinkStatements(env,{submission_id:sourceId,actor_admin_id:user.id,operation_request_id:requestId,created_at:time}):[]),
    stmt(env, `INSERT INTO collect_operations_audit(id,actor_admin_id,operation_request_id,action,subject_type,subject_id,evidence_json,occurred_at)
     SELECT ?,?,?,'sms.extract','sms_receipts',?,json_object('reason',?,'source_sha256',?,'parser_version',?,'source_fact_id',f.id),? FROM collect_sms_facts f WHERE ${sourceLookup} AND ${owned}`, crypto.randomUUID(), user.id, requestId, `${sourceKind}/${sourceId}`, data.reason, source.sourceHash, SMS_PARSER_VERSION, time, sourceKind, sourceId, requestId),
    stmt(env, `UPDATE collect_operation_requests SET status='succeeded',response_json=(SELECT json_object('request_id',?,'status','succeeded','resource_type','sms_facts','resource_id',id,'source_kind',source_kind,'source_id',COALESCE(member_submission_id,receiver_ingress_id),'parser_version',parser_version) FROM collect_sms_facts WHERE ${sourceLookup}),completed_at=? WHERE id=?`, requestId, sourceKind, sourceId, time, requestId),
    stmt(env, 'DELETE FROM collect_mutation_guards WHERE id LIKE ?', `${requestId}:%`),
    stmt(env, 'SELECT response_json,status,request_sha256 FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key)];
  try { const result = await env.ADMIN_DB.batch(batch), saved = result.at(-1).results[0];
    if (!saved || saved.status !== 'succeeded' || saved.request_sha256 !== requestHash) fail(409, 'request_pending', 'Check this request receipt before continuing.'); return JSON.parse(saved.response_json); }
  catch (error) { if (error instanceof AdminSmsError) throw error; await read(env, user, [], true);
    if (/constraint|RAISE|immutable|requires|CHECK|UNIQUE|FOREIGN KEY|guard_failed/i.test(String(error))) fail(409, 'source_conflict', 'The receipt facts or related source state changed. Refresh before continuing.');
    fail(503, 'service_unavailable', 'The extraction outcome could not be confirmed. Check the request receipt before continuing.'); }
}
export function adminSmsPermission(request) {
  const path = new URL(request.url).pathname;
  if (request.method === 'POST' && /^\/api\/admin\/sms\/receipts\/(member|receiver)\/[^/]+\/extract$/.test(path)) return 'sms.extract';
  if (request.method === 'GET' && path.endsWith('/content')) return 'sms.reveal';
  if (request.method === 'GET') return 'sms.read'; return null;
}
export async function handleAdminSms(request, env, user) {
  if (!user || user.status !== 'active' || !['owner', 'admin', 'staff'].includes(user.role)) fail(401, 'unauthenticated', 'Sign in to continue.');
  const url = new URL(request.url), parts = url.pathname.replace(/^\/api\/admin\/sms\/?/, '').split('/').filter(Boolean);
  if (!url.pathname.startsWith('/api/admin/sms/')) fail(404, 'not_found', 'This SMS endpoint does not exist.');
  const permission = adminSmsPermission(request); if (!permission) fail(405, 'method_not_allowed', 'This SMS method is unavailable.');
  if (!user.permissions?.includes(permission) || (permission !== 'sms.read' && !['owner', 'admin'].includes(user.role))) fail(403, 'permission_required', 'This SMS action is unavailable to this account.');
  if (parts[0] === 'requests' && parts.length === 2 && request.method === 'GET') {
    if (url.search || !keyValid(parts[1])) invalid('Invalid request lookup.');
    const [result] = await read(env, user, [stmt(env, "SELECT id,status,response_json FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND scope='sms.extract'", user.id, parts[1])]);
    const row = result.results[0]; return row ? { status: row.status, request_id: row.id, receipt: row.response_json ? JSON.parse(row.response_json) : null } : { status: 'not_found' };
  }
  if (parts[0] !== 'receipts') fail(404, 'not_found', 'This SMS endpoint does not exist.');
  if (parts.length === 1 && request.method === 'GET') return list(env, user, url);
  if (parts.length === 3 && request.method === 'GET') return detail(env, user, parts[1], parts[2], url);
  if (parts.length !== 4 || url.search) invalid('Invalid receipt endpoint.'); kind(parts[1]); id(parts[2]);
  if (parts[3] === 'extract' && request.method === 'POST') return extract(request, env, user, parts[1], parts[2]);
  if (parts[3] === 'content' && request.method === 'GET') return reveal(request, env, user, parts[1], parts[2]);
  fail(404, 'not_found', 'This SMS endpoint does not exist.');
}
