import { digest } from './security.mjs';
import { TRANSACTION_SMS_FACT_JOIN_SQL, TRANSACTION_SMS_FACT_COLUMNS_SQL, transactionSourceRow } from './core.mjs';
import { TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL, TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL } from './admin-sms.mjs';

export class ReconciliationError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new ReconciliationError(status, code, message); };
const invalid = message => fail(400, 'invalid_request', message);
const manager = user => ['owner', 'admin'].includes(user.role);
const exact = (value, name, minimum = 1, maximum = Number.MAX_SAFE_INTEGER) => {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) invalid(`${name} must be a bounded exact integer.`);
  return value;
};
const id = value => { if (typeof value !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value)) invalid('Invalid resource identifier.'); return value; };
const text = (value, name, min = 0, max = 200) => {
  if (typeof value !== 'string' || value.trim().length < min || value.trim().length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) invalid(`Invalid ${name}.`);
  return value.trim();
};
const oneOf = (value, choices) => { if (!choices.includes(value)) invalid('Invalid filter or outcome.'); return value; };
const fields = (data, allowed) => { if (Object.keys(data).some(key => !allowed.includes(key))) invalid('Request has unsupported fields.'); };
const canonical = value => JSON.stringify(value, (_, nested) => nested && typeof nested === 'object' && !Array.isArray(nested)
  ? Object.fromEntries(Object.keys(nested).sort().map(key => [key, nested[key]])) : nested);
const keyValid = key => typeof key === 'string' && /^[a-zA-Z0-9_.-]{8,200}$/.test(key);
const sql = (env, query, ...args) => env.ADMIN_DB.prepare(query).bind(...args);
const authSql = privileged => `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id
 WHERE s.token_hash=? AND a.id=? AND a.status='active' AND a.role IN (${privileged ? "'owner','admin'" : "'owner','admin','staff'"})
 AND a.auth_version=s.auth_version AND s.auth_version=? AND a.role=? AND s.expires_at>unixepoch())`;
const authArgs = user => [user.token_hash, user.id, user.auth_version, user.role];
async function read(env, user, queries) {
  const [authorization, ...results] = await env.ADMIN_DB.batch([sql(env, `SELECT ${authSql(false)} AS allowed`, ...authArgs(user)), ...queries]);
  if (!authorization.results[0].allowed) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
  return results;
}
function filters(url, allowed) {
  for (const key of url.searchParams.keys()) if (!allowed.includes(key) || url.searchParams.getAll(key).length !== 1) invalid('Unsupported or repeated filter.');
}
function page(url) {
  const limit = url.searchParams.get('limit') ?? '25', offset = url.searchParams.get('offset') ?? '0';
  if (!/^[1-9][0-9]*$/.test(limit) || !/^(0|[1-9][0-9]*)$/.test(offset)) invalid('Invalid page.');
  return { limit: exact(Number(limit), 'limit', 1, 100), offset: exact(Number(offset), 'offset', 0, 2147483647) };
}
const paged = (rows, total, paging) => ({ rows, total, ...paging, next_offset: paging.offset + rows.length < total ? paging.offset + rows.length : null });
const allocated = "COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a WHERE a.transaction_id=t.id),0)";
export const RECONCILIATION_QUEUE_COUNT_SQL = `SELECT count(*) AS total FROM collect_transactions t
 WHERE t.verification_status!='rejection_recorded' AND t.amount_rwf>${allocated}`;
const transactionProjection = `SELECT t.*,g.title AS group_title,g.status AS group_status,g.version AS group_version,
 y.label AS payee_name,y.momo_number_or_code AS payee_momo,y.momo_number_or_code AS payee_momo_number_or_code,
 ${TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL},${TRANSACTION_SMS_FACT_COLUMNS_SQL},y.status AS payee_status,y.version AS payee_version,
 ${allocated} AS allocated_amount_rwf,t.amount_rwf-${allocated} AS unallocated_amount_rwf,
 (SELECT count(*) FROM collect_reconciliation_proposals p WHERE p.transaction_id=t.id
  AND NOT EXISTS(SELECT 1 FROM collect_reconciliation_reviews r WHERE r.proposal_id=p.id)) AS pending_proposals
 FROM collect_transactions t JOIN collect_groups g ON g.id=t.group_id JOIN collect_payees y ON y.id=t.payee_id
 ${TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL} ${TRANSACTION_SMS_FACT_JOIN_SQL}`;
