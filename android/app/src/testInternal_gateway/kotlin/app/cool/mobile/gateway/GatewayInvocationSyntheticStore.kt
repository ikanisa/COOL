package app.cool.mobile.gateway

import org.json.JSONObject

/** Synthetic storage for pure-state fixtures; it makes no fsync/Keystore claim. */
internal class GatewayInvocationSyntheticStore : GatewayInvocationStorage {
    private val rows = HashMap<String, JSONObject>()
    override fun requireInvocationActive() = Unit
    override fun invocationRealm(deviceId: String) = JSONObject()
        .put("installation_id", "00000000-0000-0000-0000-000000000099")
        .put("key_sha256", "a".repeat(64)).put("signing_certificate_sha256", "b".repeat(64))
    override fun readInvocationRecord(kind: String, attemptId: String) = rows["$kind:$attemptId"]?.let { JSONObject(it.toString()) }
    override fun invocationRecordIndexed(kind: String, attemptId: String) = rows.containsKey("$kind:$attemptId")
    override fun publishInvocationRecord(kind: String, attemptId: String, value: JSONObject) {
        val key = "$kind:$attemptId"
        rows[key]?.let { if (!archiveJsonEqual(it, value)) throw GatewayStateException("gateway_archive_immutable") }
        rows[key] = JSONObject(value.toString())
    }
}
