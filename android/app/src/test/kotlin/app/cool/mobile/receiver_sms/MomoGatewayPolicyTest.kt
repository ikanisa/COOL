package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

class MomoGatewayPolicyTest {
    @Test fun deterministicSourceFailuresDoNotStopUnrelatedUploads() {
        assertEquals(MomoGatewayPolicy.UploadFailure.SOURCE_CONFLICT, MomoGatewayPolicy.uploadFailure(409))
        assertEquals(MomoGatewayPolicy.UploadFailure.SOURCE_REJECTED, MomoGatewayPolicy.uploadFailure(422))
        assertFalse(MomoGatewayPolicy.uploadEligible("binding-1", 1, "binding-1", 1, false, true))
        assertTrue(MomoGatewayPolicy.uploadEligible("binding-1", 1, "binding-1", 1, false, false))
        assertFalse(MomoGatewayPolicy.uploadEligible("binding-old", 1, "binding-1", 1, false, false))
        assertFalse(MomoGatewayPolicy.uploadEligible("binding-1", 1, "binding-1", 1, true, false))
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
