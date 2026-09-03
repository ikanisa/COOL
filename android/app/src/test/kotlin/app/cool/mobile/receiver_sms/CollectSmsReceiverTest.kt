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
    fun acceptsScopedEnglishMomoCredit() {
        assertTrue(
            receiver.isLikelyMomoReceipt(
                "M-Money",
                "You have received RWF 50,000 from 0788123456. Financial Transaction Id: 12345678901.",
            ),
        )
    }

    @Test
    fun acceptsMtnAndAirtelReceiptSenders() {
        assertTrue(
            receiver.isLikelyMomoReceipt(
                "MTN MoMo",
                "Payment received: 25,000 RWF from 0788123456. Txn 99887766",
            ),
        )
        assertTrue(
            receiver.isLikelyMomoReceipt(
                "AirtelMoney",
                "Wakiriye 45,000 RWF from 0732123456. Transaction ID 88776655",
            ),
        )
    }

    @Test
    fun rejectsReceiptsWithoutCurrencyOrTransactionIdentity() {
        assertFalse(
            receiver.isLikelyMomoReceipt(
                "M-Money",
                "You have received 50,000 from 0788123456. Txn 99887766",
            ),
        )
        assertFalse(
            receiver.isLikelyMomoReceipt(
                "M-Money",
                "You have received RWF 50,000 from 0788123456.",
            ),
        )
    }

    @Test
    fun acceptsCompleteMaskedReceiptWithoutProviderReference() {
        val body = "You have received 1,500 RWF from TEST MEMBER A (***456) " +
            "at 2026-09-02 10:00:00. Your balance: 9,500 RWF."
        assertTrue(receiver.isLikelyMomoReceipt("M-Money", body))
        assertTrue(receiver.isLikelyMomoReceipt("M-Money", body.replace("9,500", "0")))
        assertFalse(receiver.isLikelyMomoReceipt("M-Money", body.replace("***456", "***45")))
        assertFalse(receiver.isLikelyMomoReceipt("M-Money", "Reversed. $body"))
        assertFalse(receiver.isLikelyMomoReceipt("M-Money", "Withdrawal. $body"))
        assertFalse(receiver.isLikelyMomoReceipt("M-Money", "OTP verification code. $body"))
        assertFalse(receiver.isLikelyMomoReceipt("M-Money", body.substringBefore("Your balance")))
    }

    @Test
    fun envelopePreservesExactEvidenceWhitespace() {
        val body = "You have received 1,500 RWF from TEST MEMBER A (***456). Balance: 9,500 RWF."
        assertNotEquals(
            receiver.envelopeIdFor("user-1", "M-Money", body, 1_700_000_000_000),
            receiver.envelopeIdFor("user-1", "M-Money", " $body\n", 1_700_000_000_000),
        )
    }

    @Test
    fun rejectsMarketingAndUnrelatedFinancialSms() {
        assertFalse(
            receiver.isLikelyMomoReceipt(
                "M-Money",
                "Promotion: invite a friend and earn RWF 10,000. Txn BONUS10.",
            ),
        )
        assertFalse(
            receiver.isLikelyMomoReceipt(
                "Courier",
                "Package received. Transaction ID 123456. RWF 10,000.",
            ),
        )
        assertFalse(
            receiver.isLikelyMomoReceipt(
                "AirtelMoney",
                "Transaction pending: RWF 10,000 from 0732123456. Txn 123456.",
            ),
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
