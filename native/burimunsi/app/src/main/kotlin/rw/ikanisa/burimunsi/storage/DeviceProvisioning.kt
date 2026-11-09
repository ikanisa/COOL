package rw.ikanisa.burimunsi.storage

import android.content.Context
import android.content.RestrictionsManager
import rw.ikanisa.burimunsi.core.ContractFailure
import java.util.UUID

/** Managed enrollment is out-of-band, not public registration or SMS verification.
 * An MDM token is accepted only for this locally generated installation identity.
 */
class DeviceProvisioning(context: Context, suppliedInstallationId: String? = null) {
    private val secure = SecureStore(context, "installation")
    val installationId: String = suppliedInstallationId ?: secure.read() ?: UUID.randomUUID().toString().also(secure::write)
    private val restrictions = context.getSystemService(RestrictionsManager::class.java)
    fun token(): String {
        val values = restrictions?.applicationRestrictions ?: throw ContractFailure("managed_setup_required")
        val acceptedId = values.getString("burimunsi_installation_id")
        val token = values.getString("burimunsi_installation_token").orEmpty()
        if (acceptedId != installationId || !Regex("[a-f0-9]{64}").matches(token)) throw ContractFailure("managed_setup_required")
        return token
    }
}
