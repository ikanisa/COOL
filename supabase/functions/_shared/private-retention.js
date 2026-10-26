import catalog from '../../retention-inventory.json' with {type:'json'};
import {ApiError,digest,stableJson,id} from './domain/core.js';
import {MEMBER_REALTIME_CLASS,memberRealtimeRetentionIdentity,inventoryMemberRealtime,memberRealtimeRetentionGuards} from './member-realtime-retention.js';

const fail=code=>{throw new ApiError(409,code,'Retention inventory or approval changed. Obtain a current reviewed decision.');};
export const privateRetentionClasses=Object.freeze(catalog.classes.map(entry=>entry.name));
export const sharedFenceRetentionClasses=Object.freeze(catalog.classes.filter(entry=>['shared_fence','shared_realtime'].includes(entry.scope)).map(entry=>entry.name));
const ownKeys=`SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=?
 UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=?
 UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=?
 UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=?
 UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=?
 UNION SELECT object_key FROM app.upload_objects WHERE user_id=?`;
function selection(entry,subject){
 const mapped='SELECT auth_user_id FROM private.auth_principal_links WHERE user_id=?';
 switch(entry.scope){
  case 'principal':return {where:'r.user_id=?',args:[subject]};
  case 'admin_invitation':return {where:'r.principal_id=? OR r.actor_principal_id=?',args:[subject,subject]};
  case 'admin_email':return {where:'r.principal_id=?',args:[subject]};
  case 'otp':return {where:`r.privacy_expected_user_id=? OR r.privacy_verified_user_id=? OR r.identity_value IN(SELECT email FROM app.users WHERE id=? UNION SELECT phone FROM app.users WHERE id=? UNION SELECT a.email FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id WHERE l.user_id=?)`,args:[subject,subject,subject,subject,subject]};
  case 'bff':return {where:`r.auth_user_id IN(${mapped})`,args:[subject]};
  case 'mfa':return {where:`r.user_id IN(${mapped})`,args:[subject]};
  case 'google':return {where:`r.flow_id IN(SELECT f.id FROM app.auth_google_flows f WHERE f.email IN(SELECT email FROM app.users WHERE id=? UNION SELECT a.email FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id WHERE l.user_id=?) OR f.google_subject IN(SELECT subject FROM app.auth_google_identities WHERE user_id=?))`,args:[subject,subject,subject]};
  case 'namespace':return {where:'true',args:[]};
  case 'storage':return {where:`r.object_key IN(${ownKeys})`,args:Array(6).fill(subject)};
  case 'attempt':return {where:`r.operation_id IN(SELECT operation_id FROM private.storage_put_intents WHERE object_key IN(${ownKeys}))`,args:Array(6).fill(subject)};
  case 'metadata_view':return {where:`r.object_key IN(${ownKeys})`,args:Array(6).fill(subject)};
  default:fail('privacy_retention_unknown_private_class');
 }
}
const mutable={
 'private.admin_email_operations':['send_claim','verification_state','verification_operation_id','verify_receipts','cleanup_state','cleanup_claim','verified_session_id','verified_amr_at'],
 'private.storage_put_intents':['state','delete_tombstone','last_outcome','updated_at'],
 'private.storage_payload_reservations':['sealed_body','cleared_at'],
 'private.storage_delete_intents':['state','last_outcome','absence_proof','committed_at']
};
function expressions(entry){
 const row='to_jsonb(r)',minus=mutable[entry.relation]??[];
 const identity=minus.length?`${row}-ARRAY[${minus.map(x=>"'"+x+"'").join(',')}]`:row;
 const key=entry.relation==='private.auth_principal_links'?'r.auth_user_id::text':entry.relation==='private.bff_sessions'?'r.token_hash':entry.relation==='private.managed_mfa_proofs'?'r.session_id::text':entry.relation==='private.managed_phone_verifications'||entry.relation==='private.admin_email_operations'?'r.challenge_id':entry.relation==='private.admin_sensitive_email_proofs'?'r.id::text':entry.relation==='private.google_flow_context'?'r.flow_id':entry.relation==='private.admin_invitation_attempts'?'r.request_id::text':entry.relation==='private.storage_namespace'?"'singleton'":entry.relation==='private.storage_upload_attempts'?'r.id::text':entry.relation.includes('storage_')||entry.relation==='private.object_metadata'?'r.object_key':'r.id';
 const hash=value=>`encode(sha256(convert_to((${value})::text,'UTF8')),'hex')`;
 let lifecycle="'{}'::jsonb";
 if(entry.relation==='private.supabase_otp_challenges')lifecycle="jsonb_build_object('active',r.consumed_at IS NULL AND r.expires_at>app.unixepoch() AND r.delivery_status IN('reserved','accepted','unknown') AND(r.privacy_mode IS NULL OR r.privacy_cancelled_at IS NULL),'unresolved',r.privacy_mode IS NOT NULL AND(r.privacy_verification_state IN('verifying','unconfirmed') OR r.privacy_cleanup_state IN('claimed','unconfirmed')))";
 if(entry.relation==='private.admin_email_operations')lifecycle="jsonb_build_object('state',r.verification_state,'cleanup',r.cleanup_state,'active',EXISTS(SELECT 1 FROM private.supabase_otp_challenges q WHERE q.id=r.challenge_id AND q.consumed_at IS NULL AND q.expires_at>app.unixepoch() AND q.delivery_status IN('reserved','accepted','unknown')),'unresolved',r.verification_state IN('verifying','unconfirmed') OR r.cleanup_state IN('claimed','unconfirmed') OR(r.mode='reauth' AND r.verification_state='verified' AND r.cleanup_state='not_started') OR(r.send_claim IS NOT NULL AND EXISTS(SELECT 1 FROM private.supabase_otp_challenges q WHERE q.id=r.challenge_id AND q.delivery_status='reserved')))";
 if(entry.relation==='private.admin_sensitive_email_proofs')lifecycle="jsonb_build_object('immutable',true)";
 if(entry.relation==='private.admin_invitation_attempts')lifecycle="jsonb_build_object('state',r.state,'active',r.replayed_request_id IS NULL AND r.state IN('reserved','dispatching','unknown'),'alias',r.replayed_request_id IS NOT NULL)";
 if(entry.relation==='private.storage_put_intents')lifecycle="jsonb_build_object('state',r.state,'tombstone',r.delete_tombstone,'unresolved',r.upload_unresolved,'active',r.active_attempt IS NOT NULL,'sha256',r.sha256)";
 if(entry.relation==='private.storage_payload_reservations')lifecycle="jsonb_build_object('sealed',r.sealed_body IS NOT NULL,'cleared',r.cleared_at IS NOT NULL,'sha256',r.plaintext_sha256)";
 if(entry.relation==='private.storage_delete_intents')lifecycle="jsonb_build_object('state',r.state,'absence',coalesce(r.absence_proof @> '{\"headStatus\":404,\"getStatus\":404,\"bucketVerified\":true}'::jsonb,false),'sha256',r.expected_sha256)";
 return {rowHash:hash(row),identityHash:hash(identity),keyHash:hash(key),lifecycle};
}
function rowQuery(entry,subject){
 const scoped=selection(entry,subject),e=expressions(entry);
 return {sql:`SELECT ${e.keyHash} AS key_sha256,${e.rowHash} AS row_sha256,${e.identityHash} AS identity_sha256,${e.lifecycle} AS lifecycle FROM ${entry.relation} r WHERE ${scoped.where} ORDER BY ${e.keyHash} LIMIT ${catalog.limits.rows_per_class+1}`,args:scoped.args};
}
async function record(rows){
 if(rows.length>catalog.limits.rows_per_class)fail('privacy_retention_private_inventory_limit');
 return {status:'observed',count:rows.length,sha256:await digest(stableJson(rows)),rows};
}
const all=async(env,sql,args=[])=>(await env.DB.prepare(sql).bind(...args).all()).results;
const privateSchemaSql=`SELECT c.relname::text AS name,c.relkind::text AS kind,
  (SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text,',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) AS columns,
  (SELECT string_agg(pg_get_constraintdef(x.oid),';' ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid) AS constraints,
  (SELECT string_agg(pg_get_triggerdef(t.oid),';' ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal) AS triggers
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relkind IN('r','p','v') ORDER BY c.relname`;
const stoppedClass='private:collect_fence_stopped_admissions';
export async function privateRetentionCatalogIdentity(env){
 const observed=await all(env,privateSchemaSql);
 const expected=catalog.classes.filter(x=>x.relation.startsWith('private.')).map(x=>x.relation.slice(8)).sort();
 const names=stableJson(observed.map(x=>x.name)),current=names===stableJson(expected);
 // SQL11 remains an explicitly qualified historical application prefix. Only
 // the exact SQL14 addition may be absent there; every other relation remains
 // mandatory. Both profiles retain a blocked, unmapped stopped-work class.
 const legacy=names===stableJson(expected.filter(name=>name!==stoppedClass.slice(8)));
 if(!current&&!legacy)fail('privacy_retention_unknown_private_class');
 const managed=await all(env,'SELECT private.retention_managed_inventory(?) AS inventory',[null]);
 const schema=managed[0]?.inventory?.schema;
 if(!schema||managed[0].inventory.contract_version!==1)fail('privacy_retention_managed_inventory_unavailable');
 const memberRealtimeIdentity=await memberRealtimeRetentionIdentity(env);
 const definition=(await all(env,"SELECT encode(sha256(convert_to(pg_get_functiondef('private.retention_managed_inventory(text)'::regprocedure),'UTF8')),'hex') AS sha256"))[0].sha256;
 return {contract_version:1,schema_profile:current?'stopped_admission14':'admin_email11',catalog_sha256:await digest(stableJson(catalog)),schema_sha256:await digest(stableJson({private:observed,managed:schema,managed_helper:definition,member_realtime:memberRealtimeIdentity})),private_schema:observed,managed_schema:schema,managed_helper_sha256:definition,member_realtime_identity:memberRealtimeIdentity,classes:privateRetentionClasses};
}
export async function inventoryPrivateRetention(env,subject){
 if(typeof subject!=='string'||!subject.length||subject.length>200)fail('privacy_retention_subject_invalid');
 const identity=await privateRetentionCatalogIdentity(env);
 // These are the projected opaque descriptors returned by rowQuery and the
 // validated managed inventory. Keep the dynamic dictionary in the exported
 // return type; it is not an empty-object contract or a replacement inventory.
 /** @type {Record<string,{status:string,count:number,sha256:string,rows:Array<{key_sha256:string,row_sha256:string,identity_sha256?:string,lifecycle:{sealed?:boolean,cleared?:boolean,active?:boolean,unresolved?:boolean,tombstone?:boolean,absence?:boolean,state?:string,sha256?:string,catalog_rows?:number,[key:string]:unknown},[key:string]:unknown}>}>} */
 const classes={};
 for(const entry of catalog.classes.filter(x=>!['managed','managed_realtime','shared_fence','shared_realtime'].includes(x.scope))){const q=rowQuery(entry,subject);classes[entry.name]=await record(await all(env,q.sql,q.args));}
 // Shared opaque work has no retained subject mapping. No raw-table SELECT,
 // global-empty claim or volatile all-admissions hash belongs in a personal
 // snapshot. These explicit unmapped classes always require blocked disposition.
 for(const name of sharedFenceRetentionClasses)classes[name]={status:'unmapped',count:0,sha256:await digest(stableJson([])),rows:[]};
 const managed=(await all(env,'SELECT private.retention_managed_inventory(?) AS inventory',[subject]))[0]?.inventory;
 if(!managed||managed.contract_version!==1||stableJson(managed.schema)!==stableJson(identity.managed_schema))fail('privacy_retention_managed_inventory_changed');
 for(const name of ['managed:auth','managed:storage']){
  const value=managed.classes?.[name];
  if(!value||!['observed','unmapped','unavailable'].includes(value.status)||!Number.isSafeInteger(value.count)||value.count<0||!Array.isArray(value.rows)||value.rows.length>catalog.limits.rows_per_class)fail('privacy_retention_managed_inventory_invalid');
  classes[name]={...value,sha256:await digest(stableJson(value.rows))};
 }
 classes[MEMBER_REALTIME_CLASS]=await inventoryMemberRealtime(env,subject,identity.member_realtime_identity);
 const unresolved=classes['private:supabase_otp_challenges'].rows.some(r=>r.lifecycle.active||r.lifecycle.unresolved)||classes['private:admin_email_operations'].rows.some(r=>r.lifecycle.active||r.lifecycle.unresolved)||classes['private:admin_invitation_attempts'].rows.some(r=>r.lifecycle.active)||classes['private:storage_put_intents'].rows.some(r=>r.lifecycle.unresolved||r.lifecycle.active||r.lifecycle.state==='pending');
 const result={contract_version:1,catalog_sha256:identity.catalog_sha256,schema_sha256:identity.schema_sha256,private_schema:identity.private_schema,managed_schema:identity.managed_schema,managed_helper_sha256:identity.managed_helper_sha256,member_realtime_identity:identity.member_realtime_identity,classes,unlinked_identifiers:'unverified',external_copy_disposition:'blocked',in_flight_unresolved:unresolved};
 if(new TextEncoder().encode(stableJson(result)).length>catalog.limits.inventory_bytes)fail('privacy_retention_private_inventory_limit');
 return result;
}

