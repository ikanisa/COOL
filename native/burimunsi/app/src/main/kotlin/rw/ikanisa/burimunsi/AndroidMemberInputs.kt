package rw.ikanisa.burimunsi

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import rw.ikanisa.burimunsi.core.SmartOnboardingPresentation
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.MemberImportFailure
import rw.ikanisa.burimunsi.ui.MemberInputKind
import rw.ikanisa.burimunsi.ui.Sheet
import java.io.File

/** Owns Android member picker results and the lifetime of selected documents and temporary photos. */
internal class AndroidMemberInputs(
    private val activity: ComponentActivity,
    private val controller: () -> BuriViewModel,
) {
    private val model: BuriViewModel get() = controller()

    private val memberPhotos by lazy{MemberPhotoFiles(activity.cacheDir)}
    private var pendingMemberCapture:String?=null
    private var pendingMemberCaptureId: String? = null
    private var pendingMemberPhotoId: String? = null
    private var pendingMemberDocumentId: String? = null
    var selectedCapture by mutableStateOf<String?>(null)
        private set
    private var selectedMemberCaptureId: String? = null
    private var memberPreviewJob:Job?=null
    private var memberPreviewEpoch=0L

    private val memberImport = activity.activityResultRegistry.register("burimunsi.member-import.document.v1", activity,
        ActivityResultContracts.OpenDocument()) { uri ->
        val launchId = pendingMemberDocumentId
        pendingMemberDocumentId = null
        finishMemberPicker(launchId, uri)
    }
    private val memberPhotoCapture = activity.activityResultRegistry.register("burimunsi.member-photo.capture.v1", activity,
        MemberPhotoCaptureContract()) { success ->
        val name = pendingMemberCapture
        val launchId = pendingMemberCaptureId
        pendingMemberCapture = null
        pendingMemberCaptureId = null
        val file = memberPhotos.restore(name)
        try {
            if (success && file != null && launchId != null) {
                val uri = memberPhotoUri(activity, file)
                if (model.receiveMemberInput(launchId, uri.toString(), detectMime = {
                        check(file.length() > 0)
                        "image/jpeg"
                    })) {
                    clearSelectedMemberCapture()
                    selectedMemberCaptureId = launchId
                    selectedCapture = name
                } else memberPhotos.remove(name)
            } else {
                memberPhotos.remove(name)
                model.receiveMemberInput(launchId, null, if (success) MemberImportFailure.UNREADABLE else null)
            }
        } catch (_: Exception) {
            memberPhotos.remove(name)
            model.receiveMemberInput(launchId, null, MemberImportFailure.UNREADABLE)
        } finally {
            file?.let(::revokeMemberCapture)
        }
    }
    private val memberPhotoPicker = activity.activityResultRegistry.register("burimunsi.member-photo.picker.v1", activity,
        ActivityResultContracts.PickVisualMedia()) { uri ->
        val launchId = pendingMemberPhotoId
        pendingMemberPhotoId = null
        finishMemberPicker(launchId, uri)
    }
    private fun finishMemberPicker(launchId: String?, uri: Uri?) {
        val resolver = activity.applicationContext.contentResolver
        model.receiveMemberInput(launchId, uri?.toString(), detectMime = uri?.let { selected ->
            { resolver.getType(selected)?.lowercase() }
        })
    }

    fun restore(savedInstanceState: Bundle?) {
        pendingMemberCapture = memberPhotos.restore(savedInstanceState?.getString("burimunsi.member-photo.pending"))?.name
        pendingMemberCaptureId = savedInstanceState?.getString("burimunsi.member-photo.capture-request")
            ?: savedInstanceState?.getString("burimunsi.member-photo.pending-owner")?.let { "retired" }
        pendingMemberPhotoId = savedInstanceState?.getString("burimunsi.member-photo.picker-request")
            ?: savedInstanceState?.getString("burimunsi.member-photo.picker-owner")?.let { "retired" }
        pendingMemberDocumentId = savedInstanceState?.getString("burimunsi.member-import.document-request")
        selectedMemberCaptureId = savedInstanceState?.getString("burimunsi.member-photo.selected-request")
            ?.takeIf(model::ownsMemberInput)
        selectedCapture = if (selectedMemberCaptureId != null)
            memberPhotos.restore(savedInstanceState?.getString("burimunsi.member-photo.selected"))?.name else null
        memberPhotos.removeExcept(setOfNotNull(pendingMemberCapture, selectedCapture))
    }

    fun save(outState: Bundle) {
        pendingMemberCapture?.let { outState.putString("burimunsi.member-photo.pending", it) }
        pendingMemberCaptureId?.let { outState.putString("burimunsi.member-photo.capture-request", it) }
        pendingMemberPhotoId?.let { outState.putString("burimunsi.member-photo.picker-request", it) }
        pendingMemberDocumentId?.let { outState.putString("burimunsi.member-import.document-request", it) }
        selectedCapture?.let { outState.putString("burimunsi.member-photo.selected", it) }
        selectedMemberCaptureId?.let { outState.putString("burimunsi.member-photo.selected-request", it) }
    }

    fun reconcileSelection() {
        if (model.state.sheet != Sheet.ENROLL || model.state.operator == null) memberPreviewJob?.cancel()
        if (selectedMemberCaptureId?.let(model::ownsMemberInput) == false) clearSelectedMemberCapture()
    }

    fun finish() {
        clearSelectedMemberCapture()
        memberPhotos.restore(pendingMemberCapture)?.let(::revokeMemberCapture)
        memberPhotos.remove(pendingMemberCapture)
    }

    private fun hasPendingMemberInput(): Boolean =
        pendingMemberCaptureId != null || pendingMemberPhotoId != null || pendingMemberDocumentId != null

    private fun clearSelectedMemberCapture() {
        memberPhotos.remove(selectedCapture)
        selectedCapture = null
        selectedMemberCaptureId = null
    }

    private fun revokeMemberCapture(file: File) {
        runCatching {
            activity.revokeUriPermission(memberPhotoUri(activity, file),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
    }

    fun takePhoto() {
        if (hasPendingMemberInput()) return
        val launchId = model.beginMemberInput(MemberInputKind.CAMERA) ?: return
        pendingMemberCaptureId = launchId
        try {
            val file = memberPhotos.create()
            pendingMemberCapture = file.name
            memberPhotoCapture.launch(memberPhotoUri(activity, file))
        } catch (_: Exception) {
            memberPhotos.restore(pendingMemberCapture)?.let(::revokeMemberCapture)
            memberPhotos.remove(pendingMemberCapture)
            pendingMemberCapture = null
            pendingMemberCaptureId = null
            model.receiveMemberInput(launchId, null, MemberImportFailure.CAMERA_UNAVAILABLE)
        }
    }

    fun pickPhoto() {
        if (hasPendingMemberInput()) return
        val launchId = model.beginMemberInput(MemberInputKind.PHOTO) ?: return
        pendingMemberPhotoId = launchId
        try {
            memberPhotoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        } catch (_: Exception) {
            pendingMemberPhotoId = null
            model.receiveMemberInput(launchId, null, MemberImportFailure.UNREADABLE)
        }
    }

    fun pickDocument() {
        if (hasPendingMemberInput()) return
        val launchId = model.beginMemberInput(MemberInputKind.DOCUMENT) ?: return
        pendingMemberDocumentId = launchId
        try {
            memberImport.launch(arrayOf("text/csv", "text/comma-separated-values", "application/csv",
                "image/jpeg", "image/png", "image/webp", "application/pdf",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
        } catch (_: Exception) {
            pendingMemberDocumentId = null
            model.receiveMemberInput(launchId, null, MemberImportFailure.UNREADABLE)
        }
    }

    /** Read only the explicitly selected document, with a strict bound and no durable copy. */
    fun previewDocument(requestId: String) = prepareMemberFile(requestId, automaticPhoto = false)

    fun previewCapturedPhoto(requestId: String) = prepareMemberFile(requestId, automaticPhoto = true)

    private fun prepareMemberFile(requestId: String, automaticPhoto: Boolean) {
        val resolver = activity.contentResolver
        val selection = model.currentMemberSelection(requestId, automaticPhoto) ?: return
        val photo = model.state.onboarding.documentMimeType?.startsWith("image/") == true
        memberPreviewJob?.cancel()
        val attempt = ++memberPreviewEpoch
        memberPreviewJob = activity.lifecycleScope.launch {
            var prepared: ByteArray? = null
            var transferred = false
            try {
                val pair = withContext(Dispatchers.IO) {
                    model.validateMemberDocumentRead(selection)
                    val uri = Uri.parse(selection.uri)
                    require(uri.scheme == "content")
                    val mime = resolver.getType(uri)?.lowercase() ?: "application/octet-stream"
                    val image = mime.startsWith("image/") || photo
                    val max = if (image) 20 * 1024 * 1024
                        else if (mime in setOf("text/csv", "text/comma-separated-values", "application/csv")) 2 * 1024 * 1024
                        else 5 * 1024 * 1024
                    val requiresConsent = image || SmartOnboardingPresentation.previewNeedsConsent(mime)
                    model.validateMemberDocumentRead(selection, requiresConsent)
                    val bytes = resolver.openInputStream(uri)?.use { input ->
                        readMemberDocument(input, max) { ensureActive(); model.checkMemberDocumentRead(selection, requiresConsent) }
                    } ?: error("file unavailable")
                    prepared = bytes
                    val result = if (image) "image/jpeg" to prepareMemberPhoto(bytes) else mime to bytes
                    prepared = result.second
                    model.validateMemberDocumentRead(selection, requiresConsent)
                    result
                }
                if (attempt != memberPreviewEpoch) return@launch
                model.previewMemberDocument(selection, pair.first, pair.second, automaticPhoto)
                transferred = true
            } catch (_: MemberDocumentTooLarge) {
                if (attempt == memberPreviewEpoch)
                    model.memberDocumentReadFailed(selection, if (photo) MemberImportFailure.TOO_LARGE else MemberImportFailure.UNREADABLE)
            } catch (_: OutOfMemoryError) {
                if (attempt == memberPreviewEpoch)
                    model.memberDocumentReadFailed(selection, if (photo) MemberImportFailure.TOO_LARGE else MemberImportFailure.UNREADABLE)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                if (attempt == memberPreviewEpoch) model.memberDocumentReadFailed(selection, MemberImportFailure.UNREADABLE)
            } finally {
                if (!transferred) prepared?.fill(0)
            }
        }
    }
}
