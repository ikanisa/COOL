// Bounded, read-only comparison of two exclusively owned pg clients.
// This is not an importer, an identity resolver, or production authorization.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {performance} from 'node:perf_hooks';
import pg from '../node_modules/pg/lib/index.js';
import {isManagedReconciliationPeer} from './managed-target.mjs';

const {Client} = pg;
const PROJECT = 'rrlduytparvsjfmegalh';
const FORMAT = 'collect.current-pg-reconciliation.v1';
const active = new WeakSet();
const HEX = /^[a-f0-9]{64}$/;
const NAME = /^[a-z_][a-z0-9_]{0,62}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SCHEMAS = new Set(['app', 'private', 'collect_sms', 'auth']);
// Fixture naming is an accidental-use guard, not attestation of a local host.
export function isSyntheticReconciliationSocket(host,platform=process.platform) {
  if(typeof host!=='string')return false;
  return platform==='darwin'?/^\/private\/tmp\/collect-pg-transfer-[A-Za-z0-9]+\/s$/.test(host):
    platform==='linux'?/^\/tmp\/collect-pg-transfer-[A-Za-z0-9]+\/s$/.test(host):false;
}
// These are PostgreSQL's format_type names, checked again against the actual
// catalogue before any selected data is read. Only built-in types are accepted.
const TYPES = /^(?:text|uuid|boolean|smallint|integer|bigint|bytea|jsonb|numeric(?:\([1-9][0-9]{0,3},-?(?:0|[1-9][0-9]{0,3})\))?|timestamp(?:\([0-6]\))? with time zone|character varying(?:\([1-9][0-9]{0,5}\))?)$/;
const TEXT_TYPE = /^(?:text|character varying(?:\([1-9][0-9]{0,5}\))?)$/;
// Do not inherit caller-global pg type parsers: all query results are text,
// except the fixed catalogue boolean and int4 fields. This preserves NULL and
// prevents an application parser from silently changing compared values.
const QUERY_TYPES = {getTypeParser(oid,format) {
  if (format !== 'text') fail('unexpected_result_format');
  if (oid === 16) return value => { if (value === 't') return true; if (value === 'f') return false; fail('invalid_cell'); };
  if (oid === 23) return value => { if (!/^-?\d{1,10}$/.test(value)) fail('invalid_cell'); return Number(value); };
  return value => value;
}};

export class ReconciliationError extends Error {
  constructor(code) { super(code); this.name = 'ReconciliationError'; this.code = code; }
}
const fail = code => { throw new ReconciliationError(code); };
const exact = (o, keys) => o && typeof o === 'object' && !Array.isArray(o) &&
  Object.keys(o).sort().join('\0') === [...keys].sort().join('\0');
const int = (n, min, max) => Number.isSafeInteger(n) && n >= min && n <= max;
const safeText = (s, max = 128) => typeof s === 'string' && Buffer.byteLength(s, 'utf8') <= max &&
  s.length > 0 && !/[\u0000-\u001f\u007f]/u.test(s) && !/[\ud800-\udfff]/u.test(s);
const ident = s => '"' + s.replaceAll('"', '""') + '"';
const canonical = value => {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number' && Number.isSafeInteger(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value && Object.getPrototypeOf(value) === Object.prototype)
    return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  fail('invalid_contract');
};

// The expected digest must come from independent review/custody, not this call.
export function contractDigest(contract) { return createHash('sha256').update(canonical(contract), 'utf8').digest('hex'); }
export const identityDigest = identity => contractDigest(identity);

