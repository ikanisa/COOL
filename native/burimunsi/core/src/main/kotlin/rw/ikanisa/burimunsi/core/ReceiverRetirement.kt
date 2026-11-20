package rw.ikanisa.burimunsi.core

import java.util.IdentityHashMap
import java.util.UUID

/** A control-plane retirement acknowledgement, never a replacement credential. */
data class ReceiverRetirementAck(val handoffId:String,val requestId:String) {
    init { Values.requestId(handoffId);Values.requestId(requestId) }
    val retired:Boolean get()=true
    val reauthenticationRequired:Boolean get()=true
}
enum class ReceiverRetirementState { PREPARED, SENT, UNKNOWN, RETIRED }
data class ReceiverRetirementRecord(val requestId:String,val groupId:String,val actorId:String,
    val installationId:String,val generation:String,val fingerprint:String,val tokenHash:String,
    val token:String?,val state:ReceiverRetirementState,val ack:ReceiverRetirementAck?=null) {
    override fun toString()="ReceiverRetirementRecord(redacted)"
}
interface ReceiverRetirementStore {
    val coordinationLock:Any get()=this
    fun load():ReceiverRetirementRecord?
    fun save(value:ReceiverRetirementRecord)
    /** Retain terminal history durably before releasing the current slot. */
    fun archive(value:ReceiverRetirementRecord)
}
private object ReceiverRetirementReads {
    private val active=IdentityHashMap<Any,Any>()
    @Synchronized fun begin(key:Any):Any {
        checkContract(!active.containsKey(key),"gateway_retirement_check_in_progress")
        return Any().also{active[key]=it}
    }
    @Synchronized fun finish(key:Any,lease:Any){if(active[key]===lease)active.remove(key)}
}
/** One dispatch for the installation. An interrupted/unknown command can only
 * be checked with its original opaque proof, never sent again or replaced.
 * The financial journal and receiving queue are independent and never cleared.
 */
class ReceiverRetirementJournal(private val store:ReceiverRetirementStore,
    private val requestId:()->String={UUID.randomUUID().toString()}) {
    private val hash=Regex("[a-f0-9]{64}")
    private fun validate(r:ReceiverRetirementRecord):ReceiverRetirementRecord {
        Values.requestId(r.requestId);Values.requestId(r.installationId);Values.id(r.groupId);Values.id(r.actorId)
        checkContract(Regex("0|[1-9][0-9]{0,15}").matches(r.generation)&&
            r.generation.toLongOrNull()?.let{it<=9007199254740991L}==true&&hash.matches(r.fingerprint)&&hash.matches(r.tokenHash),"corrupt_gateway_retirement")
        checkContract(if(r.state==ReceiverRetirementState.RETIRED)r.token==null&&r.ack?.requestId==r.requestId
            else r.ack==null&&r.token?.let{hash.matches(it)&&Values.sha256(it)==r.tokenHash}==true,"corrupt_gateway_retirement")
        return r
    }
    private fun loaded()=store.load()?.let(::validate)
    private fun persist(r:ReceiverRetirementRecord){validate(r);store.save(r);checkContract(loaded()==r,"gateway_retirement_store_unavailable")}
    private fun owned(expected:ReceiverRetirementRecord):ReceiverRetirementRecord {
        val actual=loaded()?:throw ContractFailure("missing_gateway_retirement")
        checkContract(actual.copy(state=expected.state,token=expected.token,ack=expected.ack)==expected,"gateway_retirement_identity_changed")
        return actual
    }
    fun retained():ReceiverRetirementRecord?=synchronized(store.coordinationLock){loaded()}
    fun archiveAfterPair()=synchronized(store.coordinationLock){
        val actual=loaded()
        if(actual!=null){
            checkContract(actual.state==ReceiverRetirementState.RETIRED,"gateway_retirement_unconfirmed")
            store.archive(actual);checkContract(loaded()==null,"gateway_retirement_store_unavailable")
        }
    }
    fun prepare(groupId:String,actorId:String,installationId:String,generation:String,token:String,code:String):ReceiverRetirementRecord=synchronized(store.coordinationLock){
        checkContract(loaded()==null&&hash.matches(code)&&hash.matches(token),"gateway_retirement_unconfirmed")
        val id=Values.requestId(requestId())
        val fingerprint=Values.sha256("burimunsi.gateway.retire.v1:"+Values.sha256(code)+":"+id.lowercase())
        ReceiverRetirementRecord(id,groupId,actorId,installationId,generation,fingerprint,Values.sha256(token),token,ReceiverRetirementState.PREPARED)
            .also(::persist)
    }
    fun beginDispatch(expected:ReceiverRetirementRecord)=synchronized(store.coordinationLock){
        val actual=owned(expected);checkContract(actual.state==ReceiverRetirementState.PREPARED,"gateway_retirement_unconfirmed")
        persist(actual.copy(state=ReceiverRetirementState.SENT))
    }
    fun uncertain(expected:ReceiverRetirementRecord)=synchronized(store.coordinationLock){
        val actual=owned(expected)
        if(actual.state!=ReceiverRetirementState.RETIRED){
            checkContract(actual.state in setOf(ReceiverRetirementState.SENT,ReceiverRetirementState.UNKNOWN),"gateway_retirement_identity_changed")
            persist(actual.copy(state=ReceiverRetirementState.UNKNOWN))
        }
    }
    fun acknowledge(expected:ReceiverRetirementRecord,ack:ReceiverRetirementAck)=synchronized(store.coordinationLock){
        val actual=owned(expected);checkContract(ack.requestId==actual.requestId,"gateway_retirement_identity_changed")
        checkContract(actual.ack==null||actual.ack==ack,"conflicting_gateway_retirement")
        // Keep the historical ACK, erase the original raw bearer after proof.
        persist(actual.copy(state=ReceiverRetirementState.RETIRED,token=null,ack=ack))
    }
    fun <T> withOutcomeRead(expected:ReceiverRetirementRecord,action:()->T):T {
        val key=store.coordinationLock
        val lease=synchronized(key){owned(expected);ReceiverRetirementReads.begin(key)}
        return try{action()}finally{ReceiverRetirementReads.finish(key,lease)}
    }
}
