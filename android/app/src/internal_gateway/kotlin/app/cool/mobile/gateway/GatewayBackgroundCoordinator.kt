package app.cool.mobile.gateway

import java.util.concurrent.atomic.AtomicBoolean

/** A scheduled cycle can be stopped before any new external invocation. */
internal class GatewayCycleToken(private val elapsed: () -> Long = { System.nanoTime() / 1_000_000 }) {
    private val cancelled = AtomicBoolean(false)
    private val started = elapsed()
    fun cancel() {
        cancelled.set(true)
        // Return only after an already admitted invocation has left the final
        // journal/invoker critical section. Never wait for arm HTTP here.
        synchronized(GatewayJournal.PROCESS_LOCK) { }
    }
    fun active(): Boolean = !cancelled.get() && elapsed() - started in 0..MAX_CYCLE_MILLIS
    companion object { const val MAX_CYCLE_MILLIS = 90_000L }
}

/** Background and manually requested network work share this process gate.
 * Pause and framework callback journaling do not wait for this network gate. */
internal object GatewayCycleGate {
    private val held = AtomicBoolean(false)
    fun <T> run(action: () -> T): T? {
        if (!held.compareAndSet(false, true)) return null
        try { return action() } finally { held.set(false) }
    }
}

internal data class GatewayCycleResult(val reasonCode: String, val backoff: Boolean)

/** Ordering local intents is independent of network completion ordering. */
internal class GatewayLocalDispatchIntent {
    private var epoch = 0L
    fun generation(): Long = synchronized(GatewayJournal.PROCESS_LOCK) { epoch }
    fun invalidate() = synchronized(GatewayJournal.PROCESS_LOCK) { epoch++ }
    fun pause(journal: GatewayJournal) = synchronized(GatewayJournal.PROCESS_LOCK) { epoch++; journal.pause() }
    fun allow(expected: Long, journal: GatewayJournal) = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (epoch != expected) throw GatewayStateException("gateway_local_intent_superseded")
        journal.resume()
    }
}

internal class GatewayGuardedSmsInvoker(private val delegate: GatewaySmsInvoker, private val active: () -> Boolean) : GatewaySmsInvoker {
    override fun divide(body: String, subscriptionId: Int): List<String> {
        if (!active()) throw GatewayStateException("gateway_cycle_stopped")
        return delegate.divide(body, subscriptionId)
    }
    override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
        synchronized(GatewayJournal.PROCESS_LOCK) {
            if (!active()) throw GatewayStateException("gateway_cycle_stopped")
            delegate.invoke(grant, record, parts, subscriptionId)
        }
    }
}

internal object GatewaySchedulePolicy {
    const val IDLE_MILLIS = 5 * 60_000L
    const val MAX_FAILURES = 6
    fun failures(previous: Int, backoff: Boolean): Int = if (backoff) (previous.coerceIn(0, MAX_FAILURES) + 1).coerceAtMost(MAX_FAILURES) else 0
    fun delayMillis(failures: Int): Long = if (failures <= 0) IDLE_MILLIS else
        (60_000L * (1L shl failures.coerceIn(1, MAX_FAILURES))).coerceAtMost(30 * 60_000L)
}

internal class GatewayBackgroundCoordinator(
    private val journal: GatewayJournal,
    private val backend: GatewayBackend,
    private val observe: () -> GatewayObservations,
    private val dispatch: () -> GatewayAttempt?,
    private val configured: () -> Boolean,
    private val verifyEnrollment: () -> Unit,
    private val token: GatewayCycleToken,
) {
    fun cycle(dispatchAllowed: Boolean = true): GatewayCycleResult = GatewayCycleGate.run {
        try {
            if (!token.active()) return@run GatewayCycleResult("gateway_cycle_stopped", true)
            verifyEnrollment()
            journal.read() // Corrupt evidence is never replaced with an empty journal.
            if (!configured()) return@run GatewayCycleResult("gateway_not_configured", true)
            val observation = observe()
            if (!observation.networkConnected || !observation.networkValidated) return@run GatewayCycleResult("gateway_network_unavailable", true)
            // Permission/SIM/local pause are recorded independently; they do
            // not prevent reconciliation of already armed callback evidence.
            var healthRecorded = true
            try { backend.heartbeat(observation) } catch (_: Exception) { healthRecorded = false }
            if (!token.active()) return@run GatewayCycleResult("gateway_cycle_stopped", true)
            backend.reconcile(journal.read())
            if (!token.active()) return@run GatewayCycleResult("gateway_cycle_stopped", true)
            if (!healthRecorded) return@run GatewayCycleResult("gateway_health_unavailable", true)
            if (journal.read().emergencyPaused || !dispatchAllowed) return@run GatewayCycleResult("gateway_health_evidence_recorded", false)
            if (!observe().ready()) return@run GatewayCycleResult("gateway_device_not_ready", true)
            val attempt = dispatch() // Engine obtains fresh signed grant and final arm itself.
            GatewayCycleResult(if (attempt == null) "gateway_no_authorized_receipt" else "gateway_invocation_reserved", false)
        } catch (failure: GatewayStateException) {
            GatewayCycleResult(if (failure.reasonCode.matches(Regex("gateway_[a-z_]{1,80}"))) failure.reasonCode else "gateway_operation_unavailable", true)
        } catch (_: Exception) {
            GatewayCycleResult("gateway_operation_unavailable", true)
        }
    } ?: GatewayCycleResult("gateway_cycle_busy", true)

    /** An explicit local preference, never remote activation or send authority. */
    fun allowGovernedDispatch(commitLocalIntent: () -> Unit = journal::resume): GatewayCycleResult = GatewayCycleGate.run {
        verifyEnrollment()
        if (!configured()) throw GatewayStateException("gateway_not_configured")
        if (!token.active()) throw GatewayStateException("gateway_cycle_stopped")
        commitLocalIntent()
        GatewayCycleResult("gateway_local_dispatch_allowed", false)
    } ?: throw GatewayStateException("gateway_cycle_busy")
}
