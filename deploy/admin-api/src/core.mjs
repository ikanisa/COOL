import { TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL, TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL, transactionPublicReferenceRow } from './admin-sms.mjs';

// Explicit, read-only projections of the fresh Cloudflare Collect schema.
// No legacy RPC dispatch, provider requests, operating writes or inferred source matching.
export const CORE_READ_PERMISSIONS = Object.freeze([
  'collections.read', 'users.read', 'receivers.read', 'payments.read', 'ledger.read',
]);
// Evaluate inside the identity-creating D1 batch, not in a preceding read: two
// concurrent creations must not choose the same apparently available number.
export const AVAILABLE_PERSON_PUBLIC_ID_SQL = `SELECT (CASE WHEN min(candidate) IS NULL THEN NULL ELSE printf('%06d',min(candidate)) END) FROM
  (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM collect_public_identities WHERE public_id!='999999') c
  WHERE NOT EXISTS(SELECT 1 FROM collect_public_identities i WHERE i.public_id=printf('%06d',c.candidate))`;

export class CoreReadError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new CoreReadError(status, code, message); };
const invalid = message => fail(400, 'invalid_filter', message);
const integer = value => {
  if (!Number.isSafeInteger(value) || value < 0) fail(503, 'invalid_source_data', 'Workspace measurements are temporarily unavailable.');
  return value;
};
const date = seconds => seconds == null ? null : new Date(integer(seconds) * 1000).toISOString();
const rwf = amount => String(integer(amount));
function maskedRoute(value) {
  if (!value) return null;
  return `••••${value.slice(value.length >= 8 ? -4 : -2)}`;
}
function maskedEmail(value) {
  if (!value) return null;
  const separator = value.lastIndexOf('@');
  return `${value.slice(0, 1)}•••${value.slice(separator)}`;
}
export function personRow(row) {
  if (!/^[0-9]{6}$/.test(row.public_id)) fail(503, 'invalid_source_data', 'A person identifier is unavailable.');
  const types = [row.operator_role === 'staff' ? 'Staff' : row.operator_role ? 'Admin' : null,
    row.collect_user_id ? row.member_type === 'direct' ? 'Direct' : 'App' : null].filter(Boolean);
  return {
    title: row.public_id,
    subtitle: row.display_name || row.email || '',
    status: row.status, amount: `${integer(row.active_groups)} groups`,
    public_id: row.public_id, display_name: row.display_name,
    display_name_recorded: row.display_name_recorded===1,
    person_id: row.id, collect_user_id: row.collect_user_id, operator_admin_id: row.operator_admin_id,
    operator_public_id: row.operator_public_id, operator_role: row.operator_role, operator_status: row.operator_status,
    user_types: types, member_type: row.member_type, phone_e164: row.phone_e164, email: row.email,
    whatsapp_number: row.member_type === 'app' ? row.phone_e164 : null,
    momo_provider: row.momo_provider || null, momo_number: row.momo_number || null, momo_pay_code: row.momo_pay_code || null,
    total_contributed_rwf: integer(row.total_contributed_rwf), posted_contributed_rwf: integer(row.posted_contributed_rwf),
    contribution_basis: 'confirmation_recorded_allocations',
    name_verification: row.display_name_recorded===1 ? 'recorded_not_provider_verified' : 'not_recorded',
    phone_masked: maskedRoute(row.phone_e164), email_masked: maskedEmail(row.email),
    active_groups: integer(row.active_groups), account_status: row.status,
  };
}

// A transaction sees only its explicitly preserved source fact. Matching a
// provider reference, payer name or masked suffix must never select a source.
export const TRANSACTION_SMS_FACT_JOIN_SQL = `LEFT JOIN collect_transaction_sms_sources reviewed_sms_source ON reviewed_sms_source.transaction_id=t.id
  LEFT JOIN collect_sms_facts sms_fact ON sms_fact.id=COALESCE(public_reference.source_fact_id,reviewed_sms_source.source_fact_id)`;
export const sourcePhoneLocalSql = value => `(CASE WHEN substr(${value},1,4)='+250' THEN '0'||substr(${value},5)
  WHEN substr(${value},1,3)='250' THEN '0'||substr(${value},4) ELSE ${value} END)`;
