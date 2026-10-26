import {requireFreshAdminEmail} from './admin_email_policy.js';
import {ApiError,json,first,id,digest,stableJson,uuid} from './core.js';
import {authRequest} from '../auth-http.js';

const OWNER='info@ikanisa.com';
const internalStates=new Set(['reserved','dispatching','accepted','rejected','unknown','already_registered']);
const isObject=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const email=value=>typeof value==='string'&&value.length<=254&&/^\S+@[^\s@]+\.[^\s@]+$/.test(value);
const validId=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const reject=(status,code,message)=>{throw new ApiError(status,code,message);};

function actorArguments(account) {
 if(account?.role!=='owner'||account.email!==OWNER||!account.permissions?.includes('admin_users.manage')||
  !validId(account.id)||!validId(account.public_id)||typeof account.token_hash!=='string'||!/^[a-f0-9]{64}$/.test(account.token_hash)||
  typeof account.origin!=='string'||!account.origin.startsWith('https://'))reject(403,'owner_required','Verify the owner sign-in before managing team invitations.');
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
 if(missing&&isObject(value)&&value.found===false)return value;
 if(!isObject(value)||!validId(value.requestId)||!validId(value.id)||!validId(value.principalId)||!email(value.email)||
  !internalStates.has(value.emailStatus)||!['invite','resend'].includes(value.operation)||
  !['invited','active','revoked'].includes(value.accessStatus)||value.duplicate!==undefined&&typeof value.duplicate!=='boolean')throw new Error('invalid_invitation_state');
 return value;
}
function publicReceipt(row) {
 return {id:row.id,requestId:row.requestId,emailStatus:['reserved','dispatching'].includes(row.emailStatus)?'unknown':row.emailStatus,
  accessStatus:row.accessStatus,operation:row.operation,replayed:row.replayed===true,duplicate:row.duplicate===true};
}
function failure(status,code,message,extra={}) {return json({ok:false,...extra,error:{code,message}},status);}
function operationUnknown(row=null) {
 return failure(503,'invitation_operation_unknown','The invitation request could not be confirmed. Check the original request before trying again.',
  {outcome:'operation_unknown',...(row?publicReceipt({...row,emailStatus:'unknown'}):{})});
}
function receipt(row) {
 const result=publicReceipt(row);
 if(result.duplicate)return failure(409,'invitation_existing_request','An invitation request already exists. Check the original request.',{...result,outcome:'existing_request'});
 if(result.emailStatus==='accepted')return json({ok:true,...result,outcome:'accepted'});
 if(result.emailStatus==='already_registered')return failure(409,'invitation_notification_required',
  'Account already registered. Check linked Admin access. No invitation email was sent.',{...result,outcome:'notification_pending'});
 if(result.emailStatus==='rejected')return failure(422,'invitation_rejected','The invitation request was rejected.',{...result,outcome:'delivery_rejected'});
 return failure(503,'invitation_delivery_unknown','Invitation sending is unconfirmed. Check the original request before trying again.',{...result,outcome:'delivery_unknown'});
}
const sql={
 prepare:'SELECT private.admin_invitation_prepare(?,?,?,?,?,?,?,?,?,?,?,?) AS result',
 claim:'SELECT private.admin_invitation_claim(?,?,?,?,?::uuid,?::uuid) AS result',
 finish:'SELECT private.admin_invitation_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result',
 recover:'SELECT private.admin_invitation_recover(?,?,?,?,?) AS result',
};
async function transition(env,kind,args) {return first(env,sql[kind],...args);}
function knownDatabaseFailure(error) {
 const code=typeof error?.message==='string'?error.message:'';
 if(code==='recent_email_sign_in_required'||code==='recent_email_verification_required')reject(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
 if(code==='admin_invitation_authority')reject(403,'admin_access_changed','Your account access changed. Sign in and verify again.');
 if(code==='admin_invitation_idempotency_conflict')reject(409,'idempotency_conflict','This original request has different invitation details.');
 if(code==='admin_invitation_identity_conflict')reject(409,'invitation_identity_conflict','The linked account requires an Admin access review.');
 if(code==='admin_invitation_subject_unavailable')reject(409,'not_pending','This account does not have a pending invitation.');
 if(code==='admin_invitation_invalid')reject(400,'invalid_invitation','The invitation request is invalid.');
}
function acceptedInvite(data,target) {
 return isObject(data)&&validId(data.id)&&typeof data.email==='string'&&data.email.toLowerCase()===target&&
  data.email_confirmed_at==null&&typeof data.invited_at==='string'&&data.invited_at.length<=64&&Number.isFinite(Date.parse(data.invited_at));
}

// Preapproval, target identity, current actor authority and the one-send claim
// are enforced by the additive database protocol. GoTrue remains the mailer;
// no arbitrary SMTP service or legacy password-invitation token is introduced.
export async function handleAdminInvitation(request,env,account,body,path) {
 const resend=/^\/team\/([0-9a-f-]{36})\/resend$/.exec(path);
 const recover=path==='/team/invitation-status';
 if(path!=='/team/invite'&&!resend&&!recover)return null;
 if(request.method!==(recover?'GET':'POST'))reject(405,'method_not_allowed',recover?'Use GET.':'Use POST.');
 const actor=actorArguments(account),key=keyOf(request);
 if(recover){
  try{
   const retained=checked(await transition(env,'recover',[...actor,key]),{missing:true});
   return retained.found===false?json({ok:true,found:false}):json({ok:true,found:true,...publicReceipt(retained)});
  }catch(error){knownDatabaseFailure(error);return operationUnknown();}
 }
 let targetEmail=null,role=null,display=null;
 const kind=resend?'resend':'invite',subject=resend?uuid(resend[1]):id(),principal=id();
 if(!resend){
  targetEmail=typeof body?.email==='string'?body.email.trim().toLowerCase():'';
  role=body?.role;display=typeof body?.displayName==='string'?body.displayName.trim():'';
  if(!email(targetEmail)||targetEmail===OWNER||!['admin','staff'].includes(role)||display.length>120||/[\u0000-\u001f\u007f]/.test(display))reject(400,'invalid_invitation','The invitation request is invalid.');
 }
 const bodyHash=await digest(stableJson(resend?{kind,subjectId:subject}:{kind,email:targetEmail,role,displayName:display}));
 let prepared;
 try{prepared=checked(await transition(env,'prepare',[...actor,key,kind,subject,principal,targetEmail,role,display,bodyHash]));}
 catch(error){knownDatabaseFailure(error);return operationUnknown();}
 if(prepared.duplicate===true||prepared.emailStatus!=='reserved')return receipt(prepared);
 const claim=id();let claimed;
 try{claimed=checked(await transition(env,'claim',[...actor,prepared.requestId,claim]));}
 catch(error){knownDatabaseFailure(error);return operationUnknown(prepared);}
 if(claimed.claimed!==true)return receipt(claimed);
 if(claimed.emailStatus!=='dispatching'||claimed.requestId!==prepared.requestId||claimed.id!==prepared.id||claimed.principalId!==prepared.principalId||claimed.email!==prepared.email)return operationUnknown(prepared);
 let state='accepted',providerCode=null;
 try{
  const data=await authRequest(env,'/invite',{admin:true,body:{email:claimed.email,data:{collect_invitation:true}}});
  if(!acceptedInvite(data,claimed.email)){state='unknown';providerCode='provider_response_unconfirmed';}
 }catch(error){
  if(error instanceof ApiError&&error.status===422&&error.code==='email_exists'){state='already_registered';providerCode='email_exists';}
  else if(error instanceof ApiError&&[400,401,403,422,429].includes(error.status)){state='rejected';providerCode='provider_rejected';}
  else{state='unknown';providerCode='provider_outcome_unknown';}
 }
 try{
  const completed=checked(await transition(env,'finish',[...actor,prepared.requestId,claim,state,providerCode]));
  if(completed.requestId!==prepared.requestId||completed.id!==prepared.id||completed.principalId!==prepared.principalId||completed.email!==prepared.email||completed.emailStatus!==state)return operationUnknown(prepared);
  return receipt(completed);
 }catch{return operationUnknown(prepared);}
}
