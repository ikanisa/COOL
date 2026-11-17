// Synthetic, single-database experiment. This module is intentionally not a
// managed Supabase executor. Every connection is identity-checked before BEGIN.
import {createHash,createHmac,timingSafeEqual} from 'node:crypto';
import {types} from 'node:util';

export class BusinessImportError extends Error {
 constructor(code){super(code);this.name='BusinessImportError';this.code=code;}
}
const fail=code=>{throw new BusinessImportError(code);};
const hex=/^[0-9a-f]{64}$/;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const textId=/^[a-zA-Z0-9_-]{1,80}$/;
const fields=['version','operation_id','source_collection_id','source_user_id','source_auth_id','target_user_id','target_auth_id','source_epoch','target_epoch','source_collection_hmac','expected_post_hmac','source_user_hmac','source_auth_hmac','source_link_hmac','target_user_hmac','target_auth_hmac','target_link_hmac','evidence_id','evidence_hmac'];
const sortObject=x=>Array.isArray(x)?x.map(sortObject):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,sortObject(x[k])])):x;
export function planDigest(plan){return createHash('sha256').update(JSON.stringify(sortObject(plan))).digest('hex');}
export function snapshotHmac(key,domain,postgresJson){
 if(!Buffer.isBuffer(key)||key.length!==32||typeof domain!=='string'||typeof postgresJson!=='string')fail('invalid_input');
 return createHmac('sha256',key).update('collect-synthetic-import-v1\0').update(domain).update('\0').update(postgresJson).digest('hex');
}
function same(a,b){return hex.test(a??'')&&hex.test(b??'')&&timingSafeEqual(Buffer.from(a,'hex'),Buffer.from(b,'hex'));}
// Capture all caller-owned inputs synchronously. A plan is a flat record of
// primitive strings: no accessors, proxies, extra keys, symbols or alternate
// prototype can change its meaning during hashing or after the first await.
function dataValue(record,name){
 const descriptor=Object.getOwnPropertyDescriptor(record,name);
 if(!descriptor||!Object.hasOwn(descriptor,'value'))fail('invalid_plan');
 return descriptor.value;
}
function plainRecord(value){
 return !!value&&typeof value==='object'&&!types.isProxy(value)&&Object.getPrototypeOf(value)===Object.prototype;
}
const typedArrayPrototype=Object.getPrototypeOf(Uint8Array.prototype);
const typedBuffer=Object.getOwnPropertyDescriptor(typedArrayPrototype,'buffer').get;
const typedLength=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteLength').get;
const typedOffset=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteOffset').get;
function copyKey(value){
 if(types.isProxy(value)||!Buffer.isBuffer(value)||Object.getPrototypeOf(value)!==Buffer.prototype)fail('invalid_plan');
 let buffer,length,offset;
 try{buffer=typedBuffer.call(value);length=typedLength.call(value);offset=typedOffset.call(value);}catch{fail('invalid_plan');}
 // Shared memory could be changed by another thread while the copy is made.
 if(types.isSharedArrayBuffer(buffer)||length!==32)fail('invalid_plan');
 try{
  const copy=Buffer.alloc(32);
  Uint8Array.prototype.set.call(copy,new Uint8Array(buffer,offset,length));
  return copy;
 }catch{fail('invalid_plan');}
}
function captureOptions(options){
 if(!plainRecord(options))fail('invalid_plan');
 const mode=dataValue(options,'mode');
 if(mode!=='synthetic')fail('managed_execution_closed');
 const inputPlan=dataValue(options,'plan');
 if(!plainRecord(inputPlan))fail('invalid_plan');
 const keys=Reflect.ownKeys(inputPlan);
 if(keys.some(k=>typeof k!=='string')||keys.sort().join(',')!==[...fields].sort().join(','))fail('invalid_plan');
 const plan={};
 for(const name of fields){const value=dataValue(inputPlan,name);if(typeof value!=='string')fail('invalid_plan');plan[name]=value;}
 Object.freeze(plan);
 const approvedDigest=dataValue(options,'approvedDigest'),connect=dataValue(options,'connect'),sourceKey=dataValue(options,'key');
 if(typeof connect!=='function'||typeof approvedDigest!=='string'||!hex.test(approvedDigest)||
  plan.version!=='collect.synthetic-collection-import.v1'||
  !uuid.test(plan.operation_id)||!uuid.test(plan.source_auth_id)||!uuid.test(plan.target_auth_id)||
  ![plan.source_collection_id,plan.source_user_id,plan.target_user_id,plan.evidence_id].every(x=>textId.test(x))||
  ![plan.source_epoch,plan.target_epoch].every(x=>/^[1-9][0-9]{0,12}$/.test(x))||
  !fields.filter(x=>x.endsWith('_hmac')).every(x=>hex.test(plan[x]))||!same(planDigest(plan),approvedDigest))fail('invalid_plan');
 return Object.freeze({mode,plan,approvedDigest,connect,key:copyKey(sourceKey)});
}
async function checkFixture(c){
 const q=await c.query(`SELECT current_database() AS db, current_setting('cluster_name') AS cluster,
  session_user AS login,current_user AS role, inet_server_addr() IS NULL AS socket,
  current_setting('session_replication_role') AS replication,
  (SELECT rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname=current_user) AS privileged`);
 const x=q.rows[0];
 if(q.rowCount!==1||x.db!=='collect_business_import_fixture'||x.cluster!=='collect_business_import_fixture'||
  x.login!=='fixture_operator'||x.role!=='fixture_operator'||!x.socket||x.replication!=='origin'||x.privileged!==false)fail('fixture_identity_rejected');
}
async function lockContext(c){
 // These relations and trigger identities belong to the fixture only. Relation
 // locks exclude row writers and DDL until COMMIT; all lockers use this order.
 await c.query(`LOCK TABLE src.collections,src.users,src.auth_users,src.auth_principal_links,src.collection_dependencies,
  app.users,auth.users,private.auth_principal_links,private.fixture_fences,private.fixture_admissions,
  private.fixture_evidence IN SHARE MODE`);
 await c.query('LOCK TABLE app.collections,private.fixture_receipts IN SHARE ROW EXCLUSIVE MODE');
 const r=await c.query(`SELECT n.nspname,c.relname,t.tgname,t.tgenabled
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE NOT t.tgisinternal AND ((n.nspname='src' AND c.relname='auth_principal_links' AND t.tgname='fixture_link_immutable')
   OR (n.nspname='private' AND c.relname='auth_principal_links' AND t.tgname='fixture_link_immutable')
   OR (n.nspname='app' AND c.relname='collections' AND t.tgname='fixture_collection_fence'))`);
 if(r.rowCount!==3||r.rows.some(x=>x.tgenabled!=='A'))fail('fixture_guards_changed');
}
async function rowJson(c,sql,params){
 // Filtering in SQL prevents handing an unbounded row to the JS process.
 const r=await c.query(sql,params);if(r.rowCount!==1)fail('preimage_unavailable');return r.rows[0].value;
}
const queries={
 source_collection:'SELECT to_jsonb(t)::text value FROM src.collections t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
 source_user:'SELECT to_jsonb(t)::text value FROM src.users t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
 source_auth:'SELECT to_jsonb(t)::text value FROM src.auth_users t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
 source_link:'SELECT to_jsonb(t)::text value FROM src.auth_principal_links t WHERE auth_user_id=$1 AND user_id=$2 AND octet_length(to_jsonb(t)::text)<=16384',
 target_user:'SELECT to_jsonb(t)::text value FROM app.users t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
 target_auth:'SELECT to_jsonb(t)::text value FROM auth.users t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
 target_link:'SELECT to_jsonb(t)::text value FROM private.auth_principal_links t WHERE auth_user_id=$1 AND user_id=$2 AND octet_length(to_jsonb(t)::text)<=16384',
 evidence:'SELECT to_jsonb(t)::text value FROM private.fixture_evidence t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
 target_collection:'SELECT to_jsonb(t)::text value FROM app.collections t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
 projected:'SELECT (to_jsonb(t)||jsonb_build_object(\'creator_user_id\',$2::text))::text value FROM src.collections t WHERE id=$1 AND octet_length(to_jsonb(t)::text)<=16384',
};
async function checkSnapshot(c,key,plan,name,params){
 const value=await rowJson(c,queries[name],params);
 if(!same(snapshotHmac(key,name,value),plan[name+'_hmac']))fail('preimage_changed');
 return JSON.parse(value);
}
async function checkTargetIdentity(c,key,p){
 const user=await checkSnapshot(c,key,p,'target_user',[p.target_user_id]);
 const auth=await checkSnapshot(c,key,p,'target_auth',[p.target_auth_id]);
 await checkSnapshot(c,key,p,'target_link',[p.target_auth_id,p.target_user_id]);
 if(user.access_status!=='active'||auth.active!==true)fail('identity_inactive');
}
async function checkContext(c,key,p){
 await lockContext(c);
 const fences=await c.query('SELECT side,epoch::text,mode FROM private.fixture_fences ORDER BY side');
 if(fences.rowCount!==2||fences.rows[0].side!=='source'||fences.rows[0].epoch!==p.source_epoch||fences.rows[0].mode!=='fenced'||
  fences.rows[1].side!=='target'||fences.rows[1].epoch!==p.target_epoch||fences.rows[1].mode!=='fenced')fail('fence_changed');
 const admissions=await c.query("SELECT 1 FROM private.fixture_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0 LIMIT 1");
 if(admissions.rowCount)fail('unsettled_work');
 const collection=await checkSnapshot(c,key,p,'source_collection',[p.source_collection_id]);
 const user=await checkSnapshot(c,key,p,'source_user',[p.source_user_id]);
 const auth=await checkSnapshot(c,key,p,'source_auth',[p.source_auth_id]);
 await checkSnapshot(c,key,p,'source_link',[p.source_auth_id,p.source_user_id]);
 await checkTargetIdentity(c,key,p);
 const proof=await checkSnapshot(c,key,p,'evidence',[p.evidence_id]);
 if(collection.creator_user_id!==p.source_user_id||user.access_status!=='active'||auth.active!==true)fail('mapping_mismatch');
 // Synthetic attestation is not evidence of the real catalogue or real keys.
 if(proof.source_collection_id!==p.source_collection_id||proof.source_user_id!==p.source_user_id||proof.target_user_id!==p.target_user_id||
  proof.reviewed!==true||proof.complete_object_graph!==true||proof.reference_free!==true||proof.key_aad_verified!==true||
  proof.identity_aad_independent!==true||!hex.test(proof.source_key_aad??'')||!same(proof.source_key_aad,proof.target_key_aad))fail('proof_unavailable');
 const deps=await c.query('SELECT 1 FROM src.collection_dependencies WHERE collection_id=$1 LIMIT 1',[p.source_collection_id]);
 if(deps.rowCount)fail('dependent_history_present');
 const projected=await rowJson(c,queries.projected,[p.source_collection_id,p.target_user_id]);
 const expectedPostHmac=snapshotHmac(key,'target_collection',projected);
 if(!same(expectedPostHmac,p.expected_post_hmac))fail('expected_postimage_changed');
 return {expectedPostHmac};
}
async function readReceipt(c,p){
 const r=await c.query('SELECT operation_id::text,plan_digest,source_collection_id,source_user_id,target_user_id,target_auth_id::text,source_hmac,target_hmac,evidence_hmac FROM private.fixture_receipts WHERE operation_id=$1',[p.operation_id]);
 return r.rows[0];
}
async function checkReceipt(c,key,p,approvedDigest,receipt,expectedPostHmac){
 if(!receipt||receipt.plan_digest!==approvedDigest||receipt.source_collection_id!==p.source_collection_id||receipt.source_user_id!==p.source_user_id||
  receipt.target_user_id!==p.target_user_id||receipt.target_auth_id!==p.target_auth_id||receipt.source_hmac!==p.source_collection_hmac||
  receipt.evidence_hmac!==p.evidence_hmac||!same(receipt.target_hmac,p.expected_post_hmac)||(expectedPostHmac&&!same(receipt.target_hmac,expectedPostHmac)))fail('receipt_mismatch');
 const target=await rowJson(c,queries.target_collection,[p.source_collection_id]);
 if(!same(snapshotHmac(key,'target_collection',target),receipt.target_hmac))fail('target_postimage_changed');
}
const INSERT_COLLECTION=`INSERT INTO app.collections(id,slug,creator_user_id,title,description,collection_type,country_code,currency,status,
 visibility_status,is_platform_sponsored,receiver_momo_number,receiver_network,receiver_display_label,share_code_hash,share_code_ciphertext,
 share_code_version,revision,data_json,created_at,updated_at)
 SELECT id,slug,$2,title,description,collection_type,country_code,currency,status,visibility_status,is_platform_sponsored,
 receiver_momo_number,receiver_network,receiver_display_label,share_code_hash,share_code_ciphertext,share_code_version,revision,data_json,created_at,updated_at
 FROM src.collections WHERE id=$1 AND creator_user_id=$3`;
