package app.cool.mobile.receiver_sms

import android.content.SharedPreferences
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptPreferenceCommitTest {
    @Test
    fun failedDiskCommitCannotAcknowledgeReceiptCustody() {
        val journal = PreferenceJournal(commitSucceeds = false)
        val acknowledged = journal.preferences.commitReceiptState {
            putBoolean("enabled", false)
            putString("owner", "member-a")
        }

        assertFalse(acknowledged)
        assertEquals(listOf("edit", "putBoolean", "putString", "commit"), journal.calls)
    }

    @Test
    fun successfulCommitAppliesTheCompleteMutationBeforeAcknowledging() {
        val journal = PreferenceJournal(commitSucceeds = true)
        val acknowledged = journal.preferences.commitReceiptState {
            putString("encrypted_queue", "ciphertext")
            remove("legacy_queue")
        }

        assertTrue(acknowledged)
        assertEquals(listOf("edit", "putString", "remove", "commit"), journal.calls)
    }

    @Test
    fun mutationFailureDoesNotCommitOrScheduleAnAsynchronousWrite() {
        val journal = PreferenceJournal(commitSucceeds = true)
        try {
            journal.preferences.commitReceiptState {
                putBoolean("enabled", true)
                throw IllegalStateException("Interrupted before complete owner binding")
            }
            throw AssertionError("Mutation failure must propagate")
        } catch (_: IllegalStateException) {
            assertEquals(listOf("edit", "putBoolean"), journal.calls)
        }
    }

    private class PreferenceJournal(private val commitSucceeds: Boolean) {
        val calls = mutableListOf<String>()
        private val editor = Proxy.newProxyInstance(
            SharedPreferences.Editor::class.java.classLoader,
            arrayOf(SharedPreferences.Editor::class.java),
        ) { proxy, method, _ ->
            calls.add(method.name)
            when (method.name) {
                "commit" -> commitSucceeds
                "putBoolean", "putString", "remove" -> proxy
                else -> throw AssertionError("Unexpected editor operation: ${method.name}")
            }
        } as SharedPreferences.Editor

        val preferences = Proxy.newProxyInstance(
            SharedPreferences::class.java.classLoader,
            arrayOf(SharedPreferences::class.java),
        ) { _, method, _ ->
            calls.add(method.name)
            when (method.name) {
                "edit" -> editor
                else -> throw AssertionError("Unexpected preferences operation: ${method.name}")
            }
        } as SharedPreferences
    }
}