function validateContract(c, pin) {
  if (!exact(c, ['format','source_set_sha256','source_identity_sha256','target_identity_sha256','limits','relations']) || c.format !== FORMAT ||
      !HEX.test(c.source_set_sha256 ?? '') || !HEX.test(c.source_identity_sha256 ?? '') ||
      !HEX.test(c.target_identity_sha256 ?? '') || !HEX.test(pin ?? '') || contractDigest(c) !== pin) fail('invalid_contract');
  const l = c.limits;
  if (!exact(l, ['rows_per_relation','bytes_per_cell','bytes_total','statement_timeout_ms','total_timeout_ms']) ||
      !int(l.rows_per_relation, 1, 10000) || !int(l.bytes_per_cell, 1, 4096) ||
      !int(l.bytes_total, 1, 16777216) || !int(l.statement_timeout_ms, 100, 30000) ||
      !int(l.total_timeout_ms, l.statement_timeout_ms, 120000) || !Array.isArray(c.relations) ||
      c.relations.length < 1 || c.relations.length > 32) fail('invalid_contract');
  const names = new Set();
  for (const r of c.relations) {
    if (!exact(r, ['schema','name','columns','constraints','key','unique_checks']) || !SCHEMAS.has(r.schema) ||
        !NAME.test(r.name ?? '') || !Array.isArray(r.columns) || r.columns.length < 1 || r.columns.length > 128 ||
        !Array.isArray(r.constraints) || r.constraints.length > 256 ||
        !Array.isArray(r.key) || r.key.length < 1 || r.key.length > 8 ||
        !Array.isArray(r.unique_checks) || r.unique_checks.length > 8) fail('invalid_contract');
    const rel = r.schema + '.' + r.name;
    if (names.has(rel)) fail('invalid_contract');
    names.add(rel);
    const cols = new Map();
    for (const a of r.columns) {
      if (!exact(a, ['name','type','nullable','compare','collation','default_sha256','identity','generated']) || !NAME.test(a.name ?? '') ||
          !safeText(a.type, 128) || typeof a.nullable !== 'boolean' || typeof a.compare !== 'boolean' ||
          !(a.default_sha256 === null || HEX.test(a.default_sha256 ?? '')) || !['','a','d'].includes(a.identity) ||
          !['','s'].includes(a.generated) ||
          (a.compare && !TYPES.test(a.type)) || cols.has(a.name) ||
          !(a.collation === null || (exact(a.collation, ['schema','name']) &&
              safeText(a.collation.schema, 63) && safeText(a.collation.name, 63)))) fail('invalid_contract');
      cols.set(a.name, a);
    }
    const constraintNames = new Set();
    for (const x of r.constraints) {
      if (!exact(x,['name','kind','definition_sha256','deferrable','initially_deferred','validated']) ||
          !NAME.test(x.name ?? '') || !['c','f','p','u','x'].includes(x.kind) ||
          !HEX.test(x.definition_sha256 ?? '') || typeof x.deferrable !== 'boolean' ||
          typeof x.initially_deferred !== 'boolean' || typeof x.validated !== 'boolean' ||
          (x.initially_deferred && !x.deferrable) || constraintNames.has(x.name)) fail('invalid_contract');
      constraintNames.add(x.name);
    }
    if (r.columns.filter(x => x.compare).length > 32 || new Set(r.key).size !== r.key.length ||
        r.key.some(k => !cols.get(k)?.compare || cols.get(k)?.type === 'jsonb')) fail('invalid_contract');
    const checks = new Set();
    for (const u of r.unique_checks) {
      if (!exact(u, ['column','classification','normalization']) || !cols.get(u.column)?.compare ||
          cols.get(u.column)?.type === 'jsonb' ||
          !['principal_email','principal_link'].includes(u.classification) || checks.has(u.classification) ||
          !['exact','ascii_lower_trim'].includes(u.normalization) ||
          (u.classification === 'principal_email' && u.normalization !== 'ascii_lower_trim') ||
          (u.normalization === 'ascii_lower_trim' && !/^(?:text|character varying)/.test(cols.get(u.column).type))) fail('invalid_contract');
      checks.add(u.classification);
    }
  }
}

