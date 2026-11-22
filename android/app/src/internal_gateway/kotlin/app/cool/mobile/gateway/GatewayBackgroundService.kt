package app.cool.mobile.gateway

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import app.cool.mobile.BuildConfig
import java.util.concurrent.Executors

internal object GatewayBackgroundScheduler {
    const val JOB_ID = 904501
    fun ensure(context: Context) {
        if (BuildConfig.FLAVOR != "internal_gateway") throw GatewayStateException("gateway_flavor_required")
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: throw GatewayStateException("gateway_scheduler_unavailable")
        // Never replace a running/pending job on every foreground refresh.
        if (scheduler.getPendingJob(JOB_ID) == null) schedule(context, 0)
    }
    fun schedule(context: Context, failures: Int, reconciliationOffset: Int = 0) {
        if (BuildConfig.FLAVOR != "internal_gateway") throw GatewayStateException("gateway_flavor_required")
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: throw GatewayStateException("gateway_scheduler_unavailable")
        val extras = PersistableBundle().apply {
            putInt("failures", failures.coerceIn(0, GatewaySchedulePolicy.MAX_FAILURES))
            putInt("reconciliation_offset", reconciliationOffset.coerceIn(0, GatewayEncryptedStore.MAX_REQUESTS - 1))
        }
        val job = JobInfo.Builder(JOB_ID, ComponentName(context, GatewayBackgroundService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setMinimumLatency(GatewaySchedulePolicy.delayMillis(failures))
            .setBackoffCriteria(120_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
            .setPersisted(true).setExtras(extras).build()
        if (scheduler.schedule(job) != JobScheduler.RESULT_SUCCESS) throw GatewayStateException("gateway_scheduler_unavailable")
    }
}

/** JobScheduler timing is opportunistic, never an exact cadence or a send lease. */
class GatewayBackgroundService : JobService() {
    private data class Work(val params: JobParameters, val token: GatewayCycleToken)
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var work: Work? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (BuildConfig.FLAVOR != "internal_gateway" || params.jobId != GatewayBackgroundScheduler.JOB_ID || work != null) return false
        val current = Work(params, GatewayCycleToken())
        work = current
        executor.execute {
            var result = GatewayCycleResult("gateway_operation_unavailable", true)
            var offset = params.extras.getInt("reconciliation_offset", 0)
            try { GatewayAndroidRuntime(applicationContext, current.token, offset).use {
                try { result = it.coordinator.cycle() } finally { offset = it.backend.reconciliationOffset() }
            } }
            catch (_: Exception) { /* No body, keys, contact, device or exception logs. */ }
            val failures = GatewaySchedulePolicy.failures(params.extras.getInt("failures", 0), result.backoff)
            main.post {
                if (work === current) {
                    work = null
                    // Finish first; replacing an executing job could stop it.
                    jobFinished(params, false)
                    try { GatewayBackgroundScheduler.schedule(applicationContext, failures, offset) } catch (_: Exception) { }
                }
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        val current = work
        if (current != null && current.params.jobId == params.jobId) {
            current.token.cancel()
            work = null
        }
        // Platform backoff repeats a bounded new cycle, never saved grants or
        // mutation bytes; durable reservations remain unavailable for replay.
        return true
    }

    override fun onDestroy() {
        work?.token?.cancel()
        work = null
        executor.shutdown()
        super.onDestroy()
    }
}