function checkedTransaction(row) {
  for (const key of ['amount_rwf', 'allocated_amount_rwf', 'unallocated_amount_rwf'])
    if (!Number.isSafeInteger(row[key]) || row[key] < 0) fail(503, 'invalid_source_data', 'Transaction measurements are temporarily unavailable.');
  if (row.allocated_amount_rwf > row.amount_rwf) fail(503, 'invalid_source_data', 'Transaction measurements are temporarily unavailable.');
  const {public_reference,payer_last3_known,payee_last3_known,public_reference_source_fact_id,public_reference_random_source,payer_source_match_count,allocated_member_count,...resource}=row;
  return { ...resource, ...transactionSourceRow(row), source_parsed_at:row.source_parsed_at, allocation_status: row.unallocated_amount_rwf === 0 ? 'allocated' : row.allocated_amount_rwf === 0 ? 'unallocated' : 'partially_allocated',
    settlement_status: 'not_asserted' };
}
async function queue(env, user, url) {
  filters(url, ['search', 'verification_status', 'allocation_status', 'limit', 'offset']); const paging = page(url);
  const where = [`t.verification_status!='rejection_recorded'`, `t.amount_rwf>${allocated}`], args = [];
  if (url.searchParams.has('verification_status')) { where.push('t.verification_status=?'); args.push(oneOf(url.searchParams.get('verification_status'), ['pending', 'confirmation_recorded', 'evidence_conflict'])); }
  if (url.searchParams.has('allocation_status')) where.push(`${allocated}${oneOf(url.searchParams.get('allocation_status'), ['unallocated', 'partially_allocated']) === 'unallocated' ? '=0' : '>0'}`);
  const search = text(url.searchParams.get('search') ?? '', 'search');
  if (search) { where.push(`(instr(lower(t.provider_reference),lower(?))>0 OR instr(lower(g.title),lower(?))>0 OR instr(lower(y.label),lower(?))>0
   OR instr(y.momo_number_or_code,?)>0 OR instr(public_reference.public_reference,?)>0 OR instr(lower(COALESCE(sms_fact.payer_name,'')),lower(?))>0 OR EXISTS(SELECT 1 FROM collect_reconciliation_proposals p JOIN collect_profiles f ON f.user_id=p.member_user_id
    WHERE p.transaction_id=t.id AND (instr(lower(f.display_name),lower(?))>0 OR instr(f.momo_number,?)>0 OR instr(f.momo_pay_code,?)>0)))`); args.push(...Array(9).fill(search)); }
  const condition = where.join(' AND ');
  const [count, result] = await read(env, user, [sql(env, `SELECT count(*) AS total FROM collect_transactions t JOIN collect_groups g ON g.id=t.group_id JOIN collect_payees y ON y.id=t.payee_id ${TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL} ${TRANSACTION_SMS_FACT_JOIN_SQL} WHERE ${condition}`, ...args),
    sql(env, `${transactionProjection} WHERE ${condition} ORDER BY t.observed_at,t.id LIMIT ? OFFSET ?`, ...args, paging.limit, paging.offset)]);
  return paged(result.results.map(checkedTransaction), count.results[0].total, paging);
}
const proposalProjection = `SELECT p.*,COALESCE(r.outcome,'pending') AS status,(CASE WHEN r.id IS NULL THEN 1 ELSE 2 END) AS version,
 r.id AS review_id,r.allocation_id,r.reviewed_by_admin_id,r.reason AS review_reason,r.reviewed_at,
 (CASE WHEN f.display_name_recorded=1 THEN f.display_name END) AS current_display_name,f.public_id FROM collect_reconciliation_proposals p
 LEFT JOIN collect_reconciliation_reviews r ON r.proposal_id=p.id LEFT JOIN collect_profiles f ON f.user_id=p.member_user_id`;
