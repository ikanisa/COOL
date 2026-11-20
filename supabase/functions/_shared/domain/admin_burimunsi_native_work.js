import {ApiError,json,readJson,uuid} from './core.js';
import {adminAccountSession} from './admin_accounts.js';
import {adminEmailArguments,requireFreshAdminEmail} from './admin_email_policy.js';
import {preliminaryCurrentOwner} from './admin_owner_precheck.js';
import {applicationWork,applicationWorkTuple} from '../application-fence.js';
import {verifyDeploymentProfile} from '../deployment-profile.js';
import {adminSessionOriginMatches} from '../admin-security.js';
import {PostgresNativeAuthority} from './burimunsi/postgres-authority.js';
import {PostgresNativeWorkGrants} from './burimunsi/postgres-native-work-grants.js';
import {selectAdminCollection} from './burimunsi/admin-scope-selection.js';

const BASE='/api/admin/burimunsi/native-work-grants';
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const headers={'Cache-Control':'no-store, private','Pragma':'no-cache','Vary':'Cookie, Origin'};
const exact=(body,required,optional=[])=>body&&typeof body==='object'&&!Array.isArray(body)&&
 required.every(k=>Object.hasOwn(body,k))&&Object.keys(body).every(k=>required.includes(k)||optional.includes(k));
function known(error){
 if(error instanceof ApiError)throw error;
 if(['recent_email_sign_in_required','recent_email_verification_required'].includes(error?.message))
  fail(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
 if(error?.code==='42501')fail(403,'native_work_authority_denied','The owner, policy or financial permission changed.');
 if(error?.code==='23505')fail(409,'native_work_request_conflict','The original request or worker grant changed.');
 if(['22023','22P02'].includes(error?.code))fail(400,'invalid_request','Check the worker grant details.');
}

/** Uses the existing Owner cookie, CSRF, recent-email and scope selection.
 * This route only records/revokes a service grant; it cannot post a payment. */
export async function adminBuriMunsiNativeWork(request,env){
 const url=new URL(request.url),path=url.pathname;
 if(path!==BASE&&!path.startsWith(BASE+'/'))return null;
 const recovery=path.match(/^\/api\/admin\/burimunsi\/native-work-grants\/requests\/([^/]+)$/);
 if(path!==BASE&&!recovery)fail(404,'not_found','This worker action does not exist.');
 if(!(request.method==='POST'&&path===BASE)&&!(request.method==='GET'&&recovery))fail(405,'method_not_allowed','Use the worker action or its request outcome.');
 for(const k of url.searchParams.keys())if(k!=='collectionId'||url.searchParams.getAll(k).length!==1)fail(400,'invalid_request','Choose one collection.');
 if(request.method==='POST'&&url.search)fail(400,'invalid_request','Use the worker action without filters.');
 const account=await adminAccountSession(request,env);
 if(!await preliminaryCurrentOwner(env,account)||!['admin_users.manage','receivers.manage'].every(p=>account.permissions.includes(p)))
  fail(403,'owner_required','The Collect owner manages worker access.');
 requireFreshAdminEmail(account);
 const work=applicationWork(env),tuple=applicationWorkTuple(work),profile=await verifyDeploymentProfile(env);
 if(work.kind!=='http_admin'||env.DB?.applicationWork!==work||tuple[2]!==env.BUILD_SOURCE_ID||
  !adminSessionOriginMatches(request,env,profile,account))
  fail(503,'native_work_unavailable','Worker access is unavailable for this deployment.');
 const body=request.method==='POST'?await readJson(request,2048):null;
 const group=await selectAdminCollection({env,account,requested:body?.collectionId??url.searchParams.get('collectionId')});
 const service=new PostgresNativeWorkGrants({authority:new PostgresNativeAuthority({db:env.DB,groupId:group}),actorArgs:adminEmailArguments(account)});
 if(recovery){
  const requestId=uuid(recovery[1]);
  try{return json({requestId,...await service.lookup(requestId)},200,headers);}
  catch(error){known(error);fail(503,'native_work_unavailable','The original worker request could not be confirmed.');}
 }
 if(!body||body.collectionId!==group)fail(409,'burimunsi_scope_changed','The selected group changed. Refresh before continuing.');
 const operation=body.operation,issue=operation==='issue';
 if(!issue&&operation!=='revoke')fail(400,'invalid_request','Choose an issue or revoke action.');
 if(issue&&!exact(body,['operation','collectionId','requestId','grantId','owner','version','policyVersion','expiresAt'],['enabled'])||
  !issue&&!exact(body,['operation','collectionId','requestId','grantId']))fail(400,'invalid_request','Supply the exact worker grant fields.');
 const requestId=uuid(body.requestId),grantId=uuid(body.grantId);
 if(request.headers.get('Idempotency-Key')!==requestId)fail(400,'idempotency_required','Use the original worker request identity.');
 if(issue&&(typeof body.owner!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(body.owner)||!Number.isSafeInteger(body.version)||body.version<1||
  typeof body.policyVersion!=='string'||body.policyVersion.length<1||body.policyVersion.length>128||/[\u0000-\u001f\u007f]/.test(body.policyVersion)||
  !Number.isSafeInteger(body.expiresAt)||body.expiresAt<1||(Object.hasOwn(body,'enabled')&&typeof body.enabled!=='boolean')))
  fail(400,'invalid_request','Check the worker grant details.');
 if(issue&&!account.permissions.includes('payments.reconcile'))fail(403,'financial_permission_required','The owner needs current financial permission to issue a worker grant.');
 try{
  const receipt=issue?await service.issue({requestId,grantId,owner:body.owner,version:body.version,policyVersion:body.policyVersion,
    expiresAt:body.expiresAt,...(Object.hasOwn(body,'enabled')?{enabled:body.enabled}:{})}):await service.revoke({requestId,grantId});
  return json({requestId,...receipt},200,headers);
 }catch(error){known(error);
  return json({requestId,outcome:'operation_unknown',error:{code:'native_work_request_unknown',
   message:'The worker action was not confirmed. Check the original request before trying again.'}},503,headers);
 }
}
