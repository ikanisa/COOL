package rw.ikanisa.burimunsi.data

import android.content.Context
import app.cool.mobile.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import rw.ikanisa.burimunsi.core.ManagedCollectSession
import rw.ikanisa.burimunsi.core.ManagedCollectFailure
import rw.ikanisa.burimunsi.core.CollectEmailCodeState
import rw.ikanisa.burimunsi.storage.DeviceProvisioning
import rw.ikanisa.burimunsi.gateway.GatewayFactory

data class ManagedLoginStatus(val signedIn:Boolean=false,val issue:String?=null,val emailCode:CollectEmailCodeState=CollectEmailCodeState())

/** Application-owned, process-memory-only login. Receiver capture/queue custody
 * is independent and never receives the BFF cookie, email code or access token.
 */
class ManagedCollectBroker(context:Context):ManagedSessionTokenProvider {
    val configured=BuildConfig.BURI_ADMIN_ORIGIN.isNotBlank()&&BuildConfig.BURI_API_ORIGIN.isNotBlank()&&BuildConfig.BURI_GROUP_ID.isNotBlank()
    private val mutableStatus=MutableStateFlow(ManagedLoginStatus())
    val status=mutableStatus.asStateFlow()
    private val state=lazy{
        if(!configured)throw ManagedCollectFailure("configuration_required")
        val installation=DeviceProvisioning(context,GatewayFactory.installationId(context))
        ManagedCollectSession(CollectAdminTransport(BuildConfig.BURI_ADMIN_ORIGIN,BuildConfig.BURI_API_ORIGIN),installation.installationId,
            BuildConfig.BURI_GROUP_ID,if(BuildConfig.IS_GATEWAY)"internal_receiver" else "staff",installation::token)
    }
    private fun publish(issue:String?=null){mutableStatus.value=ManagedLoginStatus(state.isInitialized()&&state.value.signedIn,issue,
        if(state.isInitialized())state.value.emailCodeState else CollectEmailCodeState())}
    fun requestEmailCode(email:String){try{state.value.requestEmailCode(email);publish()}catch(e:Exception){publish((e as? ManagedCollectFailure)?.code?:"managed_sign_in_unavailable");throw e}}
    fun verifyEmailCode(code:String){try{state.value.verifyEmailCode(code);publish()}catch(e:Exception){publish((e as? ManagedCollectFailure)?.code?:"managed_sign_in_unavailable");throw e}}
    override fun currentAccessToken():String?=try{state.value.currentAccessToken().also{publish()}}catch(e:Exception){publish((e as? ManagedCollectFailure)?.code?:"managed_sign_in_unavailable");throw e}
    fun onBackground(){if(state.isInitialized())state.value.onBackground()}
    fun cancelEmailCode(){if(state.isInitialized())state.value.cancelEmailCode();publish()}
    fun signOut(){try{if(state.isInitialized())state.value.signOut();publish()}catch(e:Exception){publish("managed_sign_out_unconfirmed");throw e}}
}
