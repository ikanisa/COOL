package app.cool.mobile.security

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.*
import org.junit.Test

class ContributionCommandJournalTest {
    private val a = "a".repeat(64)
    private val b = "b".repeat(64)
    private class Memory : ContributionCommandCustody {
        val values = mutableMapOf<String, ContributionCommandSnapshot>()
        var failBeforeWrite = false; var failAfterWrite = false
        override fun <T> exclusive(block: () -> T): T = synchronized(this) { block() }
        override fun load(partition: String) = values[partition] ?: ContributionCommandSnapshot(partition, 0, null)
        override fun persist(snapshot: ContributionCommandSnapshot) {
            check(!failBeforeWrite)
            values[snapshot.partitionId] = snapshot
            check(!failAfterWrite)
        }
    }
    private fun rejected(block: () -> Unit) {
        try { block(); fail("Expected failure") } catch (_: Exception) { }
    }
    @Test fun reconstructionConflictAndOtherOwnerRemainRetained() {
        val memory = Memory(); val journal = ContributionCommandJournal(memory)
        assertEquals(0L, journal.read(a)["revision"])
        assertEquals(true, journal.compareAndSet(a, 0, "original")["committed"])
        assertEquals(true, journal.compareAndSet(b, 0, "other owner")["committed"])
        val stale = ContributionCommandJournal(memory).compareAndSet(a, 0, "replacement")
        assertEquals(false, stale["committed"]); assertEquals("original", stale["payload"])
        assertEquals("other owner", journal.read(b)["payload"])
    }
    @Test fun concurrentClaimsAdmitOneWinnerAcrossJournalInstances() {
        val memory = Memory(); val ready = CountDownLatch(16); val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(16)
        try {
            val futures = (0 until 16).map { index -> executor.submit<Boolean> {
                ready.countDown(); start.await()
                ContributionCommandJournal(memory).compareAndSet(a, 0, "request-$index")["committed"] == true
            } }
            assertTrue(ready.await(3, java.util.concurrent.TimeUnit.SECONDS)); start.countDown()
            assertEquals(1, futures.count { it.get(3, java.util.concurrent.TimeUnit.SECONDS) })
            assertEquals(1L, memory.values[a]!!.revision)
        } finally { start.countDown(); executor.shutdownNow() }
    }
    @Test fun lostCommitAcknowledgementDoesNotBecomeASecondDispatchPermit() {
        val memory = Memory(); val journal = ContributionCommandJournal(memory)
        memory.failAfterWrite = true
        rejected { journal.compareAndSet(a, 0, "dispatchPossible") }
        memory.failAfterWrite = false
        assertEquals("dispatchPossible", ContributionCommandJournal(memory).read(a)["payload"])
        assertEquals(false, journal.compareAndSet(a, 0, "new request")["committed"])
    }
    @Test fun precommitFailureAndInvalidInputNeverEraseRetainedHistory() {
        val memory = Memory(); val journal = ContributionCommandJournal(memory)
        journal.compareAndSet(a, 0, "retained"); memory.failBeforeWrite = true
        rejected { journal.compareAndSet(a, 1, "changed") }
        rejected { journal.compareAndSet(a, -1, "changed") }
        rejected { journal.compareAndSet(a, ContributionCommandCipher.MAX_REVISION, "changed") }
        rejected { journal.compareAndSet(a, 1, "") }
        rejected { journal.compareAndSet(a, 1, "x".repeat(ContributionCommandCipher.MAX_PAYLOAD_BYTES + 1)) }
        assertEquals("retained", journal.read(a)["payload"])
    }
    @Test fun purposeAndPartitionCiphertextAreBoundAndTamperingRetainsInputBytes() {
        val secret = SecretKeySpec(ByteArray(32) { 74 }, "AES")
        val cipher = ContributionCommandCipher { secret }
        val original = ContributionCommandSnapshot(a, 1, "{\"phase\":\"dispatchPossible\"}")
        val encrypted = cipher.encrypt(original); val before = encrypted.clone()
        assertEquals(original, cipher.decrypt(a, encrypted))
        rejected { cipher.decrypt(b, encrypted) }
        assertArrayEquals(before, encrypted)
        encrypted[encrypted.lastIndex] = (encrypted.last().toInt() xor 1).toByte()
        rejected { cipher.decrypt(a, encrypted) }
        // Old snapshot-purpose ciphertext is not accepted even with the same controlled key.
        val old = SnapshotCipher { secret }.encrypt("d1000000-0000-4000-8000-000000000001", "private")
        rejected { cipher.decrypt(a, old) }
        val foreignPurpose = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        foreignPurpose.init(javax.crypto.Cipher.ENCRYPT_MODE, secret)
        foreignPurpose.updateAAD(("collect.payment-help.v1\u0000" + a).toByteArray(Charsets.UTF_8))
        val foreignBytes = byteArrayOf(1) + foreignPurpose.iv + foreignPurpose.doFinal(java.nio.ByteBuffer.allocate(9).putLong(1).put(120.toByte()).array())
        rejected { cipher.decrypt(a, foreignBytes) }
    }
    @Test fun strictUtf8RevisionAndPartitionBoundariesFailClosed() {
        rejected { ContributionCommandCipher.payloadBytes("\uD800") }
        rejected { ContributionCommandSnapshot(a.uppercase(), 1, "payload") }
        rejected { ContributionCommandSnapshot(a, 0, "payload") }
        rejected { ContributionCommandSnapshot(a, 1, null) }
        rejected { ContributionCommandSnapshot(a, ContributionCommandCipher.MAX_REVISION + 1, "payload") }
        val memory = Memory(); memory.values[a] = ContributionCommandSnapshot(a, ContributionCommandCipher.MAX_REVISION - 1, "before")
        assertEquals(ContributionCommandCipher.MAX_REVISION,
            ContributionCommandJournal(memory).compareAndSet(a, ContributionCommandCipher.MAX_REVISION - 1, "last")["revision"])
        rejected { ContributionCommandJournal(memory).compareAndSet(a, ContributionCommandCipher.MAX_REVISION, "overflow") }
    }
}
