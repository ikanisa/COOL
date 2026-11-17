package rw.ikanisa.burimunsi.storage

import android.content.Context
import org.json.JSONObject
import org.json.JSONArray
import rw.ikanisa.burimunsi.core.*

/** Dedicated Keystore/no-backup receipt. It is never a normal session source. */
class AndroidReceiverRetirementStore(context:Context):ReceiverRetirementStore {
    companion object{private val lock=Any()}
    override val coordinationLock:Any get()=lock
    private val secure=SecureStore(context,"receiver-retirement")
    private val history=SecureStore(context,"receiver-retirement-history")
    override fun load():ReceiverRetirementRecord?=synchronized(lock){secure.read()?.let{raw->
        val j=JSONObject(raw)
        checkContract(j.keys().asSequence().toSet()==setOf("requestId","groupId","actorId","installationId","generation","fingerprint","tokenHash","token","state","ack"),"corrupt_gateway_retirement")
        fun text(key:String):String{val value=j.get(key);checkContract(value is String,"corrupt_gateway_retirement");return value as String}
        val token=if(j.isNull("token"))null else text("token")
        val ack=if(j.isNull("ack"))null else j.getJSONObject("ack").let{
            checkContract(it.keys().asSequence().toSet()==setOf("handoffId","requestId"),"corrupt_gateway_retirement")
            checkContract(it.get("handoffId") is String&&it.get("requestId") is String,"corrupt_gateway_retirement")
            ReceiverRetirementAck(it.getString("handoffId"),it.getString("requestId"))
        }
        val state=try{ReceiverRetirementState.valueOf(text("state"))}catch(_:IllegalArgumentException){throw ContractFailure("corrupt_gateway_retirement")}
        ReceiverRetirementRecord(text("requestId"),text("groupId"),text("actorId"),text("installationId"),text("generation"),text("fingerprint"),text("tokenHash"),token,state,ack)
    }}
    private fun encoded(value:ReceiverRetirementRecord):JSONObject {
        val ack=value.ack?.let{JSONObject().put("handoffId",it.handoffId).put("requestId",it.requestId)}
        return JSONObject().put("requestId",value.requestId).put("groupId",value.groupId).put("actorId",value.actorId)
            .put("installationId",value.installationId).put("generation",value.generation).put("fingerprint",value.fingerprint)
            .put("tokenHash",value.tokenHash).put("token",value.token?:JSONObject.NULL).put("state",value.state.name).put("ack",ack?:JSONObject.NULL)
    }
    override fun save(value:ReceiverRetirementRecord)=synchronized(lock){
        secure.write(encoded(value).toString())
        checkContract(load()==value,"gateway_retirement_store_unavailable")
    }
    override fun archive(value:ReceiverRetirementRecord)=synchronized(lock){
        checkContract(load()==value&&value.state==ReceiverRetirementState.RETIRED&&value.token==null&&value.ack!=null,"gateway_retirement_identity_changed")
        val retained=history.read()?.let(::JSONArray)?:JSONArray();var found=false
        for(i in 0 until retained.length()){
            val row=retained.getJSONObject(i)
            checkContract(row.isNull("token")&&row.getString("state")==ReceiverRetirementState.RETIRED.name,"corrupt_gateway_retirement")
            if(row.getString("requestId")==value.requestId){checkContract(row.toString()==encoded(value).toString(),"conflicting_gateway_retirement");found=true}
        }
        if(!found)retained.put(encoded(value))
        val payload=retained.toString();history.write(payload)
        checkContract(history.read()==payload,"gateway_retirement_store_unavailable")
        // Only a verified successful Pair reaches here. Keep all old receipts;
        // failed archive/clear readback leaves the old slot unreusable.
        secure.clear();checkContract(secure.read()==null,"gateway_retirement_store_unavailable")
    }
}
