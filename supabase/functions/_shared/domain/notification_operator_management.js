import {requireFreshAdminEmail} from './admin_email_policy.js';
import {ApiError,json,readJson,uuid,integer,id,digest,stableJson,now} from './core.js';
import {adminAccountSession,adminCanonicalActor,accountDatabase,validateAdminOrigin} from './admin_accounts.js';
import {OWNER_EMAIL} from './admin_account_support/security.js';
import {mutation,retainedResponse} from './mutations.js';
import {enqueueAssistedSms,assistedSmsSourceCapabilities,assistedSmsLivePaymentSql} from './notification_operator.js';
const template='collect.recorded_contribution.v1';
const marker={contract_version:1,scope:'owner_receipt_sms_configuration',legal_release_approved:false,provider_approved:false,delivery_confirmed:false};
const options={permission:'assisted_sms.manage',minimumAssurance:2,freshSeconds:300,entityType:'assisted_sms_policy'};
function fields(body,allowed){if(!body||Array.isArray(body)||Object.keys(body).some(k=>!allowed.includes(k)))throw new ApiError(400,'invalid_request','Request contains unsupported fields.');}
async function owner(request,base,permission='assisted_sms.manage'){
 base={...base,DB:base.DB.withSession?base.DB.withSession('first-primary'):base.DB};
 validateAdminOrigin(request,base);const account=await adminAccountSession(request,base);
 if(account.role!=='owner'||account.email!==OWNER_EMAIL)throw new ApiError(403,'owner_required','Only the main administrator can configure receipt SMS.');
 if(!account.permissions.includes(permission))throw new ApiError(403,'permission_required','Receipt SMS configuration is unavailable.');
 requireFreshAdminEmail(account);
 const env=accountDatabase(base,account,permission,{owner:true,mfa:true,fresh:true}),actor=await adminCanonicalActor(request,env,account,permission);return {env,actor,account};
}
async function query(ctx,sql,...args){return (await ctx.env.DB.batch([ctx.env.DB.prepare(sql).bind(...args)]))[0].results;}
function gate(env,condition,args,key=id()){return [env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN ${condition} THEN 1 ELSE 0 END)`).bind(key,...args),env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(key)];}
function failure(error){
 if(error instanceof ApiError)return error;
 if(/recent_email_(?:verification|sign_in)_required/.test(String(error?.message??error)))return new ApiError(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');const text=String(error?.message??error);
 if(/admin_account_authority|admin_account_guards|session_changed|permission_denied|mfa_required/.test(text))return new ApiError(403,'sms_authority_changed','Your account access changed. Sign in and verify again.');
 if(/admin_bridge_state|sms_policy_revision|UNIQUE constraint/.test(text))return new ApiError(409,'sms_policy_changed','The collection or policy changed. Refresh before continuing.');
 return new ApiError(503,'sms_configuration_unknown','The result could not be confirmed. Check its original request before repeating it.');
}
const accessOptions={...options,permission:'admin_users.manage',entityType:'assisted_sms_access'};
const permissionNames=['assisted_sms.read','assisted_sms.manage'];
async function accessState(ctx){
 const [row]=await query(ctx,`SELECT
  EXISTS(SELECT 1 FROM admin_grants WHERE user_id=? AND permission='assisted_sms.read') AS read_granted,
  EXISTS(SELECT 1 FROM admin_grants WHERE user_id=? AND permission='assisted_sms.manage') AS manage_granted,
  (SELECT count(*) FROM admin_account_role_capabilities WHERE role='owner' AND permission IN('assisted_sms.read','assisted_sms.manage')) AS definitions,
  (SELECT count(*) FROM admin_account_role_capabilities WHERE permission IN('assisted_sms.read','assisted_sms.manage')) AS total_definitions,
  (SELECT count(*) FROM request_receipts WHERE user_id=? AND operation='assisted_sms.access.set') AS decision_revision`,ctx.actor.userId,ctx.actor.userId,ctx.actor.userId);
 if(row.definitions!==2||row.total_definitions!==2)throw new ApiError(503,'sms_access_configuration_unavailable','The reviewed receipt SMS capabilities are unavailable.');
 if(!Number.isSafeInteger(row.decision_revision)||row.decision_revision<0)throw new ApiError(503,'sms_decision_history_unavailable','The recorded choice history could not be verified.');
 return {...marker,scope:'owner_receipt_sms_access',current_admin_id:ctx.account.id,current_principal_id:ctx.actor.userId,
  read_granted:row.read_granted===1,manage_granted:row.manage_granted===1,can_operate:row.read_granted===1&&row.manage_granted===1,decision_revision:row.decision_revision,permissions:permissionNames};
}
async function setAccess(ctx,body){
 fields(body,['request_id','expected_read','expected_manage','expected_decision_revision','enabled','owner_confirmation']);
 const requestId=uuid(body.request_id,'request_id'),expectedDecision=integer(body.expected_decision_revision,'expected_decision_revision',0,Number.MAX_SAFE_INTEGER-1);
 if([body.expected_read,body.expected_manage,body.enabled].some(x=>typeof x!=='boolean')||body.owner_confirmation!==undefined&&typeof body.owner_confirmation!=='boolean')throw new ApiError(400,'invalid_access_choice','Choose the exact receipt SMS access state.');
 if(body.enabled&&body.owner_confirmation!==true)throw new ApiError(400,'owner_confirmation_required','Confirm receipt SMS access for your current account.');
 const {env,actor}=ctx,operation='assisted_sms.access.set',retained=await retainedResponse(env,actor,operation,requestId,body,accessOptions);
 if(retained.found)return {...retained.value,replay:true};
 const before=await accessState(ctx);if(before.read_granted!==body.expected_read||before.manage_granted!==body.expected_manage||before.decision_revision!==expectedDecision)throw new ApiError(409,'sms_access_changed','Your receipt SMS access changed. Refresh before continuing.');
 const timestamp=now(),grantTransactionId=id(),decision={kind:'authenticated_owner_receipt_sms_access',request_id:requestId,grant_transaction_id:grantTransactionId,current_admin_id:ctx.account.id,current_principal_id:actor.userId,
  originating_session_id:actor.sessionId,public_session_id:ctx.account.public_id,enabled:body.enabled,decision_revision:expectedDecision+1,permissions:permissionNames,recorded_at:timestamp};
 const receipt={...marker,scope:'owner_receipt_sms_access',...decision,read_granted:body.enabled,manage_granted:body.enabled,can_operate:body.enabled,decision_sha256:await digest(stableJson(decision)),recorded_state_only:true,replay:false};
 const condition=`(SELECT count(*) FROM admin_account_role_capabilities WHERE role='owner' AND permission IN('assisted_sms.read','assisted_sms.manage'))=2
  AND (SELECT count(*) FROM admin_account_role_capabilities WHERE permission IN('assisted_sms.read','assisted_sms.manage'))=2
  AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=? AND permission='assisted_sms.read')=?
  AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=? AND permission='assisted_sms.manage')=?
  AND (SELECT count(*) FROM request_receipts WHERE user_id=? AND operation='assisted_sms.access.set')=?`;
 // Both guards include this batch's already inserted immutable decision. A
 // no-op disable advances the head even while the grant booleans stay false.
 const pre=gate(env,condition,[actor.userId,Number(body.expected_read),actor.userId,Number(body.expected_manage),actor.userId,expectedDecision+1],grantTransactionId),post=gate(env,condition,[actor.userId,Number(body.enabled),actor.userId,Number(body.enabled),actor.userId,expectedDecision+1]);
 const writes=[pre[0]];
 for(const permission of permissionNames)writes.push(body.enabled?env.DB.prepare('INSERT OR IGNORE INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,?,?,?)').bind(actor.userId,permission,'admin-account:'+ctx.account.id,timestamp):
  env.DB.prepare('DELETE FROM admin_grants WHERE user_id=? AND permission=?').bind(actor.userId,permission));
 writes.push(post[0],post[1],pre[1]);
 try{return await mutation(env,actor,operation,requestId,body,receipt,writes,{...accessOptions,entityId:actor.userId,auditDetails:{enabled:body.enabled,permissions:permissionNames,decision_revision:expectedDecision+1,decision_sha256:receipt.decision_sha256}});}
 catch(error){const mapped=failure(error);if(mapped.code==='sms_policy_changed')throw new ApiError(409,'sms_access_changed','Your receipt SMS access changed. Refresh before continuing.');throw mapped;}
}
const conflict=()=>new ApiError(409,'request_conflict','This request belongs to a different operation or sign-in.');
async function operationReceipt(ctx,requestId,operation,input){
 const [row]=await query(ctx,'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?',ctx.actor.userId,requestId);
 if(!row)return null;
 if(row.operation!==operation||row.session_id!==ctx.actor.sessionId||input!==undefined&&row.body_sha256!==await digest(stableJson(input)))throw conflict();
 return {row,value:JSON.parse(row.response_json)};
}
async function accessOperation(ctx,requestId){
 const found=await operationReceipt(ctx,requestId,'assisted_sms.access.set');
 if(found){const value=found.value;
  if(value.request_id!==requestId||value.current_admin_id!==ctx.account.id||value.current_principal_id!==ctx.actor.userId||value.originating_session_id!==ctx.actor.sessionId||value.public_session_id!==ctx.account.public_id)throw conflict();
 }
 const current=await accessState(ctx);
 // The immutable outcome conveys neither replay permission nor the current
 // grants. In particular, self-revoke must remain readable without manage.
 await query(ctx,'SELECT 1 AS access_operation_current_authority');
 return {...marker,scope:'owner_receipt_sms_access_operation',request_id:requestId,observed:!!found,
  status:found?'recorded':'not_recorded',may_be_in_flight:!found,recorded_decision:found?.value??null,
  current_access:current,recorded_state_only:true,may_send:false,replay_authorized:false};
}
const historyKinds={
 'assisted_sms.access.set':{kind:'access',outcome:'decision_recorded',path:'/api/admin/notification-operator/access/operations/'},
 'assisted_sms.policy.configure':{kind:'policy',outcome:'decision_recorded',path:'/api/admin/notification-operator/policies/operations/'},
 'assisted_sms.materialize.plan':{kind:'materialization',outcome:'plan_recorded',path:'/api/admin/notification-operator/materialize/'},
};
function timestamp(value){
 if(typeof value!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)||!Number.isFinite(Date.parse(value))||new Date(value).toISOString()!==value)throw new ApiError(400,'invalid_cursor','Use the complete receipt history cursor.');
 return value;
}
async function operationHistory(ctx,url){
 for(const key of url.searchParams.keys())if(!['limit','after_created_at','after_request_id'].includes(key)||url.searchParams.getAll(key).length!==1)throw new ApiError(400,'invalid_cursor','Use the supported receipt history fields.');
 const rawLimit=url.searchParams.get('limit');
 if(rawLimit!==null&&!/^(?:[1-9]|1[0-9]|2[0-5])$/.test(rawLimit))throw new ApiError(400,'invalid_cursor','Choose a receipt history page of one to twenty-five records.');
 const limit=rawLimit===null?25:Number(rawLimit),after=url.searchParams.get('after_created_at'),rawAfterId=url.searchParams.get('after_request_id');
 if((after===null)!==(rawAfterId===null))throw new ApiError(400,'invalid_cursor','Use the complete receipt history cursor.');
 const afterId=rawAfterId===null?null:uuid(rawAfterId,'after_request_id');if(after!==null)timestamp(after);
 const rows=await query(ctx,`SELECT request_id,operation,created_at,response_json FROM request_receipts
  WHERE user_id=? AND session_id=? AND operation IN('assisted_sms.access.set','assisted_sms.policy.configure','assisted_sms.materialize.plan')
  AND json_extract(response_json,'$.public_session_id')=?
  AND (? IS NULL OR created_at<? OR (created_at=? AND request_id<?))
  ORDER BY created_at DESC,request_id DESC LIMIT ?`,ctx.actor.userId,ctx.actor.sessionId,ctx.account.public_id,after,after,after,afterId,limit+1);
 const items=rows.slice(0,limit).map(row=>{
  const type=historyKinds[row.operation],value=JSON.parse(row.response_json),requestId=uuid(row.request_id,'request_id');
  if(!type||requestId!==row.request_id||value.request_id!==requestId||value.originating_session_id!==ctx.actor.sessionId||value.public_session_id!==ctx.account.public_id||
   (type.kind==='policy'?value.owner_user_id!==ctx.actor.userId:value.current_principal_id!==ctx.actor.userId||value.current_admin_id!==ctx.account.id))throw new ApiError(503,'sms_history_unavailable','The recorded request metadata could not be verified.');
  let recordedAt;try{recordedAt=timestamp(row.created_at);}catch{throw new ApiError(503,'sms_history_unavailable','The recorded request metadata could not be verified.');}
  return {request_id:requestId,kind:type.kind,recorded_at:recordedAt,recorded_outcome:type.outcome,
   status_path:type.path+requestId,recorded_state_only:true,may_send:false};
 });
 await query(ctx,'SELECT 1 AS operation_history_current_authority');
 const last=items.at(-1);return {...marker,scope:'own_receipt_sms_request_history',items,
  next_cursor:rows.length>limit?{after_created_at:last.recorded_at,after_request_id:last.request_id}:null,
  original_session_only:true,recorded_state_only:true,may_send:false,replay_authorized:false};
}
async function currentPolicy(ctx,collectionId){
 const [row]=await query(ctx,`SELECT c.id,c.status,p.enabled,p.revision,p.template_key,p.approval_reference_sha256,p.updated_at
 FROM collections c LEFT JOIN assisted_sms_policies p ON p.collection_id=c.id WHERE c.id=?`,collectionId);
 if(!row)throw new ApiError(404,'not_found','This group was not found.');
 return {...marker,collection_id:collectionId,configured:row.revision!==null,enabled:row.enabled===1,revision:row.revision??0,template_key:row.template_key??template,
  recorded_owner_decision_sha256:row.approval_reference_sha256??null,recorded_at:row.updated_at??null,collection_active:row.status==='active'};
}
async function configure(ctx,collectionId,body){
 fields(body,['request_id','expected_revision','enabled','owner_confirmation']);const requestId=uuid(body.request_id,'request_id'),expected=integer(body.expected_revision,'expected_revision',0,999999998),enabled=body.enabled===undefined?false:body.enabled;
 if(typeof enabled!=='boolean'||body.owner_confirmation!==undefined&&typeof body.owner_confirmation!=='boolean')throw new ApiError(400,'invalid_policy','Choose whether this group may offer receipt SMS.');
 if(enabled&&body.owner_confirmation!==true)throw new ApiError(400,'owner_confirmation_required','Confirm this collection policy explicitly before enabling it.');
 const {env,actor}=ctx,operation='assisted_sms.policy.configure',input={collection_id:collectionId,...body};
 const retained=await retainedResponse(env,actor,operation,requestId,input,options);if(retained.found)return retained.value;
 const old=await currentPolicy(ctx,collectionId);if(old.revision!==expected)throw new ApiError(409,'sms_policy_changed','The policy changed. Refresh before continuing.');
 if(enabled&&!old.collection_active)throw new ApiError(409,'sms_collection_inactive','An inactive group cannot enable receipt SMS.');
 const revision=expected+1,timestamp=now(),decision={kind:'authenticated_owner_receipt_sms_policy',request_id:requestId,collection_id:collectionId,revision,enabled,template_key:template,
  owner_user_id:actor.userId,originating_session_id:actor.sessionId,public_session_id:ctx.account.public_id,recorded_at:timestamp,legal_release_approved:false,provider_approved:false};
 const reference=await digest(stableJson(decision)),receipt={...marker,...decision,recorded_owner_decision_sha256:reference};
 const check=gate(env,`EXISTS(SELECT 1 FROM collections WHERE id=? AND (?=0 OR status='active')) AND `+(expected===0?'NOT EXISTS(SELECT 1 FROM assisted_sms_policies WHERE collection_id=?)':'EXISTS(SELECT 1 FROM assisted_sms_policies WHERE collection_id=? AND revision=?)'),[collectionId,Number(enabled),collectionId,...(expected===0?[]:[expected])]);
 const write=expected===0?env.DB.prepare('INSERT INTO assisted_sms_policies(collection_id,enabled,revision,template_key,approval_reference_sha256,updated_at) VALUES(?,?,?,?,?,?)').bind(collectionId,Number(enabled),revision,template,reference,timestamp):
  env.DB.prepare('UPDATE assisted_sms_policies SET enabled=?,revision=?,approval_reference_sha256=?,updated_at=? WHERE collection_id=?').bind(Number(enabled),revision,reference,timestamp,collectionId);
 try{return await mutation(env,actor,operation,requestId,input,receipt,[check[0],write,check[1]],{...options,entityId:collectionId,auditDetails:{policy_revision:revision,enabled,recorded_owner_decision_sha256:reference}});}
 catch(error){throw failure(error);}
}
async function policyOperation(ctx,requestId){
 const found=await operationReceipt(ctx,requestId,'assisted_sms.policy.configure');
 if(found){const value=found.value;
  if(value.request_id!==requestId||value.owner_user_id!==ctx.actor.userId||value.originating_session_id!==ctx.actor.sessionId||value.public_session_id!==ctx.account.public_id)throw conflict();
 }
 await query(ctx,'SELECT 1 AS policy_operation_current_authority');
 return {...marker,scope:'owner_receipt_sms_policy_operation',request_id:requestId,observed:!!found,status:found?'recorded':'not_recorded',
  may_be_in_flight:!found,recorded_decision:found?.value??null,recorded_state_only:true,may_send:false,replay_authorized:false};
}
// Selection is advisory. The authoritative insertion trigger in the core
// candidate rechecks the complete current job/source/authorization snapshot.
const eligible=capabilities=>`SELECT e.id AS entry_id,p.id AS payment_id FROM ledger_entries e JOIN payments p ON p.id=e.payment_id
 JOIN collections c ON c.id=p.collection_id JOIN users u ON u.id=p.member_id
 JOIN memberships m ON m.collection_id=c.id AND m.user_id=u.id
 JOIN assisted_sms_policies policy ON policy.collection_id=c.id
 JOIN assisted_sms_authorizations consent ON consent.collection_id=c.id AND consent.recipient_user_id=u.id
 WHERE c.id=? AND e.kind='contribution' AND e.amount_minor>0 AND p.status IN ('reconciled','confirmed')
 AND p.currency='RWF' AND p.rail='rwanda_momo' AND e.currency='RWF' AND e.amount_minor=p.amount_minor
 AND e.collection_id=c.id AND e.member_id=u.id AND e.evidence_id=p.evidence_id
 AND NOT EXISTS(SELECT 1 FROM ledger_entries inverse WHERE inverse.reverses_entry_id=e.id)
 AND c.status='active' AND u.access_status='active' AND u.member_type!='operator' AND m.active=1
 AND policy.enabled=1 AND policy.template_key='collect.recorded_contribution.v1' AND consent.enabled=1
 AND NOT EXISTS(SELECT 1 FROM assisted_sms_jobs existing WHERE existing.entry_id=e.id OR existing.payment_id=p.id)
 ${capabilities.momo?'AND '+assistedSmsLivePaymentSql:''}
 ORDER BY e.posted_at,e.id LIMIT ?`;
const planOperation='assisted_sms.materialize.plan';
const materializationOptions={...options,entityType:'assisted_sms_materialization'};
async function phaseRequestId(plan,entry,phase){
 const sha=await digest(stableJson(['collect.materialization.v1',plan.request_id,entry.entry_id,phase]));
 return `${sha.slice(0,8)}-${sha.slice(8,12)}-5${sha.slice(13,16)}-a${sha.slice(17,20)}-${sha.slice(20,32)}`;
}
const sourceInput=(plan,entry)=>({batch_request_id:plan.request_id,source_entry_id:entry.entry_id,payment_id:entry.payment_id});
function validatePlan(ctx,requestId,value){
 if(value.request_id!==requestId||value.current_admin_id!==ctx.account.id||value.current_principal_id!==ctx.actor.userId||value.originating_session_id!==ctx.actor.sessionId||value.public_session_id!==ctx.account.public_id)throw conflict();
 fields(value.input,['request_id','collection_id','limit']);
 const limit=integer(value.input.limit===undefined?5:value.input.limit,'limit',1,10);
 if(uuid(value.input.request_id,'request_id')!==requestId||uuid(value.input.collection_id,'collection_id')!==value.collection_id||!Array.isArray(value.sources)||value.sources.length>limit||typeof value.has_more_observed!=='boolean')throw conflict();
 uuid(value.collection_id,'collection_id');const identities=new Set();
 for(const entry of value.sources){fields(entry,['entry_id','payment_id']);uuid(entry.entry_id,'source_entry_id');uuid(entry.payment_id,'payment_id');
  if(identities.has(entry.entry_id)||entry.entry_id===requestId)throw conflict();identities.add(entry.entry_id);
 }
 return value;
}
async function readPlan(ctx,requestId,input){
 const found=await operationReceipt(ctx,requestId,planOperation,input);if(!found)return null;
 const plan=validatePlan(ctx,requestId,found.value);
 if(found.row.body_sha256!==await digest(stableJson(plan.input)))throw conflict();return plan;
}
async function materializationPlan(ctx,body){
 fields(body,['request_id','collection_id','limit']);const requestId=uuid(body.request_id,'request_id'),collectionId=uuid(body.collection_id,'collection_id'),limit=integer(body.limit===undefined?5:body.limit,'limit',1,10);
 const old=await readPlan(ctx,requestId,body);if(old)return old;
 await currentPolicy(ctx,collectionId);const candidates=await query(ctx,eligible(await assistedSmsSourceCapabilities(ctx.env)),collectionId,limit+1);
 const plan={...marker,scope:'receipt_sms_materialization_plan',request_id:requestId,input:body,collection_id:collectionId,
  current_admin_id:ctx.account.id,current_principal_id:ctx.actor.userId,originating_session_id:ctx.actor.sessionId,public_session_id:ctx.account.public_id,
  sources:candidates.slice(0,limit),has_more_observed:candidates.length>limit,recorded_at:now(),recorded_state_only:true,may_send:false};
 validatePlan(ctx,requestId,plan);
 // Use the actual winning receipt, not this invocation's advisory selection.
 // A plan is committed before any per-source intent or enqueue is attempted.
 const saved=await mutation(ctx.env,ctx.actor,planOperation,requestId,body,plan,[],{...materializationOptions,entityId:requestId});
 return validatePlan(ctx,requestId,saved);
}
async function sourceStatus(ctx,plan,entry){
 const input=sourceInput(plan,entry),intentId=await phaseRequestId(plan,entry,'intent'),blockedId=await phaseRequestId(plan,entry,'blocked');
 const intent=await operationReceipt(ctx,intentId,'assisted_sms.materialize.intent',input),blocked=await operationReceipt(ctx,blockedId,'assisted_sms.materialize.blocked',input);
 // An entry identity belongs to one original enqueue sign-in. Another batch
 // can observe that record but cannot adopt a different session's authority.
 let enqueue;
 try{enqueue=await operationReceipt(ctx,entry.entry_id,'assisted_sms.enqueue',{payment_id:entry.payment_id,request_id:entry.entry_id});}
 catch(error){if(error instanceof ApiError&&error.code==='request_conflict')return {...entry,status:'blocked',code:'source_request_conflict'};throw error;}
 const jobs=await query(ctx,'SELECT id,payment_id,entry_id FROM assisted_sms_jobs WHERE entry_id=? OR payment_id=?',entry.entry_id,entry.payment_id);
 if(enqueue){
  if(jobs.length===1&&jobs[0].id===enqueue.value.job_id&&jobs[0].entry_id===entry.entry_id&&jobs[0].payment_id===entry.payment_id&&enqueue.value.payment_id===entry.payment_id)
   return {...entry,status:'committed',receipt:enqueue.value};
  return {...entry,status:'unknown',code:'enqueue_readback_mismatch',resume_safe:false};
 }
 if(jobs.length)return {...entry,status:'blocked',code:'source_already_queued'};
 if(blocked)return {...entry,status:'blocked',code:blocked.value.code};
 return {...entry,status:intent?'unknown':'planned',code:intent?'enqueue_not_observed':null,resume_safe:true};
}
async function materializationStatus(ctx,requestId,knownPlan){
 const plan=knownPlan??await readPlan(ctx,requestId),items=[];
 if(plan)for(const entry of plan.sources)items.push(await sourceStatus(ctx,plan,entry));
 // Guard again after all asynchronous reads, not just on route entry. A
 // winning role/link/session revocation must not disclose a partial result.
 await query(ctx,'SELECT 1 AS materialization_status_current_authority');
 if(!plan)return {...marker,scope:'bounded_receipt_sms_materialization',request_id:requestId,observed:false,status:'not_recorded',may_be_in_flight:true,
  planned_count:null,items:[],materialized_jobs:[],materialized_count:0,blocked:null,recorded_state_only:true,may_send:false,transport_started:false,all_source_events_complete:false};
 const committed=items.filter(x=>x.status==='committed'),blocked=items.find(x=>x.status==='blocked'),unknown=items.some(x=>x.status==='unknown');
 return {...marker,scope:'bounded_receipt_sms_materialization',request_id:requestId,observed:true,collection_id:plan.collection_id,source_identity:'immutable_contribution_entry_id',
  originating_session_id:plan.originating_session_id,public_session_id:plan.public_session_id,recorded_at:plan.recorded_at,
  status:blocked?'partial_blocked':unknown?'unknown':committed.length===items.length?'bounded_pass':'planned',planned_count:items.length,items,
  materialized_jobs:committed.map(x=>x.receipt),materialized_count:committed.length,blocked:blocked?{source_entry_id:blocked.entry_id,code:blocked.code}:null,
  has_more_observed:plan.has_more_observed,may_be_in_flight:unknown,recorded_state_only:true,may_send:false,transport_started:false,all_source_events_complete:false};
}
async function materialize(request,ctx,body){
 const plan=await materializationPlan(ctx,body),before=await materializationStatus(ctx,plan.request_id,plan);
 for(const entry of before.items){
  if(entry.status==='committed')continue;
  if(entry.status==='blocked'||entry.resume_safe===false)break;
  const input=sourceInput(plan,entry),intentId=await phaseRequestId(plan,entry,'intent');
  await mutation(ctx.env,ctx.actor,'assisted_sms.materialize.intent',intentId,input,{...input,recorded_state_only:true,may_send:false},[],{...materializationOptions,entityId:plan.request_id});
  try{await enqueueAssistedSms(request,ctx.env,{payment_id:entry.payment_id,request_id:entry.entry_id});}
  catch(error){
   const denied=failure(error);if([401,403].includes(denied.status)||denied.status>=500)throw denied;
   const blockedId=await phaseRequestId(plan,entry,'blocked');
   await mutation(ctx.env,ctx.actor,'assisted_sms.materialize.blocked',blockedId,input,{...input,code:denied.code,recorded_state_only:true,may_send:false},[],{...materializationOptions,entityId:plan.request_id});
   break;
  }
 }
 return materializationStatus(ctx,plan.request_id,plan);
}
export async function notificationOperatorManagementRoute(request,env){
 const url=new URL(request.url),match=/^\/api\/admin\/notification-operator\/policies\/([^/]+)$/.exec(url.pathname),policyOperationMatch=/^\/api\/admin\/notification-operator\/policies\/operations\/([^/]+)$/.exec(url.pathname),materialization=/^\/api\/admin\/notification-operator\/materialize\/([^/]+)$/.exec(url.pathname),accessOperationMatch=/^\/api\/admin\/notification-operator\/access\/operations\/([^/]+)$/.exec(url.pathname),isHistory=url.pathname==='/api/admin/notification-operator/operations',isMaterializer=url.pathname==='/api/admin/notification-operator/materialize',isAccess=url.pathname==='/api/admin/notification-operator/access';
 if(!match&&!policyOperationMatch&&!materialization&&!accessOperationMatch&&!isHistory&&!isMaterializer&&!isAccess)return null;validateAdminOrigin(request,env);
 if(url.search&&!isHistory)throw new ApiError(400,'invalid_request','These commands do not accept query parameters.');
 if(!['GET','POST'].includes(request.method)||isMaterializer&&request.method!=='POST'||(materialization||accessOperationMatch||policyOperationMatch||isHistory)&&request.method!=='GET')throw new ApiError(405,'method_not_allowed','Use the supported receipt SMS command.');
 if(request.method==='POST'&&request.headers.get('X-Collect-Admin')!=='1')throw new ApiError(403,'operator_origin_required','Open the configured Admin workspace.');
 const ctx=await owner(request,env,isAccess||accessOperationMatch||isHistory?'admin_users.manage':'assisted_sms.manage');
 try{
  if(isHistory)return json({ok:true,result:await operationHistory(ctx,url)});
  if(policyOperationMatch)return json({ok:true,result:await policyOperation(ctx,uuid(policyOperationMatch[1],'request_id'))});
  if(accessOperationMatch)return json({ok:true,result:await accessOperation(ctx,uuid(accessOperationMatch[1],'request_id'))});
  if(materialization)return json({ok:true,result:await materializationStatus(ctx,uuid(materialization[1],'request_id'))});
  if(isAccess)return json({ok:true,result:request.method==='GET'?await accessState(ctx):await setAccess(ctx,await readJson(request,4096))});
  if(isMaterializer)return json({ok:true,result:await materialize(request,ctx,await readJson(request,4096))});
  const collectionId=uuid(match[1],'collection_id');return json({ok:true,result:request.method==='GET'?await currentPolicy(ctx,collectionId):await configure(ctx,collectionId,await readJson(request,4096))});
 }catch(error){throw failure(error);}
}
