package rw.ikanisa.burimunsi.data

import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*

/** Receiver pairing and proof recovery use the same preparation lock as financial commands. */
internal class NativeReceiverPairing(
    session: NativeSessionRequests,
    private val api: ApiClient,
    private val receiverRetirement: ReceiverRetirementJournal,
    private val journal: OperationJournal,
    private val commandPreparationLock: Any,
) : NativeSessionRequests by session {
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
}
