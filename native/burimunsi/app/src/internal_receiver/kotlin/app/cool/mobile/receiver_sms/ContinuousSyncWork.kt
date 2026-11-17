package app.cool.mobile.receiver_sms

import java.util.concurrent.Semaphore

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
    fun next(completed:Boolean,more:Boolean):Long {
        if(completed){failures=0;return if(more)2_000 else 30_000}
        failures=(failures+1).coerceAtMost(3)
        return 15_000L shl (failures-1)
    }
}