export const TRANSACTION_SMS_FACT_COLUMNS_SQL = `sms_fact.id AS source_fact_id,sms_fact.source_kind,sms_fact.parser_version,
  CASE WHEN public_reference.source_fact_id IS NOT NULL THEN 'public_reference'
    WHEN reviewed_sms_source.source_fact_id IS NOT NULL THEN 'reviewed_member_receipt' ELSE 'not_recorded' END AS source_link_basis,
  CASE WHEN public_reference.source_fact_id IS NULL THEN reviewed_sms_source.review_id END AS source_review_id,
  sms_fact.extraction_status AS source_extraction_status,sms_fact.source_body_sha256,sms_fact.source_payload_sha256,sms_fact.parsed_at AS source_parsed_at,
  sms_fact.payer_name,sms_fact.payer_phone,sms_fact.payer_masked_phone,sms_fact.payer_last3,
  sms_fact.payee_momo_number,sms_fact.payee_momo_code,sms_fact.momo_transaction_reference,sms_fact.momo_timestamp_local,sms_fact.momo_timezone_offset,
  sms_fact.amount_rwf AS source_amount_rwf,sms_fact.wallet_balance_rwf,sms_fact.network AS source_network,sms_fact.direction,sms_fact.is_payment,
  (SELECT count(*) FROM collect_profiles cp WHERE NULLIF(cp.momo_number,'')=${sourcePhoneLocalSql('sms_fact.payer_phone')}) AS payer_source_match_count,
  (SELECT count(DISTINCT a.member_user_id) FROM collect_payment_allocations a WHERE a.transaction_id=t.id) AS allocated_member_count`;
export function transactionSourceRow(row) {
  const matches=integer(row.payer_source_match_count), allocated=integer(row.allocated_member_count);
  return {...transactionPublicReferenceRow(row),
    source_fact_id:row.source_fact_id??null,source_kind:row.source_kind??null,parser_version:row.parser_version??null,
    source_link_basis:row.source_link_basis??'not_recorded',source_review_id:row.source_review_id??null,
    source_extraction_status:row.source_extraction_status??null,source_body_sha256:row.source_body_sha256??null,
    source_payload_sha256:row.source_payload_sha256??null,source_parsed_at:date(row.source_parsed_at),
    payer_name:row.payer_name??null,payer_phone:row.payer_phone??null,payer_masked_phone:row.payer_masked_phone??null,
    payer_last3:row.payer_last3??null,payer_last3_known:row.payer_last3!=null,
    payee_momo_number:row.payee_momo_number??null,payee_momo_code:row.payee_momo_code??null,
    payee_momo_number_or_code:row.payee_momo_number_or_code,
    momo_transaction_reference:row.momo_transaction_reference??null,momo_timestamp_local:row.momo_timestamp_local??null,
    momo_timezone_offset:row.momo_timezone_offset??null,timezone_known:row.momo_timezone_offset!=null,
    source_amount_rwf:row.source_amount_rwf==null?null:integer(row.source_amount_rwf),
    wallet_balance_rwf:row.wallet_balance_rwf==null?null:integer(row.wallet_balance_rwf),
    source_network:row.source_network??null,direction:row.direction??null,is_payment:row.is_payment==null?null:row.is_payment===1,
    payer_source_match_status:!row.payer_phone?'not_recorded':matches===1?'unique_recorded_match':matches>1?'ambiguous':'unmatched',
    payer_insights_status:allocated>0||matches===1?'available':matches>1?'ambiguous':'not_attributed',
    provider_confirmation:false,settlement_status:'not_asserted'};
}

// Explicit operator links collapse one person; emails are never identity keys.
// Security fields are excluded even for an Owner reading the system directory.
export const SYSTEM_PEOPLE_QUERY = `SELECT u.id,u.id AS collect_user_id,u.operator_admin_id,
  u.email,u.phone_e164,u.status,u.created_at,u.updated_at,u.version,u.member_type,
  COALESCE(p.public_id,i.public_id) AS public_id,(CASE WHEN p.display_name_recorded=1 THEN p.display_name END) AS display_name,p.momo_provider,p.momo_number,p.momo_pay_code,
  a.role AS operator_role,a.status AS operator_status,ai.public_id AS operator_public_id,
  COALESCE(contributions.total_contributed_rwf,0) AS total_contributed_rwf,
  COALESCE(contributions.posted_contributed_rwf,0) AS posted_contributed_rwf,
  COALESCE((SELECT group_concat(g.title,' ') FROM collect_memberships m JOIN collect_groups g ON g.id=m.group_id
    WHERE m.user_id=u.id AND m.status='active'),'') AS group_names,
  COALESCE((SELECT group_concat(m.role,' ') FROM collect_memberships m WHERE m.user_id=u.id AND m.status='active'),'') AS group_roles,
  (SELECT count(*) FROM collect_memberships m WHERE m.user_id=u.id AND m.status='active') AS active_groups,COALESCE(p.display_name_recorded,0) AS display_name_recorded
  FROM collect_users u LEFT JOIN collect_profiles p ON p.user_id=u.id
  -- Aggregate once for the complete directory query, rather than scanning all
  -- allocations twice per person before a global count, filter or page sort.
  -- allocation_id is UNIQUE on journals, so the optional posted journal cannot
  -- multiply either total. Keep integer SUM and the existing per-row safe bound.
  LEFT JOIN (SELECT x.member_user_id,sum(x.amount_rwf) AS total_contributed_rwf,
    sum(CASE WHEN j.id IS NOT NULL THEN x.amount_rwf ELSE 0 END) AS posted_contributed_rwf
    FROM collect_payment_allocations x JOIN collect_transactions t ON t.id=x.transaction_id
    LEFT JOIN collect_journals j ON j.allocation_id=x.id AND j.status='posted'
    WHERE t.verification_status='confirmation_recorded' GROUP BY x.member_user_id) contributions ON contributions.member_user_id=u.id
  LEFT JOIN collect_public_identities i ON i.collect_user_id=u.id
  LEFT JOIN admin_users a ON a.id=u.operator_admin_id LEFT JOIN collect_public_identities ai ON ai.admin_user_id=a.id
  UNION ALL SELECT a.id,NULL,a.id,a.email,NULL,a.status,a.created_at,a.updated_at,NULL,NULL,
  i.public_id,NULLIF(a.display_name,''),NULL,NULL,NULL,a.role,a.status,i.public_id,0,0,'','',0,(CASE WHEN length(trim(a.display_name))>0 THEN 1 ELSE 0 END)
  FROM admin_users a JOIN collect_public_identities i ON i.admin_user_id=a.id
  WHERE NOT EXISTS(SELECT 1 FROM collect_users u WHERE u.operator_admin_id=a.id)`;

