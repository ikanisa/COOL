import {adminSmsMetadataRead} from './admin_sms_receipts.js';
import {adminMomoRoute} from './admin_momo.js';
import {adminMemberReceiptRead} from './admin_member_receipts.js';
import {permission,lists,list,overview,fail,unavailable} from './admin_records.js';
import {ApiError,json,uuid} from './core.js';
import {evidenceRoute} from './evidence.js';
import {adminSyncEvents} from './admin_sync.js';
import {adminPrivacyRoute} from './admin_privacy.js';
import {notificationOperatorRoute} from './notification_operator.js';
import {notificationOperatorManagementRoute} from './notification_operator_management.js';
import {adminOversightRead} from './admin_oversight.js';
import {clientDiagnosticsRoute} from './client_diagnostics.js';
import {handleAdminAccounts,validateAdminOrigin,adminAccountSession,adminCanonicalActor,adminInternalRequest,accountDatabase,accountReadDatabase} from './admin_accounts.js';
import {adminBuriMunsiAccess} from './admin_burimunsi_access.js';
import {adminBuriMunsiOperators} from './admin_burimunsi_operators.js';
import {adminBuriMunsiNativeWork} from './admin_burimunsi_native_work.js';
import {adminBuriMunsiProvisioning} from './admin_burimunsi_provisioning.js';
import {operatingRead,adminOperationWrite} from './admin_operations.js';
import {adminReconciliationRoute} from './admin_reconciliation.js';

// The platform-sponsored group fixture compiles these production operations.
export {genericMutation} from './admin_record_mutations.js';
export {requestEnvironment,requestId} from './admin_request_aliases.js';
export {operatingRead} from './admin_operations.js';

async function bridgeRoute(request,env){
 validateAdminOrigin(request,env);const url=new URL(request.url),parts=url.pathname.slice('/api/admin/'.length).split('/'),account=await adminAccountSession(request,env),section=parts.shift();
 const base=accountDatabase(env,account);const actor=await adminCanonicalActor(request,base,account);
 if(section==='oversight')return json(await adminOversightRead(request,base,account,actor,parts,url));
 if(section==='diagnostics'&&parts.length===0)return clientDiagnosticsRoute(request,base,actor,{account});
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
  const scoped=accountReadDatabase(env,account,cap);
  return json(parts[0]==='overview'?await overview(scoped,url):await list(scoped,parts[0],url));
 }
 if(section==='operations'&&request.method==='GET')return json(await operatingRead(request,base,account,parts,url));
 if(section==='operations'&&['POST','PATCH'].includes(request.method))return adminOperationWrite(request,env,base,account,actor,parts,url);
 if(section==='evidence'&&request.method==='GET'&&parts.length===1){
  const reply=await evidenceRoute(await adminInternalRequest(request,base,account,`/v1/evidence/${uuid(parts[0])}`,'GET'),base,actor,{adminRequest:request,account});if(!reply)unavailable();
  await adminAccountSession(request,env);return reply;
 }
 if(section==='reconciliations')return adminReconciliationRoute(request,env,base,account,actor,parts,url);
 unavailable();
}

/** Composite same-origin Admin handler. The root router calls this BEFORE its
 * bearer /v1 auth and CORS dispatcher. No ASSETS or second operating DB here. */
export async function handleAdmin(request,env,ctx){
 const path=new URL(request.url).pathname;if(path!=='/api/admin'&&!path.startsWith('/api/admin/'))return null;
 try{const account=await handleAdminAccounts(request,env,ctx);if(account)return account;return await adminBuriMunsiAccess(request,env)??await adminBuriMunsiOperators(request,env)??await adminBuriMunsiNativeWork(request,env)??await adminBuriMunsiProvisioning(request,env)??await notificationOperatorManagementRoute(request,env)??await notificationOperatorRoute(request,env)??await bridgeRoute(request,env);}
 catch(error){if(typeof env.INTERNAL_ERROR_OBSERVER==='function')env.INTERNAL_ERROR_OBSERVER(error);const known=error instanceof ApiError,constraint=/admin_bridge_guards|admin_bridge_state|UNIQUE constraint|FOREIGN KEY constraint/.test(String(error));
  return json({error:{code:known?error.code:constraint?'state_conflict':'service_unavailable',message:known?error.message:constraint?'The record or related state changed. Refresh before continuing.':'The request could not be completed.'}},known?error.status:constraint?409:503);}
}
