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
    val progress:Boolean=false)

/** The existing observation pipeline, executed once with one process-wide finite lease.
 * Both JobScheduler and the foreground supervisor use this same runner/journal.
 */
internal object ObservationSyncCycle {
    private val gate=ContinuousSyncWorkGate()
    private const val RECHECK_AFTER_MS=5*60_000L
    private const val AUDIT_AFTER_MS=24*60*60_000L
    private data class Verified(val witness:ObservationRecovery.Latest,val at:Long,val inboxRevision:Long)
    private data class SweepProof(val scope:String,val at:Long,val inboxRevision:Long,val cloudRevision:String?=null)
    private var verified:Verified?=null
    private var captureProof:SweepProof?=null
    private var auditProof:SweepProof?=null
    private enum class Comparison { MATCHED, PENDING, UNCONFIRMED }
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
        diagnostic:ObservationSyncDiagnostics.Cycle,inboxRevision:Long):Comparison {
        diagnostic.phase(Phase.RECONCILE_PHONE)
        val latest=recovery.latest(stopped)
        if(latest !is ObservationRecovery.Latest.Ready&&latest !is ObservationRecovery.Latest.Empty){
            verified=null
            diagnostic.reject(when(latest){ObservationRecovery.Latest.Held->Fence.RECONCILE_HELD
                else->Fence.RECONCILE_UNAVAILABLE})
            return Comparison.UNCONFIRMED
        }
        val session=when(latest){is ObservationRecovery.Latest.Ready->latest.witness.session
            is ObservationRecovery.Latest.Empty->latest.session;else->return Comparison.UNCONFIRMED}
        if(pending(app,session)!=false){verified=null;diagnostic.reject(Fence.RECONCILE_PENDING);return Comparison.PENDING}
        val now=SystemClock.elapsedRealtime();val cached=verified
        if(cached!=null&&cached.witness==latest&&cached.inboxRevision==inboxRevision&&ObservationInboxRevision.observerActive()&&
            ObservationInboxRevision.snapshot()==inboxRevision&&now>=cached.at&&now-cached.at<RECHECK_AFTER_MS)return Comparison.MATCHED
        verified=null;diagnostic.phase(Phase.RECONCILE_REMOTE)
        val expectedRevision=auditProof?.cloudRevision?:return Comparison.UNCONFIRMED
        val initial=repo.observationReconcileStatus()
        if(initial.hasPending||initial.hasUnmatchedCanonical||initial.revision!=expectedRevision){
            diagnostic.reject(Fence.AUDIT_UNCONFIRMED);return Comparison.UNCONFIRMED
        }
        if(latest is ObservationRecovery.Latest.Ready){
            if(stopped()||ObservationInboxRevision.snapshot()!=inboxRevision||pending(app,session)!=false||recovery.latest(stopped)!=latest){
                diagnostic.reject(Fence.RECONCILE_CHANGED);return Comparison.UNCONFIRMED
            }
            val witness=latest.witness
            val reply=repo.reconcileObservation(witness.request)
            if(reply.sourceKey!=witness.request.sourceKey||reply.state!="matched"||reply.sourceId==null){
                diagnostic.reject(Fence.RECONCILE_MISSING);return Comparison.UNCONFIRMED
            }
            // The SMS screen currently displays server retention order, so a
            // different newest displayed source cannot be claimed to agree.
            if(reply.latestRecordedSourceId!=reply.sourceId){
                diagnostic.reject(Fence.RECONCILE_ORDER_UNCERTAIN);return Comparison.UNCONFIRMED
            }
        }else if(initial.hasRecorded){
            diagnostic.reject(Fence.RECONCILE_EMPTY);return Comparison.UNCONFIRMED
        }
        // Retention order is not proof of Cloud event chronology; the set
        // audit and the displayed last source are checked independently.
        diagnostic.phase(Phase.RECONCILE_RECHECK)
        val after=recovery.latest(stopped)
        if(stopped()||ObservationInboxRevision.snapshot()!=inboxRevision||after!=latest||pending(app,session)!=false){
            diagnostic.reject(Fence.RECONCILE_CHANGED);return Comparison.UNCONFIRMED
        }
        val finalStatus=repo.observationReconcileStatus()
        if(finalStatus.hasPending||finalStatus.hasUnmatchedCanonical||finalStatus.revision!=expectedRevision||finalStatus.recordedCount!=initial.recordedCount||
            stopped()||ObservationInboxRevision.snapshot()!=inboxRevision||pending(app,session)!=false||recovery.latest(stopped)!=latest){
            diagnostic.reject(Fence.AUDIT_UNCONFIRMED);return Comparison.UNCONFIRMED
        }
        val checkedAt=SystemClock.elapsedRealtime()
        if(checkedAt<now){diagnostic.reject(Fence.RECONCILE_UNAVAILABLE);return Comparison.UNCONFIRMED}
        verified=Verified(latest,checkedAt,inboxRevision)
        return Comparison.MATCHED
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
        var again=false
        var result=ObservationCycleResult(false,false,"sync_unconfirmed")
        fun finish(value:ObservationCycleResult):ObservationCycleResult {result=value;return value}
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
            if(diagnostic.snapshot().acknowledged>0){verified=null;auditProof=null;recovery.resetAudit()}
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
                diagnostic.phase(Phase.AUDIT_PHONE)
                var audited=false
                repeat(5){
                    if(!audited){
                        diagnostic.phase(Phase.AUDIT_REMOTE)
                        when(recovery.auditPage(repo,stopped)){
                            ObservationRecovery.Audit.COMPLETE->audited=true
                            ObservationRecovery.Audit.MORE->Unit
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
                if(stopped()||ObservationInboxRevision.snapshot()!=inboxRevision||recovery.sweepScope(stopped)!=scope){
                    diagnostic.reject(Fence.RECONCILE_CHANGED);return finish(ObservationCycleResult(false,true,"sync_unconfirmed",progress=true))
                }
                val started=recovery.auditStartedAt()
                val revision=recovery.auditRevision()
                val completedAt=SystemClock.elapsedRealtime()
                if(started==null||revision==null||completedAt<started||completedAt-started>=AUDIT_AFTER_MS){
                    diagnostic.reject(Fence.AUDIT_UNCONFIRMED);return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
                }
                auditProof=SweepProof(scope,started,inboxRevision,revision)
            }
            val comparison=compareLatest(app,recovery,repo,stopped,diagnostic,inboxRevision)
            if(!ObservationInboxRevision.observerActive()){
                diagnostic.reject(Fence.OBSERVER_UNAVAILABLE)
                return finish(ObservationCycleResult(false,false,"sync_unconfirmed"))
            }
            val changed=ObservationInboxRevision.snapshot()!=inboxRevision||recovery.sweepScope(stopped)!=scope
            val confirmed=comparison==Comparison.MATCHED&&!stopped()&&!changed
            if(changed)diagnostic.reject(Fence.RECONCILE_CHANGED)
            return finish(ObservationCycleResult(confirmed,changed||comparison==Comparison.PENDING,if(confirmed)null else "sync_unconfirmed",
                progress=changed))
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
                verified=null
                if(!result.progress){captureProof=null;auditProof=null}
            }
            diagnostic.finish(result)
        }
    }
}
