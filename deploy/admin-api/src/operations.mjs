import { digest, normalizeEmail } from './security.mjs';
import { SYSTEM_PEOPLE_QUERY, personRow, peopleSearchSql, AVAILABLE_PERSON_PUBLIC_ID_SQL, TRANSACTION_SMS_FACT_JOIN_SQL, TRANSACTION_SMS_FACT_COLUMNS_SQL, transactionSourceRow, sourcePhoneLocalSql } from './core.mjs';
import { TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL, TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL, prepareTransactionPublicReference, AdminSmsError } from './admin-sms.mjs';

export const OPERATIONS_MANAGE_PERMISSIONS = Object.freeze(['collections.manage', 'users.manage', 'receivers.manage', 'payments.manage', 'ledger.manage']);
export const OPERATIONS_CREATE_PERMISSIONS = Object.freeze(['collections.create']);
export class OperationsError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new OperationsError(status, code, message); };
const invalid = message => fail(400, 'invalid_request', message);
const now = () => Math.floor(Date.now() / 1000);
const uuid = () => crypto.randomUUID();
const exact = (value, name, minimum = 1) => {
  if (!Number.isSafeInteger(value) || value < minimum) invalid(`${name} must be an exact integer of at least ${minimum}.`);
  return value;
};
const text = (value, name, min = 1, max = 160) => {
  if (typeof value !== 'string' || value.trim().length < min || value.trim().length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) invalid(`Invalid ${name}.`);
  return value.trim();
};
const id = (value, name = 'id') => {
  if (typeof value !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value)) invalid(`Invalid ${name}.`);
  return value;
};
const oneOf = (value, name, choices) => { if (!choices.includes(value)) invalid(`Invalid ${name}.`); return value; };
const fields = (data, names) => { if (Object.keys(data).some(key => ![...names, 'reason', 'expected_version'].includes(key))) invalid('Request has unsupported fields.'); };
const mutable = (data, names) => { if (!names.some(name => Object.hasOwn(data, name))) invalid('Choose at least one field to change.'); };
const canon = value => JSON.stringify(value, (_, nested) => nested && typeof nested === 'object' && !Array.isArray(nested) ? Object.fromEntries(Object.keys(nested).sort().map(key => [key, nested[key]])) : nested);
const permission = { groups: 'collections', memberships: 'users', users: 'users', payees: 'receivers', transactions: 'payments', journals: 'ledger', accounts: 'ledger' };
const tables = { groups: 'collect_groups', users: 'collect_users', payees: 'collect_payees', transactions: 'collect_transactions', journals: 'collect_journals', accounts: 'collect_ledger_accounts' };
const manage = user => user.role === 'owner' || user.role === 'admin';
const keyValid = key => typeof key === 'string' && /^[a-zA-Z0-9_.-]{8,200}$/.test(key);
const authSql = (writes, staffCreate = false) => `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id
  WHERE s.token_hash=? AND a.id=? AND a.status='active' AND a.role IN (${writes && !staffCreate ? "'owner','admin'" : "'owner','admin','staff'"})
  AND a.auth_version=s.auth_version AND s.auth_version=? AND a.role=? AND s.expires_at>unixepoch())`;