function validateExpected(e, source) {
  if (!exact(e, ['transport','database','session_user','current_user','project_ref','baseline_manifest_sha256',
      'source_sha256','epoch','mode','operation_id','profile_sha256']) || !safeText(e.database,63) ||
      !safeText(e.session_user,63) || !safeText(e.current_user,63) || e.project_ref !== PROJECT ||
      !HEX.test(e.baseline_manifest_sha256 ?? '') || !HEX.test(e.source_sha256 ?? '') ||
      !/^[1-9][0-9]{0,15}$/.test(e.epoch ?? '') || !['open','quiescing','fenced'].includes(e.mode) ||
      !UUID.test(e.operation_id ?? '') || (source ? !HEX.test(e.profile_sha256 ?? '') : e.profile_sha256 !== null) ||
      !exact(e.transport, ['kind','host','port']) || typeof e.transport.host !== 'string' ||
      !int(e.transport.port, 1, 65535)) fail('invalid_identity');
}

// Does not open a connection. The hash must be supplied independently of the
// untrusted input stream; the identity hashes are themselves inside that pin.
export function validateReconciliationInputs({contract,sourceIdentity,targetIdentity,expectedContractSha256}) {
  validateContract(contract,expectedContractSha256);
  validateExpected(sourceIdentity,true); validateExpected(targetIdentity,false);
  if (identityDigest(sourceIdentity) !== contract.source_identity_sha256 || identityDigest(targetIdentity) !== contract.target_identity_sha256) fail('identity_binding_mismatch');
  if (sourceIdentity.transport.host === targetIdentity.transport.host &&
      sourceIdentity.transport.port === targetIdentity.transport.port && sourceIdentity.database === targetIdentity.database) fail('distinct_databases_required');
}

function validateClient(client, e, source) {
  if (!(client instanceof Client) || !client.connection?.once || !client.connection?.removeListener ||
      !client.connection?.stream?.destroy || active.has(client)) fail('invalid_client');
  const cp = client.connectionParameters, t = e.transport, stream = client.connection.stream;
  if (cp?.host !== t.host || Number(cp.port) !== t.port || cp.database !== e.database ||
      cp.options || cp.replication || cp.binary) fail('connection_mismatch');
  const local = t.host === '127.0.0.1' || (isAbsolute(t.host) && !t.host.includes('/../'));
  if (source && (t.kind !== 'local' || !local)) fail('connection_mismatch');
  if (!source && t.kind === 'managed') {
    if (!isManagedReconciliationPeer(cp,stream)) fail('connection_mismatch');
  } else if (!source && t.kind === 'synthetic') {
    if (!/^collect_fixture_[a-z0-9_]+$/.test(e.database) ||
        !isSyntheticReconciliationSocket(t.host)) fail('connection_mismatch');
  } else if (!source) fail('connection_mismatch');
}

function destroy(client) { try { client.connection.stream.destroy(); } catch {} }
async function bounded(client, sql, values, ms) {
  if (ms <= 0) fail('deadline_exceeded');
  let timer;
  try {
    return await Promise.race([
      Promise.resolve().then(() => client.query({text:sql,values,types:QUERY_TYPES})),
      new Promise((_, reject) => { timer = setTimeout(() => { destroy(client); reject(new ReconciliationError('deadline_exceeded')); }, ms); }),
    ]);
  } catch (err) {
    if (err instanceof ReconciliationError) throw err;
    if (err?.code === '57014' || err?.code === '55P03') fail('query_timed_out');
    fail('database_read_failed');
  } finally { clearTimeout(timer); }
}

async function idle(client, deadline) {
  let ready, timer;
  try {
    const status = new Promise((resolve, reject) => {
      ready = m => resolve(m?.status);
      client.connection.once('readyForQuery', ready);
      timer = setTimeout(() => reject(new Error()), Math.max(1, Math.min(5000, deadline - performance.now())));
    });
    const [r, s] = await Promise.all([bounded(client, 'SELECT 1 AS ok,pg_catalog.pg_backend_pid() AS pid', [], Math.min(5000, deadline - performance.now())), status]);
    if (s !== 'I' || r.rows?.length !== 1 || r.rows[0].ok !== 1 || !int(r.rows[0].pid,1,2147483647)) fail('connection_not_idle');
    return r.rows[0].pid;
  } catch (e) { if (e instanceof ReconciliationError) throw e; fail('connection_not_idle'); }
  finally { clearTimeout(timer); if (ready) client.connection.removeListener('readyForQuery', ready); }
}

