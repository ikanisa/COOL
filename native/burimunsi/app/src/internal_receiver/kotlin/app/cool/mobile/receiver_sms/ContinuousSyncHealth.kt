package app.cool.mobile.receiver_sms

import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.atomic.AtomicReference
import rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth

/** A control may call another control or overlap one on another thread. A stable
 * revision exists only after every operation has left its mutation interval. */
internal object ObservationAuthorityRevision {
    private val lock = Any()
    private var generation = 0L
    private var mutations = 0
    private val listeners = CopyOnWriteArraySet<() -> Unit>()

    fun stable(): Long? = synchronized(lock) { generation.takeIf { mutations == 0 } }

    private fun advance(change: Int) {
        synchronized(lock) { mutations += change; generation++ }
        listeners.forEach { runCatching { it() } }
    }

    fun changed() = advance(0)
    fun <T> changing(action: () -> T): T {
        advance(1)
        try { return action() } finally { advance(-1) }
    }
    fun observe(listener: () -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }
}

internal data class ObservationHealthProof(val verifiedAt: Long, val inbox: Long, val authority: Long) {
    companion object { const val MAX_AGE_MS = 5 * 60_000L }
    fun current(now: Long, revision: Long?, inboxRevision: Long, observed: Boolean): Boolean =
        observed && revision == authority && inbox == inboxRevision &&
            verifiedAt >= 0 && now >= verifiedAt && now - verifiedAt < MAX_AGE_MS
}

/** A stale positive result is permanently withdrawn, even if the monotonic
 * clock or a control later returns to a previously observed value. */
internal class ContinuousSyncHealthState {
    private data class Published(val health: ContinuousReceiverHealth, val proof: ObservationHealthProof?)
    private val state = AtomicReference(Published(ContinuousReceiverHealth(supported = true), null))
    fun get(): ContinuousReceiverHealth = state.get().health
    fun proof(): ObservationHealthProof? = state.get().proof

    fun set(health: ContinuousReceiverHealth, proof: ObservationHealthProof? = null) {
        val positive = health.running && health.problem == null
        state.set(if (positive && proof == null) Published(health.copy(problem = "sync_unconfirmed"), null)
            else Published(health, proof.takeIf { positive }))
    }

    fun compareAndSet(before: ContinuousReceiverHealth, next: ContinuousReceiverHealth) {
        val old = state.get()
        if (old.health === before) state.compareAndSet(old, Published(next, null))
    }

    fun invalidate() { checkProof { false } }
    fun checked(now: Long, authority: Long?, inbox: Long, observed: Boolean): ContinuousReceiverHealth =
        checkProof { proof -> proof.current(now, authority, inbox, observed) }

    private fun checkProof(current: (ObservationHealthProof) -> Boolean): ContinuousReceiverHealth {
        while (true) {
            val old = state.get()
            val proof = old.proof ?: return old.health
            if (current(proof)) return old.health
            val expired = Published(old.health.copy(problem = "sync_unconfirmed"), null)
            if (state.compareAndSet(old, expired)) return expired.health
        }
    }
}
