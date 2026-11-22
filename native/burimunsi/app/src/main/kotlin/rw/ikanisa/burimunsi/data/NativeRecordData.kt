package rw.ikanisa.burimunsi.data

import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.SecureStore
import rw.ikanisa.wire.BuriMunsiSchemas

/** Opaque, repository-owned read capability. No bearer or account material is
 * exposed to the screen/export layer; every page rechecks original ownership. */
class RecordReadScope internal constructor(private val owner:Any,private val verify:()->Unit,private val reader:(String)->String) {
    internal fun validate(expectedOwner:Any){checkContract(owner===expectedOwner,"session_changed");verify()}
    internal fun read(expectedOwner:Any,path:String):String {
        validate(expectedOwner);val result=reader(path);validate(expectedOwner);return result
    }
    override fun toString()="RecordReadScope"
}

internal class NativeRecordData(
    private val sessions: NativeSessions,
    private val api: ApiClient,
    private val cacheStore: SecureStore,
    private val receiptVersions: AllocationReceiptVersions,
    private val recordReadOwner: Any,
) : NativeSessionRequests by sessions {
    private fun records(path:String):String = records(path){value,_->value}
    private fun <T> records(path:String,read:(String,Operator)->T):T {
        val witness=ownedSession()
        val who=authority.withCurrent(witness){operator?:throw ApiFailure("session_unavailable",401)}
        if(System.currentTimeMillis()>=who.expiresAt)throw ApiFailure("session_unavailable",401)
        val sessionScope=Values.sha256(witness.token)
        try {
            val value=requestOwned(witness,"GET",path)
            return authority.withCurrent(witness){
                val now=System.currentTimeMillis()
                checkContract(now<who.expiresAt,"session_unavailable")
                val result=read(value,who)
                sessions.markRead(now, fromCache = false)
                try {
                    var cache=cacheStore.read()?.let(::JSONObject)
                    if(cache?.optString("sessionScope")!=sessionScope||cache.optString("contractVersion")!=BuriMunsiSchemas.VERSION)cache=null
                    val entries=cache?.optJSONObject("entries")?:JSONObject()
                    entries.put(path,JSONObject().put("savedAt",now).put("payload",value))
                    while(entries.length()>8){val key=entries.keys().asSequence().minByOrNull{entries.getJSONObject(it).getLong("savedAt")}?:break;entries.remove(key)}
                    val saved=JSONObject().put("contractVersion",BuriMunsiSchemas.VERSION).put("groupId",groupId).put("accountId",who.id).put("sessionScope",sessionScope).put("entries",entries).toString()
                    if(saved.toByteArray(Charsets.UTF_8).size<=1_000_000)cacheStore.write(saved)
                }catch(_:Exception){/* Cache persistence cannot change the canonical response. */}
                result
            }
        }catch(error:ApiFailure){
            if(error.status!=0||error.code!="connection_unavailable")throw error
            return authority.withCurrent(witness){
                val now=System.currentTimeMillis()
                if(now>=who.expiresAt)throw ApiFailure("session_unavailable",401)
                val cache=try{cacheStore.read()?.let(::JSONObject)}catch(_:Exception){null}
                if(cache==null||cache.optString("contractVersion")!=BuriMunsiSchemas.VERSION||cache.optString("sessionScope")!=sessionScope||cache.optString("groupId")!=groupId||cache.optString("accountId")!=who.id)throw error
                val entry=cache.optJSONObject("entries")?.optJSONObject(path)?:throw error
                val saved=entry.getLong("savedAt");if(now<saved||now-saved>SnapshotFreshness.TTL_MS)throw error
                val payload=api.validateCached(path,entry.getString("payload"),mapOf("groupId" to groupId,"actorId" to who.id,"generation" to witness.generation.toString()))
                val result=read(payload,who)
                sessions.markRead(saved, fromCache = true); result
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
            checkContract(System.currentTimeMillis()<who.expiresAt&&!sessions.hasInflightPasscode(witness),"session_unavailable")
            Triple(groupId,who.id,who.role to who.capabilities.toSet())
        }
        val verify={authority.withCurrent(witness){
            val who=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(groupId==captured.first&&who.id==captured.second&&who.role==captured.third.first&&
                who.capabilities==captured.third.second&&System.currentTimeMillis()<who.expiresAt&&!sessions.hasInflightPasscode(witness),"session_changed")
        }}
        return RecordReadScope(recordReadOwner,verify){path->verify();requestOwned(witness,"GET",path)}
    }
    fun validateRecordReadScope(scope:RecordReadScope){scope.validate(recordReadOwner)}
    private fun listingRead(target:ListingTarget,path:String,scope:RecordReadScope?):String {
        return scope?.read(recordReadOwner,path)?:if(target in setOf(ListingTarget.PAYMENTS,ListingTarget.MEMBERS,ListingTarget.LEDGER,ListingTarget.HISTORY))records(path)else sessions.request("GET",path)
    }
    fun payments(listing:ListingQuery,cursor:String?=null,memberId:String?=null,scope:RecordReadScope?=null):Page<Payment> {
        val member=memberId?.let(Values::id)
        val result=page(listingRead(ListingTarget.PAYMENTS,listingPath("/payments",ListingTarget.PAYMENTS,listing,cursor,mapOf("memberId" to member)),scope),::decodePayment)
        if(member!=null)checkContract(result.items.all{it.memberId==member},"invalid_member_payment_scope")
        return result
    }
    fun members(listing: ListingQuery, cursor: String? = null, scope: RecordReadScope? = null, anchorId: String? = null): Page<Member> {
        checkContract(anchorId == null || cursor == null, "invalid_query")
        val path = listingPath("/members", ListingTarget.MEMBERS, listing, cursor,
            mapOf("anchorId" to anchorId?.let(Values::id)))
        return page(listingRead(ListingTarget.MEMBERS, path, scope), ::decodeMember)
    }
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
    fun payment(id:String):Payment {
        val paymentId=Values.id(id)
        return records("/payments/$paymentId"){payload,owner->
            val payment=decodePaymentDetail(JSONObject(payload))
            if(payment.id!=paymentId)throw ApiFailure("record_unavailable")
            receiptVersions.requireNewer(owner.id,groupId,paymentId,payment.version)
            payment
        }
    }
    fun member(id:String):Member {
        val memberId=Values.id(id)
        return records("/members/$memberId"){payload,_->
            val member=decodeMember(JSONObject(payload))
            checkContract(member.id==memberId,"invalid_api_response")
            member
        }
    }
    fun ledger(id:String,cursor:String?=null)=page(records("/ledger"+query(mapOf("memberId" to Values.id(id),"cursor" to cursor))),::decodeLedger)
    fun sms(q:String="",cursor:String?=null,filter:String="all",limit:Int?=null)=page(sessions.request("GET","/sms"+query(mapOf("q" to q,"cursor" to cursor,"filter" to filter,"limit" to limit?.coerceIn(1,100)?.toString()))),::decodeSms)
    fun staff(cursor:String?=null)=page(sessions.request("GET","/staff"+query(mapOf("cursor" to cursor))),::decodeStaff)
    fun audit(cursor:String?=null)=page(sessions.request("GET","/audit"+query(mapOf("cursor" to cursor)))){j->AuditRow(j.getString("id"),j.getString("action"),j.getString("at"))}
    fun paymentHistory(id:String,cursor:String?=null):Page<PaymentEvent> {
        val transactionId=Values.id(id)
        return decodePaymentHistory(records("/payments/$transactionId/history"+query(mapOf("cursor" to cursor))),groupId,transactionId)
    }
}
