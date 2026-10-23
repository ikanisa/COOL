import {canonicalReconciliationRead} from './admin_reconciliation_reads.js';
import {adminSmsMetadataRead} from './admin_sms_receipts.js';
import {adminMomoRoute} from './admin_momo.js';
import {adminMemberReceiptRead} from './admin_member_receipts.js';
import {marker,permission,lists,list,filters,overview,operatingDetail,exact,iso,fail,unavailable} from './admin_records.js';
import {ApiError,json,readJson,first,rows,uuid,text,integer,now,id,digest,stableJson,requireFreshAuth} from './core.js';
import {mutation,retainedResponse} from './mutations.js';
import {assertMemberManagementTarget,memberManagementGuard} from './user_access.js';
import {financialRpc} from './payments.js';
import {evidenceRoute,compensationRpc} from './evidence.js';
import {encrypt} from './encryption.js';
import {recordOperatorNote,listOperatorNotes,operatorNotePermission} from './operator_notes.js';
import {adminSyncEvents} from './admin_sync.js';
import {adminPrivacyRoute} from './admin_privacy.js';
import {notificationOperatorRoute} from './notification_operator.js';
import {notificationOperatorManagementRoute} from './notification_operator_management.js';
import {handleAdminAccounts,validateAdminOrigin,adminAccountSession,adminCanonicalActor,adminInternalRequest,accountDatabase} from './admin_accounts.js';

const keys=(data,allowed)=>{if(Object.keys(data).some(k=>!allowed.includes(k)))fail(400,'invalid_request','Request has unsupported fields.');};
const optionalText=(v,field,max)=>v==null||v===''?null:text(v,field,max);
const requestId=async(account,key)=>{if(typeof key!=='string'||!/^[a-zA-Z0-9_.-]{8,200}$/.test(key))fail(400,'invalid_request','Supply an Idempotency-Key of 8 to 200 letters, digits, dots, hyphens or underscores.');
 const value=await digest(`collect-admin:${account.principal_id}:${key}`);return `${value.slice(0,8)}-${value.slice(8,12)}-4${value.slice(13,16)}-8${value.slice(17,20)}-${value.slice(20,32)}`;};
