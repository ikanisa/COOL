package app.cool.mobile.receiver_sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class MemberSmsWakeupScheduleTest {
    @Test fun periodicFailureDoesNotSuppressImmediateWakeup() {
        val calls = mutableListOf<String>()
        val failure = IllegalStateException("periodic registration failed")
        val result = try {
            scheduleMemberSmsWakeups(
                { calls.add("periodic"); throw failure },
                { calls.add("immediate") },
            )
            null
        } catch (error: Exception) { error }
        assertSame(failure, result)
        assertEquals(listOf("periodic", "immediate"), calls)
    }

    @Test fun bothWakeupsAreAttemptedWhenRegistrationSucceeds() {
        val calls = mutableListOf<String>()
        scheduleMemberSmsWakeups({ calls.add("periodic") }, { calls.add("immediate") })
        assertEquals(listOf("periodic", "immediate"), calls)
    }

    @Test fun immediateFailureIsStillReported() {
        val calls = mutableListOf<String>()
        val failure = IllegalStateException("immediate scheduling failed")
        val result = try {
            scheduleMemberSmsWakeups(
                { calls.add("periodic") },
                { calls.add("immediate"); throw failure },
            )
            null
        } catch (error: Exception) { error }
        assertSame(failure, result)
        assertEquals(listOf("periodic", "immediate"), calls)
    }
}
