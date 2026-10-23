import {requireFreshAdminEmail} from './admin_email_policy.js';
import {ApiError,json,first,id,digest,stableJson,uuid} from './core.js';
import {authRequest} from '../auth-http.js';
import {sendTransactionalEmail,transactionalEmailAvailable} from './email_delivery.js';
import {renderAdminAccessNotice} from './admin_access_notice_email.js';

const OWNER='info@ikanisa.com';
const states=new Set(['reserved','dispatching','accepted','rejected','unknown','already_registered']);
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const controls=/[\u0000-\u001f\u007f-\u009f]/;
const validId=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const email=value=>{
 if(typeof value!=='string'||value.length>254||value!==value.toLowerCase()||controls.test(value))return false;
 const parts=value.split('@');if(parts.length!==2)return false;
 const [local,domain]=parts,labels=domain.split('.');
 return !!local&&local.length<=64&&!local.startsWith('.')&&!local.endsWith('.')&&!local.includes('..')&&
  /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(local)&&labels.length>=2&&/^[a-z]{2,63}$/.test(labels.at(-1))&&
  labels.every(label=>/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label));
};
const origin=value=>{try{return typeof value==='string'&&!controls.test(value)&&new URL(value).protocol==='https:'&&new URL(value).origin===value;}catch{return false;}};
const reject=(status,code,message)=>{throw new ApiError(status,code,message);};