async function identity(client, expected, pid, source, run) {
  const r = await run(client, `SELECT pg_catalog.current_database() AS database, session_user AS session_user,
    current_user AS current_user, pg_catalog.pg_backend_pid() AS pid,
    pg_catalog.current_setting('transaction_isolation') AS isolation,
    pg_catalog.current_setting('transaction_read_only') AS read_only,
    pg_catalog.current_setting('server_encoding') AS server_encoding,
    pg_catalog.current_setting('client_encoding') AS client_encoding,
    pg_catalog.current_setting('server_version_num') AS server_version_num,
    project_ref,baseline_manifest_sha256,source_sha256,epoch::text,mode,operation_id::text
    FROM private.collect_fence_control WHERE singleton IS TRUE`);
  const x = r.rows?.[0];
  if (r.rows?.length !== 1 || x.pid !== pid || x.isolation !== 'repeatable read' || x.read_only !== 'on' ||
      x.server_encoding !== 'UTF8' || x.client_encoding !== 'UTF8' || !/^17\d{4}$/.test(x.server_version_num) ||
      ['database','session_user','current_user','project_ref','baseline_manifest_sha256','source_sha256','epoch','mode','operation_id'].some(k => x[k] !== expected[k])) fail('identity_mismatch');
  if (source) {
    const p = await run(client, `SELECT profile_sha256,pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(profile_raw,'UTF8')),'hex') AS calculated
      FROM private.collect_deployment_identity WHERE singleton IS TRUE AND pg_catalog.octet_length(profile_raw)<=8192`);
    if (p.rows?.length !== 1 || p.rows[0].profile_sha256 !== expected.profile_sha256 || p.rows[0].calculated !== expected.profile_sha256) fail('identity_mismatch');
  }
}