export function assertPrivateRetentionPolicy(policy,identity){
 const decision=policy?.copy_inventory;
 if(!decision||Object.keys(decision).sort().join(',')!=='bff_access_revocation,catalog_sha256,contract_version,unmapped_copies'||decision.contract_version!==1||decision.catalog_sha256!==identity.catalog_sha256||decision.unmapped_copies!=='blocked'||!['allow','block'].includes(decision.bff_access_revocation))fail('privacy_retention_private_policy_unapproved');
 for(const name of privateRetentionClasses)if(!catalog.policy_actions.includes(policy.rules?.[name]?.action))fail('privacy_retention_private_disposition_unapproved');
 if(policy.rules?.[MEMBER_REALTIME_CLASS]?.action!=='blocked')fail('privacy_retention_realtime_unapproved');
 for(const name of ['private:admin_email_operations','private:admin_sensitive_email_proofs'])if(policy.rules?.[name]?.action!=='blocked')fail('privacy_retention_admin_email_unapproved');
 for(const name of sharedFenceRetentionClasses)if(policy.rules?.[name]?.action!=='blocked')fail('privacy_retention_shared_fence_unapproved');
 for(const name of catalog.unresolved_external_classes)if(policy.rules?.[name]?.action!=='blocked')fail('privacy_retention_unmapped_copies_unapproved');
}

