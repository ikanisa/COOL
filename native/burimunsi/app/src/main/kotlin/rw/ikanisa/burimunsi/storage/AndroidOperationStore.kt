package rw.ikanisa.burimunsi.storage

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*

/** Persistence adapter only. Terminal evidence is saved, not erased as a side effect.
 * Tests use a SecureStore double; Android durability remains separately qualified. */
class AndroidOperationStore(context: Context) : OperationStore {
    companion object { private val processLock = Any() }
    override val coordinationLock: Any get() = processLock
    private val secure = SecureStore(context, "pending-command")
    override fun load(): PendingOperation? = synchronized(coordinationLock) { secure.read()?.let {
        val j = JSONObject(it)
        val required = setOf("requestId", "sessionScope", "kind", "body", "bodySha256", "state")
        val fields = j.keys().asSequence().toSet()
        val ownerFields = setOf("ownerAccountId", "groupId")
        checkContract(fields - setOf("attemptCount") - ownerFields == required &&
            (fields.intersect(ownerFields).isEmpty() || fields.containsAll(ownerFields)), "corrupt_operation")
        fun text(key: String): String {
            val value = j.get(key)
            checkContract(value is String, "corrupt_operation")
            return value as String
        }
        val attempts = if (j.has("attemptCount")) {
            val n = j.get("attemptCount")
            checkContract((n is Int || n is Long) && (n as Number).toLong() in 0..Int.MAX_VALUE.toLong(), "corrupt_operation")
            (n as Number).toInt()
        } else 0 // Legacy SENT/UNKNOWN with zero attempts remains unsendable.
        val state = try { OperationState.valueOf(text("state")) }
            catch (_: IllegalArgumentException) { throw ContractFailure("corrupt_operation") }
        val op = PendingOperation(text("requestId"), text("sessionScope"), text("kind"),
            text("body"), text("bodySha256"), state, attempts,
            if(j.has("ownerAccountId")) text("ownerAccountId").takeIf { it.isNotBlank() } else null,
            if(j.has("groupId")) text("groupId").takeIf { it.isNotBlank() } else null)
        Values.requestId(op.requestId)
        checkContract(Regex("[a-f0-9]{64}").matches(op.sessionScope) && op.kind.isNotBlank() &&
            op.bodySha256 == Values.sha256(op.body) &&
            ((op.ownerAccountId == null && op.groupId == null) ||
                (!op.ownerAccountId.isNullOrBlank() && !op.groupId.isNullOrBlank())), "corrupt_operation")
        op
    } }
    override fun save(value: PendingOperation) = synchronized(coordinationLock) {
        secure.write(JSONObject().put("requestId",value.requestId).put("sessionScope",value.sessionScope)
            .put("kind",value.kind).put("body",value.body).put("bodySha256",value.bodySha256)
            .put("state",value.state.name).put("attemptCount",value.attemptCount)
            .put("ownerAccountId",value.ownerAccountId?:"").put("groupId",value.groupId?:"").toString())
        checkContract(load() == value, "operation_store_unavailable")
    }
    override fun clear() = synchronized(coordinationLock) {
        secure.clear()
        checkContract(secure.read()==null, "operation_store_unavailable")
    }
}
