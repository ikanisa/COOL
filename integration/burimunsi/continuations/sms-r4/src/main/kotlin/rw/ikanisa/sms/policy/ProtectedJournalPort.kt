package rw.ikanisa.sms.policy

sealed class ProtectedInspection {
    class Ready internal constructor(val anchor: JournalAnchor, plaintext: ByteArray): ProtectedInspection() {
        private val bytes=plaintext.copyOf()
        fun copyPlaintext()=bytes.copyOf()
        override fun toString()="ProtectedJournalReady(sequence=${anchor.sequence})"
    }
    data class Blocked(val reason: String): ProtectedInspection()
}
/**
 * R3 append port over an AES-GCM encrypted complete journal and an independent trusted checkpoint.
 * Prepare checkpoint -> durable ciphertext CAS -> commit checkpoint. No send is released while any
 * result is unknown. Recovery can finalize the exact prepared ciphertext; it NEVER cancels a
 * preparation, adopts old bytes, emits an upload, regenerates keys or changes operation IDs.
 */
class ProtectedJournalPort(private val binding: StorageBinding, private val cipher: AesGcmJournalCipher,
    private val blobs: CiphertextBlobPort, private val checkpoints: TrustedCheckpointPort): AppendJournalPort {
    private fun checkpoint(): Checkpoint = try { checkpoints.read(binding.contextHash) } catch(_: Exception) { Checkpoint.Unavailable }
    private fun valid(anchor: JournalAnchor)=binding.valid() && anchor.valid() && anchor.contextHash==binding.contextHash
    private fun decode(anchor: JournalAnchor): ProtectedInspection {
        if(!valid(anchor)) return ProtectedInspection.Blocked("CHECKPOINT_INVALID")
        return try {
            val result=blobs.read()
            if(result !is JournalRead.Bytes) return ProtectedInspection.Blocked(
                if(result==JournalRead.Missing) "CIPHERTEXT_MISSING" else "CIPHERTEXT_UNAVAILABLE")
            val bytes=result.copy()
            if(EvidenceHash.sha256(bytes)!=anchor.ciphertextHash) return ProtectedInspection.Blocked("CIPHERTEXT_CHECKPOINT_MISMATCH")
            val plain=cipher.open(bytes,binding,anchor.sequence)
            try {
                if(EvidenceHash.sha256(plain)!=anchor.plaintextHash) return ProtectedInspection.Blocked("PLAINTEXT_CHECKPOINT_MISMATCH")
                val state=JournalFormat.replay(plain,binding.scope)
                if(state.recordCount.toLong()!=anchor.sequence) return ProtectedInspection.Blocked("RECORD_COUNT_MISMATCH")
                ProtectedInspection.Ready(anchor,plain)
            } finally { plain.fill(0) }
        } catch(e: SecureStorageException) { ProtectedInspection.Blocked(e.code.name) }
          catch(e: SnapshotFormatException) { ProtectedInspection.Blocked("JOURNAL_${e.code.name}") }
          catch(_: Exception) { ProtectedInspection.Blocked("STORAGE_UNAVAILABLE") }
    }
    fun inspect(): ProtectedInspection {
        if(!binding.valid()) return ProtectedInspection.Blocked("BINDING_INVALID")
        val cp=checkpoint()
        if(cp !is Checkpoint.Committed) return ProtectedInspection.Blocked(when(cp) {
            Checkpoint.Missing -> "CHECKPOINT_MISSING"
            Checkpoint.Unavailable -> "CHECKPOINT_UNAVAILABLE"
            is Checkpoint.Prepared -> if(CheckpointRules.prepared(cp) && valid(cp.before)) "CHECKPOINT_PENDING" else "CHECKPOINT_INVALID"
            else -> "CHECKPOINT_INVALID"
        })
        val inspected=decode(cp.anchor)
        // Reject an observation that raced with a prepare/finalize in another process.
        if(inspected is ProtectedInspection.Ready && checkpoint()!=cp) return ProtectedInspection.Blocked("CHECKPOINT_CHANGED")
        return inspected
    }
    override fun read(): JournalRead = when(val r=inspect()) {
        is ProtectedInspection.Ready -> JournalRead.Bytes(r.copyPlaintext())
        is ProtectedInspection.Blocked -> JournalRead.Unavailable
    }
    private fun cas(before: Checkpoint, after: Checkpoint): StoreWrite {
        if(!CheckpointRules.follows(before,after)) return StoreWrite.NOT_COMMITTED
        return try { checkpoints.compareAndSet(before,after) } catch(_: Exception) { StoreWrite.UNKNOWN }
    }
    override fun append(expectedContentHash: String, record: ByteArray): StoreWrite {
        val read=inspect() as? ProtectedInspection.Ready ?: return StoreWrite.NOT_COMMITTED
        if(read.anchor.plaintextHash!=expectedContentHash) return StoreWrite.REVISION_CONFLICT
        val plain=read.copyPlaintext()
        if(record.isEmpty() || record.size>JournalFormat.MAX_BYTES-plain.size) { plain.fill(0); return StoreWrite.NOT_COMMITTED }
        val next=plain+record.copyOf(); plain.fill(0)
        val sealed: ByteArray
        val anchor: JournalAnchor
        try {
            val state=JournalFormat.replay(next,binding.scope)
            if(state.recordCount.toLong()!=read.anchor.sequence+1) return StoreWrite.NOT_COMMITTED
            sealed=cipher.seal(next,binding,state.recordCount.toLong())
            anchor=JournalAnchor(binding.contextHash,state.recordCount.toLong(),EvidenceHash.sha256(sealed),state.contentHash)
        } catch(_: Exception) { return StoreWrite.NOT_COMMITTED }
        finally { next.fill(0) }
        val prepared=Checkpoint.Prepared(read.anchor,anchor)
        val prepare=cas(Checkpoint.Committed(read.anchor),prepared)
        if(prepare!=StoreWrite.COMMITTED) return prepare
        val write=try { blobs.replace(read.anchor.ciphertextHash,sealed) } catch(_: Exception) { StoreWrite.UNKNOWN }
        // The checkpoint may already have changed. Never undo it even if disk reports no write.
        if(write!=StoreWrite.COMMITTED) return StoreWrite.UNKNOWN
        return if(cas(prepared,Checkpoint.Committed(anchor))==StoreWrite.COMMITTED) StoreWrite.COMMITTED else StoreWrite.UNKNOWN
    }
    /** Explicit, idempotent local recovery step; no queue/network effect is returned. */
    fun recoverPrepared(): String {
        if(!binding.valid()) return "BINDING_INVALID"
        val p=checkpoint()
        if(p is Checkpoint.Committed) return if(inspect() is ProtectedInspection.Ready) "ALREADY_COMMITTED" else "RECOVERY_BLOCKED"
        if(p !is Checkpoint.Prepared || !CheckpointRules.prepared(p) || !valid(p.before)) return "RECOVERY_BLOCKED"
        val decoded=decode(p.after)
        if(decoded !is ProtectedInspection.Ready) return "RECOVERY_BLOCKED"
        return when(cas(p,Checkpoint.Committed(p.after))) {
            StoreWrite.COMMITTED -> "RECOVERED"
            StoreWrite.UNKNOWN -> "RECOVERY_OUTCOME_UNKNOWN"
            else -> "RECOVERY_BLOCKED"
        }
    }
}
