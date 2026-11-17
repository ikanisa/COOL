package app.cool.mobile.receiver_sms

import java.io.PrintWriter
import java.util.concurrent.atomic.AtomicReference
import rw.ikanisa.burimunsi.data.ApiFailure

/** Volatile, bounded, process-local diagnostics. No caller-supplied text or
 * throwable is retained. Reading/dumping never reads storage or starts work.
 */
internal object ObservationSyncDiagnostics {
    const val MAX_COUNT=10_000
    const val MAX_DURATION_MS=120_000L
    enum class Phase {
        IDLE, LOCAL_BACKFILL, LOCAL_SCAN, LOCAL_CORRELATE, ONLINE_CHECK, RESTORE,
        COORDINATOR_START, COORDINATOR_FINISHED, CONSENT_LOCAL, CONSENT_READ, CONSENT_MERGE, CONSENT_WRITE,
        PROFILE_READ, PROFILE_SAVE, PROFILE_VALIDATE, JOURNAL_READ,
        UPLOAD_GUARD, UPLOAD, UPLOAD_UNRESOLVED, ACKNOWLEDGE,
        POST_BACKFILL, POST_SCAN, POST_CORRELATE, PENDING_CHECK, FINISHED
    }
    enum class Fence {
        NONE, STOPPED, OFFLINE, RESTORE_UNAVAILABLE, QUALIFICATION, NOT_GATEWAY, CONTROL_TRANSITION,
        OWNER_UNAVAILABLE, OWNER_CHANGED, CONSENT_READ_FAILED, CONSENT_MISSING,
        CONSENT_RECONCILE_REJECTED, CONTROL_CHANGED, CONSENT_CHANGED,
        CAPTURE_AUTHORITY_CHANGED, CONSENT_ACK_REJECTED, CONSENT_NOT_CAPTURING,
        AUTHORITY_DENIED, CONSENT_WRITE_FAILED, PROFILE_UNAVAILABLE,
        PERMISSION_REQUIRED, PAUSED, UNRESOLVED_LATER_LIMIT, UNRESOLVED_LIMIT,
        UPLOAD_FAILED, ACK_REJECTED, UNRESOLVED_REMAIN, EXCEPTION
    }
    enum class Stop { NONE, CANCELLED, ELAPSED_BUDGET, CLOCK_REVERSED, INTERRUPTED }
    enum class ErrorKind { NONE, AUTHORIZATION, TIMEOUT, NETWORK, API_UNAVAILABLE, API_OTHER, INTERRUPTED, UNKNOWN }
    enum class Outcome { NOT_RUN, RUNNING, COMPLETED, UNCONFIRMED }
    enum class Problem { NONE, STARTING, CONNECTION_WAITING, SYNC_UNCONFIRMED, AUTHORIZATION_REQUIRED,
        PERMISSION_REQUIRED, PAUSED, RECEIVER_RETIRED, NOTIFICATION_PERMISSION_REQUIRED, START_NOT_ALLOWED, UNKNOWN }
    enum class ServicePhase { NOT_ATTACHED, STARTING, SCHEDULED, PREFLIGHT, BACKGROUND_GATE_BUSY, PIPELINE, RETRY,
        EXECUTION_FAILED, DISPATCH_REJECTED, STOPPED, DESTROYED }
    enum class NotificationState { STARTING, ACTIVE, WAITING, UNCONFIRMED }

    data class Snapshot(
        val phase:Phase=Phase.IDLE,
        val coordinator:Outcome=Outcome.NOT_RUN,
        val coordinatorPhase:Phase=Phase.IDLE,
        val fence:Fence=Fence.NONE,
        val fencePhase:Phase=Phase.IDLE,
        val outcome:Outcome=Outcome.RUNNING,
        val problem:Problem=Problem.NONE,
        val stop:Stop=Stop.NONE,
        val stopPhase:Phase=Phase.IDLE,
        val error:ErrorKind=ErrorKind.NONE,
        val errorPhase:Phase=Phase.IDLE,
        val errors:Int=0,
        val online:Boolean=false,
        val queueRead:Boolean=false,
        val queued:Int=0,
        val attempts:Int=0,
        val acknowledged:Int=0,
        val unresolved:Int=0,
        val more:Boolean=false,
        val elapsedMs:Long=0,
    )
    private data class Totals(val started:Int=0,val completed:Int=0,val unconfirmed:Int=0,val busy:Int=0)
    private data class ServiceState(val phase:ServicePhase=ServicePhase.NOT_ATTACHED,val problem:Problem=Problem.NONE,
        val error:ErrorKind=ErrorKind.NONE,val errorPhase:ServicePhase=ServicePhase.NOT_ATTACHED)
    private val latest=AtomicReference<Cycle?>()
    private val totals=AtomicReference(Totals())
    private val service=AtomicReference(ServiceState())
    private fun count(value:Int)=value.coerceIn(0,MAX_COUNT)
    private fun problem(value:String?):Problem=when(value){
        null->Problem.NONE;"starting"->Problem.STARTING;"connection_waiting"->Problem.CONNECTION_WAITING
        "sync_unconfirmed"->Problem.SYNC_UNCONFIRMED;"authorization_required"->Problem.AUTHORIZATION_REQUIRED
        "permission_required"->Problem.PERMISSION_REQUIRED;"paused"->Problem.PAUSED
        "receiver_retired"->Problem.RECEIVER_RETIRED;"notification_permission_required"->Problem.NOTIFICATION_PERMISSION_REQUIRED
        "start_not_allowed"->Problem.START_NOT_ALLOWED;else->Problem.UNKNOWN
    }
    fun notificationState(value:String?):NotificationState=when(problem(value)){
        Problem.NONE->NotificationState.ACTIVE
        Problem.STARTING->NotificationState.STARTING
        Problem.CONNECTION_WAITING->NotificationState.WAITING
        else->NotificationState.UNCONFIRMED
    }
    fun errorKind(error:Exception):ErrorKind=when(error){
        is InterruptedException,is java.util.concurrent.CancellationException->ErrorKind.INTERRUPTED
        is java.net.SocketTimeoutException->ErrorKind.TIMEOUT
        is java.net.SocketException,is java.net.UnknownHostException,is javax.net.ssl.SSLException->ErrorKind.NETWORK
        is ApiFailure->when(error.status){401,403->ErrorKind.AUTHORIZATION;in 500..599->ErrorKind.API_UNAVAILABLE;else->ErrorKind.API_OTHER}
        else->ErrorKind.UNKNOWN
    }
    fun begin(online:Boolean,now:()->Long):Cycle {
        val cycle=Cycle(online,now)
        latest.set(cycle)
        totals.updateAndGet{it.copy(started=count(it.started+1))}
        return cycle
    }
    fun busy(){totals.updateAndGet{it.copy(busy=count(it.busy+1))}}
    fun service(phase:ServicePhase,problem:String?=null){service.updateAndGet{
        if(phase==ServicePhase.STARTING)ServiceState(phase,problem(problem))else it.copy(phase=phase,problem=problem(problem))
    }}
    fun serviceError(phase:ServicePhase,error:ErrorKind){service.updateAndGet{it.copy(phase=phase,error=error,errorPhase=phase)}}
    fun snapshot():Snapshot?=latest.get()?.snapshot()

