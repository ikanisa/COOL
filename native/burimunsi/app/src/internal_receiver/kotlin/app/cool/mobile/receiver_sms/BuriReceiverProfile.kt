package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ReceiptProfile
import rw.ikanisa.burimunsi.core.Values
import java.util.Locale

/** Approved receiver classifier retained inside the existing encrypted,
 * no-backup gateway state. It is not an SMS body or a provider credential. */
internal object BuriReceiverProfile {
    private const val LIFETIME_MS=24L*60*60*1000
    private const val REFRESH_MS=15L*60*1000
    private const val CLOCK_SKEW_MS=2L*60*1000
    private val fields=setOf("contractVersion","collectionId","installationId","bindingId","bindingVersion",
        "receivingAccountId","profileVersion","offsetMinutes","senders","incomingPrefixes","currencyAliases",
        "transactionIdPrefixes","issuedAt","expiresAt")

    private fun whole(value:Any?):Long?=when(value){is Int->value.toLong();is Long->value;else->null}
    private fun safe(value:Any?,max:Int):String?=(value as? String)?.takeIf { text ->
        text.isNotBlank()&&text==text.trim()&&text.length<=max&&text.none { c ->
            c.isISOControl()||c in '\u202a'..'\u202e'||c in '\u2066'..'\u2069'
        }
    }
    private fun projection(binding:JSONObject?,snapshot:JSONObject?,now:Long):ReceiptProfile? {
        if(binding==null||snapshot==null||snapshot.keys().asSequence().toSet()!=fields)return null
        if(whole(snapshot.opt("contractVersion"))!=1L||
            snapshot.opt("collectionId")!=binding.opt("collection_id")||
            snapshot.opt("bindingId")!=binding.opt("id")||
            snapshot.opt("receivingAccountId")!=binding.opt("receiving_account_id")||
            whole(snapshot.opt("bindingVersion"))!=whole(binding.opt("version")))return null
        if(listOf("collectionId","installationId","bindingId","receivingAccountId").any{safe(snapshot.opt(it),128)==null})return null
        val version=(snapshot.opt("profileVersion") as? String)?.takeIf { text ->
            text.isNotEmpty()&&text==text.trim()&&text.length<=80&&text.none { c ->
                c in '\u0000'..'\u0008'||c=='\u000b'||c=='\u000c'||c in '\u000e'..'\u001f'
            }
        }?:return null
        if(version=="unverified")return null
        val offset=whole(snapshot.opt("offsetMinutes"))?:return null
        if(offset !in -840L..840L)return null
        val issued=whole(snapshot.opt("issuedAt"))?:return null
        val expires=whole(snapshot.opt("expiresAt"))?:return null
        if(now<=0L||issued<=0L||issued>now+CLOCK_SKEW_MS||expires<=now||expires-issued!=LIFETIME_MS)return null
        fun strings(key:String):Set<String>? {
            val array=snapshot.opt(key) as? JSONArray?:return null
            if(array.length() !in 1..30)return null
            val values=(0 until array.length()).map { index ->
                (array.get(index) as? String)?.takeIf { value ->
                    value.length<=160&&value.trim().isNotEmpty()&&value.none{it=='\r'||it=='\n'||it=='\u0000'}
                }?:return null
            }
            return values.toSet()
        }
        val senders=strings("senders")?:return null
        val incoming=strings("incomingPrefixes")?:return null
        val currencies=strings("currencyAliases")?:return null
        val references=strings("transactionIdPrefixes")?:return null
        if(currencies.any{it !in setOf("RWF","FRW")})return null
        return ReceiptProfile(version,senders,offset.toInt(),incoming,currencies,references)
    }
    private fun revision(snapshot:JSONObject,profile:ReceiptProfile):String {
        val parts=listOf(snapshot.getString("collectionId"),snapshot.getString("installationId"),snapshot.getString("bindingId"),
            snapshot.get("bindingVersion").toString(),snapshot.getString("receivingAccountId"),profile.version,
            profile.offsetMinutes.toString())+listOf(profile.senders,profile.incomingPrefixes,profile.currencyAliases,profile.transactionIdPrefixes)
            .flatMap{values->listOf(values.size.toString())+values.map{it.lowercase(Locale.ROOT)}.sorted()}
        return Values.sha256(parts.joinToString(""){"${it.length}:$it"})
    }

