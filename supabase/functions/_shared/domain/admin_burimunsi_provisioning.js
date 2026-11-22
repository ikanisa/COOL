import {ApiError,json,readJson,uuid} from './core.js';
import {adminAccountSession} from './admin_accounts.js';
import {adminEmailArguments} from './admin_email_policy.js';
import {BURI_ADMIN_PRIVATE_HEADERS as headers,requireBuriMunsiOwner} from './admin_burimunsi_authority.js';
import {AdminNativeProvisioning,provisioningCommand} from './burimunsi/admin-provisioning.js';
import {selectAdminCollection} from './burimunsi/admin-scope-selection.js';

const BASE='/api/admin/burimunsi/provisioning';
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const UNAVAILABLE_CODE='burimunsi_provisioning_unavailable';
const UNAVAILABLE_MESSAGE='BuriMunsi provisioning is not configured for this deployment.';
const unavailable=()=>fail(503,UNAVAILABLE_CODE,UNAVAILABLE_MESSAGE);
function knownFailure(error){
  if(error instanceof ApiError)throw error;
  if(['recent_email_sign_in_required','recent_email_verification_required'].includes(error?.message))
    fail(403,'recent_email_sign_in_required','Verify your current owner email before continuing.');
  if(['admin_invitation_authority','burimunsi_provisioning_denied','burimunsi_operator_not_approved'].includes(error?.message))
    fail(403,'burimunsi_provisioning_denied','The current owner or approved Collect account could not be confirmed.');
  if(['burimunsi_provisioning_changed','burimunsi_provisioning_request_conflict'].includes(error?.message)||error?.code==='23505')
    fail(409,'burimunsi_provisioning_changed','The account, approval or installation changed. Check the original request and refresh.');
  if(error?.message==='burimunsi_delivery_expired')fail(410,'burimunsi_delivery_expired','This delivery expired or was superseded. Rotate the grant with its current version.');
  if(error?.message==='burimunsi_provisioning_invalid')fail(400,'invalid_provisioning','Check the exact provisioning fields.');
  if(['42883','42P01','42501'].includes(error?.code))unavailable();
}

/** Owner-only native app credentials in the SAME BFF/Collect DB. Does not create
 * a shared identity, activate a scope, pair a SIM/wallet or dispatch a provider. */
export async function adminBuriMunsiProvisioning(request,env){
  const url=new URL(request.url),path=url.pathname;
  if(path!==BASE&&!path.startsWith(BASE+'/'))return null;
  const match=path.match(/^\/api\/admin\/burimunsi\/provisioning\/requests\/([^/]+)(\/(?:delivery|cancel))?$/);
  if(path!==BASE&&!match)fail(404,'not_found','This provisioning view does not exist.');
  const verifyContract=url.searchParams.get('provisioningContract')==='2'&&
    (path===BASE&&['GET','POST'].includes(request.method)||request.method==='POST'&&match?.[2]==='/cancel');
  for(const key of url.searchParams.keys())if((key!=='collectionId'&&!(verifyContract&&key==='provisioningContract'))||url.searchParams.getAll(key).length!==1)
    fail(400,'invalid_request','Choose one collection and a supported provisioning format.');
  if(!(path===BASE&&['GET','POST'].includes(request.method)||match&&request.method===(match[2]?'POST':'GET')))
    fail(405,'method_not_allowed','Use the provisioning view or its explicit action.');
  const account=await adminAccountSession(request,env);
  await requireBuriMunsiOwner({request,env,account,permissions:['admin_users.manage'],
    ownerMessage:'The current Collect owner provisions native access.',
    unavailableCode:UNAVAILABLE_CODE,unavailableMessage:UNAVAILABLE_MESSAGE});
  const input=request.method==='POST'?await readJson(request,2048):null;
  const group=await selectAdminCollection({env,account,requested:input?.collectionId??url.searchParams.get('collectionId')});
  const service=new AdminNativeProvisioning({env,groupId:group,actorArgs:adminEmailArguments(account),
    actorId:account.principal_id,sessionId:account.auth_session_id,profileSha:env.COLLECT_DEPLOYMENT_PROFILE_SHA256,
    guardedWrites:verifyContract&&request.method==='POST'});
  const requestId=match?uuid(match[1]):null;
  if(requestId&&match[1]!==requestId)fail(400,'invalid_request','Use the original exact request identity.');
  if(request.method==='GET'||match?.[2]){
    try{
      let result;
      if(match?.[2]==='/cancel'){
        const body=input;
        if(Object.keys(body).length!==1||body.collectionId!==group)fail(409,'burimunsi_scope_changed','The BuriMunsi group changed.');
        result=await service.cancel(requestId);
      }else result=match?.[2]?await service.delivery(requestId,input):
        requestId?await service.lookup(requestId):await service.directory({verifyContract});
      return json(result,200,headers);
    }catch(error){knownFailure(error);unavailable();}
  }
  const body=provisioningCommand(input,group);
  if(verifyContract&&body.operation==='grant_installation')fail(400,'invalid_provisioning','This contract supports PIN setup and installation revocation.');
  try{return json(await service.apply(body),200,headers);}
  catch(error){
    knownFailure(error);
    // An unknown COMMIT never means "failed" or permission to use a new key.
    return json({contractVersion:1,collectionId:group,requestId:body.requestId,outcome:'operation_unknown',
      error:{code:'burimunsi_provisioning_unknown',message:'Provisioning was not confirmed. Check the original request before continuing.'}},503,headers);
  }
}