    class Cycle internal constructor(online:Boolean,private val now:()->Long){
        private val started=now()
        private val state=AtomicReference(Snapshot(online=online))
        private fun elapsed()=(now()-started).coerceIn(0,MAX_DURATION_MS)
        fun snapshot():Snapshot=state.get().let{if(it.outcome==Outcome.RUNNING)it.copy(elapsedMs=elapsed())else it}
        fun phase(value:Phase){state.updateAndGet{it.copy(phase=value,
            coordinatorPhase=if(it.coordinator==Outcome.RUNNING)value else it.coordinatorPhase)}}
        fun coordinatorStarted(){state.updateAndGet{it.copy(coordinator=Outcome.RUNNING)}}
        fun coordinatorFinished(completed:Boolean){state.updateAndGet{it.copy(coordinator=if(completed)Outcome.COMPLETED else Outcome.UNCONFIRMED)}}
        fun reject(value:Fence){state.updateAndGet{if(it.fence!=Fence.NONE)it else it.copy(fence=value,fencePhase=it.phase)}}
        fun stopped(value:Stop){state.updateAndGet{if(it.stop!=Stop.NONE)it else it.copy(stop=value,stopPhase=it.phase)}}
        fun error(value:ErrorKind){state.updateAndGet{it.copy(error=value,errorPhase=it.phase,errors=count(it.errors+1))}}
        fun queued(value:Int){state.updateAndGet{it.copy(queueRead=true,queued=count(value))}}
        fun attempted(){state.updateAndGet{it.copy(attempts=count(it.attempts+1))}}
        fun acknowledged(){state.updateAndGet{it.copy(acknowledged=count(it.acknowledged+1))}}
        fun unresolved(){state.updateAndGet{it.copy(unresolved=count(it.unresolved+1))}}
        fun finish(result:ObservationCycleResult){
            while(true){
                val before=state.get()
                if(before.outcome!=Outcome.RUNNING)return
                val after=before.copy(phase=Phase.FINISHED,outcome=if(result.completed)Outcome.COMPLETED else Outcome.UNCONFIRMED,
                    problem=problem(result.problem),more=result.more,elapsedMs=elapsed())
                if(state.compareAndSet(before,after))break
            }
            totals.updateAndGet{if(result.completed)it.copy(completed=count(it.completed+1))else it.copy(unconfirmed=count(it.unconfirmed+1))}
        }
    }

    /** Only literal keys, enum names, bounded numbers and booleans leave this object. */
    fun dump(writer:PrintWriter){
        val summary=totals.get();val serviceState=service.get();val cycle=snapshot()
        writer.println("buri_sync_diagnostics schema=1")
        writer.println("service_phase=${serviceState.phase} service_problem=${serviceState.problem} service_error=${serviceState.error} service_error_phase=${serviceState.errorPhase}")
        writer.println("cycles_started=${summary.started} cycles_completed=${summary.completed} cycles_unconfirmed=${summary.unconfirmed} busy_skips=${summary.busy}")
        if(cycle==null){writer.println("phase=IDLE outcome=NOT_RUN");return}
        writer.println("phase=${cycle.phase} outcome=${cycle.outcome} problem=${cycle.problem} online=${cycle.online} elapsed_ms=${cycle.elapsedMs}")
        writer.println("coordinator=${cycle.coordinator} coordinator_phase=${cycle.coordinatorPhase} fence=${cycle.fence} fence_phase=${cycle.fencePhase}")
        writer.println("stop=${cycle.stop} stop_phase=${cycle.stopPhase} error=${cycle.error} error_phase=${cycle.errorPhase} errors=${cycle.errors}")
        writer.println("queue_read=${cycle.queueRead} queued=${cycle.queued} attempts=${cycle.attempts} acknowledged=${cycle.acknowledged} unresolved=${cycle.unresolved} more=${cycle.more}")
    }
}
