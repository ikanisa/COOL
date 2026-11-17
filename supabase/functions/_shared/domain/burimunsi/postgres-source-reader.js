import {auditStatement} from '../core.js';
import {canonicalManagedActor} from './postgres-managed-actor.js';
import {authorize} from './policy.js';
import {requirePort,requireThat,BuriError} from './errors.js';
import {canonicalJson,requireId,requireRequestId,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PostgresPostingCustody} from './postgres-posting-custody.js';
import {PostgresStorageWitnesses} from './postgres-storage-witnesses.js';
import {hasPhonePinContext} from './phone-pin-request.js';
import {canonicalListingInstant,listingText} from './listing-query.js';

const copy=value=>JSON.parse(canonicalJson(value));
const equal=(a,b)=>canonicalJson(a)===canonicalJson(b);
const enc=new TextEncoder(),dec=new TextDecoder('utf-8',{fatal:true});
const bytesHash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');
const integer=value=>pgInteger(value,{minimum:0,code:'source_integrity_failed'});
const integrity=value=>requireThat(value,'source_integrity_failed',503);

// The immutable source association is the only group-routing fact. Neither a
// current wallet match nor an arbitrary duplicate/parse link grants visibility.
// Aggregating links avoids multiplying receipts or choosing an arbitrary ID.
export const NATIVE_SOURCE_SQL=`SELECT r.*,x.collection_id,x.receiving_account_id,
 to_jsonb(x) AS association,
 coalesce(links.duplicate,false) AS duplicate,
 CASE WHEN links.transaction_count=1 THEN links.transaction_id ELSE NULL END AS transaction_id,
 coalesce(links.identities,'[]'::jsonb) AS link_identities,
 o.operation_id,o.sha256 AS stored_sha256,o.size AS stored_size,
 p.state AS storage_state,p.delete_tombstone,p.upload_unresolved,p.active_attempt
 FROM private.burimunsi_sms_source_scopes x
 JOIN app.sms_receipts r ON r.id=x.source_id AND r.owner_user_id=x.owner_user_id
  AND r.body_sha256=x.source_body_sha256 AND r.object_sha256=x.object_sha256
 JOIN private.storage_objects o ON o.object_key=r.object_key
  AND o.scope=jsonb_build_object('ownerId',r.owner_user_id,'purpose','sms_receipt','entityId',r.id)
 JOIN private.storage_put_intents p ON p.operation_id=o.operation_id AND p.object_key=o.object_key
  AND p.sha256=o.sha256 AND p.size=o.size AND p.scope=o.scope
 LEFT JOIN LATERAL (
  SELECT bool_or(src.relation='duplicate') AS duplicate,count(DISTINCT t.id) AS transaction_count,min(t.id) AS transaction_id,
   jsonb_agg(jsonb_build_array(t.id,src.parse_attempt_id,src.relation,a.source_body_sha256,a.outcome)
    ORDER BY t.id,src.parse_attempt_id,src.relation) AS identities
  FROM app.momo_transaction_sources src
  JOIN app.momo_transactions t ON t.id=src.transaction_id AND t.receiving_account_id=x.receiving_account_id
  JOIN private.burimunsi_transaction_scopes tx ON tx.transaction_id=t.id AND tx.collection_id=x.collection_id
   AND tx.receiving_account_id=x.receiving_account_id
  JOIN app.momo_parse_attempts a ON a.id=src.parse_attempt_id AND a.raw_sms_id=r.id AND a.source_body_sha256=r.body_sha256
  WHERE src.raw_sms_id=r.id
 ) links ON true
 WHERE x.collection_id=$1 AND p.state='committed' AND NOT p.delete_tombstone
  AND NOT p.upload_unresolved AND p.active_attempt IS NULL
  AND NOT EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=r.object_key)`;

export const NATIVE_CURRENT_BINDING_SQL=`SELECT b.id,b.version,b.status,c.installation_id,c.revoked_at,s.enabled,s.binding_version
 FROM private.burimunsi_scopes s
 JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id AND b.receiving_account_id=s.receiving_account_id
 JOIN app.momo_gateway_credentials c ON c.binding_id=b.id
 WHERE s.collection_id=$1 AND c.installation_id=$2`;

