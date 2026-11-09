package rw.ikanisa.burimunsi.stateformattingtests

import rw.ikanisa.burimunsi.core.*
import java.time.LocalDate
import java.util.Locale
import java.util.TimeZone

fun main() {
    var checks=0
    fun ck(label:String,ok:Boolean){check(ok){label};checks++;println("PASS $label")}
    val ready=DisplayInput(authenticated=true,loaded=true,itemCount=1)
    for((name,input,want) in listOf(
        Triple("loading",ready.copy(loaded=false,busy=true),DisplayState.LOADING),
        Triple("empty",ready.copy(itemCount=0),DisplayState.EMPTY),
        Triple("content",ready,DisplayState.CONTENT),
        Triple("offline",ready.copy(offline=true),DisplayState.OFFLINE),
        Triple("stale",ready.copy(fresh=false),DisplayState.STALE),
        Triple("rejected",ready.copy(failure=DisplayFailure.REJECTED),DisplayState.REJECTED),
        Triple("conflict",ready.copy(failure=DisplayFailure.CONFLICT),DisplayState.CONFLICT),
        Triple("uncertain",ready.copy(unresolved=true),DisplayState.UNCERTAIN),
        Triple("unavailable",ready.copy(loaded=false),DisplayState.UNAVAILABLE),
        Triple("sign in",ready.copy(authenticated=false),DisplayState.SIGN_IN),
        Triple("locked",ready.copy(gate=ScreenGate.BACKGROUND),DisplayState.LOCKED)
    ))ck("state $name",PresentationState.reduce(input).state==want)
    ck("uncertainty wins over an optimistic empty or busy screen",PresentationState.reduce(ready.copy(unresolved=true,itemCount=0,busy=true)).state==DisplayState.UNCERTAIN)
    ck("offline read is not financial command permission",PresentationState.reduce(ready.copy(offline=true)).let{it.showRecords&&!it.mayStartCommand&&!it.mayCheckOutcome})
    ck("offline permits read-only status probes, never a new command",PresentationState.reduce(ready.copy(offline=true,unresolved=true)).let{it.mayCheckOutcome&&it.mayRetryRead&&!it.mayStartCommand})
    ck("unknown data is not zero-item success",PresentationState.reduce(ready.copy(loaded=false,itemCount=0)).state==DisplayState.UNAVAILABLE)
    ck("conflicting records are not redisplayed",!PresentationState.reduce(ready.copy(failure=DisplayFailure.CONFLICT)).showRecords)
    ck("negative count rejected",runCatching{ready.copy(itemCount=-1)}.isFailure)
    var combinations=0
    for(auth in listOf(false,true))for(loaded in listOf(false,true))for(busy in listOf(false,true))
    for(offline in listOf(false,true))for(fresh in listOf(false,true))for(pending in listOf(false,true))
    for(gate in ScreenGate.entries)for(failure in DisplayFailure.entries){
        val i=DisplayInput(auth,gate,loaded,if(loaded)1 else 0,busy,offline,fresh,pending,failure)
        val p=PresentationState.reduce(i);combinations++
        check(!p.mayStartCommand||(auth&&loaded&&fresh&&!busy&&!offline&&!pending&&failure==DisplayFailure.NONE&&gate==ScreenGate.OPEN))
        check(!p.showRecords||(auth&&gate==ScreenGate.OPEN&&loaded&&fresh&&failure!=DisplayFailure.CONFLICT))
        check(!p.mayCheckOutcome||(auth&&!busy&&gate==ScreenGate.OPEN&&p.unresolvedWarning))
        check(!(pending||failure==DisplayFailure.UNCERTAIN)||p.unresolvedWarning)
    }
    ck("safety invariants across $combinations state combinations",combinations==1600)
    for(code in listOf("operation_still_pending","operation_store_unavailable","operation_recovery_denied","invalid_recovery_receipt","invalid_recovery_proof"))
        ck("uncertain recovery $code",PresentationState.failure(code)==DisplayFailure.UNCERTAIN)
    for(code in listOf("cursor_stale","session_changed","invalid_history_page","invalid_api_response"))
        ck("conflict $code",PresentationState.failure(code)==DisplayFailure.CONFLICT)
    ck("transport uncertainty overrides error category",PresentationState.failure("operation_rejected",true)==DisplayFailure.UNCERTAIN)
    ck("unrecognized errors fail closed",PresentationState.failure("new_error")==DisplayFailure.UNAVAILABLE)
    ck("state labels are nonempty",DisplayState.entries.all{PresentationState.label(it).isNotBlank()})

    val amounts=listOf(0L to "0",1L to "1",999L to "999",1000L to "1,000",-1000L to "−1,000",
        9007199254740993L to "9,007,199,254,740,993",Long.MAX_VALUE to "9,223,372,036,854,775,807",Long.MIN_VALUE to "−9,223,372,036,854,775,808")
    for((value,expected) in amounts){
        ck("English exact $value",ExactDisplay.amount(value,"en-RW")==expected)
        ck("Kinyarwanda exact $value",ExactDisplay.amount(value,"rw-RW")==expected.replace(',','.'))
    }
    ck("missing amount stays unknown",ExactDisplay.amount(null)==null)
    ck("positive sign explicit",ExactDisplay.amount(1000,positiveSign=true)=="+1,000")
    ck("zero has no invented positive sign",ExactDisplay.amount(0,positiveSign=true)=="0")
    ck("negative sign never doubled",ExactDisplay.amount(Long.MIN_VALUE,positiveSign=true)=="−9,223,372,036,854,775,808")
    ck("unsupported language uses explicit English fallback",ExactDisplay.amount(1000,"fr-RW")=="1,000")
    val dates=mapOf(
        "2026-11-09T23:30:00Z" to "10 Nov 2026 01:30:00 UTC+02:00",
        "2024-02-29T00:00:00+02:00" to "29 Feb 2024 00:00:00 UTC+02:00",
        "2026-12-31T23:59:59.123456789Z" to "1 Jan 2027 01:59:59.123456789 UTC+02:00",
        "2026-11-09T12:00:00.000+02:00" to "9 Nov 2026 12:00:00.000 UTC+02:00",
        "2026-11-09T00:30:00+14:00" to "8 Nov 2026 12:30:00 UTC+02:00",
        "2026-11-09T23:30:00-12:00" to "10 Nov 2026 13:30:00 UTC+02:00")
    for((raw,expected) in dates)ck("exact timestamp $raw",ExactDisplay.timestamp(raw)==expected)
    ck("rw date uses explicit day month year order",ExactDisplay.timestamp("2026-11-09T00:00:00Z","rw-RW")=="09/11/2026 02:00:00 UTC+02:00")
    for(raw in listOf(null,"","2026-11-09 12:00:00","2026-11-09T12:00:00","2026-11-09T12:00Z","2026-02-29T00:00:00Z",
        "2024-02-30T00:00:00Z","2026-11-09T24:00:00Z","2026-11-09T23:59:60Z","2026-11-09T00:00:00-00:00",
        "2026-11-09T00:00:00+14:01","2026-11-09T00:00:00+18:00","2026-11-09T00:00:00.1234567890Z",
        "0000-01-01T00:00:00Z","9999-12-31T23:59:59Z"," 2026-11-09T00:00:00Z","2026-11-09T00:00:00Zjunk"))
        ck("malformed or ambiguous timestamp rejected: $raw",ExactDisplay.timestamp(raw)==null)
    ck("epoch extremes not mislabeled valid dates",ExactDisplay.epochTimestamp(Long.MIN_VALUE)==null&&ExactDisplay.epochTimestamp(Long.MAX_VALUE)==null)
    ck("missing epoch not current time",ExactDisplay.epochTimestamp(null)==null)
    ck("date year bound explicit",ExactDisplay.date(LocalDate.of(0,1,1))==null)
    val oldLocale=Locale.getDefault();val oldZone=TimeZone.getDefault()
    try{
        Locale.setDefault(Locale.forLanguageTag("ar-EG"));TimeZone.setDefault(TimeZone.getTimeZone("Pacific/Honolulu"))
        ck("device timezone and locale cannot change canonical display",ExactDisplay.amount(1000)=="1,000"&&ExactDisplay.timestamp("2026-11-09T00:00:00Z")=="9 Nov 2026 02:00:00 UTC+02:00")
    }finally{Locale.setDefault(oldLocale);TimeZone.setDefault(oldZone)}
    val now=1_800_000_000_000L
    val operator=Operator("owner","Example","+250780000001",Role.ADMIN,Capability.entries.map{it.key}.toSet(),now+10_000)
    val saved=NavigationCheckpoint("owner","group",now,Route.PAYMENTS,query="payer",filter="unallocated",index=4,offset=12)
    for(journal in JournalKnowledge.entries){
        val restored=ScreenRestoration.decide(saved,operator,"group",now,true,true,journal)
        ck("restore context with journal $journal",restored.route==Route.PAYMENTS&&restored.query=="payer"&&restored.index==4&&restored.offset==12)
        ck("journal $journal does not authorize replay or evidence removal",!restored.replayCommand&&!restored.clearJournal&&!restored.restoreDraft&&restored.requiresReadback&&restored.pending==(journal!=JournalKnowledge.CLEAR))
        for((label,checkpoint,who) in listOf(Triple("owner",saved.copy(ownerId="other"),operator),Triple("group",saved.copy(groupId="other"),operator),
            Triple("expired",saved.copy(savedAt=now-NavigationCheckpoint.TTL_MS-1),operator),Triple("future",saved.copy(savedAt=now+1),operator),
            Triple("bad route",saved.copy(route=Route.PAYMENT),operator),Triple("absent",null,operator),Triple("no session",saved,null))){
            val result=ScreenRestoration.decide(checkpoint,who,"group",now,true,true,journal)
            ck("$label checkpoint retains $journal",result.route in setOf(Route.HOME,Route.LOGIN)&&result.query.isEmpty()&&result.pending==(journal!=JournalKnowledge.CLEAR)&&!result.clearJournal&&!result.replayCommand)
        }
    }
    ck("expired session does not restore sensitive records",ScreenRestoration.decide(saved,operator.copy(expiresAt=now),"group",now,true,true,JournalKnowledge.UNRESOLVED).let{it.route==Route.LOGIN&&it.pending})
    ck("revoked read permission cannot restore Home",ScreenRestoration.decide(saved,operator.copy(capabilities=emptySet()),"group",now,true,true,JournalKnowledge.UNRESOLVED).route==Route.LOGIN)
    val sms=saved.copy(route=Route.SMS,filter="all")
    ck("Staff does not restore privileged SMS",ScreenRestoration.decide(sms,operator.copy(role=Role.STAFF),"group",now,true,true,JournalKnowledge.CLEAR).route==Route.HOME)
    ck("unbound receiver does not restore SMS",ScreenRestoration.decide(sms,operator,"group",now,true,false,JournalKnowledge.CLEAR).route==Route.HOME)
    println("RESULT: $checks state/format/restoration checks passed; $combinations state combinations exercised; no Android execution.")
}
