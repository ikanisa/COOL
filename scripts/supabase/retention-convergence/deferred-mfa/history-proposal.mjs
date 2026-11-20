// Non-executable candidate manifest. It performs no database or filesystem
// mutation and cannot attest the provenance of the supplied observation.
import {planManagedHistory} from '../history-plan.mjs';

const WIP=Object.freeze(['20261114110100','20261114110300']);
const MANAGED_BLOCKERS=Object.freeze({
 '20261101013157':Object.freeze({classification:'original_predecessor_managed_binding_unqualified',
  status:'blocked_pending_managed_qualification',
  detail:'Preserve the original deployment-identity migration as the predecessor; its binder accepts only self_hosted profiles. A separate managed binder and its scheduler-function preimage decision require independent qualification before binding.'}),
 '20261110181002':Object.freeze({classification:'local_vm_stopped_admission_semantics',
  status:'blocked_pending_managed_qualification',
  detail:'The original local-VM stopped-executor and retention semantics need an explicit managed-applicability, predecessor and recovery decision; no equivalent hosted executor closure is demonstrated.'}),
});
const fail=()=>{const error=Error('deferred_mfa_proposal_refused');error.code=error.message;throw error;};

export async function proposeDeferredMfaHistory(observedJson,expectedObservedSha256){
 const source=await planManagedHistory(observedJson,expectedObservedSha256);
 if(source.observed_history_count!==14||source.source_file_count!==65||source.pending_action_count!==52||
  source.execution_supported!==false||source.history_written!==false)fail();
 const deferred=source.actions.filter(action=>WIP.includes(action.source_version));
 if(deferred.length!==2||deferred.some((action,index)=>action.source_version!==WIP[index]||
  action.version!==WIP[index]||action.kind!=='original_source'||action.work_in_progress!==true))fail();
 const actions=source.actions.filter(action=>!WIP.includes(action.source_version)).map(action=>({
  ...action,...(MANAGED_BLOCKERS[action.source_version]?{managed_portability:MANAGED_BLOCKERS[action.source_version]}:{}),
 }));
 if(actions.length!==50||actions.some(action=>action.work_in_progress)||
  actions.some((action,index)=>index>0&&actions[index-1].version>=action.version)||
  actions.some(action=>WIP.includes(action.version)||WIP.includes(action.source_version)))fail();
 for(const version of Object.keys(MANAGED_BLOCKERS))
  if(actions.filter(action=>action.source_version===version&&action.version===version&&
   action.kind==='original_source'&&action.managed_portability?.status==='blocked_pending_managed_qualification').length!==1)fail();
 return {
  format:'collect.deferred-mfa-history-proposal.v1',project_ref:source.project_ref,status:'analysis_only',
  observed_history_sha256:source.observed_history_sha256,observed_history_count:14,source_file_count:65,
  pending_action_count:actions.length,actions,
  deferred:deferred.map(action=>({version:action.source_version,name:action.source_name,source_sha256:action.source_sha256,
   status:'deferred_unexecuted',history_recorded:false})),
  excluded_divergent_originals:source.excluded_divergent_originals,
  managed_portability_qualified:false,managed_blocker_count:Object.keys(MANAGED_BLOCKERS).length,
  runtime_preconditions:{COLLECT_ADMIN_TOTP_ENABLED:'not_true',COLLECT_ADMIN_TOTP_RECOVERY_ENABLED:'not_true'},
  history_written:false,execution_supported:false,source_directory_push_safe:false,production_authorized:false,
  limitations:[
   'The 14-row observation is caller asserted and may be stale',
   'Both WIP features and recovery paths must stay disabled; current users and data may still depend on them',
   'Both deferred source versions precede the proposed latest version; their later implementation needs a fresh reviewed history strategy',
   'The original self-hosted identity migration is only a predecessor; binding requires a separately qualified managed binder and scheduler preimage decision',
   'The local stopped-admission migration requires an independently reviewed managed recovery and applicability decision',
   'The managed catalogue, production executor, fence, backup, data transfer and provider behavior remain unqualified',
  ],
 };
}