function domainGuard(env,condition,args=[]){const guardId=id();return [env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN ${condition} THEN 1 ELSE 0 END)`).bind(guardId,...args),env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guardId)];}
function expected(data,current){const value=integer(data.expected_version,'expected_version',1);if(value!==current)fail(409,'stale_state','The record changed. Refresh before continuing.');return value;}
function rwPhone(value,{optional=false}={}){if(optional&&(value==null||value===''))return null;if(typeof value!=='string')fail(400,'invalid_phone','Enter a Rwanda phone number.');const digits=value.replace(/^\+/,'');
 const normalized=/^07[2389]\d{7}$/.test(digits)?'250'+digits.slice(1):digits;if(!/^2507[2389]\d{7}$/.test(normalized))fail(400,'invalid_phone','Enter a Rwanda phone number.');return '+'+normalized;}
function validReceiver(receiver,{allowCode=false}={}){if(!receiver||typeof receiver!=='object'||Array.isArray(receiver))fail(400,'invalid_receiver','Record the group receiver.');keys(receiver,['label','network','momo_number_or_code']);
 if(!['mtn_momo','airtel_money'].includes(receiver.network))fail(400,'invalid_receiver','Choose a Rwanda MoMo network.');
 const route=receiver.momo_number_or_code,code=allowCode&&typeof route==='string'&&/^[0-9]{4,12}$/.test(route)&&!/^07[2389][0-9]{7}$/.test(route);
 return {label:text(receiver.label,'receiver label',120),network:receiver.network,number:code?route:rwPhone(route).slice(1)};}
function receipt(requestId,type,resourceId,version){return {status:'succeeded',request_id:requestId,resource_type:type,resource_id:resourceId,version};}

// Preserve the UI's arbitrary idempotency keys while canonical mutations keep
// their UUID request ID. The alias and the actual receipt commit together.
function requestEnvironment(env,account,key,rid,operation,source,{before=[],after=[]}={}){
 const map=new WeakMap(),shaPromise=digest(stableJson(source));
 const wrapStatement=(stmt,query)=>{const proxy=new Proxy(stmt,{get(target,name){if(name==='bind')return(...args)=>wrapStatement(target.bind(...args),query);const value=Reflect.get(target,name,target);return typeof value==='function'?value.bind(target):value;}});map.set(proxy,{stmt,query});return proxy;};
 const db=new Proxy(env.DB,{get(target,name){
  if(name==='prepare')return query=>wrapStatement(target.prepare(query),query);
  if(name==='batch')return async statements=>{
   const originals=statements.map(v=>map.get(v)?.stmt??v);
   const writesReceipt=statements.some(v=>/INSERT INTO request_receipts\b/.test(map.get(v)?.query??''));
   if(!writesReceipt)return target.batch(originals);
   const sha=await shaPromise,guardId=id();
   const extra=[target.prepare(`INSERT INTO admin_bridge_requests(admin_user_id,idempotency_key,request_id,session_id,operation,body_sha256,created_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(admin_user_id,idempotency_key) DO NOTHING`).bind(account.id,key,rid,account.auth_session_id,operation,sha,now()),
    target.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(SELECT 1 FROM admin_bridge_requests WHERE admin_user_id=? AND idempotency_key=? AND request_id=? AND session_id=? AND operation=? AND body_sha256=?) THEN 1 ELSE 0 END)`).bind(guardId,account.id,key,rid,account.auth_session_id,operation,sha)];
   const result=await target.batch([...extra,...before,...originals,...after,target.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guardId)]);
   return result.slice(extra.length+before.length,extra.length+before.length+originals.length);
  };
  if(name==='withSession')return()=>db;const value=Reflect.get(target,name,target);return typeof value==='function'?value.bind(target):value;
 }});return {...env,DB:db};
}
async function genericMutation(request,env,account,actor,parts,data,rid,source){
 const type=parts[0],create=request.method==='POST'&&parts.length===1,patch=request.method==='PATCH'&&parts.length>=2,
  operation=`admin.bridge.${type}.${request.method.toLowerCase()}.${parts.slice(1).join('.')}`;
 if(!['groups','users','memberships','payees'].includes(type))unavailable();
 const capability=type==='groups'&&create?'collections.create':`${permission[type]??(type==='memberships'?'collections':'')}.manage`;
 if(!actor.permissions.has(capability))fail(403,'permission_required','This operating action is unavailable.');
 const publicCreate=type==='groups'&&create&&(data.visibility==='public_approved'||data.is_platform_sponsored===true);
 const publicationRequest=publicCreate||(type==='groups'&&patch&&(data.visibility!==undefined||data.is_platform_sponsored!==undefined));
 if(publicationRequest){
  if(!['owner','admin'].includes(account.role)||!actor.permissions.has('collections.manage')||!actor.permissions.has('receivers.manage'))fail(403,'permission_required','Only an administrator can publish a public group.');
  // Every publication permission and the current cookie/MFA proof are checked
  // in the same D1 batch as the alias, receipt, group, owner membership and audit.
  env=accountDatabase(accountDatabase(env,account,'collections.manage',{mfa:true,fresh:true}),account,'receivers.manage',{mfa:true,fresh:true});
 }
 const options={permission:capability,minimumAssurance:2,freshSeconds:300,auditDetails:{reason:text(data.reason,'reason',500)}};
 const replay=await retainedResponse(env,actor,operation,rid,source,options);if(replay.found)return replay.value;
 if(!['groups','users','memberships','payees'].includes(type)||!create&&!patch)unavailable();text(data.reason??request.headers.get('X-Collect-Review-Reason'),'reason',500);
 const writes=[],resourceId=create?id():uuid(parts[1]),timestamp=now();let version=1;
 if(type==='groups'){
  keys(data,['title','slug','description','collection_type','purpose_label','status','visibility','is_platform_sponsored','owner_user_id','receiver','reason','expected_version']);
  if(create){if(data.expected_version!==undefined)fail(400,'invalid_request','New groups do not accept an expected version.');
   const visibility=data.visibility??'private',sponsored=data.is_platform_sponsored??false;
    if(!['private','public_approved'].includes(visibility)||typeof sponsored!=='boolean'||(visibility==='public_approved')!==sponsored)fail(400,'invalid_publication','Choose a private group or a public Collect-sponsored group.');
    const title=text(data.title,'title',160),slug=text(data.slug,'slug',100),owner=uuid(data.owner_user_id,'owner_user_id'),receiver=validReceiver(data.receiver,{allowCode:publicCreate}),kind=text(data.collection_type,'collection_type',64);
   if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)||!['ikimina','sport','church','wedding','other'].includes(kind))fail(400,'invalid_group','Choose a supported group type and slug.');
   if(data.status&&data.status!=='active')unavailable();
   const description=data.description??'';if(typeof description!=='string'||description.length>2000)fail(400,'invalid_group','The group description is too long.');
   const guard=domainGuard(env,"EXISTS(SELECT 1 FROM users WHERE id=? AND access_status='active' AND member_type!='operator')",[owner]);
   const code=id(),cipher=await encrypt(env,new TextEncoder().encode(code),`group-invite:${resourceId}`);
   writes.push(guard[0],env.DB.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,description,collection_type,receiver_momo_number,receiver_network,receiver_display_label,visibility_status,is_platform_sponsored,share_code_hash,share_code_ciphertext,data_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(resourceId,slug,owner,title,description,kind,receiver.number,receiver.network,receiver.label,visibility,Number(sponsored),await digest(code),cipher,JSON.stringify({purpose_label:optionalText(data.purpose_label,'purpose label',120)}),timestamp,timestamp),
    env.DB.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'owner',1,?)`).bind(id(),resourceId,owner,timestamp),guard[1]);
  }else{
   const row=await first(env,'SELECT * FROM collections WHERE id=?',resourceId);if(!row)fail(404,'not_found','The group was not found.');version=expected(data,row.revision)+1;
   if(row.status==='archived')fail(409,'group_archived','Archived groups cannot be changed.');
   if(data.receiver!==undefined&&(row.is_platform_sponsored===1||row.visibility_status==='public_approved'))fail(409,'receiver_locked','The public group receiver is permanently locked.');
   if(data.owner_user_id!==undefined||data.receiver!==undefined)unavailable();const status=data.status??row.status;
   if(!['active','suspended','archived'].includes(status))unavailable();const visibility=data.visibility??row.visibility_status;
   if(data.visibility!==undefined&&!['private','public_approved'].includes(visibility))fail(400,'invalid_publication','Choose private or public visibility.');
   const sponsored=row.is_platform_sponsored===1||row.visibility_status==='public_approved'||visibility==='public_approved';
   if(data.is_platform_sponsored!==undefined&&(typeof data.is_platform_sponsored!=='boolean'||data.is_platform_sponsored!==sponsored))fail(409,'publication_locked','A public group stays Collect-sponsored and its receiver stays locked.');
   if(visibility==='public_approved')validReceiver({label:row.receiver_display_label,network:row.receiver_network,momo_number_or_code:row.receiver_momo_number},{allowCode:true});
   const kind=data.collection_type??row.collection_type;if(!['ikimina','sport','church','wedding','other'].includes(kind))fail(400,'invalid_group','Choose a supported group type.');
   const stored=JSON.parse(row.data_json);if(data.purpose_label!==undefined)stored.purpose_label=optionalText(data.purpose_label,'purpose label',120);
   const description=data.description??row.description;if(typeof description!=='string'||description.length>2000)fail(400,'invalid_group','The group description is too long.');
   const guard=domainGuard(env,'EXISTS(SELECT 1 FROM collections WHERE id=? AND revision=? AND visibility_status=? AND is_platform_sponsored=? AND receiver_momo_number IS ? AND receiver_network IS ? AND receiver_display_label IS ?)',[resourceId,row.revision,row.visibility_status,row.is_platform_sponsored,row.receiver_momo_number,row.receiver_network,row.receiver_display_label]);
   writes.push(guard[0],env.DB.prepare(`UPDATE collections SET title=?,description=?,collection_type=?,status=?,visibility_status=?,is_platform_sponsored=?,revision=revision+1,data_json=?,updated_at=? WHERE id=?`).bind(data.title===undefined?row.title:text(data.title,'title',160),description,kind,status,visibility,Number(sponsored),JSON.stringify(stored),timestamp,resourceId));
   if(status!=='active'||visibility!==row.visibility_status||Number(sponsored)!==row.is_platform_sponsored)writes.push(env.DB.prepare(`UPDATE payment_intents SET status='cancelled' WHERE collection_id=? AND status='pending'`).bind(resourceId));writes.push(guard[1]);
  }
 }else if(type==='users'){
  keys(data,['display_name','email','phone_e164','member_type','momo_provider','momo_number','momo_pay_code','status','reason','expected_version']);
  const row=create?null:await first(env,'SELECT * FROM users WHERE id=?',resourceId);if(!create&&!row)fail(404,'not_found','The person was not found.');
  if(row)await assertMemberManagementTarget(env,row);const memberType=data.member_type??row?.member_type??'app';if(!['app','direct'].includes(memberType)||(!create&&memberType!==row.member_type))unavailable();
  const fullName=data.display_name===undefined?row?.full_name:text(data.display_name,'display name',120);if(!fullName)fail(400,'invalid_name','Record the full name.');
  const phone=data.phone_e164===undefined?row?.phone??null:rwPhone(data.phone_e164,{optional:true}),email=data.email===undefined?row?.email??null:optionalText(data.email,'email',254);
  if(email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))fail(400,'invalid_email','Enter a valid email address.');
  const momo=data.momo_number===undefined?row?.momo_number??'':rwPhone(data.momo_number,{optional:true})?.replace(/^\+250/,'0')??'',provider=data.momo_provider??row?.momo_provider??'';
  if(provider&&!['mtn_momo','airtel_money'].includes(provider))fail(400,'invalid_network','Choose a Rwanda MoMo network.');
  if(memberType==='direct'&&!momo)fail(400,'invalid_profile','Record the Direct member MoMo number.');
  if(memberType==='app'&&!phone&&!email)fail(400,'invalid_profile','Record a phone number or email address.');
  const code=data.momo_pay_code===undefined?row?.momo_pay_code??'':optionalText(data.momo_pay_code,'MoMo code',40)??'',status=data.status??row?.access_status??'active';if(!['active','suspended'].includes(status))unavailable();
  if(!create&&(data.phone_e164!==undefined||data.email!==undefined))unavailable(); // Credential changes require their own verified workflow.
  if(resourceId===actor.userId&&status==='suspended')fail(409,'self_suspend','Ask another administrator to suspend this person.');
  if(create){writes.push(env.DB.prepare(`INSERT INTO users(id,public_id,full_name,phone,email,member_type,momo_provider,momo_number,momo_pay_code,access_status,created_at,updated_at)
    VALUES(?,(SELECT printf('%06d',min(candidate)) FROM (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM users WHERE public_id!='999999') c WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM users WHERE public_id=printf('%06d',candidate))),?,?,?,?,?,?,?,?,?,?)`)
    .bind(resourceId,fullName,memberType==='app'?phone:null,memberType==='app'?email:null,memberType,provider,momo,code,status,timestamp,timestamp));
  }else{version=expected(data,row.revision)+1;const guards=memberManagementGuard(env,row,status);
   writes.push(guards[0],env.DB.prepare(`UPDATE users SET full_name=?,momo_provider=?,momo_number=?,momo_pay_code=?,access_status=?,revision=revision+1,updated_at=? WHERE id=?`).bind(fullName,provider,momo,code,status,timestamp,resourceId));
   if(status==='suspended')writes.push(env.DB.prepare(`UPDATE auth_sessions SET revoked_at=?,revocation_reason='account_suspended' WHERE user_id=? AND revoked_at IS NULL`).bind(Math.floor(Date.now()/1000),resourceId));writes.push(guards[1]);}
 }else if(type==='memberships'){
  keys(data,['group_id','user_id','role','status','reason','expected_version']);
  const groupId=uuid(create?data.group_id:parts[1]),userId=uuid(create?data.user_id:parts[2]),role=data.role??'member',active=(data.status??'active')==='active'?1:0;
  if(!['member','admin'].includes(role)||!['active','removed','left'].includes(data.status??'active'))unavailable();
  const existing=await first(env,'SELECT * FROM memberships WHERE collection_id=? AND user_id=?',groupId,userId);if(existing?.role==='owner')unavailable();
  if(!create){if(!existing)fail(404,'not_found','The membership was not found.');version=expected(data,existing.revision)+1;}
  const guard=domainGuard(env,`EXISTS(SELECT 1 FROM collections WHERE id=? AND status='active') AND EXISTS(SELECT 1 FROM users WHERE id=? AND access_status='active' AND member_type!='operator')
   AND (?=1 OR EXISTS(SELECT 1 FROM memberships WHERE collection_id=? AND user_id=? AND revision=? AND role!='owner'))`,[groupId,userId,Number(create),groupId,userId,existing?.revision??0]);
  writes.push(guard[0],create?env.DB.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,?,?,?)`).bind(id(),groupId,userId,role,active,timestamp):
   env.DB.prepare(`UPDATE memberships SET role=?,active=?,revision=revision+1 WHERE collection_id=? AND user_id=?`).bind(role,active,groupId,userId),guard[1]);
  const value=receipt(rid,type,`${groupId}/${userId}`,version);return mutation(env,actor,operation,rid,source,value,writes,{...options,entityType:'membership',entityId:groupId});
 }else if(type==='payees'){
  keys(data,['group_id','label','network','momo_number_or_code','status','reason','expected_version']);
  const groupId=uuid(create?data.group_id:resourceId),row=await first(env,'SELECT * FROM collections WHERE id=?',groupId);if(!row)fail(404,'not_found','The group was not found.');
   if(row.is_platform_sponsored===1||row.visibility_status==='public_approved')fail(409,'receiver_locked','The public group receiver is permanently locked.');
  if(row.status!=='active'||data.status&&data.status!=='active')unavailable();version=expected(data,row.revision)+1;
  const receiver=validReceiver({label:data.label??row.receiver_display_label,network:data.network??row.receiver_network,momo_number_or_code:data.momo_number_or_code??row.receiver_momo_number});
  const guard=domainGuard(env,"EXISTS(SELECT 1 FROM collections WHERE id=? AND revision=? AND status='active' AND is_platform_sponsored=0 AND visibility_status!='public_approved')",[groupId,row.revision]);
  writes.push(guard[0],env.DB.prepare(`UPDATE collections SET receiver_display_label=?,receiver_network=?,receiver_momo_number=?,revision=revision+1,updated_at=? WHERE id=?`).bind(receiver.label,receiver.network,receiver.number,timestamp,groupId),env.DB.prepare(`UPDATE payment_intents SET status='cancelled' WHERE collection_id=? AND status='pending'`).bind(groupId),guard[1]);
  return mutation(env,actor,operation,rid,source,receipt(rid,type,groupId,version),writes,{...options,entityType:'collection',entityId:groupId});
 }else unavailable();
 return mutation(env,actor,operation,rid,source,receipt(rid,type,resourceId,version),writes,{...options,entityType:type==='groups'?'collection':'user',entityId:resourceId});
}

