package rw.ikanisa.burimunsi.data
import android.app.Application
import org.json.JSONObject
import org.json.JSONArray
import rw.ikanisa.burimunsi.core.*
class ApiFailure(val code:String,val status:Int=400,val uncertain:Boolean=false):RuntimeException(code)
class ManagedRequestAccess(val token:String,val collectionId:String)
fun interface ManagedSessionTokenProvider { fun currentAccessToken():String?;fun currentAccessContext():ManagedRequestAccess?=null;fun currentCollectionId():String?=null }
interface ManagedSessionHost { val managedSessionTokenProvider:ManagedSessionTokenProvider;fun signOutManagedSession(){} }
class ApiClient(origin:String,id:String,token:()->String?){
 companion object{fun phonePin(origin:String,id:String,profile:String,prefix:String,publicKey:String="",token:()->String)=ApiClient(origin,id,token)}
 constructor(origin:String,id:String,provider:ManagedSessionTokenProvider,token:()->String?):this(origin,id,token)
 constructor(origin:String,id:String,prefix:String,token:()->String?):this(origin,id,token)
 constructor(origin:String,id:String,provider:ManagedSessionTokenProvider,prefix:String,token:()->String?):this(origin,id,provider,token)
}
class SupportContactClient(origin:String,prefix:String,publicKey:String=""){fun read():String?=Fixture.supportFetch()}
data class CapturedListingQuery(val target:ListingTarget,val query:ListingQuery,val cursor:String?,val memberId:String?,val limit:Int=100)
class RecordReadScope internal constructor(private val owner:Any,private val verify:()->Unit){
 internal fun validate(expected:Any){checkContract(owner===expected,"session_changed");verify()}
 override fun toString()="RecordReadScope"
}
object Fixture{
 @Volatile var supportFetch:()->String?={null}
 @Volatile var managedCollection:String?="synthetic-group"
 val repositoryCollections=java.util.concurrent.CopyOnWriteArrayList<String>()
 val enrollmentCollections=java.util.concurrent.CopyOnWriteArrayList<String>()
 var loginCalls=0;val loginCollections=java.util.concurrent.CopyOnWriteArrayList<String>();var gatewayPairCalls=0
 @Volatile var loginEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var loginBarrier:java.util.concurrent.CountDownLatch?=null
 @Volatile var sessionEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var sessionBarrier:java.util.concurrent.CountDownLatch?=null
 var onboardingPreviews=0;var onboardingImports=0;var lastOnboardingConsent:Boolean?=null;var lastOnboardingMimeType:String?=null
 var gatewayPairFailure:ApiFailure?=null;var gatewayCredentialsInstalled=0
 var retirementPendingFlag=false;var retirementRecordPresent=false;var retirementUnknown=false;var retirementAckReady=false
 var retirementRecoveryReads=0;var clearOperatorCalls=0;var logoutCalls=0;var restoreReads=0
 var lastStaffBody:JSONObject?=null;var lastStaffAutoResolve=false;var staffAutoOutcome:String?=null
 @Volatile var enrollEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var enrollBarrier:java.util.concurrent.CountDownLatch?=null
 @Volatile var enrollResponseId:String?="member-1"
 @Volatile var enrollResponseGroup:String?=null
 @Volatile var memberReadFailure:ApiFailure?=null
 @Volatile var membersFailure:ApiFailure?=null
 @Volatile var membersCachedOverride:Boolean?=null
 @Volatile var membersSavedAtOverride:Long?=null
 var financialState="posted"
 @Volatile var currentOwnerOverride:String?=null
 @Volatile var processSessionInvalidated=false
 @Volatile var reattachAllowed=false
 @Volatile var reattachEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var reattachRelease:java.util.concurrent.CountDownLatch?=null
 val processSessionObservers=java.util.concurrent.CopyOnWriteArrayList<()->Unit>()
 val processSessionEpoch=java.util.concurrent.atomic.AtomicLong()
 fun invalidateProcessSession(){processSessionEpoch.incrementAndGet();processSessionInvalidated=true;processSessionObservers.forEach{it()}}
 val listingQueries=java.util.concurrent.CopyOnWriteArrayList<CapturedListingQuery>()
 @Volatile var listingQueryObserver:((CapturedListingQuery)->Unit)?=null
 @Volatile var paged:((String,String?,String,String)->Page<String>)?=null
 @Volatile var journalFailure=false
 @Volatile var restoreSignedOut=false
 @Volatile var restoreFailure:ApiFailure?=null
 @Volatile var restoreEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var restoreBarrier:java.util.concurrent.CountDownLatch?=null
 @Volatile var renewedExpiry:Long?=null
 @Volatile var ownerId="operator"
 @Volatile var readFailure:ApiFailure?=null
 @Volatile var memberPaymentScopeFailureOnCursor=false
 @Volatile var paymentsBarrier:java.util.concurrent.CountDownLatch?=null
 @Volatile var paymentsEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var missingReadTimestamp=false
 @Volatile var readEmpty=false
 @Volatile var pinUncertain=false
 @Volatile var pinFailure:ApiFailure?=null
 @Volatile var logoutFailure:ApiFailure?=null
 @Volatile var recoveryFailure:ApiFailure?=null
 @Volatile var staffFailure:ApiFailure?=null
 @Volatile var resolveOnCheck=false
 var pendingFlag=false;var outcomeState="committed";var exportReads=0;var lastExportMember="";var sessionReads=0;var sessionFailure:ApiFailure?=null
 var homeBarrier:java.util.concurrent.CountDownLatch?=null
 var allocateBarrier:java.util.concurrent.CountDownLatch?=null
 var enrollMutations=0;var staffMutations=0;var reconciles=0
 var historySavedAt:Long?=null

