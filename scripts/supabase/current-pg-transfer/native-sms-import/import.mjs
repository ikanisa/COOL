// Disposable single-database PostgreSQL fixture only. No managed or real-data
// executor is implemented here; see README.md before integrating this code.
import {createHash,createHmac,timingSafeEqual} from 'node:crypto';
import {types} from 'node:util';

export class NativeSmsImportError extends Error{constructor(code){super(code);this.name='NativeSmsImportError';this.code=code;}}
const fail=code=>{throw new NativeSmsImportError(code);};
const HASH=/^[0-9a-f]{64}$/,UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ID=/^[A-Za-z0-9_-]{1,80}$/;
const REQUEST_KEYS=['version','operation_id','collection_id','source_owner','target_owner','source_auth','target_auth','source_epoch','target_epoch'];
const PLAN_KEYS=[...REQUEST_KEYS,'context_hmac','identity_hmac','post_hmac','sms_count'];
const canonical=x=>Array.isArray(x)?'['+x.map(canonical).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}':JSON.stringify(x);
export const nativeSmsPlanDigest=serialized=>createHash('sha256').update(serialized).digest('hex');
const mac=(key,domain,value)=>createHmac('sha256',key).update('collect-synthetic-native-sms-import-v1\0').update(domain).update('\0').update(value).digest('hex');
const same=(a,b)=>HASH.test(a??'')&&HASH.test(b??'')&&timingSafeEqual(Buffer.from(a,'hex'),Buffer.from(b,'hex'));
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function plain(o){return o&&typeof o==='object'&&!types.isProxy(o)&&Object.getPrototypeOf(o)===Object.prototype;}
const typedArrayPrototype=Object.getPrototypeOf(Uint8Array.prototype);
const typedBuffer=Object.getOwnPropertyDescriptor(typedArrayPrototype,'buffer').get;
const typedLength=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteLength').get;
const typedOffset=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteOffset').get;
const resizableBuffer=Object.getOwnPropertyDescriptor(ArrayBuffer.prototype,'resizable')?.get;
function copyKey(x){
 if(types.isProxy(x)||!Buffer.isBuffer(x)||Object.getPrototypeOf(x)!==Buffer.prototype)fail('invalid_input');
 try{const buffer=typedBuffer.call(x),length=typedLength.call(x),offset=typedOffset.call(x);
  if(types.isSharedArrayBuffer(buffer)||(resizableBuffer&&resizableBuffer.call(buffer))||length!==32)fail('invalid_input');
  const copy=Buffer.alloc(32);Uint8Array.prototype.set.call(copy,new Uint8Array(buffer,offset,length));return copy;}
 catch(e){if(e instanceof NativeSmsImportError)throw e;fail('invalid_input');}
}
function input(o,{plan=false}={}){
 if(!plain(o))fail('invalid_input');const mode=option(o,'mode');if(mode!=='synthetic')fail('managed_execution_closed');
 const serialized=option(o,plan?'planJson':'requestJson'),connect=option(o,'connect'),key=option(o,'key');
 if(typeof serialized!=='string'||Buffer.byteLength(serialized)>16384||typeof connect!=='function')fail('invalid_input');
 let value;try{value=JSON.parse(serialized);}catch{fail('invalid_input');}
 const expected=plan?PLAN_KEYS:REQUEST_KEYS;
 if(!plain(value)||Object.keys(value).sort().join('\0')!==[...expected].sort().join('\0')||canonical(value)!==serialized||
  value.version!=='collect.synthetic-native-sms-import.v1'||!UUID.test(value.operation_id??'')||
  ![value.source_auth,value.target_auth].every(x=>UUID.test(x??''))||value.source_auth===value.target_auth||
  ![value.collection_id,value.source_owner,value.target_owner].every(x=>ID.test(x??''))||value.source_owner===value.target_owner||
  ![value.source_epoch,value.target_epoch].every(x=>typeof x==='string'&&/^[1-9][0-9]{0,12}$/.test(x)))fail('invalid_input');
 if(plan){const expectedDigest=option(o,'expectedPlanSha256');if(!HASH.test(expectedDigest??'')||!same(nativeSmsPlanDigest(serialized),expectedDigest)||
  ![value.context_hmac,value.identity_hmac,value.post_hmac].every(x=>HASH.test(x??''))||
  !Number.isInteger(value.sms_count)||value.sms_count<1||value.sms_count>64)fail('invalid_input');}
 return {request:Object.freeze(value),serialized,connect,key:copyKey(key)};
}
import {FINANCIAL_CATALOG_SQL} from '../financial-import/import.mjs';
// Tables are closed to this synthetic fixture: one collection and no unrelated
// SMS graph on either side. Proof rows only attest to fixture behavior.
const UP=['sms_receipts','momo_parse_attempts','momo_transactions','momo_transaction_sources'];
const PRIV=['origins','jobs','scopes','native_lineage'];
const READ=[...UP.map(n=>'src.'+n),...PRIV.map(n=>'src.'+n),
 'src.users','app.users','src.auth_users','auth.users','src.auth_links','private.auth_links',
 'src.collections','app.collections','src.object_proofs','private.object_proofs',
 'private.fixture_native_dependencies','private.fixture_fences','private.fixture_admissions'];