function historyReceipt(row){
 const value=JSON.parse(row.response_json);if(value.resource_type)return value;
 if(row.operation.startsWith('operations.transactions.'))return receipt(row.request_id,'transactions',value.id??value.payment_id,value.revision??1);
 if(row.operation.startsWith('reconciliations.proposals.'))return {...marker,...receipt(row.request_id,'reconciliation_proposals',value.id,2),transaction_id:value.payment_id,proposal_status:value.status,transaction_version:value.payment_revision??value.expected_payment_revision+1,settlement_status:'not_asserted'};
 if(row.operation.startsWith('reconciliations.'))return {...marker,...receipt(row.request_id,'reconciliation_proposals',value.id,1),transaction_id:value.payment_id,proposal_status:'proposed',settlement_status:'not_asserted'};
 fail(503,'receipt_unavailable','The retained request outcome is unavailable.');
}
function requestScope(operation){
 if(/^operations\.(groups|users)\.[^.]+\.notes\.POST$/.test(operation))return 'operator_notes.post';
 if(operation==='request.cancelled')return 'requests.cancel';
 if(operation.startsWith('reconciliations.'))return operation.includes('.reviews')?'reconciliations.review':'reconciliations.propose';
 const parts=operation.split('.');if(parts[0]!=='operations'||!['groups','users','memberships','payees','transactions'].includes(parts[1]))fail(503,'receipt_unavailable','The retained request scope is unavailable.');
 const method=parts.at(-1)?.toLowerCase();if(!['post','patch'].includes(method))fail(503,'receipt_unavailable','The retained request method is unavailable.');
 return `${parts[1]}.${method}${parts[1]==='transactions'&&parts[3]==='reverse'?'.reverse':''}`;
}
function requestOutcome(row){
 if(!row)return {...marker,status:'not_found'};
 if(row.operation==='request.cancelled'){
  if(row.response_json)fail(503,'request_state_unavailable','The original request state needs review.');
  return {...marker,status:'cancelled',request_id:row.request_id,receipt:null};
 }
 return {...marker,status:row.response_json?'succeeded':'unconfirmed',request_id:row.request_id,receipt:row.response_json?historyReceipt(row):null};
}
async function originalRequest(env,account,key){return first(env,`SELECT a.request_id,a.operation,r.response_json
 FROM admin_bridge_requests a LEFT JOIN request_receipts r ON r.user_id=? AND r.request_id=a.request_id
 WHERE a.admin_user_id=? AND a.idempotency_key=?`,account.principal_id,account.id,key);}
