import {PostgresManagedSessions} from './postgres-managed-sessions.js';
import {PostgresIdentityDirectory} from './postgres-identity-directory.js';
import {PostgresProcessingAdmission} from './postgres-processing-admission.js';
import {PostgresRetainedSources} from './postgres-retained-sources.js';
import {PostgresCanonicalAdoption} from './postgres-canonical-adoption.js';
import {PostgresWorkerAuthority} from './postgres-worker-authority.js';
import {PostgresSchedulerStore,runSchedulerCycle} from './postgres-scheduler.js';
import {requireThat,requirePort} from './errors.js';
import {PostgresPostingAuthority} from './postgres-posting-authority.js';
import {PostgresNativeAuthStore} from './postgres-auth-store.js';
import {PostgresCanonicalStore} from './postgres-canonical-store.js';
import {PostgresReceiptJobStore} from './postgres-receipt-job-store.js';
import {PostgresRecordsStore} from './postgres-records-store.js';
import {composeNativeRequest,composeNativeContributions} from './compose.js';
import {processReceiptBatch} from './worker.js';
import {processRematchBatch} from './rematch-worker.js';
import {PostgresRematchJobStore} from './postgres-rematch-job-store.js';
import {automaticJobRouter} from './automatic-job-router.js';
import {PostgresSharedPosting} from './postgres-shared-posting.js';
import {PostgresPostingCustody} from './postgres-posting-custody.js';
import {PostgresPostingAllocation} from './postgres-posting-allocation.js';
import {PostgresPostingPreparation} from './postgres-posting-preparation.js';

/** Wire implemented adapters to the current Collect request context.
 * This is called AFTER the existing application admission, never directly from
 * user JSON. All bridges are trusted server modules. No DB I/O during assembly.
 * Missing real writer/identity/source/gateway commands intentionally block startup.
 */
