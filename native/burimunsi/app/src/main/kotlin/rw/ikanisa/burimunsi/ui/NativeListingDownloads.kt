package rw.ikanisa.burimunsi.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.ListingQuery
import rw.ikanisa.burimunsi.core.ListingTarget
import rw.ikanisa.burimunsi.core.SnapshotFreshness
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.core.export.ExportCancelledException
import rw.ikanisa.burimunsi.core.export.ExportFailure
import rw.ikanisa.burimunsi.core.export.ExportFormat
import rw.ikanisa.burimunsi.core.export.ExportTable
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.data.RecordReadScope
import rw.ikanisa.burimunsi.export.ListingExportData
import rw.ikanisa.burimunsi.gateway.GatewayPort
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicLong

data class DownloadRequest(val id: Long, val fileName: String, val format: ExportFormat)

internal data class ListingExportSelection(
    val target: ListingTarget,
    val query: ListingQuery,
    val memberId: String?,
    val paymentId: String?,
)

/** Owns the private file, its document picker, and the original listing authority until the save ends. */
internal class NativeListingDownloads(
    private val scope: CoroutineScope,
    private val repository: () -> NativeRepository,
    private val gateway: GatewayPort,
    private val clock: () -> Long,
    private val foreground: () -> Boolean,
    private val io: NativeOperationIo,
    private val runExport: (suspend () -> Unit) -> Unit,
    private val setOperationLabel: (String) -> Unit,
    private val onSessionInvalid: () -> Unit,
) {
    private data class PreparedDownload(
        val request: DownloadRequest,
        val file: File,
        val readScope: RecordReadScope,
        val contextCurrent: () -> Boolean,
        val createdAt: Long,
        val validateLocal: () -> Unit,
    )

    private data class PendingSave(val write: (File, () -> Unit) -> Unit, val abort: () -> Unit)

    var feedback: UiExportFeedback? by mutableStateOf(null)
        private set
    var request: DownloadRequest? by mutableStateOf(null)
        private set
    private val epoch = AtomicLong()
    private val zone = ZoneId.of("Africa/Kigali")
    private var exportDirectory: File? = null
    private var exportRenderer: ((ExportFormat, ExportTable, File, () -> Boolean) -> Unit)? = null
    private var preparedDownload: PreparedDownload? = null
    private var picker: DownloadRequest? = null
    private var pendingSave: PendingSave? = null
    val pickerInFlight get() = picker != null

    /** Only the app-private temporary directory is cleaned. */
    fun configure(directory: File, renderer: (ExportFormat, ExportTable, File, () -> Boolean) -> Unit) {
        if (exportDirectory == null) {
            require(directory.name == "burimunsi-exports")
            directory.mkdirs()
            require(directory.isDirectory)
            directory.listFiles()?.filter {
                it.isFile && it.name.startsWith("download-") && it.name.endsWith(".tmp")
            }?.forEach { it.delete() }
        }
        exportDirectory = directory
        exportRenderer = renderer
    }

    fun prepare(
        format: ExportFormat,
        selection: ListingExportSelection,
        contextCurrent: () -> Boolean,
        queryCurrent: () -> Boolean,
    ) {
        val directory = exportDirectory ?: return
        val renderer = exportRenderer ?: return
        clear()
        val id = epoch.incrementAndGet()
        runExport {
            feedback = UiExportFeedback(UiExportPhase.PREPARING, format, canCancel = true)
            var temporary: File? = null
            var handedOff = false
            fun check() {
                checkActive(id)
                checkContract(contextCurrent() && queryCurrent(), "session_changed")
            }
            try {
                val readScope = io { repository().recordReadScope() }
                val snapshot = io {
                    ListingExportData(repository(), gateway).collect(
                        selection.target, selection.query, selection.memberId, selection.paymentId,
                        readScope, Instant.ofEpochMilli(clock()), zone, ::check,
                    ) { rows, total ->
                        scope.launch {
                            if (epoch.get() == id && feedback?.phase == UiExportPhase.PREPARING) {
                                feedback = UiExportFeedback(
                                    UiExportPhase.PREPARING, format, completedRows = rows,
                                    totalRows = total, canCancel = true,
                                )
                            }
                        }
                    }
                }
                check()
                val file = io { File.createTempFile("download-", ".tmp", directory).also { temporary = it } }
                io { renderer(format, snapshot.table, file) { !isActive(id) } }
                check()
                io {
                    repository().validateRecordReadScope(readScope)
                    snapshot.validateLocal()
                }
                check()
                val date = Instant.ofEpochMilli(clock()).atZone(zone).toLocalDate()
                val name = "BuriMunsi-${selection.target.name.lowercase()}-$date.${format.extension}"
                val download = DownloadRequest(id, name, format)
                preparedDownload = PreparedDownload(download, file, readScope, contextCurrent, clock(), snapshot.validateLocal)
                val rows = snapshot.table.rowCount
                feedback = UiExportFeedback(UiExportPhase.CHOOSING_DESTINATION, format, name, rows, rows, true)
                request = download
                handedOff = true
            } catch (error: Exception) {
                fail(id, format, error)
            } finally {
                if (!handedOff) temporary?.delete()
            }
        }
    }

    /** Restore picker identity after process recreation, without restoring private export bytes. */
    fun restorePicker(id: Long, format: ExportFormat) {
        if (id <= 0 || id == Long.MAX_VALUE) return
        if (picker?.let { it.id == id && it.format == format } == true) return
        clear()
        epoch.updateAndGet { maxOf(it, id + 1) }
        picker = DownloadRequest(id, "", format)
    }

    /** Consume once so rotation cannot launch a second picker. */
    fun takeRequest(): DownloadRequest? {
        if (pickerInFlight) return null
        val download = request ?: return null
        request = null
        picker = download
        return download
    }

    fun acceptDestination(
        id: Long?,
        format: ExportFormat,
        write: ((File, () -> Unit) -> Unit)?,
        abort: () -> Unit,
    ): Boolean {
        val lease = picker
        if (lease == null || lease.id != id || lease.format != format) {
            discardDestination(abort)
            return false
        }
        picker = null
        if (write == null) {
            clear(showCancelled = true)
            return true
        }
        if (preparedDownload?.request?.id != lease.id) {
            discardDestination(abort)
            return false
        }
        pendingSave = PendingSave(write, abort)
        return true
    }

    /** The caller drains the picker result only after foreground session revalidation. */
    fun drain() {
        val save = pendingSave ?: return
        val prepared = preparedDownload ?: return
        val (id, name, format) = prepared.request
        runExport {
            if (pendingSave !== save || preparedDownload !== prepared) return@runExport
            pendingSave = null
            var committed = false
            fun check() {
                checkActive(id)
                checkContract(
                    prepared.contextCurrent() && SnapshotFreshness.reusable(prepared.createdAt, clock()),
                    "session_changed",
                )
                repository().validateRecordReadScope(prepared.readScope)
            }
            try {
                feedback = UiExportFeedback(UiExportPhase.WRITING, format, name, canCancel = true)
                setOperationLabel("Checking download access")
                io {
                    check()
                    repository().refreshSession()
                    check()
                    prepared.validateLocal()
                }
                setOperationLabel("Saving download")
                io {
                    check()
                    save.write(prepared.file, ::check)
                    check()
                }
                check() // Authority can change during the return from IO.
                committed = true
                feedback = UiExportFeedback(UiExportPhase.COMPLETE, format, name)
            } catch (error: Exception) {
                fail(id, format, error)
            } finally {
                withContext(NonCancellable + Dispatchers.IO) {
                    if (!committed) runCatching { save.abort() }
                    prepared.file.delete()
                }
                if (preparedDownload === prepared) preparedDownload = null
            }
        }
    }

    fun onBackground() {
        if (!pickerInFlight) clear(feedback?.phase in setOf(UiExportPhase.PREPARING, UiExportPhase.WRITING))
    }

    fun clear(showCancelled: Boolean = false) {
        epoch.incrementAndGet()
        request = null
        pendingSave?.let { discardDestination(it.abort) }
        pendingSave = null
        preparedDownload?.file?.delete()
        preparedDownload = null
        feedback = if (showCancelled) feedback?.copy(phase = UiExportPhase.CANCELLED, canCancel = false, error = null)
        else null
    }

    fun dismissFeedback() {
        if (feedback?.phase in setOf(UiExportPhase.COMPLETE, UiExportPhase.CANCELLED, UiExportPhase.FAILED)) feedback = null
    }

    private fun discardDestination(abort: () -> Unit) {
        scope.launch(Dispatchers.IO) { runCatching { abort() } }
    }

    private fun isActive(id: Long) = epoch.get() == id && foreground()

    private fun checkActive(id: Long) {
        if (!isActive(id)) throw ExportCancelledException()
    }

    private fun fail(id: Long, format: ExportFormat, error: Exception) {
        if (error is CancellationException) throw error
        if (error is ApiFailure && error.status == 401 ||
            error is ContractFailure && error.code in setOf("session_changed", "session_unavailable")) onSessionInvalid()
        if (epoch.get() == id) {
            val phase = if (error is ExportCancelledException) UiExportPhase.CANCELLED else UiExportPhase.FAILED
            feedback = UiExportFeedback(phase, format, error = downloadError(error))
        }
    }

    private fun downloadError(error: Exception): String = when {
        error is ExportCancelledException -> "Download cancelled."
        error is ExportFailure -> error.code.description
        error is ContractFailure && error.code == "export_limit" -> "This download is too large. Narrow the filters and try again."
        error is ContractFailure && error.code in setOf("cursor_stale", "invalid_page") -> "Records changed. Refresh and try the download again."
        error is ApiFailure && error.status == 0 -> "Download unavailable. Reconnect and try again."
        else -> "Unable to save download. Choose a destination and try again."
    }
}
