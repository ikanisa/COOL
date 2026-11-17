package rw.ikanisa.burimunsi.observationhinttests

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.SmsSourceRef
import rw.ikanisa.burimunsi.core.SmsObservation
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore

/** Actual repository with synthetic API and storage; no live observation is read. */
fun main(){
    SecureStore.reset();val context=Context();val api=ApiClient();api.installationProfile="internal_receiver"
    val expiry=System.currentTimeMillis()+3_600_000
    val session=JSONObject().put("token","a".repeat(64)).put("expiresAt",expiry).put("profile",JSONObject()
        .put("id","admin-1").put("name","Synthetic Admin").put("phone","+250780000001").put("role","admin")
        .put("capabilities",JSONArray().put("records.read").put("sms.read").put("gateway.manage")))
    val text="You have received 1,000 RWF. FT Id: REF-1";val amount="1,000 RWF";val start=text.indexOf(amount)
    var payload=JSONObject().put("groupId","group-1").put("sourceKind","observation").put("sourceId","source-1")
        .put("status","source_unresolved").put("at","2026-11-09T00:00:00Z").put("sender","M-Money").put("rawBody",text)
        .put("financialEffects",0).put("displayHints",JSONObject().put("schemaVersion",1).put("kind","partial_inbox_display_only")
            .put("profileVersion","approved-v1").put("profileSha256","a".repeat(64)).put("bodySha256",Values.sha256(text))
            .put("hints",JSONArray().put(JSONObject().put("kind","quoted_incoming_amount").put("text",amount).put("start",start).put("end",start+amount.length))))
    val recovery=SmsObservation("00000000-0000-4000-8000-000000000111","M-Money",text,"catch_up",false,
        "2026-11-17T18:00:00Z",null,"2026-11-17T17:59:00Z",3,"a".repeat(64))
    val heldAck=JSONObject().put("requestId",recovery.requestId).put("sourceId","source-1").put("bodySha256",Values.sha256(text))
        .put("status","source_unresolved").put("financialEffects",0).put("autoProcessing","held")
    val lookup=JSONObject().put("requestId",recovery.requestId).put("sourceKey",recovery.sourceKey).put("bodySha256",Values.sha256(text))
        .put("state","acknowledged").put("sourceId","source-1").put("autoProcessing","held").put("financialEffects",0).put("retryAllowed",false)
    val verified=JSONObject().put("groupId","group-1").put("hasPending",false).put("hasRecorded",false).put("recordedCount",0)
        .put("hasUnmatchedCanonical",false).put("revision","a".repeat(64)).put("scope","verified_collection")
    api.handler={request->when {
        request.path.endsWith("/session/login")->session.toString()
        request.path.endsWith("/reveal")->payload.toString()
        request.path.endsWith("/recover-held")->heldAck.toString()
        request.path.endsWith("/recover-held-ack")->lookup.toString()
        request.path.endsWith("/reconcile-verified-status")->verified.toString()
        request.path.endsWith("/logout")->JSONObject().put("signedOut",true).toString()
        else->error("Unexpected synthetic request")
    }}
    val repo=NativeRepository(context,api,"group-1");repo.login("0780000001","2468")
    val source=SmsSourceRef.Observation("source-1")
    val result=repo.revealObservation(source,"Review original SMS")
    check(result.displayHints?.hints?.single()?.text==amount)
    check(api.calls.last().body?.getInt("displayHintsVersion")==1)
    payload.getJSONObject("displayHints").getJSONArray("hints").getJSONObject(0).put("text","9,000 RWF")
    check(runCatching{repo.revealObservation(source,"Review original SMS")}.isFailure)
    payload.getJSONObject("displayHints").getJSONArray("hints").getJSONObject(0).put("text",amount)
    payload.getJSONObject("displayHints").put("bodySha256","b".repeat(64))
    check(runCatching{repo.revealObservation(source,"Review original SMS")}.isFailure)
    payload.put("displayHints",JSONObject.NULL)
    check(repo.revealObservation(source,"Review original SMS").displayHints==null)
    payload.put("sourceId","other-source")
    check(runCatching{repo.revealObservation(source,"Review original SMS")}.isFailure)
    val originalGeneration=7L
    check(repo.recoverHeldObservation(recovery,originalGeneration).autoProcessing=="held")
    val written=api.calls.last().body!!
    check(written.getString("requestId")==recovery.requestId&&written.getString("rawBody")==text&&
        written.getString("sourceKey")==recovery.sourceKey&&written.getString("sourceMode")=="catch_up"&&!written.getBoolean("complete")&&
        written.getLong("expectedConsentGeneration")==originalGeneration)
    val originalBody=written.toString()
    val contract=rw.ikanisa.wire.BuriMunsiSchemas.contract
    for(operation in listOf("observationRecoverHeld.request","observationRecoverHeldAck.request")){
        check(runCatching{contract.validate(operation,rw.ikanisa.wire.StrictJson.parse(originalBody))}.isSuccess)
        val missing=JSONObject(originalBody);missing.remove("expectedConsentGeneration")
        check(runCatching{contract.validate(operation,rw.ikanisa.wire.StrictJson.parse(missing.toString()))}.isFailure)
        for(bad in listOf<Any>(0L,-1L,9_007_199_254_740_992L,"7",1.5)){
            val changed=JSONObject(originalBody).put("expectedConsentGeneration",bad)
            check(runCatching{contract.validate(operation,rw.ikanisa.wire.StrictJson.parse(changed.toString()))}.isFailure)
        }
    }
    check(repo.heldRecoveryAcknowledgement(recovery,originalGeneration).state=="acknowledged"&&api.calls.last().body!!.toString()==originalBody)
    lookup.put("state","unconfirmed").put("sourceId",JSONObject.NULL).put("autoProcessing","unknown")
    check(repo.heldRecoveryAcknowledgement(recovery,originalGeneration).state=="unconfirmed")
    lookup.put("state","acknowledged").put("sourceId","source-1").put("autoProcessing","held")
    for((field,bad,good) in listOf(Triple("requestId","other",recovery.requestId),Triple("sourceKey","b".repeat(64),recovery.sourceKey),
        Triple("bodySha256","b".repeat(64),Values.sha256(text)),Triple("autoProcessing","unknown","held"),
        Triple("financialEffects",1,0),Triple("retryAllowed",true,false),Triple("sourceId",JSONObject.NULL,"source-1"))){
        lookup.put(field,bad);check(runCatching{repo.heldRecoveryAcknowledgement(recovery,originalGeneration)}.isFailure);lookup.put(field,good)
    }
    for((field,bad,good) in listOf(Triple("requestId","other",recovery.requestId),Triple("bodySha256","b".repeat(64),Values.sha256(text)),
        Triple("autoProcessing","released","held"),Triple("financialEffects",1,0))){
        heldAck.put(field,bad);check(runCatching{repo.recoverHeldObservation(recovery,originalGeneration)}.isFailure);heldAck.put(field,good)
    }
    val before=api.calls.size;check(runCatching{repo.recoverHeldObservation(recovery.copy(sourceMode="live"),originalGeneration)}.isFailure&&api.calls.size==before)
    for(bad in listOf(0L,-1L,9_007_199_254_740_992L)){
        check(runCatching{repo.recoverHeldObservation(recovery,bad)}.isFailure&&api.calls.size==before)
        check(runCatching{repo.heldRecoveryAcknowledgement(recovery,bad)}.isFailure&&api.calls.size==before)
    }
    check(repo.observationReconcileVerifiedStatus().scope=="verified_collection")
    for((field,bad,good) in listOf(Triple("scope","all","verified_collection"),Triple("groupId","other","group-1"),
        Triple("hasRecorded",true,false),Triple("revision","bad","a".repeat(64)))){
        verified.put(field,bad);check(runCatching{repo.observationReconcileVerifiedStatus()}.isFailure);verified.put(field,good)
    }
    repo.logout()
    println("PASS actual repository validates hints and held-recovery scope, request identity, held status and zero effects")
}
