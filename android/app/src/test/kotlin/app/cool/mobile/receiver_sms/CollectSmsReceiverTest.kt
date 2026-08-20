package app.cool.mobile.receiver_sms

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CollectSmsReceiverTest {
    private val receiver = CollectSmsReceiver()

    @Test
    fun acceptsScopedEnglishMomoTransaction() {
        assertTrue(
            receiver.isLikelyMobileMoney(
                "MTN MoMo",
                "You received RWF 5,000 from a customer.",
            ),
        )
    }

    @Test
    fun acceptsScopedFrenchAndKinyarwandaTransactions() {
        assertTrue(
            receiver.isLikelyMobileMoney(
                "Airtel Money",
                "Paiement reçu: 2 500 FRW.",
            ),
        )
        assertTrue(
            receiver.isLikelyMobileMoney(
                "M-Money",
                "Konti yawe yakiriye amafaranga 4,500 RWF.",
            ),
        )
    }

    @Test
    fun acceptsProviderTransactionWithAmountAndReferenceWithoutCurrencyMarker() {
        assertTrue(
            receiver.isLikelyMobileMoney(
                "M-Money",
                "You have received 5000. Financial Transaction Id: 123456789.",
            ),
        )
        assertTrue(
            receiver.isLikelyMobileMoney(
                "M-Money",
                "Wakiriye RWF 3,000 kuri MTN Mobile Money.",
            ),
        )
    }

    @Test
    fun rejectsProviderMarketingAndUnrelatedFinancialSms() {
        assertFalse(
            receiver.isLikelyMobileMoney(
                "MTN",
                "Buy a weekly bundle today for RWF 1,000.",
            ),
        )
        assertFalse(
            receiver.isLikelyMobileMoney(
                "Bank",
                "Payment received: RWF 10,000.",
            ),
        )
        assertFalse(
            receiver.isLikelyMobileMoney(
                "Airtel Money",
                "Payment received successfully.",
            ),
        )
        assertFalse(
            receiver.isLikelyMobileMoney(
                "MTN MoMo",
                "Promotion: buy a bundle today and pay only RWF 1,000.",
            ),
        )
    }

    @Test
    fun envelopeIdIsStableForDuplicateBroadcastsAndChangesWithTimestamp() {
        val first = receiver.envelopeIdFor(
            "user-1",
            "M-Money",
            "You received RWF 5,000. Transaction Id: ABC1234.",
            1_700_000_000_000,
        )
        val duplicate = receiver.envelopeIdFor(
            "user-1",
            "M-Money",
            "You received RWF 5,000. Transaction Id: ABC1234.",
            1_700_000_000_000,
        )
        val later = receiver.envelopeIdFor(
            "user-1",
            "M-Money",
            "You received RWF 5,000. Transaction Id: ABC1234.",
            1_700_000_001_000,
        )

        assertEquals(first, duplicate)
        assertNotEquals(first, later)
        assertEquals(5, UUID.fromString(first).version())
    }

    @Test
    fun queueEventBusEmitsMonotonicMetadataOnlySignals() {
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
        assertTrue(observed[1] > observed[0])
    }
}