function actorArguments(account) {
 if(account?.role!=='owner'||account.email!==OWNER||!account.permissions?.includes('admin_users.manage')||
  !validId(account.id)||!validId(account.public_id)||typeof account.token_hash!=='string'||!/^[a-f0-9]{64}$/.test(account.token_hash)||!origin(account.origin))
  reject(403,'owner_required','Verify the owner sign-in before managing team invitations.');
 requireFreshAdminEmail(account);
 return [account.id,account.token_hash,account.origin,account.public_id];
}
function keyOf(request) {
 const key=request.headers.get('Idempotency-Key');
 if(typeof key!=='string'||!/^[A-Za-z0-9._:-]{8,200}$/.test(key))reject(400,'invitation_request_key_required','Use an original invitation request reference.');
 return key;
}
function checked(row,{missing=false}={}) {
 const value=row?.result;
 if(missing&&object(value)&&value.found===false)return value;
 if(!object(value)||value.contractVersion!==2||!validId(value.requestId)||!validId(value.id)||!validId(value.principalId)||!email(value.email)||
  !states.has(value.emailStatus)||!['invite','resend','notice_repair'].includes(value.operation)||!['invited','active','revoked'].includes(value.accessStatus)||
  !['auth_invite','access_notice'].includes(value.messageKind)||value.templateVersion!==(value.messageKind==='auth_invite'?'managed_invite_v1':'access_notice_v1')||
  !(value.managedAuthUserId===null||validId(value.managedAuthUserId))||!(value.sourceRequestId===null||validId(value.sourceRequestId))||
  (value.messageKind==='access_notice'?(!validId(value.managedAuthUserId)||!origin(value.noticeOrigin)||value.emailStatus==='already_registered'):value.noticeOrigin!==null)||
  value.duplicate!==undefined&&typeof value.duplicate!=='boolean'||value.replayed!==undefined&&typeof value.replayed!=='boolean')throw new Error('invalid_invitation_state');
 return value;
}
function publicReceipt(row) {
 const state=['reserved','dispatching'].includes(row.emailStatus)?'unknown':row.emailStatus;
 return {contractVersion:2,id:row.id,requestId:row.requestId,messageKind:row.messageKind,
  [row.messageKind==='auth_invite'?'emailStatus':'noticeStatus']:state,accessStatus:row.accessStatus,
  operation:row.operation,replayed:row.replayed===true,duplicate:row.duplicate===true,sourceRequestId:row.sourceRequestId};
}
const failure=(status,code,message,extra={})=>json({ok:false,...extra,error:{code,message}},status);
function operationUnknown(row=null) {
 return failure(503,'invitation_operation_unknown','The invitation request could not be confirmed. Check the original request before trying again.',
  {outcome:'operation_unknown',...(row?publicReceipt({...row,emailStatus:'unknown'}):{})});
}
function receipt(row) {
 const result=publicReceipt(row);
 if(result.duplicate)return failure(409,'invitation_existing_request','An invitation request already exists. Check the original request.',{...result,outcome:'existing_request'});
 if(row.emailStatus==='accepted')return json({ok:true,...result,outcome:'accepted'});
 if(row.emailStatus==='already_registered')return failure(409,'invitation_notification_required','Account already registered. Check linked Admin access. No invitation email was sent.',{...result,outcome:'notification_pending'});
 if(row.emailStatus==='rejected')return failure(422,'invitation_rejected','The invitation request was rejected.',{...result,outcome:'delivery_rejected'});
 return failure(503,'invitation_delivery_unknown','Invitation sending is unconfirmed. Check the original request before trying again.',{...result,outcome:'delivery_unknown'});
}
const sql={
 prepare:'SELECT private.admin_invitation_v2_prepare(?,?,?,?,?,?,?,?,?,?,?,?,?::uuid) AS result',
 claim:'SELECT private.admin_invitation_v2_claim(?,?,?,?,?::uuid,?::uuid) AS result',
 finish:'SELECT private.admin_invitation_v2_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result',
 recover:'SELECT private.admin_invitation_v2_recover(?,?,?,?,?) AS result',
 list:'SELECT private.admin_invitation_v2_list(?,?,?,?) AS result',
};
const transition=(env,kind,args)=>first(env,sql[kind],...args);
function knownDatabaseFailure(error) {
 const code=typeof error?.message==='string'?error.message:'';
 if(code==='recent_email_sign_in_required'||code==='recent_email_verification_required')reject(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
 if(code==='admin_invitation_authority')reject(403,'admin_access_changed','Your account access changed. Sign in and verify again.');
 if(code==='admin_invitation_idempotency_conflict')reject(409,'idempotency_conflict','This original request has different invitation details.');
 if(code==='admin_invitation_identity_conflict')reject(409,'invitation_identity_conflict','The linked account requires an Admin access review.');
 if(code==='admin_invitation_subject_unavailable')reject(409,'not_pending','This account does not have a pending invitation.');
 if(code==='admin_invitation_version_conflict')reject(409,'invitation_version_conflict','Check this invitation using its original request version.');
 if(code==='admin_invitation_invalid')reject(400,'invalid_invitation','The invitation request is invalid.');
}
function sameIntent(a,b) {
 return ['requestId','id','principalId','email','operation','messageKind','templateVersion','managedAuthUserId','noticeOrigin','sourceRequestId'].every(key=>a[key]===b[key]);
}
function acceptedInvite(data,target) {
 return object(data)&&validId(data.id)&&(target.managedAuthUserId===null||data.id===target.managedAuthUserId)&&
  typeof data.email==='string'&&data.email.toLowerCase()===target.email&&data.email_confirmed_at==null&&
  typeof data.invited_at==='string'&&data.invited_at.length<=64&&Number.isFinite(Date.parse(data.invited_at));
}
function noticeAvailable(env) {
 return env.AUTH_EMAIL?.provider==='workspace_smtp_v1'&&typeof env.AUTH_EMAIL.send==='function'&&env.AUTH_EMAIL_FROM===OWNER&&transactionalEmailAvailable(env);
}
function closedBody(body,keys) {
 if(!object(body)||Object.keys(body).some(key=>!keys.includes(key)))reject(400,'invalid_invitation','The invitation request is invalid.');
}
function listReceipt(result,account) {
 if(!object(result)||!Array.isArray(result.members)||!object(result.permissionsByRole))throw new Error('invalid_invitation_list');
 const permissionsByRole={};
 for(const role of ['owner','admin','staff']){
  const permissions=result.permissionsByRole[role];
  if(!Array.isArray(permissions)||permissions.some(v=>typeof v!=='string'||!v.length||v.length>120||controls.test(v)))throw new Error('invalid_invitation_list');
  permissionsByRole[role]=permissions;
 }
 const members=result.members.map(member=>{
  const date=value=>value===null||typeof value==='string'&&value.length<=64&&Number.isFinite(Date.parse(value));
  if(!object(member)||!validId(member.id)||!email(member.email)||!['owner','admin','staff'].includes(member.role)||!['invited','active','revoked'].includes(member.status)||
   !(member.publicId===null||typeof member.publicId==='string'&&member.publicId.length>=1&&member.publicId.length<=64&&!controls.test(member.publicId))||
   !(member.displayName===null||typeof member.displayName==='string'&&member.displayName.length<=120&&!controls.test(member.displayName))||
   typeof member.createdAt!=='string'||!date(member.createdAt)||!date(member.invitedAt)||!date(member.acceptedAt))throw new Error('invalid_invitation_list');
  let invitation=null;
  if(member.invitation!==null){const checkedInvitation=checked({result:member.invitation});if(checkedInvitation.id!==member.id||checkedInvitation.email!==member.email)throw new Error('invalid_invitation_list');invitation=publicReceipt(checkedInvitation);}
  return {id:member.id,publicId:member.publicId,email:member.email,role:member.role,status:member.status,displayName:member.displayName,
   createdAt:member.createdAt,invitedAt:member.invitedAt,acceptedAt:member.acceptedAt,invitation};
 });
 return json({contractVersion:2,currentEmail:account.email,canManage:true,permissionsByRole,members});
}

// SQL reserves the immutable identity/kind and the single dispatch claim. Each
// transport runs outside that transaction; an uncertain result never falls back.
export async function handleAdminInvitationV2(request,env,account,body,path) {
 const resend=/^\/team\/v2\/([0-9a-f-]{36})\/resend$/.exec(path);
 const repair=/^\/team\/v2\/([0-9a-f-]{36})\/access-notice$/.exec(path);
 const recover=path==='/team/v2/invitation-status',list=path==='/team/v2';
 if(path!=='/team/v2/invite'&&!resend&&!repair&&!recover&&!list)return null;
 if(request.method!==((recover||list)?'GET':'POST'))reject(405,'method_not_allowed',(recover||list)?'Use GET.':'Use POST.');
 const actor=actorArguments(account);
 if(list){try{return listReceipt((await transition(env,'list',actor))?.result,account);}catch(error){knownDatabaseFailure(error);return failure(503,'invitation_list_unknown','Team invitation status could not be confirmed.');}}
 const key=keyOf(request);
 if(recover){
  try{const retained=checked(await transition(env,'recover',[...actor,key]),{missing:true});return retained.found===false?json({ok:true,contractVersion:2,found:false}):json({ok:true,found:true,...publicReceipt(retained)});}
  catch(error){knownDatabaseFailure(error);return operationUnknown();}
 }
 let targetEmail=null,role=null,display=null,sourceRequestId=null;
 const kind=repair?'notice_repair':resend?'resend':'invite',subject=(resend||repair)?uuid((resend||repair)[1]):id(),principal=id();
 if(kind==='invite'){
  closedBody(body,['email','role','displayName']);
  targetEmail=typeof body.email==='string'?body.email.trim().toLowerCase():'';
  role=body.role;display=typeof body.displayName==='string'?body.displayName.trim():'';
  if(!email(targetEmail)||targetEmail===OWNER||!['admin','staff'].includes(role)||display.length>120||controls.test(display)||body.displayName!==undefined&&typeof body.displayName!=='string')reject(400,'invalid_invitation','The invitation request is invalid.');
 }else if(repair){closedBody(body,['sourceRequestId']);if(!validId(body.sourceRequestId))reject(400,'invalid_invitation','Use the original registered-account invitation reference.');sourceRequestId=body.sourceRequestId;}
 else closedBody(body,[]);
 const bodyHash=await digest(stableJson(kind==='invite'?{contractVersion:2,kind,email:targetEmail,role,displayName:display}:{contractVersion:2,kind,subjectId:subject,sourceRequestId}));
 let prepared;
 try{prepared=checked(await transition(env,'prepare',[...actor,key,kind,subject,principal,targetEmail,role,display,bodyHash,sourceRequestId]));}
 catch(error){knownDatabaseFailure(error);return operationUnknown();}
 if(prepared.duplicate===true||prepared.emailStatus!=='reserved')return receipt(prepared);
 if(prepared.messageKind==='access_notice'&&(prepared.noticeOrigin!==account.origin||!noticeAvailable(env)))return failure(503,'invitation_transport_unavailable','Staff access was retained. Email sending is unavailable; check this same request after configuration.',{...publicReceipt(prepared),outcome:'transport_unavailable'});
 const claim=id();let claimed;
 try{claimed=checked(await transition(env,'claim',[...actor,prepared.requestId,claim]));}
 catch(error){knownDatabaseFailure(error);return operationUnknown(prepared);}
 if(!sameIntent(prepared,claimed))return operationUnknown(prepared);
 if(claimed.claimed!==true)return receipt(claimed);
 if(claimed.emailStatus!=='dispatching'||claimed.duplicate===true)return operationUnknown(prepared);
 let state='accepted',providerCode=null;
 try{
  if(claimed.messageKind==='access_notice'){
   if(claimed.noticeOrigin!==account.origin||!noticeAvailable(env))throw new Error('notice_transport_changed');
   await sendTransactionalEmail(env,{to:claimed.email,...renderAdminAccessNotice(claimed.noticeOrigin)});
  }else{
   const data=await authRequest(env,'/invite',{admin:true,body:{email:claimed.email,data:{collect_invitation:true}}});
   if(!acceptedInvite(data,claimed)){state='unknown';providerCode='provider_response_unconfirmed';}
  }
 }catch(error){
  if(claimed.messageKind==='auth_invite'&&error instanceof ApiError&&error.status===422&&error.code==='email_exists'){state='already_registered';providerCode='email_exists';}
  else if(claimed.messageKind==='auth_invite'&&error instanceof ApiError&&[400,401,403,422,429].includes(error.status)){state='rejected';providerCode='provider_rejected';}
  else{state='unknown';providerCode='provider_outcome_unknown';}
 }
 try{
  const completed=checked(await transition(env,'finish',[...actor,prepared.requestId,claim,state,providerCode]));
  if(!sameIntent(prepared,completed)||completed.emailStatus!==state)return operationUnknown(prepared);
  return receipt(completed);
 }catch{return operationUnknown(prepared);}
}
