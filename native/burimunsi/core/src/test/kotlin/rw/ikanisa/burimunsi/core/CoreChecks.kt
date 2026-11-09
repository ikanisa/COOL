package rw.ikanisa.burimunsi.core

/** Dependency-free actual JVM tests. No Android emulator claims. */
object CoreChecks {
    private var count = 0
    private fun ok(name: String, run: () -> Unit) { run(); count++; println("ok $count - $name") }
    private fun rejects(block: () -> Unit) { var caught = false; try { block() } catch (_: ContractFailure) { caught = true }; check(caught) }
    @JvmStatic fun main(args: Array<String>) {
        println("TAP version 13")
        for (v in listOf("0780000816", "+250780000816", "250780000816", "00250780000816", "780000816", "+250 780 000 816")) ok("phone $v") { check(Values.phone(v) == "+250780000816") }
        for (v in listOf("staff@example.test", "abc0780000816", "*********816", "078000081", "++250780000816", "+250760000816", "0780000816<script>")) ok("reject phone $v") { rejects { Values.phone(v) } }
        ok("all 10000 PINs preserve leading zeroes") { for(n in 0..9999) { val code = n.toString().padStart(4,'0'); check(Values.pin(code) == code) } }
        for (p in listOf("123", "12345", "12 3", " 000", "１２３４", "abcd", "0000\n")) ok("invalid PIN length/script") { rejects { Values.pin(p) } }
        ok("exact RWF") { check(Values.amount("9,007,199,254,740,991") == Values.MAX_RWF); check(Values.amount("0", false) == 0L) }
        for(a in listOf("0", "-1", "+10", "1.0", "1e4", "10,00", "00", "9007199254740992")) ok("reject amount $a") { rejects { Values.amount(a) } }
        ok("calendar and timezone") { check(Values.at("2026-10-08 15:15:20",120) == "2026-10-08T13:15:20Z") }
        for(d in listOf("2026-02-29 12:00:00", "2026-01-01 24:00:00", "2026-00-00 00:00:00")) ok("reject timestamp $d") { rejects { Values.at(d,120) } }
        val profile = ReceiptProfile("approved-test",setOf("M-Money"),120)
        val raw = "You have received 10000 RWF from EXAMPLE PERSON (*********816) at 2026-10-08 15:15:20. Balance: 10450 RWF. FT Id: 90000000001."
        ok("preserve original M-Money facts") { val r=ReceiptParser.parse("M-Money",raw,true,profile);check(r.amountRwf==10000L&&r.walletBalanceRwf==10450L&&r.ftId=="90000000001"&&r.rawBody==raw&&r.fullPayerPhone==null) }
        ok("full phone extracted only when present") { check(ReceiptParser.parse("M-Money",raw.replace("*********816","0780000816"),true,profile).fullPayerPhone=="+250780000816") }
        for(b in listOf(raw+" OTP 1234", raw.replace("10000 RWF from","10000.5 RWF from"), raw.replace("2026-10-08","2026-02-30"), raw.replace("FT Id:","ID:"), raw.replace("EXAMPLE","\u202eEXAMPLE"))) ok("malformed message rejected") { rejects { ReceiptParser.parse("M-Money",b,true,profile) } }
        ok("wrong sender rejected") { rejects { ReceiptParser.parse("Someone",raw,true,profile) } }
        ok("incomplete multipart rejected") { rejects { ReceiptParser.parse("M-Money",raw,false,profile) } }
        ok("SIM missing/mismatch never queued") { check(CaptureFilter.evaluate("M-Money",raw,true,1,null,profile) is CaptureDecision.Reject);check(CaptureFilter.evaluate("M-Money",raw,true,1,2,profile) is CaptureDecision.Reject) }
        ok("bound receipt eligible for capture, not member credit") { check(CaptureFilter.evaluate("M-Money",raw,true,1,1,profile) is CaptureDecision.Retain) }
        val pending=CaptureEnvelope("source-1","owner-1",raw)
        val ack=DurableAck(true,2,true,"owner-1","source-1","raw-1",Values.sha256(raw))
        ok("durable matching ACK") { check(Acknowledgements.matches(pending,ack)) }
        for(bad in listOf(ack.copy(ok=false),ack.copy(contractVersion=1),ack.copy(stored=false),ack.copy(ownerId="other"),ack.copy(clientEnvelopeId="other"),ack.copy(rawSmsId=""),ack.copy(bodySha256="0".repeat(64)))) ok("bad ACK retains evidence") { check(!Acknowledgements.matches(pending,bad)) }
        val staff=Operator("s","Example","+250780000816",Role.STAFF,Capability.values().map { it.key }.toSet(),10000)
        ok("staff cannot gain SMS by a capability flag") { check(!Access.allows(staff,Capability.SMS,1,true,true));check(!Access.allows(staff,Capability.STAFF,1)) }
        ok("admin non-gateway cannot read SMS") { check(!Access.routeAllowed(staff.copy(role=Role.ADMIN),Route.SMS,1,true,false)) }
        ok("admin registered gateway read") { check(Access.routeAllowed(staff.copy(role=Role.ADMIN),Route.SMS,1,true,true)) }
        ok("session expiry") { check(!Access.routeAllowed(staff,Route.HOME,10000,false,false)) }
        class Memory : OperationStore { var v:PendingOperation?=null; override fun load()=v;override fun save(value:PendingOperation){v=value};override fun clear(){v=null} }
        val memory=Memory();val journal=OperationJournal(memory)
        ok("persist command before send and refuse repeated UI dispatch") {
            val p=journal.prepare("session","allocate","body");Values.requestId(p.requestId)
            journal.beginAttempt(p,"session");journal.mark(p,OperationState.UNKNOWN)
            rejects{journal.prepare("session","allocate","body")};check(journal.unresolved()?.requestId==p.requestId)
        }
        ok("unknown outcome cannot become another mutation") { rejects { journal.prepare("session","enroll","different") }; rejects { journal.prepare("other-session","allocate","body") } }
        ok("even identical prepared commands are not silently resubmitted") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("session","enroll","body")
            rejects{j.prepare("session","enroll","body")};check(m.v?.requestId==p.requestId&&m.v?.attemptCount==0)
        }
        ok("terminal outcome requires verified cleanup before a new operation") {
            val original=memory.v!!;journal.reconcile(original,OperationState.COMMITTED)
            rejects{journal.prepare("session","enroll","new")};journal.finishCleanup(original){}
            check(journal.prepare("session","enroll","new").kind=="enroll")
        }
        ok("server reconciliation retains interrupted prepared command proof") {
            journal.reconcile(memory.v!!,OperationState.COMMITTED)
            check(journal.unresolved()?.state==OperationState.COMMITTED)
        }
        ok("conflicting terminal reconciliation is rejected") { rejects { journal.reconcile(memory.v!!,OperationState.REJECTED) } }
        ok("non-terminal reconciliation is rejected") { rejects { journal.reconcile(memory.v!!,OperationState.UNKNOWN) } }
        ok("first HTTP rejection is not durable no-effect evidence") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            j.failAttempt(j.beginAttempt(p,"a"),400,false);check(j.unresolved()?.state==OperationState.UNKNOWN)
        }
        for(status in listOf(0,200,400,401,403,404,405,408,409,413,415,422,425,429,500,503)) ok("response $status without retained proof stays pending") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            j.failAttempt(j.beginAttempt(p,"a"),status,false);check(j.unresolved()!!.state==OperationState.UNKNOWN)
        }
        for(status in listOf(400,401,403,404,409,413,415,422,429,503)) ok("timeout then retry is refused before second response $status can exist") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            val attempt=j.beginAttempt(p,"a");j.failAttempt(attempt,0,true)
            rejects{j.beginAttempt(p,"a")};rejects{j.failAttempt(attempt,status,false)}
            check(j.unresolved()!!.state==OperationState.UNKNOWN)
            rejects{j.prepare("a","allocate","replacement")}
        }
        ok("process recreation of SENT preserves uncertainty") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","staff","encrypted-payload")
            j.beginAttempt(p,"a");val restarted=OperationJournal(m)
            rejects{restarted.beginAttempt(p,"a")};check(restarted.unresolved()!!.state==OperationState.SENT)
        }
        ok("legacy SENT journal with zero attempts is never assumed unsent") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","staff","x")
            m.v=p.copy(state=OperationState.SENT)
            rejects{j.beginAttempt(p,"a")};check(j.unresolved()!!.attemptCount==0)
        }
        ok("second dispatch cannot create a competing attempt") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            val first=j.beginAttempt(p,"a");rejects{j.beginAttempt(p,"a")}
            j.completeAttempt(first);check(j.unresolved()?.state==OperationState.COMMITTED)
        }
        ok("delayed failure cannot overwrite authenticated reconciliation") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            val attempt=j.beginAttempt(p,"a");j.reconcile(p,OperationState.COMMITTED)
            rejects{j.failAttempt(attempt,503,true)};check(m.v!!.state==OperationState.COMMITTED)
        }
        ok("low-level mark cannot reject commit or resend an unknown command") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            j.beginAttempt(p,"a");j.mark(p,OperationState.UNKNOWN)
            for(s in listOf(OperationState.REJECTED,OperationState.COMMITTED,OperationState.SENT))rejects{j.mark(p,s)}
        }
        ok("failed durable journal write prevents dispatch witness") {
            val broken=object:OperationStore{
                var saved:PendingOperation?=null
                override fun load()=saved
                override fun save(value:PendingOperation){if(value.state==OperationState.SENT)throw ContractFailure("storage_full");saved=value}
                override fun clear(){saved=null}
            }
            val j=OperationJournal(broken);val p=j.prepare("a","allocate","x")
            rejects{j.beginAttempt(p,"a")};check(j.unresolved()!!.state==OperationState.PREPARED)
        }
        ok("new command follows verified cleanup; old failure cannot affect it") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            val first=j.beginAttempt(p,"a");j.reconcile(p,OperationState.COMMITTED);j.finishCleanup(p){}
            val next=j.prepare("a","allocate","new");val second=j.beginAttempt(next,"a")
            rejects{j.failAttempt(first,400,false)};j.completeAttempt(second);j.finishCleanup(next){};check(j.unresolved()==null)
        }
        ok("concurrent dispatch callers obtain exactly one witnessed command") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("a","allocate","x")
            val ready=java.util.concurrent.CountDownLatch(1);val successes=java.util.concurrent.atomic.AtomicInteger()
            val threads=(1..16).map { kotlin.concurrent.thread {ready.await();if(runCatching{j.beginAttempt(p,"a")}.isSuccess)successes.incrementAndGet()} }
            ready.countDown();threads.forEach{it.join()};check(successes.get()==1&&j.unresolved()!!.attemptCount==1)
        }
        ok("immutable owner group survive rotation and reject local substitution") {
            val m=Memory();val j=OperationJournal(m);val p=j.prepare("original-token-hash","allocate","x","owner","group")
            j.failAttempt(j.beginAttempt(p,p.sessionScope),503,true)
            check(j.unresolved()!!.ownerAccountId=="owner"&&j.unresolved()!!.groupId=="group"&&j.unresolved()!!.sessionScope==p.sessionScope)
            rejects{j.prepare("replacement-token-hash","allocate","x","other","group")}
            rejects{OperationJournal(Memory()).prepare("a","allocate","x","owner",null)}
            m.v=m.v!!.copy(ownerAccountId="different");rejects{j.reconcile(p,OperationState.COMMITTED)}
        }
        val a="a".repeat(64);val b="b".repeat(64)
        ok("session witness rejects A to B to A replacement") {
            val auth=SessionAuthority();auth.install(auth.beginReplacement{},a){}
            val old=auth.capture()
            auth.install(auth.beginReplacement{},b){};auth.install(auth.beginReplacement{},a){}
            rejects{auth.withCurrent(old){error("must not reach cache")}}
        }
        ok("old 401 does not clear replacement session") {
            val auth=SessionAuthority();auth.install(auth.beginReplacement{},a){}
            val old=auth.capture();auth.install(auth.beginReplacement{},b){}
            var cleared=false
            check(!auth.invalidateIfCurrent(old){cleared=true});check(!cleared);check(auth.capture().token==b)
        }
        ok("logout fences a delayed sign-in response") {
            val auth=SessionAuthority();val ticket=auth.beginReplacement{}
            auth.beginReplacement{}
            rejects{auth.install(ticket,a){error("must not persist")}}
            rejects{auth.capture()}
        }
        ok("failed secure persistence cannot install session") {
            val auth=SessionAuthority();val ticket=auth.beginReplacement{}
            rejects{auth.install(ticket,a){throw ContractFailure("disk_full")}}
            rejects{auth.capture()}
        }
        ok("current session invalidation clears exactly once") {
            val auth=SessionAuthority();auth.install(auth.beginReplacement{},a){}
            val w=auth.capture();var cleared=0
            check(auth.invalidateIfCurrent(w){cleared++});check(!auth.invalidateIfCurrent(w){cleared++})
            check(cleared==1);rejects{auth.capture()}
        }
        for(o in listOf("http://example.test","https://u:p@example.test","https://example.test/path","https://example.test?x=1","https://example.test/#f")) ok("reject unsafe API origin") { rejects { Values.apiOrigin(o) } }
        ok("exact TLS origin") { check(Values.apiOrigin("https://example.test").toString()=="https://example.test") }
        ManagedCollectSessionChecks.run(::ok)
        println("1..$count")
    }
}
