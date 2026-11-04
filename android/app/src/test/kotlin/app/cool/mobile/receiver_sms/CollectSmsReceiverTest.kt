package app.cool.mobile.receiver_sms

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CollectSmsReceiverTest {
    private val receiver = CollectSmsReceiver()

    @Test
    fun envelopePreservesExactEvidenceWhitespace() {
        val body = "You have received 1,500 RWF from TEST MEMBER A (***456). Balance: 9,500 RWF."
        assertNotEquals(
            receiver.envelopeIdFor("user-1", "M-Money", body, 1_700_000_000_000),
            receiver.envelopeIdFor("user-1", "M-Money", " $body\n", 1_700_000_000_000),
        )
    }

    @Test
    fun envelopeIdIsStableForDuplicateBroadcastsAndChangesWithTimestamp() {
        val first = receiver.envelopeIdFor(
            "user-1",
            "M-Money",
            "You have received RWF 50,000 from 0788123456. Txn 12345678901.",
            1_700_000_000_000,
        )
        val duplicate = receiver.envelopeIdFor(
            "user-1",
            "M-Money",
            "You have received RWF 50,000 from 0788123456. Txn 12345678901.",
            1_700_000_000_000,
        )
        val later = receiver.envelopeIdFor(
            "user-1",
            "M-Money",
            "You have received RWF 50,000 from 0788123456. Txn 12345678901.",
            1_700_000_001_000,
        )

        assertEquals(first, duplicate)
        assertNotEquals(first, later)
        assertEquals(5, UUID.fromString(first).version())
    }

    @Test
    fun queueEventBusEmitsMonotonicMetadataOnlySignals() {
        val before = SmsQueueEventBus.currentSequence()
        val observed = mutableListOf<Long>()
        val listener: (Long) -> Unit = observed::add
        SmsQueueEventBus.addListener(listener)
        try {
            SmsQueueEventBus.notifyQueueChanged()
            SmsQueueEventBus.notifyQueueChanged()
        } finally {
            SmsQueueEventBus.removeListener(listener)
        }

        assertEquals(2, observed.size)
        assertTrue(observed[0] > before)
        assertTrue(observed[1] > observed[0])
        assertEquals(observed[1], SmsQueueEventBus.currentSequence())
    }
}