// The same current global grant AND Admin role ceiling used by accountDatabase.
// This existing lock-free managed snapshot is safe in REPEATABLE READ, READ ONLY;
// assert_actor()/mutation_guards deliberately remain in write disclosure phases.
export const NATIVE_METADATA_AUTH_SQL=`SELECT c.principal_user_id,c.principal_session_id
 FROM private.burimunsi_managed_admin_snapshot() c
 JOIN app.admin_grants g ON g.user_id=c.principal_user_id AND g.permission='sms.read'
 JOIN app.admin_account_role_capabilities cap ON cap.role=c.shared_role AND cap.permission=g.permission`;

export async function currentNativeBinding(sql,groupId,installationId){
 const rows=await sql.unsafe(NATIVE_CURRENT_BINDING_SQL,[groupId,installationId]);
 requireThat(rows.length<=1,'gateway_unavailable',403);const r=rows[0];
 return r?{id:r.id,groupId,installationId:r.installation_id,
  active:r.enabled===true&&r.status==='active'&&r.revoked_at===null&&integer(r.version)===integer(r.binding_version)}:null;
}
function metadata(row,groupId){
 integrity(row.collection_id===groupId&&['received','under_review','rejected','linked'].includes(row.status));
 requireId(row.id);
 // This is the server's receipt/upload time. A naive device/service-centre time
 // is never given an invented zone or substituted for the source's actual text.
 integrity(typeof row.created_at==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(row.created_at)&&
  Number.isFinite(Date.parse(row.created_at))&&new Date(row.created_at).toISOString()===row.created_at);
 integrity(typeof row.duplicate==='boolean');
 if(row.transaction_id!==null)requireId(row.transaction_id);
 return {id:row.id,groupId,sender:'',preview:'',at:row.created_at,
  state:row.status==='rejected'?'rejected':row.duplicate?'duplicate':'synced',transactionId:row.transaction_id};
}
const stateSql="CASE WHEN r.status='rejected' THEN 'rejected' WHEN coalesce(links.duplicate,false) THEN 'duplicate' ELSE 'synced' END";

/** Closed canonical reader over the same admitted Collect database and storage.
 * Metadata never decrypts source text. Explicit disclosure has two short guarded
 * SQL phases around protected object I/O; no financial transaction spans I/O.
 * Only canonical audit retains the reason. No plaintext/cache/request journal is
 * created, and no unreasoned GET can disclose original content.
 */
