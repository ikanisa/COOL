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
        val observationProfile=ObservationProfile(ReceiptProfile("provider-v1",setOf("M-Money"),120,
            setOf("You have received"),setOf("RWF"),setOf("FT Id:")),1_800_000_000_000,1_800_086_400_000)
        val observation=SmsObservation("7d900a92-1d36-4b3e-bf66-325ebd2d402e","M-Money",raw,"live",true,
            "2026-10-08T13:15:20Z",null,null,null)
        val observationNow=1_800_000_000_001L
        ok("profile fingerprint changes with candidate markers, not renewal timestamps") {
            val renewed=observationProfile.copy(issuedAt=observationProfile.issuedAt+1,expiresAt=observationProfile.expiresAt+1)
            check(renewed.fingerprint()==observationProfile.fingerprint())
            check(observationProfile.copy(receipt=observationProfile.receipt.copy(senders=setOf("Different"))).fingerprint()!=observationProfile.fingerprint())
            check(ObservationCursor.start(1200,1500)==1200L&&ObservationCursor.start(null,1500)==1000L&&ObservationCursor.start(null,100)==0L)
            check(ObservationCursor.start(100,2000)==1500L&&ObservationCursor.start(1800,2000)==1800L&&ObservationCursor.start(2200,2000)==2200L)
        }
        ok("approved receipt is an unresolved observation with only unverified local facts") {
            check(observation.valid(observationProfile,observationNow))
            val facts=observation.unverifiedFacts(observationProfile,observationNow)
            check(facts?.amountRwf==10000L&&facts.reference=="90000000001"&&facts.payerPhone=="*********816")
            check(!observation.toString().contains(raw)&&!facts.toString().contains("EXAMPLE"))
        }
        ok("sender-scoped capture retains messages without presenting security text as payment facts") {
            val securityMessage=observation.copy(rawBody=raw+" OTP 1234")
            check(securityMessage.valid(observationProfile,observationNow))
            check(securityMessage.unverifiedFacts(observationProfile,observationNow)==null)
            check(!observation.copy(rawSender="unapproved").valid(observationProfile,observationNow))
            check(!observation.valid(observationProfile,observationProfile.expiresAt))
            check(!observation.valid(observationProfile.copy(issuedAt=observationNow+300_001),observationNow))
        }
        ok("unsupported and incomplete candidate text is never presented as parsed payment facts") {
            val alternate=observation.copy(rawBody=raw.replace("You have received", "Payment received"))
            val alternateProfile=observationProfile.copy(receipt=observationProfile.receipt.copy(incomingPrefixes=setOf("Payment received")))
            check(alternate.valid(alternateProfile,observationNow)&&alternate.unverifiedFacts(alternateProfile,observationNow)==null)
            check(!observation.copy(complete=false).valid(observationProfile,observationNow))
            check(!observation.copy(sourceMode="catch_up",complete=false,inboxReceivedAt=null).valid(observationProfile,observationNow))
            check(!observation.copy(sourceMode="catch_up",complete=true).valid(observationProfile,observationNow))
            val inbox=observation.copy(sourceMode="catch_up",complete=false,inboxReceivedAt="2026-10-08T13:15:20Z")
            check(inbox.valid(observationProfile,observationNow)&&inbox.unverifiedFacts(observationProfile,observationNow)?.sourceComplete==false)
            rejects{ReceiptParser.parse("M-Money",raw,false,observationProfile.receipt)}
        }
        ok("only a matching durable unresolved acknowledgement removes an observation") {
            val ack=ObservationAck(observation.requestId,"source-1",Values.sha256(raw),"source_unresolved",0)
            check(ObservationAcknowledgement.matches(observation,ack))
            for(bad in listOf(ack.copy(requestId="another"),ack.copy(sourceId=""),ack.copy(bodySha256="0".repeat(64)),
                ack.copy(status="posted"),ack.copy(financialEffects=1)))check(!ObservationAcknowledgement.matches(observation,bad))
        }
        ok("reinstall source identity preserves distinct inbox rows and fails closed without device identity") {
            val id="1234567890abcdef";val group="group-1";val time="2026-11-07T10:00:00Z"
            val first=ObservationSourceIdentity.reinstallStable(id,group,101,time)
            check(first==ObservationSourceIdentity.reinstallStable(id.uppercase(),group,101,time))
            check(first!=ObservationSourceIdentity.reinstallStable(id,group,102,time))
            check(first!=ObservationSourceIdentity.reinstallStable(id,group,101,"2026-11-07T10:00:01Z"))
            check(first!=ObservationSourceIdentity.reinstallStable("1234567890abcdee",group,101,time))
            check(first!=ObservationSourceIdentity.reinstallStable(id,"other-group",101,time))
            for(bad in listOf("", "0000000000000000", "9774d56d682e549c", "unknown"))
                rejects{ObservationSourceIdentity.reinstallStable(bad,group,101,time)}
            rejects{ObservationSourceIdentity.reinstallStable(id,group,0,time)}
            rejects{ObservationSourceIdentity.reinstallStable(id,group,101,"invalid")}
        }
        ok("SMS consent must be confirmed and revocation immediately blocks capture") {
            val pending=ObservationConsent.reconcile(null,ObservationConsentRevision(false,0),true)!!
            check(pending.revision==ObservationConsentRevision(true,1)&&!pending.canCapture(true))
            val allowed=ObservationConsent.acknowledge(pending,pending.revision)!!
            check(allowed.canCapture(true)&&!allowed.canCapture(false))
            var wrote=false
            check(ObservationConsent.whilePermitted(allowed,{false}){wrote=true}==null&&!wrote)
            val revoked=ObservationConsent.reconcile(allowed,null,false)!!
            check(revoked.revision==ObservationConsentRevision(false,2)&&!revoked.canCapture(false))
            check(ObservationConsent.acknowledge(revoked,allowed.revision)==null)
        }
        ok("consent recovery uses current server generation and refuses conflicting echoes") {
            check(ObservationConsent.reconcile(null,null,true)==null)
            val recovered=ObservationConsent.reconcile(null,ObservationConsentRevision(false,45),true)!!
            check(recovered.revision==ObservationConsentRevision(true,46)&&!recovered.confirmed)
            check(ObservationConsent.reconcile(recovered,ObservationConsentRevision(false,46),true)?.revision==ObservationConsentRevision(true,47))
            check(ObservationConsent.reconcile(null,ObservationConsentRevision(false,9_007_199_254_740_991L),true)==null)
        }
        ok("observation queue retains source until an exact scoped durable acknowledgement") {
            var value=ObservationJournalState(emptyList(),emptyList())
            val storage=object:ObservationJournalStore {override fun read()=value;override fun write(next:ObservationJournalState){value=next}}
            val journal=ObservationJournal(storage);val owner=ObservationOwner("group-1","admin-1")
            val rowId=101L;val installation="50000000-0000-4000-8000-000000000001"
            val key=ObservationSourceIdentity.inbox(installation,owner,rowId)
            val inbox=observation.copy(sourceMode="catch_up",complete=false,inboxReceivedAt="2026-10-08T13:15:20Z")
            check(journal.append(owner,key,rowId,inbox,observationProfile,observationNow)==ObservationAppend.STORED)
            check(journal.append(owner,key,rowId,inbox,observationProfile,observationNow)==ObservationAppend.DUPLICATE)
            val ack=ObservationAck(inbox.requestId,"source-1",Values.sha256(raw),"source_unresolved",0)
            check(!journal.acknowledge(ObservationOwner("group-2","admin-1"),inbox.requestId,ack))
            check(!journal.acknowledge(owner,inbox.requestId,ack.copy(bodySha256="0".repeat(64))))
            check(journal.pending(owner).single().observation==inbox)
            val snapshot=journal.pendingSnapshot(owner)
            check(snapshot.entries.size==1&&journal.ifRevision(snapshot.revision){true}==true)
            check(journal.acknowledge(owner,inbox.requestId,ack)&&journal.pending(owner).isEmpty())
            check(journal.ifRevision(snapshot.revision){true}==null&&journal.pendingSnapshot(owner).entries.isEmpty())
            check(journal.append(owner,key,rowId,inbox,observationProfile,observationNow)==ObservationAppend.DUPLICATE)
        }
        ok("uncertain queue writes invalidate earlier display snapshots") {
            var state=ObservationJournalState(emptyList(),emptyList());var fail=false
            val store=object:ObservationJournalStore{override fun read()=state;override fun write(value:ObservationJournalState){state=value;if(fail)error("synthetic failure")}}
            val journal=ObservationJournal(store);val owner=ObservationOwner("group-1","admin-1")
            val snapshot=journal.pendingSnapshot(owner);val inbox=observation.copy(sourceMode="catch_up",complete=false,inboxReceivedAt="2026-10-08T13:15:20Z")
            fail=true;check(runCatching{journal.append(owner,ObservationSourceIdentity.inbox("50000000-0000-4000-8000-000000000001",owner,103),103,inbox,observationProfile,observationNow)}.isFailure)
            check(journal.ifRevision(snapshot.revision){true}==null)
        }
        ok("replay identity protects each owner and distinguishes identical inbox rows") {
            var state=ObservationJournalState(emptyList(),emptyList())
            val store=object:ObservationJournalStore {override fun read()=state;override fun write(value:ObservationJournalState){state=value}}
            val journal=ObservationJournal(store);val a=ObservationOwner("group-1","admin-1");val b=ObservationOwner("group-1","admin-2")
            val installation="50000000-0000-4000-8000-000000000001"
            fun item()=observation.copy(requestId=java.util.UUID.randomUUID().toString(),sourceMode="catch_up",complete=false,inboxReceivedAt="2026-10-08T13:15:20Z")
            fun retain(owner:ObservationOwner,row:Long):SmsObservation {
                val candidate=item();val key=ObservationSourceIdentity.inbox(installation,owner,row)
                check(journal.append(owner,key,row,candidate,observationProfile,observationNow)==ObservationAppend.STORED)
                val ack=ObservationAck(candidate.requestId,"source-1",Values.sha256(raw),"source_unresolved",0)
                check(journal.acknowledge(owner,candidate.requestId,ack));return candidate
            }
            val first=retain(a,101);val second=retain(a,102)
            check(first.rawBody==second.rawBody&&first.requestId!=second.requestId)
            for(row in 1L..1030L)retain(b,row)
            val aKey=ObservationSourceIdentity.inbox(installation,a,101)
            check(journal.append(a,aKey,101,item(),observationProfile,observationNow)==ObservationAppend.DUPLICATE)
            check(journal.latestSeenRow(a)==102L&&journal.latestSeenRow(b)==1030L)
            rejects{journal.append(a,ObservationSourceIdentity.inbox("50000000-0000-4000-8000-000000000002",a,101),101,item(),observationProfile,observationNow)}
            rejects{journal.append(a,aKey,101,item().copy(rawBody=raw.replace("10000","10001")),observationProfile,observationNow)}
        }
        val pending=CaptureEnvelope("source-1","owner-1",raw)
        val ack=DurableAck(true,2,true,"owner-1","source-1","raw-1",Values.sha256(raw))
        ok("durable matching ACK") { check(Acknowledgements.matches(pending,ack)) }
        for(bad in listOf(ack.copy(ok=false),ack.copy(contractVersion=1),ack.copy(stored=false),ack.copy(ownerId="other"),ack.copy(clientEnvelopeId="other"),ack.copy(rawSmsId=""),ack.copy(bodySha256="0".repeat(64)))) ok("bad ACK retains evidence") { check(!Acknowledgements.matches(pending,bad)) }
        val staff=Operator("s","Example","+250780000816",Role.STAFF,Capability.values().map { it.key }.toSet(),10000)
        ok("staff cannot gain SMS by a capability flag") { check(!Access.allows(staff,Capability.SMS,1,true,true));check(!Access.allows(staff,Capability.STAFF,1)) }
        ok("admin non-receiver variant cannot read SMS") { check(!Access.routeAllowed(staff.copy(role=Role.ADMIN),Route.SMS,1,false,false)) }
        ok("authorized admin can view unpaired receiver observations") { check(Access.routeAllowed(staff.copy(role=Role.ADMIN),Route.SMS,1,true,false)) }
        ok("admin receiver read still requires SMS capability") { check(!Access.routeAllowed(staff.copy(role=Role.ADMIN,capabilities=setOf("records.read")),Route.SMS,1,true,false)) }
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
        ok("rotation requires the original witness and durable persistence") {
            val auth=SessionAuthority();auth.install(auth.beginReplacement{},a){}
            val old=auth.capture()
            rejects{auth.replaceCurrent(old,b){throw ContractFailure("disk_full")}}
            check(auth.capture().token==a)
            auth.replaceCurrent(old,b){}
            check(auth.capture().token==b);rejects{auth.replaceCurrent(old,a){error("late write")}}
        }
        ok("empty-slot attach fences an earlier staged login; same-bearer attach is stable") {
            val auth=SessionAuthority();val staged=auth.revision()
            val first=auth.attach(a){};rejects{auth.installRevision(staged,b){error("late write")}}
            val second=auth.attach(a){};check(first==second&&auth.capture()==first)
        }
        ok("logout invalidates a replacement even if protected cleanup fails") {
            val auth=SessionAuthority();auth.install(auth.beginReplacement{},a){}
            val old=auth.capture()
            rejects{auth.retire{throw ContractFailure("disk_full")}}
            rejects{auth.capture()};rejects{auth.replaceCurrent(old,b){error("late write")}}
        }
        ok("observation quarantine survives reattachment until validated confirmation") {
            val auth=SessionAuthority();check(auth.observationAdmitted())
            val first=auth.attach(a){};check(auth.observationAdmitted())
            rejects{auth.retire{throw ContractFailure("disk_full")}}
            check(!auth.observationAdmitted())
            val restored=auth.attach(a){};check(!auth.observationAdmitted())
            rejects{auth.confirmObservationCurrent(first)}
            check(!auth.observationAdmitted())
            auth.confirmObservationCurrent(restored);check(auth.observationAdmitted())
        }
        ok("observation persistence failure notifies and cannot quarantine a replacement") {
            val auth=SessionAuthority();auth.installRevision(auth.revision(),a){}
            val old=auth.capture();val decisions=mutableListOf<Boolean>()
            val detach=auth.observe{decisions.add(auth.observationAdmitted())}
            check(auth.blockObservationIfCurrent(old)&&!auth.observationAdmitted())
            auth.confirmObservationCurrent(old);check(auth.observationAdmitted())
            auth.replaceCurrent(old,b){};check(!auth.blockObservationIfCurrent(old)&&auth.observationAdmitted())
            detach();check(decisions.contains(false)&&decisions.contains(true))
        }
        for(o in listOf("http://example.test","https://u:p@example.test","https://example.test/path","https://example.test?x=1","https://example.test/#f")) ok("reject unsafe API origin") { rejects { Values.apiOrigin(o) } }
        ok("exact TLS origin") { check(Values.apiOrigin("https://example.test").toString()=="https://example.test") }
        ManagedCollectSessionChecks.run(::ok)
        InstallationEnrollmentChecks.run(::ok)
        ok("typed full-query listing defaults, bounds and selector applicability") { ListingQueryChecks.run() }
        ok("receiver takes canonical pair collection without a build group or active operator login") {
            check(ReceiverCollectionScope.matches("server-paired-group",null))
            check(ReceiverCollectionScope.matches("server-paired-group","server-paired-group"))
            check(!ReceiverCollectionScope.matches("server-paired-group","another-group"))
            for(value in listOf(null,"","../group","group/other",1))check(!ReceiverCollectionScope.matches(value,null))
        }
        println("1..$count")
    }
}
