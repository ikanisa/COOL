package rw.ikanisa.burimunsi.pagedviewmodeltests
import android.app.Application
import androidx.lifecycle.onFixtureMain
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import app.cool.mobile.BuildConfig
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
private class MemoryCheckpoint(initial:String?):NavigationCheckpointStore{
 @Volatile var value=initial
 override fun read()=value
 override fun write(value:String){this.value=value}
 override fun clear(){value=null}
}
fun main()=runBlocking{
 var checks=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
 val realNow=System.currentTimeMillis();var now=realNow+2000
 fun reset(){
  Fixture.paged=null;Fixture.anchoredMembers=null;Fixture.currentOwnerOverride=null;Fixture.receiverGroupOverride=null;Fixture.pendingFlag=true;Fixture.journalFailure=false;Fixture.cached=false
  Fixture.recordSavedAt=null;Fixture.missingReadTimestamp=false;Fixture.ownerId="operator"
  Fixture.restoreSignedOut=false;Fixture.role=Role.ADMIN;Fixture.readFailure=null
  Fixture.mutations=0;Fixture.reconciles=0;Fixture.enrollMutations=0;Fixture.staffMutations=0
  Fixture.memberCached=false;Fixture.memberPaymentScopeFailureOnCursor=false;now=realNow+2000
 }
 suspend fun idle(vm:BuriViewModel){withTimeout(10000){while(vm.state.busy)delay(2)};delay(20)}
 fun start(route:Route=Route.PAYMENTS,index:Int=12,anchor:String?=null,listing:ListingQuery?=null):Pair<BuriViewModel,MemoryCheckpoint>{
  val cp=NavigationCheckpoint("operator",Fixture.managedCollection!!,realNow,route,
   routeId=if(route==Route.MEMBER)"member-1" else null,query="needle",
   filter=when(route){Route.PAYMENTS->"unallocated";else->"all"},index=index,offset=27,memberAnchorId=anchor,memberListing=listing)
  val store=MemoryCheckpoint(cp.encode());return BuriViewModel(Application(),store){now} to store
 }
 fun page(cursor:String?,total:Int=40,size:Int=4):Page<String>{
  val begin=cursor?.toInt()?:0;val end=minOf(begin+size,total)
  return Page((begin until end).map{"record-$it"},if(end<total)end.toString() else null,total,"stable","2026-11-09T09:00:00Z")
 }
 fun count(vm:BuriViewModel)=when(vm.state.route){
  Route.PAYMENTS->vm.state.payments!!.items.size;Route.MEMBERS->vm.state.members!!.items.size
  Route.MEMBER->vm.state.memberTransactions!!.items.size;Route.SMS->vm.state.messages!!.items.size;else->0
 }
 val routes=listOf(Route.PAYMENTS,Route.MEMBERS,Route.MEMBER)+if(BuildConfig.IS_GATEWAY)listOf(Route.SMS)else emptyList()
 for(route in routes){
  reset();val requests=mutableListOf<String?>();val contexts=mutableListOf<Pair<String,String>>()
  Fixture.paged={r,c,q,f->check(r==route.name);requests.add(c);contexts.add(q to f);page(c)}
  val target=PagedRestoration.headerItems(route)+10;val (vm,store)=start(route,target);idle(vm)
  val firstOnly=route in setOf(Route.SMS,Route.MEMBERS)
  val expectedIndex=when(route){Route.SMS->0;Route.MEMBERS->PagedRestoration.headerItems(route)+3;else->target}
  val expectedStop=if(route==Route.MEMBERS)ListRestoreStop.BUDGET_REACHED else ListRestoreStop.POSITION_READY
  ck("$route loads the appropriate pages from a fresh cursor",if(firstOnly)requests==listOf(null)&&count(vm)==4 else requests==listOf(null,"4","8")&&count(vm)==12)
  ck("$route retains safe position",vm.state.listIndex==expectedIndex&&vm.state.listOffset==(if(firstOnly)0 else 27))
  ck("$route preserves permitted query or member scope",contexts.all{it.first==when(route){Route.MEMBER->"member-1";Route.SMS->"";else->"needle"}})
  ck("$route preserves filter",contexts.all{it.second==when(route){Route.PAYMENTS->"unallocated";else->"all"}})
  ck("$route keeps journal without replay",vm.state.pending&&Fixture.mutations==0&&Fixture.reconciles==0&&Fixture.enrollMutations==0&&Fixture.staffMutations==0)
  ck("$route no panel draft or beneficiary restored",vm.state.sheet==null&&vm.state.draft.isEmpty()&&vm.state.selectedMember==null)
  ck("$route saves navigation only",NavigationCheckpoint.decode(store.value)?.index==expectedIndex&&vm.state.listRestoration==expectedStop)
  vm.viewModelScope.cancel()
 }
 for(present in listOf(true,false)){
  reset();var anchoredReads=0
  val listing=ListingQuery(q="needle",sort=ListingSort.NAME_DESC,active="active")
  Fixture.paged={_,_,_,_->error("anchor restore must not replay earlier pages")}
  Fixture.anchoredMembers={anchor,query->
   check(anchor=="record-32"&&query==listing);anchoredReads++
   page(if(present)"32" else null)
  }
  val (anchored,bookmark)=start(Route.MEMBERS,35,anchor="record-32",listing=listing);idle(anchored)
  ck("Members checks the selected row with one page",anchoredReads==1&&anchored.state.members?.items?.firstOrNull()?.id==(if(present)"record-32" else "record-0"))
  ck("Members keeps a verified anchor or resets a missing one",anchored.state.memberAnchorId==(if(present)"record-32" else null)&&
   anchored.state.listIndex==(if(present)PagedRestoration.headerItems(Route.MEMBERS) else 0)&&anchored.state.listOffset==(if(present)27 else 0))
  ck("Members retains search and sort without persisting a cursor",NavigationCheckpoint.decode(bookmark.value)?.memberListing==listing&&
   NavigationCheckpoint.decode(bookmark.value)?.memberAnchorId==(if(present)"record-32" else null))
  if(present){
   val members=anchored.state.members!!.items
   val header=PagedRestoration.headerItems(Route.MEMBERS)
   val revision=anchored.state.memberViewportRevision
   anchored.memberListPosition(revision-1,header+1,14,members[1].id)
   ck("a departed member viewport cannot replace the verified anchor",anchored.state.memberAnchorId==members.first().id)
   anchored.memberListPosition(revision,header+1,14,"prior-window-row")
   ck("a layout carrying the earlier row key cannot change the checkpoint",anchored.state.memberAnchorId==members.first().id)
   anchored.memberListPosition(revision,header+1,14,members[1].id)
   ck("the measured current member row can update the bookmark",anchored.state.memberAnchorId==members[1].id&&anchored.state.listOffset==14)
   anchored.listPosition(Route.MEMBERS,null,header+members.size,21)
   ck("pagination bookmarks the last visible member with no footer offset",anchored.state.memberAnchorId==members.last().id&&
    anchored.state.listIndex==header+members.lastIndex&&anchored.state.listOffset==0)
  }
  anchored.viewModelScope.cancel()
 }
 reset();var reads=0;Fixture.paged={_,c,_,_->reads++;page(c,total=5)}
 val (shortened,shortStore)=start(index=999);idle(shortened)
 ck("shorter dataset clamps with zero offset",reads==2&&shortened.state.listIndex==8&&shortened.state.listOffset==0)
 ck("shorter dataset exposes explicit notice",shortened.state.listRestoration==ListRestoreStop.END_REACHED&&PagedRestoration.label(shortened.state.listRestoration)!=null)
 ck("clamped bookmark points inside loaded list",NavigationCheckpoint.decode(shortStore.value)?.index==8);shortened.viewModelScope.cancel()
 reset();reads=0;Fixture.paged={_,c,_,_->reads++;page(c,total=500,size=1)}
 val (bounded,_)=start(index=90000);idle(bounded)
 ck("large index cannot cause unbounded reads",reads==16&&count(bounded)==16&&bounded.state.listRestoration==ListRestoreStop.BUDGET_REACHED)
 ck("budget leaves cursor for manual continuation",bounded.state.payments?.nextCursor=="16"&&bounded.state.listIndex==19)
 bounded.more();idle(bounded)
 ck("explicit Load more works without command replay",reads==17&&count(bounded)==17&&bounded.state.listRestoration==null&&Fixture.reconciles==0);bounded.viewModelScope.cancel()
 reset();reads=0;Fixture.paged={_,c,_,_->reads++;page(c,total=5000,size=1100)}
 val (itemBound,_)=start(index=90000);idle(itemBound)
 ck("item budget prevents oversized publication",reads==2&&count(itemBound)==1100&&itemBound.state.listRestoration==ListRestoreStop.BUDGET_REACHED);itemBound.viewModelScope.cancel()
 reset();reads=0;Fixture.cached=true;Fixture.paged={_,c,_,_->reads++;page(c)}
 val (offline,_)=start(index=30);idle(offline)
 ck("cached first page stops automatic readback",reads==1&&offline.state.offline&&offline.state.listRestoration==ListRestoreStop.OFFLINE)
 ck("offline journal warning preserved",offline.presentation.unresolvedWarning&&Fixture.reconciles==0);offline.viewModelScope.cancel()
 reset();reads=0;Fixture.paged={_,c,_,_->reads++;if(c!=null)Fixture.cached=true;page(c)}
 val (midOffline,_)=start(index=30);idle(midOffline)
 ck("mid-read cache fallback stops further reads",reads==2&&midOffline.state.offline&&count(midOffline)==8&&midOffline.state.listRestoration==ListRestoreStop.OFFLINE);midOffline.viewModelScope.cancel()
 reset();reads=0;Fixture.missingReadTimestamp=true;Fixture.paged={_,c,_,_->reads++;page(c)}
 val (stale,_)=start(index=30);idle(stale)
 ck("unknown provenance stops reads and hides records",reads==1&&stale.state.listRestoration==ListRestoreStop.STALE&&!stale.presentation.showRecords);stale.viewModelScope.cancel()
 for(mode in listOf("revision","total","overlap","empty","loop")){
  reset();reads=0
  Fixture.paged={_,c,_,_->reads++;val p=page(c);if(c==null)p else when(mode){
   "revision"->p.copy(revision="changed");"total"->p.copy(totalCount=41)
   "overlap"->p.copy(items=listOf("record-0","record-5","record-6","record-7"))
   "empty"->p.copy(items=emptyList());else->p.copy(nextCursor="4")
  }}
  val (bad,_)=start(index=30);idle(bad)
  ck("$mode rejects partial publication",bad.state.readbackRequired&&bad.state.payments==null&&!bad.presentation.showRecords&&reads==2)
  ck("$mode preserves unresolved command",bad.state.pending&&Fixture.reconciles==0&&Fixture.mutations==0);bad.viewModelScope.cancel()
 }
 reset();reads=0;Fixture.paged={_,c,_,_->reads++;val p=page(c);if(c=="8")p.copy(nextCursor="4")else p}
 val (cycle,_)=start(index=30);idle(cycle)
 ck("multi-hop cursor cycle rejected with unique rows",reads==3&&cycle.state.readbackRequired&&cycle.state.payments==null);cycle.viewModelScope.cancel()
 reset();reads=0;Fixture.paged={_,c,_,_->reads++;if(c!=null)throw ApiFailure("connection_unavailable",0);page(c)}
 val (lost,_)=start(index=30);idle(lost)
 ck("failed next read never publishes partial restoration",lost.state.payments==null&&lost.state.offline&&lost.state.pending&&reads==2);lost.viewModelScope.cancel()
 reset();reads=0;Fixture.paged={_,c,_,_->reads++;if(c!=null)now=realNow+7200000;page(c)}
 val (expired,expiredStore)=start(index=30);idle(expired)
 ck("expiry during read clears screen and bookmark",expired.state.operator==null&&expired.state.route==Route.LOGIN&&expiredStore.value==null&&reads==2)
 ck("expiry retains journal evidence",expired.state.pending&&Fixture.reconciles==0);expired.viewModelScope.cancel()
 reset();reads=0;Fixture.journalFailure=true;Fixture.paged={_,c,_,_->reads++;page(c)}
 val (journal,_)=start(index=12);idle(journal)
 ck("unavailable journal stays unresolved",journal.state.pending&&journal.presentation.unresolvedWarning&&Fixture.reconciles==0);journal.viewModelScope.cancel()
 reset();reads=0;Fixture.paged={_,c,_,_->reads++;if(c!=null)Fixture.currentOwnerOverride="another";page(c)}
 val (ownerChanged,ownerStore)=start(index=30);idle(ownerChanged)
 ck("owner changes during read cannot publish previous data",reads==2&&ownerChanged.state.operator==null&&ownerChanged.state.payments==null&&ownerStore.value==null)
 ck("owner change does not replay unresolved command",ownerChanged.state.pending&&Fixture.reconciles==0);ownerChanged.viewModelScope.cancel()
 val scopeFailures=mutableListOf<String>()
 for(stage in listOf("first", "more")){
  reset();reads=0
  Fixture.paged={r,c,_,_->
   check(r=="PAYMENTS");reads++
   if((stage=="first")== (c==null)) Fixture.processSessionEpoch.incrementAndGet()
   page(c)
  }
  val (pendingOwner,_)=start(Route.HOME);idle(pendingOwner)
  pendingOwner.onFixtureMain { navigate(Route.PAYMENTS) };idle(pendingOwner)
  if(stage=="more"){
   check(pendingOwner.state.payments?.items?.size==4)
   pendingOwner.onFixtureMain { more() };idle(pendingOwner)
  }
  if(pendingOwner.state.payments!=null||pendingOwner.presentation.showRecords||
      !pendingOwner.state.pending||Fixture.reconciles!=0||Fixture.mutations!=0||reads!=(if(stage=="first")1 else 2)) {
   scopeFailures += "$stage page published after same-operator session generation changed"
  }
  pendingOwner.viewModelScope.cancel()
 }
 for(scope in listOf("session generation","collection")){
  reset();reads=0
  Fixture.paged={_,c,_,_->
   reads++
   if(c=="4"){
    if(scope=="collection")Fixture.receiverGroupOverride="other-collection"
    else Fixture.processSessionEpoch.incrementAndGet()
   }
   page(c)
  }
  val (restoring,_)=start(index=30);idle(restoring)
  if(reads!=2||restoring.state.payments!=null||!restoring.state.pending||
      Fixture.reconciles!=0||Fixture.mutations!=0) scopeFailures += "automatic restore crossed changed $scope"
  restoring.viewModelScope.cancel()
 }
 ck("the original session and collection own first, restored and manually continued pages",scopeFailures.isEmpty().also {
  if(!it)println(scopeFailures.joinToString())
 })
 reset();reads=0;Fixture.recordSavedAt=now+1;Fixture.paged={_,c,_,_->reads++;page(c)}
 val (future,_)=start(index=30);idle(future)
 ck("future timestamp stops restoration and hides records",reads==1&&future.state.listRestoration==ListRestoreStop.STALE&&!future.presentation.showRecords);future.viewModelScope.cancel()
 reset();reads=0;Fixture.pendingFlag=false;Fixture.paged={_,c,_,_->reads++;page(c,total=0)}
 val (empty,_)=start(index=30);idle(empty)
 ck("empty readback is EMPTY not fabricated records",reads==1&&empty.state.payments?.items?.isEmpty()==true&&empty.presentation.state==DisplayState.EMPTY&&empty.state.listIndex==4);empty.viewModelScope.cancel()
 reset();reads=0;Fixture.memberCached=true;Fixture.paged={_,c,_,_->reads++;page(c)}
 val (memberOffline,_)=start(Route.MEMBER,index=30);idle(memberOffline)
 ck("cached member blocks automatic fresh-ledger crawl",reads==1&&memberOffline.state.offline&&memberOffline.state.listRestoration==ListRestoreStop.OFFLINE);memberOffline.viewModelScope.cancel()
 reset();Fixture.pendingFlag=false;Fixture.memberPaymentScopeFailureOnCursor=true;Fixture.paged={_,c,_,_->page(c)}
 val (wrongMember,_)=start(Route.MEMBER,index=30);idle(wrongMember)
 ck("mismatched later member page is quarantined instead of displayed",wrongMember.state.memberTransactions==null&&wrongMember.state.readbackRequired&&!wrongMember.presentation.showRecords)
 wrongMember.viewModelScope.cancel()
 reset();val entered=CountDownLatch(1);val release=CountDownLatch(1)
 Fixture.paged={_,c,_,_->if(c!=null){entered.countDown();check(release.await(5,TimeUnit.SECONDS))};page(c)}
 val (racing,_)=start(index=12)
 check(entered.await(5,TimeUnit.SECONDS));racing.listPosition(Route.PAYMENTS,null,0,0)
 ck("busy layout cannot overwrite target",racing.state.busy&&racing.state.listIndex==12)
 release.countDown();idle(racing)
 ck("recovery retains target after layout race",racing.state.listIndex==12&&count(racing)==12)
 racing.listPosition(Route.PAYMENTS,null,100001,1)
 ck("out of range callback rejected",racing.state.listIndex==12)
 racing.viewModelScope.cancel();reset()
 println("RESULT: $checks actual-ViewModel paged-restoration checks passed; doubles only, not installed-screen acceptance.")
}