const WRITE=[...UP.map(n=>'app.'+n),...PRIV.map(n=>'private.'+n),'private.fixture_native_receipts'];
export const NATIVE_FIXTURE_TABLES=Object.freeze([...READ,...WRITE]);
export const NATIVE_RECONCILE_TABLES=Object.freeze(['app.users','auth.users','private.auth_links',...WRITE]);
const RECONCILE=NATIVE_RECONCILE_TABLES;
const EXPECTED_CATALOG='45cf01453223af34873bb6d0a0e11d699197da47b9519a2baa35c91ac97ca228';
const EXPECTED_RECONCILE_CATALOG='da829d544c323238102d046c898e919f696c726c4fc9d690532a567236296b64';
const JSON_HELPER='6ceaad43daef880f979be7d78a07b64af581dc8abc5fcffc217fb12eee8c66aa';
const quote=s=>"'"+s.replaceAll("'","''")+"'";
const contextSql='SELECT jsonb_build_object('+READ.map(n=>quote(n)+",(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM ONLY "+n+' t)').join(',')+")::text AS value";
const boundsSql=tables=>'SELECT COALESCE(bool_or(n>256 OR largest>32768 OR total>2000000),false) OR sum(total)>2000000 AS exceeded FROM ('+tables.map(n=>
 "SELECT count(*) AS n,COALESCE(max(octet_length(to_jsonb(t)::text)),0) AS largest,COALESCE(sum(octet_length(to_jsonb(t)::text)),0) AS total FROM ONLY "+n+' t').join(' UNION ALL ')+') q';
const identitySql=`SELECT jsonb_build_object(
 'user',(SELECT to_jsonb(t) FROM ONLY app.users t WHERE id=$1),
 'auth',(SELECT to_jsonb(t) FROM ONLY auth.users t WHERE id=$2::uuid),
 'link',(SELECT to_jsonb(t) FROM ONLY private.auth_links t WHERE auth_id=$2::uuid AND user_id=$1))::text AS value`;