async function cancelOriginalRequest(env,account,actor,targetKey,data,rid,source){
 keys(data,['reason']);const reason=text(data.reason,'reason',500);
 if(reason.length<8)fail(400,'reason_required','Record a reason of at least eight characters.');
 if(!actor.permissions.has('account.manage')||actor.assuranceLevel!==2)fail(403,'mfa_required','Complete a current authenticator check.');
 requireFreshAuth(actor);const targetId=await requestId(account,targetKey);
 if(targetId===rid)fail(400,'invalid_request','Use a separate cancellation request reference.');
 const scoped=accountDatabase(env,account,'account.manage'),operation='admin.request.cancel',
  options={permission:'account.manage',minimumAssurance:2,freshSeconds:300,entityType:'request_cancellation',entityId:targetId,
   auditDetails:{reason,target_request_id:targetId}};
 const replay=await retainedResponse(scoped,actor,operation,rid,source,options);if(replay.found)return replay.value;
 let current=await originalRequest(scoped,account,targetKey);
 if(current){const outcome=requestOutcome(current);
  if(outcome.status==='unconfirmed')fail(409,'request_unconfirmed','Keep the original reference while its state is reviewed.');
  return mutation(scoped,actor,operation,rid,source,outcome,[],options);
 }
 const guard=domainGuard(scoped,`EXISTS(SELECT 1 FROM admin_bridge_requests WHERE admin_user_id=? AND idempotency_key=? AND request_id=? AND operation='request.cancelled')`,[account.id,targetKey,targetId]);
 const result={...marker,status:'cancelled',request_id:targetId,receipt:null};
 const writes=[scoped.DB.prepare(`INSERT INTO admin_bridge_requests(admin_user_id,idempotency_key,request_id,session_id,operation,body_sha256,created_at)
  VALUES(?,?,?,?,'request.cancelled',?,?) ON CONFLICT(admin_user_id,idempotency_key) DO NOTHING`)
  .bind(account.id,targetKey,targetId,account.auth_session_id,await digest(stableJson(source)),now()),guard[0],guard[1]];
 try{return await mutation(scoped,actor,operation,rid,source,result,writes,options);}
 catch(error){
  current=await originalRequest(scoped,account,targetKey);
  if(!current||requestOutcome(current).status==='unconfirmed')throw error;
  // The original write may have won the same atomic D1 race. Return its
  // retained effect instead of claiming that a committed change was cancelled.
  return mutation(scoped,actor,operation,rid,source,requestOutcome(current),[],options);
 }
}
async function operatingRead(request,env,account,parts,url){
 if(parts.length===3&&parts[2]==='notes'&&['groups','users'].includes(parts[0])){
  const entityType=parts[0]==='groups'?'collection':'profile',cap=operatorNotePermission(entityType),f=filters(url,['limit','offset']);
  const scoped=accountDatabase(env,account,cap),actor=await adminCanonicalActor(request,scoped,account,cap);
  const result=await listOperatorNotes(scoped,actor,entityType,parts[1],f);
  // Decryption can await key work: recheck authority before releasing content.
  const latest=await adminAccountSession(request,env);if(!latest.permissions.includes(cap))fail(403,'permission_required','These notes are unavailable.');
  return result;
 }
 if(parts[0]==='requests'){
  if(!account.permissions.includes('account.manage'))fail(403,'permission_required','Request history is unavailable.');env=accountDatabase(env,account,'account.manage');
  const resource=parts[1];if(resource){if(!/^[a-zA-Z0-9_.-]{8,200}$/.test(resource)||url.search)fail(400,'invalid_request','Invalid request lookup.');
   const [result]=await env.DB.batch([env.DB.prepare(`SELECT a.request_id,a.operation,r.response_json FROM admin_bridge_requests a LEFT JOIN request_receipts r ON r.user_id=? AND r.request_id=a.request_id WHERE a.admin_user_id=? AND a.idempotency_key=?`).bind(account.principal_id,account.id,resource)]);
   return requestOutcome(result.results[0]);
  }
  const f=filters(url,['limit','offset']);const [count,result]=await env.DB.batch([env.DB.prepare('SELECT count(*) AS total FROM admin_bridge_requests WHERE admin_user_id=?').bind(account.id),
   env.DB.prepare(`SELECT a.*,r.response_json FROM admin_bridge_requests a LEFT JOIN request_receipts r ON r.user_id=? AND r.request_id=a.request_id WHERE a.admin_user_id=? ORDER BY a.created_at DESC,a.request_id LIMIT ? OFFSET ?`).bind(account.principal_id,account.id,f.limit,f.offset)]);
  return {...marker,total:exact(count.results[0].total),rows:result.results.map(r=>{const outcome=requestOutcome(r);return {id:r.request_id,idempotency_key:r.idempotency_key,scope:requestScope(r.operation),status:outcome.status,receipt:outcome.receipt,created_at:iso(r.created_at)};})};
 }
 if(parts[0]==='lookups'){
  const kind=url.searchParams.get('kind');if(!lists[kind])unavailable();if(!account.permissions.includes(`${permission[kind]}.read`))fail(403,'permission_required','This lookup is unavailable.');
  const projection=new URL(url);projection.searchParams.delete('kind');const groupId=projection.searchParams.get('group_id');projection.searchParams.delete('group_id');
  if(groupId&&kind!=='members'&&kind!=='payees')fail(400,'invalid_filter','This lookup filter is unavailable.');
  if((kind==='members'||kind==='payees')&&!groupId)fail(400,'invalid_filter','Choose a group before choosing its records.');
  const result=await list(accountDatabase(env,account,`${permission[kind]}.read`),kind,projection,{activeOnly:true,eligiblePeople:['members','users'].includes(kind),groupId});
  return {...result,kind,group_id:groupId??null,rows:result.rows.map(r=>({...r,label:r.display_name||r.title,name:r.display_name||r.title}))};
 }
 if(parts.length!==2||!lists[parts[0]])unavailable();const type=parts[0];if(!account.permissions.includes(`${permission[type]}.read`))fail(403,'permission_required','This view is unavailable.');
 return operatingDetail(accountDatabase(env,account,`${permission[type]}.read`),account,type,uuid(parts[1]),url);
}

