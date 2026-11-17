package app.cool.mobile.receiver_sms

import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import java.util.UUID
import rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth

/** A cached successful cycle cannot extend the original reconciliation proof. */
internal object ContinuousSyncHealthFreshness {
    const val MAX_PROOF_AGE_MS=5*60_000L
    fun fresh(started:Long?,now:Long):Boolean = started!=null&&started>=0&&now>=started&&now-started<MAX_PROOF_AGE_MS
    fun expire(health:ContinuousReceiverHealth,now:Long,observerActive:Boolean):ContinuousReceiverHealth =
        if(health.running&&health.problem==null&&(!observerActive||!fresh(health.proofStartedAtElapsed,now)))
            health.copy(problem="sync_unconfirmed",proofStartedAtElapsed=null) else health
}

/** Expiry is committed atomically so a clock reversal cannot revive old success. */
internal class ContinuousSyncHealthState(initial:ContinuousReceiverHealth=ContinuousReceiverHealth(supported=true)) {
    private val value=AtomicReference(initial)
    fun get()=value.get()
    fun set(health:ContinuousReceiverHealth)=value.set(health)
    fun compareAndSet(expected:ContinuousReceiverHealth,next:ContinuousReceiverHealth)=value.compareAndSet(expected,next)
    fun health(now:Long,observerActive:Boolean):ContinuousReceiverHealth {
        while(true){
            val current=value.get();val checked=ContinuousSyncHealthFreshness.expire(current,now,observerActive)
            if(checked==current||value.compareAndSet(current,checked))return checked
        }
    }
}

/** A local change token only; it contains no SMS data or persistent identity. */
internal object ObservationInboxRevision {
    private val current=AtomicLong()
    private val process=UUID.randomUUID().toString()
    private val observerLock=Any()
    private var observer:Any?=null
    fun epoch():String=process
    fun snapshot():Long=current.get()
    fun changed(){current.incrementAndGet()}
    /** Called only after Android has accepted the content-observer registration. */
    fun observerRegistered():Any=synchronized(observerLock){
        Any().also{observer=it;current.incrementAndGet()}
    }
    /** Invalidate all process-local sweep witnesses before unregistering. */
    fun observerDetached(lease:Any)=synchronized(observerLock){
        if(observer===lease){observer=null;current.incrementAndGet()}
    }
    fun observerActive():Boolean=synchronized(observerLock){observer!=null}
}

/** Shared by jobs and the supervisor. An interrupted caller cannot release another cycle's lease. */
internal class ContinuousSyncWorkGate {
    private val permit=Semaphore(1)
    fun <T> runIfIdle(action:()->T):T? {
        if(!permit.tryAcquire())return null
        return try{action()}finally{permit.release()}
    }
}

/** Stops between bounded I/O operations; a lost final acknowledgement keeps its original identity. */
internal class ContinuousSyncBudget(
    private val now:()->Long,
    private val cancelled:()->Boolean,
    private val maximumMs:Long=60_000,
){
    private val started=now()
    init{require(started>=0&&maximumMs in 1_000..120_000)}
    fun stopped():Boolean {
        val current=now()
        return cancelled()||current<started||current-started>=maximumMs
    }
}

/** Event wakeups bypass this idle/error delay; failures never create an unbounded busy loop. */
internal class ContinuousSyncRetry {
    private var failures=0
    fun next(completed:Boolean,more:Boolean,progress:Boolean=false):Long {
        if(completed){failures=0;return if(more)2_000 else 30_000}
        if(progress&&more){failures=0;return 2_000}
        failures=(failures+1).coerceAtMost(3)
        return 15_000L shl (failures-1)
    }
}
