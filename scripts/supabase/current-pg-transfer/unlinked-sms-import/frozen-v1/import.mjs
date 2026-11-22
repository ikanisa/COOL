// Inert synthetic quarantine only. No managed connector, real-data path,
// financial post, SMS worker, provider or Storage operation exists here.
import {createHash,createHmac,timingSafeEqual} from 'node:crypto';
import {types} from 'node:util';
import {FINANCIAL_CATALOG_SQL} from '../financial-import/import.mjs';

export class UnlinkedSmsImportError extends Error{constructor(code){super(code);this.name='UnlinkedSmsImportError';this.code=code;}}
const fail=code=>{throw new UnlinkedSmsImportError(code);};
const HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const ID=/^[A-Za-z0-9_-]{1,80}$/;
const reqKeys=['version','operation_id','collection_id','source_owner','target_owner','source_auth','target_auth','source_epoch','target_epoch'];
const planKeys=[...reqKeys,'context_hmac','identity_hmac','post_hmac','sms_count'];
const canonical=x=>Array.isArray(x)?'['+x.map(canonical).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}':JSON.stringify(x);
export const unlinkedPlanDigest=s=>createHash('sha256').update(s).digest('hex');
const mac=(key,domain,value)=>createHmac('sha256',key).update('collect-synthetic-unlinked-quarantine-v1\0').update(domain).update('\0').update(value).digest('hex');
const same=(a,b)=>HASH.test(a??'')&&HASH.test(b??'')&&timingSafeEqual(Buffer.from(a,'hex'),Buffer.from(b,'hex'));
const plain=o=>o&&typeof o==='object'&&!types.isProxy(o)&&Object.getPrototypeOf(o)===Object.prototype;
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
const typed=Object.getPrototypeOf(Uint8Array.prototype),getBuffer=Object.getOwnPropertyDescriptor(typed,'buffer').get;
const getLength=Object.getOwnPropertyDescriptor(typed,'byteLength').get,getOffset=Object.getOwnPropertyDescriptor(typed,'byteOffset').get;
const resizable=Object.getOwnPropertyDescriptor(ArrayBuffer.prototype,'resizable')?.get;
function copyKey(x){
 if(types.isProxy(x)||!Buffer.isBuffer(x)||Object.getPrototypeOf(x)!==Buffer.prototype)fail('invalid_input');
 try{const b=getBuffer.call(x),n=getLength.call(x),off=getOffset.call(x);
  if(types.isSharedArrayBuffer(b)||(resizable&&resizable.call(b))||n!==32)fail('invalid_input');
  const out=Buffer.alloc(32);Uint8Array.prototype.set.call(out,new Uint8Array(b,off,n));return out;
 }catch(e){if(e instanceof UnlinkedSmsImportError)throw e;fail('invalid_input');}
}
function input(o,{plan=false}={}){
 if(!plain(o))fail('invalid_input');if(option(o,'mode')!=='synthetic')fail('managed_execution_closed');
 const serialized=option(o,plan?'planJson':'requestJson'),connect=option(o,'connect'),key=option(o,'key');
 if(typeof serialized!=='string'||Buffer.byteLength(serialized)>16384||typeof connect!=='function')fail('invalid_input');
 let v;try{v=JSON.parse(serialized);}catch{fail('invalid_input');}
 if(!plain(v)||Object.keys(v).sort().join('\0')!==[...(plan?planKeys:reqKeys)].sort().join('\0')||canonical(v)!==serialized||
  v.version!=='collect.synthetic-unlinked-quarantine.v1'||!UUID.test(v.operation_id??'')||
  ![v.source_auth,v.target_auth].every(x=>UUID.test(x??''))||v.source_auth===v.target_auth||
  ![v.collection_id,v.source_owner,v.target_owner].every(x=>ID.test(x??''))||v.source_owner===v.target_owner||
  ![v.source_epoch,v.target_epoch].every(x=>typeof x==='string'&&/^[1-9][0-9]{0,12}$/.test(x)))fail('invalid_input');
 if(plan){const expected=option(o,'expectedPlanSha256');if(!HASH.test(expected??'')||!same(unlinkedPlanDigest(serialized),expected)||
  ![v.context_hmac,v.identity_hmac,v.post_hmac].every(x=>HASH.test(x??''))||
  !Number.isInteger(v.sms_count)||v.sms_count<1||v.sms_count>64)fail('invalid_input');}
 return {request:Object.freeze(v),serialized,connect,key:copyKey(key)};
}

