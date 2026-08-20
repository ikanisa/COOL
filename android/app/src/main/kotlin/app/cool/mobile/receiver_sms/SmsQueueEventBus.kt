package app.cool.mobile.receiver_sms

import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.atomic.AtomicLong

/**
 * Process-local, metadata-only signal that an encrypted SMS queue changed.
 *
 * Raw SMS fields never cross this listener. A manifest receiver can capture
 * while the UI process is cold; the durable queue remains the source of truth
 * and this signal only removes foreground polling latency.
 */
object SmsQueueEventBus {
    private val listeners = CopyOnWriteArraySet<(Long) -> Unit>()
    private val sequence = AtomicLong(0L)

    fun addListener(listener: (Long) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (Long) -> Unit) {
        listeners.remove(listener)
    }

    fun notifyQueueChanged() {
        val nextSequence = sequence.incrementAndGet()
        listeners.forEach { listener ->
            runCatching { listener(nextSequence) }
        }
    }
}