export async function importSyntheticCollection(options){
 const {connect,plan:p,key,approvedDigest}=captureOptions(options);let c,started=false,commitAttempted=false;
 try{
  c=await connect();await checkFixture(c);await c.query('BEGIN');started=true;
  await checkFixture(c);const {expectedPostHmac}=await checkContext(c,key,p);
  const prior=await readReceipt(c,p);
  if(prior){await checkReceipt(c,key,p,approvedDigest,prior,expectedPostHmac);await c.query('ROLLBACK');started=false;return {status:'already_applied'};}
  const conflict=await c.query(`SELECT 1 FROM app.collections t JOIN src.collections s ON s.id=$1
   WHERE t.id=s.id OR t.slug=s.slug OR (s.share_code_hash IS NOT NULL AND t.share_code_hash=s.share_code_hash) LIMIT 1`,[p.source_collection_id]);
  if(conflict.rowCount)fail('target_unique_conflict');
  await c.query("SELECT set_config('collect.fixture_operation',$1,true)",[p.operation_id]);
  const inserted=await c.query(INSERT_COLLECTION,[p.source_collection_id,p.target_user_id,p.source_user_id]);
  if(inserted.rowCount!==1)fail('source_changed');
  const actual=await rowJson(c,queries.target_collection,[p.source_collection_id]);
  if(!same(snapshotHmac(key,'target_collection',actual),expectedPostHmac))fail('target_postimage_changed');
  await c.query(`INSERT INTO private.fixture_receipts(operation_id,plan_digest,source_collection_id,source_user_id,target_user_id,target_auth_id,source_hmac,target_hmac,evidence_hmac)
   VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[p.operation_id,approvedDigest,p.source_collection_id,p.source_user_id,p.target_user_id,p.target_auth_id,p.source_collection_hmac,expectedPostHmac,p.evidence_hmac]);
  commitAttempted=true;
  try{await c.query('COMMIT');started=false;return {status:'applied'};}
  catch{return {status:'commit_unconfirmed_do_not_retry'};}
 }catch(e){
  if(started&&!commitAttempted){try{await c.query('ROLLBACK');}catch{}}
  if(e instanceof BusinessImportError)throw e;
  fail('fixture_transaction_failed');
 }finally{if(c){try{await c.end();}catch{}}key.fill(0);}
}
export async function reconcileSyntheticCollection(options){
 const {connect,plan:p,key,approvedDigest}=captureOptions(options);let c,started=false;
 try{
  c=await connect();await checkFixture(c);await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');started=true;
  await checkFixture(c);await checkTargetIdentity(c,key,p);
  const receipt=await readReceipt(c,p);
  if(!receipt){await c.query('ROLLBACK');started=false;return {status:'receipt_not_visible_do_not_retry'};}
  await checkReceipt(c,key,p,approvedDigest,receipt);await c.query('ROLLBACK');started=false;return {status:'receipt_and_postimage_verified'};
 }catch(e){
  if(started){try{await c.query('ROLLBACK');}catch{}}
  if(e instanceof BusinessImportError)throw e;
  fail('fixture_reconciliation_failed');
 }finally{if(c){try{await c.end();}catch{}}key.fill(0);}
}
