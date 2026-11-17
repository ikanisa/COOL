package app.cool.mobile.receiver_sms

import android.content.Context
import android.os.SystemClock
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.DeviceProvisioning
import rw.ikanisa.burimunsi.core.ObservationJournal
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Fence
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Phase
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Stop

internal data class ObservationCycleResult(val completed:Boolean,val more:Boolean,val problem:String?=null,val busy:Boolean=false,
    val progress:Boolean=false,val proofStartedAtElapsed:Long?=null,val proofInboxRevision:Long?=null,
    val proofAuthorityRevision:Long?=null,val proofSessionDigest:String?=null,val proofScope:String?=null,
    val proofLegacyIssuedAtWall:Long?=null,val proofLegacyExpiresAtWall:Long?=null,val proofLegacySubscriptionsDigest:String?=null)

/** The existing observation pipeline, executed once with one process-wide finite lease.
 * Both JobScheduler and the foreground supervisor use this same runner/journal.
 */
internal object ObservationSyncCycle {
    private val gate=ContinuousSyncWorkGate()
    private const val RECHECK_AFTER_MS=ContinuousSyncHealthFreshness.MAX_PROOF_AGE_MS
    private const val AUDIT_AFTER_MS=24*60*60_000L
    private data class SweepProof(val scope:String,val at:Long,val inboxRevision:Long,val cloudRevision:String?=null)
    private data class Verified(val witness:ObservationRecovery.Latest,val at:Long,val inboxRevision:Long,val audit:SweepProof)
    private var verified:Verified?=null
    private var captureProof:SweepProof?=null
    private var auditProof:SweepProof?=null
    private enum class ComparisonStep { STATUS, SOURCE, FINAL }
    private data class ComparisonProgress(val latest:ObservationRecovery.Latest,val inboxRevision:Long,
        val cloudRevision:String,val startedAt:Long,val step:ComparisonStep,val recordedCount:Int?=null)
    private var comparisonProgress:ComparisonProgress?=null
    private enum class Comparison { MATCHED, PENDING, MORE, YIELD, UNCONFIRMED }
    private fun cachedSweep(recovery:ObservationRecovery,stopped:()->Boolean,inboxRevision:Long):Boolean {
        val cached=captureProof?:return false
        val now=SystemClock.elapsedRealtime()
        if(!ObservationInboxRevision.observerActive()||cached.inboxRevision!=inboxRevision||ObservationInboxRevision.snapshot()!=inboxRevision||
            now<cached.at||now-cached.at>=RECHECK_AFTER_MS)return false
        return recovery.sweepScope(stopped)==cached.scope&&!stopped()&&ObservationInboxRevision.observerActive()&&
            ObservationInboxRevision.snapshot()==inboxRevision
    }
    // A scheduling hint may fail open; a reconciliation proof must not. Null
    // means the owner or encrypted queue could not be checked.
    private fun pending(app:Context,session:ObservationSessionOwner?=null):Boolean? = try {
        NativeRepository.withObservationOwner(app,session){group,account->
            ObservationJournal(ObservationStateStore(app)).pending(ObservationOwner(group,account)).isNotEmpty()
        }
    }catch(_:Exception){null}
    fun run(context:Context,online:Boolean,
        restore:()->NativeRepository?={restoreRepository(context.applicationContext)},stopped:()->Boolean):ObservationCycleResult =
        gate.runIfIdle{cycle(context.applicationContext,online,stopped,restore,
            ObservationSyncDiagnostics.begin(online,SystemClock::elapsedRealtime))}
            ?:ObservationCycleResult(false,true,busy=true).also{ObservationSyncDiagnostics.busy()}

