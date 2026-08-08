package app.cool.mobile.receiver_sms

import org.junit.Assert.assertFalse
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
    }
}