const SOURCE=['src.sms_receipts','src.momo_parse_attempts','src.momo_transactions','src.momo_transaction_sources',
 'src.momo_financial_links','src.origins','src.jobs','src.scopes','src.native_lineage','src.object_proofs'];
const IDENTITY=['src.users','src.auth_users','src.auth_links','src.collections','app.users','auth.users','private.auth_links','app.collections',
 'private.fixture_fences','private.fixture_admissions'];
const CLAIM='private.fixture_unlinked_claims',RECEIPT='private.fixture_unlinked_receipts',ITEM='private.fixture_unlinked_items';
const READ=[...SOURCE,...IDENTITY].sort(),WRITE=[CLAIM,RECEIPT,ITEM].sort();
export const UNLINKED_FIXTURE_TABLES=Object.freeze([...READ,...WRITE]);
export const UNLINKED_RECONCILE_TABLES=Object.freeze(['app.users','auth.users','private.auth_links',CLAIM,RECEIPT,ITEM].sort());
// Exact catalog digests are computed on the named PG17 fixture by the tests.
const FIXTURE_CATALOG='30d93032079b10b2556aae84780b427478ce4ecce5be17c7ac86ba5550fe2363';
const RECONCILE_CATALOG='841a4a07860a32d98533c5a03488b5dde50a39193c116479a63c395e4b524aa7';
const quoted=s=>"'"+s.replaceAll("'","''")+"'";
const contextSql='SELECT jsonb_build_object('+READ.map(n=>quoted(n)+",(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM ONLY "+n+' t)').join(',')+')::text AS value';
const identitySql=`SELECT jsonb_build_object('user',(SELECT to_jsonb(t) FROM ONLY app.users t WHERE id=$1),
 'auth',(SELECT to_jsonb(t) FROM ONLY auth.users t WHERE id=$2::uuid),
 'link',(SELECT to_jsonb(t) FROM ONLY private.auth_links t WHERE auth_id=$2::uuid AND user_id=$1))::text AS value`;
const boundsSql=tables=>'SELECT COALESCE(bool_or(n>256 OR largest>32768 OR total>2000000),false) OR sum(total)>2000000 AS exceeded FROM ('+tables.map(n=>
 "SELECT count(*) n,COALESCE(max(octet_length(to_jsonb(t)::text)),0) largest,COALESCE(sum(octet_length(to_jsonb(t)::text)),0) total FROM ONLY "+n+' t').join(' UNION ALL ')+') q';

// This shape is deliberately selective. It preserves every selected fixture
// parse-attempt row and every represented nullable field as JSONB, but it does
// not certify provider facts or reproduce the real private provenance graph.
const graphFrom=`FROM ONLY src.sms_receipts r
 LEFT JOIN ONLY src.momo_transaction_sources x ON x.raw_sms_id=r.id
 LEFT JOIN ONLY src.momo_transactions t ON t.id=x.transaction_id
 LEFT JOIN ONLY src.momo_parse_attempts a ON a.id=x.parse_attempt_id
 LEFT JOIN ONLY src.origins o ON o.source_id=r.id
 LEFT JOIN ONLY src.jobs j ON j.source_id=r.id
 LEFT JOIN ONLY src.scopes sc ON sc.source_id=r.id
 LEFT JOIN ONLY src.native_lineage n ON n.source_id=r.id
 LEFT JOIN ONLY src.object_proofs sp ON sp.object_key=r.object_key`;