    private fun restoreRepository(app:Context):NativeRepository? {
        val install=DeviceProvisioning(app,MomoGatewayStore(app).installationId())
        val api=ApiClient.phonePin(BuildConfig.BURI_API_ORIGIN,install.installationId,"internal_receiver",
            BuildConfig.BURI_API_PATH_PREFIX,BuildConfig.COLLECT_PUBLISHABLE_KEY){install.registrationToken()}
        return NativeRepository(app,api).takeIf{it.restore()!=null}
    }
    private fun compareLatest(app:Context,recovery:ObservationRecovery,repo:NativeRepository,stopped:()->Boolean,
        budgetExpired:()->Boolean,diagnostic:ObservationSyncDiagnostics.Cycle,inboxRevision:Long):Comparison {
        fun reject(fence:Fence):Comparison {
            verified=null;comparisonProgress=null;auditProof=null;recovery.resetAudit()
            diagnostic.reject(fence);return Comparison.UNCONFIRMED
        }
        fun interrupted(fence:Fence):Comparison {
            if(stopped()&&budgetExpired())return Comparison.YIELD
            return reject(fence)
        }
        diagnostic.phase(Phase.RECONCILE_PHONE)
        val latest=recovery.latest(stopped)
        if(latest !is ObservationRecovery.Latest.Ready&&latest !is ObservationRecovery.Latest.Empty){
            return if(latest==ObservationRecovery.Latest.Held)reject(Fence.RECONCILE_HELD)
                else interrupted(Fence.RECONCILE_UNAVAILABLE)
        }
        val session=when(latest){is ObservationRecovery.Latest.Ready->latest.witness.session
            is ObservationRecovery.Latest.Empty->latest.session;else->return Comparison.UNCONFIRMED}
        if(pending(app,session)!=false){reject(Fence.RECONCILE_PENDING);return Comparison.PENDING}
        val proof=auditProof?:return reject(Fence.AUDIT_UNCONFIRMED)
        val expectedRevision=proof.cloudRevision?:return reject(Fence.AUDIT_UNCONFIRMED)
        val now=SystemClock.elapsedRealtime();val cached=verified
        if(cached!=null&&cached.audit==proof&&cached.witness==latest&&cached.inboxRevision==inboxRevision&&ObservationInboxRevision.observerActive()&&
            ObservationInboxRevision.snapshot()==inboxRevision&&now>=cached.at&&now-cached.at<RECHECK_AFTER_MS)return Comparison.MATCHED
        verified=null;diagnostic.phase(Phase.RECONCILE_REMOTE)
        val existing=comparisonProgress?.takeIf{it.latest==latest&&it.inboxRevision==inboxRevision&&
            it.cloudRevision==expectedRevision&&now>=it.startedAt&&now-it.startedAt<RECHECK_AFTER_MS}
        val progress=existing?:ComparisonProgress(latest,inboxRevision,expectedRevision,now,ComparisonStep.STATUS)
        // A completed response can be checked locally after the deadline, but
        // the deadline still blocks dispatch of another Cloud request.
        val localStop={stopped()&&!budgetExpired()}
        fun sameLocal()=!localStop()&&ObservationInboxRevision.observerActive()&&
            ObservationInboxRevision.snapshot()==inboxRevision&&pending(app,session)==false&&
            recovery.latest(localStop)==latest&&auditProof?.cloudRevision==expectedRevision
        if(!sameLocal())return reject(Fence.RECONCILE_CHANGED)
        if(stopped())return interrupted(Fence.RECONCILE_CHANGED)
        return when(progress.step){
            ComparisonStep.STATUS->{
                val status=repo.observationReconcileStatus()
                if(!sameLocal())return reject(Fence.RECONCILE_CHANGED)
                if(status.hasPending||status.hasUnmatchedCanonical||status.revision!=expectedRevision)
                    return reject(Fence.AUDIT_UNCONFIRMED)
                if(latest is ObservationRecovery.Latest.Empty&&status.hasRecorded)return reject(Fence.RECONCILE_EMPTY)
                comparisonProgress=progress.copy(step=if(latest is ObservationRecovery.Latest.Ready)ComparisonStep.SOURCE else ComparisonStep.FINAL,
                    recordedCount=status.recordedCount)
                Comparison.MORE
            }
            ComparisonStep.SOURCE->{
                val witness=(latest as? ObservationRecovery.Latest.Ready)?.witness?:return reject(Fence.RECONCILE_CHANGED)
                val reply=repo.reconcileObservation(witness.request)
                if(!sameLocal())return reject(Fence.RECONCILE_CHANGED)
                if(reply.sourceKey!=witness.request.sourceKey||reply.state!="matched"||reply.sourceId==null)
                    return reject(Fence.RECONCILE_MISSING)
                // The displayed Cloud list is retention-ordered.
                if(reply.latestRecordedSourceId!=reply.sourceId)return reject(Fence.RECONCILE_ORDER_UNCERTAIN)
                comparisonProgress=progress.copy(step=ComparisonStep.FINAL)
                Comparison.MORE
            }
            ComparisonStep.FINAL->{
                diagnostic.phase(Phase.RECONCILE_RECHECK)
                val status=repo.observationReconcileStatus()
                if(!sameLocal())return reject(Fence.RECONCILE_CHANGED)
                if(status.hasPending||status.hasUnmatchedCanonical||status.revision!=expectedRevision||
                    status.recordedCount!=progress.recordedCount)return reject(Fence.AUDIT_UNCONFIRMED)
                val checkedAt=SystemClock.elapsedRealtime()
                if(checkedAt<progress.startedAt||checkedAt-progress.startedAt>=RECHECK_AFTER_MS)
                    return reject(Fence.RECONCILE_UNAVAILABLE)
                comparisonProgress=null;verified=Verified(latest,progress.startedAt,inboxRevision,proof);Comparison.MATCHED
            }
        }
    }
    private fun cycle(app:Context,online:Boolean,externalStop:()->Boolean,restore:()->NativeRepository?,
        diagnostic:ObservationSyncDiagnostics.Cycle):ObservationCycleResult {
        var budgetStarted:Long?=null;var budgetNow=0L;var cancelled=false
        val budget=ContinuousSyncBudget({
            SystemClock.elapsedRealtime().also{budgetNow=it;if(budgetStarted==null)budgetStarted=it}
        },{externalStop().also{cancelled=it}})
        val inboxRevision=ObservationInboxRevision.snapshot()
        val stopped={
            budget.stopped().also{if(it){
                diagnostic.stopped(if(cancelled)Stop.CANCELLED else if(budgetNow<budgetStarted!!)Stop.CLOCK_REVERSED else Stop.ELAPSED_BUDGET)
                diagnostic.reject(Fence.STOPPED)
            }}
        }
        val budgetExpired={diagnostic.snapshot().stop==Stop.ELAPSED_BUDGET&&!cancelled}
        var again=false
        var result=ObservationCycleResult(false,false,"sync_unconfirmed")
        var preserveContinuation=false
        fun finish(value:ObservationCycleResult):ObservationCycleResult {result=value;return value}
        fun continueAfterBudget(recovery:ObservationRecovery,scope:String,advanced:Boolean):ObservationCycleResult {
            // The only reusable evidence is from fully verified prior stages.
            // Recheck local authority without another network request before
            // carrying it into the next finite cycle.
            if(budgetExpired()&&ObservationInboxRevision.observerActive()&&
                ObservationInboxRevision.snapshot()==inboxRevision&&pending(app)==false&&
                recovery.sweepScope{false}==scope&&stopped()&&budgetExpired()){
                preserveContinuation=true
                return finish(ObservationCycleResult(false,true,"sync_unconfirmed",progress=advanced))
            }
            recovery.resetAudit();comparisonProgress=null
            return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
        }
        try{
            if(stopped())return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
            // A bounded pre-network pass uses ONLY the strict current capture
            // witness/cached approved profile. API outages must not starve local
            // retention just because Android reports a validated Internet link.
            val recovery=ObservationRecovery(app)
            val cachedAtStart=cachedSweep(recovery,stopped,inboxRevision)
            var backfill=ObservationRecovery.Backfill.COMPLETE
            if(!cachedAtStart){
                diagnostic.phase(Phase.LOCAL_BACKFILL)
                backfill=recovery.backfill(stopped)
                if(backfill!=ObservationRecovery.Backfill.BLOCKED&&!stopped()){
                    diagnostic.phase(Phase.LOCAL_SCAN)
                    again=recovery.scanStatus(stopped)==ObservationRecovery.Scan.MORE||backfill==ObservationRecovery.Backfill.MORE
                }
            }
            if(!stopped()){diagnostic.phase(Phase.LOCAL_CORRELATE);recovery.correlateRecent(stopped)}
            // Offline collection is restricted by the existing cached profile,
            // consent, permissions and strict owner. Renewal never fabricates it.
            diagnostic.phase(Phase.ONLINE_CHECK)
            if(!online){diagnostic.reject(Fence.OFFLINE);return finish(ObservationCycleResult(false,true,"connection_waiting"))}
            if(stopped())return finish(ObservationCycleResult(false,again,"sync_unconfirmed"))
            // Expired/quarantined credentials cannot run that pre-pass. A
            // successful existing restore is required before upload/second pass.
            diagnostic.phase(Phase.RESTORE)
            val repo=restore()?:run{diagnostic.reject(Fence.RESTORE_UNAVAILABLE);return finish(ObservationCycleResult(false,false,"authorization_required"))}
            if(stopped())return finish(ObservationCycleResult(false,again,"sync_unconfirmed"))
            val completed=ObservationCoordinator(app,repo,diagnostic).cycle(stopped)
            // A newly retained earlier SMS can change the server's retention
            // order even while the newest phone witness remains unchanged.
            if(diagnostic.snapshot().acknowledged>0){verified=null;auditProof=null;comparisonProgress=null;recovery.resetAudit()}
            diagnostic.phase(Phase.COORDINATOR_FINISHED)
            var postScan=ObservationRecovery.Scan.BLOCKED
            if(!stopped()){
                if(cachedAtStart&&completed&&diagnostic.snapshot().acknowledged==0&&cachedSweep(recovery,stopped,inboxRevision)){
                    backfill=ObservationRecovery.Backfill.COMPLETE;postScan=ObservationRecovery.Scan.COMPLETE;again=false
                }else{
                    diagnostic.phase(Phase.POST_BACKFILL)
                    backfill=recovery.backfill(stopped)
                    if(backfill!=ObservationRecovery.Backfill.BLOCKED){
                        diagnostic.phase(Phase.POST_SCAN)
                        postScan=recovery.scanStatus(stopped)
                        again=postScan==ObservationRecovery.Scan.MORE||backfill==ObservationRecovery.Backfill.MORE
                    }
                }
                if(!stopped()){diagnostic.phase(Phase.POST_CORRELATE);recovery.correlateRecent(stopped)}
            }
            diagnostic.phase(Phase.PENDING_CHECK)
            val queuePending=pending(app)
            if(queuePending==null){
                diagnostic.reject(Fence.SWEEP_UNCONFIRMED)
                return finish(ObservationCycleResult(false,again,"sync_unconfirmed"))
            }
            again=queuePending||again
            if(!completed||stopped()||backfill==ObservationRecovery.Backfill.BLOCKED||postScan==ObservationRecovery.Scan.BLOCKED){
                diagnostic.reject(Fence.SWEEP_UNCONFIRMED)
                return finish(ObservationCycleResult(false,again,"sync_unconfirmed"))
            }
            if(again){
                diagnostic.reject(Fence.SWEEP_IN_PROGRESS)
                return finish(ObservationCycleResult(false,true,"sync_unconfirmed",progress=true))
            }
            if(!ObservationInboxRevision.observerActive()){
                diagnostic.reject(Fence.OBSERVER_UNAVAILABLE)
                return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
            }
            if(ObservationInboxRevision.snapshot()!=inboxRevision){
                diagnostic.reject(Fence.RECONCILE_CHANGED)
                return finish(ObservationCycleResult(false,true,"sync_unconfirmed",progress=true))
            }
            val scope=recovery.sweepScope(stopped)
            if(scope==null){diagnostic.reject(Fence.SWEEP_UNCONFIRMED);return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))}
            val now=SystemClock.elapsedRealtime()
            if(!cachedAtStart)captureProof=SweepProof(scope,now,inboxRevision)
            val cachedAudit=auditProof?.let{it.scope==scope&&it.inboxRevision==inboxRevision&&
                now>=it.at&&now-it.at<AUDIT_AFTER_MS}==true
            if(!cachedAudit){
                verified=null;comparisonProgress=null
                diagnostic.phase(Phase.AUDIT_PHONE)
                var audited=false;var advanced=false
                repeat(5){
                    if(!audited){
                        if(stopped())return continueAfterBudget(recovery,scope,advanced)
                        diagnostic.phase(Phase.AUDIT_REMOTE)
                        when(recovery.auditPage(repo,stopped,budgetExpired)){
                            ObservationRecovery.Audit.COMPLETE->audited=true
                            ObservationRecovery.Audit.MORE->advanced=true
                            ObservationRecovery.Audit.YIELD->return continueAfterBudget(recovery,scope,advanced)
                            ObservationRecovery.Audit.RETRY->{
                                auditProof=null;diagnostic.reject(Fence.AUDIT_UNCONFIRMED)
                                return finish(ObservationCycleResult(false,true,"sync_unconfirmed"))
                            }
                            ObservationRecovery.Audit.UNCONFIRMED->{
                                auditProof=null;diagnostic.reject(Fence.AUDIT_UNCONFIRMED)
                                return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
                            }
                            ObservationRecovery.Audit.BLOCKED->{
                                auditProof=null;diagnostic.reject(Fence.AUDIT_UNCONFIRMED)
                                return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
                            }
                        }
                    }
                }
                if(!audited){diagnostic.reject(Fence.AUDIT_IN_PROGRESS)
                    return finish(ObservationCycleResult(false,true,"sync_unconfirmed",progress=true))}
                if(!ObservationInboxRevision.observerActive()||ObservationInboxRevision.snapshot()!=inboxRevision||recovery.sweepScope{false}!=scope){
                    diagnostic.reject(Fence.RECONCILE_CHANGED);return finish(ObservationCycleResult(false,true,"sync_unconfirmed",progress=true))
                }
                val started=recovery.auditStartedAt()
                val revision=recovery.auditRevision()
                val completedAt=SystemClock.elapsedRealtime()
                if(started==null||revision==null||completedAt<started||completedAt-started>=AUDIT_AFTER_MS){
                    diagnostic.reject(Fence.AUDIT_UNCONFIRMED);return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
                }
                auditProof=SweepProof(scope,started,inboxRevision,revision)
                if(stopped())return continueAfterBudget(recovery,scope,true)
            }
            var comparison=Comparison.MORE;var compareAdvanced=false
            repeat(3){
                if(comparison==Comparison.MORE){
                    if(stopped())return continueAfterBudget(recovery,scope,compareAdvanced)
                    comparison=compareLatest(app,recovery,repo,stopped,budgetExpired,diagnostic,inboxRevision)
                    if(comparison==Comparison.MORE)compareAdvanced=true
                    if(comparison==Comparison.YIELD)return continueAfterBudget(recovery,scope,compareAdvanced)
                }
            }
            if(comparison==Comparison.MORE)
                return finish(ObservationCycleResult(false,true,"sync_unconfirmed",progress=compareAdvanced))
            if(comparison==Comparison.UNCONFIRMED){
                val changed=ObservationInboxRevision.snapshot()!=inboxRevision||recovery.sweepScope{false}!=scope
                return finish(ObservationCycleResult(false,changed,"sync_unconfirmed",progress=changed))
            }
            if(comparison==Comparison.MATCHED&&stopped())return continueAfterBudget(recovery,scope,true)
            if(!ObservationInboxRevision.observerActive()){
                diagnostic.reject(Fence.OBSERVER_UNAVAILABLE)
                return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
            }
            val authorityRevision=ObservationAuthorityRevision.stable()
            val session=NativeRepository.observationOwner(app)
            val legacy=ObservationLegacyOwnership.scope(app)
            val changed=authorityRevision==null||session==null||legacy==null||ObservationInboxRevision.snapshot()!=inboxRevision||
                recovery.sweepScope(stopped)!=scope||ObservationAuthorityRevision.stable()!=authorityRevision||
                NativeRepository.observationOwner(app)!=session||ObservationInboxRevision.snapshot()!=inboxRevision||
                ObservationLegacyOwnership.scope(app)!=legacy
            val proofStarted=verified?.at
            val confirmed=comparison==Comparison.MATCHED&&!stopped()&&!changed&&
                ContinuousSyncHealthFreshness.fresh(proofStarted,SystemClock.elapsedRealtime())
            if(changed)diagnostic.reject(Fence.RECONCILE_CHANGED)
            return finish(ObservationCycleResult(confirmed,changed||comparison==Comparison.PENDING,if(confirmed)null else "sync_unconfirmed",
                progress=changed,proofStartedAtElapsed=if(confirmed)proofStarted else null,
                proofInboxRevision=if(confirmed)inboxRevision else null,
                proofAuthorityRevision=if(confirmed)authorityRevision else null,
                proofSessionDigest=if(confirmed&&session!=null)ObservationAuthorityRevision.sessionDigest(session) else null,
                proofScope=if(confirmed)scope else null,
                proofLegacyIssuedAtWall=if(confirmed)legacy?.issuedAt else null,
                proofLegacyExpiresAtWall=if(confirmed)legacy?.expiresAt else null,
                proofLegacySubscriptionsDigest=if(confirmed)legacy?.subscriptionsDigest else null))
        }catch(error:Exception){
            val snapshot=diagnostic.snapshot()
            val kind=ObservationSyncDiagnostics.errorKind(error)
            if(snapshot.fence!=Fence.EXCEPTION||snapshot.fencePhase!=snapshot.phase)diagnostic.error(kind)
            diagnostic.reject(Fence.EXCEPTION)
            if(kind==ObservationSyncDiagnostics.ErrorKind.INTERRUPTED)diagnostic.stopped(Stop.INTERRUPTED)
            val denied=error is ApiFailure&&error.status in setOf(401,403)
            val connection=kind in setOf(ObservationSyncDiagnostics.ErrorKind.TIMEOUT,ObservationSyncDiagnostics.ErrorKind.NETWORK,
                ObservationSyncDiagnostics.ErrorKind.API_UNAVAILABLE)
            return finish(ObservationCycleResult(false,connection||again||runCatching{ObservationBackground.hasPending(app)}.getOrDefault(false),
                if(denied)"authorization_required" else if(connection)"connection_waiting" else "sync_unconfirmed"))
        }finally{
            if(!result.completed){
                if(!preserveContinuation)verified=null
                if(!result.progress&&!preserveContinuation){captureProof=null;auditProof=null;comparisonProgress=null}
            }
            diagnostic.finish(result)
        }
    }
}
