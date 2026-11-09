package rw.ikanisa.burimunsi.data

import android.content.Context
import org.json.JSONObject
import org.json.JSONArray
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.*
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/** API data is the authority. No local SMS-to-balance arithmetic and no demo accounts. */
class NativeRepository(context:Context,private val api:ApiClient,private val groupId:String){
    private val sessionStore=SecureStore(context,"session")
    private val cacheStore=SecureStore(context,"records")
    private val journal=OperationJournal(AndroidOperationStore(context))
    private val authority=SessionAuthority()
    @Volatile private var operator:Operator?=null
    var lastReadSavedAt:Long?=null;private set
    var lastReadFromCache=false;private set
    private val cacheTtlMs=SnapshotFreshness.TTL_MS
    private fun clearLocalOperator(){operator=null;sessionStore.clear();cacheStore.clear();lastReadFromCache=false;lastReadSavedAt=null}
    fun restore():Operator?{
        var stored:String?=null
        val ticket=authority.beginReplacement{stored=sessionStore.read();clearLocalOperator()}
        val saved=stored?:return null
        val j=try{JSONObject(saved)}catch(_:Exception){return null}
        val valid=runCatching{j.getString("groupId")==groupId&&j.getLong("expiresAt")>System.currentTimeMillis()&&Regex("[a-f0-9]{64}").matches(j.getString("token"))}.getOrDefault(false)
        if(!valid)return null
        authority.install(ticket,j.getString("token")){sessionStore.write(saved)}
        val restored=authority.capture()
        return try{refreshSession()}catch(e:Exception){
            // A restored token is not authority until the server revalidates it.
            authority.invalidateIfCurrent(restored,::clearLocalOperator)
            throw e
        }
    }
    fun login(phone:String,pin:String):Operator {
        val normalizedPhone=Values.phone(phone);val normalizedPin=Values.pin(pin)
        val ticket=authority.beginReplacement(::clearLocalOperator)
        val j=JSONObject(api.call("POST","/v1/burimunsi/session/login",body=JSONObject().put("phone",normalizedPhone).put("pin",normalizedPin),contractContext=mapOf("groupId" to groupId,"generation" to ticket.toString())))
        val expiry=j.getLong("expiresAt");check(expiry>System.currentTimeMillis())
        val t=j.getString("token");check(Regex("[a-f0-9]{64}").matches(t))
        val profile=operator(j.getJSONObject("profile"),expiry)
        authority.install(ticket,t){
            sessionStore.write(JSONObject().put("token",t).put("groupId",groupId).put("expiresAt",expiry).put("profile",j.getJSONObject("profile")).toString())
            cacheStore.clear();operator=profile;lastReadFromCache=false;lastReadSavedAt=System.currentTimeMillis()
        }
        return profile
    }
    fun refreshSession():Operator {
        val witness=authority.capture()
        val j=JSONObject(requestOwned(witness,"GET","/session"))
        return authority.withCurrent(witness){
            val profile=operator(j.getJSONObject("profile"),j.getLong("expiresAt"))
            val prior=operator
            if(profile.expiresAt<=System.currentTimeMillis()||(prior!=null&&prior.id!=profile.id)){
                authority.invalidateIfCurrent(witness,::clearLocalOperator)
                throw ContractFailure("session_changed")
            }
            lastReadFromCache=false;lastReadSavedAt=System.currentTimeMillis()
            operator=profile;profile
        }
    }
    fun current()=operator
    fun clearOperator(){authority.beginReplacement(::clearLocalOperator) /* NEVER touches receiving queue or gateway grants. */}
    fun logout(){
        val witness=authority.capture()
        try{requestOwned(witness,"POST","/session/logout",JSONObject())}
        finally{authority.invalidateIfCurrent(witness,::clearLocalOperator)}
    }
    private fun requestOwned(witness:SessionWitness,method:String,path:String,body:JSONObject?=null,csv:Boolean=false,recoveryOrigin:String?=null):String{
        authority.withCurrent(witness){} // Do not dispatch with an already superseded session.
        try{
            val value=api.call(method,"/v1/burimunsi$path",witness.token,body,csv,recoveryOrigin,
                mapOf("groupId" to groupId,"generation" to witness.generation.toString()) +
                    (authority.withCurrent(witness){operator?.id}?.let{mapOf("actorId" to it)} ?: emptyMap()))
            return authority.withCurrent(witness){
                lastReadFromCache=false;lastReadSavedAt=System.currentTimeMillis();value
            }
        }catch(e:ApiFailure){
            if(e.status==401)authority.invalidateIfCurrent(witness,::clearLocalOperator)
            throw e
        }
    }
    private fun request(method:String,path:String,body:JSONObject?=null,csv:Boolean=false):String=
        requestOwned(authority.capture(),method,path,body,csv)
    private fun query(values:Map<String,String?>)=values.filterValues{!it.isNullOrBlank()}.entries.joinToString("&",prefix="?"){(k,v)->URLEncoder.encode(k,"UTF-8")+"="+URLEncoder.encode(v,"UTF-8")}
    private fun records(path:String):String {
        val witness=authority.capture()
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
        return Home(j.amount("groupBalanceRwf"),j.amount("todayRwf"),j.getInt("memberCount"),j.getInt("unallocatedCount"),(0 until a.length()).map{decodePayment(a.getJSONObject(it))},j.getString("asOf"))
    }
    fun payments(q:String="",filter:String="all",cursor:String?=null)=page(records("/payments"+query(mapOf("q" to q,"filter" to filter,"cursor" to cursor))),::decodePayment)
    fun members(q:String="",cursor:String?=null)=page(records("/members"+query(mapOf("q" to q,"cursor" to cursor))),::decodeMember)
    fun payment(id:String)=decodePayment(JSONObject(records("/payments/"+Values.id(id))))
    fun member(id:String)=decodeMember(JSONObject(records("/members/"+Values.id(id))))
    fun ledger(id:String,cursor:String?=null)=page(records("/ledger"+query(mapOf("memberId" to Values.id(id),"cursor" to cursor))),::decodeLedger)
    fun sms(q:String="",cursor:String?=null,filter:String="all")=page(request("GET","/sms"+query(mapOf("q" to q,"cursor" to cursor,"filter" to filter))),::decodeSms)
    fun raw(id:String):RawSms{val j=JSONObject(request("GET","/sms/"+Values.id(id)));return RawSms(j.getString("id"),j.getString("sender"),j.getString("at"),j.getString("rawBody"),j.nullString("transactionId"))}
    fun staff(cursor:String?=null)=page(request("GET","/staff"+query(mapOf("cursor" to cursor))),::decodeStaff)
    fun audit(cursor:String?=null)=page(request("GET","/audit"+query(mapOf("cursor" to cursor)))){j->AuditRow(j.getString("id"),j.getString("action"),j.getString("at"))}
    fun paymentHistory(id:String,cursor:String?=null):Page<PaymentEvent> {
        val transactionId=Values.id(id)
        return decodePaymentHistory(records("/payments/$transactionId/history"+query(mapOf("cursor" to cursor))),groupId,transactionId)
    }
    fun exportMember(id:String)=request("GET","/members/"+Values.id(id)+"/ledger.csv",csv=true)
    fun allocate(p:Payment,member:Member,note:String):JSONObject {
        checkContract(Presentation.payment(p.state).canAllocate&&member.active,"allocation_unavailable")
        checkContract(Presentation.validNote(note),"invalid_note")
        return mutate("POST","/payments/${Values.id(p.id)}/allocate",JSONObject().put("memberId",member.id).put("expectedVersion",p.version).put("note",note.trim()))
    }
    fun enroll(name:String,phone:String)=mutate("POST","/members",JSONObject().put("name",name.trim()).put("phone",Values.phone(phone)))
    fun setMemberActive(m:Member,active:Boolean)=mutate("PATCH","/members/${Values.id(m.id)}",JSONObject().put("active",active).put("expectedVersion",m.version))
    fun staffAction(body:JSONObject)=mutate(if(body.getString("action")=="create")"POST" else "PATCH","/staff",JSONObject(body.toString()))
    fun changePin(current:String,next:String,confirm:String){
        checkContract(next==confirm,"passcodes_do_not_match")
        val body=JSONObject().put("current",Values.pin(current)).put("newPin",Values.pin(next)).put("confirm",Values.pin(confirm))
        val witness=authority.capture()
        // A lost response may have changed the passcode. Never replay automatically.
        try{requestOwned(witness,"POST","/session/passcode",body)}
        finally{authority.invalidateIfCurrent(witness,::clearLocalOperator)}
    }
    private fun mutate(method:String,path:String,body:JSONObject):JSONObject{
        val witness=authority.capture()
        val payload=JSONObject().put("method",method).put("path",path).put("body",body).toString()
        val operation=authority.withCurrent(witness){
            val owner=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(owner.expiresAt>System.currentTimeMillis(),"session_unavailable")
            journal.prepare(Values.sha256(witness.token),method+" "+path,payload,owner.id,groupId)
        }
        return sendPending(operation)
    }
    fun pending()=journal.unresolved()
    /** Read-only recovery. Backend proves original/current principal, operator,
     * group, installation and grant continuity; old digest is not authentication. */
    fun reconcilePending():JSONObject {
        val op=journal.unresolved()?:throw ApiFailure("no_pending_operation")
        val witness=authority.capture()
        return journal.withRecoveryRead(op){reconcileOwned(op,witness)}
    }
    /** Opt-in bounded read-only cycle. nowMs is a nonnegative monotonic admission
     * tick, not wall-clock time. Backoff here is admission-to-admission. No automatic
     * scheduler is installed; the UI/manual API above remains available. Exhaustion
     * never clears the financial journal. The caller retains the same controller. */
    fun reconcilePending(retry:ReadOnlyRecoveryRetry,nowMs:Long):JSONObject {
        val op=journal.unresolved()?:throw ApiFailure("no_pending_operation")
        val witness=authority.capture()
        return journal.withRecoveryRead(op){
            // Busy denial consumes no retry slot, and session changes are not a reset.
            val ticket=retry.begin(op,RecoveryReadScope(witness.generation,Values.sha256(witness.token)),nowMs)
            val status=try{reconcileOwned(op,witness)}catch(e:Exception){
                retry.finish(ticket,recoveryReadFailure(e),nowMs)
                throw e
            }
            retry.finish(ticket,if(status.getString("state")=="committed") RecoveryReadResult.RESOLVED
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
    private fun reconcileOwned(op:PendingOperation,witness:SessionWitness):JSONObject {
        val status=readAuthoritativeOutcome(op,witness)
        return authority.withCurrent(witness){
            when(status.getString("state")){
                "committed"->{journal.reconcile(op,OperationState.COMMITTED);journal.finishCleanup(op,::invalidateRecordsForCommit)}
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
        checkContract(op.sessionScope==Values.sha256(authority.capture().token),"pending_operation_requires_resolution")
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
    private fun sendPending(op:PendingOperation):JSONObject{
        val j=JSONObject(op.body);val body=j.getJSONObject("body").put("requestId",op.requestId)
        val witness=authority.capture()
        checkContract(op.sessionScope==Values.sha256(witness.token),"pending_operation_requires_resolution")
        val attempt=authority.withCurrent(witness){assertOutcomeReader(op,witness);journal.beginAttempt(op,op.sessionScope)}
        var submitted=false
        try{
            // A successful transport/JSON response is not a canonical financial
            // outcome. Check the retained server-side request receipt before
            // marking a contribution, enrollment or staff change complete.
            JSONObject(requestOwned(witness,j.getString("method"),j.getString("path"),body))
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
                            outcome
                        }
                        "pending"->{journal.observePending(op);throw ApiFailure("operation_still_pending",409,true)}
                        else->throw ApiFailure("invalid_api_response",503,true)
                    }
                }
            }
        }catch(e:ApiFailure){
            try{journal.failAttempt(attempt,e.status,e.uncertain||submitted)}catch(_:ContractFailure){/* A newer attempt/reconciliation owns the journal. */}
            throw e
        }catch(e:Exception){
            try{journal.failAttempt(attempt,0,true)}catch(_:ContractFailure){}
            throw e
        }
    }
}
