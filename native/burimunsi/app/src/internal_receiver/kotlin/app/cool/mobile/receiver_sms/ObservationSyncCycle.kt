package app.cool.mobile.receiver_sms

import android.content.Context
import android.os.SystemClock
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.DeviceProvisioning
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Fence
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Phase
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Stop

internal data class ObservationCycleResult(val completed:Boolean,val more:Boolean,val problem:String?=null,val busy:Boolean=false)

/** The existing observation pipeline, executed once with one process-wide finite lease.
 * Both JobScheduler and the foreground supervisor use this same runner/journal.
 */
internal object ObservationSyncCycle {
    private val gate=ContinuousSyncWorkGate()
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
    private fun cycle(app:Context,online:Boolean,externalStop:()->Boolean,restore:()->NativeRepository?,
        diagnostic:ObservationSyncDiagnostics.Cycle):ObservationCycleResult {
        var budgetStarted:Long?=null;var budgetNow=0L;var cancelled=false
        val budget=ContinuousSyncBudget({
            SystemClock.elapsedRealtime().also{budgetNow=it;if(budgetStarted==null)budgetStarted=it}
        },{externalStop().also{cancelled=it}})
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
            diagnostic.phase(Phase.LOCAL_BACKFILL)
            var backfill=recovery.backfill(stopped)
            if(backfill!=ObservationRecovery.Backfill.BLOCKED&&!stopped()){
                diagnostic.phase(Phase.LOCAL_SCAN)
                again=recovery.scan(stopped)||backfill==ObservationRecovery.Backfill.MORE
            }
            if(!stopped()){diagnostic.phase(Phase.LOCAL_CORRELATE);recovery.correlateRecent(stopped)}
            // Offline collection is restricted by the existing cached profile,
            // consent, permissions and strict owner. Renewal never fabricates it.
            diagnostic.phase(Phase.ONLINE_CHECK)
            if(!online){diagnostic.reject(Fence.OFFLINE);return finish(ObservationCycleResult(false,again||ObservationBackground.hasPending(app),"connection_waiting"))}
            if(stopped())return finish(ObservationCycleResult(false,again,"sync_unconfirmed"))
            // Expired/quarantined credentials cannot run that pre-pass. A
            // successful existing restore is required before upload/second pass.
            diagnostic.phase(Phase.RESTORE)
            val repo=restore()?:run{diagnostic.reject(Fence.RESTORE_UNAVAILABLE);return finish(ObservationCycleResult(false,false,"authorization_required"))}
            if(stopped())return finish(ObservationCycleResult(false,again,"sync_unconfirmed"))
            val completed=ObservationCoordinator(app,repo,diagnostic).cycle(stopped)
            diagnostic.phase(Phase.COORDINATOR_FINISHED)
            if(!stopped()){
                diagnostic.phase(Phase.POST_BACKFILL)
                backfill=recovery.backfill(stopped)
                if(backfill!=ObservationRecovery.Backfill.BLOCKED){
                    diagnostic.phase(Phase.POST_SCAN)
                    again=recovery.scan(stopped)||backfill==ObservationRecovery.Backfill.MORE||again
                }
                if(!stopped()){diagnostic.phase(Phase.POST_CORRELATE);recovery.correlateRecent(stopped)}
            }
            diagnostic.phase(Phase.PENDING_CHECK)
            again=ObservationBackground.hasPending(app)||again
            val confirmed=completed&&!stopped()
            return finish(ObservationCycleResult(confirmed,again,if(confirmed)null else "sync_unconfirmed"))
        }catch(error:Exception){
            val snapshot=diagnostic.snapshot()
            val kind=ObservationSyncDiagnostics.errorKind(error)
            if(snapshot.fence!=Fence.EXCEPTION||snapshot.fencePhase!=snapshot.phase)diagnostic.error(kind)
            diagnostic.reject(Fence.EXCEPTION)
            if(kind==ObservationSyncDiagnostics.ErrorKind.INTERRUPTED)diagnostic.stopped(Stop.INTERRUPTED)
            val denied=error is ApiFailure&&error.status in setOf(401,403)
            val connection=kind in setOf(ObservationSyncDiagnostics.ErrorKind.TIMEOUT,ObservationSyncDiagnostics.ErrorKind.NETWORK,
                ObservationSyncDiagnostics.ErrorKind.API_UNAVAILABLE)
            return finish(ObservationCycleResult(false,again||runCatching{ObservationBackground.hasPending(app)}.getOrDefault(false),
                if(denied)"authorization_required" else if(connection)"connection_waiting" else "sync_unconfirmed"))
        }finally{diagnostic.finish(result)}
    }
}
