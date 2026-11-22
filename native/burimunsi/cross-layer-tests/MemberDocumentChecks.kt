package rw.ikanisa.burimunsi.crosslayertests

import androidx.lifecycle.viewModelScope
import app.cool.mobile.BuildConfig
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import rw.ikanisa.burimunsi.readMemberDocument
import rw.ikanisa.burimunsi.core.Capability
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.Transport
import rw.ikanisa.burimunsi.storage.SecureStore
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.MemberInputKind
import rw.ikanisa.burimunsi.ui.Sheet

/** Real model, process-wide repository authority and import request; all provider and transport data is synthetic. */
fun main()=runBlocking {
    val source=SessionScenario()
    source.capabilities=listOf(Capability.READ,Capability.ENROLL)
    val delegate=Transport.handler
    val previewPath="/members/import/preview"
    Transport.handler={request->
        if(request.path.endsWith(previewPath)) JSONObject().put("rows",JSONArray()).put("sourceKind","image").toString()
        else delegate(request)
    }
    val model=BuriViewModel(source.app)
    val flavor=if(BuildConfig.IS_GATEWAY)"Admin Sync" else "Staff"
    val failures=mutableListOf<String>()
    fun expect(name:String,passed:Boolean) {
        println((if(passed)"PASS " else "FAIL ")+flavor+" "+name)
        if (!passed) failures+=name
    }
    suspend fun idle() {
        withTimeout(10_000){while(model.state.busy||model.state.starting)delay(2)}
        model.viewModelScope.launch {}.join()
    }
    suspend fun select(uri:String):String {
        val launch=checkNotNull(model.beginMemberInput(MemberInputKind.DOCUMENT))
        check(model.receiveMemberInput(launch,uri,detectMime={"image/jpeg"}))
        idle()
        return checkNotNull(model.state.onboarding.documentRequestId)
    }
    fun consent(displayed:String,value:Boolean) { model.onboardingDocumentConsent(displayed,value) }
    suspend fun click(displayed:String) {
        val selected=model.currentMemberSelection(displayed,false)?:return
        model.previewMemberDocument(selected,"image/jpeg","synthetic".toByteArray(),false)
        idle()
    }
    fun requests()=Transport.calls.filter{it.path.endsWith(previewPath)}
    try {
        idle();model.login("0780000001","2468");idle()
        model.onForeground();idle();model.openSheet(Sheet.ENROLL);idle();model.onboardingImport()
        val original=select("content://synthetic/member-list-a")
        val same=select("content://synthetic/member-list-a")
        consent(original,true)
        expect("an old checkbox cannot authorize a reselected URI",!model.state.onboarding.ocrConsent)
        click(original)
        expect("an old Preview click cannot submit a reselected URI",requests().isEmpty()&&model.state.onboarding.documentSelected)
        model.onboardingOptions();model.onboardingImport()
        val second=select("content://synthetic/member-list-b")
        consent(same,true)
        expect("a checkbox from another URI cannot authorize this selection",!model.state.onboarding.ocrConsent)
        consent(second,true)
        expect("the displayed file can grant its own OCR consent",model.state.onboarding.ocrConsent)
        click(second)
        expect("the displayed file submits once with its own disclosure",requests().size==1 &&
            requests().single().body?.getBoolean("externalOcrConsent")==true && model.state.onboarding.sourceKind=="image")
        click(second)
        expect("a consumed preview cannot submit again",requests().size==1)

        model.onboardingOptions();model.onboardingImport()
        val reading=select("content://synthetic/private-image")
        consent(reading,true)
        val selected=checkNotNull(model.currentMemberSelection(reading,false))
        model.validateMemberDocumentRead(selected,requiresConsent=true)
        var calls=0
        var heldChunk:ByteArray?=null
        val stream=object:InputStream() {
            override fun read():Int=error("expected bounded read")
            override fun read(buffer:ByteArray,off:Int,len:Int):Int {
                ++calls
                if(calls>1)return -1
                heldChunk=buffer;buffer[off]=42
                consent(reading,false)
                return 1
            }
        }
        val interrupted=runCatching {
            readMemberDocument(stream,8192) { model.checkMemberDocumentRead(selected,requiresConsent=true) }
        }.exceptionOrNull()
        expect("consent withdrawn during a provider read stops before consuming another chunk",
            interrupted is CancellationException && calls==1 && heldChunk!!.all{it==0.toByte()} && requests().size==1)
        consent(reading,true)
        expect("the same selected document can resume after explicit consent",
            runCatching{model.validateMemberDocumentRead(selected,requiresConsent=true)}.isSuccess)

        val beforeFailure=Transport.handler
        val started=CountDownLatch(1);val finish=CountDownLatch(1)
        val rejectedBytes="synthetic rejected preview".toByteArray()
        try {
            Transport.handler={r->
                if(r.path.endsWith(previewPath)) {
                    started.countDown();check(finish.await(10,TimeUnit.SECONDS))
                    throw ApiFailure("connection_unavailable",0)
                }else beforeFailure(r)
            }
            model.previewMemberDocument(selected,"image/jpeg",rejectedBytes,false)
            check(started.await(10,TimeUnit.SECONDS))
            model.onBackground();finish.countDown();idle()
            expect("a failed upload returned in the background cannot change the visible import or its error",
                model.state.error==null && !model.state.offline && model.state.onboarding.documentSelected &&
                    rejectedBytes.all{it==0.toByte()})
        } finally { finish.countDown();Transport.handler=beforeFailure }
        model.onForeground();idle()

        // The picker result can reach Android Main after the same grant was renewed on IO
        // and before the suspended screen updates its copy of that profile.
        val picker=checkNotNull(model.beginMemberInput(MemberInputKind.DOCUMENT))
        val expiry=checkNotNull(model.state.operator).expiresAt+120_000
        val loading=CountDownLatch(1);val deliver=CountDownLatch(1)
        val mainHeld=CountDownLatch(1);val releaseMain=CountDownLatch(1);val persisted=CountDownLatch(1)
        val handler=Transport.handler
        var resultAccepted=false
        var mimeReads=0
        Transport.handler={r->
            if(r.method=="GET"&&r.path.endsWith("/session")) {
                loading.countDown();check(deliver.await(10,TimeUnit.SECONDS))
                JSONObject(handler(r)).put("expiresAt",expiry).toString()
            }else handler(r)
        }
        SecureStore.afterRead={name,value->
            if(name=="session" && value!=null && JSONObject(value).getLong("expiresAt")==expiry) persisted.countDown()
        }
        try {
            model.onBackground();model.onForeground()
            check(loading.await(10,TimeUnit.SECONDS))
            model.viewModelScope.launch { mainHeld.countDown();check(releaseMain.await(10,TimeUnit.SECONDS)) }
            check(mainHeld.await(10,TimeUnit.SECONDS))
            deliver.countDown();check(persisted.await(10,TimeUnit.SECONDS))
            resultAccepted=model.receiveMemberInput(picker,"content://synthetic/renewed",detectMime={mimeReads++;"text/csv"})
            expect("an unchanged grant retains a picker result while its renewed profile awaits publication",resultAccepted&&mimeReads==0)
        } finally {
            deliver.countDown();releaseMain.countDown();SecureStore.afterRead=null;Transport.handler=handler
        }
        idle()
        expect("fresh foreground authorization releases the retained result once",
            resultAccepted && mimeReads==1 && model.currentMemberSelection(picker,false)!=null)
        val latestId=model.state.onboarding.documentRequestId ?: error("expected a selected input")
        val latest=checkNotNull(model.currentMemberSelection(latestId,false))
        val peer=source.repository()
        check(peer.restore()!=null)
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        model.viewModelScope.launch { entered.countDown();check(release.await(10,TimeUnit.SECONDS)) }
        try {
            check(entered.await(10,TimeUnit.SECONDS))
            peer.logout();source.signIn(peer)
            expect("a peer replacement fences the old picker before the queued screen callback",
                model.currentMemberSelection(latestId,false)==null && model.beginMemberInput(MemberInputKind.DOCUMENT)==null &&
                    runCatching{model.validateMemberDocumentRead(latest,false)}.isFailure)
        } finally { release.countDown() }
    } finally { model.viewModelScope.coroutineContext[Job]!!.cancelAndJoin() }
    check(failures.isEmpty()) { failures.joinToString() }
}