export function createPostgresNativePorts({admission,config,db,bridges,clock=()=>Date.now()}) {
  requireThat(admission?.verified===true&&admission.groupId===config?.groupId,'request_not_admitted',503);
  requireThat(config?.enabled===true,'native_service_disabled',503);
  requireThat(config.canonicalIntegrationEnabled===undefined||typeof config.canonicalIntegrationEnabled==='boolean','invalid_worker_config',503);
  const integrated=config.canonicalIntegrationEnabled===true;
  let managedSessions=null,workerAuthority=null;
  if(integrated){
    requireThat(config.nativePostingAuthorityEnabled===true&&config.postingPreparationEnabled===true,'posting_authority_required',503);
    for(const key of ['identities','receiptAdmission','rematchAdmission','sources','canonicalIngest'])
      requireThat(bridges?.[key]===undefined,'canonical_bridge_conflict',503);
    requireThat(bridges?.posting?.workerRuntime===undefined&&bridges?.canonical?.env?.DB===db&&
      typeof bridges.canonical.validateProviderProfile==='function'&&typeof bridges.canonical.applicationWorkTuple==='function',
      'collect_adapter_required',503);
    bridges.canonical.applicationWorkTuple(db.applicationWork);
    const inputs={db,groupId:config.groupId};
    managedSessions=new PostgresManagedSessions(inputs);
    const identities=new PostgresIdentityDirectory(inputs);
    const receiptAdmission=new PostgresProcessingAdmission({...inputs,env:bridges.canonical.env,validateProviderProfile:bridges.canonical.validateProviderProfile});
    const sources=new PostgresRetainedSources({...inputs,namespace:bridges.posting?.custody?.namespace,decrypt:bridges.posting?.custody?.decrypt});
    const canonicalIngest=new PostgresCanonicalAdoption({...inputs,sources,admission:receiptAdmission});
    bridges={...bridges,identities,receiptAdmission,rematchAdmission:receiptAdmission,sources,canonicalIngest};
  }

  requireThat(typeof bridges?.createOperatorPrincipal==='function'&&typeof bridges?.gateway==='function','collect_adapter_required',503);
  requirePort(bridges?.commands,['createDirectMember','setMembershipActive']);
  requireThat(config.sharedPostingEnabled===undefined||typeof config.sharedPostingEnabled==='boolean','invalid_worker_config',503);
  requireThat(config.journalEvidenceEnabled===undefined||typeof config.journalEvidenceEnabled==='boolean','invalid_worker_config',503);
  requireThat(config.journalEvidenceEnabled!==true||config.sharedPostingEnabled===true,'posting_writer_required',503);
  requireThat(config.journalAllocationEnabled===undefined||typeof config.journalAllocationEnabled==='boolean','invalid_worker_config',503);
  requireThat(config.journalAllocationEnabled!==true||(config.sharedPostingEnabled===true&&config.journalEvidenceEnabled===true),'posting_custody_required',503);
  requireThat(config.postingPreparationEnabled===undefined||typeof config.postingPreparationEnabled==='boolean','invalid_worker_config',503);
  requireThat(config.postingPreparationEnabled!==true||config.journalAllocationEnabled===true,'posting_allocation_required',503);
  requireThat(config.nativePostingAuthorityEnabled===undefined||typeof config.nativePostingAuthorityEnabled==='boolean','invalid_worker_config',503);
  requireThat(config.nativePostingAuthorityEnabled!==true||config.sharedPostingEnabled===true,'posting_writer_required',503);
  const auth=new PostgresNativeAuthStore({db,groupId:config.groupId,createOperatorPrincipal:bridges.createOperatorPrincipal,clock,sessionBinding:managedSessions});
  let postingAuthority=null;
  if(config.nativePostingAuthorityEnabled===true){
    requireThat(bridges.posting?.runtime===undefined,'posting_authority_conflict',503);
    postingAuthority=new PostgresPostingAuthority({authority:auth,workerRuntime:integrated&&db.applicationWork.kind==='jobs'?{assertInTransaction:(...args)=>{
      requireThat(workerAuthority!==null,'worker_financial_authority_required',503);return workerAuthority.assertInTransaction(...args);}}:bridges.posting?.workerRuntime??null});
  }else requireThat(bridges.posting?.workerRuntime===undefined,'posting_authority_conflict',503);
  let posting=null,custody=null,allocation=null;
  if(config.sharedPostingEnabled===true){
    // Ambiguous writers must never silently select one implementation.
    requireThat(bridges.commands.postContribution===undefined,'posting_writer_conflict',503);
    if(config.journalEvidenceEnabled===true){
      requireThat(bridges.posting?.evidence===undefined,'posting_evidence_conflict',503);
      custody=new PostgresPostingCustody({db,groupId:config.groupId,namespace:bridges.posting?.custody?.namespace,
        decrypt:bridges.posting?.custody?.decrypt});
    }
    if(config.journalAllocationEnabled===true){
      requireThat(bridges.posting?.allocation===undefined,'posting_allocation_conflict',503);
      allocation=new PostgresPostingAllocation({db,groupId:config.groupId,custody});
    }
    posting=new PostgresSharedPosting({db,groupId:config.groupId,runtime:postingAuthority??bridges.posting?.runtime,
      allocation:allocation??bridges.posting?.allocation,evidence:custody??bridges.posting?.evidence});
  }else requirePort(bridges.commands,['postContribution']);
  const baseCommands=posting?Object.freeze({
    postContribution:(...args)=>posting.postContribution(...args),
    createDirectMember:(...args)=>bridges.commands.createDirectMember(...args),
    setMembershipActive:(...args)=>bridges.commands.setMembershipActive(...args),
    enqueueEligibleRematch:(...args)=>bridges.commands.enqueueEligibleRematch(...args)
  }):bridges.commands;
  requireThat(config.rematchEnabled===undefined||typeof config.rematchEnabled==='boolean','invalid_worker_config',503);
  if(config.rematchEnabled===true)requirePort(bridges?.rematchAdmission,['assertInTransaction']);
  else requirePort(bridges?.commands,['enqueueEligibleRematch']);
  requirePort(bridges?.identities,['policy','members','verified']);
  requirePort(bridges?.receiptAdmission,['assertInTransaction']);
  requirePort(bridges?.sources,['assertLineage','load']);
  requirePort(bridges?.canonicalIngest,['ingest','outcome']);
  requirePort(bridges?.sourceReader,['revision','page','detail']);
  const preparation=config.postingPreparationEnabled===true?new PostgresPostingPreparation({authority:auth,posting,allocation,
    media:bridges.posting?.preparation?.media,encrypt:bridges.posting?.preparation?.encrypt,keyId:bridges.posting?.preparation?.keyId}):null;
  const jobs=new PostgresReceiptJobStore({authority:auth,admission:bridges.receiptAdmission,sources:bridges.sources,canonical:bridges.canonicalIngest,maxAttempts:config.maxReceiptAttempts??4});
  const rematches=config.rematchEnabled===true?new PostgresRematchJobStore({authority:auth,admission:bridges.rematchAdmission,
    canonical:bridges.canonicalIngest,maxAttempts:config.maxRematchAttempts??4}):null;
  // Bind methods rather than spreading a class instance (prototype methods are
  // not enumerable). The enqueue runs in the caller's existing transaction.
  const commands=rematches?Object.freeze({
    postContribution:(...args)=>baseCommands.postContribution(...args),
    createDirectMember:(...args)=>bridges.commands.createDirectMember(...args),
    setMembershipActive:(...args)=>bridges.commands.setMembershipActive(...args),
    enqueueEligibleRematch:(sql,command)=>rematches.enqueueInTransaction(sql,command)
  }):baseCommands;
  const automaticJobs=rematches?automaticJobRouter(jobs,rematches):jobs;
  let scheduler=null;
  if(integrated&&db.applicationWork.kind==='jobs'){
    workerAuthority=new PostgresWorkerAuthority({authority:auth,jobs:automaticJobs,applicationWorkTuple:bridges.canonical.applicationWorkTuple});
    scheduler=new PostgresSchedulerStore({authority:auth,admission:bridges.receiptAdmission,applicationWorkTuple:bridges.canonical.applicationWorkTuple});
  }
  const canonical=new PostgresCanonicalStore({authority:auth,commands,identities:bridges.identities,jobs:automaticJobs,clock});
  const records=new PostgresRecordsStore({authority:auth,sourceReader:bridges.sourceReader,clock});
  const gateway=bridges.gateway(auth);
  requirePort(gateway,['withAuthorityTransaction','withReadSnapshot']);
  return Object.freeze({auth,canonical,records,gateway,jobs,...(integrated?{sources:bridges.sources}:{}),...(managedSessions?{managedSessions}:{}),...(scheduler?{scheduler}:{}),...(workerAuthority?{workerAuthority}:{}),...(postingAuthority?{postingAuthority}:{}),...(rematches?{rematches}:{}),...(posting?{posting}:{}),...(custody?{custody}:{}),...(allocation?{allocation}:{}),...(preparation?{preparation}:{})});
}
export function composePostgresNativeRequest(options) {
  const ports=createPostgresNativePorts(options);
  return composeNativeRequest({...options,ports});
}

