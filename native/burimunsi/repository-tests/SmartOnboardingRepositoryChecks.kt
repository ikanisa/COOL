package rw.ikanisa.burimunsi.smartonboardingrepositorytests

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.SecureStore

fun main(){
 var checks=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
 SecureStore.reset();val api=ApiClient("installation-1");val token="a".repeat(64)
 var posts=0;var loseReply=false;var outcome="committed"
 api.handler={r->when{
  r.path.endsWith("/session/login")->JSONObject().put("token",token).put("expiresAt",4102444800000L)
   .put("profile",JSONObject().put("id","operator-1").put("name","Synthetic operator").put("phone","+250780000001")
    .put("role","admin").put("capabilities",JSONArray().put("records.read").put("members.enroll"))).toString()
  r.path.endsWith("/members/import")->{posts++;if(loseReply)throw ApiFailure("connection_unavailable",0,true)
   JSONObject().put("requestId",r.body!!.getString("requestId")).put("created",1)
    .put("results",JSONArray().put(JSONObject().put("row",1).put("status","created").put("memberId","member-1"))).toString()}
  r.path.endsWith("/recovery")->JSONObject().put("protocol","burimunsi.operation-recovery.v1")
   .put("requestId",r.path.substringBeforeLast('/').substringAfterLast('/')).put("state",outcome).put("originDigest",r.recoveryOrigin)
   .put("groupId","group-1").put("actorId","operator-1").put("installationId","installation-1").toString()
  r.path.contains("/operations/")->JSONObject().put("contractVersion",2).put("requestId",r.path.substringAfterLast('/'))
   .put("groupId","group-1").put("actorId","operator-1").put("state","committed")
   .put("operation","burimunsi.members_import").put("financialState","not_applicable").toString()
  else->error("Unexpected fixture route")
 }}
 val repo=NativeRepository(Context(),api,"group-1");repo.login("0780000001","2468")
 fun row(name:String="Synthetic member")=JSONObject().put("row",1).put("name",name).put("phone","+250780000001")
  .put("verifiedOwnership",true).put("acceptedTerms",true).put("consentRecorded",true)
 val oversized=JSONArray();repeat(500){oversized.put(row("界".repeat(1000)))}
 val failure=runCatching{repo.onboardingImport(oversized)}.exceptionOrNull()
 ck("oversized batch is refused before a journal or request exists",failure is ContractFailure&&failure.code=="smart_import_size_invalid"&&posts==0&&repo.pending()==null)
 val result=repo.onboardingImport(JSONArray().put(row()))
 ck("successful batch returns its correlated acknowledgement after outcome readback",result.getJSONObject("importResult").getInt("created")==1&&posts==1&&repo.pending()==null)
 loseReply=true;runCatching{repo.onboardingImport(JSONArray().put(row()))}
 ck("lost response keeps the original command unresolved",posts==2&&repo.pending()?.state==OperationState.UNKNOWN)
 outcome="committed";repo.reconcilePending()
 ck("recovery reads the outcome without sending another batch",posts==2&&repo.pending()==null)
 println("RESULT: $checks batch repository checks passed with synthetic transport and storage.")
}
