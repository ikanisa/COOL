import {ApiError,json,readJson,uuid} from './core.js';
import {adminAccountSession} from './admin_accounts.js';
import {adminEmailArguments} from './admin_email_policy.js';
import {requireBuriMunsiOwner} from './admin_burimunsi_authority.js';
import {PostgresNativeAuthority} from './burimunsi/postgres-authority.js';
import {validOperatorCapabilities} from './burimunsi/operator-access.mjs';
import {normalizePhone} from './burimunsi/values.js';
import {selectAdminCollection} from './burimunsi/admin-scope-selection.js';

const BASE='/api/admin/burimunsi/operators';
const DIRECTORY_SQL='SELECT private.burimunsi_operator_directory($1,$2,$3,$4,$5,$6::uuid) AS result';
const APPROVAL_GUARD_SQL=`,
 COALESCE(pg_catalog.has_function_privilege(pg_catalog.to_regprocedure(
  'private.burimunsi_operator_approve_v2(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint,text)')::oid,'EXECUTE'),false)
 AND NOT COALESCE(pg_catalog.has_function_privilege(pg_catalog.to_regprocedure(
  'private.burimunsi_operator_approve(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint)')::oid,'EXECUTE'),false)
 AS guarded_approval`;
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
function checkedReceipt(value,requestId,expectedPrincipal=null){
 if(!value||value.contractVersion!==1||value.requestId!==requestId||value.applied!==true||
   typeof value.active!=='boolean'||!Number.isSafeInteger(value.version)||value.version<1||
   typeof value.principalId!=='string')throw Error('Invalid BuriMunsi approval receipt');
 uuid(value.principalId);
 if(expectedPrincipal!==null&&value.principalId!==expectedPrincipal)throw Error('BuriMunsi approval principal changed');
 return value;
}
function knownFailure(error){
 const code=error?.message;
 if(['recent_email_sign_in_required','recent_email_verification_required'].includes(code))
  fail(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
 if(['admin_invitation_authority','burimunsi_shared_operator_unavailable'].includes(code))
  fail(403,'burimunsi_operator_unavailable','Refresh the approved Collect account before continuing.');
 if(['burimunsi_approval_changed','burimunsi_approval_request_conflict'].includes(code))
  fail(409,'burimunsi_approval_changed','This approval or its original request changed. Refresh before continuing.');
 if(code==='burimunsi_invalid_approval')fail(400,'invalid_approval','Check the selected account and BuriMunsi access.');
 if(error?.code==='23505')fail(409,'burimunsi_duplicate_phone','This BuriMunsi login phone already has an owner.');
}

/** Owner approvals inside the EXISTING Collect Admin/BFF. No invitation, email,
 * Auth signup, PIN issuance, gateway enrollment or activation is performed.
 * The database rechecks current owner/cookie/email authority in the same command.
 */
export async function adminBuriMunsiOperators(request,env){
 const url=new URL(request.url),path=url.pathname;
 if(path!==BASE&&!path.startsWith(BASE+'/'))return null;
 const recovery=path.match(/^\/api\/admin\/burimunsi\/operators\/requests\/([^/]+)$/);
 if(path!==BASE&&!recovery)fail(404,'not_found','This BuriMunsi view does not exist.');
 const negotiatesApproval=request.method==='GET'&&path===BASE&&url.searchParams.get('approvalContract')==='2';
 for(const key of url.searchParams.keys()){
  if(url.searchParams.getAll(key).length!==1||(key!=='collectionId'&&!(key==='approvalContract'&&negotiatesApproval)))
   fail(400,'invalid_request','Choose one collection and a supported directory format.');
 }
 if(request.method!=='GET'&&!(request.method==='POST'&&path===BASE))fail(405,'method_not_allowed','Use the operator view or approval action.');
 const account=await adminAccountSession(request,env);
 await requireBuriMunsiOwner({request,env,account,permissions:['admin_users.manage'],
  ownerMessage:'The Collect owner manages BuriMunsi access.',
  unavailableCode:'burimunsi_unavailable',unavailableMessage:'BuriMunsi is not configured for this deployment.'});
 const body=request.method==='POST'?await readJson(request,4096):null;
 const group=await selectAdminCollection({env,account,requested:body?.collectionId??url.searchParams.get('collectionId')});
 const authority=new PostgresNativeAuthority({db:env.DB,groupId:group}),actor=adminEmailArguments(account);
 if(request.method==='GET'){
  const requestId=recovery?uuid(recovery[1]):null;
  try{
   // The shared owner helper locks/revalidates its BFF tuple; this is an ordinary
   // guarded transaction, with no business mutation during directory reads.
   const row=await authority.write(async sql=>(await sql.unsafe(
    negotiatesApproval?DIRECTORY_SQL+APPROVAL_GUARD_SQL:DIRECTORY_SQL,
    [...actor,group,requestId]))[0]);
   const value=row?.result;
   if(!value||value.contractVersion!==1)throw Error('Invalid BuriMunsi operator directory');
   if(requestId){
    if(typeof value.found!=='boolean')throw Error('Invalid BuriMunsi request outcome');
    if(value.found)checkedReceipt(value.receipt,requestId);
    return json({...value,collectionId:group},200,{'Pragma':'no-cache'});
   }else if(value.collectionId!==group||typeof value.configured!=='boolean'||
     !Array.isArray(value.approvals)||!Array.isArray(value.team)||value.approvals.length>500||value.team.length>500)
    throw Error('Invalid BuriMunsi operator directory');
   // Only the guarded runtime transaction can attest that the principal-bound
   // command is callable and the prior command is no longer callable.
   return json({contractVersion:1,collectionId:group,configured:value.configured,team:value.team,approvals:value.approvals,
    ...(negotiatesApproval&&row.guarded_approval===true?{approvalContract:2}:{})},200,{'Pragma':'no-cache'});
  }catch(error){knownFailure(error);fail(503,'burimunsi_unavailable','The current BuriMunsi access could not be confirmed.');}
 }
 const allowed=['requestId','collectionId','adminId','principalId','phone','role','capabilities','active','expectedVersion'];
 if(Object.keys(body).length!==allowed.length||!allowed.every(k=>Object.hasOwn(body,k)))
  fail(400,'invalid_request','Supply the selected Collect account and exact approval fields.');
 const requestId=uuid(body.requestId),adminId=uuid(body.adminId),principalId=uuid(body.principalId);
 const headerKey=request.headers.get('Idempotency-Key');
 if(headerKey!==null&&headerKey!==requestId)fail(400,'invalid_request','Keep the original approval request reference.');
 // An expected scope is a concurrency assertion, never a client selector.
 // A deployment/group switch must not retarget a retained owner request.
 if(body.collectionId!==group)fail(409,'burimunsi_scope_changed','The BuriMunsi group changed. Refresh this workspace before continuing.');
 let phone;try{phone=normalizePhone(body.phone);}catch{fail(400,'invalid_phone','Enter a Rwanda login phone number.');}
 if(typeof body.active!=='boolean'||!Number.isSafeInteger(body.expectedVersion)||
   body.expectedVersion<0||body.expectedVersion>=Number.MAX_SAFE_INTEGER||!validOperatorCapabilities(body.role, body.capabilities))
  fail(400,'invalid_approval','Choose the exact BuriMunsi role and access.');
 try{
  const receipt=await authority.write(async sql=>(await sql.unsafe(
   'SELECT private.burimunsi_operator_approve_v2($1,$2,$3,$4,$5,$6::uuid,$7,$8,$9,$10::text[],$11,$12,$13) AS result',
   [...actor,group,requestId,adminId,phone,body.role,[...body.capabilities].sort(),body.active,body.expectedVersion,principalId]))[0]?.result);
  return json(checkedReceipt(receipt,requestId,principalId),200,{'Pragma':'no-cache'});
 }catch(error){
  knownFailure(error);
  // COMMIT may have succeeded. Retain the exact request ID, check its outcome,
  // and never generate/retry a replacement approval automatically.
  return json({contractVersion:1,requestId,outcome:'operation_unknown',
   error:{code:'burimunsi_approval_unknown',message:'Approval was not confirmed. Check the original request before trying again.'}},503,{'Pragma':'no-cache'});
 }
}
