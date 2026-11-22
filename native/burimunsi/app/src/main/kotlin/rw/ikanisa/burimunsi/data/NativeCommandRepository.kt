package rw.ikanisa.burimunsi.data

import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.SecureStore

/** Owns prepared financial and staff commands until their original outcomes are verified. */
internal class NativeCommandRepository(
    session: NativeSessionRequests,
    private val journal: OperationJournal,
    private val commandPreparationLock: Any,
    private val receiptVersions: AllocationReceiptVersions,
    private val cacheStore: SecureStore,
    private val installationId: () -> String,
    private val hasPendingReceiverRetirement: () -> Boolean,
) : NativeSessionRequests by session {
    fun mutate(method:String,path:String,body:JSONObject,resolveBlankPhoneDenial:Boolean=false,allocation:Payment?=null):JSONObject{
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
            if(allocation!=null)receiptVersions.requireNewer(owner.id,groupId,allocation.id,allocation.version)
            journal.prepare(Values.sha256(witness.token),method+" "+path,payload,owner.id,groupId)
        }}
        return sendPending(operation,transientPin,resolveBlankPhoneDenial)
    }
    fun pending()=journal.unresolved()
    /** Check the original outcome. A manual staff check may close an uncommitted
     * request under the server's staff mutation lock; it never resends the command. */
    fun reconcilePending():JSONObject = withPendingCommand { original, witness ->
        reconcileOwned(original, witness, resolveStaff = true)
    }

    private fun <T> withPendingCommand(action: (PendingOperation, SessionWitness) -> T): T {
        val op=journal.unresolved()?:throw ApiFailure("no_pending_operation")
        val witness=ownedSession()
        return journal.withRecoveryRead(op){action(op,witness)}
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
                decodeRecoveryOutcome(raw,op.requestId,op.sessionScope,groupId,who.id,installationId())
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
                "committed"->{journal.reconcile(op,OperationState.COMMITTED);finishCommittedCleanup(op,status)}
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
            decodeRecoveryOutcome(raw,op.requestId,op.sessionScope,groupId,who.id,installationId())
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
    private fun finishCommittedCleanup(op:PendingOperation,proof:JSONObject)=journal.finishCleanup(op){
        if(proof.getString("operation")=="burimunsi.allocate"){
            val intent=JSONObject(op.body)
            val id=Values.id(intent.getString("path").removePrefix("/payments/").removeSuffix("/allocate"))
            val allocation=AllocationReadback(id,intent.getJSONObject("body").counter("expectedVersion"))
            // Legacy journals inherit owner and group only from the verified original v1/v2 proofs.
            receiptVersions.retain(proof.getString("actorId"),proof.getString("groupId"),op.requestId,allocation)
        }
        invalidateRecordsForCommit()
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
                            finishCommittedCleanup(op,outcome)
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