const shapeSql=`WITH graph AS (SELECT r.id,r.owner_user_id,r.originating_session_id,r.receiver_hash,r.body_sha256,r.object_sha256,r.object_key,
 x.transaction_id,x.parse_attempt_id,x.relation source_relation,t.id tx_id,t.parse_attempt_id tx_attempt,t.receiving_account_id,t.has_conflict,t.allocation_state,
 a.id attempt_id,a.raw_sms_id,a.source_body_sha256,a.outcome attempt_outcome,
 o.collection_id origin_collection,o.principal_user_id origin_owner,o.body_sha256 origin_body,o.object_sha256 origin_object,
 j.source_id job_id,j.transaction_id job_tx,j.collection_id job_collection,j.source_fingerprint,j.state,
 sc.source_id scope_id,sc.transaction_id scope_tx,sc.collection_id scope_collection,sc.receiving_account_id scope_account,
 to_jsonb(n) lineage,to_jsonb(sp) proof,EXISTS(SELECT 1 FROM ONLY src.momo_financial_links f WHERE f.transaction_id=t.id) linked
 ${graphFrom})
 SELECT (SELECT count(*)::int FROM ONLY src.sms_receipts) n,count(*)::int joined,count(DISTINCT id)::int distinct_receipts,
 count(DISTINCT transaction_id)::int distinct_transactions,count(*) FILTER(WHERE NOT linked)::int unlinked,
 count(*) FILTER(WHERE linked)::int linked,
 count(*) FILTER(WHERE owner_user_id IS DISTINCT FROM $2 OR originating_session_id IS NOT NULL OR receiver_hash IS NOT NULL OR
  id !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' OR transaction_id IS DISTINCT FROM id OR tx_id IS DISTINCT FROM id OR
  body_sha256 !~ '^[a-f0-9]{64}$' OR object_sha256 !~ '^[a-f0-9]{64}$' OR
  attempt_id IS NULL OR attempt_id IS DISTINCT FROM parse_attempt_id OR attempt_id IS DISTINCT FROM tx_attempt OR
  raw_sms_id IS DISTINCT FROM id OR source_body_sha256 IS DISTINCT FROM body_sha256 OR attempt_outcome IS DISTINCT FROM 'accepted' OR source_relation IS DISTINCT FROM 'accepted' OR
  origin_collection IS DISTINCT FROM $1 OR origin_owner IS DISTINCT FROM $2 OR origin_body IS DISTINCT FROM body_sha256 OR origin_object IS DISTINCT FROM object_sha256 OR
  job_id IS NULL OR job_tx IS DISTINCT FROM id OR job_collection IS DISTINCT FROM $1 OR source_fingerprint !~ '^[a-f0-9]{64}$' OR state IS DISTINCT FROM 'completed' OR
  has_conflict IS DISTINCT FROM 0 OR (NOT linked AND allocation_state NOT IN('unallocated','needs_review','not_applicable')) OR
  (linked AND allocation_state IS DISTINCT FROM 'linked') OR
  scope_id IS NULL OR scope_tx IS DISTINCT FROM id OR scope_collection IS DISTINCT FROM $1 OR scope_account IS DISTINCT FROM receiving_account_id OR
  lineage IS NULL OR lineage->>'principal_user_id' IS DISTINCT FROM $2 OR lineage->>'attempt_id' IS DISTINCT FROM attempt_id OR
  lineage->>'observation_fingerprint' IS DISTINCT FROM source_fingerprint OR lineage->>'relation' IS DISTINCT FROM 'accepted' OR
  lineage->>'phase' IS DISTINCT FROM 'finished' OR lineage->>'lease_token' IS NOT NULL OR lineage->>'lease_until' IS NOT NULL OR lineage->>'retry_lease' IS NOT NULL OR
  lineage->>'observation_request_settled' IS DISTINCT FROM 'true' OR lineage->>'storage_intent_settled' IS DISTINCT FROM 'true' OR
  lineage->>'upload_unresolved' IS DISTINCT FROM 'false' OR lineage->>'delete_tombstone' IS DISTINCT FROM 'false' OR
  proof IS NULL OR proof->>'owner_id' IS DISTINCT FROM $2 OR proof->>'entity_id' IS DISTINCT FROM id OR proof->>'purpose' IS DISTINCT FROM 'sms_receipt' OR
  proof->>'plaintext_sha256' IS DISTINCT FROM object_sha256) ::int bad,
 (SELECT count(*)::int FROM ONLY src.momo_transactions) txs,
 (SELECT count(*)::int FROM ONLY src.momo_transaction_sources) sources,
 (SELECT count(*)::int FROM ONLY src.origins) origins,(SELECT count(*)::int FROM ONLY src.jobs) jobs,
 (SELECT count(*)::int FROM ONLY src.scopes) scopes,(SELECT count(*)::int FROM ONLY src.native_lineage) lineages,
 (SELECT count(*)::int FROM ONLY src.momo_parse_attempts a WHERE NOT EXISTS(SELECT 1 FROM ONLY src.sms_receipts r WHERE r.id=a.raw_sms_id)) orphan_attempts
 FROM graph`;
