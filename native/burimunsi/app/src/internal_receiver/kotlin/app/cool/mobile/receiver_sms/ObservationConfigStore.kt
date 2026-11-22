package app.cool.mobile.receiver_sms

import android.content.Context
import android.Manifest
import android.content.pm.PackageManager
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.SecureStore

/** Candidate filters and consent belong to the signed-in account, not to a hardcoded wallet. */
internal class ObservationConfigStore(context:Context) {
    data class Control(val paused:Boolean,val revision:Long)
    private val app=context.applicationContext
    private val profiles=SecureStore(app,"observation-profile")
    private val consents=SecureStore(app,"observation-consent")
    // A pause is scoped to the account and installation, and survives account
    // switching. A damaged protected preference fails closed rather than resuming.
    private fun control(owner:ObservationOwner):SecureStore {
        checkContract(owner.valid(),"observation_store_unavailable")
        val key=Values.sha256("${owner.collectionId.length}:${owner.collectionId}${owner.accountId.length}:${owner.accountId}")
        return SecureStore(app,"observation-control-$key")
    }
    fun controlState(owner:ObservationOwner):Control {
        val raw=control(owner).read()?:return Control(false,0)
        val value=JSONObject(raw);exact(value,setOf("collectionId","accountId","paused","revision"))
        checkContract(sameOwner(value,owner)&&value.opt("paused") is Boolean&&value.opt("revision") is Number&&
            value.getLong("revision") in 1..9_007_199_254_740_991L,"observation_store_unavailable")
        return Control(value.getBoolean("paused"),value.getLong("revision"))
    }
    fun paused(owner:ObservationOwner)=controlState(owner).paused
    fun setPaused(owner:ObservationOwner,paused:Boolean) {
        val prior=controlState(owner);if(prior.paused==paused)return
        checkContract(prior.revision<9_007_199_254_740_991L,"observation_store_unavailable")
        val target=control(owner)
        val encoded=JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId)
            .put("paused",paused).put("revision",prior.revision+1).toString()
        target.write(encoded);checkContract(target.read()==encoded,"observation_store_unavailable")
        val allowed=!paused&&listOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS).all{
            app.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED
        }
        consent(owner)?.let{current->
            val next=ObservationConsent.reconcile(current,null,allowed)?:throw ContractFailure("observation_store_unavailable")
            if(next!=current)saveConsent(owner,next)
        }
    }
    private fun sameOwner(value:JSONObject,owner:ObservationOwner)=
        owner.valid()&&value.opt("collectionId")==owner.collectionId&&value.opt("accountId")==owner.accountId
    private fun exact(value:JSONObject,keys:Set<String>)=checkContract(value.keys().asSequence().toSet()==keys,"observation_store_unavailable")
    private fun strings(value:JSONObject,key:String):Set<String>{
        val list=value.getJSONArray(key);checkContract(list.length() in 1..30,"invalid_observation_profile")
        val result=(0 until list.length()).map{list.getString(it)}
        checkContract(result.size==result.toSet().size&&result.all{it.isNotBlank()&&it.length<=160&&
            it.none{ch->ch=='\r'||ch=='\n'||ch=='\u0000'}},"invalid_observation_profile")
        return result.toSet()
    }
    private fun decodeProfile(value:JSONObject):ObservationProfile {
        val keys=setOf("profileVersion","senders","incomingPrefixes","currencyAliases","transactionIdPrefixes","offsetMinutes","issuedAt","expiresAt")
        exact(value,if(value.has("legacyHold"))keys+"legacyHold" else keys)
        val profile=ReceiptProfile(value.getString("profileVersion"),strings(value,"senders"),value.getInt("offsetMinutes"),
            strings(value,"incomingPrefixes"),strings(value,"currencyAliases"),strings(value,"transactionIdPrefixes"))
        return ObservationProfile(profile,value.getLong("issuedAt"),value.getLong("expiresAt"),
            if(value.has("legacyHold"))value.getBoolean("legacyHold") else null)
    }
    fun saveProfile(owner:ObservationOwner,data:JSONObject,now:Long) {
        checkContract(owner.valid()&&decodeProfile(data).current(now),"invalid_observation_profile")
        val encoded=JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId).put("profile",data).toString()
        profiles.write(encoded);checkContract(profiles.read()==encoded,"observation_store_unavailable")
    }
    fun profile(owner:ObservationOwner,now:Long):ObservationProfile? {
        val raw=profiles.read()?:return null;val value=JSONObject(raw);exact(value,setOf("collectionId","accountId","profile"))
        if(!sameOwner(value,owner))return null
        val profile=decodeProfile(value.getJSONObject("profile"));return profile.takeIf{it.current(now)}
    }
    fun consent(owner:ObservationOwner):ObservationConsentState? {
        val raw=consents.read()?:return null;val value=JSONObject(raw);exact(value,setOf("collectionId","accountId","enabled","generation","confirmed"))
        if(!sameOwner(value,owner))return null
        val revision=ObservationConsentRevision(value.getBoolean("enabled"),value.getLong("generation"))
        checkContract(revision.generation in 1..ObservationConsent.MAX_GENERATION,"observation_store_unavailable")
        return ObservationConsentState(revision,value.getBoolean("confirmed"))
    }
    fun saveConsent(owner:ObservationOwner,state:ObservationConsentState) {
        checkContract(owner.valid()&&state.revision.generation in 1..ObservationConsent.MAX_GENERATION,"invalid_consent_generation")
        val encoded=JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId)
            .put("enabled",state.revision.enabled).put("generation",state.revision.generation).put("confirmed",state.confirmed).toString()
        consents.write(encoded);checkContract(consents.read()==encoded,"observation_store_unavailable")
    }
}