async function catalogue(client, rel, run) {
  const r = await run(client, `SELECT c.relkind,pg_catalog.row_security_active(c.oid) AS rls_active,
    pg_catalog.has_table_privilege(c.oid,'SELECT') AS selectable,
    EXISTS(SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid=c.oid OR i.inhparent=c.oid) AS inherited,
    a.attname AS name,pg_catalog.format_type(a.atttypid,a.atttypmod) AS type,NOT a.attnotnull AS nullable,
    a.attidentity::text AS identity,a.attgenerated::text AS generated,
    CASE WHEN d.oid IS NULL THEN NULL WHEN pg_catalog.octet_length(pg_catalog.pg_get_expr(d.adbin,d.adrelid))<=16384
      THEN pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_expr(d.adbin,d.adrelid),'UTF8')),'hex') ELSE NULL END AS default_sha256,
    CASE WHEN d.oid IS NULL THEN true ELSE coalesce(pg_catalog.octet_length(pg_catalog.pg_get_expr(d.adbin,d.adrelid))<=16384,false) END AS expression_ok,
    cn.nspname AS collation_schema,co.collname AS collation_name,co.collisdeterministic AS collation_deterministic
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
    LEFT JOIN pg_catalog.pg_collation co ON co.oid=a.attcollation
    LEFT JOIN pg_catalog.pg_namespace cn ON cn.oid=co.collnamespace
    WHERE n.nspname=$1 AND c.relname=$2 ORDER BY a.attnum`, [rel.schema,rel.name]);
  if (r.rows?.length !== rel.columns.length || r.rows.some(x => x.relkind !== 'r' || x.rls_active || !x.selectable || x.inherited)) fail('catalogue_mismatch');
  const actual = new Map(r.rows.map(x => [x.name,x]));
  if (actual.size !== r.rows.length) fail('catalogue_mismatch');
  const equalityColumns = new Set([...rel.key,...rel.unique_checks.map(x => x.column)]);
  for (const c of rel.columns) {
    const a = actual.get(c.name);
    const collation = a?.collation_name === null ? null : {schema:a?.collation_schema,name:a?.collation_name};
    if (!a || a.type !== c.type || a.nullable !== c.nullable || !a.expression_ok || a.default_sha256 !== c.default_sha256 ||
        a.identity !== c.identity || a.generated !== c.generated || canonical(collation) !== canonical(c.collation)) fail('catalogue_mismatch');
    // JavaScript compares these values byte-for-byte. PostgreSQL nondeterministic
    // collations can consider different UTF-8 bytes equal, hiding key clashes.
    if (equalityColumns.has(c.name) && TEXT_TYPE.test(c.type) && a.collation_deterministic !== true)
      fail('unsupported_key_collation');
  }
  const constraints = await run(client, `SELECT x.conname::text AS name,x.contype::text AS kind,
    x.condeferrable AS deferrable,x.condeferred AS initially_deferred,x.convalidated AS validated,
    CASE WHEN pg_catalog.octet_length(pg_catalog.pg_get_constraintdef(x.oid))<=16384
      THEN pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_constraintdef(x.oid),'UTF8')),'hex') ELSE NULL END AS definition_sha256
    FROM pg_catalog.pg_constraint x JOIN pg_catalog.pg_class c ON c.oid=x.conrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=$1 AND c.relname=$2 LIMIT 257`, [rel.schema,rel.name]);
  if (constraints.rows?.length !== rel.constraints.length) fail('catalogue_mismatch');
  const expected = new Map(rel.constraints.map(x => [x.name,x]));
  const seen = new Set();
  for (const x of constraints.rows) {
    if (seen.has(x.name) || !expected.has(x.name) || canonical(x) !== canonical(expected.get(x.name))) fail('catalogue_mismatch');
    seen.add(x.name);
  }
}

async function extract(client, rel, limits, remaining, run) {
  const cols = rel.columns.filter(x => x.compare);
  const table = ident(rel.schema) + '.' + ident(rel.name);
  // Decimal arithmetic and epoch extraction are PostgreSQL operations, not JS
  // floating point. Their text encodings are independent of the session's
  // timezone/date style; bytea uses hex regardless of bytea_output.
  const rendered = c => {
    const col = ident(c.name);
    if (c.type === 'bytea') return `pg_catalog.encode(${col},'hex')`;
    if (c.type === 'numeric' || c.type.startsWith('numeric(')) return `pg_catalog.trim_scale(${col})::text`;
    if (/^timestamp(?:\([0-6]\))? with time zone$/.test(c.type)) return `extract(epoch FROM ${col})::text`;
    return `${col}::text`;
  };
  const lengths = cols.map((c,i) => c.type === 'bytea'
    ? `(pg_catalog.octet_length(${ident(c.name)})::bigint*2) AS b${i}`
    : `pg_catalog.octet_length(${rendered(c)})::bigint AS b${i}`);
  const sum = cols.map((_,i) => `coalesce(b${i},0)`).join('+');
  const max = cols.map((_,i) => `coalesce(b${i},0)`).join(',');
  const size = await run(client, `WITH s AS MATERIALIZED (SELECT ${lengths.join(',')} FROM ONLY ${table} LIMIT $1)
    SELECT pg_catalog.count(*)::text AS n,coalesce(pg_catalog.sum(${sum}),0)::text AS bytes,
    coalesce(pg_catalog.max(greatest(${max})),0)::text AS maxcell FROM s`, [limits.rows_per_relation + 1]);
  const {n,bytes,maxcell} = size.rows?.[0] ?? {};
  if (![n,bytes,maxcell].every(x => typeof x === 'string' && /^\d{1,15}$/.test(x))) fail('database_read_failed');
  const count = Number(n), byteCount = Number(bytes);
  if (count > limits.rows_per_relation || Number(maxcell) > limits.bytes_per_cell || byteCount > remaining) fail('input_limit_exceeded');
  const data = await run(client, `SELECT ${cols.map((c,i) => `${rendered(c)} AS c${i}`).join(',')}
    FROM ONLY ${table} LIMIT $1`, [limits.rows_per_relation + 1]);
  if (data.rows?.length !== count) fail('snapshot_inconsistent');
  return {rows:data.rows,cols,byteCount};
}

