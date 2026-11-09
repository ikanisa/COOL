package rw.ikanisa.burimunsi.core

import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference

object ManagedCollectSessionChecks {
    fun run(ok:(String,()->Unit)->Unit){
        val now=1794045600000L
        fun value(token:String="fixture.jwt.signature",principal:String="principal",scope:Long=1)=CollectManagedAccess(
            token,now+120_000,"auth","$principal","managed-session","operator","group","install","staff",1,1,1,scope)
        class Transport:CollectManagedTransport {
            var count=0;var logouts=0;var action:()->CollectManagedAccess={value()};var logoutFailure=false
            override fun signIn(email:String,password:String)=CollectBffSession("fixture-cookie","fixture-csrf","principal","public",now+300_000)
            override fun access(session:CollectBffSession,installationId:String,deviceToken:String):CollectManagedAccess{count++;check(deviceToken=="managed-device");return action()}
            override fun signOut(session:CollectBffSession){logouts++;if(logoutFailure)throw ManagedCollectFailure("connection_unavailable")}
        }
        fun broker(t:Transport)=ManagedCollectSession(t,"install","group","staff",{"managed-device"},{now})
        fun rejects(block:()->Unit){check(runCatching(block).exceptionOrNull() is ManagedCollectFailure)}
        ok("managed login obtains BFF and device-bound access without persisting credentials"){
            val t=Transport();val b=broker(t);rejects{b.currentAccessToken()};b.signIn("operator@example.invalid","test-only-password")
            check(b.signedIn&&b.currentAccessToken()=="fixture.jwt.signature"&&t.count==1)
            check(!value().toString().contains("fixture.jwt.signature"))
        }
        ok("background forces current managed/device revalidation before another API request"){
            val t=Transport();val b=broker(t);b.signIn("a","b");b.onBackground();b.currentAccessToken();check(t.count==2)
        }
        ok("changed principal cannot replace the current managed identity during refresh"){
            val t=Transport();val b=broker(t);b.signIn("a","b");b.onBackground();t.action={value(principal="other")}
            rejects{b.currentAccessToken()};check(!b.signedIn)
        }
        ok("managed revocation removes locally usable credentials"){
            val t=Transport();val b=broker(t);b.signIn("a","b");b.onBackground();t.action={throw ManagedCollectFailure("access_revoked",403)}
            rejects{b.currentAccessToken()};check(!b.signedIn)
        }
        ok("network failure does not invent success or replace the original login"){
            val t=Transport();val b=broker(t);b.signIn("a","b");b.onBackground();t.action={throw ManagedCollectFailure("connection_unavailable")}
            rejects{b.currentAccessToken()};check(b.signedIn);t.action={value()};check(b.currentAccessToken()=="fixture.jwt.signature")
        }
        ok("logout clears locally even when remote revocation cannot be confirmed"){
            val t=Transport();val b=broker(t);b.signIn("a","b");t.logoutFailure=true;rejects{b.signOut()}
            check(!b.signedIn&&t.logouts==1);rejects{b.currentAccessToken()}
        }
        ok("sign-out fences a delayed managed response"){
            val t=Transport();val b=broker(t);b.signIn("a","b");b.onBackground()
            val entered=CountDownLatch(1);val release=CountDownLatch(1);val result=AtomicReference<Throwable?>()
            t.action={entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS));value("late.jwt.signature")}
            val worker=Thread{try{b.currentAccessToken()}catch(e:Throwable){result.set(e)}};worker.start();check(entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
            val out=Thread{b.signOut()};out.start()
            val deadline=System.nanoTime()+2_000_000_000;while(b.signedIn&&System.nanoTime()<deadline)Thread.yield()
            check(!b.signedIn);release.countDown();worker.join(5000);out.join(5000)
            check(!worker.isAlive&&!out.isAlive&&result.get() is ManagedCollectFailure)
        }
        ok("denied device cannot leave a newly created BFF login installed"){
            val t=Transport();val b=broker(t);t.action={throw ManagedCollectFailure("burimunsi_access_denied",403)}
            rejects{b.signIn("a","b")};check(!b.signedIn&&t.logouts==1)
        }
        ok("managed account cannot be silently switched by a second login"){
            val t=Transport();val b=broker(t);b.signIn("a","b");rejects{b.signIn("c","d")};check(b.signedIn&&t.logouts==0)
        }
        ok("older scope metadata cannot replace accepted managed access"){
            val t=Transport();val b=broker(t);t.action={value(scope=2)};b.signIn("a","b");b.onBackground();t.action={value(scope=1)}
            rejects{b.currentAccessToken()};check(!b.signedIn)
        }
    }
}
