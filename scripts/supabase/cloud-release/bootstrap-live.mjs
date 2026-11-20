// The root operator supplies the user-authorized phones/PINs in memory.
// No login session is fabricated. The existing cloud owner and imported
// account IDs are verified before a separately audited fenced transaction.
import {existsSync,readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {connect,record,ROOT,sha} from './access.mjs';
import {normalizePhone} from '../../../supabase/functions/_shared/domain/burimunsi/values.js';
import {prepareInitialBootstrap,confirmDefaultStaffPin} from './initial-account-bootstrap.mjs';
import {executeManagedBootstrapMaintenance} from '../cloud-data-transfer/maintenance.mjs';

export async function bootstrapLive({adminPhone,staffPhone,adminPin,staffPin,defaultStaffPin}){
 if(existsSync(ROOT+'/initial-accounts-intent.json'))throw Error('prior_bootstrap_requires_reconciliation');
 adminPhone=normalizePhone(adminPhone);staffPhone=normalizePhone(staffPhone);
 const graph=JSON.parse(readFileSync(ROOT+'/graph-import-attempt-002-result.json'));
 const intent=JSON.parse(readFileSync(ROOT+'/graph-import-attempt-002-intent.json'));
 if(graph.outcome!=='committed_and_receipt_read_back')throw Error('graph_commit_required');
 await confirmDefaultStaffPin(defaultStaffPin);
 const c=await connect();let commitAttempted=false;
 try{
  const receipt=(await c.query('SELECT cloud_primary_id FROM private.collect_migration_import_receipts WHERE operation_id=$1',[intent.operationId])).rows;
  const groups=(await c.query('SELECT DISTINCT collection_id FROM private.collect_imported_native_history WHERE operation_id=$1',[intent.operationId])).rows;
  if(receipt.length!==1||groups.length!==1)throw Error('bootstrap_graph_mapping_invalid');
  const ownerPrincipalId=receipt[0].cloud_primary_id,collectionId=groups[0].collection_id;
  await c.query('BEGIN READ ONLY');let accounts;
  try{
   await c.query('SET LOCAL ROLE collect_runtime');
   await c.query("SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id',$1,true)",[collectionId]);
   accounts=(await c.query('SELECT id,phone,role,principal_user_id,active,removed FROM private.burimunsi_accounts WHERE collection_id=$1 AND phone=ANY($2::text[])',[collectionId,[adminPhone,staffPhone]])).rows;
   await c.query('COMMIT');
  }catch(e){await c.query('ROLLBACK').catch(()=>{});throw e;}
  const admin=accounts.find(x=>x.phone===adminPhone),staff=accounts.find(x=>x.phone===staffPhone);
  if(accounts.length!==2||!admin||!staff||admin.role!=='admin'||staff.role!=='staff'||admin.principal_user_id!==ownerPrincipalId||accounts.some(x=>x.active||x.removed))throw Error('imported_account_mapping_changed');
  const fence=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  if(fence.mode!=='fenced')throw Error('bootstrap_fence_required');
  const operationId=randomUUID();
  const authorizationSha256=sha(JSON.stringify({purpose:'Owner explicitly authorized two Cloud APK accounts, initial/default passcodes, migrations and deployment in this task',date:'2026-11-17',adminPhone,staffPhone,ownerPrincipalId,collectionId}));
  const prepared=await prepareInitialBootstrap({operationId,fenceOperationId:fence.operation_id,epoch:Number(fence.epoch),sourceSha256:fence.source_sha256,authorizationSha256,ownerPrincipalId,collectionId,adminAccountId:admin.id,staffAccountId:staff.id,adminPhone,staffPhone,adminPin,staffPin});
  record('initial-accounts-intent.json',{operationId,graphOperationId:intent.operationId,authorizationSha256,at:new Date().toISOString()});
  const result=await executeManagedBootstrapMaintenance(c,{operationId,fenceOperationId:fence.operation_id,epoch:String(fence.epoch),sourceSha256:fence.source_sha256},prepared);
  commitAttempted=true;
  const audit=(await c.query("SELECT count(*)::int n FROM app.audit_log WHERE action='burimunsi.migration.initial_accounts' AND request_id=$1 AND actor_user_id=$2 AND actor_session_id IS NULL",[operationId,ownerPrincipalId])).rows[0];
  if(audit.n!==1||result.guardAndPoliciesRestored!==true)throw Error('bootstrap_readback_unconfirmed');
  record('initial-accounts-complete.json',{operationId,accounts:2,defaultStaffPinConfirmed:true,oldCredentialsRetired:true,guardAndPoliciesRestored:true,at:new Date().toISOString()});
  return {status:'initial_accounts_activated',accounts:2,operationId};
 }catch(e){
  record('initial-accounts-failure.json',{code:e.code??null,message:/^[a-z_]+$/.test(e.message)?e.message:'bootstrap_failed',outcome:e.outcome??(commitAttempted?'commit_requires_reconciliation':'not_committed'),at:new Date().toISOString()});
  throw e;
 }finally{await c.end();}
}