const fold = value => value.normalize('NFKC').toLowerCase().replace(/[àáâãäå]/g, 'a').replace(/[èéêë]/g, 'e')
  .replace(/[ìíîï]/g, 'i').replace(/[òóôõö]/g, 'o').replace(/[ùúûü]/g, 'u').replace(/ç/g, 'c');
const foldedSql = column => {
  let value = `lower(COALESCE(${column},''))`;
  for (const [letters, replacement] of [['àáâãäåÀÁÂÃÄÅ', 'a'], ['èéêëÈÉÊË', 'e'], ['ìíîïÌÍÎÏ', 'i'], ['òóôõöÒÓÔÕÖ', 'o'], ['ùúûüÙÚÛÜ', 'u'], ['çÇ', 'c']])
    for (const letter of letters) value = `replace(${value},'${letter}','${replacement}')`;
  return value;
};
const phoneSql = column => `(CASE WHEN substr(COALESCE(${column},''),1,4)='+250' THEN '0'||substr(${column},5)
  WHEN substr(COALESCE(${column},''),1,3)='250' THEN '0'||substr(${column},4) ELSE COALESCE(${column},'') END)`;
export function peopleSearch(search) {
  let source = fold(search); const types = [], statuses = [], roles = [], groupNames = []; let group = null;
  source = source.replace(/\b(?:show|find|list)\s+(?:me\s+)?/g, '').replace(/\b(app|direct|admin|staff|owner)\s+(?:users?|members?|accounts?)\b/g, (_, type) => { types.push(type); return ''; })
    .replace(/\b(?:(?:users?|members?)\s+)?(?:with\s+no|without)\s+(?:active\s+)?groups?\b/g, () => { group = false; return ''; })
    .replace(/\b(?:(?:users?|members?)\s+)?with\s+(?:active\s+)?groups?\b/g, () => { group = true; return ''; });
  const tokens = [];
  for (const match of source.matchAll(/"([^"]+)"|(\S+)/g)) {
    const token = match[1] ?? match[2];
    if (token.startsWith('type:')) { const type = token.slice(5); if (!['app','direct','admin','staff','owner'].includes(type)) invalid('Use type:app, type:direct, type:admin, type:staff or type:owner.'); types.push(type); }
    else if (token.startsWith('status:')) { const status = token.slice(7); if (!['invited','active','suspended','closed','revoked'].includes(status)) invalid('Unsupported person status.'); statuses.push(status); }
    else if (token === 'group:none') group = false;
    else if (token === 'group:member') group = true;
    else if (token.startsWith('role:')) { const role=token.slice(5); if (!['owner','admin','receiver','member','contributor','viewer'].includes(role)) invalid('Unsupported group role.'); roles.push(role); }
    else if (token.startsWith('group:')) { const name=token.slice(6); if (!name) invalid('Add a group name after group:.'); groupNames.push(name); }
    else tokens.push(token);
  }
  // Treat phone punctuation/spacing as formatting when the whole residual query
  // is numeric. Six-digit IDs and MoMo codes retain their leading zeros.
  if (tokens.length && /^[+()\s.\-0-9]+$/.test(tokens.join(' '))) {
    let digits = tokens.join('').replace(/[^0-9]/g, '');
    if (digits.length === 12 && digits.startsWith('250')) digits = `0${digits.slice(3)}`;
    else if (digits.length === 9 && digits.startsWith('7')) digits = `0${digits}`;
    tokens.splice(0, tokens.length, digits);
  }
  if (tokens.length > 16) invalid('Use at most 16 search terms.');
  return { tokens, types: [...new Set(types)], statuses: [...new Set(statuses)], roles: [...new Set(roles)], groupNames, group };
}
export function peopleSearchSql(search) {
  const intent = peopleSearch(search); const predicates = [], bindings = [], scores = [], scoreBindings = [];
  for (const type of intent.types) {
    predicates.push(type === 'app' || type === 'direct' ? 'member_type=?' : type === 'admin' ? "operator_role IN ('owner','admin')" : 'operator_role=?');
    if (type !== 'admin') bindings.push(type);
  }
  for (const status of intent.statuses) { predicates.push('(status=? OR operator_status=?)'); bindings.push(status, status); }
  for (const role of intent.roles) { predicates.push("instr(' '||group_roles||' ',?)>0"); bindings.push(` ${role} `); }
  for (const name of intent.groupNames) { predicates.push(`instr(${foldedSql('group_names')},?)>0`); bindings.push(name); }
  if (intent.group !== null) predicates.push(`active_groups${intent.group ? '>' : '='}0`);
  const fields = ['public_id', 'operator_public_id', 'display_name', 'email', 'phone_e164', 'momo_number', 'momo_pay_code', 'group_names', 'group_roles'];
  for (const token of intent.tokens) {
    const numeric = /^[0-9]+$/.test(token);
    const columns = fields.map(column => numeric && ['phone_e164','momo_number'].includes(column) ? phoneSql(column)
      : ['display_name','group_names'].includes(column) ? foldedSql(column) : `lower(COALESCE(${column},''))`);
    predicates.push(`(${columns.map(column => `instr(${column},?)>0`).join(' OR ')})`); bindings.push(...columns.map(() => token));
    scores.push(`(CASE WHEN public_id=? OR operator_public_id=? THEN 100 WHEN ${phoneSql('phone_e164')}=? OR momo_number=? OR momo_pay_code=? THEN 80 WHEN ${foldedSql('display_name')}=? THEN 60 ELSE 10 END)`);
    scoreBindings.push(token, token, token, token, token, token);
  }
  return { predicates, bindings, score: scores.length ? scores.join('+') : '0', scoreBindings };
}

