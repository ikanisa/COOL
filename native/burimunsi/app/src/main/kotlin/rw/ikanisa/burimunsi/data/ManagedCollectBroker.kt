package rw.ikanisa.burimunsi.data

import android.content.Context
import app.cool.mobile.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.DeviceProvisioning
import rw.ikanisa.burimunsi.gateway.GatewayFactory

data class ManagedLoginStatus(val signedIn:Boolean=false,val issue:String?=null,val emailCode:CollectEmailCodeState=CollectEmailCodeState(),
    val collectionId:String?=null,val enrollment:InstallationEnrollmentState=InstallationEnrollmentState(InstallationEnrollmentSource.UNAVAILABLE),
    val authInFlight:Boolean=false)

/** Application-owned, process-memory-only login. Receiver capture/queue custody
 * is independent and never receives the BFF cookie, email code or access token.
 */
class ManagedCollectBroker(context:Context):ManagedSessionTokenProvider {
    val configured=BuildConfig.BURI_ADMIN_ORIGIN.isNotBlank()&&BuildConfig.BURI_API_ORIGIN.isNotBlank()&&BuildConfig.BURI_AUTH_ORIGIN.isNotBlank()
    private val transitions=Any()
    @Volatile private var authInFlight=false
    private val installation=lazy{DeviceProvisioning(context,GatewayFactory.installationId(context))}
    private fun enrollment()=try{installation.value.status()}catch(_:Exception){InstallationEnrollmentState(InstallationEnrollmentSource.UNAVAILABLE)}
    private val mutableStatus=MutableStateFlow(ManagedLoginStatus(enrollment=enrollment()))
    val status=mutableStatus.asStateFlow()
    private val state=lazy{
        if(!configured)throw ManagedCollectFailure("configuration_required")
        val installation=installation.value
        val profile=if(BuildConfig.IS_GATEWAY)"internal_receiver" else "staff"
        ManagedCollectSession(CollectAdminTransport(BuildConfig.BURI_ADMIN_ORIGIN,BuildConfig.BURI_AUTH_ORIGIN,
            installation.installationId,profile,installation::token,nativeApiOrigin=BuildConfig.BURI_API_ORIGIN),installation.installationId,profile,installation::token)
    }
    private fun publish(issue:String?=null){mutableStatus.value=ManagedLoginStatus(state.isInitialized()&&state.value.signedIn,issue,
        if(state.isInitialized())state.value.emailCodeState else CollectEmailCodeState(),currentCollectionId(),enrollment(),authInFlight)}
    private fun auth(operation:()->Unit){
        synchronized(transitions){if(authInFlight)throw ManagedCollectFailure("phone_setup_busy",409);authInFlight=true}
        publish(mutableStatus.value.issue)
        try{operation();publish()}catch(e:Exception){publish((e as? ManagedCollectFailure)?.code?:"managed_sign_in_unavailable");throw e}
        finally{synchronized(transitions){authInFlight=false};publish(mutableStatus.value.issue)}
    }
    fun requestEmailCode(email:String)=auth{state.value.requestEmailCode(email)}
    fun verifyEmailCode(code:String)=auth{state.value.verifyEmailCode(code)}
    /** Local credential edits are serialized against authentication. They never
     * manufacture a session or touch the independently retained SMS/journal realm. */
    private fun editEnrollment(operation:(DeviceProvisioning)->Unit)=synchronized(transitions){
        try{
            InstallationEnrollment.requireEditable(state.isInitialized()&&state.value.signedIn,authInFlight,
                if(state.isInitialized())state.value.emailCodeState else CollectEmailCodeState())
            // Invalidate any earlier generation before changing a token supplier.
            if(state.isInitialized())state.value.cancelEmailCode()
            operation(installation.value);publish()
        }catch(e:Exception){publish((e as? ContractFailure)?.code?:"phone_setup_unavailable");throw e}
    }
    fun savePhoneSetup(token:String)=editEnrollment{it.saveLocalToken(token)}
    fun clearPhoneSetup()=editEnrollment{it.clearLocalToken()}
    fun refreshPhoneSetup(){publish(mutableStatus.value.issue)}
    override fun currentAccessToken():String?=currentAccessContext()?.token
    override fun currentCollectionId():String?=if(state.isInitialized())state.value.currentCollectionId else null
    override fun currentAccessContext():ManagedRequestAccess?=try{
        val access=state.value.currentAccess();ManagedRequestAccess(access.token,access.collectionId).also{publish()}
    }catch(e:Exception){publish((e as? ManagedCollectFailure)?.code?:"managed_sign_in_unavailable");throw e}
    fun onBackground(){if(state.isInitialized())state.value.onBackground()}
    fun cancelEmailCode(){if(state.isInitialized())state.value.cancelEmailCode();publish()}
    fun signOut()=auth{try{if(state.isInitialized())state.value.signOut()}catch(_:Exception){throw ManagedCollectFailure("managed_sign_out_unconfirmed")}}
}