 var paymentFailure=false;var recordSavedAt:Long?=null;var refreshedRole:Role?=null;var refreshedCaps:Set<String>?=null;var paymentReads=0;
 var historyFailure=false;var historyReads=0;var historyRevision="history-v1";var historyLoop=false;var historyOverlap=false;var lastHistoryId="";var historyDelay=0L;
 @Volatile var rawBarrier:java.util.concurrent.CountDownLatch?=null;@Volatile var rawEntered:java.util.concurrent.CountDownLatch?=null;var rawApiFailure:ApiFailure?=null;var lastRawReason=""
 var rawFailure=false;var rawReads=0;var mutations=0;var role=Role.ADMIN;var cached=false;var memberCached=false;var lifecycleCalls=0;var homeReads=0
 var observationReads=0;var observationRevealReads=0;var observationRows:List<ObservationListRow> = emptyList();var observationFailure:ApiFailure?=null
 val smsQueries=java.util.concurrent.CopyOnWriteArrayList<String>();val observationQueries=java.util.concurrent.CopyOnWriteArrayList<String>()
 var smsListRevealReads=0;var observationListRevealReads=0;val listRevealReasons=java.util.concurrent.CopyOnWriteArrayList<String>()
 val listRevealSources=java.util.concurrent.CopyOnWriteArrayList<String>()
 @Volatile var listRevealFailure:ApiFailure?=null;@Volatile var listRevealEntered:java.util.concurrent.CountDownLatch?=null;@Volatile var listRevealRelease:java.util.concurrent.CountDownLatch?=null
 @Volatile var observationPaged:((String,String?)->Page<ObservationListRow>)?=null
 val listBodies=java.util.concurrent.ConcurrentHashMap<String,String>()
 var observationBody="synthetic unverified message";var observationHints:ObservationHintSet?=null
 var lastFilter="";val saved=1794063600000L
 fun operator()=Operator(ownerId, "Example Operator", "+250780000001",role,Capability.entries.map{it.key}.toSet(),System.currentTimeMillis()+3600000)
 val member=Member("member-1","Example Member","+250780000816",10000,true,1)
 fun payment(id:String="tx-1")=Payment(id,"Example Payer","+250780000816",10000,"2026-11-07 12:00:00","90001","unallocated",1)
 fun <T> page(items:List<T>,next:String?=null)=Page(items,next,2,"v1","2026-11-07T12:00:00Z")
}
class NativeRepository(app:Application,api:ApiClient,group:String?=null){
 private val readScopeOwner=Any();private var readScopeRevision=0L
 private var bound=group?:Fixture.managedCollection.takeUnless{Fixture.restoreSignedOut}
 val boundCollectionId:String? get()=bound
 val collectionId:String get()=bound?:throw ApiFailure("session_unavailable",401)
 init{Fixture.repositoryCollections.add(group?:"<unbound>")}
 var lastReadFromCache=false;var lastReadSavedAt:Long?=null;private var operator:Operator?=if(Fixture.restoreSignedOut)null else Fixture.operator()
 private fun provenance(cached:Boolean=Fixture.cached){lastReadFromCache=cached;lastReadSavedAt=if(Fixture.missingReadTimestamp)null else if(cached)Fixture.saved else Fixture.recordSavedAt?:System.currentTimeMillis()}
 fun restore():Operator?{Fixture.restoreReads++;Fixture.restoreEntered?.countDown();
  check(Fixture.restoreBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false)
  Fixture.restoreFailure?.let{throw it};return operator}
 fun current()=operator?.takeUnless{Fixture.processSessionInvalidated}?.let{it.copy(id=Fixture.currentOwnerOverride?:it.id)}
 fun login(phone:String,pin:String):Operator{Fixture.loginCalls++;Fixture.loginEntered?.countDown();check(Fixture.loginBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);val selected=Fixture.managedCollection?:throw ApiFailure("invalid_credentials",401);bound=selected;Fixture.loginCollections.add(selected);readScopeRevision++;operator=Fixture.operator();return operator!!}
 fun pairGateway(code:String,replace:Boolean):JSONObject{
  if(operator==null)throw ApiFailure("session_unavailable",401);Fixture.gatewayPairCalls++
  Fixture.gatewayPairFailure?.let{if(it.status==401)operator=null;throw it}
  if(replace){
   Fixture.retirementRecordPresent=true
   if(Fixture.retirementUnknown){Fixture.retirementPendingFlag=true;throw ApiFailure("gateway_retirement_unconfirmed",0,true)}
   return retirementAck()
  }
  Fixture.gatewayCredentialsInstalled++;return JSONObject().put("groupId",collectionId)
 }
 private fun retirementAck()=JSONObject().put("handoffId","ac100000-0000-4000-8000-000000000101").put("requestId","ac100000-0000-4000-8000-000000000102")
 fun hasPendingReceiverRetirement()=Fixture.retirementPendingFlag
 fun hasReceiverRetirementRecord()=Fixture.retirementRecordPresent||Fixture.retirementPendingFlag
 fun recoverReceiverRetirement():JSONObject?{Fixture.retirementRecoveryReads++;if(!Fixture.retirementAckReady)return null;Fixture.retirementPendingFlag=false;return retirementAck()}
 fun logout(){Fixture.logoutCalls++;readScopeRevision++;operator=null;Fixture.logoutFailure?.let{throw it}};fun clearOperator(){Fixture.clearOperatorCalls++;readScopeRevision++;operator=null};fun refreshSession():Operator{Fixture.sessionReads++;Fixture.sessionEntered?.countDown();check(Fixture.sessionBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);Fixture.sessionFailure?.let{if(it.status==401){readScopeRevision++;operator=null};throw it};operator=operator!!.copy(role=Fixture.refreshedRole?:operator!!.role,capabilities=Fixture.refreshedCaps?:operator!!.capabilities,expiresAt=Fixture.renewedExpiry?:operator!!.expiresAt);return operator!!}
 fun retryPendingSignOuts():Boolean=true
 fun observeProcessSession(listener:()->Unit):()->Unit{Fixture.processSessionObservers.add(listener);return {Fixture.processSessionObservers.remove(listener)}}
 fun hasPendingPasscode():Boolean=Fixture.pinUncertain
 fun hasSavedSession():Boolean=Fixture.restoreFailure!=null
 fun reattachSameOwner(owner:String,collection:String):Operator?{
  Fixture.reattachEntered?.countDown();check(Fixture.reattachRelease?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false)
  val current=operator?:return null
  if(!Fixture.reattachAllowed||current.id!=owner||bound!=collection)return null
  Fixture.processSessionInvalidated=false;return current
 }
 fun pending():Any?{if(Fixture.journalFailure)throw ContractFailure("operation_store_unavailable");return if(Fixture.pendingFlag)"original-operation" else null}
 fun reconcilePending():JSONObject{Fixture.reconciles++;Fixture.recoveryFailure?.let{throw it};if(Fixture.resolveOnCheck&&Fixture.outcomeState in setOf("committed","cancelled"))Fixture.pendingFlag=false;return JSONObject().put("state",Fixture.outcomeState).put("financialState",Fixture.financialState)}
 fun home():Home{Fixture.readFailure?.let{throw it};provenance();Fixture.homeReads++;check(Fixture.homeBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);return Home(10000,10000,1,1,listOf(Fixture.payment()),"now")}
 fun recordReadScope():RecordReadScope{
  val who=current()?:throw ContractFailure("session_unavailable");val collection=collectionId;val revision=readScopeRevision
  val epoch=Fixture.processSessionEpoch.get();val caps=who.capabilities.toSet()
  checkContract(!Fixture.pinUncertain&&who.expiresAt>System.currentTimeMillis(),"session_unavailable")
  return RecordReadScope(readScopeOwner){
   val now=current()?:throw ContractFailure("session_changed")
   checkContract(revision==readScopeRevision&&epoch==Fixture.processSessionEpoch.get()&&collection==bound&&now.id==who.id&&now.role==who.role&&now.capabilities==caps&&now.expiresAt>System.currentTimeMillis()&&!Fixture.pinUncertain,"session_changed")
  }
 }
 fun validateRecordReadScope(scope:RecordReadScope){scope.validate(readScopeOwner)}
 private fun <T> typedListing(target:ListingTarget,query:ListingQuery,cursor:String?,memberId:String?,scope:RecordReadScope?,limit:Int=100,read:()->T):T{
  query.validated(target);checkContract(limit in 1..100,"invalid_query");scope?.let(::validateRecordReadScope)
  val captured=CapturedListingQuery(target,query,cursor,memberId,limit);Fixture.listingQueries.add(captured);Fixture.listingQueryObserver?.invoke(captured)
  if(scope!=null&&Fixture.cached)throw ApiFailure("connection_unavailable",0)
  val value=read();scope?.let(::validateRecordReadScope);return value
 }
 fun payments(listing:ListingQuery,cursor:String?=null,memberId:String?=null,scope:RecordReadScope?=null):Page<Payment> =
  typedListing(ListingTarget.PAYMENTS,listing,cursor,memberId,scope){payments(listing.q,listing.filter,cursor,memberId)}
 fun members(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<Member> =
  typedListing(ListingTarget.MEMBERS,listing,cursor,null,scope){members(listing.q,cursor)}
 fun ledger(id:String,listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<LedgerRow> =
  typedListing(ListingTarget.LEDGER,listing,cursor,id,scope){ledger(id,cursor)}
 fun sms(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null,limit:Int=100):Page<SmsRow> =
  typedListing(ListingTarget.SMS,listing,cursor,null,scope,limit){sms(listing.q,cursor,listing.filter,limit)}
 fun observationPage(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null,limit:Int=100):Page<ObservationListRow> =
  typedListing(ListingTarget.OBSERVATIONS,listing,cursor,null,scope,limit){observationPage(listing.q,cursor,limit)}
 fun staff(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<StaffAccount> =
  typedListing(ListingTarget.STAFF,listing,cursor,null,scope){staff(cursor)}
 fun audit(listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<AuditRow> =
  typedListing(ListingTarget.AUDIT,listing,cursor,null,scope){audit(cursor)}
 fun paymentHistory(id:String,listing:ListingQuery,cursor:String?=null,scope:RecordReadScope?=null):Page<PaymentEvent> =
  typedListing(ListingTarget.HISTORY,listing,cursor,id,scope){paymentHistory(id,cursor)}
 fun payments(q:String="",filter:String="all",cursor:String?=null,memberId:String?=null):Page<Payment>{Fixture.paymentsEntered?.countDown();check(Fixture.paymentsBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);Fixture.readFailure?.let{throw it};if(memberId!=null&&cursor!=null&&Fixture.memberPaymentScopeFailureOnCursor)throw ContractFailure("invalid_member_payment_scope");provenance();Fixture.lastFilter=filter;Fixture.paged?.let{handler->val p=handler(if(memberId==null)"PAYMENTS"else "MEMBER",cursor,memberId?:q,filter);provenance();return Page(p.items.map{Fixture.payment(it).copy(memberId=memberId)},p.nextCursor,p.totalCount,p.revision,p.asOf)};if(Fixture.readEmpty)return Page(emptyList(),null,0,"empty","2026-11-09T00:00:00Z");return Fixture.page(listOf(Fixture.payment(if(cursor==null)"tx-1" else "tx-2").copy(memberId=memberId)),if(memberId==null&&cursor==null)"more" else null)}
 fun members(q:String="",cursor:String?=null):Page<Member>{
  Fixture.membersFailure?.let{if(it.status==401)operator=null;throw it}
  fun memberProvenance(){provenance(Fixture.membersCachedOverride?:Fixture.cached);Fixture.membersSavedAtOverride?.let{lastReadSavedAt=it}}
  memberProvenance();Fixture.paged?.let{handler->val p=handler("MEMBERS",cursor,q,"all");memberProvenance();return Page(p.items.map{Fixture.member.copy(id=it)},p.nextCursor,p.totalCount,p.revision,p.asOf)};return Fixture.page(listOf(Fixture.member.copy(id=if(cursor==null)"member-1" else "member-2")),if(cursor==null)"more" else null)
 }
 fun payment(id:String):Payment{Fixture.paymentReads++;if(Fixture.paymentFailure)throw ApiFailure("connection_unavailable",0);provenance();return Fixture.payment(id)}
 fun member(id:String):Member{Fixture.memberReadFailure?.let{throw it};provenance(Fixture.memberCached||Fixture.cached);return Fixture.member.copy(id=id)}
 fun ledger(id:String,cursor:String?=null):Page<LedgerRow>{provenance();Fixture.paged?.let{handler->val p=handler("MEMBER",cursor,id,"all");provenance();return Page(p.items.map{LedgerRow(it,"tx-1",10000,"at","90001","Payer")},p.nextCursor,p.totalCount,p.revision,p.asOf)};return Fixture.page(listOf(LedgerRow("l-1","tx-1",10000,"at","90001","Payer")))}
 fun sms(q:String="",cursor:String?=null,filter:String="all",limit:Int?=null):Page<SmsRow>{Fixture.smsQueries.add(q);Fixture.lastFilter=filter;Fixture.paged?.let{handler->val p=handler("SMS",cursor,q,filter);return Page(p.items.map{SmsRow(it,"M-Money","at","synthetic",filter,null)},p.nextCursor,p.totalCount,p.revision,p.asOf)};return Fixture.page(listOf(SmsRow("s-1","M-Money","at","synthetic",filter,null)))}
 fun observationPage(q:String="",cursor:String?=null,limit:Int?=null):Page<ObservationListRow> {Fixture.observationQueries.add(q);Fixture.observationReads++;Fixture.observationFailure?.let{throw it};Fixture.observationPaged?.let{return it(q,cursor)};return Page(Fixture.observationRows,null,Fixture.observationRows.size,"observations-v1","2026-11-09T00:00:00Z")}
 fun observationProcessing(sources:List<SmsSourceRef.Observation>):Map<SmsSourceRef.Observation,ObservationProcessing> = emptyMap()
 fun retryObservation(source:SmsSourceRef.Observation,requestId:String):String = "scheduled"
 fun revealObservation(source:SmsSourceRef.Observation,reason:String):ObservationDisclosure{
  if(reason=="Automatic SMS list preview"){Fixture.observationListRevealReads++;Fixture.listRevealReasons.add(reason);Fixture.listRevealSources.add("observation:"+source.id);Fixture.listRevealEntered?.countDown();check(Fixture.listRevealRelease?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);Fixture.listRevealFailure?.let{throw it};return ObservationDisclosure(source,"2026-11-09T00:00:00Z","SyntheticSender",Fixture.listBodies[source.id]?:Fixture.observationBody)}
  Fixture.observationRevealReads++;return ObservationDisclosure(source,"2026-11-09T00:00:00Z","M-Money",Fixture.observationBody,Fixture.observationHints)
 }
 fun staff(cursor:String?=null):Page<StaffAccount> =Fixture.page(listOf(StaffAccount(if(cursor==null)"staff-1" else "staff-2","Staff","+250780000002",true,1,emptySet())),if(cursor==null)"more" else null)
 fun audit(cursor:String?=null):Page<AuditRow> =Fixture.page(listOf(AuditRow(if(cursor==null)"audit-1" else "audit-2","Action","at")),if(cursor==null)"more" else null)
 fun raw(id:String,reason:String):RawSms{
  if(reason=="Automatic SMS list preview"){Fixture.smsListRevealReads++;Fixture.listRevealReasons.add(reason);Fixture.listRevealSources.add("canonical:"+id);Fixture.listRevealEntered?.countDown();check(Fixture.listRevealRelease?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);Fixture.listRevealFailure?.let{throw it};return RawSms(id,"SyntheticSender","at",Fixture.listBodies[id]?:"synthetic canonical body",null)}
  Fixture.rawReads++;Fixture.lastRawReason=reason;Fixture.rawEntered?.countDown();check(Fixture.rawBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);Fixture.rawApiFailure?.let{throw it};if(Fixture.rawFailure)throw ApiFailure("connection_unavailable",0);return RawSms(id,"M-Money","at","unaltered", "tx-1")
 }
 fun allocate(p:Payment,m:Member,note:String):JSONObject{Fixture.mutations++;check(Fixture.allocateBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);return JSONObject()}
 fun enroll(name:String,phone:String):JSONObject{Fixture.enrollMutations++;Fixture.enrollmentCollections.add(collectionId);Fixture.enrollEntered?.countDown();check(Fixture.enrollBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);return JSONObject().put("groupId",Fixture.enrollResponseGroup?:collectionId).also{j->Fixture.enrollResponseId?.let{j.put("createdMemberId",it)}}}
 fun onboardingSuggestions(q:String,cursor:String?):JSONObject=JSONObject().put("items",JSONArray()).put("nextCursor",null)
 fun onboardingPreview(mimeType:String,bytes:ByteArray,consent:Boolean):JSONObject{
  Fixture.onboardingPreviews++
  Fixture.lastOnboardingConsent=consent;Fixture.lastOnboardingMimeType=mimeType
  val rows=JSONArray().put(JSONObject().put("row",1).put("momoName","Example Member").put("momoNumber","bad").put("status","invalid").put("issue","invalid_phone").put("selected",false))
  return JSONObject().put("sourceKind","csv").put("rows",rows)
 }
 fun onboardingImport(rows:JSONArray):JSONObject{
  Fixture.onboardingImports++
  val results=JSONArray();for(i in 0 until rows.length())results.put(JSONObject().put("row",rows.getJSONObject(i).getInt("row")).put("status","created").put("memberId","member-1"))
  return JSONObject().put("importResult",JSONObject().put("results",results).put("created",rows.length()))
 }
 fun staffAction(body:JSONObject,resolveBlankPhoneDenial:Boolean=false):JSONObject{
  Fixture.staffMutations++;Fixture.lastStaffBody=body;Fixture.lastStaffAutoResolve=resolveBlankPhoneDenial
  Fixture.staffFailure?.let{error->
   when(if(resolveBlankPhoneDenial)Fixture.staffAutoOutcome else null){
    "cancelled"->{Fixture.pendingFlag=false;throw error}
    "committed"->{Fixture.pendingFlag=false;return JSONObject().put("state","committed")}
    else->{Fixture.pendingFlag=true;throw error}
   }
  };return JSONObject()
 }
 fun setMemberActive(m:Member,active:Boolean):JSONObject{Fixture.lifecycleCalls++;return JSONObject()}
 fun changePin(current:String,next:String,confirm:String):Operator{
  Fixture.pinFailure?.let{throw it}
  if(Fixture.pinUncertain){operator=null;Fixture.pendingFlag=true;throw ApiFailure("passcode_change_unconfirmed",503,true)}
  return operator?:throw ApiFailure("session_unavailable",401)
 }
 fun paymentHistory(id:String,cursor:String?=null):Page<PaymentEvent>{
  Fixture.historyReads++;Fixture.lastHistoryId=id;if(Fixture.historyDelay>0)Thread.sleep(Fixture.historyDelay)
  if(Fixture.historyFailure)throw ApiFailure("connection_unavailable",0)
  provenance();Fixture.historySavedAt?.let{lastReadSavedAt=it};val first=cursor==null||Fixture.historyOverlap
  val event=if(first)PaymentEvent("transaction:$id",id,"transaction_recorded","2026-11-08T10:00:00Z",null,null)
    else PaymentEvent("ledger:l-1",id,"ledger_entry","2026-11-08T10:00:01Z",10000,"member-1")
  return Page(listOf(event),if(cursor==null||Fixture.historyLoop)"history-more" else null,2,Fixture.historyRevision,"2026-11-08T10:00:02Z")
 }
 fun exportMember(id:String):String{Fixture.exportReads++;Fixture.lastExportMember=id;return "synthetic csv"}
}
