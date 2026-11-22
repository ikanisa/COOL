package rw.ikanisa.burimunsi.observationhinttests

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.SmsSourceRef
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
    api.handler={request->when {
        request.path.endsWith("/session/login")->session.toString()
        request.path.endsWith("/reveal")->payload.toString()
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
    repo.logout()
    println("PASS actual repository opts in to provisional hints and rejects forged spans, digest and source identity")
}
