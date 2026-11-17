package rw.ikanisa.burimunsi.receiverretirementrepositorytests

import android.content.Context
import org.json.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*

/** Actual repository, encrypted-store adapter and journal with explicit
 * test-only storage/JSON/HTTP doubles. No real account/device/service is used. */
fun main(){
 var count=0;fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");count++}
 val install="40000000-0000-4000-8000-000000000001";val handoff="40000000-0000-4000-8000-000000000002"
 val token="a".repeat(64);val code="b".repeat(64)
 fun login()=JSONObject().put("groupId","group-1").put("token",token).put("expiresAt",System.currentTimeMillis()+3600000)
  .put("profile",JSONObject().put("id","operator-1").put("name","Synthetic Admin").put("phone","+250780000001").put("role","admin")
   .put("capabilities",JSONArray().put("records.read").put("gateway.manage").put("members.enroll"))).toString()
 fun ack(request:String)=JSONObject().put("retired",true).put("handoffId",handoff).put("requestId",request).put("reauthenticationRequired",true)
 fun api()=ApiClient(install).also{it.resolvesLoginScope=true;it.installationProfile="internal_receiver"}
 SecureStore.reset();val api=api();var posts=0;var reads=0;var retired=false;var request=""
 api.handler={r->when{
  r.path.endsWith("/session/login")->login()
  r.path.endsWith("/gateway/replace")->{posts++;request=r.body!!.getString("requestId");throw ApiFailure("connection_unavailable",0,true)}
  r.path.contains("/gateway/replacements/")->{reads++;check(r.method=="GET"&&r.body==null&&r.token==token)
   check(r.contractContext["groupId"]=="group-1"&&r.contractContext["actorId"]=="operator-1")
   JSONObject().put("protocol","burimunsi.receiver-retirement.v1").put("requestId",request)
    .put("fingerprint",r.contractContext["handoffFingerprint"]).put("state",if(retired)"retired" else "unknown")
    .put("ack",if(retired)ack(request) else JSONObject.NULL).toString()}
  else->error("Unexpected ordinary request")
 }}
 val repo=NativeRepository(Context(),api);repo.login("0780000001","2468")
 val lost=runCatching{repo.pairGateway(code,true)}.exceptionOrNull()
 ck("lost retirement POST keeps a separate UNKNOWN proof",lost is ApiFailure&&lost.code=="gateway_retirement_unconfirmed"&&posts==1&&repo.hasPendingReceiverRetirement()&&repo.pending()==null)
 val proof=AndroidReceiverRetirementStore(Context()).load()!!
 ck("original request fingerprint binds code and request",proof.fingerprint==Values.sha256("burimunsi.gateway.retire.v1:"+Values.sha256(code)+":"+request))
 repo.clearOperator()
 ck("local logout preserves original encrypted retirement proof",repo.current()==null&&AndroidReceiverRetirementStore(Context()).load()==proof)
 ck("unknown GET cannot clear proof or assert not-applied",repo.recoverReceiverRetirement()==null&&posts==1&&reads==1&&repo.hasPendingReceiverRetirement())
 val recreated=NativeRepository(Context(),api)
 ck("recreation recovers without restore or current native operator",recreated.recoverReceiverRetirement()==null&&recreated.current()==null&&posts==1&&reads==2)
 runCatching{recreated.pairGateway("c".repeat(64),true)}
 ck("repeat Replace uses original GET and never changes request/code identity",posts==1&&reads==3&&AndroidReceiverRetirementStore(Context()).load()==proof)
 runCatching{recreated.pairGateway(code,false)}
 ck("pending retirement cannot pair another receiver credential",posts==1&&reads==3&&api.calls.none{it.path.endsWith("/gateway/pair")})
 retired=true;val resolved=recreated.recoverReceiverRetirement()!!
 ck("matching ACK settles only retirement",resolved.getString("requestId")==request&&!recreated.hasPendingReceiverRetirement()&&recreated.pending()==null&&posts==1)
 ck("settlement erases bearer but retains exact historical ACK",AndroidReceiverRetirementStore(Context()).load()?.let{it.token==null&&it.state==ReceiverRetirementState.RETIRED&&it.ack?.handoffId==handoff}==true)
 ck("terminal ACK remains discoverable until its local gateway park is applied",recreated.hasReceiverRetirementRecord()&&!recreated.hasPendingReceiverRetirement())
 val prior=api.calls.size;recreated.recoverReceiverRetirement()
 ck("retained terminal ACK does not refresh or make another request",api.calls.size==prior)
 val terminal=AndroidReceiverRetirementStore(Context()).load()!!
 val baseHandler=api.handler
 api.handler={r->if(r.path.endsWith("/gateway/pair"))JSONObject().put("binding",JSONObject().put("id","new-binding")).put("gateway_token","c".repeat(64)).toString() else baseHandler(r)}
 recreated.login("0780000001","2468")
 SecureStore.dropWrite="receiver-retirement-history"
 ck("failed terminal archive prevents a later Pair from releasing its current slot",runCatching{recreated.pairGateway(code,false)}.isFailure&&AndroidReceiverRetirementStore(Context()).load()==terminal)
 SecureStore.dropWrite=null;recreated.pairGateway(code,false)
 val history=JSONArray(SecureStore.records.getValue("receiver-retirement-history"))
 ck("successful later Pair archives terminal ACK and erases only the current retirement slot",AndroidReceiverRetirementStore(Context()).load()==null&&history.length()==1&&history.getJSONObject(0).getJSONObject("ack").getString("requestId")==request&&history.getJSONObject(0).isNull("token"))
 ck("archived old ACK cannot masquerade as a new pending retirement",!recreated.hasReceiverRetirementRecord())
 val oldRequest=request;retired=false;runCatching{recreated.pairGateway(code,true)}
 ck("reused authorized handset dispatches a new retirement rather than replaying historical ACK",posts==2&&request!=oldRequest&&recreated.hasPendingReceiverRetirement()&&history.getJSONObject(0).getJSONObject("ack").getString("requestId")==oldRequest)
 // Independent financial evidence must block retirement before proof creation.
 SecureStore.reset();val financialApi=api();financialApi.handler={r->if(r.path.endsWith("/session/login"))login() else error("Must not dispatch")}
 val financial=NativeRepository(Context(),financialApi);financial.login("0780000001","2468")
 val journal=OperationJournal(AndroidOperationStore(Context()));val pending=journal.prepare(Values.sha256(token),"POST /members","{}","operator-1","group-1")
 val before=financialApi.calls.size;runCatching{financial.pairGateway(code,true)}
 ck("unconfirmed financial journal refuses retirement before POST",financialApi.calls.size==before&&financial.pending()==pending&&!financial.hasPendingReceiverRetirement())
 // A storage readback failure cannot be interpreted as permission to transmit.
 SecureStore.reset();val brokenApi=api();brokenApi.handler={login()};val broken=NativeRepository(Context(),brokenApi);broken.login("0780000001","2468")
 SecureStore.dropWrite="receiver-retirement";val beforeBroken=brokenApi.calls.size
 runCatching{broken.pairGateway(code,true)}
 ck("dropped private proof write prevents retirement dispatch",brokenApi.calls.size==beforeBroken&&!broken.hasPendingReceiverRetirement())
 SecureStore.reset()
 println("RESULT: $count retirement repository checks passed; explicit test doubles, no Android/SQL/network claims.")
}
