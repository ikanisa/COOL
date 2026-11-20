package app.cool.mobile.receiver_sms

/** One process-local owner; the encrypted outbox and platform jobs survive process death. */
class MomoGatewayWakeupGate {
    private val lock = Any()
    private var running = false
    fun begin(): Boolean = synchronized(lock) { if (running) false else { running = true; true } }
    fun signal(schedule: () -> Unit) = synchronized(lock) { if (!running) schedule() }
    fun finish(finishJob: () -> Unit, recheckAfterFinish: () -> Unit) = synchronized(lock) {
        finishJob()
        running = false
        recheckAfterFinish()
    }
}