// Recompute the exact same bounded row fingerprints in the effect transaction.
// No private row, token, ciphertext or provider value enters a retained plan.
/** @param {*} env @param {*} plan @param {*} snapshot @param {string} className
 * @param {{erasureObjects?:Array<{key:string,key_sha256:string}>}} options */
export function privateRetentionGuards(env,plan,snapshot,className,{erasureObjects=[]}={}){
 const inventory=snapshot.summary.private_inventory;if(!inventory)fail('privacy_retention_private_inventory_missing');
 for(const object of erasureObjects)if(!/^[a-f0-9]{64}$/.test(object.key_sha256??'')||!snapshot.summary.objects.some(x=>x.key===object.key&&x.class_name==='r2:upload_objects'&&x.owner_user_id===plan.subject_id))fail('privacy_retention_private_effect_unapproved');
 const excluded=erasureObjects.map(x=>x.key_sha256),placeholders=excluded.map(()=>'?').join(','),effectClasses=new Set(['private:storage_put_intents','private:storage_payload_reservations','private:storage_delete_intents','private:storage_objects','private:object_metadata']);
 const statements=[...memberRealtimeRetentionGuards(env,plan,className,inventory.classes[MEMBER_REALTIME_CLASS],inventory.member_realtime_identity)];
 for(const entry of catalog.classes.filter(x=>!['managed','managed_realtime','shared_fence','shared_realtime'].includes(x.scope))){
  const q=rowQuery(entry,plan.subject_id),expected=inventory.classes[entry.name],ignore=effectClasses.has(entry.name)&&excluded.length>0;
  const query=ignore?`SELECT * FROM (${q.sql}) scoped WHERE key_sha256 NOT IN(${placeholders})`:q.sql;
  const rows=ignore?expected.rows.filter(x=>!excluded.includes(x.key_sha256)):expected.rows;
  // PostgreSQL JSONB canonical equality avoids serialization differences
  // between the SQL adapter and the retained opaque row descriptors.
  statements.push(env.DB.prepare(`INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,CASE WHEN coalesce((SELECT jsonb_agg(to_jsonb(q) ORDER BY q.key_sha256) FROM (${query}) q),'[]'::jsonb)=?::jsonb THEN 1 ELSE 0 END`).bind(id(),plan.id,className,...q.args,...(ignore?excluded:[]),rows));
 }
 const expectedManaged=Object.fromEntries(['managed:auth','managed:storage'].map(name=>[name,{...inventory.classes[name],sha256:undefined}]));
 if(excluded.length){expectedManaged['managed:storage'].rows=expectedManaged['managed:storage'].rows.filter(x=>!excluded.includes(x.key_sha256));expectedManaged['managed:storage'].count=expectedManaged['managed:storage'].rows.reduce((n,row)=>n+row.lifecycle.catalog_rows,0);}
 const managedQuery=excluded.length?`WITH observed AS(SELECT private.retention_managed_inventory(?)->'classes' AS classes),filtered AS(SELECT classes,coalesce((SELECT jsonb_agg(item ORDER BY item->>'key_sha256') FROM jsonb_array_elements(classes->'managed:storage'->'rows') item WHERE item->>'key_sha256' NOT IN(${placeholders})),'[]'::jsonb) AS rows FROM observed) SELECT jsonb_set(jsonb_set(classes,'{managed:storage,rows}',rows),'{managed:storage,count}',to_jsonb(coalesce((SELECT sum((item->'lifecycle'->>'catalog_rows')::bigint) FROM jsonb_array_elements(rows) item),0))) FROM filtered`:`SELECT private.retention_managed_inventory(?)->'classes'`;
 statements.push(env.DB.prepare(`INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,CASE WHEN (${managedQuery})=?::jsonb THEN 1 ELSE 0 END`).bind(id(),plan.id,className,plan.subject_id,...excluded,expectedManaged));
 statements.push(env.DB.prepare(`INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,CASE WHEN (SELECT jsonb_agg(to_jsonb(q) ORDER BY q.name) FROM (${privateSchemaSql}) q)=?::jsonb AND(private.retention_managed_inventory(NULL)->'schema')=?::jsonb AND encode(sha256(convert_to(pg_get_functiondef('private.retention_managed_inventory(text)'::regprocedure),'UTF8')),'hex')=? THEN 1 ELSE 0 END`).bind(id(),plan.id,className,inventory.private_schema,inventory.managed_schema,inventory.managed_helper_sha256));
 for(const object of erasureObjects)statements.push(env.DB.prepare(`INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,CASE WHEN encode(sha256(convert_to(?,'UTF8')),'hex')=? THEN 1 ELSE 0 END`).bind(id(),plan.id,className,object.key,object.key_sha256));
 return statements;
}

