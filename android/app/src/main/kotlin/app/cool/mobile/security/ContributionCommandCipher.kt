package app.cool.mobile.security

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Custody only. A retained command is never payment or launch authorization. */
data class ContributionCommandSnapshot(val partitionId: String, val revision: Long, val payload: String?) {
    init {
        ContributionCommandCipher.validatePartition(partitionId)
        require(revision in 0..ContributionCommandCipher.MAX_REVISION)
        if (revision == 0L) require(payload == null) else ContributionCommandCipher.payloadBytes(requireNotNull(payload))
    }
    fun wire(): Map<String, Any?> = mapOf("schema_version" to 1, "partition_id" to partitionId,
        "revision" to revision, "payload" to payload)
}

class ContributionCommandCipher(private val key: (Boolean) -> SecretKey) {
    fun encrypt(snapshot: ContributionCommandSnapshot): ByteArray {
        require(snapshot.revision > 0)
        val payload = payloadBytes(requireNotNull(snapshot.payload))
        val plaintext = ByteBuffer.allocate(8 + payload.size).putLong(snapshot.revision).put(payload).array()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true)); cipher.updateAAD(aad(snapshot.partitionId))
        return byteArrayOf(1) + cipher.iv + cipher.doFinal(plaintext)
    }
    fun decrypt(partition: String, encrypted: ByteArray): ContributionCommandSnapshot {
        require(encrypted.size in 38..MAX_CIPHERTEXT_BYTES && encrypted[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, encrypted.copyOfRange(1, 13)))
        cipher.updateAAD(aad(partition))
        val bytes = cipher.doFinal(encrypted.copyOfRange(13, encrypted.size))
        require(bytes.size in 9..(8 + MAX_PAYLOAD_BYTES))
        val buffer = ByteBuffer.wrap(bytes); val revision = buffer.long
        val payload = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(buffer).toString()
        return ContributionCommandSnapshot(partition, revision, payload).also { require(it.revision > 0) }
    }
    private fun aad(partition: String): ByteArray {
        validatePartition(partition)
        return ("collect.contribution-commands.v1\u0000" + partition).toByteArray(Charsets.US_ASCII)
    }
    companion object {
        const val MAX_REVISION = 9007199254740991L
        const val MAX_PAYLOAD_BYTES = 1024 * 1024
        const val MAX_CIPHERTEXT_BYTES = MAX_PAYLOAD_BYTES + 37
        const val MAX_PARTITIONS = 64
        const val MAX_AGGREGATE_BYTES = 16L * 1024 * 1024
        fun validatePartition(value: String) { require(Regex("^[0-9a-f]{64}$").matches(value)) }
        fun payloadBytes(value: String): ByteArray {
            val buffer = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).encode(java.nio.CharBuffer.wrap(value))
            require(buffer.remaining() in 1..MAX_PAYLOAD_BYTES)
            return ByteArray(buffer.remaining()).also { buffer.get(it) }
        }
    }
}

internal interface ContributionCommandCustody {
    fun <T> exclusive(block: () -> T): T
    fun load(partition: String): ContributionCommandSnapshot
    fun persist(snapshot: ContributionCommandSnapshot)
}

/** One acknowledged CAS winner; no retries, deletes, empty fallback or eviction. */
internal class ContributionCommandJournal(private val custody: ContributionCommandCustody) {
    fun read(partition: String): Map<String, Any?> {
        ContributionCommandCipher.validatePartition(partition)
        return custody.exclusive { checkedLoad(partition).wire() }
    }
    fun compareAndSet(partition: String, expected: Long, payload: String): Map<String, Any?> {
        ContributionCommandCipher.validatePartition(partition)
        require(expected in 0 until ContributionCommandCipher.MAX_REVISION)
        ContributionCommandCipher.payloadBytes(payload)
        return custody.exclusive {
            val current = checkedLoad(partition)
            if (current.revision != expected) current.wire() + ("committed" to false)
            else {
                val proposed = ContributionCommandSnapshot(partition, expected + 1, payload)
                custody.persist(proposed)
                check(checkedLoad(partition) == proposed) { "Contribution recovery commit unavailable" }
                proposed.wire() + ("committed" to true)
            }
        }
    }
    private fun checkedLoad(partition: String): ContributionCommandSnapshot = custody.load(partition).also {
        check(it.partitionId == partition) { "Contribution recovery identity unavailable" }
    }
}