const lists = Object.freeze({
  groups: {
    permission: 'collections.read', statuses: ['draft', 'active', 'suspended', 'archived'],
    search: ['title', 'slug', 'description', 'purpose_label'],
    query: `SELECT g.id,g.slug,g.title,g.description,g.collection_type,g.purpose_label,g.status,g.visibility,
      g.is_platform_sponsored,g.created_at,
      (SELECT count(*) FROM collect_memberships m WHERE m.group_id=g.id AND m.status='active') AS active_members
      FROM collect_groups g WHERE g.country_code='RW'`,
    row: row => ({ title: row.title, subtitle: [row.collection_type, row.visibility].join(' · '),
      status: row.status, amount: `${integer(row.active_members)} members`, slug: row.slug,
      collection_type: row.collection_type, purpose_label: row.purpose_label, visibility: row.visibility,
      is_platform_sponsored: row.is_platform_sponsored === 1, active_members: integer(row.active_members) }),
  },
  users: {
    permission: 'users.read', statuses: ['invited', 'active', 'suspended', 'closed', 'revoked'],
    search: ['public_id', 'display_name'], query: SYSTEM_PEOPLE_QUERY, row: personRow, people: true,
  },
  members: {
    permission: 'users.read', statuses: ['invited', 'active', 'suspended', 'closed'],
    search: ['public_id', 'display_name'],
    query: `SELECT * FROM (${SYSTEM_PEOPLE_QUERY}) WHERE collect_user_id IS NOT NULL AND active_groups>0`,
    row: personRow, people: true,
  },
  payees: {
    permission: 'receivers.read', statuses: ['active', 'inactive'],
    search: ['label', 'group_title', 'network', 'momo_number_or_code'],
    query: `SELECT p.id,p.group_id,p.label,p.network,p.momo_number_or_code,p.status,p.created_at,g.title AS group_title
      FROM collect_payees p JOIN collect_groups g ON g.id=p.group_id WHERE g.country_code='RW'`,
    row: row => ({ title: row.label, subtitle: row.group_title,
      status: row.status, amount: row.momo_number_or_code, group_id: row.group_id,
      group_name: row.group_title, network: row.network, momo_masked: maskedRoute(row.momo_number_or_code),
      momo_number_or_code: row.momo_number_or_code,
      momo_number: /^(?:07[2389][0-9]{7}|2507[2389][0-9]{7})$/.test(row.momo_number_or_code) ? row.momo_number_or_code : null,
      momo_pay_code: /^(?:07[2389][0-9]{7}|2507[2389][0-9]{7})$/.test(row.momo_number_or_code) ? null : row.momo_number_or_code }),
  },
  transactions: {
    permission: 'payments.read', statuses: ['pending', 'confirmation_recorded', 'rejection_recorded', 'evidence_conflict'],
    search: ['public_reference', 'provider_reference', 'group_title', 'payee_label', 'payer_name', 'payer_phone', 'payer_last3', 'payee_momo_number', 'payee_momo_code', 'payee_momo_number_or_code', 'momo_transaction_reference'],
    query: `SELECT t.id,t.group_id,t.payee_id,t.network,t.provider_reference,t.amount_rwf,t.verification_status AS status,
      t.created_at,t.observed_at,g.title AS group_title,p.label AS payee_label,p.momo_number_or_code AS payee_momo_number_or_code,
      ${TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL},${TRANSACTION_SMS_FACT_COLUMNS_SQL},
      COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a WHERE a.transaction_id=t.id),0) AS allocated_amount_rwf,
      (SELECT count(*) FROM collect_journals j WHERE j.transaction_id=t.id AND j.status='posted') AS posted_journals
      FROM collect_transactions t JOIN collect_groups g ON g.id=t.group_id JOIN collect_payees p ON p.id=t.payee_id
      ${TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL} ${TRANSACTION_SMS_FACT_JOIN_SQL}
      WHERE g.country_code='RW'`,
    row: row => ({ ...transactionSourceRow(row),title: row.public_reference??row.provider_reference, subtitle: `${row.group_title} · ${row.payee_label}`,
      status: row.status, amount: rwf(row.amount_rwf), group_id: row.group_id, group_name: row.group_title,
      payee_id: row.payee_id, payee_label: row.payee_label, network: row.network, rail: 'rwanda_momo',
      provider_reference: row.provider_reference, amount_rwf: integer(row.amount_rwf),
      allocated_amount_rwf: integer(row.allocated_amount_rwf),
      allocation_status: row.allocated_amount_rwf === row.amount_rwf ? 'allocated' : row.allocated_amount_rwf > 0 ? 'partial' : 'unallocated',
      posted_journals: integer(row.posted_journals), observed_at: date(row.observed_at) }),
  },
  ledgers: {
    permission: 'ledger.read', statuses: ['draft', 'posted'],
    search: ['description', 'group_title'],
    query: `SELECT j.id,j.group_id,j.transaction_id,j.allocation_id,j.description,j.status,j.created_at,j.posted_at,g.title AS group_title,
      COALESCE((SELECT sum(e.debit_rwf) FROM collect_journal_entries e WHERE e.journal_id=j.id),0) AS debit_rwf,
      COALESCE((SELECT sum(e.credit_rwf) FROM collect_journal_entries e WHERE e.journal_id=j.id),0) AS credit_rwf,
      (SELECT count(*) FROM collect_journal_entries e WHERE e.journal_id=j.id) AS entry_count
      FROM collect_journals j JOIN collect_groups g ON g.id=j.group_id WHERE g.country_code='RW'`,
    row: row => ({ title: row.description, subtitle: row.group_title, status: row.status, amount: rwf(row.debit_rwf),
      group_id: row.group_id, group_name: row.group_title, transaction_id: row.transaction_id, allocation_id: row.allocation_id,
      debit_rwf: integer(row.debit_rwf), credit_rwf: integer(row.credit_rwf), entry_count: integer(row.entry_count),
      balanced: row.entry_count >= 2 && row.debit_rwf > 0 && row.debit_rwf === row.credit_rwf, posted_at: date(row.posted_at) }),
  },
});