const authArgs = user => [user.token_hash, user.id, user.auth_version, user.role];
const stmt = (env, sql, ...values) => env.ADMIN_DB.prepare(sql).bind(...values);
async function authorizedRead(env, user, queries) {
  const [authorization, ...results] = await env.ADMIN_DB.batch([stmt(env, `SELECT ${authSql(false)} AS allowed`, ...authArgs(user)), ...queries]);
  if (authorization.results[0].allowed !== 1) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
  return results;
}
async function jsonBody(request) {
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) fail(415, 'invalid_content_type', 'Send a JSON request.');
  const reader = request.body?.getReader(); if (!reader) invalid('Send a JSON request.');
  let length = 0; let raw = ''; const decoder = new TextDecoder();
  while (true) { const chunk = await reader.read(); if (chunk.done) break; length += chunk.value.byteLength;
    if (length > 65536) { await reader.cancel(); fail(413, 'request_too_large', 'Request is too large.'); } raw += decoder.decode(chunk.value, { stream: true }); }
  raw += decoder.decode();
  // Inspect numeric lexemes before JSON.parse can round a fractional token into
  // an apparently safe integer. Every numeric input in this contract is integer.
  const lexemes = raw.match(/"(?:\\.|[^"\\])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/g) || [];
  if (lexemes.some(token => token[0] !== '"' && /[.eE]/.test(token))) invalid('Use plain integer JSON numbers, without decimals or exponents.');
  let result; try { result = JSON.parse(raw); } catch { invalid('Request is invalid JSON.'); }
  if (!result || typeof result !== 'object' || Array.isArray(result)) invalid('Send an object.');
  result.reason = text(result.reason, 'reason', 8, 1000); return result;
}
function contacts(row, user) {
  // All callers passed the same-snapshot operating read fence. Staff needs full
  // payment identity for reconciliation. No operator security fields enter the
  // explicitly selected system-person projection.
  return row ? { ...row } : row;
}
function relatedPage(url) {
  for (const name of url.searchParams.keys()) if (!['relation','limit','offset'].includes(name) || url.searchParams.getAll(name).length!==1) invalid('Unsupported detail page filter.');
  const relation=url.searchParams.get('relation');
  if (relation!==null && !/^[a-z_]{1,40}$/.test(relation)) invalid('Invalid related view.');
  if (!relation && url.searchParams.size) invalid('Choose the related view to page.');
  const number=(name,fallback,min,max)=>{const value=url.searchParams.get(name);if(value===null)return fallback;
    if(!/^(0|[1-9][0-9]*)$/.test(value))invalid(`Invalid ${name}.`);const n=Number(value);if(!Number.isSafeInteger(n)||n<min||n>max)invalid(`Invalid ${name}.`);return n;};
  return {relation,limit:number('limit',50,1,100),offset:number('offset',0,0,2147483647)};
}
// Attribution is conservative: an explicit allocation is a recorded member
// relationship; a full source phone must match exactly one actual MoMo profile.
// Last-three digits, app WhatsApp and payer names are never identity keys.
const payerInsightsSql = `WITH source AS (
  SELECT sms_fact.payer_phone FROM collect_transactions t ${TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL} ${TRANSACTION_SMS_FACT_JOIN_SQL} WHERE t.id=?
),phone_matches AS (
  SELECT p.user_id FROM collect_profiles p,source s WHERE NULLIF(p.momo_number,'')=${sourcePhoneLocalSql('s.payer_phone')}
),attributed AS (
  SELECT member_user_id,max(from_phone) AS from_phone,max(from_allocation) AS from_allocation FROM (
    SELECT user_id AS member_user_id,1 AS from_phone,0 AS from_allocation FROM phone_matches WHERE (SELECT count(*) FROM phone_matches)=1
    UNION ALL SELECT member_user_id,0,1 FROM collect_payment_allocations WHERE transaction_id=? AND member_user_id IS NOT NULL
  ) GROUP BY member_user_id
),history AS (
  SELECT a.transaction_id,a.member_user_id FROM collect_payment_allocations a JOIN attributed i ON i.member_user_id=a.member_user_id
  UNION SELECT t.id,p.user_id FROM collect_transactions t ${TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL} ${TRANSACTION_SMS_FACT_JOIN_SQL}
    JOIN collect_profiles p ON NULLIF(p.momo_number,'')=${sourcePhoneLocalSql('sms_fact.payer_phone')}
    JOIN attributed i ON i.member_user_id=p.user_id
    WHERE (SELECT count(*) FROM collect_profiles other WHERE NULLIF(other.momo_number,'')=${sourcePhoneLocalSql('sms_fact.payer_phone')})=1
),latest AS (
  SELECT h.member_user_id,t.id,t.group_id,t.provider_reference,t.observed_at,t.verification_status,r.public_reference,
    row_number() OVER(PARTITION BY h.member_user_id ORDER BY t.observed_at DESC,t.created_at DESC,t.id DESC) AS recency
  FROM history h JOIN collect_transactions t ON t.id=h.transaction_id LEFT JOIN collect_transaction_public_references r ON r.transaction_id=t.id
)
SELECT u.id||':'||COALESCE(m.group_id,'overall') AS id,u.id AS member_user_id,p.public_id,
  (CASE WHEN p.display_name_recorded=1 THEN p.display_name END) AS display_name,COALESCE(p.display_name_recorded,0) AS display_name_recorded,
  u.member_type,NULLIF(p.momo_number,'') AS momo_number,NULLIF(p.momo_pay_code,'') AS momo_pay_code,
  m.group_id,g.title AS group_title,m.role AS membership_role,m.status AS membership_status,i.from_phone,i.from_allocation,
  COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a JOIN collect_transactions tx ON tx.id=a.transaction_id
    WHERE a.member_user_id=u.id AND tx.verification_status='confirmation_recorded'),0) AS total_contributed_rwf,
  COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a JOIN collect_transactions tx ON tx.id=a.transaction_id
    JOIN collect_journals j ON j.allocation_id=a.id AND j.status='posted'
    WHERE a.member_user_id=u.id AND tx.verification_status='confirmation_recorded'),0) AS posted_contributed_rwf,
  COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a JOIN collect_transactions tx ON tx.id=a.transaction_id
    WHERE a.member_user_id=u.id AND a.group_id=m.group_id AND tx.verification_status='confirmation_recorded'),0) AS group_total_contributed_rwf,
  COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a JOIN collect_transactions tx ON tx.id=a.transaction_id
    JOIN collect_journals j ON j.allocation_id=a.id AND j.status='posted'
    WHERE a.member_user_id=u.id AND a.group_id=m.group_id AND tx.verification_status='confirmation_recorded'),0) AS group_posted_contributed_rwf,
  COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a WHERE a.member_user_id=u.id AND a.transaction_id=target.id
    AND (m.group_id IS NULL OR a.group_id=m.group_id)),0) AS transaction_allocated_rwf,
  (SELECT count(*) FROM history h WHERE h.member_user_id=u.id) AS attributed_transaction_count,
  l.id AS latest_transaction_id,l.public_reference AS latest_transaction_reference,l.provider_reference AS latest_provider_reference,
  l.group_id AS latest_transaction_group_id,l.observed_at AS latest_transaction_observed_at,l.verification_status AS latest_transaction_verification_status
FROM attributed i JOIN collect_users u ON u.id=i.member_user_id LEFT JOIN collect_profiles p ON p.user_id=u.id
  LEFT JOIN collect_memberships m ON m.user_id=u.id LEFT JOIN collect_groups g ON g.id=m.group_id
  LEFT JOIN latest l ON l.member_user_id=u.id AND l.recency=1 JOIN collect_transactions target ON target.id=?
ORDER BY COALESCE(p.public_id,u.id),u.id,COALESCE(m.group_id,'')`;
function payerInsightRow({from_phone,from_allocation,...row}) {
  return {...row,display_name_recorded:row.display_name_recorded===1,
    attribution_basis:[...(from_phone===1?['source_full_momo_phone']:[]),...(from_allocation===1?['allocated_member']:[])],
    contribution_basis:'confirmation_recorded_allocations',name_verification:row.display_name_recorded===1?'recorded_not_provider_verified':'not_recorded'};
}

