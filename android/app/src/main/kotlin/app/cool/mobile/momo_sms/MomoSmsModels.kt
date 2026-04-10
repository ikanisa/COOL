package app.cool.mobile.momo_sms

import java.time.Instant

enum class MomoSmsQueueStatus {
    PENDING,
    SYNCED,
    FAILED,
}

data class MomoSmsCapture(
    val sender: String,
    val body: String,
    val receivedAt: Instant,
    val deviceMessageKey: String,
    val ingestionSource: String,
)

data class MomoSmsQueueRecord(
    val id: Long,
    val userId: String,
    val sender: String,
    val body: String,
    val receivedAt: Instant,
    val deviceMessageKey: String,
    val ingestionSource: String,
    val status: MomoSmsQueueStatus,
    val retries: Int,
    val lastError: String?,
)

data class MomoSmsQueueSnapshot(
    val pendingCount: Int = 0,
    val failedCount: Int = 0,
    val syncedCount: Int = 0,
    val totalCount: Int = 0,
)

data class MomoSmsSyncStats(
    val uploadedMessages: Int = 0,
    val duplicateMessages: Int = 0,
    val failedMessages: Int = 0,
    val rateLimited: Boolean = false,
    val lastError: String? = null,
)

data class MomoSmsInboxSyncResult(
    val scannedMessages: Int,
    val uploadedMessages: Int,
    val duplicateMessages: Int,
    val queuedMessages: Int,
    val oldestMessageAt: Instant? = null,
    val newestMessageAt: Instant? = null,
    val rateLimited: Boolean = false,
)
