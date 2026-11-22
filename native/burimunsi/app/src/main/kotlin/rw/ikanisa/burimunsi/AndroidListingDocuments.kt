package rw.ikanisa.burimunsi

import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import rw.ikanisa.burimunsi.core.export.CsvEncoder
import rw.ikanisa.burimunsi.core.export.ExportFormat
import rw.ikanisa.burimunsi.core.export.ExportLimits
import rw.ikanisa.burimunsi.core.export.XlsxEncoder
import rw.ikanisa.burimunsi.export.NativePdfExporter
import rw.ikanisa.burimunsi.ui.BuriViewModel
import java.io.File

/** Binds each Android document result to the export request that launched it. */
internal class AndroidListingDocuments(
    private val activity: ComponentActivity,
    private val controller: () -> BuriViewModel,
) {
    private data class Binding(val id: Long, val format: ExportFormat)

    private var active: Binding? = null
    private val csv = register("burimunsi.download.csv.v1", ExportFormat.CSV)
    private val xlsx = register("burimunsi.download.xlsx.v1", ExportFormat.XLSX)
    private val pdf = register("burimunsi.download.pdf.v1", ExportFormat.PDF)

    private fun register(key: String, format: ExportFormat) = activity.activityResultRegistry.register(
        key, activity, ActivityResultContracts.CreateDocument(format.mimeType),
    ) { uri -> receive(uri, format) }

    fun restore(state: Bundle?) {
        val requestId = state?.takeIf { it.containsKey(ID) }?.getLong(ID)
        val format = state?.getString(FORMAT)?.let { runCatching { ExportFormat.valueOf(it) }.getOrNull() }
        if (requestId != null && format != null) {
            active = Binding(requestId, format)
            controller().restoreDownloadPicker(requestId, format)
        }

        val context = activity.applicationContext
        controller().configureDownloads(File(context.cacheDir, "burimunsi-exports")) { kind, table, file, cancelled ->
            file.outputStream().use { output ->
                when (kind) {
                    ExportFormat.CSV -> CsvEncoder.write(table, output, cancelled)
                    ExportFormat.XLSX -> XlsxEncoder.write(table, output, cancelled)
                    ExportFormat.PDF -> NativePdfExporter(context).write(table, output, cancelled)
                }
            }
        }
    }

    fun save(state: Bundle) {
        active?.let {
            state.putLong(ID, it.id)
            state.putString(FORMAT, it.format.name)
        }
    }

    fun launchNext() {
        val model = controller()
        val request = model.takeDownloadRequest() ?: return
        active = Binding(request.id, request.format)
        try {
            val launcher = when (request.format) {
                ExportFormat.CSV -> csv
                ExportFormat.XLSX -> xlsx
                ExportFormat.PDF -> pdf
            }
            launcher.launch(request.fileName)
        } catch (_: Exception) {
            active = null
            model.downloadDestination(request.id, request.format, null)
        }
    }

    private fun receive(uri: Uri?, format: ExportFormat) {
        val binding = active?.takeIf { it.format == format } ?: return
        active = null
        val model = controller()
        if (uri == null) {
            model.downloadDestination(binding.id, format, null)
            return
        }

        val resolver = activity.applicationContext.contentResolver
        val deletePartial: () -> Unit = {
            runCatching { DocumentsContract.deleteDocument(resolver, uri) }
        }
        model.downloadDestination(binding.id, format, write = { file, check ->
            try {
                check()
                require(uri.scheme == "content" && file.length() in 1..ExportLimits().maxOutputBytes)
                resolver.openOutputStream(uri, "wt")?.use { output ->
                    file.inputStream().use { input ->
                        val chunk = ByteArray(8192)
                        try {
                            while (true) {
                                check()
                                val size = input.read(chunk)
                                if (size < 0) break
                                require(size > 0)
                                output.write(chunk, 0, size)
                            }
                            check()
                            output.flush()
                        } finally {
                            chunk.fill(0)
                        }
                    }
                } ?: error("Destination unavailable")
                check()
            } catch (error: Exception) {
                deletePartial()
                throw error
            }
        }, abort = deletePartial)
    }

    private companion object {
        const val ID = "burimunsi.download.id"
        const val FORMAT = "burimunsi.download.format"
    }
}
