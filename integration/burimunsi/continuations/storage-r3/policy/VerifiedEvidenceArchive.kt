package rw.ikanisa.storagepolicy

/** Content identities supplement the reducer's opaque artifact inventory. These are
 * ciphertext bytes; the verifier neither decrypts nor claims recoverability of lost keys. */
data class ArchivedArtifact(val id: String, val bytes: Long, val sha256: String)
data class EvidenceArchiveManifest(val binding: Binding, val receiptId: String, val artifacts: List<ArchivedArtifact>)
interface EvidenceArchiveReadPort {
    /** Independently hash the retained, immutable archive bytes. Return null only for
     * verified absence; throw on unreadability. Do not use metadata-only cached claims. */
    fun inspect(binding: Binding, receiptId: String, artifactId: String): ArchivedArtifact?
}
class VerifiedEvidenceArchive private constructor(val proof: ArchiveProof) {
    companion object {
        /** The expected content manifest must have been captured from the original evidence
         * under its storage lock. This verifies a copy, not the manifest's authenticity.
         * The archive must remain immutable/pinned for as long as the proof is retained. */
        fun verify(expected: EvidenceArchiveManifest, required: StorageState, archive: EvidenceArchiveReadPort): VerifiedEvidenceArchive {
            required.validated()
            fun need(ok: Boolean, code: String) { if (!ok) throw StoragePolicyFailure(code) }
            need(expected.binding == required.binding, "archive_binding_mismatch")
            need(expected.receiptId.isNotBlank() && expected.receiptId.length <= 256 && expected.receiptId.none { it.isISOControl() }, "archive_invalid_receipt")
            need(expected.artifacts.size <= LifecycleSnapshotCodec.MAX_ITEMS, "archive_item_limit")
            need(expected.artifacts.map { it.id }.distinct().size == expected.artifacts.size, "archive_duplicate_artifact")
            need(expected.artifacts.map { it.id }.toSet() == required.evidence, "archive_inventory_mismatch")
            for (entry in expected.artifacts) {
                need(entry.bytes >= 0 && entry.sha256.matches(Regex("[0-9a-f]{64}")), "archive_invalid_content_identity")
                need(archive.inspect(expected.binding, expected.receiptId, entry.id) == entry, "archive_content_mismatch")
            }
            return VerifiedEvidenceArchive(ArchiveProof(expected.binding, required.evidence.toSet(), expected.receiptId))
        }
    }
}