    fun current(binding:JSONObject?,now:Long=System.currentTimeMillis()):ReceiptProfile? {
        val snapshot=binding?.optJSONObject("receipt_profile")?:return null
        val result=projection(binding,snapshot,now)?:return null
        if(binding.opt("receipt_profile_revision")!=revision(snapshot,result))return null
        return result
    }
    fun installation(binding:JSONObject?):String?=binding?.optJSONObject("receipt_profile")?.let{safe(it.opt("installationId"),128)}
    fun senderAllowed(binding:JSONObject?,sender:String,now:Long=System.currentTimeMillis()):Boolean =
        current(binding,now)?.senders?.any{it.lowercase(Locale.ROOT)==sender.lowercase(Locale.ROOT)}==true

    /** The receiver lock precedes session/store locks. Announce only a real
     * profile change, before its protected write, and wake after the lock. */
    private fun updateProfile(store:MomoGatewayStore,binding:JSONObject,token:String,
        profile:JSONObject?,marker:String?):Boolean {
        var changed=false;var applied=false
        try{
            store.withObservationState{state->
                val selected=state?.optJSONObject("binding")
                if(state?.opt("gateway_token")==token&&selected!=null&&
                    BuriReceiverReliability.bindingMatches(binding::opt,selected::opt)){
                    val old=selected.optJSONObject("receipt_profile")
                    val same=if(profile==null)!selected.has("receipt_profile")&&!selected.has("receipt_profile_revision")
                        else old?.toString()==profile.toString()&&selected.opt("receipt_profile_revision")==marker
                    if(same)applied=true else {
                        changed=true
                        ObservationAuthorityRevision.changing{
                            store.update{current->
                                val currentBinding=current.optJSONObject("binding")
                                if(current.opt("gateway_token")==token&&currentBinding!=null&&
                                    BuriReceiverReliability.bindingMatches(binding::opt,currentBinding::opt)){
                                    if(profile==null){currentBinding.remove("receipt_profile");currentBinding.remove("receipt_profile_revision")}
                                    else currentBinding.put("receipt_profile",profile).put("receipt_profile_revision",marker)
                                    applied=true
                                }
                            }
                        }
                    }
                }
            }
        }finally{if(changed)ObservationAuthorityRevision.receiverChanged()}
        return applied
    }

    /** Refresh only outside the gateway-state lock; install a response only if
     * the original token and binding still own the same receiving route. */
    fun refresh(context:Context,http:MomoGatewayHttp=MomoGatewayHttp(),now:Long=System.currentTimeMillis()):Boolean {
        val store=MomoGatewayStore(context);val before=store.read()?:return false
        val binding=before.optJSONObject("binding")?:return false
        val token=before.opt("gateway_token") as? String?:return false
        val installation=store.existingInstallationId()?:return false
        if(!Regex("[a-f0-9]{64}").matches(token))return false
        val existing=binding.optJSONObject("receipt_profile")
        val issued=existing?.let{whole(it.opt("issuedAt"))}
        if(current(binding,now)!=null&&installation(binding)==installation&&issued!=null&&now>=issued&&now-issued<REFRESH_MS)return true
        fun discard(){updateProfile(store,binding,token,null,null)}
        val response=try{http.request("profile",token)}catch(e:MomoGatewayHttp.ResponseFailure){
            if(e.status in setOf(401,403,404))runCatching{discard()}
            return current(store.binding(),now)!=null&&installation(store.binding())==installation
        }catch(_:Exception){return current(store.binding(),now)!=null&&installation(store.binding())==installation}
        val approved=projection(binding,response,now)
        if(approved==null||response.opt("installationId")!=installation){runCatching{discard()};return false}
        val marker=revision(response,approved)
        return try{updateProfile(store,binding,token,response,marker)}catch(_:Exception){false}
    }
}