/** @param {*} original @param {*} current
 * @param {{approvedErasureObjects?:Array<{key_sha256:string,sha256:string,absent:boolean,committed:boolean,pending?:boolean}>,allowBffRevocation?:boolean}} options */
export function assertPrivateRetentionSource(original,current,{approvedErasureObjects=[],allowBffRevocation=false}={}){
 if(!original||!current||original.catalog_sha256!==current.catalog_sha256||original.schema_sha256!==current.schema_sha256||stableJson(Object.keys(original.classes).sort())!==stableJson(Object.keys(current.classes).sort()))fail('privacy_retention_private_scope_changed');
 const erased=new Map(approvedErasureObjects.map(x=>[x.key_sha256,x]));
 for(const name of privateRetentionClasses){
  const before=original.classes[name],after=current.classes[name];
  if(stableJson(before)===stableJson(after))continue;
  if(name==='private:bff_sessions'&&allowBffRevocation&&after.status==='observed'&&after.count===0)continue;
  const mutableStorage=['private:storage_put_intents','private:storage_payload_reservations','private:storage_delete_intents','private:storage_objects','private:object_metadata','managed:storage'];
  if(!mutableStorage.includes(name)||before.status!==after.status)fail('privacy_retention_private_scope_changed');
  const oldRows=new Map(before.rows.map(r=>[r.key_sha256,r])),newRows=new Map(after.rows.map(r=>[r.key_sha256,r]));
  for(const key of new Set([...oldRows.keys(),...newRows.keys()])){
   const old=oldRows.get(key),now=newRows.get(key);if(stableJson(old)===stableJson(now))continue;
   const effect=erased.get(key);if(!effect)fail('privacy_retention_private_scope_changed');
   if(name==='private:storage_objects'||name==='private:object_metadata'||name==='managed:storage'){
    if(!old||now||!effect.absent||!(effect.committed||name==='managed:storage'&&effect.pending))fail('privacy_retention_private_object_changed');
   }else if(name==='private:storage_put_intents'){
    if(!old||!now||old.identity_sha256!==now.identity_sha256||!now.lifecycle.tombstone||now.lifecycle.active||now.lifecycle.unresolved||now.lifecycle.sha256!==effect.sha256||!['committed','pending','erased'].includes(now.lifecycle.state)||(now.lifecycle.state==='erased'&&!effect.committed))fail('privacy_retention_private_object_changed');
   }else if(name==='private:storage_payload_reservations'){
    if(!old||!now||old.identity_sha256!==now.identity_sha256||now.lifecycle.sealed||!now.lifecycle.cleared||!effect.absent||!effect.committed)fail('privacy_retention_private_object_changed');
   }else if(name==='private:storage_delete_intents'){
    if(!now||old&&old.identity_sha256!==now.identity_sha256||now.lifecycle.sha256!==effect.sha256||!['pending','committed'].includes(now.lifecycle.state)||now.lifecycle.state==='committed'&&(!now.lifecycle.absence||!effect.absent||!effect.committed))fail('privacy_retention_private_object_changed');
   }
  }
 }
}

