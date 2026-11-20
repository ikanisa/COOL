package rw.ikanisa.burimunsi.listingrepositorytests

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore

/** Actual repository ownership and requests, synthetic transport only. */
fun main(){
    var checks=0
    fun ok(value:Boolean){check(value);checks++}
    val profile=JSONObject().put("id","admin-1").put("name","Example Admin").put("phone","+250780000001").put("role","admin")
        .put("capabilities",JSONArray().put("records.read").put("sms.read").put("gateway.manage"))
    fun session()=JSONObject().put("token","a".repeat(64)).put("expiresAt",System.currentTimeMillis()+3_600_000).put("profile",profile).toString()
    val row=JSONObject().put("id","tx-1").put("groupId","group-1").put("payerNameRaw","Example payer").put("payerPhoneRaw","*********123")
        .put("amountRwf",1000).put("atRaw","2026-11-14 12:00:00").put("ftId","1234").put("state","unallocated").put("version",1)
        .put("memberId",JSONObject.NULL).put("memberPhone",JSONObject.NULL).put("sourceId",JSONObject.NULL)
    fun page()=JSONObject().put("items",JSONArray().put(row)).put("totalCount",1).put("nextCursor",JSONObject.NULL).put("revision","revision-1").put("asOf","2026-11-14T10:00:00Z").toString()
    fun sourcePage(observation:Boolean):String {
        val source=JSONObject().put("id","10000000-0000-4000-8000-000000000001").put("groupId","group-1").put("at","2026-11-14T10:00:00Z")
        if(observation)source.put("sourceKind","observation").put("sourceId","10000000-0000-4000-8000-000000000001").put("status","source_unresolved").put("financialEffects",0)
        else source.put("sender","").put("preview","").put("state","synced").put("transactionId",JSONObject.NULL)
        return JSONObject().put("items",JSONArray().put(source)).put("totalCount",1).put("nextCursor",JSONObject.NULL).put("revision","sources-v1").put("asOf","2026-11-14T10:00:00Z").toString()
    }
    var offline=false;var beforeReply:(()->Unit)?=null
    val api=ApiClient();api.installationProfile="internal_receiver";api.handler={request->when{
        request.path.endsWith("/session/login")->session()
        request.path.endsWith("/session/logout")->JSONObject().put("signedOut",true).toString()
        request.path=="/v1/burimunsi/session"->JSONObject().put("groupId","group-1").put("profile",profile).put("expiresAt",System.currentTimeMillis()+3_600_000).toString()
        request.path.contains("/payments?")-> {if(offline)throw ApiFailure("connection_unavailable",0);beforeReply?.invoke();page()}
        request.path.contains("/sms/observations?")->sourcePage(true)
        request.path.contains("/sms?")->sourcePage(false)
        else->error("Unexpected synthetic request")
    }}
    SecureStore.reset();val repo=NativeRepository(Context(),api,"group-1");repo.login("0780000001","2468")
    val query=ListingQuery(sort=ListingSort.AMOUNT_DESC,minRwf=500,direction="incoming",fromAt="2026-11-14T00:00:00Z")
    repo.payments(query)
    val scope=repo.recordReadScope();ok(scope.toString()=="RecordReadScope")
    ok(repo.payments(query,scope=scope).items.single().id=="tx-1")
    val request=api.calls.last();ok(request.path.contains("sort=amount_desc")&&request.path.contains("minRwf=500")&&request.path.contains("direction=incoming"))
    ok(request.path.contains("fromAt=2026-11-14T00%3A00%3A00Z")&&request.path.contains("limit=100"))
    val wire=rw.ikanisa.wire.BuriMunsiSchemas.contract
    ok(wire.query("payments",request.path.substringAfter('?'))["sort"]=="amount_desc")
    ok(wire.query("members","sort=balance_desc&active=active&minRwf=0")["active"]=="active")
    ok(wire.query("history","sort=oldest&filter=ledger_entry&minRwf=-100")["filter"]=="ledger_entry")
    ok(runCatching{wire.query("sms","sort=newest&minRwf=10")}.isFailure)
    ok(repo.sms(ListingQuery(),limit=5).items.size==1&&api.calls.last().path.contains("limit=5"))
    ok(repo.observationPage(ListingQuery(),limit=5).items.size==1&&api.calls.last().path.contains("limit=5"))
    val beforeInvalidLimit=api.calls.size
    ok(runCatching{repo.sms(ListingQuery(),limit=0)}.exceptionOrNull() is ContractFailure)
    ok(runCatching{repo.observationPage(ListingQuery(),limit=101)}.exceptionOrNull() is ContractFailure)
    ok(api.calls.size==beforeInvalidLimit)
    repo.validateRecordReadScope(scope);ok(true)
    offline=true;ok(runCatching{repo.payments(query,scope=scope)}.exceptionOrNull() is ApiFailure);offline=false
    profile.put("role","staff");repo.refreshSession()
    val before=api.calls.size
    ok(runCatching{repo.validateRecordReadScope(scope)}.exceptionOrNull() is ContractFailure)
    ok(runCatching{repo.payments(query,scope=scope)}.exceptionOrNull() is ContractFailure&&api.calls.size==before)
    val staffScope=repo.recordReadScope()
    beforeReply={repo.logout()}
    ok(runCatching{repo.payments(query,scope=staffScope)}.exceptionOrNull() is ContractFailure)
    ok(runCatching{repo.validateRecordReadScope(staffScope)}.exceptionOrNull() is ContractFailure)
    println("PASS listing repository checks $checks")
}