const payload=`jsonb_build_object('source_id',r.id,'receipt',to_jsonb(r),'source_link',to_jsonb(x),'transaction',to_jsonb(t),
 'parse_attempts',(SELECT COALESCE(jsonb_agg(to_jsonb(pa) ORDER BY pa.id),'[]'::jsonb) FROM ONLY src.momo_parse_attempts pa WHERE pa.raw_sms_id=r.id),
 'origin',to_jsonb(o),'job',to_jsonb(j),
 'job_sql_nulls',jsonb_build_object('posting_facts',j.posting_facts IS NULL,'posting_output',j.posting_output IS NULL),
 'scope',to_jsonb(sc),'synthetic_lineage',to_jsonb(n),'synthetic_object_metadata',to_jsonb(sp))`;
const onlyUnlinked='WHERE NOT EXISTS(SELECT 1 FROM ONLY src.momo_financial_links f WHERE f.transaction_id=t.id)';
const postSql=`SELECT COALESCE(jsonb_agg(${payload} ORDER BY r.id),'[]'::jsonb)::text AS value ${graphFrom} ${onlyUnlinked}`;
const archivedSql=`SELECT COALESCE(jsonb_agg(payload ORDER BY source_id),'[]'::jsonb)::text AS value FROM ONLY ${ITEM} WHERE operation_id=$1::uuid`;

