package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

class MomoGatewayPolicyTest {
    private fun memberCapture(sender: String, body: String, complete: Boolean = true): Boolean =
        MomoMultipartPolicy.memberCaptureEligible(sender, MomoMultipartPolicy.Assembly(body, complete))

    @Test fun memberCaptureKeepsCompleteFinancialMessagesWithoutAReceiptTemplate() {
        for (body in listOf("You received 1500 RWF.", "Sent 3000 RWF. Txn 1234", "Transaction failed: 100 RWF", "Reversal 321: 200 UGX", "Wakiriye 600 RWF"))
            assertTrue(body, memberCapture("M-Money", body))
        val maskedReceipt = "You have received 1,500 RWF from TEST MEMBER A (***456) " +
            "at 2026-09-02 10:00:00. Your balance: 0 RWF."
        assertTrue(memberCapture("M-Money", maskedReceipt))
        assertTrue(memberCapture("AirtelMoney", "Wakiriye 45,000 RWF from 0732123456. Transaction ID 88776655"))
        assertFalse(memberCapture("M-Money", "You received 1500 RWF.", complete = false))
    }
    @Test fun memberCaptureExcludesKnownUnrelatedPromotionalAndCredentialMessages() {
        assertFalse(memberCapture("Courier", "Received 100 RWF ref 123"))
        assertFalse(memberCapture("M-Money", "OTP verification code 123456 for transaction 100 RWF"))
        assertFalse(memberCapture("MTN MoMo", "Promotion: buy a bundle for 1000 RWF"))
        assertFalse(memberCapture("M-Money", "Your PIN is 1234 for 1000 RWF"))
        assertFalse(memberCapture("M-Money", "Hello"))
        for (credential in listOf("authorization code", "AUTHORISATION CODE", "password", "mot de passe")) {
            assertFalse(credential, memberCapture("MTN", "Your $credential is 123456; transaction 100 RWF"))
        }
        assertTrue(memberCapture("MTN", "Transaction code 123456: received 100 RWF"))
    }