function normalized(value, u) {
  if (value === null) return null;
  if (typeof value !== 'string') fail('invalid_cell');
  if (u.normalization === 'exact') return value;
  // Deliberately narrow: unknown Unicode or whitespace semantics stop the run.
  const trimmed = value.replace(/^ +| +$/g, '');
  if (!/^[\x21-\x7e]+$/.test(trimmed) || !/^[^@]+@[^@]+$/.test(trimmed)) fail('unsupported_principal_email');
  return trimmed.toLowerCase();
}

function indexRows(extracted, rel) {
  const pos = new Map(extracted.cols.map((c,i) => [c.name,i]));
  const rows = new Map();
  const indexes = rel.unique_checks.map(() => new Map());
  const byKey = rel.unique_checks.map(() => new Map());
  const nulls = rel.unique_checks.map(() => 0);
  for (const row of extracted.rows) {
    const values = extracted.cols.map((c,i) => {
      const v = row['c'+i];
      if (v !== null && typeof v !== 'string') fail('invalid_cell');
      if (v === null && !c.nullable) fail('invalid_cell');
      return v;
    });
    const keyValues = rel.key.map(k => values[pos.get(k)]);
    if (keyValues.some(v => v === null)) fail('null_key');
    const key = JSON.stringify(keyValues);
    if (rows.has(key)) fail('duplicate_key');
    rows.set(key, JSON.stringify(values));
    rel.unique_checks.forEach((u,i) => {
      const v = normalized(values[pos.get(u.column)], u);
      byKey[i].set(key,v);
      if (v === null) { nulls[i]++; return; }
      if (indexes[i].has(v)) fail('duplicate_unique_value');
      indexes[i].set(v,key);
    });
  }
  return {rows,indexes,byKey,nulls};
}

function compare(a,b,rel) {
  const x = indexRows(a,rel), y = indexRows(b,rel);
  let equal = 0, changed = 0, sourceOnly = 0, targetOnly = 0;
  for (const [k,v] of x.rows) {
    if (!y.rows.has(k)) sourceOnly++;
    else if (y.rows.get(k) === v) equal++;
    else changed++;
  }
  for (const k of y.rows.keys()) if (!x.rows.has(k)) targetOnly++;
  const uniqueChecks = rel.unique_checks.map((u,i) => {
    let sameValueDifferentKey = 0, sameKeyDifferentValue = 0;
    for (const [value,key] of x.indexes[i]) if (y.indexes[i].has(value) && y.indexes[i].get(value) !== key) sameValueDifferentKey++;
    for (const [key,value] of x.byKey[i]) {
      const other = y.byKey[i].get(key);
      if (y.byKey[i].has(key) && value !== null && other !== null && value !== other) sameKeyDifferentValue++;
    }
    return {classification:u.classification,same_value_different_key:sameValueDifferentKey,
      same_key_different_value:sameKeyDifferentValue,
      source_nulls:x.nulls[i],target_nulls:y.nulls[i]};
  });
  return {schema:rel.schema,relation:rel.name,source_rows:x.rows.size,target_rows:y.rows.size,
    matching_keys_equal_selected:equal,matching_keys_changed_selected:changed,source_only_keys:sourceOnly,
    target_only_keys:targetOnly,unique_checks:uniqueChecks};
}