const proposalRow = ({ payment_identity_json, payee_identity_json, ...row }) => ({ ...row, payment_identity: JSON.parse(payment_identity_json), payee_identity: JSON.parse(payee_identity_json) });
const relatedQueries = {
  evidence: 'SELECT id,kind,reference,artifact_sha256 AS sha256,recorded_by_admin_id,recorded_at AS created_at FROM collect_transaction_evidence WHERE transaction_id=? ORDER BY recorded_at,id',
  verification_reviews: 'SELECT *,reviewed_at AS created_at FROM collect_transaction_reviews WHERE transaction_id=? ORDER BY reviewed_at,id',
  allocations: 'SELECT a.*,f.public_id,(CASE WHEN f.display_name_recorded=1 THEN f.display_name END) AS display_name FROM collect_payment_allocations a LEFT JOIN collect_profiles f ON f.user_id=a.member_user_id WHERE transaction_id=? ORDER BY a.created_at,a.id',
  proposals: `${proposalProjection} WHERE p.transaction_id=? ORDER BY p.created_at,p.id`,
  journals: 'SELECT id,description,status,version,created_by_admin_id,edited_by_admin_id,posted_by_admin_id,allocation_id,created_at FROM collect_journals WHERE transaction_id=? ORDER BY created_at,id',
};
async function detail(env, user, transactionId, url) {
  id(transactionId); filters(url, ['related', 'limit', 'offset']); const paging = page(url);
  const kinds = url.searchParams.has('related') ? [oneOf(url.searchParams.get('related'), Object.keys(relatedQueries))] : Object.keys(relatedQueries);
  const queries = [sql(env, `${transactionProjection} WHERE t.id=?`, transactionId)];
  for (const kind of kinds) { const query = relatedQueries[kind]; queries.push(sql(env, `SELECT count(*) AS total FROM (${query})`, transactionId), sql(env, `${query} LIMIT ? OFFSET ?`, transactionId, paging.limit, paging.offset)); }
  const results = await read(env, user, queries); if (!results[0].results.length) fail(404, 'not_found', 'This transaction does not exist.');
  return { resource_type: 'reconciliations', resource: checkedTransaction(results[0].results[0]), current_actor_id: user.id,
    can_propose: user.permissions.includes('reconciliations.propose'), can_review: manager(user) && user.permissions.includes('reconciliations.review'),
    related: Object.fromEntries(kinds.map((kind, index) => [kind, paged(results[index * 2 + 2].results.map(kind === 'proposals' ? proposalRow : row => row), results[index * 2 + 1].results[0].total, paging)])) };
}
async function members(env, user, url) {
  filters(url, ['transaction_id', 'search', 'limit', 'offset']); const paging = page(url);
  const transactionId = url.searchParams.has('transaction_id') ? id(url.searchParams.get('transaction_id')) : null;
  const search = text(url.searchParams.get('search') ?? '', 'search');
  let digits = search.replace(/[\s()+.-]/g, ''); if (/^2507[2389][0-9]{7}$/.test(digits)) digits = `0${digits.slice(3)}`;
  const predicates = ["u.status='active'", "m.status='active'", "g.status='active'", "f.momo_number!=''","f.display_name_recorded=1"];
  const args = [];
  // A selected transaction scopes eligibility to its stored group. Without one,
  // operators can search actual member identities across all active memberships.
  if (transactionId) { predicates.push('m.group_id=(SELECT group_id FROM collect_transactions WHERE id=?)'); args.push(transactionId); }
  if (search) { predicates.push('(instr(lower(f.display_name),lower(?))>0 OR instr(f.public_id,?)>0 OR instr(f.momo_number,?)>0 OR instr(f.momo_pay_code,?)>0)'); args.push(search, search, digits, digits); }
  const from = `FROM collect_users u JOIN collect_profiles f ON f.user_id=u.id JOIN collect_memberships m ON m.user_id=u.id JOIN collect_groups g ON g.id=m.group_id WHERE ${predicates.join(' AND ')}`;
  const queries = [sql(env, `SELECT count(*) AS total ${from}`, ...args), sql(env, `SELECT u.id AS member_user_id,u.version AS member_version,u.member_type,f.public_id,f.display_name,f.momo_provider,f.momo_number,f.momo_pay_code,
   m.version AS membership_version,m.role AS membership_role,m.group_id,g.title AS group_title,g.version AS group_version ${from} ORDER BY f.display_name,f.public_id,m.group_id LIMIT ? OFFSET ?`, ...args, paging.limit, paging.offset)];
  if (transactionId) queries.push(sql(env, 'SELECT id FROM collect_transactions WHERE id=?', transactionId));
  const results = await read(env, user, queries); if (transactionId && !results[2].results.length) fail(404, 'not_found', 'This transaction does not exist.');
  return paged(results[1].results.map(row => ({ ...row, payment_identity: Object.fromEntries(['display_name', 'momo_provider', 'momo_number', 'momo_pay_code'].map(key => [key, row[key]])) })), results[0].results[0].total, paging);
}
async function body(request) {
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) fail(415, 'invalid_content_type', 'Send a JSON request.');
  const reader = request.body?.getReader(); if (!reader) invalid('Send a JSON request.');
  let raw = '', size = 0; const decoder = new TextDecoder();
  while (true) { const chunk = await reader.read(); if (chunk.done) break; size += chunk.value.byteLength;
    if (size > 65536) { await reader.cancel(); fail(413, 'request_too_large', 'Request is too large.'); } raw += decoder.decode(chunk.value, { stream: true }); }
  raw += decoder.decode();
  const tokens = raw.match(/"(?:\\.|[^"\\])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/g) ?? [];
  if (tokens.some(token => token[0] !== '"' && /[.eE]/.test(token))) invalid('Use plain integer JSON numbers, without decimals or exponents.');
  let data; try { data = JSON.parse(raw); } catch { invalid('Request is invalid JSON.'); }
  if (!data || typeof data !== 'object' || Array.isArray(data)) invalid('Send an object.');
  data.reason = text(data.reason, 'reason', 8, 1000); return data;
}
function paymentIdentity(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid('Select a recorded member payment identity.');
  fields(value, ['display_name', 'momo_provider', 'momo_number', 'momo_pay_code']);
  const identity = { display_name: text(value.display_name, 'member name', 2, 120), momo_provider: oneOf(value.momo_provider, ['', 'mtn_momo', 'airtel_money']),
    momo_number: value.momo_number, momo_pay_code: value.momo_pay_code };
  if (typeof identity.momo_number !== 'string' || (identity.momo_number !== '' && !/^07[2389][0-9]{7}$/.test(identity.momo_number))) invalid('Select the recorded MoMo number.');
  if (typeof identity.momo_pay_code !== 'string' || (identity.momo_pay_code !== '' && !/^[0-9]{4,9}$/.test(identity.momo_pay_code))) invalid('Select the recorded MoMo code.');
  if (!identity.momo_number && !identity.momo_pay_code) invalid('A recorded MoMo number or code is required.');
  return identity;
}
function plan(env, requestId) {
  const queries = []; let index = 0; const exists = 'EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)';
  return { queries,
    assert(query, ...args) { queries.push(sql(env, `INSERT INTO collect_mutation_guards(id,passed) VALUES(?,CASE WHEN NOT ${exists} OR (${query}) THEN 1 ELSE 0 END)`, `${requestId}:${++index}`, requestId, ...args)); },
    insert(table, values) { const keys = Object.keys(values); queries.push(sql(env, `INSERT INTO ${table}(${keys.join(',')}) SELECT ${keys.map(() => '?').join(',')} WHERE ${exists}`, ...Object.values(values), requestId)); },
    update(table, values, where, ...args) { const keys = Object.keys(values); queries.push(sql(env, `UPDATE ${table} SET ${keys.map(key => `${key}=?`).join(',')} WHERE ${where} AND ${exists}`, ...Object.values(values), ...args, requestId)); },
  };
}
function currentMember(p, memberId, groupId, memberVersion, membershipVersion, identity) {
  p.assert(`EXISTS(SELECT 1 FROM collect_users u JOIN collect_profiles f ON f.user_id=u.id JOIN collect_memberships m ON m.user_id=u.id
   WHERE u.id=? AND u.status='active' AND u.version=? AND m.group_id=? AND m.status='active' AND m.version=?
    AND f.display_name_recorded=1 AND f.display_name=? AND f.momo_provider=? AND f.momo_number=? AND f.momo_pay_code=? AND f.momo_number!='')`,
  memberId, memberVersion, groupId, membershipVersion, identity.display_name, identity.momo_provider, identity.momo_number, identity.momo_pay_code);
}
function currentTransaction(p, transactionId, version, amount, groupId) {
  p.assert(`EXISTS(SELECT 1 FROM collect_transactions t WHERE t.id=? AND t.group_id=? AND t.version=? AND t.verification_status!='rejection_recorded'
   AND t.amount_rwf-${allocated}>=?)`, transactionId, groupId, version, amount);
}
async function buildMutation(env, user, parts, data, requestId) {
  const p = plan(env, requestId), time = Math.floor(Date.now() / 1000);
  if (parts.length === 2 && parts[1] === 'proposals') {
    fields(data, ['member_user_id', 'amount_rwf', 'expected_transaction_version', 'expected_member_version', 'expected_membership_version', 'expected_payment_identity', 'reason']);
    const transactionId = id(parts[0]), memberId = id(data.member_user_id), amount = exact(data.amount_rwf, 'amount_rwf'), transactionVersion = exact(data.expected_transaction_version, 'expected_transaction_version', 1, Number.MAX_SAFE_INTEGER - 1);
    const memberVersion = exact(data.expected_member_version, 'expected_member_version'), membershipVersion = exact(data.expected_membership_version, 'expected_membership_version'), identity = paymentIdentity(data.expected_payment_identity);
    const [source] = await read(env, user, [sql(env, `${transactionProjection} WHERE t.id=?`, transactionId)]);
    const t = source.results[0]; if (!t) fail(404, 'not_found', 'This transaction does not exist.'); checkedTransaction(t);
    currentTransaction(p, transactionId, transactionVersion, amount, t.group_id); currentMember(p, memberId, t.group_id, memberVersion, membershipVersion, identity);
    p.assert("EXISTS(SELECT 1 FROM collect_groups WHERE id=? AND version=? AND status='active')", t.group_id, t.group_version);
    p.assert("EXISTS(SELECT 1 FROM collect_payees WHERE id=? AND version=? AND status='active' AND momo_number_or_code=? AND network=?)", t.payee_id, t.payee_version, t.payee_momo, t.network);
    const proposalId = crypto.randomUUID(), payeeIdentity = { payee_id: t.payee_id, network: t.network, momo_number_or_code: t.payee_momo };
    p.insert('collect_reconciliation_proposals', { id: proposalId, transaction_id: transactionId, group_id: t.group_id, member_user_id: memberId, amount_rwf: amount,
      transaction_version: transactionVersion, member_version: memberVersion, membership_version: membershipVersion, group_version: t.group_version, payee_version: t.payee_version,
      payment_identity_json: canonical(identity), payee_identity_json: canonical(payeeIdentity), proposed_by_admin_id: user.id, operation_request_id: requestId, reason: data.reason, created_at: time });
    return { ...p, groupId: t.group_id, subjectId: proposalId, time, scope: 'reconciliations.propose', receipt: { resource_type: 'reconciliation_proposals', resource_id: proposalId, transaction_id: transactionId, version: 1, proposal_status: 'pending' }, evidence: { payment_identity: identity, payee_identity: payeeIdentity, member_version: memberVersion, membership_version: membershipVersion, transaction_version: transactionVersion, amount_rwf: amount } };
  }
  fields(data, ['outcome', 'expected_proposal_version', 'expected_transaction_version', 'reason']);
  const proposalId = id(parts[1]), outcome = oneOf(data.outcome, ['approved', 'rejected']); exact(data.expected_proposal_version, 'expected_proposal_version', 1, 2);
  const transactionVersion = exact(data.expected_transaction_version, 'expected_transaction_version', 1, Number.MAX_SAFE_INTEGER - 1);
  const [source] = await read(env, user, [sql(env, `${proposalProjection} WHERE p.id=?`, proposalId)]);
  const proposal = source.results[0]; if (!proposal) fail(404, 'not_found', 'This proposal does not exist.');
  const identity = paymentIdentity(JSON.parse(proposal.payment_identity_json)), payeeIdentity = JSON.parse(proposal.payee_identity_json);
  p.assert('EXISTS(SELECT 1 FROM collect_reconciliation_proposals WHERE id=? AND proposed_by_admin_id!=?) AND ?=1 AND NOT EXISTS(SELECT 1 FROM collect_reconciliation_reviews WHERE proposal_id=?)', proposalId, user.id, data.expected_proposal_version, proposalId);
  p.assert('EXISTS(SELECT 1 FROM collect_transactions WHERE id=? AND version=?)', proposal.transaction_id, transactionVersion);
  let allocationId = null;
  if (outcome === 'approved') {
    currentTransaction(p, proposal.transaction_id, transactionVersion, proposal.amount_rwf, proposal.group_id);
    p.assert("EXISTS(SELECT 1 FROM collect_transactions WHERE id=? AND verification_status='confirmation_recorded' AND payee_id=?)", proposal.transaction_id, payeeIdentity.payee_id);
    currentMember(p, proposal.member_user_id, proposal.group_id, proposal.member_version, proposal.membership_version, identity);
    p.assert("EXISTS(SELECT 1 FROM collect_groups WHERE id=? AND status='active' AND version=?)", proposal.group_id, proposal.group_version);
    p.assert("EXISTS(SELECT 1 FROM collect_payees WHERE id=? AND group_id=? AND status='active' AND version=? AND network=? AND momo_number_or_code=?)", payeeIdentity.payee_id, proposal.group_id, proposal.payee_version, payeeIdentity.network, payeeIdentity.momo_number_or_code);
    allocationId = crypto.randomUUID();
    p.insert('collect_payment_allocations', { id: allocationId, transaction_id: proposal.transaction_id, group_id: proposal.group_id, member_user_id: proposal.member_user_id, amount_rwf: proposal.amount_rwf,
      operation_request_id: requestId, created_by_admin_id: user.id, created_at: time });
    p.update('collect_transactions', { version: transactionVersion + 1 }, 'id=? AND version=?', proposal.transaction_id, transactionVersion);
  }
  const resultingVersion = transactionVersion + (outcome === 'approved' ? 1 : 0), reviewId = crypto.randomUUID();
  p.insert('collect_reconciliation_reviews', { id: reviewId, proposal_id: proposalId, outcome, allocation_id: allocationId, transaction_version: resultingVersion, reviewed_by_admin_id: user.id, operation_request_id: requestId, reason: data.reason, reviewed_at: time });
  return { ...p, groupId: proposal.group_id, subjectId: proposalId, time, scope: 'reconciliations.review',
    receipt: { resource_type: 'reconciliation_proposals', resource_id: proposalId, transaction_id: proposal.transaction_id, version: 2, proposal_status: outcome, review_id: reviewId, allocation_id: allocationId, transaction_version: resultingVersion, settlement_status: 'not_asserted' },
    evidence: { outcome, allocation_id: allocationId, previous_transaction_version: transactionVersion, resulting_transaction_version: resultingVersion, payment_identity: identity, payee_identity: payeeIdentity, amount_rwf: proposal.amount_rwf } };
}
async function mutate(request, env, user, parts) {
  const key = request.headers.get('Idempotency-Key'); if (!keyValid(key)) invalid('Supply an Idempotency-Key of 8 to 200 letters, digits, dots, hyphens or underscores.');
  const data = await body(request), requestHash = await digest(canonical({ method: request.method, path: `reconciliations/${parts.join('/')}`, body: data }));
  const [existing] = await read(env, user, [sql(env, 'SELECT * FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key)]);
  if (existing.results.length) { const row = existing.results[0]; if (row.request_sha256 !== requestHash) fail(409, 'idempotency_conflict', 'This request key belongs to different content.');
    if (row.status !== 'succeeded') fail(409, 'request_pending', 'Check this request receipt before continuing.'); return JSON.parse(row.response_json); }
  const requestId = crypto.randomUUID(), operation = await buildMutation(env, user, parts, data, requestId), privileged = operation.scope === 'reconciliations.review';
  const receipt = { request_id: requestId, status: 'succeeded', ...operation.receipt };
  const batch = [sql(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authSql(privileged)} THEN 1 ELSE 0 END`, `${requestId}:auth`, ...authArgs(user)),
    sql(env, 'INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(actor_admin_id,idempotency_key) DO NOTHING', requestId, user.id, operation.scope, key, requestHash, operation.time),
    sql(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND request_sha256=?) THEN 1 ELSE 0 END', `${requestId}:key`, user.id, key, requestHash),
    ...operation.queries,
    sql(env, `INSERT INTO collect_operations_audit(id,actor_admin_id,operation_request_id,action,group_id,subject_type,subject_id,evidence_json,occurred_at)
     SELECT ?,?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)`, crypto.randomUUID(), user.id, requestId, operation.scope, operation.groupId, 'reconciliation_proposals', operation.subjectId, canonical({ reason: data.reason, request_sha256: requestHash, ...operation.evidence }), operation.time, requestId),
    sql(env, "UPDATE collect_operation_requests SET status='succeeded',response_json=?,completed_at=? WHERE id=?", JSON.stringify(receipt), operation.time, requestId),
    sql(env, 'DELETE FROM collect_mutation_guards WHERE id LIKE ?', `${requestId}:%`),
    sql(env, 'SELECT response_json,request_sha256,status FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key)];
  try {
    const results = await env.ADMIN_DB.batch(batch), saved = results.at(-1).results[0];
    if (!saved || saved.status !== 'succeeded' || saved.request_sha256 !== requestHash) fail(409, 'request_pending', 'Check this request receipt before continuing.');
    return JSON.parse(saved.response_json);
  } catch (error) {
    if (error instanceof ReconciliationError) throw error;
    const current = await sql(env, `SELECT ${authSql(false)} AS active,${authSql(privileged)} AS allowed`, ...authArgs(user), ...authArgs(user)).first();
    if (!current.active) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
    if (!current.allowed) fail(403, 'permission_required', 'This account cannot review reconciliation proposals.');
    if (/constraint|RAISE|immutable|requires|exceed|independent|CHECK|UNIQUE|FOREIGN KEY|guard_failed/i.test(String(error))) fail(409, 'state_conflict', 'The transaction, proposal, member or payment evidence changed. Refresh before continuing.');
    fail(503, 'service_unavailable', 'The operation outcome could not be confirmed. Check the request receipt before continuing.');
  }
}
export function reconciliationPermission(request) {
  const parts = new URL(request.url).pathname.replace(/^\/api\/admin\/reconciliations\/?/, '').split('/').filter(Boolean);
  if (request.method === 'GET') return 'reconciliations.read';
  if (request.method === 'POST' && parts.length === 2 && parts[1] === 'proposals') return 'reconciliations.propose';
  if (request.method === 'POST' && parts.length === 3 && parts[0] === 'proposals' && parts[2] === 'reviews') return 'reconciliations.review';
  return null;
}
export async function handleReconciliation(request, env, user) {
  if (!user || user.status !== 'active' || !['owner', 'admin', 'staff'].includes(user.role)) fail(401, 'unauthenticated', 'Sign in to continue.');
  const url = new URL(request.url), prefix = '/api/admin/reconciliations';
  if (url.pathname !== prefix && !url.pathname.startsWith(`${prefix}/`)) fail(404, 'not_found', 'This reconciliation endpoint does not exist.');
  const parts = url.pathname.slice(prefix.length).split('/').filter(Boolean), permission = reconciliationPermission(request);
  if (!permission) fail(405, 'method_not_allowed', 'This reconciliation method is unavailable.');
  if (!user.permissions?.includes(permission) || (permission === 'reconciliations.review' && !manager(user))) fail(403, 'permission_required', 'This reconciliation action is unavailable to this account.');
  if (request.method === 'GET') {
    if (!parts.length) return queue(env, user, url);
    if (parts.length === 1 && parts[0] === 'members') return members(env, user, url);
    if (parts.length === 2 && parts[0] === 'requests') {
      if (url.search || !keyValid(parts[1])) invalid('Invalid request lookup.');
      const [result] = await read(env, user, [sql(env, "SELECT id,status,response_json FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND scope IN ('reconciliations.propose','reconciliations.review')", user.id, parts[1])]);
      const row = result.results[0]; return row ? { status: row.status, request_id: row.id, receipt: row.response_json ? JSON.parse(row.response_json) : null } : { status: 'not_found' };
    }
    if (parts.length === 1) return detail(env, user, parts[0], url);
    fail(404, 'not_found', 'This reconciliation endpoint does not exist.');
  }
  if (url.search) invalid('This endpoint does not accept query filters.');
  return mutate(request, env, user, parts);
}