function graphSql(projected){
 const tables=[...UP,...PRIV];
 return 'SELECT jsonb_build_object('+tables.map(n=>{
  const schema=projected?'src':UP.includes(n)?'app':'private';
  let row='to_jsonb(t)';
  if(projected&&n==='sms_receipts')row+="||jsonb_build_object('owner_user_id',$1::text)";
  if(projected&&(n==='origins'||n==='native_lineage'))row+="||jsonb_build_object('principal_user_id',$1::text)";
  return quote(n)+`,(SELECT COALESCE(jsonb_agg(${row} ORDER BY t.${n==='momo_transaction_sources'?'transaction_id':UP.includes(n)?'id':'source_id'}),'[]'::jsonb) FROM ONLY ${schema}.${n} t)`;
 }).join(',')+')::text AS value';
}
async function fixture(c){
 const q=await c.query(`SELECT current_database() db,current_setting('cluster_name') cluster,session_user login,current_user role,
  inet_server_addr() IS NULL socket,current_setting('server_version_num')::int/10000 major,current_setting('session_replication_role') replication,
  (SELECT rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname=current_user) privileged`);
 const x=q.rows[0];if(q.rowCount!==1||x.db!=='collect_financial_import_fixture'||x.cluster!=='collect_financial_import_fixture'||x.login!=='fixture_operator'||
  x.role!=='fixture_operator'||!x.socket||x.major!==17||x.replication!=='origin'||x.privileged!==false)fail('fixture_identity_rejected');
}
async function lock(c,{write=false}={}){
 await c.query("SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='15s'");
 await c.query('LOCK TABLE '+READ.join(',')+' IN SHARE MODE');
 await c.query('LOCK TABLE '+WRITE.join(',')+' IN '+(write?'SHARE ROW EXCLUSIVE':'SHARE')+' MODE');
}
async function visibleTables(c,tables){
 const q=await c.query(`WITH required(name) AS (SELECT unnest($1::text[])),r AS (SELECT name,to_regclass(name) oid FROM required)
  SELECT EXISTS(SELECT 1 FROM r LEFT JOIN pg_class c ON c.oid=r.oid WHERE r.oid IS NULL OR c.relkind<>'r'
   OR pg_get_userbyid(c.relowner) IS DISTINCT FROM 'fixture_bootstrap' OR c.relrowsecurity OR c.relforcerowsecurity
   OR NOT coalesce(has_table_privilege(current_user,r.oid,'SELECT'),false) OR coalesce(row_security_active(r.oid),true)
   OR EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid)) AS bad`,[tables]);
 if(q.rows[0]?.bad!==false)fail('fixture_catalog_refused');
}
async function guard(c,{reconcile=false}={}){
 const tables=reconcile?RECONCILE:NATIVE_FIXTURE_TABLES;
 await visibleTables(c,tables);
 const q=await c.query(FINANCIAL_CATALOG_SQL,[tables]);
 if(q.rows[0]?.value!==(reconcile?EXPECTED_RECONCILE_CATALOG:EXPECTED_CATALOG))fail('fixture_schema_changed');
 const b=await c.query(boundsSql(tables));if(b.rows[0]?.exceeded!==false)fail('fixture_bounds_exceeded');
 if(!reconcile){const h=await c.query(`SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=$1
  AND pg_get_userbyid(p.proowner)='fixture_bootstrap' AND p.prokind='f' AND p.provolatile='i'
  AND p.proisstrict AND NOT p.prosecdef AND p.proconfig IS NULL AND l.lanname='plpgsql' AS ok
  FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid='app.json_valid(text)'::regprocedure`,[JSON_HELPER]);
  if(h.rowCount!==1||h.rows[0]?.ok!==true)fail('fixture_guard_changed');}
}
async function value(c,sql,params=[]){const q=await c.query(sql,params);if(q.rowCount!==1||typeof q.rows[0].value!=='string'||Buffer.byteLength(q.rows[0].value)>2000000)fail('snapshot_unavailable');return q.rows[0].value;}
async function fenceAndIdentity(c,p){
 const q=await c.query(`SELECT (SELECT count(*)=2 AND bool_and(mode='fenced') FROM private.fixture_fences) AND
  EXISTS(SELECT 1 FROM private.fixture_fences WHERE side='source' AND epoch=$1::bigint) AND
  EXISTS(SELECT 1 FROM private.fixture_fences WHERE side='target' AND epoch=$2::bigint) AND
  NOT EXISTS(SELECT 1 FROM private.fixture_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0) AND
  EXISTS(SELECT 1 FROM src.users u JOIN src.auth_links l ON l.user_id=u.id JOIN src.auth_users a ON a.id=l.auth_id
   WHERE u.id=$3 AND u.active AND a.id=$4::uuid AND a.active) AND
  EXISTS(SELECT 1 FROM app.users u JOIN private.auth_links l ON l.user_id=u.id JOIN auth.users a ON a.id=l.auth_id
   WHERE u.id=$5 AND u.active AND a.id=$6::uuid AND a.active) AND
  EXISTS(SELECT 1 FROM src.collections WHERE id=$7 AND creator_user_id=$3) AND
  EXISTS(SELECT 1 FROM app.collections WHERE id=$7 AND creator_user_id=$5) AS ok`,
 [p.source_epoch,p.target_epoch,p.source_owner,p.source_auth,p.target_owner,p.target_auth,p.collection_id]);
 if(q.rows[0]?.ok!==true)fail('identity_or_fence_changed');
}
const GRAPH=`WITH linked AS (
 SELECT r.id,r.owner_user_id,r.originating_session_id,r.receiver_hash,r.body_sha256,r.object_key,r.object_sha256,
 a.id attempt_id,a.raw_sms_id,a.source_body_sha256,a.outcome attempt_outcome,
 x.transaction_id,x.parse_attempt_id,x.relation source_relation,t.parse_attempt_id tx_attempt,t.receiving_account_id,
 t.event_kind tx_event,t.currency tx_currency,t.amount_minor tx_amount,t.mode tx_mode,t.has_conflict,t.allocation_state,
 o.collection_id origin_collection,o.principal_user_id origin_owner,o.body_sha256 origin_body,o.object_sha256 origin_object,
 j.source_id job_id,j.transaction_id job_tx,j.collection_id job_collection,j.source_fingerprint,j.state,j.posting_facts,
 sc.source_id scope_id,sc.transaction_id scope_tx,sc.collection_id scope_collection,sc.receiving_account_id scope_account,
 to_jsonb(n) lineage,to_jsonb(d) dependency,to_jsonb(sp) source_proof,to_jsonb(tp) target_proof
 FROM ONLY src.sms_receipts r
 LEFT JOIN ONLY src.momo_parse_attempts a ON a.raw_sms_id=r.id
 LEFT JOIN ONLY src.momo_transaction_sources x ON x.raw_sms_id=r.id
 LEFT JOIN ONLY src.momo_transactions t ON t.id=x.transaction_id
 LEFT JOIN ONLY src.origins o ON o.source_id=r.id
 LEFT JOIN ONLY src.jobs j ON j.source_id=r.id
 LEFT JOIN ONLY src.scopes sc ON sc.source_id=r.id
 LEFT JOIN ONLY src.native_lineage n ON n.source_id=r.id
 LEFT JOIN ONLY private.fixture_native_dependencies d ON d.source_id=r.id
 LEFT JOIN ONLY src.object_proofs sp ON sp.object_key=r.object_key
 LEFT JOIN ONLY private.object_proofs tp ON tp.object_key=r.object_key
 ) SELECT (SELECT count(*)::int FROM ONLY src.sms_receipts) n,(SELECT count(*)::int FROM linked) joined,
 (SELECT count(DISTINCT transaction_id)::int FROM linked) tx_count,
 (SELECT count(*)::int FROM linked WHERE
  owner_user_id IS DISTINCT FROM $2 OR originating_session_id IS NOT NULL OR receiver_hash IS NOT NULL OR
  id !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' OR transaction_id IS DISTINCT FROM id OR
  body_sha256 !~ '^[a-f0-9]{64}$' OR object_sha256 !~ '^[a-f0-9]{64}$' OR object_key IS DISTINCT FROM 'sms/'||id OR
  attempt_id IS NULL OR attempt_id IS DISTINCT FROM parse_attempt_id OR attempt_id IS DISTINCT FROM tx_attempt OR
  attempt_id !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' OR
  raw_sms_id IS DISTINCT FROM id OR source_body_sha256 IS DISTINCT FROM body_sha256 OR
  attempt_outcome IS DISTINCT FROM 'accepted' OR source_relation IS DISTINCT FROM 'accepted' OR
  origin_collection IS DISTINCT FROM $1 OR origin_owner IS DISTINCT FROM $2 OR origin_body IS DISTINCT FROM body_sha256 OR origin_object IS DISTINCT FROM object_sha256 OR
  job_id IS NULL OR job_tx IS DISTINCT FROM transaction_id OR job_collection IS DISTINCT FROM $1 OR
  source_fingerprint !~ '^[a-f0-9]{64}$' OR state IS DISTINCT FROM 'completed' OR
  tx_event IS DISTINCT FROM 'incoming_receipt' OR tx_currency IS DISTINCT FROM 'RWF' OR tx_amount IS NULL OR tx_amount<=0 OR
  has_conflict IS DISTINCT FROM 0 OR allocation_state IS DISTINCT FROM 'linked' OR
  jsonb_typeof(posting_facts) IS DISTINCT FROM 'object' OR
  (posting_facts ?& ARRAY['event_kind','payment_outcome','currency','amount_minor','source_mode','wallet_balance_after_minor']) IS DISTINCT FROM true OR
  posting_facts->>'event_kind' IS DISTINCT FROM tx_event OR posting_facts->>'payment_outcome' IS DISTINCT FROM 'successful' OR
  posting_facts->>'currency' IS DISTINCT FROM tx_currency OR jsonb_typeof(posting_facts->'amount_minor') IS DISTINCT FROM 'number' OR
  posting_facts->>'amount_minor' !~ '^[1-9][0-9]{0,15}$' OR posting_facts->'amount_minor' IS DISTINCT FROM to_jsonb(tx_amount) OR
  posting_facts->>'source_mode' IS DISTINCT FROM (CASE WHEN tx_mode='live' THEN 'live' ELSE 'catch_up' END) OR
  jsonb_typeof(posting_facts->'wallet_balance_after_minor') IS DISTINCT FROM 'number' OR NOT COALESCE(CASE
   WHEN posting_facts->>'wallet_balance_after_minor' ~ '^(0|[1-9][0-9]{0,15})$'
   THEN (posting_facts->>'wallet_balance_after_minor')::numeric<=9007199254740991 ELSE false END,false) OR
  scope_id IS NULL OR scope_tx IS DISTINCT FROM transaction_id OR scope_collection IS DISTINCT FROM $1 OR scope_account IS DISTINCT FROM receiving_account_id OR
  lineage IS NULL OR lineage->>'principal_user_id' IS DISTINCT FROM $2 OR lineage->>'phase' IS DISTINCT FROM 'finished' OR
  lineage->>'attempt_id' IS DISTINCT FROM attempt_id OR lineage->>'relation' IS DISTINCT FROM 'accepted' OR lineage->>'payment_outcome' IS DISTINCT FROM 'successful' OR
  (lineage->>'grant_version')::bigint<1 OR lineage->>'observation_fingerprint' IS DISTINCT FROM source_fingerprint OR
  lineage->>'profile_sha256' !~ '^[a-f0-9]{64}$' OR lineage->>'facts_sha256' !~ '^[a-f0-9]{64}$' OR
  NOT ((lineage->>'admission_kind'='jobs' AND lineage->>'admitting_session_id' IS NULL) OR (lineage->>'admission_kind'='native_actor' AND lineage->>'admitting_session_id' IS NOT NULL)) OR
  lineage->>'lease_token' IS NOT NULL OR lineage->>'lease_until' IS NOT NULL OR lineage->>'retry_lease' IS NOT NULL OR
  lineage->>'observation_request_settled' IS DISTINCT FROM 'true' OR lineage->>'storage_intent_settled' IS DISTINCT FROM 'true' OR
  lineage->>'upload_unresolved' IS DISTINCT FROM 'false' OR lineage->>'delete_tombstone' IS DISTINCT FROM 'false' OR
  dependency IS NULL OR dependency->>'collection_id' IS DISTINCT FROM $1 OR dependency->>'source_owner' IS DISTINCT FROM $2 OR dependency->>'target_owner' IS DISTINCT FROM $3 OR
  dependency->>'account_id' IS DISTINCT FROM lineage->>'account_id' OR dependency->>'installation_id' IS DISTINCT FROM lineage->>'installation_id' OR
  dependency->>'grant_id' IS DISTINCT FROM lineage->>'grant_id' OR dependency->>'grant_version' IS DISTINCT FROM lineage->>'grant_version' OR
  dependency->>'capture_session_id' IS DISTINCT FROM lineage->>'capture_session_id' OR dependency->>'admitting_session_id' IS DISTINCT FROM lineage->>'admitting_session_id' OR
  dependency->>'request_id' IS DISTINCT FROM lineage->>'request_id' OR dependency->>'account_inert' IS DISTINCT FROM 'true' OR
  dependency->>'grant_inert' IS DISTINCT FROM 'true' OR dependency->>'sessions_revoked' IS DISTINCT FROM 'true' OR
  dependency->>'mapping_reviewed' IS DISTINCT FROM 'true' OR dependency->>'runtime_replay_disabled' IS DISTINCT FROM 'true' OR dependency->>'evidence_sha256' !~ '^[a-f0-9]{64}$' OR
  source_proof IS NULL OR source_proof->>'owner_id' IS DISTINCT FROM $2 OR source_proof->>'entity_id' IS DISTINCT FROM id OR
  source_proof->>'purpose' IS DISTINCT FROM 'sms_receipt' OR source_proof->>'plaintext_sha256' IS DISTINCT FROM object_sha256 OR
  source_proof->>'ciphertext_sha256' !~ '^[a-f0-9]{64}$' OR source_proof->>'aad' IS DISTINCT FROM ('sms:'||id||':'||object_sha256) OR
  source_proof->>'verified' IS DISTINCT FROM 'true' OR target_proof IS DISTINCT FROM (source_proof||jsonb_build_object('owner_id',$3::text))
 ) bad,`+UP.slice(1).map(n=>`(SELECT count(*)::int FROM ONLY src.${n}) AS ${n}`).join(',')+','+PRIV.map(n=>`(SELECT count(*)::int FROM ONLY src.${n}) AS ${n}`).join(',');