    @Test fun deterministicSourceFailuresDoNotStopUnrelatedUploads() {
        fun eligible(binding: String = "binding-1", unresolved: Boolean = false, parked: Boolean = false) =
            MomoGatewayPolicy.uploadEligible(binding, 1, "binding-1", 1, unresolved, parked,
                "live", true, "M-Money", "You received 500 RWF, transaction 123")
        assertEquals(MomoGatewayPolicy.UploadFailure.SOURCE_CONFLICT, MomoGatewayPolicy.uploadFailure(409))
        assertEquals(MomoGatewayPolicy.UploadFailure.SOURCE_REJECTED, MomoGatewayPolicy.uploadFailure(422))
        assertFalse(eligible(parked = true))
        assertFalse(eligible())
        assertFalse(eligible(binding = "binding-old"))
        assertFalse(eligible(unresolved = true))
    }
    @Test fun ownerHoldStopsEvenCompleteLiveFinancialMessages() {
        fun eligible(mode: String = "live", complete: Boolean = true, sender: String = "M-Money",
                     body: String = "You received 500 RWF, transaction 123") =
            MomoGatewayPolicy.uploadEligible("binding-1", 1, "binding-1", 1, false, false,
                mode, complete, sender, body)
        assertFalse(MomoGatewayPolicy.gatewayUploadsAdmitted())
        assertFalse(eligible())
        assertFalse(eligible(complete = false))
        // Legacy inbox rows claimed complete without retaining PDU evidence.
        assertFalse(eligible(mode = "catch_up"))
        assertFalse(eligible(mode = ""))
        assertFalse(eligible(sender = "Courier"))
        assertFalse(eligible(body = "Your verification code is 1234 for transaction 5 RWF"))
        assertFalse(eligible(body = "Your passcode is 1234 for transaction 5 RWF"))
        assertFalse(eligible(body = "Your security code is 1234 for transaction 5 RWF"))
        assertFalse(eligible(sender = "MTN", body = "Your login code is 123456; reference 42"))
        assertFalse(eligible(body = "Your code is 123456; transaction 42 RWF"))
        assertFalse(eligible(body = "Votre code est 123456, référence transaction 42 RWF"))
        assertFalse(eligible(body = "Airtime offer 5 RWF"))
    }
    @Test fun inboxRecoveryReservesSpaceForLiveCapture() {
        val max = MomoGatewayPolicy.MAX_PENDING
        val reserve = MomoGatewayPolicy.LIVE_CAPTURE_RESERVE
        assertEquals(MomoGatewayPolicy.QueueAdmission.AVAILABLE, MomoGatewayPolicy.queueAdmission(max - reserve - 1, max, reserve))
        assertEquals(MomoGatewayPolicy.QueueAdmission.RESERVED, MomoGatewayPolicy.queueAdmission(max - reserve, max, reserve))
        assertEquals(MomoGatewayPolicy.QueueAdmission.RESERVED, MomoGatewayPolicy.queueAdmission(max, max, reserve))
        assertEquals(MomoGatewayPolicy.QueueAdmission.AVAILABLE, MomoGatewayPolicy.queueAdmission(max - reserve, max, 0))
        assertEquals(MomoGatewayPolicy.QueueAdmission.FULL, MomoGatewayPolicy.queueAdmission(max, max, 0))
    }
    @Test fun authorizationAndTemporaryFailuresHaveDifferentRecoveryOwners() {
        assertEquals(MomoGatewayPolicy.UploadFailure.AUTHORIZATION, MomoGatewayPolicy.uploadFailure(401))
        assertEquals(MomoGatewayPolicy.UploadFailure.AUTHORIZATION, MomoGatewayPolicy.uploadFailure(403))
        for (status in listOf(408, 429, 500, 503)) assertEquals(MomoGatewayPolicy.UploadFailure.RETRY, MomoGatewayPolicy.uploadFailure(status))
    }
    @Test fun sourceCaptureRetainsChangedFormatsAndReversalsForServerClassification() {
        assertTrue(MomoGatewayPolicy.providerSource("M-Money"))
        assertTrue(MomoGatewayPolicy.providerSource("MTN MoMo"))
        assertTrue(MomoGatewayPolicy.providerSource("AirtelMoney"))
        assertFalse(MomoGatewayPolicy.providerSource("Courier"))
        assertFalse(MomoGatewayPolicy.providerSource("a"))
    }
    @Test fun captureIdentitySurvivesRetryAndPreservesUnicodeAndWhitespace() {
        fun identity(body: String = "Wakiriye 1,000 RWF\nTX: 000123 é", binding: String = "binding-1", sim: Int? = 7) =
            MomoGatewayPolicy.captureId("installation-1", binding, "M-Money", body, 1700000000000, sim)
        assertEquals(identity(), identity())
        assertNotEquals(identity(), identity("Wakiriye 1,000 RWF TX: 000123 é"))
        assertNotEquals(identity(), identity(binding = "binding-2"))
        assertNotEquals(identity(), identity(sim = 8))
    }
    @Test fun multiSimNeverChoosesAnUnobservedOrDifferentSubscription() {
        assertFalse(MomoGatewayPolicy.sourceResolved(null, null, true))
        assertFalse(MomoGatewayPolicy.sourceResolved(7, null, true))
        assertFalse(MomoGatewayPolicy.sourceResolved(7, 8, true))
        assertTrue(MomoGatewayPolicy.sourceResolved(7, 7, true))
        assertTrue(MomoGatewayPolicy.sourceResolved(null, null, false))
    }
    @Test fun oldUncapturedInboxMessagesNeverInheritCurrentWallet() {
        assertFalse(MomoGatewayPolicy.historicalSourceResolved(12, null, null, null, false))
        assertFalse(MomoGatewayPolicy.historicalSourceResolved(12, 12, null, null, false))
        assertFalse(MomoGatewayPolicy.historicalSourceResolved(11, 12, 7, 7, false))
        assertTrue(MomoGatewayPolicy.historicalSourceResolved(13, 12, 7, 7, false))
    }
    @Test fun mixedSenderAndMissingPartsDoNotClaimCompleteness() {
        assertTrue(MomoGatewayPolicy.completeParts(listOf("M-Money", "M-Money"), listOf(10, 10), listOf("TX 000", "123")))
        assertFalse(MomoGatewayPolicy.completeParts(listOf("M-Money", "Airtel"), listOf(10, 10), listOf("TX 000", "123")))
        assertFalse(MomoGatewayPolicy.completeParts(listOf("M-Money"), listOf(10), listOf(null)))
        assertFalse(MomoGatewayPolicy.completeParts(listOf("M-Money"), listOf(0), listOf("TX 000")))
    }
}