/** Build bounded worker entrypoints inside a genuine admitted worker context.
 * Does not start a scheduler, enable processing or create a new admission. The
 * same source-derived preparation selection is used by native requests/workers.
 * Callers cannot replace the store, contribution service, group or clock via
 * batch arguments. Recreate after admission expiry; do not cache across leases.
 */
export function composePostgresNativeWorkers(options) {
  if(options?.config?.nativePostingAuthorityEnabled===true&&options?.config?.canonicalIntegrationEnabled!==true)
    requirePort(options.bridges?.posting?.workerRuntime,['assertInTransaction']);
  const ports=createPostgresNativePorts(options);
  const contributions=composeNativeContributions({...options,ports});
  const groupId=options.config.groupId,clock=options.clock??(()=>Date.now());
  const workers={
    processReceipts:({owner,profile,limit=20,leaseMs=180000})=>
      processReceiptBatch({store:ports.jobs,contributions,groupId,owner,profile,limit,leaseMs,now:clock}),
    ...(ports.rematches?{processRematches:({owner,limit=5,targetsPerJob=20,leaseMs=180000})=>
      processRematchBatch({store:ports.rematches,contributions,groupId,owner,limit,targetsPerJob,leaseMs})}:{})
  };
  if(ports.scheduler){
    workers.runScheduledCycle=({owner,receiptLimit=20,rematchLimit=ports.rematches?5:0,targetsPerJob=20,leaseMs=180000,budgetMs=30000})=>
      runSchedulerCycle({store:ports.scheduler,workers,owner,receiptLimit,rematchLimit,targetsPerJob,leaseMs,budgetMs});
    // Server-only original source identifier. Enqueue is idempotent; caller cannot
    // inject text, group, binding, profile, digest, a parsed receipt or a ledger ID.
    workers.enqueueRetainedSource=sourceId=>ports.auth.write(async sql=>
      ports.jobs.enqueueInTransaction(sql,await ports.sources.sourceForEnqueue(sql,sourceId)));
  }
  return Object.freeze(workers);
}
