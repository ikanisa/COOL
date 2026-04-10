package app.cool.mobile.momo_sms

import android.content.Context

class MomoSmsSyncExecutor(context: Context) {
    private val prefs = MomoSmsPrefs.getInstance(context)
    private val queueRepository = MomoSmsQueueRepository.getInstance(context)
    private val apiClient = MomoSmsApiClient(context)

    fun syncPendingNow(onlyRowIds: Set<Long>? = null): MomoSmsSyncStats {
        val userId = prefs.currentUserId().orEmpty()
        if (userId.isBlank() || !prefs.hasSyncConfiguration()) {
            return MomoSmsSyncStats(lastError = "Native SMS sync is not configured.")
        }

        var uploadedMessages = 0
        var duplicateMessages = 0
        var failedMessages = 0
        var rateLimited = false
        var lastError: String? = null

        while (true) {
            val batch = queueRepository.getRetryableBatch(
                userId = userId,
                limit = 50,
                restrictToIds = onlyRowIds,
            )
            if (batch.isEmpty()) {
                break
            }

            val response = apiClient.uploadBatch(batch)
            if (response.rateLimited) {
                queueRepository.markRetry(batch.map(MomoSmsQueueRecord::id), response.errorMessage)
                rateLimited = true
                lastError = response.errorMessage
                break
            }

            if (response.errorMessage != null && response.results.isEmpty()) {
                queueRepository.markRetry(batch.map(MomoSmsQueueRecord::id), response.errorMessage)
                failedMessages += batch.size
                lastError = response.errorMessage
                break
            }

            val syncedIds = mutableListOf<Long>()
            val retryIds = mutableListOf<Long>()
            batch.forEach { record ->
                val result = response.results[record.deviceMessageKey]
                if (result == null) {
                    retryIds += record.id
                    return@forEach
                }
                if (result.success) {
                    syncedIds += record.id
                    if (result.duplicate) {
                        duplicateMessages += 1
                    } else {
                        uploadedMessages += 1
                    }
                } else {
                    retryIds += record.id
                    failedMessages += 1
                    lastError = result.errorMessage
                }
            }

            if (syncedIds.isNotEmpty()) {
                queueRepository.markSynced(syncedIds)
            }
            if (retryIds.isNotEmpty()) {
                queueRepository.markRetry(retryIds, lastError)
                break
            }

            if (!onlyRowIds.isNullOrEmpty()) {
                val remaining = queueRepository.getRetryableBatch(
                    userId = userId,
                    limit = 1,
                    restrictToIds = onlyRowIds,
                )
                if (remaining.isEmpty()) {
                    break
                }
            }
        }

        return MomoSmsSyncStats(
            uploadedMessages = uploadedMessages,
            duplicateMessages = duplicateMessages,
            failedMessages = failedMessages,
            rateLimited = rateLimited,
            lastError = lastError,
        )
    }
}