function parameters(url, overview = false) {
  const allowed = overview ? ['country'] : ['country', 'search', 'status', 'limit', 'offset', 'sort'];
  for (const key of url.searchParams.keys()) {
    if (!allowed.includes(key) || url.searchParams.getAll(key).length !== 1) invalid('This filter is not supported.');
  }
  const country = url.searchParams.get('country') ?? 'RW';
  if (country !== 'RW') invalid('Only the Rwanda workspace is available.');
  if (overview) return { country };
  const numeric = (name, fallback, minimum, maximum) => {
    const raw = url.searchParams.get(name);
    if (raw === null) return fallback;
    if (!/^(0|[1-9][0-9]*)$/.test(raw)) invalid(`Invalid ${name}.`);
    const result = Number(raw);
    if (!Number.isSafeInteger(result) || result < minimum || result > maximum) invalid(`Invalid ${name}.`);
    return result;
  };
  const rawSearch = url.searchParams.get('search') ?? '';
  if (rawSearch.length > 200 || /[\u0000-\u001f\u007f]/.test(rawSearch)) invalid('Search must contain at most 200 printable characters.');
  const sort = url.searchParams.get('sort') ?? 'created_at_desc';
  if (!/^[a-z_]+_(?:asc|desc)$/.test(sort)) invalid('This sort is not supported.');
  return { country, search: rawSearch.trim(), status: url.searchParams.get('status') ?? '',
    limit: numeric('limit', 25, 1, 100), offset: numeric('offset', 0, 0, 2147483647), sort };
}