async function fixture(c){
 const q=await c.query(`SELECT current_database() db,current_setting('cluster_name') cluster,session_user login,current_user role,
  inet_server_addr() IS NULL socket,current_setting('server_version_num')::int/10000 major,current_setting('session_replication_role') replication,
  (SELECT rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname=current_user) privileged`);
 const x=q.rows[0];if(q.rowCount!==1||x.db!=='collect_unlinked_sms_fixture'||x.cluster!=='collect_unlinked_sms_fixture'||
  x.login!=='fixture_operator'||x.role!=='fixture_operator'||!x.socket||x.major!==17||x.replication!=='origin'||x.privileged!==false)fail('fixture_identity_rejected');
}
async function lock(c,{write=false,readonly=false}={}){
 await c.query("SET LOCAL search_path=pg_catalog,pg_temp;SET LOCAL lock_timeout='3s';SET LOCAL statement_timeout='15s';SET LOCAL TIME ZONE 'UTC'");
 if(readonly)await c.query('LOCK TABLE '+UNLINKED_RECONCILE_TABLES.join(',')+' IN ACCESS SHARE MODE');
 else{await c.query('LOCK TABLE '+READ.join(',')+' IN SHARE MODE');await c.query('LOCK TABLE '+WRITE.join(',')+' IN '+(write?'SHARE ROW EXCLUSIVE':'SHARE')+' MODE');}
}
async function guard(c,{reconcile=false}={}){
 const names=reconcile?UNLINKED_RECONCILE_TABLES:UNLINKED_FIXTURE_TABLES;
 const q=await c.query(`WITH r AS (SELECT name,to_regclass(name) oid FROM unnest($1::text[]) name)
 SELECT EXISTS(SELECT 1 FROM r LEFT JOIN pg_class c ON c.oid=r.oid WHERE r.oid IS NULL OR c.relkind<>'r'
  OR pg_get_userbyid(c.relowner) IS DISTINCT FROM 'fixture_bootstrap' OR c.relrowsecurity OR c.relforcerowsecurity
  OR NOT coalesce(has_schema_privilege(current_user,c.relnamespace,'USAGE'),false)
  OR NOT coalesce(has_table_privilege(current_user,r.oid,'SELECT'),false) OR coalesce(row_security_active(r.oid),true)
  OR EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid)) bad`,[names]);
 if(q.rows[0]?.bad!==false)fail('fixture_catalog_refused');
 const cat=await c.query(FINANCIAL_CATALOG_SQL,[names]);if(cat.rows[0]?.value!==(reconcile?RECONCILE_CATALOG:FIXTURE_CATALOG))fail('fixture_schema_changed');
 const b=await c.query(boundsSql(names));if(b.rows[0]?.exceeded!==false)fail('fixture_bounds_exceeded');
 const runtime=await c.query(`SELECT NOT EXISTS(SELECT 1 FROM unnest($1::text[]) t
  CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
  WHERE has_table_privilege('fixture_runtime',t,p)) AS closed`,[WRITE]);
 if(runtime.rows[0]?.closed!==true)fail('fixture_runtime_access_refused');
}
async function identity(c,p){
 const q=await c.query(`SELECT (SELECT count(*)=2 AND bool_and(mode='fenced') FROM private.fixture_fences) AND
  EXISTS(SELECT 1 FROM private.fixture_fences WHERE side='source' AND epoch=$1::bigint) AND
  EXISTS(SELECT 1 FROM private.fixture_fences WHERE side='target' AND epoch=$2::bigint) AND
  NOT EXISTS(SELECT 1 FROM private.fixture_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0) AND
  EXISTS(SELECT 1 FROM src.users u JOIN src.auth_links l ON l.user_id=u.id JOIN src.auth_users a ON a.id=l.auth_id WHERE u.id=$3 AND u.active AND a.id=$4::uuid AND a.active) AND
  EXISTS(SELECT 1 FROM app.users u JOIN private.auth_links l ON l.user_id=u.id JOIN auth.users a ON a.id=l.auth_id WHERE u.id=$5 AND u.active AND a.id=$6::uuid AND a.active) AND
  EXISTS(SELECT 1 FROM src.collections WHERE id=$7 AND creator_user_id=$3) AND EXISTS(SELECT 1 FROM app.collections WHERE id=$7 AND creator_user_id=$5) ok`,
 [p.source_epoch,p.target_epoch,p.source_owner,p.source_auth,p.target_owner,p.target_auth,p.collection_id]);
 if(q.rows[0]?.ok!==true)fail('identity_or_fence_changed');
}
async function value(c,sql,params=[]){const q=await c.query(sql,params);if(q.rowCount!==1||typeof q.rows[0].value!=='string'||Buffer.byteLength(q.rows[0].value)>2000000)fail('snapshot_unavailable');return q.rows[0].value;}
async function graph(c,p){
 const {rows:[r]}=await c.query(shapeSql,[p.collection_id,p.source_owner]);
 if(!r||r.n<1||r.n>64||r.unlinked<1||r.unlinked>64||r.bad!==0||r.orphan_attempts!==0||
  [r.joined,r.distinct_receipts,r.distinct_transactions,r.txs,r.sources,r.origins,r.jobs,r.scopes,r.lineages].some(n=>n!==r.n))fail('unlinked_graph_refused');
 return r.unlinked;
}
async function context(c,key,p){await fixture(c);await guard(c);await identity(c,p);const count=await graph(c,p);
 return {count,context:mac(key,'context',await value(c,contextSql)),identity:mac(key,'identity',await value(c,identitySql,[p.target_owner,p.target_auth])),
  post:mac(key,'post',await value(c,postSql))};}
