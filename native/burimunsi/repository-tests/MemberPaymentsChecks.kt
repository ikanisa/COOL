package rw.ikanisa.burimunsi.memberpaymenttests
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.Member
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore

/** Actual repository, synthetic transport: no deployed backend or device. */
fun main(){
 val profile=JSONObject().put("id","admin-1").put("name","Example Admin").put("phone","+250780000001").put("role","admin")
  .put("capabilities",JSONArray().put("records.read"))
 val session=JSONObject().put("token","a".repeat(64)).put("expiresAt",System.currentTimeMillis()+3_600_000).put("profile",profile).toString()
 var paymentState="processing"
 fun payment(id:String,member:String?)=JSONObject().put("id",id).put("groupId","group-1").put("memberId",member?:JSONObject.NULL)
  .put("memberPhone",if(member==null)JSONObject.NULL else "+250780000816").put("sourceId",JSONObject.NULL)
  .put("payerNameRaw","Synthetic payer").put("payerPhoneRaw","*********123").put("amountRwf",1000)
  .put("atRaw","2026-11-08 12:00:00").put("ftId","10001").put("state",paymentState).put("version",1)
 fun page(row:JSONObject,next:String?)=JSONObject().put("items",JSONArray().put(row)).put("totalCount",2)
  .put("nextCursor",next?:JSONObject.NULL).put("revision","v1").put("asOf","2026-11-08T10:00:00Z").toString()
 var bad=false;val api=ApiClient();api.handler={r->when{
  r.path.endsWith("/session/login")->session
  r.path.contains("/payments?")->page(payment(if(r.path.contains("cursor="))"tx-2" else "tx-1",if(bad)"member-2" else "member-1"),if(r.path.contains("cursor="))null else "next")
  else->error("Unexpected synthetic request")
 }}
 SecureStore.reset();val repo=NativeRepository(Context(),api,"group-1");repo.login("0780000001","2468")
 val first=repo.payments(memberId="member-1");check(first.items.single().memberId=="member-1"&&first.items.single().state=="processing"&&first.nextCursor=="next")
 val second=repo.payments(cursor=first.nextCursor,memberId="member-1");check(second.items.single().id=="tx-2")
 val calls=api.calls.filter{it.path.contains("/payments?")};check(calls.size==2&&calls.all{it.path.contains("memberId=member-1")}&&calls.last().path.contains("cursor=next"))
 paymentState="corrected"
 val correctedRecord=repo.payments(memberId="member-1").items.single();check(correctedRecord.state=="corrected")
 val before=api.calls.size
 val corrected=runCatching{repo.allocate(correctedRecord,Member("member-1","Example Member","+250780000816",0,true,1),"verified member")}.exceptionOrNull()
 check(corrected is ContractFailure&&corrected.code=="allocation_unavailable"&&api.calls.size==before)
 bad=true
 val wrong=runCatching{repo.payments(memberId="member-1")}.exceptionOrNull()
 check(wrong is ContractFailure&&wrong.code=="invalid_member_payment_scope")
 val wrongNext=runCatching{repo.payments(cursor="next",memberId="member-1")}.exceptionOrNull()
 check(wrongNext is ContractFailure&&wrongNext.code=="invalid_member_payment_scope")
 val detail=payment("tx-1","member-1").put("sourceId","source-1")
 val negotiated=JSONObject().put("payment",detail).put("paymentReference","100000000017")
 api.handler={check(it.path.endsWith("/payments/tx-1"));negotiated.toString()}
 val expanded=repo.payment("tx-1")
 check(expanded.paymentReference=="100000000017"&&expanded.id=="tx-1"&&expanded.ftId=="10001"&&expanded.sourceId=="source-1"&&expanded.state=="corrected")
 api.handler={throw ApiFailure("connection_unavailable",0)}
 check(repo.payment("tx-1")==expanded&&repo.lastReadFromCache)
 api.handler={detail.toString()};val predecessor=repo.payment("tx-1")
 check(predecessor==expanded.copy(paymentReference=null))
 api.handler={throw ApiFailure("connection_unavailable",0)}
 check(repo.payment("tx-1")==predecessor&&repo.lastReadFromCache)
 val scope=mapOf<String,Any?>("groupId" to "group-1","actorId" to "admin-1","generation" to "1")
 for((path,group) in listOf("/payments/tx-2" to "group-1","/payments/tx-1" to "other-group")){
     val denied=runCatching{api.validateCached(path,negotiated.toString(),scope+("groupId" to group))}.exceptionOrNull()
     check(denied is ApiFailure&&denied.code=="contract_identity")
 }
 println("PASS payment detail and the session-owned cache preserve upgraded and predecessor references")
 println("PASS member payment pages keep scope and state, and reject a mismatched member")
}
