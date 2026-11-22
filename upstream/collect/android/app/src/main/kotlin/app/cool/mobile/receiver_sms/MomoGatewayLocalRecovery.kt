package app.cool.mobile.receiver_sms

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import app.cool.mobile.BuildConfig
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Local inbox recovery has its own jobs; the existing network heartbeat job is unchanged. */
internal object MomoGatewayLocalRecoveryJobs {
    private const val PERIODIC = 904_603
    private const val CONTINUE = 904_604

    fun isContinuation(jobId: Int): Boolean = jobId == CONTINUE

    fun ensure(context: Context, scheduler: JobScheduler) {
        if (BuildConfig.FLAVOR != "internal_receiver") return
        if (scheduler.getPendingJob(PERIODIC) != null) return
        val service = ComponentName(context, MomoGatewayLocalRecoveryService::class.java)
        val periodic = JobInfo.Builder(PERIODIC, service)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE).setPersisted(true)
            .setPeriodic(15 * 60 * 1000L).build()
        check(scheduler.schedule(periodic) == JobScheduler.RESULT_SUCCESS) { "Local recovery scheduling unavailable" }
        // Register one initial pass; later continuation is scheduled only when
        // the bounded scanner reports more work.
        scheduleContinuation(context, scheduler, 0)
    }

    fun scheduleContinuation(context: Context, scheduler: JobScheduler, delay: Long) {
        if (BuildConfig.FLAVOR != "internal_receiver" || scheduler.getPendingJob(CONTINUE) != null) return
        val job = JobInfo.Builder(CONTINUE, ComponentName(context, MomoGatewayLocalRecoveryService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE).setPersisted(true)
            .setMinimumLatency(delay).setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL).build()
        check(scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS) { "Local recovery scheduling unavailable" }
    }
}

/** At most five pages per job. A stopped or empty scan must never request continuation. */
internal fun runLocalRecoveryPages(stopped: () -> Boolean, scan: () -> Boolean): Boolean {
    repeat(5) {
        if (stopped()) return false
        if (!scan()) return false
    }
    return !stopped()
}

class MomoGatewayLocalRecoveryService : JobService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var current: Pair<JobParameters, AtomicBoolean>? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (BuildConfig.FLAVOR != "internal_receiver" || current != null) return false
        val stopped = AtomicBoolean(false)
        current = params to stopped
        executor.execute {
            var retry = false
            try {
                val more = runLocalRecoveryPages(stopped::get) { MomoGatewayRecovery(applicationContext).catchUp() }
                if (more && !stopped.get()) {
                    if (MomoGatewayLocalRecoveryJobs.isContinuation(params.jobId)) {
                        // Let JobScheduler reschedule the currently running job
                        // with its backoff; replacing its own ID may be ignored.
                        retry = true
                    } else {
                        val scheduler = getSystemService(JobScheduler::class.java)
                            ?: throw IllegalStateException("Local recovery scheduler unavailable")
                        MomoGatewayLocalRecoveryJobs.scheduleContinuation(applicationContext, scheduler, 60_000)
                    }
                }
            } catch (_: Exception) { retry = true }
            main.post {
                if (current?.second === stopped) {
                    current = null
                    jobFinished(params, retry)
                }
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        if (current?.first?.jobId != params.jobId) return false
        current?.second?.set(true)
        current = null
        return true
    }

    override fun onDestroy() {
        current?.second?.set(true)
        current = null
        executor.shutdown()
        super.onDestroy()
    }
}
