package rw.ikanisa.storagepolicy

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

/** This is NOT a legacy database parser. Each product must decode its real journal without
 * dropping pending operations, tombstones or faults, and independently inventory every
 * retained ledger/key/sidecar artifact. The storage lock must cover capture through commit. */
interface LegacyLifecycleReadPort {
    fun <T> frozen(block: () -> T): T
    fun capture(binding: Binding): LegacyLifecycleCapture
}
data class LegacyLifecycleCapture(val state: StorageState, val artifacts: List<ArchivedArtifact>)

/** Immutable exact plan. Original revision and content identities remain in the permanent
 * migration marker; the new journal starts at revision zero but does not reset semantics. */
class LegacyLifecycleMigration private constructor(
    val binding: Binding,
    val operationId: String,
    private val original: ByteArray,
    private val inventory: List<ArchivedArtifact>,
) {
    companion object {
        fun prepare(binding: Binding, operationId: String, capture: LegacyLifecycleCapture): LegacyLifecycleMigration {
            fun need(ok: Boolean, code: String) { if (!ok) throw StoragePolicyFailure(code) }
            val bytes = LifecycleSnapshotCodec.encode(capture.state)
            val s = LifecycleSnapshotCodec.decode(bytes)
            need(s.binding == binding, "migration_binding_mismatch")
            need(operationId.isNotBlank() && operationId.length <= 256 && operationId.none { it.isISOControl() }, "migration_invalid_operation")
            need(operationId !in s.usedOperations, "migration_operation_reused")
            val entries = capture.artifacts.map { it.copy() }.sortedBy { it.id }
            need(entries.size <= LifecycleSnapshotCodec.MAX_ITEMS, "migration_item_limit")
            need(entries.map { it.id }.distinct().size == entries.size, "migration_duplicate_artifact")
            need(entries.map { it.id }.toSet() == s.evidence, "migration_inventory_mismatch")
            need(entries.all { it.bytes >= 0 && it.sha256.matches(Regex("[0-9a-f]{64}")) }, "migration_invalid_content_identity")
            return LegacyLifecycleMigration(binding, operationId, bytes, entries).also {
                LifecycleSnapshotCodec.encode(it.initialState())
                if (it.marker().size > LifecycleSnapshotCodec.MAX_BYTES) throw StoragePolicyFailure("migration_marker_limit")
            }
        }
    }
    fun initialState(): StorageState {
        val state = LifecycleSnapshotCodec.decode(original)
        return state.copy(revision = 0, usedOperations = state.usedOperations + operationId).validated()
    }
    fun initialBytes() = LifecycleSnapshotCodec.encode(initialState())
    fun marker(): ByteArray {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            fun text(s: String) { val b = s.toByteArray(Charsets.UTF_8); out.writeInt(b.size); out.write(b) }
            out.writeInt(0x4d494731); out.writeInt(1); text(operationId)
            out.writeInt(original.size); out.write(original)
            out.writeInt(inventory.size)
            inventory.forEach { text(it.id); out.writeLong(it.bytes); text(it.sha256) }
        }
        return bytes.toByteArray()
    }
    fun verifyCurrent(capture: LegacyLifecycleCapture) {
        val now = prepare(binding, operationId, capture)
        if (!now.marker().contentEquals(marker())) throw StoragePolicyFailure("migration_source_changed")
    }
}
