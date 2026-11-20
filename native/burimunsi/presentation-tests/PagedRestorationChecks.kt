package rw.ikanisa.burimunsi.pagedrestorationtests
import rw.ikanisa.burimunsi.core.*
fun main(){
 var checks=0;var combinations=0
 fun ck(s:String,b:Boolean){check(b){s};println("PASS $s");checks++}
 fun d(route:Route=Route.PAYMENTS,target:Int=50,count:Int=10,cursor:String?="next",pages:Int=1,offline:Boolean=false,fresh:Boolean=true,offset:Int=12)=PagedRestoration.decide(route,target,offset,count,cursor,pages,offline,fresh)
 ck("header counts match rendered lists",listOf(Route.PAYMENTS,Route.MEMBERS,Route.MEMBER,Route.SMS).map{PagedRestoration.headerItems(it)}==listOf(2,1,5,3))
 for(route in listOf(Route.PAYMENTS,Route.MEMBERS,Route.MEMBER,Route.SMS)){
  val h=PagedRestoration.headerItems(route)
  for(count in listOf(0,1,30,2000))for(target in listOf(0,h,h+count,100000))for(cursor in listOf(null,"next"))for(pages in listOf(1,16))for(offline in listOf(false,true))for(fresh in listOf(false,true)){
   val r=d(route,target,count,cursor,pages,offline,fresh)
   check(r.index<=target&&r.index<=h+maxOf(count,1)-1);check(r.index==target||r.offset==0)
   if(r.fetchNext)check(cursor!=null&&!offline&&fresh&&pages<16&&count<2000)
   combinations++
  }
  ck("$route restores exact loaded position",d(route,h+2,10).let{!it.fetchNext&&it.index==h+2&&it.offset==12&&it.stop==ListRestoreStop.POSITION_READY})
  ck("$route preserves header position",d(route,h-1,0,null).let{it.index==h-1&&it.offset==12&&!it.fetchNext})
  ck("$route shortened list clamps and resets offset",d(route,100,2,null).let{it.index==h+1&&it.offset==0&&it.stop==ListRestoreStop.END_REACHED})
  ck("$route empty list is bounded",d(route,100,0,null).let{it.index==h&&it.offset==0&&!it.fetchNext})
 }
 ck("unloaded target permits next read",d().fetchNext)
 ck("cache never triggers automatic crawl",d(offline=true).stop==ListRestoreStop.OFFLINE)
 ck("unknown freshness stops paging",d(fresh=false).stop==ListRestoreStop.STALE)
 ck("page budget enforced",d(pages=16).stop==ListRestoreStop.BUDGET_REACHED)
 ck("item budget enforced",d(target=4000,count=2000).stop==ListRestoreStop.BUDGET_REACHED)
 ck("ready position never fetches unnecessarily",!d(target=2,offline=true,fresh=false,pages=16).fetchNext)
 for(i in listOf(-1,100001))ck("invalid index $i rejected",runCatching{d(target=i)}.isFailure)
 for(i in listOf(-1,100001))ck("invalid offset $i rejected",runCatching{d(offset=i)}.isFailure)
 ck("nonpaged route rejected",runCatching{d(route=Route.HOME)}.isFailure)
 ck("negative count rejected",runCatching{d(count=-1)}.isFailure)
 ck("missing first page rejected",runCatching{d(pages=0)}.isFailure)
 ck("complete restoration has no warning",PagedRestoration.label(null)==null&&PagedRestoration.label(ListRestoreStop.POSITION_READY)==null)
 ck("all partial results have notice",ListRestoreStop.values().filter{it!=ListRestoreStop.POSITION_READY}.all{PagedRestoration.label(it)!=null})
 println("RESULT: $checks pure paged-restoration checks passed; $combinations decision combinations exercised.")
}
