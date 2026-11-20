package app.cool.mobile.receiver_sms

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsQueueOwnerPolicyTest {
    @Test fun captureStatusDisclosesReceiptFlagsOnlyToTheCurrentRequestedOwner() {
        assertTrue(SmsQueueOwnerPolicy.canSeeCaptureStatus("account-a", "account-a"))
        assertFalse(SmsQueueOwnerPolicy.canSeeCaptureStatus("account-a", "account-b"))
        assertFalse(SmsQueueOwnerPolicy.canSeeCaptureStatus("account-a", ""))
        assertFalse(SmsQueueOwnerPolicy.canSeeCaptureStatus("", ""))
        assertTrue(SmsQueueOwnerPolicy.canSeeCaptureStatus("account-a", null))
    }

    @Test
    fun disableRequiresTheBoundOwnerAndNeverAcceptsAnEmptyCaller() {
        assertTrue(SmsQueueOwnerPolicy.canDisable("account-a", "account-a"))
        assertTrue(SmsQueueOwnerPolicy.canDisable("", "account-a"))
        assertFalse(SmsQueueOwnerPolicy.canDisable("account-b", "account-a"))
        assertFalse(SmsQueueOwnerPolicy.canDisable("account-a", ""))
    }

    @Test
    fun onlyCurrentAuthenticatedOwnerCanRead() {
        assertTrue(SmsQueueOwnerPolicy.canRead(true, "account-a", "account-a", listOf("account-a")))
        assertFalse(SmsQueueOwnerPolicy.canRead(false, "account-a", "account-a", listOf("account-a")))
        assertFalse(SmsQueueOwnerPolicy.canRead(true, "account-a", "account-b", listOf("account-a")))
        assertFalse(SmsQueueOwnerPolicy.canRead(true, "", "", emptyList()))
    }

    @Test
    fun mixedOrUnownedEvidenceNeverLeavesQueue() {
        assertFalse(SmsQueueOwnerPolicy.canRead(true, "account-a", "account-a", listOf("account-b")))
        assertFalse(SmsQueueOwnerPolicy.canRead(true, "account-a", "account-a", listOf("account-a", "account-b")))
        assertFalse(SmsQueueOwnerPolicy.canRead(true, "account-a", "account-a", listOf("")))
    }
}
