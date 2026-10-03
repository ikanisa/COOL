package app.cool.mobile.gateway

import org.json.JSONObject
import java.time.Instant

internal fun validateGatewayResult(action: String, id: String, deviceId: String, payload: JSONObject, result: JSONObject) {
        when (action) {
            "heartbeat" -> {
                requireKeys(result, setOf("observation_id", "ingested_at", "replay", "carrier_proof"))
                requireUuid(result, "observation_id")
                strictTimestamp(result, "ingested_at")
                strictBoolean(result, "replay")
                if (strictBoolean(result, "carrier_proof")) throw GatewayStateException("gateway_response_invalid")
            }
            "callback" -> {
                requireKeys(result, setOf("callback_id", "recorded_at", "replay", "carrier_proof"))
                if (requireUuid(result, "callback_id") != requireUuid(payload, "callback_id") || strictBoolean(result, "carrier_proof")) {
                    throw GatewayStateException("gateway_response_invalid")
                }
                strictTimestamp(result, "recorded_at")
                strictBoolean(result, "replay")
            }
            "dispatch_grant" -> {
                requireKeys(result, setOf("ok", "code", "device_id", "request_id", "replay"))
                if (strictBoolean(result, "ok") || strictString(result, "code") != "GATEWAY_DISPATCH_AUTHORITY_PENDING" ||
                    strictString(result, "device_id") != deviceId || requireUuid(result, "request_id") != id) {
                    throw GatewayStateException("gateway_response_invalid")
                }
                strictBoolean(result, "replay")
            }
            "reconcile" -> {
                requireKeys(result, setOf("target_request_id", "outcome", "recorded_action", "recorded_result"))
                if (requireUuid(result, "target_request_id") != requireUuid(payload, "target_request_id")) throw GatewayStateException("gateway_response_invalid")
                when (strictString(result, "outcome")) {
                    "unknown" -> if (!result.isNull("recorded_action") || !result.isNull("recorded_result")) throw GatewayStateException("gateway_response_invalid")
                    "recorded" -> if (strictString(result, "recorded_action") !in setOf("heartbeat", "callback", "dispatch_grant") || result.get("recorded_result") !is JSONObject) throw GatewayStateException("gateway_response_invalid")
                    else -> throw GatewayStateException("gateway_response_invalid")
                }
            }
            else -> throw GatewayStateException("gateway_response_invalid")
        }
    }

internal fun requireKeys(value: JSONObject, names: Set<String>) {
    if (value.keys().asSequence().toSet() != names) throw GatewayStateException("gateway_response_invalid")
}
internal fun strictString(value: JSONObject, name: String): String = value.get(name) as? String
    ?: throw GatewayStateException("gateway_response_invalid")
internal fun strictBoolean(value: JSONObject, name: String): Boolean = value.get(name) as? Boolean
    ?: throw GatewayStateException("gateway_response_invalid")
internal fun strictInteger(value: JSONObject, name: String): Long = when (val number = value.get(name)) {
    is Int -> number.toLong()
    is Long -> number
    else -> throw GatewayStateException("gateway_response_invalid")
}
internal fun requireUuid(value: JSONObject, name: String): String = strictString(value, name).also {
    if (!validUuid(it)) throw GatewayStateException("gateway_response_invalid")
}
internal fun strictTimestamp(value: JSONObject, name: String): Instant = try {
    val raw = strictString(value, name)
    if (!raw.endsWith("Z") || raw.length > 40) throw IllegalArgumentException()
    Instant.parse(raw)
} catch (_: Exception) { throw GatewayStateException("gateway_response_invalid") }