async function graphValid(c,p){
 const {rows:[r]}=await c.query(GRAPH,[p.collection_id,p.source_owner,p.target_owner]);
 if(!r||r.n<1||r.n>64||r.bad!==0||[r.joined,r.tx_count,...UP.slice(1).map(n=>r[n]),...PRIV.map(n=>r[n])].some(n=>n!==r.n))fail('native_graph_refused');
 return r.n;
}
async function context(c,key,p){
 await fixture(c);await guard(c);await fenceAndIdentity(c,p);const count=await graphValid(c,p);
 return {count,context:mac(key,'context',await value(c,contextSql)),identity:mac(key,'identity',await value(c,identitySql,[p.target_owner,p.target_auth])),
  post:mac(key,'post',await value(c,graphSql(true),[p.target_owner]))};
}
async function emptyTarget(c){const sql='SELECT '+WRITE.map(n=>`(SELECT count(*) FROM ONLY ${n})`).join('+')+' AS n';const {rows:[r]}=await c.query(sql);if(Number(r.n)!==0)fail('target_native_conflict');}
async function receipt(c,p){const q=await c.query('SELECT operation_id::text,collection_id,plan_sha256,source_hmac,post_hmac,source_owner,target_owner,source_auth::text,target_auth::text,sms_count FROM private.fixture_native_receipts WHERE operation_id=$1::uuid',[p.operation_id]);return q.rows[0];}
async function verifyReceipt(c,key,p,digest,r){
 if(!r||r.collection_id!==p.collection_id||r.plan_sha256!==digest||r.source_hmac!==p.context_hmac||r.post_hmac!==p.post_hmac||r.source_owner!==p.source_owner||r.target_owner!==p.target_owner||r.source_auth!==p.source_auth||r.target_auth!==p.target_auth||r.sms_count!==p.sms_count)fail('receipt_mismatch');
 if(!same(mac(key,'identity',await value(c,identitySql,[p.target_owner,p.target_auth])),p.identity_hmac))fail('identity_changed');
 if(!same(mac(key,'post',await value(c,graphSql(false))),p.post_hmac))fail('postimage_changed');
}
const INSERTS=[
 `INSERT INTO app.sms_receipts SELECT (jsonb_populate_record(NULL::app.sms_receipts,to_jsonb(s)||jsonb_build_object('owner_user_id',$1::text))).* FROM ONLY src.sms_receipts s ORDER BY s.id`,
 ...UP.slice(1).map(n=>`INSERT INTO app.${n} SELECT s.* FROM ONLY src.${n} s`),
 `INSERT INTO private.origins SELECT (jsonb_populate_record(NULL::private.origins,to_jsonb(s)||jsonb_build_object('principal_user_id',$1::text))).* FROM ONLY src.origins s`,
 ...['jobs','scopes'].map(n=>`INSERT INTO private.${n} SELECT s.* FROM ONLY src.${n} s`),
 `INSERT INTO private.native_lineage SELECT (jsonb_populate_record(NULL::private.native_lineage,to_jsonb(s)||jsonb_build_object('principal_user_id',$1::text))).* FROM ONLY src.native_lineage s`];
