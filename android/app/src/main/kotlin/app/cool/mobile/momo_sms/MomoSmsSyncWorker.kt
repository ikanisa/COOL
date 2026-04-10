package app.cool.mobile.momo_sms

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * WorkManager sync job for uploading queued MoMo SMS to the server.
 *
 * - Runs only when NETWORK_CONNECTED
 * - Exponential backoff: 1min → 2min → 4min → 8min → max 30min
 * - Unique work name prevents concurrent sync jobs
 * - Uses [MomoSmsSyncExecutor] for actual upload logic
 * - Reads auth from [MomoSmsPrefs] — survives process death + reboot
 */
class MomoSmsSyncWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "MomoSmsSyncWorker"
        private const val UNIQUE_WORK_NAME = "cool_momo_sms_sync"

        fun enqueue(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = OneTimeWorkRequestBuilder<MomoSmsSyncWorker>()
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    1,
                    TimeUnit.MINUTES,
                )
                .addTag(TAG)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(
                    UNIQUE_WORK_NAME,
                    ExistingWorkPolicy.KEEP,
                    request,
                )
        }
    }

    override suspend fun doWork(): Result {
        val prefs = MomoSmsPrefs.getInstance(applicationContext)
        if (!prefs.hasSyncConfiguration()) {
            Log.w(TAG, "No sync configuration — skipping")
            return Result.success()
        }

        return try {
            val executor = MomoSmsSyncExecutor(applicationContext)
            val stats = executor.syncPendingNow()

            Log.i(
                TAG,
                "Sync complete: uploaded=${stats.uploadedMessages} " +
                    "duplicates=${stats.duplicateMessages} " +
                    "failed=${stats.failedMessages} " +
                    "rateLimited=${stats.rateLimited}",
            )

            if (stats.rateLimited) {
                Result.retry()
            } else {
                Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
            if (runAttemptCount < 5) {
                Result.retry()
            } else {
                Log.e(TAG, "Max retries exceeded — marking as failure")
                Result.failure()
            }
        }
    }
}