async function collision(c){const q=await c.query(`SELECT EXISTS(SELECT 1 ${graphFrom} JOIN ONLY ${ITEM} target ON target.source_id=r.id ${onlyUnlinked}) AS collision`);
 if(q.rows[0]?.collision!==false)fail('target_unlinked_conflict');}
async function start(opts,{write=false,readonly=false}={}){
 const c=await opts.connect();try{await fixture(c);await c.query(readonly?'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY':'BEGIN');await lock(c,{write,readonly});return c;}
 catch(e){try{await c.end();}catch{}if(readonly&&e?.code==='42501')fail('fixture_catalog_refused');throw e;}
}
async function close(c){if(c)try{await c.end();}catch{}}
async function rollback(c){if(c)try{await c.query('ROLLBACK');}catch{}}

export async function captureSyntheticUnlinkedPlan(options){
 const o=input(options);let c;try{c=await start(o);const p=o.request,v=await context(c,o.key,p);await collision(c);
  const used=await c.query(`SELECT EXISTS(SELECT 1 FROM ONLY ${CLAIM} WHERE operation_id=$1::uuid OR collection_id=$2) used`,[p.operation_id,p.collection_id]);
  if(used.rows[0]?.used!==false)fail('claim_exists_do_not_retry');
  const plan={...p,context_hmac:v.context,identity_hmac:v.identity,post_hmac:v.post,sms_count:v.count};
  const planJson=canonical(plan);await rollback(c);return {planJson,expectedPlanSha256:unlinkedPlanDigest(planJson),writeAuthorized:false};
 }catch(e){await rollback(c);if(e instanceof UnlinkedSmsImportError)throw e;fail('fixture_capture_failed');}
 finally{await close(c);o.key.fill(0);}
}
// A separate, durable fixture claim deliberately survives an import failure.
// It is scoped to this fixture database and collection, not globally durable.
export async function importSyntheticUnlinkedQuarantine(options){
 const o=input(options,{plan:true}),p=o.request,digest=unlinkedPlanDigest(o.serialized);let c,commitAttempted=false;
 try{
  c=await start(o,{write:true});let observed=await context(c,o.key,p);
  if(observed.count!==p.sms_count||!same(observed.context,p.context_hmac)||!same(observed.identity,p.identity_hmac)||!same(observed.post,p.post_hmac))fail('preimage_changed');
  const used=await c.query(`SELECT EXISTS(SELECT 1 FROM ONLY ${CLAIM} WHERE operation_id=$1::uuid OR collection_id=$2) used`,[p.operation_id,p.collection_id]);
  if(used.rows[0]?.used!==false)fail('claim_exists_do_not_retry');await collision(c);
  try{await c.query(`INSERT INTO ${CLAIM}(operation_id,collection_id,plan_sha256) VALUES($1::uuid,$2,$3)`,[p.operation_id,p.collection_id,digest]);}
  catch(e){if(e?.code==='23505')fail('claim_exists_do_not_retry');throw e;}
  commitAttempted=true;try{await c.query('COMMIT');}catch{return {status:'claim_commit_unconfirmed_do_not_retry'};}
  await close(c);c=null;commitAttempted=false;
  c=await start(o,{write:true});observed=await context(c,o.key,p);
  if(observed.count!==p.sms_count||!same(observed.context,p.context_hmac)||!same(observed.identity,p.identity_hmac)||!same(observed.post,p.post_hmac))fail('preimage_changed_after_claim');
  const claim=await c.query(`SELECT operation_id::text,collection_id,plan_sha256 FROM ONLY ${CLAIM} WHERE operation_id=$1::uuid`,[p.operation_id]);
  if(claim.rowCount!==1||claim.rows[0].collection_id!==p.collection_id||claim.rows[0].plan_sha256!==digest)fail('claim_mismatch');
  await collision(c);
  await c.query(`INSERT INTO ${RECEIPT}(operation_id,collection_id,plan_sha256,context_hmac,identity_hmac,post_hmac,source_owner,target_owner,source_auth,target_auth,sms_count)
   VALUES($1::uuid,$2,$3,$4,$5,$6,$7,$8,$9::uuid,$10::uuid,$11)`,[p.operation_id,p.collection_id,digest,p.context_hmac,p.identity_hmac,p.post_hmac,p.source_owner,p.target_owner,p.source_auth,p.target_auth,p.sms_count]);
  const inserted=await c.query(`INSERT INTO ${ITEM}(source_id,operation_id,payload) SELECT r.id,$1::uuid,${payload} ${graphFrom} ${onlyUnlinked} ORDER BY r.id`,[p.operation_id]);
  if(inserted.rowCount!==p.sms_count||!same(mac(o.key,'post',await value(c,archivedSql,[p.operation_id])),p.post_hmac))fail('postimage_changed');
  await guard(c);commitAttempted=true;try{await c.query('COMMIT');return {status:'quarantined',sms_count:p.sms_count,replayEnabled:false};}
  catch{return {status:'commit_unconfirmed_do_not_retry'};}
 }catch(e){if(!commitAttempted)await rollback(c);if(e instanceof UnlinkedSmsImportError)throw e;fail('fixture_transaction_failed');}
 finally{await close(c);o.key.fill(0);}
}
export async function reconcileSyntheticUnlinkedQuarantine(options){
 const o=input(options,{plan:true}),p=o.request,digest=unlinkedPlanDigest(o.serialized);let c;
 try{c=await start(o,{readonly:true});await fixture(c);await guard(c,{reconcile:true});
  const claim=await c.query(`SELECT collection_id,plan_sha256 FROM ONLY ${CLAIM} WHERE operation_id=$1::uuid`,[p.operation_id]);
  const r=await c.query(`SELECT collection_id,plan_sha256,context_hmac,identity_hmac,post_hmac,source_owner,target_owner,source_auth::text,target_auth::text,sms_count
   FROM ONLY ${RECEIPT} WHERE operation_id=$1::uuid`,[p.operation_id]);
  if(!claim.rowCount&&r.rowCount)fail('receipt_claim_inconsistent');
  if(!claim.rowCount||!r.rowCount){await rollback(c);return {status:'receipt_or_claim_not_visible_do_not_retry'};}
  const a=claim.rows[0],b=r.rows[0];if(a.collection_id!==p.collection_id||a.plan_sha256!==digest||b.collection_id!==p.collection_id||b.plan_sha256!==digest||
   b.context_hmac!==p.context_hmac||b.identity_hmac!==p.identity_hmac||b.post_hmac!==p.post_hmac||b.source_owner!==p.source_owner||b.target_owner!==p.target_owner||
   b.source_auth!==p.source_auth||b.target_auth!==p.target_auth||b.sms_count!==p.sms_count)fail('receipt_mismatch');
  if(!same(mac(o.key,'identity',await value(c,identitySql,[p.target_owner,p.target_auth])),p.identity_hmac))fail('identity_changed');
  if(!same(mac(o.key,'post',await value(c,archivedSql,[p.operation_id])),p.post_hmac))fail('postimage_changed');
  await rollback(c);return {status:'quarantine_receipt_and_postimage_verified',replayEnabled:false};
 }catch(e){await rollback(c);if(e instanceof UnlinkedSmsImportError)throw e;fail('fixture_reconciliation_failed');}
 finally{await close(c);o.key.fill(0);}
}