export class PostgresCollectSourceReader {
 constructor({authority,custody,storageWitnesses,clock=()=>Date.now()}){
  requirePort(authority,['read','write','session','assertOwned']);
  requirePort(authority.db,['prepare','statement']);requireId(authority.groupId);
  requireThat(custody instanceof PostgresPostingCustody&&storageWitnesses instanceof PostgresStorageWitnesses&&
   custody.storageWitnesses===storageWitnesses&&custody.db===authority.db&&custody.groupId===authority.groupId,
   'collect_adapter_required',503);
  Object.assign(this,{authority,db:authority.db,groupId:authority.groupId,custody,storageWitnesses,clock});
 }
 scope(group){requireThat(group===this.groupId,'access_denied',403);}
 async metadataAuthority(sql,expected){
  requireRequestId(expected?.id);requireRequestId(expected?.sessionId);
  const actor=await this.authority.session(sql,{id:expected.sessionId});
  requireThat(actor?.id===expected.id&&actor.sessionId===expected.sessionId,'session_unavailable',401);
  authorize(actor,this.groupId,'sms.read',{now:this.clock(),binding:await currentNativeBinding(sql,this.groupId,actor.installationId)});
  const rows=await sql.unsafe(hasPhonePinContext(this.db)?
    'SELECT principal_user_id,native_session_id AS principal_session_id FROM private.burimunsi_pin_context()':NATIVE_METADATA_AUTH_SQL);
  requireThat(rows.length===1&&rows[0].principal_user_id===actor.principalUserId&&
   rows[0].principal_session_id===actor.principalSessionId,'access_denied',403);
  await this.authority.assertOwned();
 }
 async revision(sql,group,actor){
  this.scope(group);await this.metadataAuthority(sql,actor);
  const rows=await sql.unsafe(NATIVE_SOURCE_SQL+' ORDER BY r.id LIMIT 100001',[group]);
  requireThat(rows.length<=100000,'snapshot_limit',413);
  rows.forEach(row=>metadata(row,group));await this.authority.assertOwned();return sha256(canonicalJson(Array.from(rows)));
 }
 async page(sql,{groupId,kind,q,filter,limit,after},actor){
  this.scope(groupId);requireThat(kind==='sms','invalid_list');
  requireThat(typeof q==='string'&&q.length<=80&&Number.isInteger(limit)&&limit>=1&&limit<=100&&
   ['all','queued','duplicate','synced','rejected'].includes(filter),'invalid_query');
  const offset=after?.offset??0;requireThat(Number.isSafeInteger(offset)&&offset>=0&&offset<=100000,'invalid_cursor');
  const base=NATIVE_SOURCE_SQL+" AND position(lower($2) in lower(r.id))>0"+
   (filter==='all'?'':filter==='queued'?' AND false':` AND ${stateSql}=$3`);
  const values=filter==='all'||filter==='queued'?[groupId,q]:[groupId,q,filter];
  await this.metadataAuthority(sql,actor);
  const total=integer((await sql.unsafe('SELECT count(*) AS total FROM ('+base+') counted',values))[0]?.total);
  const rows=await sql.unsafe(base+` ORDER BY r.created_at DESC,r.id ASC LIMIT $${values.length+1} OFFSET $${values.length+2}`,
   [...values,limit,offset]);
  requireThat(rows.length===Math.max(0,Math.min(limit,total-offset)),'invalid_page',503);
  await this.authority.assertOwned();return {items:rows.map(row=>metadata(row,groupId)),totalCount:total,
   after:offset+rows.length<total?{offset:offset+rows.length}:null,asOf:new Date(this.clock()).toISOString()};
 }
 async listingSnapshot(sql,groupId,actor){
  this.scope(groupId);await this.metadataAuthority(sql,actor);
  // Same retained association/custody boundary as ordinary SMS metadata.
  // This path never reads/decrypts a body and never grants bulk disclosure.
  const rows=await sql.unsafe(NATIVE_SOURCE_SQL+' ORDER BY r.id LIMIT 100001',[groupId]);
  requireThat(rows.length<=100000,'snapshot_limit',413);
  const entries=rows.map(row=>{const item=metadata(row,groupId);return {item,at:canonicalListingInstant(item.at),search:listingText(item.id)};});
  await this.authority.assertOwned();return {entries,asOf:new Date(this.clock()).toISOString()};
 }
 detail(){throw new BuriError('review_reason_required',400);}
 async guard(sql,canonical,permission){
  requireThat(['sms.read','sms.reveal'].includes(permission),'collect_adapter_required',503);
  const id=crypto.randomUUID();
  const statements=[this.db.prepare(`INSERT INTO app.mutation_guards
   (id,user_id,session_id,now_seconds,collection_id,permission,minimum_assurance,expected_mfa_at,fresh_seconds)
   VALUES(?,?,?,?,?,?,?,?,?)`).bind(id,canonical.userId,canonical.sessionId,canonical.now,
    canonical.authMethod==='phone_pin'?this.groupId:null,permission,canonical.authMethod==='phone_pin'?null:2,canonical.mfa,300),
   this.db.prepare('DELETE FROM app.mutation_guards WHERE id=?').bind(id)];
  for(const statement of statements){
   await this.authority.assertOwned();let result;
   try{result=await this.db.statement(sql,statement);}catch(error){
    if(['request_not_admitted','application_fenced','application_fence_unavailable'].includes(error?.code))throw error;
    throw new BuriError('access_denied',403);
   }
   integrity(result?.success===true&&result.meta?.changes===1);
  }
 }
 async current(sql,selector){
  const actor=await this.authority.session(sql,{id:selector.sessionId});
  requireThat(actor?.id===selector.id&&actor.sessionId===selector.sessionId,'session_unavailable',401);
  authorize(actor,this.groupId,'sms.read',{now:this.clock(),binding:await currentNativeBinding(sql,this.groupId,actor?.installationId)});
  const canonical=await canonicalManagedActor(this.authority,sql);
  requireThat(actor.principalUserId===canonical.userId&&actor.principalSessionId===canonical.sessionId,'access_denied',403);
  await this.guard(sql,canonical,'sms.read');await this.guard(sql,canonical,'sms.reveal');
  return {canonical,identity:{actor:copy(actor),principal:canonical.userId,session:canonical.sessionId,mfa:canonical.mfa}};
 }
 async source(sql,id){
  const rows=await sql.unsafe(NATIVE_SOURCE_SQL+' AND r.id=$2',[this.groupId,id]);
  requireThat(rows.length===1,'record_unavailable',404);const row=copy(rows[0]);metadata(row,this.groupId);
  integrity(row.object_key==='sms/'+id&&row.evidence_level==='client_received'&&
   /^[a-f0-9]{64}$/.test(row.object_sha256)&&/^[a-f0-9]{64}$/.test(row.body_sha256)&&
   integer(row.size_bytes)>0&&integer(row.size_bytes)<=262144);
  return row;
 }
 target(row){return {ownerId:row.owner_user_id,purpose:'sms_receipt',entityId:row.id,
  plaintextSha256:row.object_sha256,aad:`sms:${row.id}:${row.object_sha256}`};}
 async namespace(sql){
  const rows=await sql.unsafe('SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
  integrity(rows.length===1&&equal(rows[0],this.custody.namespace));return copy(rows[0]);
 }
 async revealSms(selector,input){
  const request=copy(input);this.scope(request.groupId);requireId(request.id);
  requireRequestId(request.requestId);requireRequestId(selector.id);requireRequestId(selector.sessionId);
  const reason=typeof request.reason==='string'?request.reason.trim():'';
  requireThat([...reason].length>=8&&[...reason].length<=1000&&!/[\u0000-\u001f\u007f-\u009f]/.test(reason),'review_reason_required',400);
  let binding=null,plaintext;
  try{
   const initial=await this.authority.write(async sql=>{
    const current=await this.current(sql,selector),row=await this.source(sql,request.id),namespace=await this.namespace(sql);
    const journal=await this.custody.journal(sql,row.object_key,this.target(row));
    binding={kind:'disclosure',groupId:this.groupId,requestId:request.requestId,identity:current.identity,source:row};
    const plan=await this.storageWitnesses.stage(binding,[{key:row.object_key,journal}]);
    return {identity:current.identity,row,namespace,journal,plan};
   });
   // Actual protected provider retrieval and decryption occur after the SQL
   // callback returned. Only ciphertext is held by the private witness store.
   await this.storageWitnesses.prefetch(initial.plan);
   const sealed=await this.storageWitnesses.sealed(binding,initial.row.object_key,initial.journal);
   plaintext=await this.custody.decrypt(sealed,this.target(initial.row).aad);
   integrity(plaintext instanceof Uint8Array&&plaintext.length===integer(initial.row.size_bytes)&&
    await bytesHash(plaintext)===initial.row.object_sha256);
   const payload=JSON.parse(dec.decode(plaintext));
   integrity(payload&&typeof payload==='object'&&!Array.isArray(payload)&&typeof payload.raw_sender==='string'&&
    payload.raw_sender.trim().length>0&&payload.raw_sender.length<=96&&
    !/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(payload.raw_sender)&&
    typeof payload.raw_body==='string'&&payload.raw_body.length>0&&payload.raw_body.length<=16384&&
    !payload.raw_body.includes('\0')&&enc.encode(payload.raw_body).length<=16384&&await sha256(payload.raw_body)===initial.row.body_sha256);
   await this.authority.assertOwned();
   const response=await this.authority.write(async sql=>{
    const current=await this.current(sql,selector);
    requireThat(equal(current.identity,initial.identity),'access_denied',403);
    const row=await this.source(sql,request.id),namespace=await this.namespace(sql);
    requireThat(equal(row,initial.row)&&equal(namespace,initial.namespace),'source_scope_changed',409);
    const journal=await this.custody.journal(sql,row.object_key,this.target(row));
    integrity(this.custody.sameJournal(journal,initial.journal));
    await this.storageWitnesses.sealed(binding,row.object_key,journal);
    const result=await this.db.statement(sql,auditStatement({DB:this.db},current.canonical,
     'sms.capture.revealed','sms_receipt',row.id,{reason,purpose:current.canonical.authMethod==='phone_pin'?'native_sms_review':'operator_review',
      purpose_source:current.canonical.authMethod==='phone_pin'?'app_action':'operator_action',source_kind:'capture',collection_id:this.groupId,
      native_actor_id:selector.id,native_session_id:selector.sessionId,owner_user_id:row.owner_user_id,
      source_sha256:row.body_sha256,object_sha256:row.object_sha256},request.requestId));
    integrity(result?.success===true&&result.meta?.changes===1);
    const final=await this.current(sql,selector);requireThat(equal(final.identity,initial.identity),'access_denied',403);
    return {id:row.id,groupId:this.groupId,sender:payload.raw_sender,at:row.created_at,
     rawBody:payload.raw_body,transactionId:row.transaction_id};
   });
   // Unknown/failed audit COMMIT never produces plaintext success.
   await this.authority.assertOwned();return response;
  }finally{
   plaintext?.fill(0);if(binding)this.storageWitnesses.forget(binding);
  }
 }
}
