package app.cool.mobile.gateway

import android.content.Context
import app.cool.mobile.BuildConfig

/** Capability of the reviewed installed artifact, separate from backend send
 * authority. No preferences, caller argument, endpoint or key can set it. */
internal object GatewayNoticeArtifactAdmission {
    const val RESOURCE_NAME = "collect_gateway_receipt_notice_protocol_admitted"

    fun admitted(context: Context): Boolean {
        if (BuildConfig.FLAVOR != "internal_gateway") return false
        return try {
            val resources = context.resources
            val id = resources.getIdentifier(RESOURCE_NAME, "bool", context.packageName)
            id != 0 && resources.getResourceTypeName(id) == "bool" && resources.getBoolean(id)
        } catch (_: Exception) {
            false
        }
    }
}