/** After admission, consumes and closes both connected, dedicated pg Clients. */
export async function reconcileCurrentPg({sourceClient,targetClient,sourceIdentity,targetIdentity,contract,expectedContractSha256}) {
  // Freeze the reviewed values used after asynchronous operations begin. Do not
  // retain references that a caller could change after the digest check.
  sourceIdentity = JSON.parse(canonical(sourceIdentity));
  targetIdentity = JSON.parse(canonical(targetIdentity));
  contract = JSON.parse(canonical(contract));
  validateReconciliationInputs({contract,sourceIdentity,targetIdentity,expectedContractSha256});
  if (sourceClient === targetClient) fail('distinct_databases_required');
  validateClient(sourceClient,sourceIdentity,true); validateClient(targetClient,targetIdentity,false);
  active.add(sourceClient); active.add(targetClient);
  const clients = [sourceClient,targetClient], deadline = performance.now() + contract.limits.total_timeout_ms;
  const run = (client,sql,values=[]) => bounded(client,sql,values,Math.min(contract.limits.statement_timeout_ms + 1000,deadline-performance.now()));
  try {
    const pids = [];
    for (const client of clients) pids.push(await idle(client,deadline));
    for (const [i,client] of clients.entries()) {
      const begin = await run(client,'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      if (begin.command !== 'BEGIN') fail('transaction_failed');
      await run(client,`SET LOCAL statement_timeout = '${contract.limits.statement_timeout_ms}ms'`);
      await run(client,"SET LOCAL lock_timeout = '1000ms'");
      await run(client,"SET LOCAL idle_in_transaction_session_timeout = '35s'");
      await run(client,'SET LOCAL search_path = pg_catalog');
      await run(client,'SET LOCAL row_security = off');
      // Lock the complete declared set before any SELECT establishes this
      // transaction's snapshot. A catalogue read after an earlier snapshot
      // can otherwise miss DDL committed before a later table is locked.
      const lockSet = [...contract.relations]
        .sort((a,b) => { const x = a.schema + '.' + a.name, y = b.schema + '.' + b.name; return x < y ? -1 : x > y ? 1 : 0; })
        .map(r => `ONLY ${ident(r.schema)}.${ident(r.name)}`).join(',');
      await run(client,`LOCK TABLE ${lockSet} IN ACCESS SHARE MODE`);
      await identity(client,i ? targetIdentity : sourceIdentity,pids[i],i === 0,run);
    }
    let remaining = contract.limits.bytes_total;
    const relations = [];
    for (const rel of contract.relations) {
      for (const client of clients) await catalogue(client,rel,run);
      const a = await extract(sourceClient,rel,contract.limits,remaining,run); remaining -= a.byteCount;
      const b = await extract(targetClient,rel,contract.limits,remaining,run); remaining -= b.byteCount;
      relations.push(compare(a,b,rel));
    }
    for (const [i,client] of clients.entries()) {
      const check = await run(client,'SELECT pg_catalog.pg_backend_pid() AS pid');
      if (check.rows?.length !== 1 || check.rows[0].pid !== pids[i]) fail('backend_changed');
      const r = await run(client,'ROLLBACK');
      if (r.command !== 'ROLLBACK') fail('transaction_failed');
    }
    return {format:FORMAT,contract_sha256:expectedContractSha256,source_set_sha256:contract.source_set_sha256,
      target_transport:targetIdentity.transport.kind,independent_snapshots:true,quiescence_proven:false,
      identities_resolved:false,write_authorized:false,selected_columns_only:true,relations};
  } catch (e) {
    if (e instanceof ReconciliationError) throw e;
    fail('reconciliation_failed');
  } finally {
    for (const client of clients) { destroy(client); active.delete(client); }
    // The TCP/Unix socket is already destroyed; errors and server text are never logged.
    for (const client of clients) { try { void client.end().catch(() => {}); } catch {} }
  }
}
