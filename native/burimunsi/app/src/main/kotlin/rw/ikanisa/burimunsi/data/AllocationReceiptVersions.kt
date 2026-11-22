package rw.ikanisa.burimunsi.data

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.AllocationReadback
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.storage.SecureStore

/** One minimum version per locally confirmed allocation receipt, independent of session and cache eviction. */
internal class AllocationReceiptVersions(private val context: Context) {
    private fun store(actor: String, group: String, payment: String): SecureStore {
        val scope = listOf(actor, group, payment).joinToString("/") { Values.id(it) }
        return SecureStore(context, "allocation-readback-" + Values.sha256(scope))
    }

    private fun retainedVersion(record: SecureStore): Long? = record.read()?.let { raw ->
        val value = JSONObject(raw)
        Values.requestId(value.getString("requestId"))
        value.counter("fromVersion")
    }

    // The repository holds its process-wide authority through this read and journal preparation or publication.
    fun requireNewer(actor: String, group: String, payment: String, version: Long) {
        val consumed = retainedVersion(store(actor, group, payment)) ?: return
        if (version <= consumed) throw ApiFailure("record_unavailable", 409)
    }

    fun retain(actor: String, group: String, requestId: String, allocation: AllocationReadback) {
        val record = store(actor, group, allocation.paymentId)
        val previous = retainedVersion(record)
        if (previous != null && previous >= allocation.fromVersion) return
        val value = JSONObject().put("requestId", Values.requestId(requestId))
            .put("fromVersion", allocation.fromVersion).toString()
        record.write(value)
        checkContract(record.read() == value, "operation_store_unavailable")
    }
}
