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
    fun acceptsScopedEnglishBankCredit() {
        assertTrue(
            receiver.isLikelyBankNotification(
                "Revolut",
                "Incoming transfer received: EUR 50.00. Reference COL-ABC1234567.",
            ),
        )
    }

    @Test
    fun acceptsScopedFrenchAndGermanBankCredits() {
        assertTrue(
            receiver.isLikelyBankNotification(
                "Collect Bank",
                "Paiement reçu: EUR 25.00. Référence COL-ABC1234567.",
            ),
        )
        assertTrue(
            receiver.isLikelyBankNotification(
                "SEPA Credit",
                "Gutschrift EUR 45,00. End-to-end reference COL-ABC1234567.",
            ),
        )
    }

    @Test
    fun rejectsCreditsWithoutCurrencyOrReference() {
        assertFalse(
            receiver.isLikelyBankNotification(
                "Revolut",
                "Incoming transfer received: 50.00. Reference COL-ABC1234567.",
            ),
        )
        assertFalse(
            receiver.isLikelyBankNotification(
                "Revolut",
                "Incoming transfer received: EUR 50.00.",
            ),
        )
    }

    @Test
    fun rejectsMarketingAndUnrelatedFinancialSms() {
        assertFalse(
            receiver.isLikelyBankNotification(
                "Revolut",
                "Promotion: invite a friend and earn EUR 10.00. Ref BONUS10.",
            ),
        )
        assertFalse(
            receiver.isLikelyBankNotification(
                "Courier",
                "Package received. Reference COL-ABC1234567. EUR 10.00.",
            ),
        )
        assertFalse(
            receiver.isLikelyBankNotification(
                "Collect Bank",
                "Transfer pending: EUR 10.00. Reference COL-ABC1234567.",
            ),
        )
    }

    @Test
    fun envelopeIdIsStableForDuplicateBroadcastsAndChangesWithTimestamp() {
        val first = receiver.envelopeIdFor(
            "user-1",
            "Revolut",
            "Incoming transfer received: EUR 50.00. Reference COL-ABC1234567.",
            1_700_000_000_000,
        )
        val duplicate = receiver.envelopeIdFor(
            "user-1",
            "Revolut",
            "Incoming transfer received: EUR 50.00. Reference COL-ABC1234567.",
            1_700_000_000_000,
        )
        val later = receiver.envelopeIdFor(
            "user-1",
            "Revolut",
            "Incoming transfer received: EUR 50.00. Reference COL-ABC1234567.",
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
