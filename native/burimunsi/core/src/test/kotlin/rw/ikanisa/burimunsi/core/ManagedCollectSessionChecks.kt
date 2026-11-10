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
            var requests=0;var verifications=0;var suppliedCode=""
            var requestAction:(String)->CollectEmailChallenge={CollectEmailChallenge(it,"10000000-0000-4000-8000-000000000001",now+300_000,now+60_000)}
            var verifyAction:()->CollectBffSession={CollectBffSession("fixture-cookie","fixture-csrf","principal","public",now+300_000)}
            override fun requestEmailCode(email:String):CollectEmailChallenge{requests++;return requestAction(email)}
            override fun verifyEmailCode(challenge:CollectEmailChallenge,code:String):CollectBffSession{verifications++;suppliedCode=code;return verifyAction()}
            override fun access(session:CollectBffSession,installationId:String,deviceToken:String):CollectManagedAccess{count++;check(deviceToken=="managed-device");return action()}
            override fun signOut(session:CollectBffSession){logouts++;if(logoutFailure)throw ManagedCollectFailure("connection_unavailable")}
        }
        fun broker(t:Transport)=ManagedCollectSession(t,"install","group","staff",{"managed-device"},{now})
        fun login(b:ManagedCollectSession){b.requestEmailCode("operator@example.invalid");b.verifyEmailCode("001234")}
        fun rejects(block:()->Unit){check(runCatching(block).exceptionOrNull() is ManagedCollectFailure)}
        ok("managed login obtains BFF and device-bound access without persisting credentials"){
            val t=Transport();val b=broker(t);rejects{b.currentAccessToken()};login(b)
            check(b.signedIn&&b.currentAccessToken()=="fixture.jwt.signature"&&t.count==1&&t.requests==1&&t.verifications==1&&t.suppliedCode=="001234")
            check(!value().toString().contains("fixture.jwt.signature"))
        }
        ok("background forces current managed/device revalidation before another API request"){
            val t=Transport();val b=broker(t);login(b);b.onBackground();b.currentAccessToken();check(t.count==2)
        }
        ok("changed principal cannot replace the current managed identity during refresh"){
            val t=Transport();val b=broker(t);login(b);b.onBackground();t.action={value(principal="other")}
            rejects{b.currentAccessToken()};check(!b.signedIn)
        }
        ok("managed revocation removes locally usable credentials"){
            val t=Transport();val b=broker(t);login(b);b.onBackground();t.action={throw ManagedCollectFailure("access_revoked",403)}
            rejects{b.currentAccessToken()};check(!b.signedIn)
        }
        ok("network failure does not invent success or replace the original login"){
            val t=Transport();val b=broker(t);login(b);b.onBackground();t.action={throw ManagedCollectFailure("connection_unavailable")}
            rejects{b.currentAccessToken()};check(b.signedIn);t.action={value()};check(b.currentAccessToken()=="fixture.jwt.signature")
        }
        ok("logout clears locally even when remote revocation cannot be confirmed"){
            val t=Transport();val b=broker(t);login(b);t.logoutFailure=true;rejects{b.signOut()}
            check(!b.signedIn&&t.logouts==1);rejects{b.currentAccessToken()}
        }
        ok("sign-out fences a delayed managed response"){
            val t=Transport();val b=broker(t);login(b);b.onBackground()
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
            rejects{login(b)};check(!b.signedIn&&t.logouts==1)
        }
        ok("managed account cannot be silently switched by a second login"){
            val t=Transport();val b=broker(t);login(b);rejects{login(b)};check(b.signedIn&&t.logouts==0)
        }
        ok("older scope metadata cannot replace accepted managed access"){
            val t=Transport();val b=broker(t);t.action={value(scope=2)};login(b);b.onBackground();t.action={value(scope=1)}
            rejects{b.currentAccessToken()};check(!b.signedIn)
        }

        ok("email normalization matches approved Collect identities and rejects malformed addresses"){
            check(normalizeCollectEmail(" Operator@Example.Invalid ")=="operator@example.invalid")
            for(email in listOf("a..b@example.invalid",".a@example.invalid","a@-example.invalid","a@ex_ample.invalid","a b@example.invalid","a@localhost"))rejects{normalizeCollectEmail(email)}
        }
        ok("code entry requires current challenge and six digits, preserving leading zeroes"){
            val t=Transport();val b=broker(t);rejects{b.verifyEmailCode("001234")};b.requestEmailCode("operator@example.invalid")
            for(code in listOf("12345","1234567"," 001234","abcdef"))rejects{b.verifyEmailCode(code)}
            check(t.verifications==0);b.verifyEmailCode("001234");check(t.suppliedCode=="001234")
        }
        ok("unknown delivery with an original receipt can verify, without another send"){
            val t=Transport();val b=broker(t)
            t.requestAction={CollectEmailChallenge(it,"10000000-0000-4000-8000-000000000001",now+300_000,now+60_000,true)}
            b.requestEmailCode("operator@example.invalid");check(b.emailCodeState.challenge!!.deliveryUnknown);b.onBackground()
            b.verifyEmailCode("001234");check(b.signedIn&&t.requests==1&&t.verifications==1)
        }
        ok("uncertain send reserves cooldown before IO; cancellation and address changes cannot resend"){
            val t=Transport();var time=now;val b=ManagedCollectSession(t,"install","group","staff",{"managed-device"},{time})
            t.requestAction={throw ManagedCollectFailure("managed_connection_unavailable")}
            rejects{b.requestEmailCode("operator@example.invalid")};check(t.requests==1&&b.emailCodeState.challenge==null)
            b.cancelEmailCode();rejects{b.requestEmailCode("other@example.invalid")};check(t.requests==1)
            time+=60_001;t.requestAction={CollectEmailChallenge(it,"10000000-0000-4000-8000-000000000001",time+300_000,time+60_000)}
            b.requestEmailCode("other@example.invalid");check(t.requests==2&&b.emailCodeState.challenge!!.email=="other@example.invalid")
        }
        ok("uncertain verification cannot replay the code or silently dispatch a new request"){
            val t=Transport();val b=broker(t);b.requestEmailCode("operator@example.invalid")
            t.verifyAction={throw ManagedCollectFailure("managed_connection_unavailable")}
            rejects{b.verifyEmailCode("001234")};check(b.emailCodeState.verificationUnknown)
            rejects{b.verifyEmailCode("001234")};b.onBackground();rejects{b.verifyEmailCode("001234")}
            check(!b.signedIn&&t.requests==1&&t.verifications==1)
        }
        ok("definite invalid-code response permits a manual retry on the same original challenge"){
            val t=Transport();val b=broker(t);b.requestEmailCode("operator@example.invalid")
            t.verifyAction={throw ManagedCollectFailure("invalid_credentials",400)}
            rejects{b.verifyEmailCode("001234")};check(!b.emailCodeState.verificationUnknown)
            t.verifyAction={CollectBffSession("fixture-cookie","fixture-csrf","principal","public",now+300_000)}
            b.verifyEmailCode("001235");check(b.signedIn&&t.requests==1&&t.verifications==2)
        }
        ok("expired original challenge cannot dispatch verification"){
            val t=Transport();var time=now;val b=ManagedCollectSession(t,"install","group","staff",{"managed-device"},{time})
            b.requestEmailCode("operator@example.invalid");time+=300_001;rejects{b.verifyEmailCode("001234")};check(t.verifications==0)
        }
        ok("background rejects delayed challenge publication and preserves the send cooldown"){
            val t=Transport();val b=broker(t);val entered=CountDownLatch(1);val release=CountDownLatch(1)
            val result=AtomicReference<Throwable?>();t.requestAction={email->entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS));CollectEmailChallenge(email,"10000000-0000-4000-8000-000000000001",now+300_000,now+60_000)}
            val worker=Thread{try{b.requestEmailCode("operator@example.invalid")}catch(e:Throwable){result.set(e)}}
            worker.start();check(entered.await(5,java.util.concurrent.TimeUnit.SECONDS));b.onBackground();release.countDown();worker.join(5000)
            check(!worker.isAlive&&result.get() is ManagedCollectFailure&&b.emailCodeState.challenge==null)
            rejects{b.requestEmailCode("operator@example.invalid")};check(t.requests==1)
        }

    }
}
