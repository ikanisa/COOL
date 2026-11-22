package rw.ikanisa.burimunsi.managedscopetests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.Fixture

/** Historical suite name retained. The actual entry contract is phone/PIN;
 * repository doubles represent server-selected scope, never a fabricated BFF/JWT. */
fun main()=runBlocking{
 var checks=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
 suspend fun idle(m:BuriViewModel){withTimeout(10_000){while(m.state.busy)delay(2)};delay(15)}
 Fixture.managedCollection=null;Fixture.restoreSignedOut=true;Fixture.repositoryCollections.clear();Fixture.loginCalls=0;Fixture.loginCollections.clear()
 val first=BuriViewModel(Application());idle(first)
 ck("fresh plain Android host constructs an unbound repository and original login",Fixture.repositoryCollections.toList()==listOf("<unbound>")&&!first.state.configurationRequired&&first.state.operator==null&&first.state.route==Route.LOGIN)
 first.login("0780000001","2468");idle(first)
 ck("missing approved phone identity fails at real login without business records",Fixture.loginCalls==1&&first.state.operator==null&&first.state.home==null)
 Fixture.managedCollection="approved-group-A";first.login("0780000001","2468");idle(first)
 ck("phone PIN accepts only server-selected collection and reaches Home",Fixture.loginCalls==2&&Fixture.loginCollections.toList()==listOf("approved-group-A")&&first.state.operator!=null&&first.state.home!=null)
 first.navigate(Route.PAYMENTS);idle(first);Fixture.pendingFlag=true;first.refresh();idle(first)
 Fixture.managedCollection="approved-group-B";first.onBackground();first.onForeground();idle(first)
 ck("directory changes cannot silently rebind an existing authenticated native session",Fixture.repositoryCollections.size==1&&Fixture.loginCollections.last()=="approved-group-A"&&first.state.operator!=null)
 ck("scope observations never clear an unresolved financial journal",first.state.pending&&Fixture.pendingFlag)
 first.viewModelScope.cancel()
 Fixture.pendingFlag=false;Fixture.restoreSignedOut=false;Fixture.managedCollection="approved-group-A";Fixture.enrollmentCollections.clear()
 val model=BuriViewModel(Application());idle(model);model.onForeground();idle(model);model.navigate(Route.MEMBERS);idle(model);model.openSheet(Sheet.ENROLL);idle(model)
 val entered=CountDownLatch(1);val release=CountDownLatch(1);Fixture.enrollEntered=entered;Fixture.enrollBarrier=release
 model.enroll("Synthetic member","0780000001");ck("original scoped command entered",entered.await(5,TimeUnit.SECONDS));val count=Fixture.repositoryCollections.size
 Fixture.managedCollection="approved-group-B";model.onBackground();model.onForeground()
 ck("background and directory change gate records during the original command",Fixture.repositoryCollections.size==count&&model.screenGate!=ScreenGate.OPEN)
 release.countDown();idle(model)
 ck("original command keeps original collection with no automatic redispatch",Fixture.enrollmentCollections.toList()==listOf("approved-group-A")&&Fixture.repositoryCollections.size==count)
 model.logout();idle(model);model.login("0780000001","2468");idle(model)
 ck("a different server collection requires explicit new phone PIN authentication",Fixture.loginCollections.last()=="approved-group-B"&&model.state.route==Route.HOME)
 model.viewModelScope.cancel();Fixture.enrollEntered=null;Fixture.enrollBarrier=null;Fixture.managedCollection="synthetic-group"
 println("$checks original phone PIN collection checks passed")
}