async function bridgeRoute(request,env,ctx){
 validateAdminOrigin(request,env);const url=new URL(request.url),parts=url.pathname.slice('/api/admin/'.length).split('/'),account=await adminAccountSession(request,env),section=parts.shift();
 const base=accountDatabase(env,account);const actor=await adminCanonicalActor(request,base,account);
 if(section==='momo')return adminMomoRoute(request,base,account,actor,parts,url);
 if(section==='sms')return json(await adminSmsMetadataRead(request,base,account,actor,parts,url));
 if(section==='gateway'&&parts[0]==='receipts')return json(await adminMemberReceiptRead(request,base,account,actor,parts,url));
 if(section==='privacy')return adminPrivacyRoute(request,accountDatabase(env,account,'privacy.review',{mfa:true,fresh:true}),actor,parts);
 if(section==='sync'){
  if(parts.length!==0)fail(404,'not_found','This update view does not exist.');
  if(request.method!=='GET')fail(405,'method_not_allowed','Updates are read-only.');
  return json(await adminSyncEvents(request,base,account));
 }
 if(section==='core'){
  if(request.method!=='GET')fail(405,'method_not_allowed','This view is read-only.');
  if(parts.length!==1||parts[0]!=='overview'&&!lists[parts[0]])fail(404,'not_found','This workspace view does not exist.');
  const cap=parts[0]==='overview'?'overview.read':`${permission[parts[0]]}.read`;if(!actor.permissions.has(cap))fail(403,'permission_required','This view is unavailable.');
  const scoped=accountDatabase(env,account,cap);return json(parts[0]==='overview'?await overview(scoped,url):await list(scoped,parts[0],url));
 }
 if(section==='operations'&&request.method==='GET')return json(await operatingRead(request,base,account,parts,url));
 if(section==='operations'&&['POST','PATCH'].includes(request.method)){
  if(parts.length===3&&parts[2]==='notes'&&request.method!=='POST')fail(405,'method_not_allowed','Support notes must be recorded with POST.');
  if(url.search)fail(400,'invalid_request','This action does not accept filters.');const data=await readJson(request,2097152),key=request.headers.get('Idempotency-Key'),rid=await requestId(account,key),source={method:request.method,path:url.pathname,body:data};
  if(parts.length===3&&parts[0]==='requests'&&parts[2]==='cancel'&&request.method==='POST')return json(await cancelOriginalRequest(base,account,actor,parts[1],data,rid,source));
  const scoped=requestEnvironment(base,account,key,rid,`operations.${parts.join('.')}.${request.method}`,source);
  if(parts.length===3&&parts[2]==='notes'&&['groups','users'].includes(parts[0])&&request.method==='POST'){
   keys(data,['body']);const entityType=parts[0]==='groups'?'collection':'profile',cap=operatorNotePermission(entityType);
   const noteEnv=requestEnvironment(accountDatabase(env,account,cap),account,key,rid,`operations.${parts.join('.')}.POST`,source);
   return json(await recordOperatorNote(noteEnv,actor,{entityType,entityId:parts[1],body:data.body,requestId:rid,requestBody:source,
    operation:'admin.operator_note.recorded',receipt:noteId=>receipt(rid,'operator_notes',noteId,1)}));
  }
  if(parts[0]==='transactions'&&request.method==='POST'&&parts.length===1){
   keys(data,['group_id','payee_id','network','provider_reference','amount_rwf','observed_at','evidence','payer_name','verification_status','reason']);
   if(data.verification_status&&data.verification_status!=='pending')unavailable();text(data.reason??request.headers.get('X-Collect-Review-Reason'),'reason',500);
   if(typeof data.evidence!=='string')unavailable();const groupId=uuid(data.group_id),amount=integer(data.amount_rwf,'amount_rwf',1);
   if(data.payee_id&&uuid(data.payee_id)!==groupId)fail(400,'invalid_receiver','Select this group recorded receiver.');
   if(data.observed_at===undefined)fail(400,'observed_at_required','Record when this evidence was observed.');
   const value={collection_id:groupId,amount_minor:amount,external_reference:optionalText(data.provider_reference,'reference',200),observed_at:iso(data.observed_at),
    evidence:data.evidence,payer_display_name:data.payer_name??'',reason:text(data.reason,'reason',500),request_id:rid,admin_bridge_request:source};
   const reply=await evidenceRoute(await adminInternalRequest(request,scoped,account,'/v1/evidence','POST',value),scoped,actor);if(!reply)unavailable();
   const result=await reply.json();await adminAccountSession(request,env);return json(receipt(rid,'transactions',result.id,1));
  }
  if(parts[0]==='transactions'&&parts[2]==='reverse'&&request.method==='POST'){
   const result=await compensationRpc('admin_reverse_payment_v1',{p_payment_id:uuid(parts[1]),p_expected_revision:integer(data.expected_version,'expected_version',1),p_request_id:rid,p_reason:text(data.reason,'reason',500),admin_bridge_request:source},scoped,actor);
   return json(receipt(rid,'transactions',result.value.payment_id,result.value.revision));
  }
  return json(await genericMutation(request,scoped,account,actor,parts,data,rid,source));
 }
 if(section==='evidence'&&request.method==='GET'&&parts.length===1){
  const reply=await evidenceRoute(await adminInternalRequest(request,base,account,`/v1/evidence/${uuid(parts[0])}`,'GET'),base,actor);if(!reply)unavailable();
  await adminAccountSession(request,env);return reply;
 }
 if(section==='reconciliations'){
  if(!actor.permissions.has('payments.read'))fail(403,'permission_required','Payment review is unavailable.');
  if(request.method==='GET'){
   if(!actor.permissions.has('reconciliations.read'))fail(403,'permission_required','Payment reconciliation is unavailable.');
   if(parts[0]==='requests'){if(parts.length>2)fail(404,'not_found','This request view is unavailable.');return json(await operatingRead(request,base,account,['requests',parts[1]],url));}
   return json(await canonicalReconciliationRead(base,account,actor,parts,url));
  }
  if(request.method!=='POST')unavailable();
  if(!actor.permissions.has('users.read'))fail(403,'permission_required','Recorded member identity review is unavailable.');
  const data=await readJson(request),key=request.headers.get('Idempotency-Key'),rid=await requestId(account,key),source={method:request.method,path:url.pathname,body:data};
  const reconciliationBase=accountDatabase(env,account,'users.read'),scoped=requestEnvironment(reconciliationBase,account,key,rid,`reconciliations.${parts.join('.')}`,source);let result;
  if(parts.length===2&&parts[1]==='proposals'){
   if(!actor.permissions.has('reconciliations.propose'))fail(403,'permission_required','Payment attribution is unavailable.');
   keys(data,['member_user_id','amount_rwf','expected_transaction_version','expected_member_version','expected_membership_version','expected_payment_identity','reason']);
   const payload={p_payment_id:uuid(parts[0]),p_member_id:uuid(data.member_user_id),p_request_id:rid,admin_bridge_request:source};
   const replay=await retainedResponse(scoped,actor,'propose_payment_reconciliation_v2',rid,payload,{permission:'reconciliations.propose',minimumAssurance:2,freshSeconds:300});
   if(replay.found)return json({...marker,...receipt(rid,'reconciliation_proposals',replay.value.id,1),transaction_id:payload.p_payment_id,proposal_status:'proposed',settlement_status:'not_asserted'});
   const p=await first(base,'SELECT * FROM payments WHERE id=?',payload.p_payment_id);if(!p)fail(404,'not_found','This payment was not found.');
   if(integer(data.expected_transaction_version,'transaction version',1)!==p.revision)fail(409,'stale_state','The payment changed. Refresh before continuing.');
   if(integer(data.amount_rwf,'amount_rwf',1)!==p.amount_minor)unavailable();text(data.reason,'reason',500);
   const member=await first(base,`SELECT u.*,m.id AS membership_id,m.revision AS membership_revision,c.revision AS collection_revision,
    c.receiver_momo_number,c.receiver_network,c.receiver_display_label FROM users u JOIN memberships m ON m.user_id=u.id JOIN collections c ON c.id=m.collection_id
    WHERE u.id=? AND c.id=? AND m.active=1 AND u.access_status='active' AND c.status='active'`,payload.p_member_id,p.collection_id);
   if(!member)fail(409,'member_changed','The selected member is no longer eligible.');
   const memberVersion=integer(data.expected_member_version,'member version',1),membershipVersion=integer(data.expected_membership_version,'membership version',1);
   if(member.revision!==memberVersion||member.membership_revision!==membershipVersion)fail(409,'member_changed','The selected member changed.');
   const identity=data.expected_payment_identity;if(!identity||typeof identity!=='object'||Array.isArray(identity))fail(400,'invalid_payment_identity','Review the recorded member payment identity.');keys(identity,['display_name','momo_provider','momo_number','momo_pay_code']);
   const actualIdentity={display_name:member.full_name,momo_provider:member.momo_provider,momo_number:member.momo_number,momo_pay_code:member.momo_pay_code};
   if(!member.full_name||!member.momo_number||stableJson(identity)!==stableJson(actualIdentity))fail(409,'member_changed','The recorded payment identity changed.');
   const gate=domainGuard(base,`EXISTS(SELECT 1 FROM users u JOIN memberships m ON m.user_id=u.id JOIN collections c ON c.id=m.collection_id
    WHERE u.id=? AND u.revision=? AND u.access_status='active' AND m.id=? AND m.revision=? AND m.active=1 AND c.id=? AND c.revision=? AND c.status='active')`,
    [member.id,memberVersion,member.membership_id,membershipVersion,p.collection_id,member.collection_revision]);
   const snapshot=base.DB.prepare(`INSERT INTO admin_bridge_reconciliation_snapshots(reconciliation_id,collection_id,collection_revision,member_id,member_revision,membership_id,membership_revision,payment_identity_json,receiver_number,receiver_network,receiver_label,created_at)
    SELECT id,?,?,?,?,?,?,?,?,?,?,? FROM reconciliations WHERE request_id=?`).bind(p.collection_id,member.collection_revision,member.id,memberVersion,member.membership_id,membershipVersion,stableJson(actualIdentity),member.receiver_momo_number,member.receiver_network,member.receiver_display_label,now(),rid);
   if(p.evidence_id){const retained=await first(base,'SELECT receiver_momo_number,receiver_network,receiver_display_label FROM payment_evidence WHERE id=?',p.evidence_id);
    if(!retained||retained.receiver_momo_number!==member.receiver_momo_number||retained.receiver_network!==member.receiver_network||retained.receiver_display_label!==member.receiver_display_label)fail(409,'receiver_changed','The current receiver differs from the retained evidence. Review the receiver history before attribution.');}
   result=await financialRpc('propose_payment_reconciliation_v2',payload,requestEnvironment(reconciliationBase,account,key,rid,`reconciliations.${parts.join('.')}`,source,{before:[gate[0]],after:[snapshot,gate[1]]}),actor,{permission:'reconciliations.propose',freshSeconds:300,reason:data.reason});
   return json({...marker,...receipt(rid,'reconciliation_proposals',result.value.id,1),transaction_id:p.id,proposal_status:'proposed',settlement_status:'not_asserted'});
  }
  if(parts.length===3&&parts[0]==='proposals'&&parts[2]==='reviews'){
   if(!actor.permissions.has('reconciliations.review')||account.role==='staff')fail(403,'permission_required','Independent payment review is unavailable.');
   keys(data,['outcome','expected_proposal_version','expected_transaction_version','reason']);if(!['approved','rejected'].includes(data.outcome))unavailable();integer(data.expected_proposal_version,'proposal version',1,1);text(data.reason,'reason',500);
   const approved=data.outcome==='approved',operation=approved?'approve_payment_reconciliation_v2':'reject_payment_reconciliation_v2';
   const payload={p_reconciliation_id:uuid(parts[1]),p_request_id:rid,admin_bridge_request:source};
   const replay=await retainedResponse(scoped,actor,operation,rid,payload,{permission:'reconciliations.review',minimumAssurance:2,freshSeconds:300});
   if(replay.found)return json({...marker,...receipt(rid,'reconciliation_proposals',parts[1],2),transaction_id:replay.value.payment_id,proposal_status:replay.value.status,transaction_version:replay.value.payment_revision??replay.value.expected_payment_revision+1,settlement_status:'not_asserted'});
   const snapshot=await first(base,`SELECT s.*,r.payment_id,p.revision AS payment_revision FROM admin_bridge_reconciliation_snapshots s JOIN reconciliations r ON r.id=s.reconciliation_id JOIN payments p ON p.id=r.payment_id WHERE r.id=?`,payload.p_reconciliation_id);
   if(!snapshot)fail(409,'review_snapshot_unavailable','A retained identity review snapshot is required.');
   if(integer(data.expected_transaction_version,'transaction version',1)!==snapshot.payment_revision)fail(409,'stale_state','The payment changed. Refresh before continuing.');
   const identity=JSON.parse(snapshot.payment_identity_json),gate=domainGuard(base,`EXISTS(SELECT 1 FROM collections c JOIN memberships m ON m.collection_id=c.id JOIN users u ON u.id=m.user_id
    WHERE c.id=? AND c.revision=? AND c.status='active' AND c.receiver_momo_number IS ? AND c.receiver_network IS ? AND c.receiver_display_label IS ?
    AND m.id=? AND m.revision=? AND m.active=1 AND u.id=? AND u.revision=? AND u.access_status='active'
    AND u.full_name=? AND u.momo_provider=? AND u.momo_number=? AND u.momo_pay_code=?)`,[snapshot.collection_id,snapshot.collection_revision,snapshot.receiver_number,snapshot.receiver_network,snapshot.receiver_label,
    snapshot.membership_id,snapshot.membership_revision,snapshot.member_id,snapshot.member_revision,identity.display_name,identity.momo_provider,identity.momo_number,identity.momo_pay_code]);
   result=await financialRpc(operation,payload,requestEnvironment(reconciliationBase,account,key,rid,`reconciliations.${parts.join('.')}`,source,approved?{before:[gate[0]],after:[gate[1]]}:{}),actor,{permission:'reconciliations.review',freshSeconds:300,reason:data.reason});
   return json({...marker,...receipt(rid,'reconciliation_proposals',parts[1],2),transaction_id:result.value.payment_id,proposal_status:result.value.status,transaction_version:result.value.payment_revision,settlement_status:'not_asserted'});
  }
  unavailable();
 }
 unavailable();
}

/** Composite same-origin Admin handler. The root router calls this BEFORE its
 * bearer /v1 auth and CORS dispatcher. No ASSETS or second operating DB here. */
export async function handleAdmin(request,env,ctx){
 const path=new URL(request.url).pathname;if(path!=='/api/admin'&&!path.startsWith('/api/admin/'))return null;
 const account=await handleAdminAccounts(request,env,ctx);if(account)return account;
 try{return await notificationOperatorManagementRoute(request,env)??await notificationOperatorRoute(request,env)??await bridgeRoute(request,env,ctx);}
 catch(error){const known=error instanceof ApiError,constraint=/admin_bridge_guards|admin_bridge_state|UNIQUE constraint|FOREIGN KEY constraint/.test(String(error));
  return json({error:{code:known?error.code:constraint?'state_conflict':'service_unavailable',message:known?error.message:constraint?'The record or related state changed. Refresh before continuing.':'The request could not be completed.'}},known?error.status:constraint?409:503);}
}