async function detail(env, user, type, resourceId, url) {
  const paging=relatedPage(url);
  id(resourceId); const table = tables[type]; if (!table) fail(404, 'not_found', 'This resource does not exist.');
  const resourceSql = type === 'users' ? `SELECT * FROM (${SYSTEM_PEOPLE_QUERY}) WHERE id=? OR operator_admin_id=?`
    : type === 'transactions' ? `SELECT t.*,p.momo_number_or_code AS payee_momo_number_or_code,${TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL},${TRANSACTION_SMS_FACT_COLUMNS_SQL},
      COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a WHERE a.transaction_id=t.id),0) AS allocated_amount_rwf
      FROM collect_transactions t JOIN collect_payees p ON p.id=t.payee_id ${TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL} ${TRANSACTION_SMS_FACT_JOIN_SQL} WHERE t.id=?`
      : `SELECT * FROM ${table} WHERE id=?`;
  const queries = [stmt(env, resourceSql, resourceId, ...(type === 'users' ? [resourceId] : []))];
  const related = [], available=[];
  const add = (name, sql, ...bindings) => { available.push(name); if(paging.relation&&paging.relation!==name)return;
    related.push(name);queries.push(stmt(env,`SELECT count(*) AS total FROM (${sql})`,...bindings),stmt(env,`${sql} LIMIT ? OFFSET ?`,...bindings,paging.limit,paging.offset)); };
  if (type === 'groups' || type === 'users') add('memberships', `SELECT m.*,g.title AS group_title,(CASE WHEN p.display_name_recorded=1 THEN p.display_name END) AS display_name,
    p.display_name_recorded,p.public_id,p.momo_number,p.momo_pay_code,u.member_type,
    (CASE WHEN u.member_type='app' THEN u.phone_e164 END) AS whatsapp_number,
    COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a JOIN collect_transactions t ON t.id=a.transaction_id
      WHERE a.member_user_id=m.user_id AND a.group_id=m.group_id AND t.verification_status='confirmation_recorded'),0) AS total_contributed_rwf,
    COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a JOIN collect_transactions t ON t.id=a.transaction_id
      JOIN collect_journals j ON j.allocation_id=a.id AND j.status='posted'
      WHERE a.member_user_id=m.user_id AND a.group_id=m.group_id AND t.verification_status='confirmation_recorded'),0) AS posted_contributed_rwf
    FROM collect_memberships m JOIN collect_groups g ON g.id=m.group_id JOIN collect_users u ON u.id=m.user_id
    LEFT JOIN collect_profiles p ON p.user_id=m.user_id WHERE ${type === 'groups' ? 'm.group_id=?' : '(m.user_id=? OR u.operator_admin_id=?)'} ORDER BY m.created_at,m.user_id,m.group_id`, resourceId, ...(type === 'users' ? [resourceId] : []));
  if (type === 'groups') {
    add('payees', 'SELECT * FROM collect_payees WHERE group_id=? ORDER BY created_at,id', resourceId);
    add('accounts', 'SELECT * FROM collect_ledger_accounts WHERE group_id=? ORDER BY code,id', resourceId);
  }
  if (type === 'transactions') {
    add('evidence', 'SELECT id,kind,reference,artifact_sha256 AS sha256,recorded_by_admin_id,recorded_at FROM collect_transaction_evidence WHERE transaction_id=? ORDER BY recorded_at,id', resourceId);
    add('reviews', 'SELECT * FROM collect_transaction_reviews WHERE transaction_id=? ORDER BY reviewed_at,id', resourceId);
    add('allocations', 'SELECT a.*,p.public_id,(CASE WHEN p.display_name_recorded=1 THEN p.display_name END) AS display_name FROM collect_payment_allocations a LEFT JOIN collect_profiles p ON p.user_id=a.member_user_id WHERE a.transaction_id=? ORDER BY a.created_at,a.id', resourceId);
    add('journals', 'SELECT id,description,status,version,created_by_admin_id,edited_by_admin_id,posted_by_admin_id,allocation_id FROM collect_journals WHERE transaction_id=? ORDER BY created_at,id', resourceId);
    add('payer_insights',payerInsightsSql,resourceId,resourceId,resourceId);
  }
  if (type === 'journals') add('entries', 'SELECT e.*,a.code AS account_code,a.name AS account_name FROM collect_journal_entries e JOIN collect_ledger_accounts a ON a.id=e.account_id WHERE journal_id=? ORDER BY line_number', resourceId);
  if(paging.relation&&!available.includes(paging.relation))invalid('This related view is unavailable for the record.');
  const results = await authorizedRead(env, user, queries); if (!results[0].results.length) fail(404, 'not_found', 'This resource does not exist.');
  if (type === 'transactions' && (!Number.isSafeInteger(results[0].results[0].allocated_amount_rwf)
    || results[0].results[0].allocated_amount_rwf < 0 || results[0].results[0].allocated_amount_rwf > results[0].results[0].amount_rwf))
    fail(503, 'invalid_source_data', 'Transaction measurements are temporarily unavailable.');
  const source = results[0].results[0];
  const {public_reference,payer_last3_known,payee_last3_known,public_reference_source_fact_id,public_reference_random_source,
    payer_source_match_count,allocated_member_count,...transactionSource}=source;
  const resource = type === 'users' ? { ...source, ...personRow(source) } : type==='transactions' ? { ...transactionSource,...transactionSourceRow(source),source_parsed_at:source.source_parsed_at??null } : contacts(source,user);
  for (const result of results.slice(1)) for (const row of result.results) for (const key of ['total_contributed_rwf','posted_contributed_rwf','group_total_contributed_rwf','group_posted_contributed_rwf','transaction_allocated_rwf','attributed_transaction_count'])
    if (key in row && (!Number.isSafeInteger(row[key]) || row[key]<0)) fail(503, 'invalid_source_data', 'Contribution measurements are temporarily unavailable.');
  const relatedRows={},pages={};
  related.forEach((key,index)=>{const total=results[index*2+1].results[0].total,rows=results[index*2+2].results;
    if(!Number.isSafeInteger(total)||total<0||rows.length!==Math.max(0,Math.min(paging.limit,total-paging.offset)))fail(503,'invalid_source_data','Related measurements are temporarily unavailable.');
    relatedRows[key]=rows.map(row=>key==='payer_insights'?payerInsightRow(row):contacts(row,user));pages[key]={total,limit:paging.limit,offset:paging.offset,next_offset:paging.offset+rows.length<total?paging.offset+rows.length:null};
  });
  return { resource_type: type, resource, current_actor_id: user.id, can_manage: manage(user) && (type!=='users' || !!source.collect_user_id),
    related:relatedRows,related_pages:pages,related_truncated:related.some(key=>pages[key].total>relatedRows[key].length) };
}
async function lookups(env, user, url) {
  for (const name of url.searchParams.keys()) if (!['kind', 'group_id', 'search', 'limit'].includes(name) || url.searchParams.getAll(name).length !== 1) invalid('Unsupported lookup filter.');
  const kind = oneOf(url.searchParams.get('kind'), 'kind', ['groups', 'users', 'members', 'payees', 'accounts']);
  if (!user.permissions?.includes(`${kind === 'members' ? 'users' : permission[kind]}.read`)) fail(403, 'permission_required', 'This lookup is unavailable.');
  const search = text(url.searchParams.get('search') || '', 'search', 0, 200);
  const rawLimit = url.searchParams.get('limit') ?? '50'; if (!/^[1-9][0-9]*$/.test(rawLimit)) invalid('Invalid limit.');
  const limit = exact(Number(rawLimit), 'limit'); if (limit > 100) invalid('Limit is at most 100.');
  const groupId = url.searchParams.get('group_id');
  if (['members', 'payees', 'accounts'].includes(kind)) id(groupId, 'group_id'); else if (groupId !== null) invalid('This lookup does not accept group_id.');
  let sql, args;
  if (kind === 'groups') { sql = "SELECT id,title AS label,version FROM collect_groups WHERE status='active' AND instr(lower(title),lower(?))>0 ORDER BY title,id LIMIT ?"; args = [search, limit]; }
  if (kind === 'users' || kind === 'members') {
    const match = peopleSearchSql(search);
    const from = `(${SYSTEM_PEOPLE_QUERY})`;
    const eligible = kind === 'members' ? 'EXISTS(SELECT 1 FROM collect_memberships m WHERE m.group_id=? AND m.user_id=records.collect_user_id AND m.status=\'active\')' : '1';
    sql = `WITH records AS (SELECT * FROM ${from}) SELECT id,COALESCE(display_name,'Name not recorded')||' · '||public_id||' · '||COALESCE(momo_number,'') AS label,
      ${kind==='members' ? '(SELECT version FROM collect_memberships m WHERE m.group_id=? AND m.user_id=records.collect_user_id)' : 'version'} AS version,
      public_id,display_name,member_type,momo_number,momo_pay_code,phone_e164,(CASE WHEN member_type='app' THEN phone_e164 END) AS whatsapp_number,
      ${match.score} AS search_rank${kind === 'members' ? ',(SELECT role FROM collect_memberships m WHERE m.group_id=? AND m.user_id=records.collect_user_id) AS role' : ''}
      FROM records WHERE collect_user_id IS NOT NULL AND status='active' AND ${eligible}${match.predicates.length ? ` AND ${match.predicates.join(' AND ')}` : ''}
      ORDER BY search_rank DESC,display_name,id LIMIT ?`;
    args = [...(kind==='members' ? [groupId] : []), ...match.scoreBindings, ...(kind === 'members' ? [groupId,groupId] : []), ...match.bindings, limit];
  }
  if (kind === 'payees') { sql = "SELECT id,label,version,network FROM collect_payees WHERE group_id=? AND status='active' AND instr(lower(label),lower(?))>0 ORDER BY label,id LIMIT ?"; args = [groupId, search, limit]; }
  if (kind === 'accounts') { sql = "SELECT id,code||' · '||name AS label,version,account_type,normal_side FROM collect_ledger_accounts WHERE group_id=? AND status='active' AND (instr(lower(name),lower(?))>0 OR instr(lower(code),lower(?))>0) ORDER BY code,id LIMIT ?"; args = [groupId, search, search, limit]; }
  const [result] = await authorizedRead(env, user, [stmt(env, sql, ...args)]); return { rows: result.results };
}
function plan(env, requestId) {
  const queries = []; let index = 0; const exists = 'EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)';
  return { queries,
    assert(sql, ...values) { queries.push(stmt(env, `INSERT INTO collect_mutation_guards(id,passed) VALUES(?,CASE WHEN NOT ${exists} OR (${sql}) THEN 1 ELSE 0 END)`, `${requestId}:${++index}`, requestId, ...values)); },
    insert(table, values) { const keys = Object.keys(values); queries.push(stmt(env, `INSERT INTO ${table}(${keys.join(',')}) SELECT ${keys.map(() => '?').join(',')} WHERE ${exists}`, ...Object.values(values), requestId)); },
    profile(values) { const keys = Object.keys(values); queries.push(stmt(env, `INSERT INTO collect_profiles(${keys.join(',')},public_id) SELECT ${keys.map(() => '?').join(',')},(${AVAILABLE_PERSON_PUBLIC_ID_SQL}) WHERE ${exists}`, ...Object.values(values), requestId)); },
    update(table, values, where, ...bindings) { const keys = Object.keys(values); queries.push(stmt(env, `UPDATE ${table} SET ${keys.map(key => `${key}=?`).join(',')} WHERE ${where} AND ${exists}`, ...Object.values(values), ...bindings, requestId)); },
    notify(userId, groupId, transactionId, event, subject, message, time) {
      queries.push(stmt(env, `INSERT INTO collect_notification_outbox(id,recipient_user_id,group_id,transaction_id,channel,notification_type,deduplication_key,payload_json,created_at,updated_at)
        SELECT ?,u.id,?,?,'email',?,?,json_object('to',u.email,'subject',?,'text',?),?,? FROM collect_users u
        WHERE u.id=? AND u.email IS NOT NULL AND u.status='active' AND ${exists}`, uuid(), groupId, transactionId, event, `${requestId}:${event}:${userId}`, subject, message, time, time, userId, requestId));
    },
    remove(table, where, ...bindings) { queries.push(stmt(env, `DELETE FROM ${table} WHERE ${where} AND ${exists}`, ...bindings, requestId)); },
  };
}
async function getRow(env, table, resourceId) { const row = await stmt(env, `SELECT * FROM ${table} WHERE id=?`, resourceId).first(); if (!row) fail(404, 'not_found', 'This resource does not exist.'); return row; }
function expected(p, data, table, resourceId) {
  const version = exact(data.expected_version, 'expected_version'); if (version === Number.MAX_SAFE_INTEGER) invalid('Version limit reached.');
  p.assert(`EXISTS(SELECT 1 FROM ${table} WHERE id=? AND version=?)`, resourceId, version); return version + 1;
}
function activeGroup(p, groupId) { p.assert("EXISTS(SELECT 1 FROM collect_groups WHERE id=? AND status='active')", groupId); }
function editableGroup(p, groupId) { p.assert("EXISTS(SELECT 1 FROM collect_groups WHERE id=? AND status!='archived')", groupId); }
function groupValues(data) {
  const output = {};
  for (const key of ['title', 'description', 'category_subtype', 'purpose_label']) if (Object.hasOwn(data, key)) output[key] = data[key] === null && ['category_subtype', 'purpose_label'].includes(key) ? null : text(data[key], key, key === 'title' ? 3 : 0, key === 'title' ? 160 : key === 'description' ? 1000 : 120);
  if ('collection_type' in data) output.collection_type = oneOf(data.collection_type, 'collection_type', ['ikimina', 'sport', 'church', 'wedding', 'other']);
  if ('visibility' in data) output.visibility = oneOf(data.visibility, 'visibility', ['private', 'public_approved']);
  if ('status' in data) output.status = oneOf(data.status, 'status', ['draft', 'active', 'suspended', 'archived']);
  if ('is_platform_sponsored' in data) { if (typeof data.is_platform_sponsored !== 'boolean') invalid('Invalid sponsorship choice.'); output.is_platform_sponsored = data.is_platform_sponsored ? 1 : 0; }
  if ('recurring_cadence' in data) output.recurring_cadence = data.recurring_cadence === null ? null : oneOf(data.recurring_cadence, 'recurring_cadence', ['weekly', 'monthly', 'quarterly', 'annually']);
  if ('suggested_amount_rwf' in data) output.suggested_amount_rwf = data.suggested_amount_rwf === null ? null : exact(data.suggested_amount_rwf, 'suggested_amount_rwf');
  return output;
}
function userValues(data) {
  const output = {};
  if ('email' in data) { output.email = data.email === null ? null : normalizeEmail(data.email); if (data.email !== null && !output.email) invalid('Invalid email.'); }
  if ('phone_e164' in data) { if (data.phone_e164 !== null && (typeof data.phone_e164 !== 'string' || !/^\+2507[2389][0-9]{7}$/.test(data.phone_e164))) invalid('Use a Rwanda phone number in +250 format.'); output.phone_e164 = data.phone_e164; }
  if ('status' in data) output.status = oneOf(data.status, 'status', ['invited', 'active', 'suspended', 'closed']);
  if ('member_type' in data) output.member_type = oneOf(data.member_type, 'member_type', ['app', 'direct']);
  if ('operator_admin_id' in data) output.operator_admin_id = data.operator_admin_id === null ? null : id(data.operator_admin_id, 'operator_admin_id');
  return output;
}
function profileValues(data) {
  const values = {};
  if ('display_name' in data) {values.display_name = text(data.display_name, 'display_name', 2, 120);values.display_name_recorded=1;}
  if ('momo_provider' in data) values.momo_provider = oneOf(data.momo_provider ?? '', 'momo_provider', ['', 'mtn_momo', 'airtel_money']);
  if ('momo_number' in data) {
    let number = data.momo_number ?? '';
    if (typeof number !== 'string') invalid('Use a numeric recorded MoMo number.');
    number = number.replace(/[\s()+.-]/g, '');
    if (/^2507[2389][0-9]{7}$/.test(number)) number = `0${number.slice(3)}`;
    if (number !== '' && !/^07[2389][0-9]{7}$/.test(number)) invalid('Use a recorded Rwanda MoMo number.');
    values.momo_number = number;
  }
  if ('momo_pay_code' in data) { values.momo_pay_code = data.momo_pay_code ?? ''; if (typeof values.momo_pay_code !== 'string' || (values.momo_pay_code!=='' && !/^[0-9]{4,9}$/.test(values.momo_pay_code))) invalid('Use a numeric recorded MoMo code.'); }
  if (values.momo_number && values.momo_provider && !(values.momo_provider === 'mtn_momo' ? /^07[89]/ : /^07[23]/).test(values.momo_number)) invalid('The recorded number does not match the selected MoMo provider.');
  return values;
}
const personFields = ['email', 'phone_e164', 'display_name', 'status', 'member_type', 'operator_admin_id', 'momo_provider', 'momo_number', 'momo_pay_code'];
const groupFields = ['title', 'description', 'collection_type', 'category_subtype', 'purpose_label', 'visibility', 'is_platform_sponsored', 'recurring_cadence', 'suggested_amount_rwf', 'status'];
function evidence(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(key => !['kind', 'reference', 'sha256'].includes(key))) invalid('Invalid evidence.');
  const kind = oneOf(value.kind, 'evidence kind', ['operator_observation', 'payer_receipt', 'receiver_statement', 'provider_statement']);
  if (typeof value.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.sha256)) invalid('Evidence requires a lowercase SHA-256 digest.');
  return { kind, reference: text(value.reference, 'evidence reference', 8, 500), artifact_sha256: value.sha256 };
}
function entries(value) {
  if (!Array.isArray(value) || value.length < 2 || value.length > 100) invalid('A journal requires 2 to 100 entries.');
  let debits = 0n, credits = 0n;
  const output = value.map(line => {
    if (!line || typeof line !== 'object' || Array.isArray(line) || Object.keys(line).some(key => !['account_id', 'debit_rwf', 'credit_rwf', 'description'].includes(key))) invalid('Invalid journal entry.');
    const debit = exact(line.debit_rwf, 'debit_rwf', 0), credit = exact(line.credit_rwf, 'credit_rwf', 0);
    if ((debit === 0) === (credit === 0)) invalid('Each entry must have one positive side.');
    debits += BigInt(debit); credits += BigInt(credit);
    return { account_id: id(line.account_id, 'account_id'), debit_rwf: debit, credit_rwf: credit, description: text(line.description ?? '', 'entry description', 0, 500) };
  });
  if (debits !== credits || debits > BigInt(Number.MAX_SAFE_INTEGER)) invalid('Journal debit and credit totals must be equal and within the exact RWF range.');
  return { rows: output, total: Number(debits) };
}

