package app.cool.mobile.gateway

import org.json.JSONObject

internal object GatewayInstalledEnrollment {
    private fun hash(value: JSONObject, name: String): String = strictString(value, name).also {
        if (!it.matches(Regex("[0-9a-f]{64}"))) throw GatewayStateException("gateway_enrollment_invalid")
    }
    fun verify(metadata: JSONObject?, enrollment: JSONObject?, keySha256: String, publicKeyBase64: String, certificateSha256: String): String {
        val local = metadata ?: throw GatewayStateException("gateway_not_enrolled")
        val installed = enrollment ?: throw GatewayStateException("gateway_not_enrolled")
        requireKeys(local, setOf("contract_version", "installation_id", "key_sha256", "signing_certificate_sha256", "public_key_spki_base64"))
        requireKeys(installed, setOf("contract_version", "device_id", "installation_id", "key_sha256", "signing_certificate_sha256"))
        if (strictInteger(local, "contract_version") != 1L || strictInteger(installed, "contract_version") != 1L ||
            requireUuid(local, "installation_id") != requireUuid(installed, "installation_id") ||
            hash(local, "key_sha256") != keySha256 || hash(installed, "key_sha256") != keySha256 ||
            hash(local, "signing_certificate_sha256") != certificateSha256 ||
            hash(installed, "signing_certificate_sha256") != certificateSha256 ||
            strictString(local, "public_key_spki_base64") != publicKeyBase64) throw GatewayStateException("gateway_enrollment_invalid")
        return requireUuid(installed, "device_id")
    }
}
