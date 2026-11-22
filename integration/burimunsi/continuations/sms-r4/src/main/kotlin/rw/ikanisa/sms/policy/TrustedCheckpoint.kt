package rw.ikanisa.sms.policy

/** Trusted high-water mark, bound to a single store, key alias, owner, installation and generation. */
data class JournalAnchor(val contextHash: String, val sequence: Long, val ciphertextHash: String, val plaintextHash: String) {
    fun valid(): Boolean = sequence in 0..JournalFormat.MAX_RECORDS.toLong() &&
        listOf(contextHash,ciphertextHash,plaintextHash).all { it.matches(Regex("[a-f0-9]{64}")) }
}
sealed class Checkpoint {
    data class Committed(val anchor: JournalAnchor): Checkpoint()
    data class Prepared(val before: JournalAnchor, val after: JournalAnchor): Checkpoint()
    data object Missing: Checkpoint()
    data object Unavailable: Checkpoint()
}
object CheckpointRules {
    fun prepared(p: Checkpoint.Prepared): Boolean = p.before.valid() && p.after.valid() &&
        p.before.contextHash==p.after.contextHash && p.after.sequence==p.before.sequence+1 &&
        p.before.ciphertextHash!=p.after.ciphertextHash && p.before.plaintextHash!=p.after.plaintextHash
    fun follows(before: Checkpoint, after: Checkpoint): Boolean = when {
        before is Checkpoint.Committed && after is Checkpoint.Prepared -> prepared(after) && before.anchor==after.before
        before is Checkpoint.Prepared && after is Checkpoint.Committed -> prepared(before) && after.anchor==before.after
        else -> false
    }
}
/**
 * Must be independently rollback-resistant and authenticated. A sibling file/SharedPreferences or
 * another field in the same restorable database is NOT a trusted checkpoint. CAS must be linearizable
 * across all writers and durable before COMMITTED; enforce CheckpointRules on the trusted side.
 * Missing/unavailable checkpoints are never initialized/adopted by normal reads or appends.
 * Provision an empty store explicitly through a separate authorized lifecycle workflow.
 */
interface TrustedCheckpointPort {
    fun read(contextHash: String): Checkpoint
    fun compareAndSet(expected: Checkpoint, next: Checkpoint): StoreWrite
}
/**
 * Existing encrypted blob only. Atomically compare ALL old ciphertext bytes and durably replace
 * under an interprocess transaction. The replacement contains the complete retained journal, not
 * just its last snapshot. Never truncate/repair/adopt corrupt data. Preserve incomplete artifacts
 * for recovery. COMMITTED implies the native platform's durable write and directory barriers.
 */
interface CiphertextBlobPort {
    fun read(): JournalRead
    fun replace(expectedCiphertextHash: String, replacement: ByteArray): StoreWrite
}