// An existing immutable source send-start and its exact original object bind
// every permitted journal lifecycle change. Neither caller-provided keys nor
// an absent HEAD response alone qualify a private-copy change.
export async function privateErasureObjects(original,current,effects){
 const allowed=[];
 for(const effect of effects){
  const before=original.objects.find(o=>o.key===effect.object_key),after=current.objects.find(o=>o.key===effect.object_key);
  if(!before||!after||before.class_name!=='r2:upload_objects'||before.owner_user_id!==original.subject_id||before.version!==effect.object_version||before.body_sha256!==effect.source_sha256)continue;
  const key=await digest(effect.object_key),put=current.private_inventory.classes['private:storage_put_intents'].rows.find(r=>r.key_sha256===key),deletion=current.private_inventory.classes['private:storage_delete_intents'].rows.find(r=>r.key_sha256===key);
  const committed=put?.lifecycle.state==='erased'&&put.lifecycle.tombstone&&!put.lifecycle.active&&!put.lifecycle.unresolved&&put.lifecycle.sha256===effect.source_sha256&&deletion?.lifecycle.state==='committed'&&deletion.lifecycle.absence&&deletion.lifecycle.sha256===effect.source_sha256;
  // Only the managed provider mirror may disappear before journal commit.
  // Its dual-absence witness must bind the original effect's exact operation;
  // protected metadata/spool removal still requires the committed journal.
  const pending=after.pending_erasure?.absence_verified===true&&after.pending_erasure.operation_id==='retention:'+effect.task_id+':'+before.record_id&&after.pending_erasure.source_sha256===effect.source_sha256&&put?.lifecycle.state==='committed'&&put.lifecycle.tombstone&&!put.lifecycle.active&&!put.lifecycle.unresolved&&put.lifecycle.sha256===effect.source_sha256&&deletion?.lifecycle.state==='pending'&&deletion.lifecycle.sha256===effect.source_sha256;
  allowed.push({key_sha256:key,sha256:effect.source_sha256,absent:after.present===false,committed:!!committed,pending:!!pending});
 }
 return allowed;
}

export async function privateRetentionAfterAccess(inventory,policy){
 if(inventory.classes['private:bff_sessions'].count&&policy.copy_inventory?.bff_access_revocation!=='allow')fail('privacy_retention_bff_revocation_unapproved');
 return {...inventory,classes:{...inventory.classes,'private:bff_sessions':await record([])}};
}
export function privateCopyRetainable(inventory,name){return inventory?.classes?.[name]?.status==='observed';}