async function buildMutation(env, user, method, parts, data, requestId) {
  const p = plan(env, requestId); const type = parts[0]; const resourceId = parts[1] ? id(parts[1]) : uuid();
  const time = now(); let version = 1; let groupId = null; let subjectId = resourceId;
  const create = method === 'POST' && parts.length === 1;
  const patch = method === 'PATCH' && parts.length === 2;
  if (create && 'expected_version' in data) invalid('New resources do not accept expected_version.');
  if (type === 'groups' && (create || patch)) {
    fields(data, [...groupFields, ...(create ? ['slug','owner_user_id','receiver'] : [])]);
    const values = groupValues(data); groupId = resourceId;
    if (create) {
      if(user.role==='staff'){
        if(values.visibility==='public_approved'||values.is_platform_sponsored===1)fail(403,'permission_required','Staff may create private groups only.');
        values.visibility='private';values.is_platform_sponsored=0;
      }
      text(data.title, 'title', 3, 160); oneOf(data.collection_type, 'collection_type', ['ikimina', 'sport', 'church', 'wedding', 'other']);
      const slug = text(data.slug, 'slug', 3, 100); if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) invalid('Use lowercase letters, digits and single hyphens for the slug.');
      if(values.status&&!['draft','active'].includes(values.status))invalid('New groups start as private drafts or as safely configured active groups.');
      const ownerId=data.owner_user_id==null?null:id(data.owner_user_id,'owner_user_id');
      let receiver=null;
      if(data.receiver!=null){
        if(typeof data.receiver!=='object'||Array.isArray(data.receiver)||Object.keys(data.receiver).some(key=>!['label','network','momo_number_or_code'].includes(key)))invalid('Invalid group receiver.');
        const route=text(data.receiver.momo_number_or_code,'receiver MoMo number or code',4,12);
        if(!/^[0-9]{4,12}$/.test(route))invalid('Use a numeric receiver MoMo number or code.');
        receiver={label:text(data.receiver.label,'receiver name',2,120),network:oneOf(data.receiver.network,'receiver network',['mtn_momo','airtel_money']),momo_number_or_code:route};
      }
      if(values.status==='active'&&(!ownerId||!receiver))invalid('An active group needs a selected active owner and a recorded MoMo receiver.');
      p.insert('collect_groups', { id: resourceId, slug, ...values, created_by_admin_id: user.id, created_at: time, updated_at: time });
      if(ownerId){p.assert("EXISTS(SELECT 1 FROM collect_users WHERE id=? AND status='active')",ownerId);
        p.insert('collect_memberships',{group_id:resourceId,user_id:ownerId,role:'owner',status:'active',joined_at:time,created_at:time,updated_at:time});}
      if(receiver)p.insert('collect_payees',{id:uuid(),group_id:resourceId,...receiver,status:'active',created_by_admin_id:user.id,creation_reason:data.reason,created_at:time});
    } else {
      mutable(data, groupFields); version = expected(p, data, 'collect_groups', resourceId); editableGroup(p, resourceId);
      if (values.status === 'active') {
        p.assert("EXISTS(SELECT 1 FROM collect_memberships m JOIN collect_users u ON u.id=m.user_id WHERE m.group_id=? AND m.role='owner' AND m.status='active' AND u.status='active')", resourceId);
        p.assert("EXISTS(SELECT 1 FROM collect_payees WHERE group_id=? AND status='active')", resourceId);
      }
      p.update('collect_groups', { ...values, version, updated_at: time }, 'id=?', resourceId);
    }
  } else if (type === 'users' && (create || patch)) {
    fields(data, personFields); const values = userValues(data), profile = profileValues(data);
    if ('operator_admin_id' in data && user.role!=='owner') fail(403, 'permission_required', 'Only the Owner may link an operator account to a Collect person.');
    if (values.operator_admin_id) p.assert('EXISTS(SELECT 1 FROM admin_users WHERE id=?)', values.operator_admin_id);
    if (create) {
      values.member_type ??= 'app';
      // A Direct member's MoMo number is contact data, never an App/WhatsApp
      // credential. The derived phone satisfies the existing contact invariant.
      if (values.member_type==='direct' && !values.email && !values.phone_e164 && profile.momo_number) values.phone_e164=`+250${profile.momo_number.slice(1)}`;
      if (!values.email && !values.phone_e164) invalid('Add an email or Rwanda phone number.');
      text(data.display_name, 'display_name', 2, 120);
      if (values.member_type==='direct' && !profile.momo_number) invalid('Record the Direct member\'s MoMo number. The code is optional.');
      p.insert('collect_users', { id: resourceId, ...values, created_by_admin_id: user.id, created_at: time, updated_at: time });
      p.profile({ user_id: resourceId, ...profile, created_at: time, updated_at: time });
      if (values.member_type==='app') p.notify(resourceId, null, null, 'user_created', 'Your Collect profile', 'A Collect profile was created for you. Use the Collect App sign-in workflow to view your account.', time);
    } else {
      mutable(data, personFields); version = expected(p, data, 'collect_users', resourceId);
      p.assert("EXISTS(SELECT 1 FROM collect_users WHERE id=? AND status!='closed')", resourceId);
      if (values.status && values.status !== 'active') p.assert("NOT EXISTS(SELECT 1 FROM collect_memberships m JOIN collect_groups g ON g.id=m.group_id WHERE m.user_id=? AND m.role='owner' AND m.status='active' AND g.status='active')", resourceId);
      const previous = await getRow(env, 'collect_users', resourceId);
      if ((values.member_type ?? previous.member_type)==='direct') p.assert("EXISTS(SELECT 1 FROM collect_profiles WHERE user_id=? AND COALESCE(?,NULLIF(momo_number,'')) IS NOT NULL AND COALESCE(?,NULLIF(momo_number,''))!='')", resourceId, Object.hasOwn(profile,'momo_number') ? profile.momo_number : null, Object.hasOwn(profile,'momo_number') ? profile.momo_number : null);
      p.update('collect_users', { ...values, version, updated_at: time }, 'id=?', resourceId);
      if (Object.keys(profile).length) { p.assert('EXISTS(SELECT 1 FROM collect_profiles WHERE user_id=?)', resourceId); p.update('collect_profiles', { ...profile, updated_at: time }, 'user_id=?', resourceId); }
    }
  } else if (type === 'memberships' && (create || (method === 'PATCH' && parts.length === 3))) {
    fields(data, create ? ['group_id', 'user_id', 'role', 'status'] : ['role', 'status']);
    groupId = id(create ? data.group_id : parts[1], 'group_id'); const userId = id(create ? data.user_id : parts[2], 'user_id'); subjectId = `${groupId}/${userId}`;
    editableGroup(p, groupId); p.assert("EXISTS(SELECT 1 FROM collect_users WHERE id=? AND status!='closed')", userId);
    const values = {};
    if ('role' in data || create) values.role = oneOf(data.role, 'role', ['owner', 'admin', 'receiver', 'member', 'contributor', 'viewer']);
    if ('status' in data || create) values.status = oneOf(data.status, 'status', ['active', 'invited', 'removed', 'left']);
    if (values.status === 'active') { p.assert("EXISTS(SELECT 1 FROM collect_users WHERE id=? AND status='active')", userId); values.joined_at = time; }
    if (create) p.insert('collect_memberships', { group_id: groupId, user_id: userId, ...values, created_at: time, updated_at: time });
    else {
      mutable(data, ['role', 'status']); version = exact(data.expected_version, 'expected_version') + 1;
      if (!Number.isSafeInteger(version)) invalid('Version limit reached.');
      p.assert('EXISTS(SELECT 1 FROM collect_memberships WHERE group_id=? AND user_id=? AND version=?)', groupId, userId, data.expected_version);
      if ((values.role && values.role !== 'owner') || (values.status && values.status !== 'active')) p.assert("NOT EXISTS(SELECT 1 FROM collect_memberships m JOIN collect_groups g ON g.id=m.group_id WHERE m.group_id=? AND m.user_id=? AND m.role='owner' AND m.status='active' AND g.status='active')", groupId, userId);
      p.update('collect_memberships', { ...values, version, updated_at: time }, 'group_id=? AND user_id=?', groupId, userId);
    }
    p.notify(userId, groupId, null, 'membership_changed', 'Your Collect group membership', 'Your Collect group membership was updated by an administrator. Sign in to view the group and your current role.', time);
  } else if (type === 'payees' && (create || patch)) {
    fields(data, create ? ['group_id', 'label', 'network', 'momo_number_or_code', 'status'] : ['label', 'status']);
    const values = {};
    if ('label' in data || create) values.label = text(data.label, 'label', 2, 120);
    if ('status' in data) values.status = oneOf(data.status, 'status', ['active', 'inactive']);
    if (create) {
      groupId = id(data.group_id, 'group_id'); editableGroup(p, groupId);
      const network = oneOf(data.network, 'network', ['mtn_momo', 'airtel_money']); const route = text(data.momo_number_or_code, 'momo_number_or_code', 4, 12);
      if (!/^[0-9]+$/.test(route)) invalid('Use digits for the MoMo number or code.');
      p.insert('collect_payees', { id: resourceId, group_id: groupId, ...values, network, momo_number_or_code: route, created_by_admin_id: user.id, creation_reason: data.reason, created_at: time });
    } else {
      mutable(data, ['label', 'status']); version = expected(p, data, 'collect_payees', resourceId); const old = await getRow(env, 'collect_payees', resourceId); groupId = old.group_id; editableGroup(p, groupId);
      if (values.status === 'inactive') p.assert("NOT EXISTS(SELECT 1 FROM collect_groups g JOIN collect_payees p ON p.group_id=g.id WHERE p.id=? AND p.status='active' AND g.status='active')", resourceId);
      p.update('collect_payees', { ...values, version }, 'id=?', resourceId);
    }
  } else if (type === 'accounts' && (create || patch)) {
    fields(data, create ? ['group_id', 'code', 'name', 'account_type', 'normal_side'] : ['name', 'status']);
    if (create) {
      groupId = id(data.group_id, 'group_id'); editableGroup(p, groupId);
      const code = text(data.code, 'code', 1, 40); if (!/^[A-Za-z0-9_.-]+$/.test(code)) invalid('Invalid account code.');
      p.insert('collect_ledger_accounts', { id: resourceId, group_id: groupId, code, name: text(data.name, 'name', 2, 120), account_type: oneOf(data.account_type, 'account_type', ['asset', 'liability', 'equity', 'income', 'expense']), normal_side: oneOf(data.normal_side, 'normal_side', ['debit', 'credit']), created_by_admin_id: user.id, created_at: time });
    } else {
      mutable(data, ['name', 'status']); version = expected(p, data, 'collect_ledger_accounts', resourceId); const old = await getRow(env, 'collect_ledger_accounts', resourceId); groupId = old.group_id;
      const values = {}; if ('name' in data) values.name = text(data.name, 'name', 2, 120); if ('status' in data) values.status = oneOf(data.status, 'status', ['active', 'closed']);
      p.update('collect_ledger_accounts', { ...values, version }, 'id=?', resourceId);
    }
  } else if (type === 'transactions' && create) {
    fields(data, ['group_id', 'payee_id', 'provider_reference', 'amount_rwf', 'observed_at', 'evidence', 'source_fact_id']);
    groupId = id(data.group_id, 'group_id'); activeGroup(p, groupId); const payeeId = id(data.payee_id, 'payee_id');
    const payee = await getRow(env, 'collect_payees', payeeId);
    p.assert("EXISTS(SELECT 1 FROM collect_payees WHERE id=? AND group_id=? AND status='active')", payeeId, groupId);
    const observed = exact(data.observed_at, 'observed_at'); if (observed > time + 60) invalid('Observation time cannot be in the future.');
    const sourceFactId=data.source_fact_id==null?null:id(data.source_fact_id,'source_fact_id');
    let reference;
    try { reference=await prepareTransactionPublicReference(env,{transaction_id:resourceId,payee_id:payeeId,source_fact_id:sourceFactId,operation_request_id:requestId}); }
    catch(error){if(error instanceof AdminSmsError)fail(error.status,error.code,error.message);throw error;}
    // The plan insert is claim-guarded. A same-key race loser neither inserts
    // an orphan reference nor changes the winning transaction's identity.
    p.insert('collect_transaction_public_references',reference.values);
    p.insert('collect_transactions', { id: resourceId, group_id: groupId, payee_id: payeeId, network: payee.network, provider_reference: text(data.provider_reference, 'provider_reference', 1, 160), amount_rwf: exact(data.amount_rwf, 'amount_rwf'), observed_at: observed, recorded_by_admin_id: user.id, created_at: time });
    p.insert('collect_transaction_evidence', { id: uuid(), transaction_id: resourceId, ...evidence(data.evidence), recorded_by_admin_id: user.id, operation_request_id: requestId, recorded_at: time });
  } else if (type === 'transactions' && method === 'POST' && parts.length === 3 && ['evidence', 'verification'].includes(parts[2])) {
    const action = parts[2]; fields(data, action === 'evidence' ? ['evidence'] : ['evidence_id', 'outcome']);
    const old = await getRow(env, 'collect_transactions', resourceId); groupId = old.group_id;
    version = expected(p, data, 'collect_transactions', resourceId);
    if (action === 'evidence') {
      p.insert('collect_transaction_evidence', { id: uuid(), transaction_id: resourceId, ...evidence(data.evidence), recorded_by_admin_id: user.id, operation_request_id: requestId, recorded_at: time });
      p.update('collect_transactions', { version }, 'id=?', resourceId);
    } else {
      p.assert("NOT EXISTS(SELECT 1 FROM collect_journals WHERE transaction_id=? AND status='posted')", resourceId);
      const outcome = oneOf(data.outcome, 'outcome', ['confirmation_recorded', 'rejection_recorded', 'evidence_conflict']); const evidenceId = id(data.evidence_id, 'evidence_id');
      p.insert('collect_transaction_reviews', { id: uuid(), transaction_id: resourceId, evidence_id: evidenceId, outcome, transaction_version: version, reviewed_by_admin_id: user.id, operation_request_id: requestId, reason: data.reason, reviewed_at: time });
      p.update('collect_transactions', { verification_status: outcome, verified_by_admin_id: user.id, verified_at: time, version }, 'id=?', resourceId);
    }
  } else if (type === 'journals' && (create || patch)) {
    fields(data, create ? ['group_id', 'description', 'entries', 'allocation_id'] : ['description', 'entries']);
    const lines = entries(data.entries); const description = text(data.description, 'description', 3, 1000);
    let allocationId = null; let transactionId = null;
    if (create) { groupId = id(data.group_id, 'group_id'); if (data.allocation_id != null) allocationId = id(data.allocation_id, 'allocation_id'); }
    else { const old = await getRow(env, 'collect_journals', resourceId); groupId = old.group_id; allocationId = old.allocation_id; transactionId = old.transaction_id; version = expected(p, data, 'collect_journals', resourceId); p.assert("EXISTS(SELECT 1 FROM collect_journals WHERE id=? AND status='draft')", resourceId); }
    activeGroup(p, groupId);
    if (allocationId) {
      const allocation = await getRow(env, 'collect_payment_allocations', allocationId); transactionId = allocation.transaction_id;
      p.assert("EXISTS(SELECT 1 FROM collect_payment_allocations a JOIN collect_transactions t ON t.id=a.transaction_id WHERE a.id=? AND a.group_id=? AND a.amount_rwf=? AND t.verification_status='confirmation_recorded')", allocationId, groupId, lines.total);
    }
    for (const line of lines.rows) p.assert("EXISTS(SELECT 1 FROM collect_ledger_accounts WHERE id=? AND group_id=? AND status='active')", line.account_id, groupId);
    if (create) p.insert('collect_journals', { id: resourceId, group_id: groupId, transaction_id: transactionId, allocation_id: allocationId, operation_request_id: requestId, description, created_by_admin_id: user.id, edited_by_admin_id: user.id, created_at: time });
    else { p.remove('collect_journal_entries', 'journal_id=?', resourceId); p.update('collect_journals', { description, version, edited_by_admin_id: user.id }, 'id=?', resourceId); }
    lines.rows.forEach((line, index) => p.insert('collect_journal_entries', { id: uuid(), journal_id: resourceId, group_id: groupId, line_number: index + 1, ...line }));
  } else if (type === 'journals' && method === 'POST' && parts.length === 3 && parts[2] === 'post') {
    fields(data, []); const old = await getRow(env, 'collect_journals', resourceId); groupId = old.group_id; activeGroup(p, groupId);
    version = expected(p, data, 'collect_journals', resourceId); p.assert("EXISTS(SELECT 1 FROM collect_journals WHERE id=? AND status='draft')", resourceId);
    p.update('collect_journals', { status: 'posted', posted_by_admin_id: user.id, posted_at: time, version }, 'id=?', resourceId);
    if (old.allocation_id) { const allocation = await getRow(env, 'collect_payment_allocations', old.allocation_id);
      if (allocation.member_user_id) p.notify(allocation.member_user_id, groupId, old.transaction_id, 'contribution_posted', 'Contribution recorded in Collect', `A contribution of RWF ${allocation.amount_rwf} was recorded in Collect after independent operator review. Sign in to view the record. This email is a Collect record notification, not a payment provider receipt.`, time);
    }
  } else fail(404, 'not_found', 'This operating action does not exist.');
  return { queries: p.queries, type, subjectId, groupId, version, time };
}

