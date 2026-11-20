// Snapshot primitive for the production read-only dump executor. No CLI entry
// point exists here. The managed connector has a fixed endpoint and CA.
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import pg from '../node_modules/pg/lib/index.js';
import {isManagedReconciliationPeer,managedReconciliationSsl} from '../current-pg-transfer/managed-target.mjs';
import {isSyntheticReconciliationSocket} from '../current-pg-transfer/reconcile.mjs';
const {Client}=pg;
export class SnapshotError extends Error{constructor(code){super(code);this.name='SnapshotError';this.code=code;}}
const fail=c=>{throw new SnapshotError(c);};
const HOST='db.rrlduytparvsjfmegalh.supabase.co',DB='postgres',USER='postgres';
const forbidden=/^(?:PG[A-Z0-9_]*|NODE_[A-Z0-9_]*|SSL_[A-Z0-9_]*|OPENSSL_[A-Z0-9_]*|LD_[A-Z0-9_]*|DYLD_[A-Z0-9_]*|(?:HTTP|HTTPS|ALL|NO)_PROXY)$/i;
const sha=s=>createHash('sha256').update(s,'utf8').digest('hex');
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function plain(o){return o&&typeof o==='object'&&!types.isProxy(o)&&Object.getPrototypeOf(o)===Object.prototype;}
export function cleanManagedEnvironment(env=process.env,execArgv=process.execArgv){return Array.isArray(execArgv)&&execArgv.length===0&&!Object.entries(env).some(([k,v])=>forbidden.test(k)&&v);}
// This is a conservative selected-schema preflight, not a dump-completeness
// proof. Call inside the exported snapshot, using the same role as pg_dump.
export async function checkDumpVisibility(c){
 const r=await c.query(`SELECT
  count(DISTINCT n.oid) FILTER (WHERE NOT pg_catalog.has_schema_privilege(n.oid,'USAGE'))::int AS inaccessible_schemas,
  count(c.oid) FILTER (WHERE c.relkind='f')::int AS foreign_tables,
  count(c.oid) FILTER (WHERE CASE WHEN c.relkind IN ('r','p','m') THEN NOT pg_catalog.has_table_privilege(c.oid,'SELECT') ELSE false END)::int AS inaccessible_tables,
  count(c.oid) FILTER (WHERE CASE WHEN c.relkind='S' THEN NOT pg_catalog.has_sequence_privilege(c.oid,'SELECT') ELSE false END)::int AS inaccessible_sequences,
  count(c.oid) FILTER (WHERE CASE WHEN c.relkind IN ('r','p') THEN pg_catalog.row_security_active(c.oid) ELSE false END)::int AS rls_active_tables
  FROM pg_catalog.pg_namespace n LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid
  WHERE n.nspname=ANY($1::text[])`,[['app','private','collect_sms','auth','storage','public','supabase_migrations']]);
 if(r.rowCount!==1||!['inaccessible_schemas','foreign_tables','inaccessible_tables','inaccessible_sequences','rls_active_tables']
  .every(k=>Number.isInteger(r.rows[0][k])&&r.rows[0][k]===0))fail('visibility_preflight_refused');
 return r.rows[0];
}
async function createSnapshot(c,expected){
 let started=false;
 try{
  await c.connect();if(expected.managed&&!isManagedReconciliationPeer(c.connectionParameters,c.connection.stream))fail('managed_peer_refused');
  await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');started=true;
  await c.query("SET LOCAL search_path=pg_catalog; SET LOCAL statement_timeout='15s'; SET LOCAL lock_timeout='5s'");
  const q=await c.query(`SELECT current_database() AS database,session_user AS session_user,current_user AS current_user,
   current_setting('server_version_num') AS version,current_setting('server_encoding') AS encoding,
   current_setting('transaction_isolation') AS isolation,current_setting('transaction_read_only') AS read_only,
   pg_backend_pid() AS backend_pid,clock_timestamp()::text AS observed_at,
   pg_export_snapshot() AS exported_snapshot,pg_current_snapshot()::text AS mvcc_snapshot`);
  const x=q.rows[0];if(q.rowCount!==1||x.database!==expected.database||x.session_user!==expected.user||x.current_user!==expected.user||
   !/^17[0-9]{4}$/.test(x.version)||x.encoding!=='UTF8'||x.isolation!=='repeatable read'||x.read_only!=='on'||
   !Number.isInteger(x.backend_pid)||x.backend_pid<1||!/^[0-9A-F]{8}-[0-9A-F]{8}-[1-9][0-9]*$/.test(x.exported_snapshot)||typeof x.mvcc_snapshot!=='string')fail('snapshot_identity_refused');
  const visibility=await checkDumpVisibility(c);
  const inventory=await c.query(`SELECT n.nspname AS schema,coalesce(c.relkind::text,'-') AS kind,count(c.oid)::int AS count
   FROM pg_catalog.pg_namespace n LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relkind IN ('r','p','v','m','S','f')
   WHERE n.nspname=ANY($1::text[])
   GROUP BY n.nspname,c.relkind ORDER BY n.nspname,c.relkind`,[['app','private','collect_sms','auth','storage','public','supabase_migrations']]);
  let clusterIdentifierSha256=null;
  await c.query('SAVEPOINT optional_cluster_id');
  try{const s=await c.query('SELECT system_identifier::text AS id FROM pg_catalog.pg_control_system()');if(s.rowCount===1&&/^[0-9]{1,20}$/.test(s.rows[0].id))clusterIdentifierSha256=sha(s.rows[0].id);}
  catch{await c.query('ROLLBACK TO SAVEPOINT optional_cluster_id');}
  await c.query('RELEASE SAVEPOINT optional_cluster_id');
  const metadata={database:x.database,session_user:x.session_user,current_user:x.current_user,server_major:17,encoding:x.encoding,
   observed_at:x.observed_at,backend_pid:x.backend_pid,snapshot_sha256:sha(x.exported_snapshot),mvcc_sha256:sha(x.mvcc_snapshot),
   cluster_identifier_sha256:clusterIdentifierSha256,visibility_preflight:visibility,inventory:inventory.rows};
  let ended=false;
  return {snapshotId:x.exported_snapshot,metadata,assertAlive:async()=>{
   if(ended)fail('snapshot_not_live');const r=await c.query(`SELECT pg_backend_pid() AS pid,current_setting('transaction_read_only') AS ro,
    current_setting('transaction_isolation') AS isolation`);if(r.rowCount!==1||r.rows[0].pid!==x.backend_pid||r.rows[0].ro!=='on'||r.rows[0].isolation!=='repeatable read')fail('snapshot_not_live');
  },close:async()=>{if(ended)return;ended=true;try{await c.query('ROLLBACK');}catch{}try{await c.end();}catch{try{c.connection.stream.destroy();}catch{}}}};
 }catch(e){if(started)try{await c.query('ROLLBACK');}catch{}try{await c.end();}catch{try{c.connection.stream.destroy();}catch{}}
  if(e instanceof SnapshotError)throw e;fail('snapshot_unavailable');}
}
// Do not invoke without the governed, independently reviewed production runner.
// Its caller supplies a private password; no caller-controlled endpoint, TLS
// object, connection string, proxy, stream or startup options are accepted.
export async function openPinnedManagedSnapshot(o){
 if(!plain(o)||!cleanManagedEnvironment())fail('managed_environment_refused');
 if(Reflect.ownKeys(o).length!==1||Reflect.ownKeys(o)[0]!=='password')fail('invalid_input');
 const password=option(o,'password');if(typeof password!=='string'||!password.length||Buffer.byteLength(password)>4096||/[\0\r\n]/.test(password))fail('invalid_input');
 const c=new Client({host:HOST,port:5432,database:DB,user:USER,password,ssl:managedReconciliationSsl(),options:'-c default_transaction_read_only=on',connectionTimeoutMillis:10000});c.on('error',()=>{});
 return createSnapshot(c,{database:DB,user:USER,managed:true});
}
// Synthetic cluster guard is an accidental-use check, not host attestation.
export async function openSyntheticSnapshot(o){
 if(!plain(o)||option(o,'mode')!=='synthetic')fail('synthetic_only');const host=option(o,'socket'),port=option(o,'port');
 if(!isSyntheticReconciliationSocket(host)||!Number.isInteger(port)||port<1024||port>65535)fail('synthetic_fixture_refused');
 const c=new Client({host,port,database:'collect_fixture_dump',user:'fixture_bootstrap',ssl:false,connectionTimeoutMillis:5000});c.on('error',()=>{});
 return createSnapshot(c,{database:'collect_fixture_dump',user:'fixture_bootstrap',managed:false});
}
