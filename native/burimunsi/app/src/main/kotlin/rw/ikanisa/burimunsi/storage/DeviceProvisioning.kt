package rw.ikanisa.burimunsi.storage

import android.content.Context
import android.content.RestrictionsManager
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.InstallationEnrollment
import rw.ikanisa.burimunsi.core.InstallationEnrollmentState
import rw.ikanisa.burimunsi.core.InstallationEnrollmentSource
import rw.ikanisa.burimunsi.core.InstallationGrant
import java.util.UUID

/** Owner-issued enrollment, not public registration or SMS verification.
 * Managed policy wins. The local fallback uses the same server-issued grant and
 * fixed installation ID; it never changes an account, SIM, binding or queue.
 */
class DeviceProvisioning(context: Context, suppliedInstallationId: String? = null) {
    companion object {private val identityLock=Any();private val registrationLock=Any()}
    private val secure = SecureStore(context, "installation")
    private val local = SecureStore(context, "installation-grant")
    private val registration = SecureStore(context, "installation-registration")
    val installationId: String = suppliedInstallationId ?: synchronized(identityLock){secure.read() ?: UUID.randomUUID().toString().also(secure::write)}
    /** A random installation proposal, not an account or SMS permission. The
     * server registers it only after verifying the existing account's PIN.
     * Retaining the proposal before dispatch also permits an uncertain login
     * response to be reconciled without silently replacing the installation. */
    fun registrationToken():String = synchronized(registrationLock) {
        registration.read()?.let {
            if(!Regex("[a-f0-9]{64}").matches(it))throw ContractFailure("installation_credential_unavailable")
            return@synchronized it
        }
        // Preserve a previously approved installation secret during an upgrade.
        // It remains only a candidate: the server still requires valid current
        // account credentials and refuses revoked/colliding grants.
        val previous=runCatching{token()}.getOrNull()?.takeIf{Regex("[a-f0-9]{64}").matches(it)}
        val token=previous?:ByteArray(32).also(java.security.SecureRandom()::nextBytes)
            .joinToString(""){ "%02x".format(it.toInt() and 255) }
        registration.write(token)
        if(registration.read()!=token)throw ContractFailure("installation_credential_unavailable")
        token
    }
    private val restrictions = context.getSystemService(RestrictionsManager::class.java)
    private fun values()=restrictions?.applicationRestrictions?:throw ContractFailure("managed_setup_required")
    @Suppress("DEPRECATION")
    fun status():InstallationEnrollmentState=try {
        val values=values()
        InstallationEnrollment.inspect(installationId,values.containsKey("burimunsi_installation_id"),values.get("burimunsi_installation_id") as? String,
            values.containsKey("burimunsi_installation_token"),values.get("burimunsi_installation_token") as? String,local::read)
    }catch(_:Exception){InstallationEnrollmentState(InstallationEnrollmentSource.UNAVAILABLE)}
    @Suppress("DEPRECATION")
    fun token(): String {
        val values=values()
        return InstallationEnrollment.resolve(installationId,values.containsKey("burimunsi_installation_id"),values.get("burimunsi_installation_id") as? String,
            values.containsKey("burimunsi_installation_token"),values.get("burimunsi_installation_token") as? String,local::read)
            ?.token()?:throw ContractFailure("managed_setup_required")
    }
    fun saveLocalToken(token:String) {
        if(!status().canSave)throw ContractFailure("managed_setup_required")
        val grant=InstallationGrant.create(installationId,token)
        local.write(grant.localRecord())
        if(status().source!=InstallationEnrollmentSource.LOCAL||this.token()!=token)
            throw ContractFailure("managed_setup_required")
    }
    fun clearLocalToken() {
        if(!status().canClearLocal)throw ContractFailure("managed_setup_required")
        // SecureStore.clear deletes only this credential file. Its shared
        // Keystore alias, installation identity and all other stores survive.
        local.clear()
        if(status().source!=InstallationEnrollmentSource.MISSING)throw ContractFailure("managed_setup_required")
    }
}