async function mutation(request, env, user, parts) {
  const staffCreate=user.role==='staff'&&request.method==='POST'&&parts.length===1&&parts[0]==='groups';
  const key = request.headers.get('Idempotency-Key'); if (!keyValid(key)) invalid('Supply an Idempotency-Key of 8 to 200 letters, digits, dots, hyphens or underscores.');
  const data = await jsonBody(request); const requestHash = await digest(canon({ method: request.method, path: parts.join('/'), body: data }));
  const [existing] = await authorizedRead(env, user, [stmt(env, 'SELECT * FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key)]);
  if (existing.results.length) {
    const row = existing.results[0]; if (row.request_sha256 !== requestHash) fail(409, 'idempotency_conflict', 'This request key belongs to different content.');
    if (row.status !== 'succeeded') fail(409, 'request_pending', 'This request is awaiting reconciliation.'); return JSON.parse(row.response_json);
  }
  const requestId = uuid(); const operation = await buildMutation(env, user, request.method, parts, data, requestId);
  const receipt = { request_id: requestId, resource_type: operation.type, resource_id: operation.subjectId, version: operation.version, status: 'succeeded' };
  const scope = `${operation.type}.${request.method.toLowerCase()}${parts[2] && operation.type !== 'memberships' ? `.${parts[2]}` : ''}`;
  const batch = [
    stmt(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN '+authSql(true,staffCreate)+' THEN 1 ELSE 0 END', `${requestId}:auth`, ...authArgs(user)),
    stmt(env, `INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(actor_admin_id,idempotency_key) DO NOTHING`, requestId, user.id, scope, key, requestHash, operation.time),
    stmt(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND request_sha256=?) THEN 1 ELSE 0 END', `${requestId}:key`, user.id, key, requestHash),
    ...operation.queries,
    stmt(env, `INSERT INTO collect_operations_audit(id,actor_admin_id,operation_request_id,action,group_id,subject_type,subject_id,evidence_json,occurred_at)
      SELECT ?,?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)`, uuid(), user.id, requestId, scope, operation.groupId, operation.type, operation.subjectId, JSON.stringify({ reason: data.reason, request_sha256: requestHash, previous_version: data.expected_version ?? null, resulting_version: operation.version, changed_fields: Object.keys(data).filter(key => !['reason', 'expected_version'].includes(key)) }), operation.time, requestId),
    stmt(env, "UPDATE collect_operation_requests SET status='succeeded',response_json=?,completed_at=? WHERE id=?", JSON.stringify(receipt), operation.time, requestId),
    stmt(env, 'DELETE FROM collect_mutation_guards WHERE id LIKE ?', `${requestId}:%`),
    stmt(env, 'SELECT response_json,request_sha256,status FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key),
  ];
  try {
    const result = await env.ADMIN_DB.batch(batch); const saved = result.at(-1).results[0];
    if (!saved || saved.status !== 'succeeded' || saved.request_sha256 !== requestHash) fail(409, 'request_pending', 'This request is awaiting reconciliation.');
    return JSON.parse(saved.response_json);
  } catch (error) {
    if (error instanceof OperationsError) throw error;
    const current = await stmt(env, `SELECT ${authSql(false)} AS active,${authSql(true,staffCreate)} AS manager`, ...authArgs(user), ...authArgs(user)).first();
    if (!current.active) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
    if (!current.manager) fail(403, 'permission_required', 'This account has read-only operating access.');
    if (/constraint|RAISE|immutable|requires|exceed|independent|CHECK|UNIQUE|FOREIGN KEY|guard_failed/i.test(String(error))) fail(409, 'state_conflict', 'The record, approval or related state changed, or conflicts with this action. Refresh the details before trying again.');
    fail(503, 'service_unavailable', 'The operation outcome could not be confirmed. Check the request receipt before continuing.');
  }
}

export async function handleOperations(request, env, user) {
  if (!user || user.status !== 'active' || !['owner', 'admin', 'staff'].includes(user.role)) fail(401, 'unauthenticated', 'Sign in to continue.');
  const url = new URL(request.url); const prefix = '/api/admin/operations/';
  if (!url.pathname.startsWith(prefix)) fail(404, 'not_found', 'This operating endpoint does not exist.');
  const parts = url.pathname.slice(prefix.length).split('/');
  if (parts[0] === 'lookups' && parts.length === 1 && request.method === 'GET') return lookups(env, user, url);
  if (parts[0] === 'requests' && request.method === 'GET' && parts.length <= 2) {
    if (parts.length === 2) {
      if (url.search || !keyValid(parts[1])) invalid('Invalid request lookup.');
      const [result] = await authorizedRead(env, user, [stmt(env, 'SELECT id,status,response_json FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, parts[1])]);
      const row = result.results[0]; if (!row) return { status: 'not_found' };
      return { status: row.status, request_id: row.id, receipt: row.response_json ? JSON.parse(row.response_json) : null };
    }
    for (const key of url.searchParams.keys()) if (!['limit', 'offset'].includes(key) || url.searchParams.getAll(key).length !== 1) invalid('Invalid request history filter.');
    const rawLimit = url.searchParams.get('limit') ?? '25', rawOffset = url.searchParams.get('offset') ?? '0';
    if (!/^[1-9][0-9]*$/.test(rawLimit) || !/^(0|[1-9][0-9]*)$/.test(rawOffset)) invalid('Invalid request history page.');
    const limit = exact(Number(rawLimit), 'limit'), offset = exact(Number(rawOffset), 'offset', 0);
    if (limit > 100 || offset > 2147483647) invalid('Invalid request history page.');
    const [count, page] = await authorizedRead(env, user, [stmt(env, 'SELECT count(*) AS total FROM collect_operation_requests WHERE actor_admin_id=?', user.id), stmt(env, 'SELECT id,idempotency_key,scope,status,response_json,created_at,completed_at FROM collect_operation_requests WHERE actor_admin_id=? ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?', user.id, limit, offset)]);
    return { total: count.results[0].total, rows: page.results.map(({ response_json, ...row }) => ({ ...row, receipt: response_json ? JSON.parse(response_json) : null })) };
  }
  if (!Object.hasOwn(permission, parts[0])) fail(404, 'not_found', 'This operating endpoint does not exist.');
  if (request.method === 'GET' && parts.length === 2 && parts[0] !== 'memberships') {
    if (!user.permissions?.includes(`${permission[parts[0]]}.read`)) fail(403, 'permission_required', 'This view is unavailable.');
    return detail(env, user, parts[0], parts[1],url);
  }
  if (url.search) invalid('This endpoint does not accept query filters.');
  if (!['POST', 'PATCH'].includes(request.method)) fail(405, 'method_not_allowed', 'This operating method is unavailable.');
  const privateGroupCreate=request.method==='POST'&&parts.length===1&&parts[0]==='groups'&&user.role==='staff'&&user.permissions?.includes('collections.create');
  if (!privateGroupCreate&&(!manage(user) || !user.permissions?.includes(`${permission[parts[0]]}.manage`))) fail(403, 'permission_required', 'This account has read-only operating access for this action.');
  if (request.method==='POST'&&parts[0]==='transactions'&&parts.length===3&&parts[2]==='allocations')
    fail(409,'reconciliation_required','Allocate this transaction through a member proposal and independent reconciliation review.');
  return mutation(request, env, user, parts);
}
