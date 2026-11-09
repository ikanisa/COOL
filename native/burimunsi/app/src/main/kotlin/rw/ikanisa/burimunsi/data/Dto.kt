package rw.ikanisa.burimunsi.data

import org.json.JSONObject
import org.json.JSONArray
import rw.ikanisa.burimunsi.core.*

/** Deliberate DTO decoding: monetary values may not round through floating-point. */
internal fun JSONObject.amount(name:String,positive:Boolean=false):Long {
    val raw=get(name);checkContract(raw is Int || raw is Long,"contract_amount")
    val n=(raw as Number).toLong();check(n in -Values.MAX_RWF..Values.MAX_RWF);if(positive)check(n>0);return n
}
internal fun JSONObject.nullString(name:String):String? {
    checkContract(has(name),"contract_missing_field")
    if(isNull(name))return null
    val value=get(name);checkContract(value is String,"contract_type");return value as String
}
internal fun JSONObject.capabilities():Set<String> {
    checkContract(has("capabilities")&&!isNull("capabilities"),"contract_missing_field")
    val a=getJSONArray("capabilities");val values=(0 until a.length()).map{val v=a.get(it);checkContract(v is String,"contract_type");v as String}
    checkContract(values.toSet().size==values.size,"contract_duplicate");return values.toSet()
}
internal fun operator(j:JSONObject,expiry:Long):Operator { checkedDto("profile",j);return Operator(j.getString("id"),j.getString("name"),Values.phone(j.getString("phone")),when(j.getString("role")){"admin"->Role.ADMIN;"staff"->Role.STAFF;else->error("Invalid role")},j.capabilities(),expiry) }
internal fun decodePayment(j:JSONObject):Payment { checkedDto("payment",j);return Payment(j.getString("id"),j.getString("payerNameRaw"),j.getString("payerPhoneRaw"),j.amount("amountRwf"),j.getString("atRaw"),j.getString("ftId"),j.getString("state"),j.getLong("version"),j.nullString("memberId"),j.nullString("memberPhone"),j.nullString("sourceId")) }
internal fun decodeMember(j:JSONObject):Member { checkedDto("member",j);return Member(j.getString("id"),j.getString("name"),Values.phone(j.getString("phone")),j.amount("balanceRwf"),j.getBoolean("active"),j.getLong("version")) }
internal fun decodeLedger(j:JSONObject):LedgerRow { checkedDto("ledgerRow",j);return LedgerRow(j.getString("id"),j.nullString("transactionId"),j.amount("amountRwf"),j.getString("atRaw"),j.getString("ftId"),j.getString("payerNameRaw")) }
internal fun decodeSms(j:JSONObject):SmsRow { checkedDto("smsRow",j);return SmsRow(j.getString("id"),j.getString("sender"),j.getString("at"),j.getString("preview"),j.getString("state"),j.nullString("transactionId")) }
internal fun decodeStaff(j:JSONObject):StaffAccount { checkedDto("staffRow",j);return StaffAccount(j.getString("id"),j.getString("name"),Values.phone(j.getString("phone")),j.getBoolean("active"),j.getLong("version"),j.capabilities()) }
/** Exact nonnegative integers; Android getInt/getLong can coerce or truncate. */
internal fun JSONObject.counter(name:String,max:Long=Long.MAX_VALUE):Long {
    val raw=get(name)
    checkContract(raw is Number&&Regex("[0-9]+").matches(raw.toString()),"invalid_api_response")
    val value=raw.toString().toLongOrNull()?:throw ContractFailure("invalid_api_response")
    checkContract(value in 0..max,"invalid_api_response");return value
}
internal fun <T> page(json:String,read:(JSONObject)->T):Page<T>{
    val j=JSONObject(json);val a=j.getJSONArray("items");checkContract(a.length()<=100,"invalid_page")
    val total=j.counter("totalCount",Int.MAX_VALUE.toLong()).toInt()
    val revision=j.getString("revision");val at=j.getString("asOf");val cursor=j.nullString("nextCursor")
    checkContract(revision.isNotBlank()&&revision.length<=256&&at.isNotBlank(),"invalid_page")
    checkContract(cursor==null||(cursor.isNotBlank()&&cursor.length<=8192),"invalid_page")
    checkContract(total>=a.length()&&(cursor==null||a.length()>0),"invalid_page")
    val ids=mutableSetOf<String>()
    val rows=(0 until a.length()).map{val row=a.getJSONObject(it);val id=row.getString("id")
        checkContract(id.isNotBlank()&&ids.add(id),"invalid_page");read(row)}
    return Page(rows,cursor,total,revision,at)
}
internal fun decodePaymentHistory(json:String,groupId:String,transactionId:String):Page<PaymentEvent> = page(json){j->
    checkContract(j.getString("groupId")==groupId&&j.getString("transactionId")==transactionId,"invalid_history_scope")
    val id=j.getString("id");val kind=j.getString("kind");val at=j.getString("recordedAt")
    checkContract(kind in setOf("transaction_recorded","ledger_entry"),"invalid_history_event")
    val prefix=if(kind=="transaction_recorded")"transaction:" else "ledger:"
    checkContract(id.startsWith(prefix),"invalid_history_event");val recordId=Values.id(id.removePrefix(prefix))
    checkContract(at.endsWith("Z")&&runCatching{java.time.Instant.parse(at)}.isSuccess,"invalid_history_timestamp")
    val amount=if(j.isNull("amountRwf"))null else j.amount("amountRwf")
    val member=j.nullString("memberId")
    if(kind=="transaction_recorded")checkContract(recordId==transactionId&&amount==null&&member==null,"invalid_history_event")
    else{checkContract(amount!=null&&amount!=0L&&member!=null,"invalid_history_event");Values.id(member!!)}
    PaymentEvent(id,transactionId,kind,at,amount,member)
}

/** Recovery fields must be actual strings, not Android JSON primitive coercions. */
internal fun decodeRecoveryOutcome(json:String,requestId:String,originDigest:String,groupId:String,actorId:String,installationId:String):JSONObject {
    val value=try{JSONObject(json)}catch(_:Exception){throw ContractFailure("invalid_recovery_response")}
    val fields=setOf("protocol","requestId","state","originDigest","groupId","actorId","installationId")
    checkContract(value.keys().asSequence().toSet()==fields,"invalid_recovery_response")
    for(field in fields)checkContract(value.get(field) is String,"invalid_recovery_response")
    checkContract(value.getString("protocol")=="burimunsi.operation-recovery.v1","invalid_recovery_response")
    checkContract(value.getString("requestId")==requestId&&value.getString("originDigest")==originDigest,"invalid_recovery_response")
    checkContract(value.getString("groupId")==groupId&&value.getString("actorId")==actorId&&value.getString("installationId")==installationId,"invalid_recovery_response")
    checkContract(value.getString("state") in setOf("committed","pending"),"invalid_recovery_response")
    return value
}
