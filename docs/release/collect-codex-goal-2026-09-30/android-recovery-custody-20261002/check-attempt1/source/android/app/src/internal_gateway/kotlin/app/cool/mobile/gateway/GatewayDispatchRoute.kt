package app.cool.mobile.gateway

import org.json.JSONObject

/** Versioned evidence identity. Existing primary receipt bytes retain their meaning. */
internal sealed interface GatewayDispatchRoute {
    data object PrimaryV2 : GatewayDispatchRoute
    data class ReceiptSuccessorV1(
        val primaryReceiptId: String,
        val dispatchJobId: String,
        val approvalId: String,
    ) : GatewayDispatchRoute
}

internal fun validateDispatchRoute(route: GatewayDispatchRoute, jobId: String) {
    if (!validUuid(jobId)) throw GatewayStateException("gateway_route_invalid")
    when (route) {
        is GatewayDispatchRoute.PrimaryV2 -> Unit
        is GatewayDispatchRoute.ReceiptSuccessorV1 -> if (route.dispatchJobId != jobId || !validUuid(route.primaryReceiptId) || !validUuid(route.approvalId) ||
            route.primaryReceiptId == route.dispatchJobId) throw GatewayStateException("gateway_route_invalid")
    }
}

internal fun successorRouteJson(route: GatewayDispatchRoute): JSONObject {
    if (route !is GatewayDispatchRoute.ReceiptSuccessorV1) throw GatewayStateException("gateway_route_invalid")
    validateDispatchRoute(route, route.dispatchJobId)
    return JSONObject().put("route_version", 1).put("route_kind", "receipt_successor")
        .put("primary_receipt_id", route.primaryReceiptId).put("dispatch_job_id", route.dispatchJobId).put("approval_id", route.approvalId)
}

internal fun successorRouteFromJson(value: JSONObject): GatewayDispatchRoute.ReceiptSuccessorV1 {
    requireKeys(value, setOf("route_version", "route_kind", "primary_receipt_id", "dispatch_job_id", "approval_id"))
    if (strictInteger(value, "route_version") != 1L || strictString(value, "route_kind") != "receipt_successor") throw GatewayStateException("gateway_route_invalid")
    return GatewayDispatchRoute.ReceiptSuccessorV1(requireUuid(value, "primary_receipt_id"), requireUuid(value, "dispatch_job_id"),
        requireUuid(value, "approval_id")).also { validateDispatchRoute(it, it.dispatchJobId) }
}

/** Primary v2 digest is untouched. A successor receives a distinct domain and exact tuple. */
internal fun successorReservationDigest(record: GatewayAttempt, originalDigest: String): String {
    val route = record.dispatchRoute as? GatewayDispatchRoute.ReceiptSuccessorV1 ?: throw GatewayStateException("gateway_route_invalid")
    validateDispatchRoute(route, record.jobId)
    return sha256(listOf("collect-receipt-successor-reservation:v1", "1", "receipt_successor", route.primaryReceiptId,
        route.dispatchJobId, route.approvalId, originalDigest).joinToString("|"))
}