async function connectAndStart(opts,{write=false,readonly=false}={}){
 const c=await opts.connect();try{await fixture(c);await c.query(readonly?'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY':'BEGIN');
  if(readonly){await c.query("SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='15s'");await c.query('LOCK TABLE '+RECONCILE.join(',')+' IN ACCESS SHARE MODE');}
  else await lock(c,{write});return c;}
 catch(e){try{await c.end();}catch{}if(readonly&&e?.code==='42501')fail('fixture_catalog_refused');throw e;}
}
export async function captureSyntheticNativeSmsPlan(options){
 const opts=input(options);let c,started=false;
 try{c=await connectAndStart(opts);started=true;const p=opts.request;const result=await context(c,opts.key,p);await emptyTarget(c);
  const plan={...p,context_hmac:result.context,identity_hmac:result.identity,post_hmac:result.post,sms_count:result.count};
  const planJson=canonical(plan);await c.query('ROLLBACK');started=false;return {planJson,expectedPlanSha256:nativeSmsPlanDigest(planJson),writeAuthorized:false};
 }catch(e){if(c&&started)try{await c.query('ROLLBACK');}catch{}if(e instanceof NativeSmsImportError)throw e;fail('fixture_capture_failed');}
 finally{if(c)try{await c.end();}catch{}opts.key.fill(0);}
}
export async function importSyntheticNativeSmsGraph(options){
 const opts=input(options,{plan:true});let c,started=false,commitAttempted=false;
 try{c=await connectAndStart(opts,{write:true});started=true;const p=opts.request,digest=nativeSmsPlanDigest(opts.serialized),observed=await context(c,opts.key,p);
  if(observed.count!==p.sms_count||!same(observed.context,p.context_hmac)||!same(observed.identity,p.identity_hmac)||!same(observed.post,p.post_hmac))fail('preimage_changed');
  const old=await receipt(c,p);if(old){await verifyReceipt(c,opts.key,p,digest,old);await c.query('ROLLBACK');started=false;return {status:'already_applied'};}
  await emptyTarget(c);
  for(const statement of INSERTS){const q=await c.query(statement,statement.includes('$1')?[p.target_owner]:[]);if(q.rowCount!==p.sms_count)fail('source_changed');}
  if(!same(mac(opts.key,'post',await value(c,graphSql(false))),p.post_hmac))fail('postimage_changed');
  await c.query(`INSERT INTO private.fixture_native_receipts(operation_id,collection_id,plan_sha256,source_hmac,post_hmac,source_owner,target_owner,source_auth,target_auth,sms_count)
   VALUES($1::uuid,$2,$3,$4,$5,$6,$7,$8::uuid,$9::uuid,$10)`,[p.operation_id,p.collection_id,digest,p.context_hmac,p.post_hmac,p.source_owner,p.target_owner,p.source_auth,p.target_auth,p.sms_count]);
  await guard(c);commitAttempted=true;try{await c.query('COMMIT');started=false;return {status:'applied',sms_count:p.sms_count};}catch{return {status:'commit_unconfirmed_do_not_retry'};}
 }catch(e){if(c&&started&&!commitAttempted)try{await c.query('ROLLBACK');}catch{}if(e instanceof NativeSmsImportError)throw e;fail('fixture_transaction_failed');}
 finally{if(c)try{await c.end();}catch{}opts.key.fill(0);}
}
export async function reconcileSyntheticNativeSmsGraph(options){
 const opts=input(options,{plan:true});let c,started=false;
 try{c=await connectAndStart(opts,{readonly:true});started=true;await fixture(c);await guard(c,{reconcile:true});const p=opts.request,old=await receipt(c,p);
  if(!old){await c.query('ROLLBACK');started=false;return {status:'receipt_not_visible_do_not_retry'};}
  await verifyReceipt(c,opts.key,p,nativeSmsPlanDigest(opts.serialized),old);await c.query('ROLLBACK');started=false;return {status:'receipt_and_postimage_verified'};
 }catch(e){if(c&&started)try{await c.query('ROLLBACK');}catch{}if(e instanceof NativeSmsImportError)throw e;fail('fixture_reconciliation_failed');}
 finally{if(c)try{await c.end();}catch{}opts.key.fill(0);}
}
