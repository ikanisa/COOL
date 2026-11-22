package androidx.compose.runtime.snapshots

import androidx.compose.runtime.MutableState
import java.util.concurrent.atomic.AtomicBoolean

/** The receiver can publish a queue snapshot from IO. Buffer its writes and reject a
 * conflicting UI write at apply time, as required by the production snapshot consumer.
 */
object Snapshot {
    val conflict = AtomicBoolean()
    private val lock = Any()
    private class Entry(val version: Long, var value: Any?, var written: Boolean = false)
    private val active = ThreadLocal<MutableMap<MutableState<*>, Entry>>()

    private fun MutableMap<MutableState<*>, Entry>.entry(state: MutableState<*>) =
        getOrPut(state) { Entry(state.version, state.committed) }

    @Suppress("UNCHECKED_CAST")
    internal fun <T> read(state: MutableState<T>): T = synchronized(lock) {
        val snapshot = active.get()
        (if (snapshot == null) state.committed else snapshot.entry(state).value) as T
    }

    internal fun <T> write(state: MutableState<T>, next: T) = synchronized(lock) {
        val snapshot = active.get()
        if (snapshot == null) commit(state, next) else {
            val entry = snapshot.entry(state)
            if (!state.equivalent(entry.value, next)) {
                entry.value = next
                entry.written = true
            }
        }
    }

    private fun commit(state: MutableState<*>, next: Any?) {
        if (!state.equivalent(state.committed, next)) {
            state.committed = next
            state.version++
        }
    }

    fun <T> withMutableSnapshot(block: () -> T): T {
        if (conflict.compareAndSet(true, false)) throw SnapshotApplyConflictException()
        check(active.get() == null)
        val snapshot = mutableMapOf<MutableState<*>, Entry>()
        active.set(snapshot)
        try {
            val result = block()
            synchronized(lock) {
                if (snapshot.any { (state, entry) -> entry.written && state.version != entry.version && !state.equivalent(state.committed, entry.value) })
                    throw SnapshotApplyConflictException()
                for ((state, entry) in snapshot) if (entry.written) commit(state, entry.value)
            }
            return result
        } finally {
            active.remove()
        }
    }
}

class SnapshotApplyConflictException : Exception()
