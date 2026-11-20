package rw.ikanisa.burimunsi.smartonboardingtests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.ui.*

/** Real ViewModel with synthetic repository and lifecycle boundaries. */
fun main()=runBlocking {
 var checks=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
 val model=BuriViewModel(Application())
 suspend fun idle(){withTimeout(10000){while(model.state.busy)delay(2)};delay(20);withTimeout(10000){while(model.state.busy)delay(2)}}
 idle();model.onForeground();idle();model.openSheet(Sheet.ENROLL);idle()
 model.onboardingPhoto();model.onBackground();model.onboardingPhotoSelected("content://example/capture.jpg")
 ck("captured photo waits for foreground revalidation",!model.state.onboarding.documentSelected&&!model.takeOnboardingPhotoPreview("content://example/capture.jpg"))
 model.onForeground();idle()
 ck("the disclosed camera action binds consent to the captured image",model.state.onboarding.photoCaptureFlow&&model.state.onboarding.photoPreviewPending&&model.state.onboarding.ocrConsent&&model.state.onboarding.documentUri=="content://example/capture.jpg")
 ck("a different URI cannot consume the captured-photo request",!model.takeOnboardingPhotoPreview("content://example/other.jpg"))
 ck("captured-photo preview is consumed exactly once",model.takeOnboardingPhotoPreview("content://example/capture.jpg")&&!model.takeOnboardingPhotoPreview("content://example/capture.jpg"))
 val photoBytes="synthetic photo".toByteArray();model.onboardingPreview("image/jpeg",photoBytes);idle()
 ck("captured photo reaches extraction once with scoped consent and bytes wiped",Fixture.onboardingPreviews==1&&Fixture.lastOnboardingConsent==true&&Fixture.lastOnboardingMimeType=="image/jpeg"&&photoBytes.all{it==0.toByte()})
 model.onboardingOptions()
 model.onboardingPhoto();model.onBackground();model.onboardingPhotoCancelled();model.onForeground();idle()
 ck("cancelled camera returns to options without upload",model.state.onboarding.step==SmartOnboardingStep.OPTIONS&&!model.state.onboarding.photoPreviewPending&&Fixture.onboardingPreviews==1)
 model.onboardingImport();model.onboardingFileSelected("content://example/manual-source.csv","text/csv");model.onboardingManual()
 ck("manual entry from import discards the prior document and consent",model.state.onboarding.step==SmartOnboardingStep.MEMBER&&model.state.onboarding.documentUri==null&&!model.state.onboarding.ocrConsent&&model.state.onboarding.rows.isEmpty())
 model.onboardingImport();model.onboardingFileSelected("content://example/suggestions-source.csv","text/csv");model.onboardingSuggestions();idle()
 ck("suggestions from import discard the prior document and consent",model.state.onboarding.step==SmartOnboardingStep.SUGGESTIONS&&model.state.onboarding.documentUri==null&&!model.state.onboarding.ocrConsent&&model.state.onboarding.rows.isEmpty())
 model.onboardingImport();model.onboardingFileSelected("content://example/photo-source.csv","text/csv");model.onboardingPhoto()
 ck("camera from import starts a fresh capture without the prior document",model.state.onboarding.photoCaptureFlow&&model.state.onboarding.documentUri==null&&!model.state.onboarding.ocrConsent)
 model.onboardingPhotoCancelled()
 model.onboardingImport()
 ck("import is part of the existing Add Member panel",model.state.sheet==Sheet.ENROLL&&model.state.onboarding.step==SmartOnboardingStep.IMPORT)
 model.onBackground();model.onboardingFileSelected("content://example/member.csv","text/csv")
 ck("document picker result waits for fresh foreground authorization",!model.state.onboarding.documentSelected)
 model.onForeground();idle()
 ck("authorized picker result survives background and resume without photo consent",model.state.onboarding.documentSelected&&model.state.onboarding.documentUri=="content://example/member.csv"&&!model.state.onboarding.ocrConsent&&!model.state.onboarding.photoPreviewPending)
 val bytes="synthetic csv".toByteArray();model.onboardingPreview("text/csv",bytes);idle()
 ck("preview reads selected rows once and wipes input",Fixture.onboardingPreviews==2&&Fixture.lastOnboardingConsent==false&&bytes.all{it==0.toByte()}&&model.state.onboarding.rows.size==1)
 ck("successful preview drops the private source URI while retaining extracted rows",model.state.onboarding.documentUri==null&&!model.state.onboarding.documentSelected)
 model.onboardingEditRow(1);model.onboardingConsent("ownership",true);model.onboardingConsent("terms",true);model.onboardingConsent("consent",true)
 model.onboardingSaveRow("Example Member","0780000001")
 ck("correcting an invalid row keeps the preview and selects the verified row",model.state.onboarding.rows.single().verified&&Fixture.onboardingPreviews==2)
 model.onboardingManual();model.onboardingSuggestions();model.onboardingPhoto()
 ck("source switches cannot silently discard a reviewed batch",model.state.onboarding.step==SmartOnboardingStep.IMPORT&&model.state.onboarding.rows.single().verified&&model.state.onboarding.sourceKind!=null)
 model.onboardingSubmitBatch();idle()
 ck("verified batch is submitted once and displays its retained result",Fixture.onboardingImports==1&&model.state.onboarding.step==SmartOnboardingStep.RESULTS&&model.state.onboarding.created==1)
 model.closeSheet();model.openSheet(Sheet.ENROLL);idle();model.onboardingPhoto();model.onBackground()
 model.onboardingPhotoSelected("content://example/old.jpg");model.logout();idle();model.onForeground();idle()
 ck("sign out discards a camera result from the former session without upload",model.state.operator==null&&!model.state.onboarding.documentSelected&&Fixture.onboardingPreviews==2)
 model.viewModelScope.cancel()
 var timeOffset=0L
 val expired=BuriViewModel(Application()){System.currentTimeMillis()+timeOffset}
 suspend fun idleExpired(){withTimeout(10000){while(expired.state.busy)delay(2)};delay(20);withTimeout(10000){while(expired.state.busy)delay(2)}}
 idleExpired();expired.onForeground();idleExpired();expired.openSheet(Sheet.ENROLL);idleExpired();expired.onboardingPhoto()
 ck("camera starts from a freshly authorized enrollment sheet",expired.state.sheet==Sheet.ENROLL&&expired.state.onboarding.photoCaptureFlow)
 expired.onBackground()
 val advanced=expired.state.operator!!.expiresAt+1
 timeOffset=advanced-System.currentTimeMillis()
 Fixture.renewedExpiry=advanced+3_600_000
 Fixture.recordSavedAt=advanced
 expired.onboardingPhotoSelected("content://example/expired-capture.jpg")
 ck("expired cached authority queues the owner-bound camera result without uploading",!expired.state.onboarding.documentSelected&&Fixture.onboardingPreviews==2)
 expired.onForeground();idleExpired()
 ck("renewed foreground authority releases the queued camera capture",expired.state.onboarding.documentUri=="content://example/expired-capture.jpg"&&expired.state.onboarding.photoPreviewPending&&expired.state.onboarding.ocrConsent)
 ck("renewed capture remains one-shot",expired.takeOnboardingPhotoPreview("content://example/expired-capture.jpg")&&!expired.takeOnboardingPhotoPreview("content://example/expired-capture.jpg"))
 expired.onboardingPhoto();expired.onBackground();expired.onboardingPhotoSelected("content://example/revoked-capture.jpg")
 Fixture.refreshedCaps=setOf(Capability.READ.key)
 expired.onForeground();idleExpired()
 ck("revoked enrollment access never releases or uploads the queued camera capture",!expired.state.onboarding.documentSelected&&!expired.state.onboarding.photoPreviewPending&&Fixture.onboardingPreviews==2)
 Fixture.renewedExpiry=null;Fixture.recordSavedAt=null;Fixture.refreshedCaps=null;expired.viewModelScope.cancel()
 println("RESULT: $checks smart onboarding controller checks passed with synthetic boundaries; no live data or Android lifecycle claim.")
}
