package app.cool.mobile.momo_sms

import android.content.Context
import android.net.Uri
import java.time.Instant

class MomoSmsInboxSync(private val context: Context) {
    private val prefs = MomoSmsPrefs.getInstance(context)
    private val queueRepository = MomoSmsQueueRepository.getInstance(context)
    private val syncExecutor = MomoSmsSyncExecutor(context)
    private val contentResolver = context.contentResolver

    fun run(cutoff: Instant, trigger: String): MomoSmsInboxSyncResult {
        val userId = prefs.currentUserId().orEmpty()
        if (userId.isBlank()) {
            throw IllegalStateException("A signed-in session is required for SMS inbox sync.")
        }

        val uri = Uri.parse("content://sms/inbox")
        val cursor = contentResolver.query(
            uri,
            arrayOf("address", "body", "date"),
            "date >= ?",
            arrayOf(cutoff.toEpochMilli().toString()),
            "date DESC",
        ) ?: return MomoSmsInboxSyncResult(
            scannedMessages = 0,
            uploadedMessages = 0,
            duplicateMessages = 0,
            queuedMessages = 0,
        )

        var scannedMessages = 0
        var duplicateMessages = 0
        val insertedRowIds = mutableSetOf<Long>()
        var oldestMessageAt: Instant? = null
        var newestMessageAt: Instant? = null
        cursor.use { rows ->
            while (rows.moveToNext()) {
                val sender = rows.getString(0)?.trim().orEmpty()
                val body = rows.getString(1).orEmpty()
                val timestampMillis = rows.getLong(2).takeIf { it > 0L } ?: continue
                if (!prefs.isApprovedSender(sender)) {
                    continue
                }
                val receivedAt = Instant.ofEpochMilli(timestampMillis)
                val normalizedBody = MomoSmsNormalizer.normalizeWhitespace(body)
                if (normalizedBody.isBlank()) {
                    continue
                }
                scannedMessages += 1
                oldestMessageAt = when {
                    oldestMessageAt == null -> receivedAt
                    receivedAt.isBefore(oldestMessageAt) -> receivedAt
                    else -> oldestMessageAt
                }
                newestMessageAt = when {
                    newestMessageAt == null -> receivedAt
                    receivedAt.isAfter(newestMessageAt) -> receivedAt
                    else -> newestMessageAt
                }
                val capture = MomoSmsCapture(
                    sender = sender,
                    body = normalizedBody,
                    receivedAt = receivedAt,
                    deviceMessageKey = MomoSmsNormalizer.buildDeviceMessageKey(
                        sender = sender,
                        body = normalizedBody,
                        receivedAt = receivedAt,
                    ),
                    ingestionSource = when (trigger) {
                        "initial_permission_grant" -> "android_sms_initial_sync"
                        else -> "android_sms_manual_sync"
                    },
                )
                val rowId = queueRepository.insertIfAbsent(userId, capture)
                if (rowId == -1L) {
                    duplicateMessages += 1
                } else {
                    insertedRowIds += rowId
                }
            }
        }

        val syncStats = if (insertedRowIds.isEmpty()) {
            MomoSmsSyncStats()
        } else {
            syncExecutor.syncPendingNow(onlyRowIds = insertedRowIds)
        }
        MomoSmsSyncWorker.enqueue(context)
        return MomoSmsInboxSyncResult(
            scannedMessages = scannedMessages,
            uploadedMessages = syncStats.uploadedMessages,
            duplicateMessages = duplicateMessages + syncStats.duplicateMessages,
            queuedMessages = insertedRowIds.size,
            oldestMessageAt = oldestMessageAt,
            newestMessageAt = newestMessageAt,
            rateLimited = syncStats.rateLimited,
        )
    }
}
