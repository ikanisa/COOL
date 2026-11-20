package rw.ikanisa.burimunsi.core

/** Device credentials are never UI state, a data-class string or an authority
 * decision. The server still checks the exact approved installation on sign-in. */
class InstallationGrant private constructor(val installationId:String,private val secret:String) {
    fun token():String=secret
    fun localRecord():String="burimunsi-local-grant-v1|$installationId|$secret"
    override fun toString()="InstallationGrant(redacted)"
    companion object {
        fun create(installationId:String,token:String):InstallationGrant {
            if(!InstallationEnrollment.validId(installationId)||!InstallationEnrollment.validToken(token))
                throw ContractFailure("invalid_installation_grant")
            return InstallationGrant(installationId,token)
        }
        fun read(installationId:String,record:String):InstallationGrant {
            if(record.length>160)throw ContractFailure("managed_setup_required")
            val parts=record.split('|')
            if(parts.size!=3||parts[0]!="burimunsi-local-grant-v1"||parts[1]!=installationId)
                throw ContractFailure("managed_setup_required")
            return create(installationId,parts[2])
        }
    }
}

enum class InstallationEnrollmentSource { MISSING,MANAGED,MANAGED_BLOCKED,LOCAL,LOCAL_BLOCKED,UNAVAILABLE }

/** Safe metadata only. Available means a credential can be read locally; it
 * never means that an account, installation or receiving scope is approved. */
data class InstallationEnrollmentState(val source:InstallationEnrollmentSource) {
    val available:Boolean get()=source==InstallationEnrollmentSource.MANAGED||source==InstallationEnrollmentSource.LOCAL
    val canSave:Boolean get()=source==InstallationEnrollmentSource.MISSING
    val canClearLocal:Boolean get()=source==InstallationEnrollmentSource.LOCAL||source==InstallationEnrollmentSource.LOCAL_BLOCKED
}

object InstallationEnrollment {
    private val id=Regex("[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
    private val token=Regex("[a-f0-9]{64}")
    fun validId(value:String)=id.matches(value)
    fun validToken(value:String)=token.matches(value)
    /** Presence, including an empty/wrong-type value, is managed policy. Never
     * downgrade a malformed managed grant to a previously saved local one. */
    fun resolve(installationId:String,idPresent:Boolean,managedId:String?,tokenPresent:Boolean,managedToken:String?,
        readLocal:()->String?):InstallationGrant? {
        if(!validId(installationId))throw ContractFailure("managed_setup_required")
        if(idPresent||tokenPresent){
            if(!idPresent||!tokenPresent||managedId!=installationId||managedToken==null)
                throw ContractFailure("managed_setup_required")
            return InstallationGrant.create(installationId,managedToken)
        }
        return readLocal()?.let{InstallationGrant.read(installationId,it)}
    }
    fun inspect(installationId:String,idPresent:Boolean,managedId:String?,tokenPresent:Boolean,managedToken:String?,
        readLocal:()->String?):InstallationEnrollmentState {
        if(!validId(installationId))return InstallationEnrollmentState(InstallationEnrollmentSource.UNAVAILABLE)
        val managed=idPresent||tokenPresent
        return try {
            val grant=resolve(installationId,idPresent,managedId,tokenPresent,managedToken,readLocal)
            InstallationEnrollmentState(if(managed)InstallationEnrollmentSource.MANAGED else
                if(grant==null)InstallationEnrollmentSource.MISSING else InstallationEnrollmentSource.LOCAL)
        } catch(_:Exception){InstallationEnrollmentState(if(managed)InstallationEnrollmentSource.MANAGED_BLOCKED else InstallationEnrollmentSource.LOCAL_BLOCKED)}
    }
    /** Editing is a signed-out local operation, never an authentication shortcut.
     * Cancel existing code entry first; late auth responses must be invalidated. */
    fun requireEditable(signedIn:Boolean,authInFlight:Boolean,code:CollectEmailCodeState) {
        if(signedIn||authInFlight||code.challenge!=null||code.verificationUnknown)
            throw ContractFailure("phone_setup_busy")
    }
}