// SQL expressions come exclusively from this registry; user input is bound.
const CORE_SORTS = {
  groups: {title:'title COLLATE NOCASE',slug:'slug',collection_type:'collection_type',visibility:'visibility',active_members:'active_members'},
  users: {public_id:'public_id',display_name:'display_name COLLATE NOCASE',email:'email COLLATE NOCASE',member_type:'member_type',whatsapp_number:"CASE WHEN member_type='app' THEN phone_e164 END",momo_number:'momo_number',momo_pay_code:'momo_pay_code',active_groups:'active_groups',total_contributed_rwf:'total_contributed_rwf',posted_contributed_rwf:'posted_contributed_rwf'},
  payees: {label:'label COLLATE NOCASE',group_title:'group_title COLLATE NOCASE',momo_number_or_code:'momo_number_or_code'},
  transactions: {public_reference:'public_reference',allocation_status:"CASE WHEN allocated_amount_rwf=amount_rwf THEN 'allocated' ELSE 'unallocated' END",amount_rwf:'amount_rwf',allocated_amount_rwf:'allocated_amount_rwf',remaining_rwf:'amount_rwf-allocated_amount_rwf',payer_name:'payer_name COLLATE NOCASE',payer_last3:'payer_last3',payee_momo_number_or_code:'payee_momo_number_or_code',group_title:'group_title COLLATE NOCASE',payee_label:'payee_label COLLATE NOCASE',observed_at:'observed_at'},
  ledgers: {description:'description COLLATE NOCASE',group_title:'group_title COLLATE NOCASE',debit_rwf:'debit_rwf',credit_rwf:'credit_rwf',entry_count:'entry_count',posted_at:'posted_at'},
};
CORE_SORTS.members=CORE_SORTS.users;
function operationalSearch(name,spec,search) {
  const predicates=[],bindings=[];
  let source=fold(search);
  const add=(predicate,...values)=>{predicates.push(predicate);bindings.push(...values);};
  source=source.replace(/\b(?:show|find|list)\s+(?:me\s+)?/g,'');
  if(name==='groups') source=source.replace(/\b(private|public)(?:\s+groups?)?\b/g,(_,v)=>{add('visibility=?',v==='public'?'public_approved':'private');return '';});
  if(name==='transactions') source=source.replace(/\b(unallocated|allocated|partial)(?:\s+(?:payments?|transactions?))?\b/g,(_,v)=>{add(v==='allocated'?'allocated_amount_rwf=amount_rwf':v==='partial'?'allocated_amount_rwf>0 AND allocated_amount_rwf<amount_rwf':'allocated_amount_rwf=0');return '';});
  if(name==='ledgers') source=source.replace(/\b(unbalanced|balanced)(?:\s+(?:journals?|ledgers?))?\b/g,(_,v)=>{add(v==='balanced'?'debit_rwf=credit_rwf':'debit_rwf!=credit_rwf');return '';});
  source=source.replace(/\b([a-z_]+):(?:"([^"]+)"|(\S+))/g,(_,field,phrase,word)=>{
    const value=phrase??word;
    if(field==='status') {if(!spec.statuses.includes(value)) invalid('Unsupported search status.');add('status=?',value);}
    else {
      const map={name:name==='groups'?'title':name==='payees'?'label':name==='ledgers'?'description':'payer_name',group:'group_title',momo:name==='payees'?'momo_number_or_code':'payee_momo_number_or_code',reference:'provider_reference'};
      const column=map[field];if(!column||!spec.search.includes(column))invalid('Unsupported search field.');
      add(`instr(${foldedSql(column)},?)>0`,value);
    }
    return '';
  });
  source=source.replace(/\b([a-z_]+)(?:\s+(?:groups?|payees?|journals?|ledgers?|transactions?|payments?))?\b/g,(whole,value)=>{
    if(spec.statuses.includes(value)){add('status=?',value);return '';}
    return whole;
  });
  const tokens=[...source.matchAll(/"([^"]+)"|(\S+)/g)].map(m=>m[1]??m[2]);
  if(tokens.length>16)invalid('Use at most 16 search terms.');
  if(tokens.length&&/^[+()\s.\-0-9]+$/.test(tokens.join(' ')))tokens.splice(0,tokens.length,tokens.join('').replace(/[^0-9]/g,''));
  for(const token of tokens){
    const columns=spec.search.map(column=>foldedSql(column));
    add(`(${columns.map(column=>`instr(${column},?)>0`).join(' OR ')})`,...columns.map(()=>token));
  }
  return {predicates,bindings};
}

