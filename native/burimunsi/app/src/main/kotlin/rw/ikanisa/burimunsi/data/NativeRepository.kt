package rw.ikanisa.burimunsi.data

import android.content.Context
import java.util.Base64
import org.json.JSONObject
import org.json.JSONArray
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.*
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.UUID

/** Opaque, repository-owned read capability. No bearer or account material is
 * exposed to the screen/export layer; every page rechecks original ownership. */
class RecordReadScope internal constructor(private val owner:Any,private val verify:()->Unit,private val reader:(String)->String) {
    internal fun validate(expectedOwner:Any){checkContract(owner===expectedOwner,"session_changed");verify()}
    internal fun read(expectedOwner:Any,path:String):String {
        validate(expectedOwner);val result=reader(path);validate(expectedOwner);return result
    }
    override fun toString()="RecordReadScope"
}

/** API data is the authority. No local SMS-to-balance arithmetic and no demo accounts. */
class NativeRepository(context:Context,private val api:ApiClient,groupId:String?=null){
    companion object {
        private val commandPreparationLock=Any();private val signOutLock=Any()
        // UI and the foreground supervisor share one ordered server-profile
        // stream. This lock never excludes logout or credential replacement.
        private val sessionRefreshLock=Any()
        private val processSessionAuthority=SessionAuthority()
        private var signOutRetryRunning=false

        private fun pendingSignOut(saved:JSONObject,raw:String?):Boolean {
            if(raw==null)return false
            val entries=JSONObject(raw).getJSONArray("entries");checkContract(entries.length()<=50,"operation_store_unavailable")
            val token=saved.getString("token");val group=saved.getString("groupId")
            val candidate=saved.optJSONObject("pendingPasscode")?.optString("token")
            return (0 until entries.length()).any{i->val entry=entries.getJSONObject(i)
                entry.getString("groupId")==group&&listOfNotNull(token,candidate).any{proof->
                    proof==entry.getString("token")||entry.optString("candidate")==proof}}
        }

        /** Caller holds processSessionAuthority. Expired metadata may authorize
         * a visible renewal attempt, never observation capture or upload. */
        private fun observationIdentifiers(context:Context,allowExpired:Boolean):Pair<String,String>? {
            if(SecureStore(context,"signed-out").read()!=null||!processSessionAuthority.observationAdmitted())return null
            val saved=JSONObject(SecureStore(context,"session").read()?:return null)
            val deadline=saved.getLong("expiresAt")
            if(deadline<=0||!allowExpired&&deadline<=System.currentTimeMillis())return null
            val token=saved.getString("token")
            if(!Regex("[a-f0-9]{64}").matches(token))return null
            if(processSessionAuthority.hasActive()){
                if(processSessionAuthority.capture().token!=token)return null
            }else if(processSessionAuthority.revision()!=0L)return null
            val pending=saved.optJSONObject("pendingPasscode")
            if(saved.has("pendingPasscode")&&(pending==null||pending.getString("state")!="prepared"||
                !Regex("[a-f0-9]{64}").matches(pending.getString("token"))||pending.getString("token")==token))return null
            if(synchronized(signOutLock){pendingSignOut(saved,SecureStore(context,"session-revocations").read())})return null
            val profile=saved.getJSONObject("profile")
            if(profile.getString("role")!="admin")return null
            val capabilities=profile.getJSONArray("capabilities")
            val values=(0 until capabilities.length()).map{capabilities.getString(it)}.toSet()
            if(!values.containsAll(setOf("sms.read","gateway.manage")))return null
            return Values.id(saved.getString("groupId")) to Values.id(profile.getString("id"))
        }

        /** Foreground-supervisor eligibility only. The supervisor must still
         * call restore() before any scan/upload; an expired lease grants none. */
        internal fun canRestoreObservationOwner(context:Context):Boolean=restorableObservationOwner(context)!=null
        /** Identifiers for persisted pause/control lookup during renewal only;
         * this never returns an ObservationSessionOwner or a capture witness. */
        internal fun restorableObservationOwner(context:Context):ObservationOwner?=synchronized(processSessionAuthority){
            try{observationIdentifiers(context,allowExpired=true)?.let{ObservationOwner(it.first,it.second)}}catch(_:Exception){null}
        }

        /** Serialize local observation custody with login/logout on the same process.
         * The callback receives only validated scope identifiers, never a bearer. */
        internal fun observationOwner(context:Context):ObservationSessionOwner? =
            withObservationOwner(context){group,account->ObservationSessionOwner(ObservationOwner(group,account),processSessionAuthority.revision())}
        internal fun <T> withObservationOwner(context:Context,expected:ObservationSessionOwner?=null,action:(String,String)->T):T? = synchronized(processSessionAuthority){
            val identifiers=try{observationIdentifiers(context,allowExpired=false)}catch(_:Exception){null}?:return@synchronized null
            if(expected!=null&&expected!=ObservationSessionOwner(ObservationOwner(identifiers.first,identifiers.second),processSessionAuthority.revision()))return@synchronized null
            action(identifiers.first,identifiers.second)
        }
    }
    @Volatile private var boundGroup:String?=groupId?.let(Values::id)
    private val configuredGroup=groupId?.let(Values::id)
    private val groupId:String get()=boundGroup?:throw ApiFailure("session_unavailable",401)
    val collectionId:String get()=groupId
    val boundCollectionId:String? get()=boundGroup
    private val sessionStore=SecureStore(context,"session")
    private val revocationStore=SecureStore(context,"session-revocations")
    private val signedOutStore=SecureStore(context,"signed-out")
    private val cacheStore=SecureStore(context,"records")
    private val journal=OperationJournal(AndroidOperationStore(context))
    private val receiverRetirement=ReceiverRetirementJournal(AndroidReceiverRetirementStore(context))
    private val authority=processSessionAuthority
    private val recordReadOwner=Any()
    private data class LocalOwnership(val group:String,val owner:String?,val tokenHash:String)
    @Volatile private var ownedWitness:SessionWitness?=null
    @Volatile private var lastOwned:LocalOwnership?=null
    @Volatile private var operator:Operator?=null
    var lastReadSavedAt:Long?=null;private set
    var lastReadFromCache=false;private set
    private val cacheTtlMs=SnapshotFreshness.TTL_MS
    private fun clearMemoryOperator(){ownedWitness=null;operator=null;lastReadFromCache=false;lastReadSavedAt=null}
    private fun ownedSession():SessionWitness {
        val witness=ownedWitness?:throw ContractFailure("session_unavailable")
        return authority.withCurrent(witness){witness}
    }
    private fun clearLocalOperator(){
        clearMemoryOperator()
        sessionStore.clear()
        check(sessionStore.read()==null){"Protected session could not be removed"}
        cacheStore.clear();lastOwned=null
    }
    private fun confirmedSessionDenial(e:ApiFailure):Boolean=!e.uncertain&&when(e.status){
        401->e.code in setOf("session_unavailable","invalid_credentials","invalid_session")
        403->e.code in setOf("native_scope_changed","access_denied","permission_denied")
        else->false
    }
    fun restore():Operator?{
        // Snapshot, validate and attach under one process-wide lock. A second
        // activity with the same saved bearer joins the existing generation.
        val restored=synchronized(authority){
            val signedOut=signedOutStore.read()!=null
            val raw=sessionStore.read()
            clearMemoryOperator()
            if(signedOut){
                if(raw!=null)runCatching{retainSignOut(JSONObject(raw));sessionStore.clear()}
                runCatching{cacheStore.clear()}
                return@synchronized null
            }
            if(raw==null)return@synchronized null
            val j=try{JSONObject(raw)}catch(_:Exception){authority.retire(::clearLocalOperator);return@synchronized null}
            if(hasPendingSignOut(j)){authority.retire(::clearLocalOperator);return@synchronized null}
            val restoredGroup=runCatching{Values.id(j.getString("groupId"))}.getOrNull()
            val savedOwner=runCatching{if(!j.has("profile")||j.isNull("profile"))null else Values.id(j.getJSONObject("profile").getString("id"))}
            val valid=runCatching{restoredGroup!=null&&(configuredGroup==null||restoredGroup==configuredGroup)&&
                j.getLong("expiresAt")>0&&Regex("[a-f0-9]{64}").matches(j.getString("token"))&&savedOwner.isSuccess}.getOrDefault(false)
            if(!valid){authority.retire(::clearLocalOperator);return@synchronized null}
            val pending=j.optJSONObject("pendingPasscode")
            if(pending!=null){
                val validPending=runCatching{Regex("[a-f0-9]{64}").matches(pending.getString("token"))&&
                    pending.getString("token")!=j.getString("token")&&pending.getString("state") in setOf("prepared","inflight")&&
                    savedOwner.getOrNull()!=null}.getOrDefault(false)
                if(!validPending){authority.retire(::clearLocalOperator);return@synchronized null}
                if(pending.getString("state")=="prepared")j.remove("pendingPasscode")
            }
            val witness=authority.attach(j.getString("token")){w->
                boundGroup=restoredGroup
                if(pending!=null&&pending.getString("state")=="prepared")saveSession(j)
                ownedWitness=w;lastOwned=LocalOwnership(restoredGroup!!,savedOwner.getOrNull(),Values.sha256(w.token))
            }
            Triple(witness,j,savedOwner.getOrNull())
        }
        if(restored==null)return null
        val (witness,j,savedOwner)=restored
        return try{
            if(j.optJSONObject("pendingPasscode")!=null)recoverPasscode(witness,j,savedOwner!!)
            else refreshSession(savedOwner)
        }catch(e:Exception){
            // A transient error may be retried after reconnecting. A confirmed
            // revocation/scope change clears the encrypted record and cache.
            val revoked=e is ApiFailure&&confirmedSessionDenial(e)||
                e is ContractFailure&&e.code=="session_changed"
            if(revoked)authority.invalidateIfCurrent(witness,::clearLocalOperator)
            else if(ownedWitness==witness)clearMemoryOperator()
            throw e
        }
    }
    fun login(phone:String,pin:String):Operator {
        val normalizedPhone=Values.phone(phone);val normalizedPin=Values.pin(pin)
        val ticket=synchronized(authority){
            val saved=sessionStore.read()?.let(::JSONObject)
            val explicitlySignedOut=signedOutStore.read()!=null
            if(explicitlySignedOut&&saved!=null)retainSignOut(saved)
            if(!explicitlySignedOut&&saved?.optJSONObject("pendingPasscode")?.optString("state")=="inflight")
                throw ApiFailure("passcode_change_unconfirmed",503,true)
            if(!explicitlySignedOut&&(saved!=null||authority.hasActive()))throw ApiFailure("session_already_active",409)
            authority.revision()
        }
        val context=mapOf<String,Any?>("generation" to ticket.toString())+
            (if(api.resolvesLoginScope)emptyMap() else mapOf("groupId" to groupId))
        val j=JSONObject(api.call("POST","/v1/burimunsi/session/login",body=JSONObject().put("phone",normalizedPhone).put("pin",normalizedPin),contractContext=context))
        val selected=if(j.has("groupId"))Values.id(j.getString("groupId")) else if(api.resolvesLoginScope)throw ApiFailure("invalid_api_response") else groupId
        val expiry=j.getLong("expiresAt")
        val t=j.getString("token");check(Regex("[a-f0-9]{64}").matches(t))
        val profile=operator(j.getJSONObject("profile"),expiry)
        try{
            if(configuredGroup!=null&&selected!=configuredGroup)throw ApiFailure("scope_changed",403)
            check(expiry>System.currentTimeMillis())
            authority.installRevision(ticket,t){witness->
            val before=sessionStore.read();val marker=signedOutStore.read()
            try{
                val previous=before?.let(::JSONObject)
                if(marker==null&&previous?.optJSONObject("pendingPasscode")?.optString("state")=="inflight")
                    throw ApiFailure("passcode_change_unconfirmed",503,true)
                if(marker==null&&previous!=null)throw ApiFailure("session_already_active",409)
                saveSession(JSONObject().put("token",t).put("groupId",selected).put("expiresAt",expiry).put("profile",j.getJSONObject("profile")))
                signedOutStore.clear();check(signedOutStore.read()==null){"Protected sign-out marker could not be removed"}
                cacheStore.clear()
            }catch(e:Exception){
                runCatching{if(before==null)sessionStore.clear() else sessionStore.write(before);if(marker!=null)signedOutStore.write(marker)}
                throw e
            }
            boundGroup=selected;operator=profile;ownedWitness=witness;lastOwned=LocalOwnership(selected,profile.id,Values.sha256(t));lastReadFromCache=false;lastReadSavedAt=System.currentTimeMillis()
        }}catch(e:Exception){
            // Server sign-in can succeed after this instance was superseded.
            // Keep its exact returned token only as a revocation obligation.
            val orphan=JSONObject().put("token",t).put("groupId",selected).put("profile",j.getJSONObject("profile"))
            try{retainSignOut(orphan)}catch(_:Exception){
                val context=mapOf<String,Any?>("groupId" to selected,"generation" to "0","actorId" to profile.id)
                val revoked=runCatching{JSONObject(api.call("POST","/v1/burimunsi/session/logout",t,JSONObject(),contractContext=context)).getBoolean("signedOut")}.getOrDefault(false)
                if(!revoked)throw ApiFailure("login_cleanup_unconfirmed",503,true)
            }
            throw e
        }
        return profile
    }
    fun refreshSession():Operator = refreshSession(null)
    private fun refreshSession(expectedOwner:String?):Operator=synchronized(sessionRefreshLock){
        refreshSessionLocked(expectedOwner)
    }
    private fun refreshSessionLocked(expectedOwner:String?):Operator {
        val witness=ownedSession()
        val j=try{JSONObject(requestOwned(witness,"GET","/session"))}catch(e:ApiFailure){
            if(e.status==403&&confirmedSessionDenial(e)){authority.invalidateIfCurrent(witness,::clearLocalOperator);throw ApiFailure("session_unavailable",401)}
            throw e
        }
        return authority.withCurrent(witness){
            if(j.has("groupId")&&j.getString("groupId")!=groupId){
                authority.invalidateIfCurrent(witness,::clearLocalOperator)
                throw ContractFailure("session_changed")
            }
            val profile=operator(j.getJSONObject("profile"),j.getLong("expiresAt"))
            val prior=operator
            if(profile.expiresAt<=System.currentTimeMillis()||(prior!=null&&prior.id!=profile.id)||
                (expectedOwner!=null&&expectedOwner!=profile.id)){
                authority.invalidateIfCurrent(witness,::clearLocalOperator)
                throw ContractFailure("session_changed")
            }
            // A revalidated session may have a renewed deadline. Persist the
            // exact server result before exposing the operator to the UI.
            val saved=JSONObject(sessionStore.read()?:throw ContractFailure("session_changed"))
            checkContract(saved.getString("token")==witness.token&&saved.getString("groupId")==groupId,"session_changed")
            saved.optJSONObject("pendingPasscode")?.let{pending->
                checkContract(Regex("[a-f0-9]{64}").matches(pending.getString("token"))&&pending.getString("token")!=witness.token&&
                    pending.getString("state") in setOf("prepared","inflight"),"session_changed")
            }
            // Preserve any exact in-flight passcode candidate while persisting a
            // delayed refresh of this same predecessor session.
            saved.put("expiresAt",profile.expiresAt).put("profile",j.getJSONObject("profile"))
            try{saveSession(saved)}catch(e:Exception){authority.blockObservationIfCurrent(witness);throw e}
            lastReadFromCache=false;lastReadSavedAt=System.currentTimeMillis()
            operator=profile
            authority.confirmObservationCurrent(witness)
            profile
        }
    }
    private fun saveSession(value:JSONObject){
        val encoded=value.toString();sessionStore.write(encoded)
        check(sessionStore.read()==encoded){"Protected session could not be saved"}
    }
    private fun pendingSession(witness:SessionWitness,candidate:String):JSONObject {
        val saved=JSONObject(sessionStore.read()?:throw ContractFailure("session_changed"))
        val pending=saved.optJSONObject("pendingPasscode")?:throw ContractFailure("session_changed")
        checkContract(saved.getString("token")==witness.token&&saved.getString("groupId")==groupId&&
            pending.getString("token")==candidate,"session_changed")
        return saved
    }
    private fun hasInflightPasscode(witness:SessionWitness):Boolean {
        return try{
            val saved=sessionStore.read()?.let(::JSONObject)?:return false
            saved.getString("token")==witness.token&&saved.optJSONObject("pendingPasscode")?.optString("state")=="inflight"
        }catch(_:Exception){true} // Do not erase a damaged or unavailable protected record as a guess.
    }
    private fun installPasscodeSession(witness:SessionWitness,candidate:String,profileJson:JSONObject,expiry:Long,expectedOwner:String):Operator {
        val profile=operator(profileJson,expiry)
        checkContract(profile.id==expectedOwner&&expiry>System.currentTimeMillis(),"session_changed")
        authority.replaceCurrentWithWitness(witness,candidate){nextWitness->
            val saved=pendingSession(witness,candidate)
            checkContract(saved.getJSONObject("profile").getString("id")==expectedOwner,"session_changed")
            saved.remove("pendingPasscode")
            saved.put("token",candidate).put("expiresAt",expiry).put("profile",profileJson)
            saveSession(saved)
            operator=profile;ownedWitness=nextWitness;lastOwned=LocalOwnership(groupId,profile.id,Values.sha256(candidate));lastReadFromCache=false;lastReadSavedAt=System.currentTimeMillis()
        }
        return profile
    }
    private fun recoverPasscode(witness:SessionWitness,saved:JSONObject,owner:String):Operator {
        val candidate=saved.getJSONObject("pendingPasscode").getString("token")
        val selected=authority.withCurrent(witness){groupId}
        // This is only a candidate proof read. A 401 cannot establish that the
        // original POST will never commit, so leave the pending credential intact.
        val reply=try{api.call("GET","/v1/burimunsi/session",candidate,contractContext=
            mapOf("groupId" to selected,"generation" to witness.generation.toString(),"actorId" to owner))}
        catch(_:Exception){throw ApiFailure("passcode_change_unconfirmed",503,true)}
        val value=try{JSONObject(reply)}catch(_:Exception){throw ApiFailure("passcode_change_unconfirmed",503,true)}
        checkContract(!value.has("groupId")||value.getString("groupId")==selected,"session_changed")
        return installPasscodeSession(witness,candidate,value.getJSONObject("profile"),value.getLong("expiresAt"),owner)
    }
    fun current():Operator? {
        val witness=ownedWitness?:return null
        return try{authority.withCurrent(witness){operator}}catch(_:ContractFailure){null}
    }
    /** Join only an already-active same-owner/group replacement. A logout or
     * account switch never opens a fresh process slot through this path. */
    fun reattachSameOwner(owner:String,collection:String):Operator? {
        Values.id(owner);Values.id(collection)
        val witness=synchronized(authority){
            if(!authority.hasActive()||signedOutStore.read()!=null)return null
            val saved=sessionStore.read()?.let(::JSONObject)?:return null
            if(saved.getString("groupId")!=collection||saved.getJSONObject("profile").getString("id")!=owner||
                saved.optJSONObject("pendingPasscode")!=null)return null
            authority.attach(saved.getString("token")){w->boundGroup=collection;ownedWitness=w;lastOwned=LocalOwnership(collection,owner,Values.sha256(w.token))}
        }
        return try{refreshSession(owner)}catch(e:Exception){
            if(ownedWitness==witness)clearMemoryOperator()
            throw e
        }
    }
    fun observeProcessSession(listener:()->Unit):()->Unit=authority.observe(listener)
    fun hasPendingPasscode():Boolean = try{
        signedOutStore.read()==null&&sessionStore.read()?.let(::JSONObject)?.optJSONObject("pendingPasscode")?.optString("state")=="inflight"
    }catch(_:Exception){true}
    fun hasSavedSession():Boolean=try{signedOutStore.read()==null&&sessionStore.read()!=null}catch(_:Exception){true}
    fun hasPendingReceiverRetirement():Boolean=receiverRetirement.retained()?.state?.let{it!=ReceiverRetirementState.RETIRED}==true
    /** Factory also needs terminal ACKs whose local gateway park was interrupted. */
    fun hasReceiverRetirementRecord():Boolean=receiverRetirement.retained()!=null
    private fun retirementAck(value:JSONObject,requestId:String):ReceiverRetirementAck {
        checkedDto("replace.data",value)
        checkContract(value.getString("requestId")==requestId,"gateway_retirement_identity_changed")
        return ReceiverRetirementAck(Values.requestId(value.getString("handoffId")),Values.requestId(requestId))
    }
    private fun ackJson(ack:ReceiverRetirementAck)=JSONObject().put("retired",true).put("handoffId",ack.handoffId)
        .put("requestId",ack.requestId).put("reauthenticationRequired",true)
    /** Historical ACK only; its retained bearer is never installed as a session.
     * This read works before restore/login and cannot dispatch another POST. */
    fun recoverReceiverRetirement():JSONObject? {
        val record=receiverRetirement.retained()?:return null
        checkContract(record.installationId==api.installationId&&api.installationProfile=="internal_receiver","gateway_retirement_identity_changed")
        record.ack?.let{return ackJson(it)}
        return receiverRetirement.withOutcomeRead(record){
            try{
                val token=record.token?:throw ContractFailure("corrupt_gateway_retirement")
                val raw=api.call("GET","/v1/burimunsi/gateway/replacements/${record.requestId}/outcome",token,
                    contractContext=mapOf("groupId" to record.groupId,"actorId" to record.actorId,"generation" to record.generation,"handoffFingerprint" to record.fingerprint))
                val value=JSONObject(raw);checkedDto("retirementOutcome.data",value)
                checkContract(value.getString("requestId")==record.requestId&&value.getString("fingerprint")==record.fingerprint,"gateway_retirement_identity_changed")
                if(value.getString("state")=="unknown"){
                    checkContract(value.isNull("ack"),"gateway_retirement_identity_changed");null
                }else{
                    checkContract(value.getString("state")=="retired"&&!value.isNull("ack"),"gateway_retirement_identity_changed")
                    val ack=retirementAck(value.getJSONObject("ack"),record.requestId)
                    receiverRetirement.acknowledge(record,ack);ackJson(ack)
                }
            }catch(_:Exception){throw ApiFailure("gateway_retirement_unconfirmed",503,true)}
        }
    }
    private fun retireReceiver(code:String):JSONObject {
        // Even a PREPARED record from an interrupted process is read-only now.
        if(receiverRetirement.retained()!=null)return recoverReceiverRetirement()?:throw ApiFailure("gateway_retirement_unconfirmed",503,true)
        val value=code.trim();checkContract(Regex("[a-f0-9]{64}").matches(value),"invalid_pairing_code")
        checkContract(api.installationProfile=="internal_receiver"&&api.resolvesLoginScope,"access_denied")
        val witness=ownedSession()
        val record=synchronized(commandPreparationLock){authority.withCurrent(witness){
            checkContract(journal.unresolved()==null,"pending_operation_requires_resolution")
            val who=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(who.expiresAt>System.currentTimeMillis()&&who.role==Role.ADMIN&&Capability.GATEWAY.key in who.capabilities,"access_denied")
            receiverRetirement.prepare(groupId,who.id,api.installationId,witness.generation.toString(),witness.token,value)
        }}
        authority.withCurrent(witness){receiverRetirement.beginDispatch(record)}
        try{
            authority.withCurrent(witness){checkContract(journal.unresolved()==null,"pending_operation_requires_resolution")}
            val raw=api.call("POST","/v1/burimunsi/gateway/replace",witness.token,
                JSONObject().put("replacementCode",value).put("requestId",record.requestId),
                contractContext=mapOf("groupId" to record.groupId,"actorId" to record.actorId,"generation" to record.generation))
            val ack=retirementAck(JSONObject(raw),record.requestId)
            receiverRetirement.acknowledge(record,ack)
            return ackJson(ack)
        }catch(_:Exception){
            runCatching{receiverRetirement.uncertain(record)}
            throw ApiFailure("gateway_retirement_unconfirmed",503,true)
        }
    }
    fun pairGateway(code:String,replace:Boolean):JSONObject {
        if(replace)return retireReceiver(code)
        checkContract(!hasPendingReceiverRetirement(),"gateway_retirement_unconfirmed")
        val value=code.trim()
        require(Regex("[a-f0-9]{64}").matches(value))
        val witness=ownedSession()
        val result=JSONObject(requestOwned(witness,"POST","/gateway/pair",JSONObject()
            .put("pairingCode",value).put("replace",false).put("requestId",java.util.UUID.randomUUID().toString())))
        return authority.withCurrent(witness){receiverRetirement.archiveAfterPair();result}
    }
    fun clearOperator(){ownedWitness?.let{authority.invalidateIfCurrent(it,::clearLocalOperator)} /* NEVER touches receiving queue or gateway grants. */}
    private fun retainSignOut(saved:JSONObject):String? {
        val old=saved.getString("token");val group=Values.id(saved.getString("groupId"))
        checkContract(Regex("[a-f0-9]{64}").matches(old),"invalid_session")
        val candidate=saved.optJSONObject("pendingPasscode")?.let{it.getString("token")}
        checkContract(candidate==null||Regex("[a-f0-9]{64}").matches(candidate)&&candidate!=old,"invalid_session")
        val owner=saved.optJSONObject("profile")?.let{Values.id(it.getString("id"))}
        return synchronized(signOutLock){
            val stored=revocationStore.read()?.let(::JSONObject)?:JSONObject().put("entries",JSONArray())
            val existing=stored.getJSONArray("entries");checkContract(existing.length()<=50,"operation_store_unavailable")
            if((0 until existing.length()).any{i->val item=existing.getJSONObject(i)
                item.getString("groupId")==group&&item.getString("token")==old&&
                    (if(item.has("candidate"))item.getString("candidate") else null)==candidate})return@synchronized null
            checkContract(existing.length()<50,"operation_store_unavailable")
            val next=JSONArray();for(i in 0 until existing.length())next.put(existing.getJSONObject(i))
            val id=UUID.randomUUID().toString()
            val item=JSONObject().put("id",id).put("groupId",group).put("token",old)
            if(candidate!=null)item.put("candidate",candidate)
            if(owner!=null)item.put("actorId",owner)
            next.put(item);val encoded=JSONObject().put("entries",next).toString()
            revocationStore.write(encoded)
            check(revocationStore.read()==encoded){"Protected sign-out obligation could not be saved"}
            id
        }
    }
    private fun hasPendingSignOut(saved:JSONObject):Boolean=synchronized(signOutLock){
        pendingSignOut(saved,revocationStore.read())
    }
    /** Retry only revocation; network calls never hold the journal lock and
     * these proofs can never be installed as a login. */
    fun retryPendingSignOuts():Boolean {
        // Finish a crash-interrupted local transfer first. The authority lock
        // excludes a new login while its signed-out marker is being cleared.
        var transferComplete=true
        val snapshot=synchronized(authority){
            try{
                if(signedOutStore.read()!=null)
                    sessionStore.read()?.let{retainSignOut(JSONObject(it));sessionStore.clear();check(sessionStore.read()==null)}
            }catch(_:Exception){transferComplete=false}
            // An in-progress login can stage the displaced proof before it
            // commits its replacement. Snapshot admission shares its lock, so
            // a rollback can remove that staged proof before any network call.
            synchronized(signOutLock){
                if(signOutRetryRunning)return false
                val raw=revocationStore.read()?:return transferComplete
                val entries=JSONObject(raw).getJSONArray("entries");checkContract(entries.length()<=50,"operation_store_unavailable")
                val copy=(0 until entries.length()).map{JSONObject(entries.getJSONObject(it).toString())}
                signOutRetryRunning=true;copy
            }
        }
        try{
            val confirmed=mutableMapOf<String,Triple<String,String,String?>>()
            for(item in snapshot){
                val id=Values.requestId(item.getString("id"));val group=Values.id(item.getString("groupId"));val old=item.getString("token")
                val candidate=if(item.has("candidate"))item.getString("candidate") else null
                checkContract(Regex("[a-f0-9]{64}").matches(old)&&
                    (candidate==null||Regex("[a-f0-9]{64}").matches(candidate)&&candidate!=old),"operation_store_unavailable")
                val context=mapOf<String,Any?>("groupId" to group,"generation" to "0")+
                    (if(item.has("actorId"))mapOf("actorId" to Values.id(item.getString("actorId"))) else emptyMap())
                val body=JSONObject();if(candidate!=null)body.put("replacementToken",candidate)
                val committed=try{
                    JSONObject(api.call("POST","/v1/burimunsi/session/logout",old,body,contractContext=context)).getBoolean("signedOut")
                }catch(_:Exception){false}
                if(committed)confirmed[id]=Triple(group,old,candidate)
            }
            val complete=synchronized(signOutLock){
                val current=revocationStore.read()?.let(::JSONObject)?.getJSONArray("entries")?:return@synchronized true
                checkContract(current.length()<=50,"operation_store_unavailable")
                val remaining=JSONArray()
                for(i in 0 until current.length()){
                    val item=current.getJSONObject(i);val id=Values.requestId(item.getString("id"))
                    val candidate=if(item.has("candidate"))item.getString("candidate") else null
                    if(confirmed[id]!=Triple(item.getString("groupId"),item.getString("token"),candidate))remaining.put(item)
                }
                if(remaining.length()==0){revocationStore.clear();check(revocationStore.read()==null){"Protected sign-out obligation could not be removed"}}
                else{
                    val encoded=JSONObject().put("entries",remaining).toString();revocationStore.write(encoded)
                    check(revocationStore.read()==encoded){"Protected sign-out obligation could not be saved"}
                }
                remaining.length()==0
            }
            return complete&&transferComplete
        }finally{synchronized(signOutLock){signOutRetryRunning=false}}
    }
    fun logout(){
        // Invalidate the local generation before the network; a delayed PIN
        // response or restore can never install another local credential.
        var localUnconfirmed=false;var remoteProofLost=false;var localClearFailed=false
        val witness=synchronized(authority){
            val owned=ownedWitness
            val stillCurrent=owned!=null&&runCatching{authority.withCurrent(owned){true}}.getOrDefault(false)
            if(stillCurrent)owned else sessionStore.read()?.let(::JSONObject)?.let{saved->
                // A stale activity may sign out the replacement only if it is
                // still the same account and group as its last local operator.
                val prior=lastOwned?:throw ContractFailure("session_changed")
                val group=saved.getString("groupId");val owner=saved.optJSONObject("profile")?.getString("id")
                val same=group==prior.group&&(if(prior.owner!=null)owner==prior.owner else Values.sha256(saved.getString("token"))==prior.tokenHash)
                if(!same)
                    throw ContractFailure("session_changed")
                // Never recreate a cleared process slot just to sign it out.
                if(authority.hasActive())authority.attach(saved.getString("token")){} else null
            }
        }
        authority.retireOwned(witness){
            val marked=try{signedOutStore.write("signed-out");check(signedOutStore.read()=="signed-out");true}
            catch(_:Exception){localUnconfirmed=true;false}
            val transferred=try{sessionStore.read()?.let{retainSignOut(JSONObject(it))};true}
            catch(_:Exception){localUnconfirmed=true;false}
            if(!transferred&&!marked)remoteProofLost=true
            if(transferred||!marked){
                try{clearLocalOperator()}catch(_:Exception){clearMemoryOperator();localUnconfirmed=true;localClearFailed=true}
            }else{
                // The marker prevents restoration while this encrypted proof
                // waits for a durable transfer on a later launch/sign-in.
                clearMemoryOperator();runCatching{cacheStore.clear()}
            }
        }
        if(remoteProofLost)throw ApiFailure(if(localClearFailed)"logout_local_unconfirmed" else "logout_unconfirmed_no_retry",503,true)
        if(localUnconfirmed||!runCatching{retryPendingSignOuts()}.getOrDefault(false))throw ApiFailure("logout_unconfirmed",503,true)
    }
    private fun requestOwned(witness:SessionWitness,method:String,path:String,body:JSONObject?=null,csv:Boolean=false,recoveryOrigin:String?=null):String{
        val requestGroup=authority.withCurrent(witness){groupId} // Do not dispatch with an already superseded session.
        try{
            val value=api.call(method,"/v1/burimunsi$path",witness.token,body,csv,recoveryOrigin,
                mapOf("groupId" to requestGroup,"generation" to witness.generation.toString()) +
                    (authority.withCurrent(witness){operator?.id}?.let{mapOf("actorId" to it)} ?: emptyMap()))
            return authority.withCurrent(witness){
                lastReadFromCache=false;lastReadSavedAt=System.currentTimeMillis();value
            }
        }catch(e:ApiFailure){
            // A malformed/truncated response after a passcode POST may hide a
            // committed rotation even when its HTTP status was 401. A separate
            // old-session request may also see 401 after that rotation commits.
            if(e.status in setOf(401,403)&&hasInflightPasscode(witness)&&
                (path!="/session/passcode"||e.uncertain)){
                authority.invalidateIfCurrent(witness,::clearMemoryOperator)
                throw ApiFailure("passcode_change_unconfirmed",503,true)
            }
            if((e.status==401||e.status==403&&path=="/session")&&!confirmedSessionDenial(e))
                throw ApiFailure("session_revalidation_unavailable",503,false)
            if(e.status==401&&confirmedSessionDenial(e))authority.invalidateIfCurrent(witness,::clearLocalOperator)
            throw e
        }
    }
    private fun request(method:String,path:String,body:JSONObject?=null,csv:Boolean=false):String=
        requestOwned(ownedSession(),method,path,body,csv)
    private fun query(values:Map<String,String?>)=values.filterValues{!it.isNullOrBlank()}.entries.joinToString("&",prefix="?"){(k,v)->URLEncoder.encode(k,"UTF-8")+"="+URLEncoder.encode(v,"UTF-8")}
    private fun records(path:String):String {
        val witness=ownedSession()
        val who=authority.withCurrent(witness){operator?:throw ApiFailure("session_unavailable",401)}
        if(System.currentTimeMillis()>=who.expiresAt)throw ApiFailure("session_unavailable",401)
        val sessionScope=Values.sha256(witness.token)
        try {
            val value=requestOwned(witness,"GET",path)
            return authority.withCurrent(witness){
                val now=System.currentTimeMillis()
                checkContract(now<who.expiresAt,"session_unavailable")
                lastReadFromCache=false;lastReadSavedAt=now
                try {
                    var cache=cacheStore.read()?.let(::JSONObject)
                    if(cache?.optString("sessionScope")!=sessionScope||cache?.optString("contractVersion")!=rw.ikanisa.wire.BuriMunsiSchemas.VERSION)cache=null
                    val entries=cache?.optJSONObject("entries")?:JSONObject()
                    entries.put(path,JSONObject().put("savedAt",now).put("payload",value))
                    while(entries.length()>8){val key=entries.keys().asSequence().minByOrNull{entries.getJSONObject(it).getLong("savedAt")}?:break;entries.remove(key)}
                    val saved=JSONObject().put("contractVersion",rw.ikanisa.wire.BuriMunsiSchemas.VERSION).put("groupId",groupId).put("accountId",who.id).put("sessionScope",sessionScope).put("entries",entries).toString()
                    if(saved.toByteArray(Charsets.UTF_8).size<=1_000_000)cacheStore.write(saved)
                }catch(_:Exception){/* Cache persistence cannot change the canonical response. */}
                value
            }
        }catch(error:ApiFailure){
            if(error.status!=0||error.code!="connection_unavailable")throw error
            return authority.withCurrent(witness){
                val now=System.currentTimeMillis()
                if(now>=who.expiresAt)throw ApiFailure("session_unavailable",401)
                val cache=try{cacheStore.read()?.let(::JSONObject)}catch(_:Exception){null}
                if(cache==null||cache.optString("contractVersion")!=rw.ikanisa.wire.BuriMunsiSchemas.VERSION||cache.optString("sessionScope")!=sessionScope||cache.optString("groupId")!=groupId||cache.optString("accountId")!=who.id)throw error
                val entry=cache.optJSONObject("entries")?.optJSONObject(path)?:throw error
                val saved=entry.getLong("savedAt");if(now<saved||now-saved>cacheTtlMs)throw error
                val payload=api.validateCached(path,entry.getString("payload"),mapOf("groupId" to groupId,"actorId" to who.id,"generation" to witness.generation.toString()))
                lastReadFromCache=true;lastReadSavedAt=saved;payload
            }
        }
    }
    fun home():Home{
        val j=JSONObject(records("/home"));val a=j.getJSONArray("recentPayments")
        return Home(j.amount("groupBalanceRwf"),j.amount("todayRwf"),j.getInt("memberCount"),j.getInt("unallocatedCount"),(0 until a.length()).map{decodePayment(a.getJSONObject(it))},j.getString("asOf"),if(j.has("unallocatedAmountRwf")&&!j.isNull("unallocatedAmountRwf"))j.amount("unallocatedAmountRwf")else null)
    }
    /** Full-query export collectors use online reads with one immutable local
     * identity witness. Server cursors independently bind group/actor/query and
     * data revision. Ordinary offline cache is deliberately unavailable here. */
    fun recordReadScope():RecordReadScope {
        val witness=ownedSession()
        val captured=authority.withCurrent(witness){
            val who=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(System.currentTimeMillis()<who.expiresAt&&!hasInflightPasscode(witness),"session_unavailable")
            Triple(groupId,who.id,who.role to who.capabilities.toSet())
        }
        val verify={authority.withCurrent(witness){
            val who=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(groupId==captured.first&&who.id==captured.second&&who.role==captured.third.first&&
                who.capabilities==captured.third.second&&System.currentTimeMillis()<who.expiresAt&&!hasInflightPasscode(witness),"session_changed")
        }}
        return RecordReadScope(recordReadOwner,verify){path->verify();requestOwned(witness,"GET",path)}
    }
    fun validateRecordReadScope(scope:RecordReadScope){scope.validate(recordReadOwner)}
    private fun listingRead(target:ListingTarget,path:String,scope:RecordReadScope?):String {
        if(target==ListingTarget.OBSERVATIONS)observationSession()
        return scope?.read(recordReadOwner,path)?:if(target in setOf(ListingTarget.PAYMENTS,ListingTarget.MEMBERS,ListingTarget.LEDGER,ListingTarget.HISTORY))records(path)else request("GET",path)
    }
    private fun listingPath(base:String,target:ListingTarget,listing:ListingQuery,cursor:String?,extra:Map<String,String?> = emptyMap(),limit:Int=100):String {
        checkContract(limit in 1..100,"invalid_query")
        return base+query(listing.queryValues(target)+extra+mapOf("cursor" to cursor,"limit" to limit.toString()))
    }
    fun payments(listing:ListingQuery,cursor:String?=null,memberId:String?=null,scope:RecordReadScope?=null):Page<Payment> {
        val member=memberId?.let(Values::id)
        val result=page(listingRead(ListingTarget.PAYMENTS,listingPath("/payments",ListingTarget.PAYMENTS,listing,cursor,mapOf("memberId" to member)),scope),::decodePayment)
        if(member!=null)checkContract(result.items.all{it.memberId==member},"invalid_member_payment_scope")
        return result
    }
    fun members(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<Member> =
        page(listingRead(ListingTarget.MEMBERS,listingPath("/members",ListingTarget.MEMBERS,listing,cursor),scope),::decodeMember)
    fun ledger(id:String,listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<LedgerRow> =
        page(listingRead(ListingTarget.LEDGER,listingPath("/ledger",ListingTarget.LEDGER,listing,cursor,mapOf("memberId" to Values.id(id))),scope),::decodeLedger)
    fun sms(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null,limit:Int=100):Page<SmsRow> =
        page(listingRead(ListingTarget.SMS,listingPath("/sms",ListingTarget.SMS,listing,cursor,limit=limit),scope),::decodeSms)
    fun staff(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<StaffAccount> =
        page(listingRead(ListingTarget.STAFF,listingPath("/staff",ListingTarget.STAFF,listing,cursor),scope),::decodeStaff)
    fun audit(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<AuditRow> =
        page(listingRead(ListingTarget.AUDIT,listingPath("/audit",ListingTarget.AUDIT,listing,cursor),scope)){j->AuditRow(j.getString("id"),j.getString("action"),j.getString("at"))}
    fun paymentHistory(id:String,listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<PaymentEvent> {
        val transactionId=Values.id(id)
        return decodePaymentHistory(listingRead(ListingTarget.HISTORY,listingPath("/payments/$transactionId/history",ListingTarget.HISTORY,listing,cursor),scope),groupId,transactionId)
    }
    fun payments(q:String="",filter:String="all",cursor:String?=null,memberId:String?=null):Page<Payment>{
        val member=memberId?.let(Values::id)
        val result=page(records("/payments"+query(mapOf("q" to q,"filter" to filter,"cursor" to cursor,"memberId" to member))),::decodePayment)
        if(member!=null)checkContract(result.items.all{it.memberId==member},"invalid_member_payment_scope")
        return result
    }
    fun members(q:String="",cursor:String?=null)=page(records("/members"+query(mapOf("q" to q,"cursor" to cursor))),::decodeMember)
    fun payment(id:String)=decodePayment(JSONObject(records("/payments/"+Values.id(id))))
    fun member(id:String)=decodeMember(JSONObject(records("/members/"+Values.id(id))))
    fun ledger(id:String,cursor:String?=null)=page(records("/ledger"+query(mapOf("memberId" to Values.id(id),"cursor" to cursor))),::decodeLedger)
    fun sms(q:String="",cursor:String?=null,filter:String="all",limit:Int?=null)=page(request("GET","/sms"+query(mapOf("q" to q,"cursor" to cursor,"filter" to filter,"limit" to limit?.coerceIn(1,100)?.toString()))),::decodeSms)
    private fun observationSession():SessionWitness {
        val witness=ownedSession()
        return authority.withCurrent(witness){
            val who=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(api.installationProfile=="internal_receiver"&&who.role==Role.ADMIN&&
                who.expiresAt>System.currentTimeMillis()&&
                setOf(Capability.SMS.key,Capability.GATEWAY.key).all{it in who.capabilities},"access_denied")
            witness
        }
    }
    fun observationProfile():JSONObject = JSONObject(requestOwned(observationSession(),"GET","/sms/observation-profile"))
    fun observationConsent():ObservationConsentRevision {
        val value=JSONObject(requestOwned(observationSession(),"GET","/sms/observation-consent"))
        return ObservationConsentRevision(value.getBoolean("enabled"),value.getLong("generation"))
    }
    fun setObservationConsent(revision:ObservationConsentRevision):ObservationConsentRevision {
        checkContract(revision.generation in 1..9_007_199_254_740_991L,"invalid_consent_generation")
        val body=JSONObject().put("enabled",revision.enabled).put("generation",revision.generation)
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observation-consent",body))
        val result=ObservationConsentRevision(value.getBoolean("enabled"),value.getLong("generation"))
        checkContract(result==revision,"invalid_consent_response")
        return result
    }
    private fun observationBody(observation:SmsObservation):JSONObject {
        val body=JSONObject().put("requestId",observation.requestId).put("rawSender",observation.rawSender)
            .put("rawBody",observation.rawBody).put("sourceMode",observation.sourceMode).put("complete",observation.complete)
            .put("capturedAt",observation.capturedAt).put("serviceCentreAt",observation.serviceCentreAt?:JSONObject.NULL)
            .put("inboxReceivedAt",observation.inboxReceivedAt?:JSONObject.NULL).put("subscriptionId",observation.subscriptionId?:JSONObject.NULL)
        observation.sourceKey?.let{body.put("sourceKey",it)}
        return body
    }
    fun submitObservation(observation:SmsObservation):ObservationAck {
        val body=observationBody(observation)
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations",body))
        val ack=ObservationAck(value.getString("requestId"),value.getString("sourceId"),value.getString("bodySha256"),
            value.getString("status"),value.getInt("financialEffects"))
        checkContract(ObservationAcknowledgement.matches(observation,ack),"invalid_observation_ack")
        return ack
    }
    /** Recovery retains a source on hold; it must not authorize processing or money movement. */
    fun recoverHeldObservation(observation:SmsObservation):HeldObservationAck {
        checkContract(observation.sourceMode=="catch_up"&&!observation.complete&&observation.inboxReceivedAt!=null&&
            observation.sourceKey?.let{Regex("[a-f0-9]{64}").matches(it)}==true,"invalid_observation_source")
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/recover-held",observationBody(observation)))
        val ack=ObservationAck(value.getString("requestId"),value.getString("sourceId"),value.getString("bodySha256"),
            value.getString("status"),value.getInt("financialEffects"))
        val processing=value.getString("autoProcessing")
        checkContract(processing=="held"&&ObservationAcknowledgement.matches(observation,ack),"invalid_observation_ack")
        return HeldObservationAck(ack,processing)
    }
    /** Compare only opaque identity and hashed SMS content; never disclose the body. */
    fun reconcileObservation(request:ObservationReconcileRequest):ObservationReconcileReply {
        checkContract(Regex("[a-f0-9]{64}").matches(request.sourceKey)&&Regex("[a-f0-9]{64}").matches(request.bodySha256),"invalid_observation_source")
        val body=JSONObject().put("sourceKey",request.sourceKey).put("bodySha256",request.bodySha256)
            .put("rawSender",request.rawSender).put("serviceCentreAt",request.serviceCentreAt?:JSONObject.NULL)
            .put("inboxReceivedAt",request.inboxReceivedAt).put("subscriptionId",request.subscriptionId?:JSONObject.NULL)
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/reconcile",body))
        val state=value.getString("state")
        val source=if(value.isNull("sourceId"))null else value.getString("sourceId")
        val newest=if(value.isNull("latestRecordedSourceId"))null else value.getString("latestRecordedSourceId")
        checkContract(value.getString("groupId")==groupId&&value.getString("sourceKey")==request.sourceKey&&
            state in setOf("matched","missing")&&(state=="matched")== (source!=null)&&
            (source==null||runCatching{Values.requestId(source)==source}.getOrDefault(false))&&
            (newest==null||runCatching{Values.requestId(newest)==newest}.getOrDefault(false)),"invalid_observation_reconciliation")
        return ObservationReconcileReply(request.sourceKey,state,source,newest)
    }
    /** Audit bounded phone witnesses without submitting SMS content or financial work. */
    fun reconcileObservations(requests:List<ObservationReconcileRequest>):List<ObservationReconcileReply> {
        checkContract(requests.size in 1..20&&requests.map{it.sourceKey}.toSet().size==requests.size,
            "invalid_observation_reconciliation")
        val items=JSONArray()
        for(request in requests){
            checkContract(Regex("[a-f0-9]{64}").matches(request.sourceKey)&&Regex("[a-f0-9]{64}").matches(request.bodySha256),
                "invalid_observation_source")
            items.put(JSONObject().put("sourceKey",request.sourceKey).put("bodySha256",request.bodySha256)
                .put("rawSender",request.rawSender).put("serviceCentreAt",request.serviceCentreAt?:JSONObject.NULL)
                .put("inboxReceivedAt",request.inboxReceivedAt).put("subscriptionId",request.subscriptionId?:JSONObject.NULL))
        }
        val body=JSONObject().put("items",items)
        checkContract(body.toString().toByteArray(Charsets.UTF_8).size<=8192,"invalid_observation_reconciliation")
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/reconcile-batch",body))
        val rows=value.getJSONArray("items")
        checkContract(value.getString("groupId")==groupId&&rows.length()==requests.size,"invalid_observation_reconciliation")
        return requests.mapIndexed{index,request->
            val row=rows.getJSONObject(index);val state=row.getString("state")
            val source=if(row.isNull("sourceId"))null else row.getString("sourceId")
            checkContract(row.getString("sourceKey")==request.sourceKey&&state in setOf("matched","missing")&&
                (state=="matched")== (source!=null)&&(source==null||runCatching{Values.requestId(source)==source}.getOrDefault(false)),
                "invalid_observation_reconciliation")
            ObservationReconcileReply(request.sourceKey,state,source,null)
        }
    }
    fun observationReconcileStatus():ObservationReconcileStatus {
        val value=JSONObject(requestOwned(observationSession(),"GET","/sms/observations/reconcile-status"))
        val count=value.getInt("recordedCount");val recorded=value.getBoolean("hasRecorded");val revision=value.getString("revision")
        checkContract(value.getString("groupId")==groupId&&count in 0..100_000&&recorded==(count>0)&&
            Regex("[a-f0-9]{64}").matches(revision),"invalid_observation_reconciliation")
        return ObservationReconcileStatus(value.getBoolean("hasPending"),recorded,count,revision,value.getBoolean("hasUnmatchedCanonical"))
    }
    /** This narrower status can gate recovery but cannot establish all-Cloud equality. */
    fun observationReconcileVerifiedStatus():ObservationVerifiedStatus {
        val value=JSONObject(requestOwned(observationSession(),"GET","/sms/observations/reconcile-verified-status"))
        val count=value.getInt("recordedCount");val recorded=value.getBoolean("hasRecorded");val revision=value.getString("revision")
        val scope=value.getString("scope")
        checkContract(value.getString("groupId")==groupId&&scope=="verified_collection"&&count in 0..100_000&&
            recorded==(count>0)&&Regex("[a-f0-9]{64}").matches(revision),"invalid_observation_reconciliation")
        return ObservationVerifiedStatus(scope,ObservationReconcileStatus(value.getBoolean("hasPending"),recorded,count,revision,
            value.getBoolean("hasUnmatchedCanonical")))
    }
    /** A quarantine page is a distinct source stream, never a canonical SMS/payment page. */
    fun observationPage(q:String="",cursor:String?=null,limit:Int?=null):Page<ObservationListRow> {
        val data=requestOwned(observationSession(),"GET","/sms/observations"+query(mapOf("q" to q,"cursor" to cursor,"limit" to limit?.coerceIn(1,100)?.toString())))
        return decodeObservationPage(data)
    }
    fun observationPage(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null,limit:Int=100):Page<ObservationListRow> =
        decodeObservationPage(listingRead(ListingTarget.OBSERVATIONS,listingPath("/sms/observations",ListingTarget.OBSERVATIONS,listing,cursor,limit=limit),scope))
    private fun decodeObservationPage(data:String):Page<ObservationListRow> =
        page(data){row->
            checkedDto("observationPageItem",row)
            checkContract(row.getString("sourceKind")=="observation"&&row.getString("id")==row.getString("sourceId")&&
                row.getString("groupId")==groupId&&row.getString("status")=="source_unresolved"&&row.counter("financialEffects")==0L,"invalid_observation_source")
            ObservationListRow(SmsSourceRef.Observation(Values.id(row.getString("sourceId"))),groupId,row.getString("at"))
        }
    fun observationProcessing(sources:List<SmsSourceRef.Observation>):Map<SmsSourceRef.Observation,ObservationProcessing>{
        checkContract(sources.isNotEmpty()&&sources.size<=100&&sources.distinct().size==sources.size,"invalid_observation_source")
        val ids=JSONArray();sources.forEach{ids.put(Values.id(it.id))}
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/processing-status",JSONObject().put("sourceIds",ids)))
        val rows=value.getJSONArray("statuses")
        checkContract(value.getString("groupId")==groupId&&rows.length()==sources.size,"invalid_observation_source")
        return sources.mapIndexed{index,source->
            val row=rows.getJSONObject(index);val status=row.getString("status");val retry=row.getBoolean("canRetry")
            checkContract(row.getString("sourceId")==source.id&&status in setOf("pending","retrying","parsed","needs_review","conflict","duplicate","security","historical","unknown")&&
                (!retry||status in setOf("retrying","needs_review")),"invalid_observation_source")
            source to ObservationProcessing(status,retry)
        }.toMap()
    }
    fun retryObservation(source:SmsSourceRef.Observation,requestId:String):String{
        val id=Values.id(source.id)
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/$id/retry",JSONObject().put("requestId",requestId)))
        checkContract(value.getString("groupId")==groupId&&value.getString("sourceId")==id&&value.getString("requestId")==requestId&&
            value.getString("result") in setOf("scheduled","not_eligible"),"invalid_observation_source")
        return value.getString("result")
    }
    /** Only an explicitly typed observation can use this audited disclosure path. */
    fun revealObservation(source:SmsSourceRef.Observation,reason:String):ObservationDisclosure {
        val normalized=RawDisclosureInput.reason(reason)?:throw ApiFailure("reason_required",400)
        val id=Values.id(source.id)
        val row=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/$id/reveal",JSONObject().put("reason",normalized).put("displayHintsVersion",1)))
        checkedDto("observationReveal.data",row)
        checkContract(row.getString("sourceKind")=="observation"&&row.getString("sourceId")==id&&row.getString("groupId")==groupId&&
            row.getString("status")=="source_unresolved"&&row.counter("financialEffects")==0L,"invalid_observation_source")
        checkContract(row.has("displayHints"),"invalid_observation_source")
        val body=row.getString("rawBody")
        val hints=if(row.isNull("displayHints"))null else row.getJSONObject("displayHints").let{h->
            val values=h.getJSONArray("hints")
            ObservationHintSet(h.getInt("schemaVersion"),h.getString("kind"),h.getString("profileVersion"),h.getString("profileSha256"),h.getString("bodySha256"),
                (0 until values.length()).map{index->val v=values.getJSONObject(index);ObservationHint(v.getString("kind"),v.getString("text"),v.getInt("start"),v.getInt("end"))})
        }
        checkContract(hints==null||ObservationHintValidation.valid(body,hints),"invalid_observation_source")
        return ObservationDisclosure(source,row.getString("at"),row.getString("sender"),body,hints)
    }
    /** Audited, explicit disclosure only. Never cache/journal the reason or body. */
    fun raw(id:String,reason:String):RawSms{
        val normalized=RawDisclosureInput.reason(reason)?:throw ApiFailure("reason_required",400)
        val witness=ownedSession()
        val j=JSONObject(requestOwned(witness,"POST","/sms/"+Values.id(id)+"/reveal",JSONObject().put("reason",normalized)))
        return RawSms(j.getString("id"),j.getString("sender"),j.getString("at"),j.getString("rawBody"),j.nullString("transactionId"),j.optionalNullString("simLabel"))
    }
    fun staff(cursor:String?=null)=page(request("GET","/staff"+query(mapOf("cursor" to cursor))),::decodeStaff)
    fun audit(cursor:String?=null)=page(request("GET","/audit"+query(mapOf("cursor" to cursor)))){j->AuditRow(j.getString("id"),j.getString("action"),j.getString("at"))}
    fun paymentHistory(id:String,cursor:String?=null):Page<PaymentEvent> {
        val transactionId=Values.id(id)
        return decodePaymentHistory(records("/payments/$transactionId/history"+query(mapOf("cursor" to cursor))),groupId,transactionId)
    }
    fun exportMember(id:String)=request("GET","/members/"+Values.id(id)+"/ledger.csv",csv=true)
    fun allocate(p:Payment,member:Member,note:String):JSONObject {
        checkContract(PaymentPresentation.canAllocate(p)&&member.active,"allocation_unavailable")
        checkContract(Presentation.validNote(note),"invalid_note")
        return mutate("POST","/payments/${Values.id(p.id)}/allocate",JSONObject().put("memberId",member.id).put("expectedVersion",p.version).put("note",note.trim()))
    }
    fun enroll(name:String,phone:String)=mutate("POST","/members",JSONObject().put("name",name.trim()).put("phone",Values.phone(phone)))
    fun onboardingSuggestions(q:String,cursor:String?):JSONObject = JSONObject(request("GET","/members/suggestions"+
        query(mapOf("q" to q,"cursor" to cursor,"limit" to "40"))))
    fun onboardingPreview(mimeType:String,bytes:ByteArray,consent:Boolean):JSONObject {
        checkContract(bytes.isNotEmpty()&&bytes.size<=5*1024*1024,"smart_import_size_invalid")
        val encoded=Base64.getEncoder().encodeToString(bytes)
        return try{JSONObject(request("POST","/members/import/preview",JSONObject().put("mimeType",mimeType)
            .put("fileBytes",encoded).put("externalOcrConsent",consent)))}catch(e:ApiFailure){
            if(e.uncertain)throw ApiFailure("smart_import_preview_unconfirmed",e.status,false)
            throw e
        }
    }
    fun onboardingImport(rows:JSONArray):JSONObject {
        checkContract(rows.length() in 1..500,"invalid_import")
        val body=JSONObject().put("rows",rows)
        // Validate before creating the durable dispatch journal. A request that
        // cannot fit the wire limit must never strand an unsent command as SENT.
        val sized=JSONObject(body.toString()).put("requestId","00000000-0000-4000-8000-000000000000")
        checkContract(sized.toString().toByteArray(Charsets.UTF_8).size<=SmartOnboardingLimits.MAX_BATCH_BYTES,"smart_import_size_invalid")
        return mutate("POST","/members/import",body)
    }
    fun setMemberActive(m:Member,active:Boolean)=mutate("PATCH","/members/${Values.id(m.id)}",JSONObject().put("active",active).put("expectedVersion",m.version))
    fun staffAction(body:JSONObject,resolveBlankPhoneDenial:Boolean=false)=mutate(if(body.getString("action")=="create")"POST" else "PATCH","/staff",JSONObject(body.toString()),resolveBlankPhoneDenial)
    fun changePin(current:String,next:String,confirm:String):Operator{
        val currentPin=Values.pin(current);val newPin=Values.pin(next);Values.pin(confirm)
        checkContract(newPin==confirm,"passcodes_do_not_match")
        checkContract(currentPin!=newPin,"passcode_unchanged")
        val witness=ownedSession()
        val candidate=ByteArray(32).also{SecureRandom().nextBytes(it)}.joinToString(""){"%02x".format(it.toInt() and 255)}
        val owner=authority.withCurrent(witness){
            val who=operator?:throw ApiFailure("session_unavailable",401)
            val saved=JSONObject(sessionStore.read()?:throw ContractFailure("session_changed"))
            checkContract(saved.getString("token")==witness.token&&saved.getString("groupId")==groupId&&
                saved.getJSONObject("profile").getString("id")==who.id&&saved.optJSONObject("pendingPasscode")==null,"session_changed")
            saved.put("pendingPasscode",JSONObject().put("token",candidate).put("state","prepared"));saveSession(saved)
            who.id
        }
        authority.withCurrent(witness){
            val saved=pendingSession(witness,candidate)
            saved.getJSONObject("pendingPasscode").put("state","inflight");saveSession(saved)
        }
        val body=JSONObject().put("current",currentPin).put("newPin",newPin).put("confirm",confirm).put("replacementToken",candidate)
        val reply=try{requestOwned(witness,"POST","/session/passcode",body)}catch(e:ApiFailure){
            if(!e.uncertain&&(e.status==0||e.status in 400..499&&e.status !in setOf(408,425,429))){
                // A definite rejection cannot have changed the PIN.
                runCatching{authority.withCurrent(witness){val saved=pendingSession(witness,candidate);saved.remove("pendingPasscode");saveSession(saved)}}
                throw e
            }
            // Preserve the candidate durably and disable old in-memory authority.
            // Recovery checks the candidate, and never repeats the PIN change.
            authority.invalidateIfCurrent(witness,::clearMemoryOperator)
            throw ApiFailure("passcode_change_unconfirmed",503,true)
        }catch(e:ContractFailure){
            // A concurrent old-session 401 may have retired this witness while
            // the server was committing the passcode change. Logout, by
            // contrast, removes the saved pending record and must stay final.
            if(e.code=="session_changed"&&hasInflightPasscode(witness))throw ApiFailure("passcode_change_unconfirmed",503,true)
            throw e
        }
        try{
            val value=JSONObject(reply)
            checkContract(value.getBoolean("reauthenticationRequired")==false,"invalid_api_response")
            val expiry=value.getLong("expiresAt")
            val saved=authority.withCurrent(witness){pendingSession(witness,candidate)}
            return installPasscodeSession(witness,candidate,saved.getJSONObject("profile"),expiry,owner)
        }catch(e:ContractFailure){
            if(e.code=="session_changed")throw e
            authority.invalidateIfCurrent(witness,::clearMemoryOperator)
            throw ApiFailure("passcode_change_unconfirmed",503,true)
        }catch(_:Exception){
            authority.invalidateIfCurrent(witness,::clearMemoryOperator)
            throw ApiFailure("passcode_change_unconfirmed",503,true)
        }
    }
    private fun mutate(method:String,path:String,body:JSONObject,resolveBlankPhoneDenial:Boolean=false):JSONObject{
        if(resolveBlankPhoneDenial)checkContract(path=="/staff"&&method=="PATCH"&&body.optString("action")=="edit"&&
            !body.has("pin")&&body.has("phone")&&body.has("id")&&body.has("expectedVersion"),"invalid_staff_command")
        val witness=ownedSession()
        // A staff PIN is required for the first dispatch only. Persist a redacted
        // intent, never the PIN or a digest derived from it. If the process dies
        // before dispatch, this intent cannot be resent without new authority.
        val transientPin=if(path=="/staff"&&body.has("pin")){
            checkContract(method in setOf("POST","PATCH")&&body.optString("action") in setOf("create","edit","reset"),"invalid_staff_command")
            val value=body.get("pin")
            checkContract(value is String,"invalid_passcode")
            Values.pin(value as String)
        }else null
        val savedBody=if(transientPin==null)body else JSONObject(body.toString()).also{it.remove("pin")}
        val envelope=JSONObject().put("method",method).put("path",path).put("body",savedBody)
        if(transientPin!=null)envelope.put("credentialOmitted",true)
        val payload=envelope.toString()
        val operation=synchronized(commandPreparationLock){authority.withCurrent(witness){
            checkContract(!hasPendingReceiverRetirement(),"gateway_retirement_unconfirmed")
            val owner=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(owner.expiresAt>System.currentTimeMillis(),"session_unavailable")
            journal.prepare(Values.sha256(witness.token),method+" "+path,payload,owner.id,groupId)
        }}
        return sendPending(operation,transientPin,resolveBlankPhoneDenial)
    }
    fun pending()=journal.unresolved()
    /** Check the original outcome. A manual staff check may close an uncommitted
     * request under the server's staff mutation lock; it never resends the command. */
    fun reconcilePending():JSONObject {
        val op=journal.unresolved()?:throw ApiFailure("no_pending_operation")
        val witness=ownedSession()
        return journal.withRecoveryRead(op){reconcileOwned(op,witness,resolveStaff=true)}
    }
    /** Opt-in bounded read-only cycle. nowMs is a nonnegative monotonic admission
     * tick, not wall-clock time. Backoff here is admission-to-admission. No automatic
     * scheduler is installed; the UI/manual API above remains available. Exhaustion
     * never clears the financial journal. The caller retains the same controller. */
    fun reconcilePending(retry:ReadOnlyRecoveryRetry,nowMs:Long):JSONObject {
        val op=journal.unresolved()?:throw ApiFailure("no_pending_operation")
        val witness=ownedSession()
        return journal.withRecoveryRead(op){
            // Busy denial consumes no retry slot, and session changes are not a reset.
            val ticket=retry.begin(op,RecoveryReadScope(witness.generation,Values.sha256(witness.token)),nowMs)
            val status=try{reconcileOwned(op,witness)}catch(e:Exception){
                retry.finish(ticket,recoveryReadFailure(e),nowMs)
                throw e
            }
            retry.finish(ticket,if(status.getString("state") in setOf("committed","cancelled")) RecoveryReadResult.RESOLVED
                else RecoveryReadResult.PENDING,nowMs)
            status
        }
    }
    private fun recoveryReadFailure(error:Exception):RecoveryReadResult=when(error){
        is ApiFailure->when{
            error.status==401->RecoveryReadResult.AUTH_REQUIRED
            error.status==403->RecoveryReadResult.DENIED
            error.code=="invalid_api_response"||error.code.startsWith("contract_")->RecoveryReadResult.INVALID_RESPONSE
            error.status==0&&error.code=="connection_unavailable"->RecoveryReadResult.TRANSIENT_FAILURE
            error.status==429||error.status in 500..599->RecoveryReadResult.TRANSIENT_FAILURE
            else->RecoveryReadResult.INVALID_RESPONSE
        }
        is ContractFailure->when(error.code){
            "session_changed","session_unavailable"->RecoveryReadResult.AUTH_REQUIRED
            "operation_identity_changed","operation_changed","operation_attempt_changed",
            "conflicting_reconciliation","corrupt_operation","missing_operation"->RecoveryReadResult.CONFLICT
            "record_cache_unavailable","operation_store_unavailable"->RecoveryReadResult.CLEANUP_FAILED
            else->RecoveryReadResult.INVALID_RESPONSE
        }
        is InterruptedException->RecoveryReadResult.CANCELLED
        else->RecoveryReadResult.INVALID_RESPONSE // Unknown failure is not permission to keep polling.
    }
    private fun reconcileOwned(op:PendingOperation,witness:SessionWitness,resolveStaff:Boolean=false):JSONObject {
        var status=readAuthoritativeOutcome(op,witness)
        if(resolveStaff&&status.getString("state")=="pending"&&operationName(op) in setOf(
                "burimunsi.staff.create","burimunsi.staff.edit","burimunsi.staff.reset",
                "burimunsi.staff.disable","burimunsi.staff.enable","burimunsi.staff.remove")){
            val who=assertOutcomeReader(op,witness)
            val raw=requestOwned(witness,"POST","/operations/"+Values.requestId(op.requestId)+"/staff-resolution",
                JSONObject().put("operation",operationName(op)),recoveryOrigin=op.sessionScope)
            val resolved=authority.withCurrent(witness){
                assertOutcomeReader(op,witness)
                decodeRecoveryOutcome(raw,op.requestId,op.sessionScope,groupId,who.id,api.installationId)
            }
            checkContract(resolved.getString("state") in setOf("committed","cancelled"),"invalid_api_response")
            if(resolved.getString("state")=="cancelled")
                checkContract(resolved.optString("operation")==operationName(op),"invalid_api_response")
            // A committed acknowledgement is verified through the ordinary
            // original proof and canonical command outcome before cleanup.
            status=if(resolved.getString("state")=="committed")readAuthoritativeOutcome(op,witness)else resolved
        }
        return authority.withCurrent(witness){
            when(status.getString("state")){
                "committed"->{journal.reconcile(op,OperationState.COMMITTED);journal.finishCleanup(op,::invalidateRecordsForCommit)}
                "cancelled"->{journal.reconcile(op,OperationState.REJECTED);journal.finishCleanup(op,::invalidateRecordsForCommit)}
                "pending"->journal.observePending(op) // Never downgrade a retained proof or resend.
                else->throw ApiFailure("invalid_api_response")
            }
            status
        }
    }
    /** The only allowed direct send is a durable PREPARED command that has
     * never begun a dispatch. SENT/UNKNOWN are never retried on the client. */
    fun retryPending():JSONObject {
        val op=journal.unresolved()?:throw ApiFailure("no_pending_operation")
        checkContract(op.state==OperationState.PREPARED&&op.attemptCount==0,"pending_operation_requires_resolution")
        checkContract(op.sessionScope==Values.sha256(ownedSession().token),"pending_operation_requires_resolution")
        // Neither redacted nor legacy staff credential intents may be resent from
        // durable storage. Their original outcome is checked through read-only recovery.
        val saved=JSONObject(op.body)
        checkContract(!saved.has("credentialOmitted")&&
            !(saved.optString("path")=="/staff"&&saved.getJSONObject("body").has("pin")),"pending_operation_requires_resolution")
        return sendPending(op)
    }
    private fun assertOutcomeReader(op:PendingOperation,witness:SessionWitness):Operator = authority.withCurrent(witness){
        val who=operator?:throw ApiFailure("session_unavailable",401)
        checkContract(who.expiresAt>System.currentTimeMillis(),"session_unavailable")
        // Legacy journals have no local owner fields. Only the server's original
        // v1 proof can establish principal, installation and grant continuity.
        checkContract((op.ownerAccountId==null)==(op.groupId==null),"invalid_api_response")
        if(op.ownerAccountId!=null)checkContract(op.ownerAccountId==who.id&&op.groupId==groupId,"pending_operation_requires_resolution")
        who
    }
    private fun operationName(op:PendingOperation):String {
        val j=JSONObject(op.body);val path=j.getString("path")
        return when {
            path.startsWith("/payments/")&&path.endsWith("/allocate")->"burimunsi.allocate"
            path=="/members"->"burimunsi.enroll"
            path=="/members/import"->"burimunsi.members_import"
            path.startsWith("/members/")->"burimunsi.membership"
            path=="/staff"->"burimunsi.staff."+j.getJSONObject("body").getString("action")
            else->throw ApiFailure("invalid_api_response")
        }
    }
    private fun readAuthoritativeOutcome(op:PendingOperation,witness:SessionWitness):JSONObject {
        val who=assertOutcomeReader(op,witness)
        val path="/operations/"+Values.requestId(op.requestId)
        val raw=requestOwned(witness,"GET",path+"/recovery",recoveryOrigin=op.sessionScope)
        val proof=authority.withCurrent(witness){
            assertOutcomeReader(op,witness)
            decodeRecoveryOutcome(raw,op.requestId,op.sessionScope,groupId,who.id,api.installationId)
        }
        if(proof.getString("state")=="pending")return proof
        if(proof.getString("state")=="cancelled"){
            checkContract(proof.optString("operation")==operationName(op),"invalid_api_response")
            return proof
        }
        // Proof v1 authenticates the original command; status v2 reports its
        // current economic effect. Neither substitutes for the other. These are
        // separate primary snapshots, not an atomic cross-request transaction.
        val status=JSONObject(requestOwned(witness,"GET",path))
        return authority.withCurrent(witness){
            assertOutcomeReader(op,witness)
            checkContract(status.keys().asSequence().toSet()==setOf("contractVersion","requestId","groupId","actorId","state","operation","financialState"),"invalid_api_response")
            checkContract(status.counter("contractVersion",2)==2L&&status.get("requestId")==op.requestId&&
                status.get("groupId")==groupId&&status.get("actorId")==who.id&&status.get("state")=="committed"&&
                status.get("operation")==operationName(op),"invalid_api_response")
            val effect=status.get("financialState")
            checkContract(if(operationName(op)=="burimunsi.allocate")effect in setOf("posted","reversed","corrected") else effect=="not_applicable","invalid_api_response")
            proof.put("financialState",effect).put("operation",operationName(op)).put("contractVersion",2)
        }
    }
    /** Do not open the next-command gate while stale financial cache survives.
     * A storage failure leaves the same original operation available for another
     * read-only outcome check, never a second dispatch. */
    private fun invalidateRecordsForCommit(){
        cacheStore.clear()
        checkContract(cacheStore.read()==null,"record_cache_unavailable")
    }
    private fun sendPending(op:PendingOperation,transientPin:String?=null,resolveBlankPhoneDenial:Boolean=false):JSONObject{
        val j=JSONObject(op.body);val body=j.getJSONObject("body").put("requestId",op.requestId)
        val omitted=j.has("credentialOmitted")
        if(omitted){
            checkContract(j.get("credentialOmitted")==true&&j.getString("path")=="/staff"&&
                j.getString("method") in setOf("POST","PATCH")&&body.optString("action") in setOf("create","edit","reset")&&
                !body.has("pin")&&transientPin!=null,"pending_operation_requires_resolution")
            body.put("pin",Values.pin(transientPin!!))
        }else checkContract(transientPin==null,"pending_operation_requires_resolution")
        val witness=ownedSession()
        checkContract(op.sessionScope==Values.sha256(witness.token),"pending_operation_requires_resolution")
        val attempt=authority.withCurrent(witness){assertOutcomeReader(op,witness);journal.beginAttempt(op,op.sessionScope)}
        var submitted=false
        try{
            // A successful transport/JSON response is not a canonical financial
            // outcome. Check the retained server-side request receipt before
            // marking a contribution, enrollment or staff change complete.
            val acknowledgement=JSONObject(requestOwned(witness,j.getString("method"),j.getString("path"),body))
            submitted=true
            return journal.withRecoveryRead(op){
                val outcome=readAuthoritativeOutcome(op,witness)
                authority.withCurrent(witness){
                    when(outcome.getString("state")){
                        "committed"->{
                            journal.completeAttempt(attempt)
                            journal.finishCleanup(op,::invalidateRecordsForCommit)
                            if(outcome.optString("financialState") in setOf("reversed","corrected"))
                                throw ApiFailure("operation_financially_changed",409,false)
                            // The enrollment POST returns the new member ID, but it
                            // is usable only after the original command has also
                            // passed both authoritative readbacks and cleanup.
                            // A missing or foreign-scope acknowledgement never
                            // supplies an ID and never causes a second POST.
                            if(operationName(op)=="burimunsi.enroll")
                                outcome.put("createdMemberId",if(acknowledgement.optString("groupId")==groupId)acknowledgement.optString("id") else "")
                            if(operationName(op)=="burimunsi.members_import")outcome.put("importResult",acknowledgement)
                            outcome
                        }
                        "pending"->{journal.observePending(op);throw ApiFailure("operation_still_pending",409,true)}
                        else->throw ApiFailure("invalid_api_response",503,true)
                    }
                }
            }
        }catch(e:ApiFailure){
            try{journal.failAttempt(attempt,e.status,e.uncertain||submitted)}catch(_:ContractFailure){/* A newer attempt/reconciliation owns the journal. */}
            val denied=resolveBlankPhoneDenial&&!submitted&&!e.uncertain&&when(e.code){
                "access_denied"->e.status==403
                "new_passcode_required"->e.status==400
                "duplicate_phone"->e.status==409
                else->false
            }
            if(denied){
                // Resolve this exact original request under the server's staff
                // mutation lock; never resend the edit or a credential. A failed
                // recovery retains the journal and propagates the actual error.
                val outcome=journal.withRecoveryRead(op){reconcileOwned(op,witness,resolveStaff=true)}
                if(outcome.getString("state")=="committed")return outcome
            }
            throw e
        }catch(e:Exception){
            try{journal.failAttempt(attempt,0,true)}catch(_:ContractFailure){}
            throw e
        }finally{if(omitted)body.remove("pin")}
    }
}