async function authorizedBatch(env, user, statements) {
  // Authenticate again at the same transactional snapshot as the data. A
  // password reset/revoke between Worker session lookup and this batch must
  // return 401, not disclose rows under the stale pre-query identity.
  const [authorization, ...results] = await env.ADMIN_DB.batch([
    env.ADMIN_DB.prepare(`SELECT 1 AS authorized FROM admin_sessions s JOIN admin_users u ON u.id=s.user_id
      WHERE s.token_hash=? AND u.id=? AND u.status='active' AND u.role IN ('owner','admin','staff')
      AND s.auth_version=u.auth_version AND s.auth_version=? AND s.expires_at>unixepoch()`)
      .bind(user.token_hash, user.id, user.auth_version),
    ...statements,
  ]);
  if (authorization.results.length !== 1) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
  return results;
}

async function overview(env, user) {
  const [read] = await authorizedBatch(env, user, [env.ADMIN_DB.prepare(`WITH people AS (${SYSTEM_PEOPLE_QUERY}) SELECT
    (SELECT count(*) FROM people) AS users,
    (SELECT count(*) FROM people WHERE member_type='app') AS app_users,
    (SELECT count(*) FROM people WHERE member_type='direct') AS direct_users,
    (SELECT count(*) FROM admin_users WHERE role IN ('owner','admin')) AS admin_users,
    (SELECT count(*) FROM admin_users WHERE role='staff') AS staff_users,
    (SELECT count(*) FROM collect_groups WHERE country_code='RW') AS groups,
    (SELECT count(*) FROM collect_users u WHERE EXISTS(SELECT 1 FROM collect_memberships m WHERE m.user_id=u.id AND m.status='active')) AS active_members,
    (SELECT count(*) FROM collect_payees) AS payees,
    (SELECT count(*) FROM collect_payees WHERE status='active') AS active_payees,
    (SELECT count(*) FROM collect_transactions) AS transactions,
    (SELECT count(*) FROM collect_transactions t WHERE verification_status!='rejection_recorded' AND
      amount_rwf>COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a WHERE a.transaction_id=t.id),0)) AS unallocated_transactions,
    (SELECT count(*) FROM member_receipt_submissions)+(SELECT count(*) FROM collect_receipt_ingress) AS sms_receipts,
    (SELECT count(*) FROM member_receipt_submissions WHERE status='needs_review') AS receipts_needing_review,
    (SELECT count(*) FROM collect_journals WHERE status='draft') AS draft_journals,
    (SELECT count(*) FROM collect_journals WHERE status='posted') AS posted_journals,
    (SELECT CAST(COALESCE(sum(amount_rwf),0) AS TEXT) FROM collect_transactions WHERE verification_status='confirmation_recorded') AS total_collected_rwf,
    (SELECT CAST(COALESCE(sum(a.amount_rwf),0) AS TEXT) FROM collect_payment_allocations a JOIN collect_transactions t ON t.id=a.transaction_id WHERE t.verification_status='confirmation_recorded') AS total_allocated_rwf,
    (SELECT CAST(COALESCE(sum(t.amount_rwf-COALESCE((SELECT sum(a.amount_rwf) FROM collect_payment_allocations a WHERE a.transaction_id=t.id),0)),0) AS TEXT)
      FROM collect_transactions t WHERE t.verification_status!='rejection_recorded') AS total_unallocated_rwf,
    (SELECT CAST(COALESCE(sum(a.amount_rwf),0) AS TEXT) FROM collect_payment_allocations a JOIN collect_transactions t ON t.id=a.transaction_id
      JOIN collect_journals j ON j.allocation_id=a.id AND j.status='posted' WHERE t.verification_status='confirmation_recorded') AS total_posted_contributions_rwf`)]);
  const result = read.results[0];
  const names = { users: 'Users', groups: 'Groups', active_members: 'Active members', payees: 'Payees',
    transactions: 'Transactions', draft_journals: 'Draft journals', posted_journals: 'Posted journals',
    app_users: 'App users', direct_users: 'Direct users', admin_users: 'Admin users', staff_users: 'Staff users',
    active_payees: 'Active payees', unallocated_transactions: 'Unallocated transactions', sms_receipts: 'SMS receipts', receipts_needing_review: 'Receipts needing review' };
  const counts = Object.fromEntries(Object.keys(names).map(key => [key, integer(result[key])]));
  const amountNames = { total_collected_rwf: 'Total collected', total_allocated_rwf: 'Total allocated',
    total_unallocated_rwf: 'Total unallocated', total_posted_contributions_rwf: 'Posted contributions' };
  const amounts = Object.fromEntries(Object.keys(amountNames).map(key => {
    if (typeof result[key] !== 'string' || !/^(0|[1-9][0-9]*)$/.test(result[key])) fail(503, 'invalid_source_data', 'Workspace measurements are temporarily unavailable.');
    return [key, result[key]];
  }));
  return { country_code: 'RW', measured_at: new Date().toISOString(), counts, amounts,
    contribution_basis: 'confirmation_recorded_allocations', collected_basis: 'confirmation_recorded_transactions',
    reconciliations_available: true,
    metrics: [...Object.entries(names).map(([key, label]) => ({ key, label, value: String(counts[key]), status: 'measured' })),
      ...Object.entries(amountNames).map(([key, label]) => ({ key, label, value: amounts[key], status: 'measured' }))] };
}

export async function handleCoreRead(request, env, user) {
  // Worker supplies only its freshly resolved active account/session. This
  // helper also refuses missing/unknown roles rather than trusting the caller.
  if (!user || user.status !== 'active' || !['owner', 'admin', 'staff'].includes(user.role)) fail(401, 'unauthenticated', 'Sign in to continue.');
  const url = new URL(request.url);
  const name = url.pathname.slice('/api/admin/core/'.length);
  if (name !== 'overview' && !Object.hasOwn(lists, name)) fail(404, 'not_found', 'This workspace view does not exist.');
  if (request.method !== 'GET') fail(405, 'method_not_allowed', 'This workspace view is read-only.');
  const permission = name === 'overview' ? 'overview.read' : lists[name].permission;
  if (!user.permissions?.includes(permission)) fail(403, 'permission_required', 'This workspace view is not available for this account.');
  if (name === 'overview') { parameters(url, true); return overview(env, user); }
  const spec = lists[name]; const filter = parameters(url);
  if (filter.status && !spec.statuses.includes(filter.status)) invalid('This status is not supported for this view.');
  const predicates = []; const bindings = [];
  if (filter.status) { predicates.push('status=?'); bindings.push(filter.status); }
  let ranking = { score: '0', scoreBindings: [] };
  if (filter.search && spec.people) {
    ranking = peopleSearchSql(filter.search); predicates.push(...ranking.predicates); bindings.push(...ranking.bindings);
  } else if (filter.search) {
    const intent=operationalSearch(name,spec,filter.search);
    predicates.push(...intent.predicates);bindings.push(...intent.bindings);
  }
  const where = predicates.length ? ` WHERE ${predicates.join(' AND ')}` : '';
  const cte = `WITH records AS (${spec.query})`;
  const key=filter.sort.replace(/_(?:asc|desc)$/,''), direction=filter.sort.endsWith('_asc')?'ASC':'DESC';
  const registry={created_at:'created_at',status:'status',...CORE_SORTS[name]};
  const sort=Object.hasOwn(registry,key)?registry[key]:null;
  if(!sort)invalid('This sort is not supported for this view.');
  const order=`${key==='created_at'?'search_rank DESC,':''}(${sort}) IS NULL ASC,${sort} ${direction},created_at DESC,id ASC`;
  // Both reads share one D1 transaction snapshot. A separate count request
  // could disagree with this page during a concurrent operational write.
  const [count, page] = await authorizedBatch(env, user, [
    env.ADMIN_DB.prepare(`${cte} SELECT count(*) AS total FROM records${where}`).bind(...bindings),
    env.ADMIN_DB.prepare(`${cte} SELECT *,${ranking.score} AS search_rank FROM records${where} ORDER BY ${order} LIMIT ? OFFSET ?`).bind(...ranking.scoreBindings, ...bindings, filter.limit, filter.offset),
  ]);
  const total = integer(count.results[0].total);
  const rows = page.results.map(row => ({ id: row.id, ...spec.row(row), created_at: date(row.created_at),
    country_code: 'RW', currency_code: 'RWF' }));
  if (rows.length !== Math.max(0, Math.min(filter.limit, total - filter.offset))) fail(503, 'invalid_source_data', 'Workspace measurements are temporarily unavailable.');
  return { rows, total };
}
