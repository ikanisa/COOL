package app.cool.mobile.receiver_sms

import android.Manifest
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import app.cool.mobile.BuildConfig
import org.json.JSONObject
import java.time.Instant
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Scheduling and completion share a lock, so a capture cannot lose its wake-up at worker exit. */
object MomoGatewayJobs {
    private const val IMMEDIATE = 904_601
    private const val RECOVERY = 904_602
    private val gate = MomoGatewayWakeupGate()
    fun ensure(context: Context) {
        if (BuildConfig.FLAVOR != "internal_receiver") return
        if (context.checkSelfPermission(Manifest.permission.RECEIVE_BOOT_COMPLETED) != PackageManager.PERMISSION_GRANTED) return
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        if (scheduler.getPendingJob(RECOVERY) == null) {
            val recovery = JobInfo.Builder(RECOVERY, ComponentName(context, MomoGatewayJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(BuildConfig.FLAVOR == "internal_receiver")
                .setPeriodic(15 * 60 * 1000L).build()
            check(scheduler.schedule(recovery) == JobScheduler.RESULT_SUCCESS) { "Gateway scheduling unavailable" }
        }
        signal(context)
    }
    fun signal(context: Context, delay: Long = 0) = gate.signal schedule@{
        if (BuildConfig.FLAVOR != "internal_receiver") return@schedule
        if (context.checkSelfPermission(Manifest.permission.RECEIVE_BOOT_COMPLETED) != PackageManager.PERMISSION_GRANTED) return@schedule
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return@schedule
        val job = JobInfo.Builder(IMMEDIATE, ComponentName(context, MomoGatewayJobService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(BuildConfig.FLAVOR == "internal_receiver")
            .setMinimumLatency(delay).setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL).build()
        check(scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS) { "Gateway scheduling unavailable" }
    }
    fun begin(): Boolean = gate.begin()
    fun finish(context: Context, retry: Boolean, finish: () -> Unit) = gate.finish(finish) {
        // Check *after* finishing, under the signal lock. A later capture schedules itself.
        val store = MomoGatewayStore(context)
        if (store.active()) {
            val state = store.read()!!
            val owner = state.getJSONObject("binding").getString("owner_user_id")
            val binding = state.getJSONObject("binding")
            val cases = state.optJSONObject("source_cases") ?: JSONObject()
            val pending = SmsQueueStore(context).readForGateway(owner)
            val uploadable = (0 until pending.length()).any { index ->
                val row = pending.getJSONObject(index)
                MomoGatewayPolicy.uploadEligible(row.optString("gateway_binding_id"), row.optInt("gateway_binding_version"),
                    binding.getString("id"), binding.getInt("version"), row.optBoolean("source_unresolved", true), cases.sourceParked(row.optString("id")))
            }
            if (retry || uploadable || state.optBoolean("catch_up_pending")) signal(context, if (retry) 60_000 else 0)
        }
    }
}

class MomoGatewayJobService : JobService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var current: Pair<JobParameters, AtomicBoolean>? = null
    override fun onStartJob(params: JobParameters): Boolean {
        if (BuildConfig.FLAVOR != "internal_receiver" || !MomoGatewayJobs.begin()) return false
        val stopped = AtomicBoolean(false)
        current = params to stopped
        executor.execute {
            var retry = false
            try { retry = MomoGatewayUploader(applicationContext).cycle(stopped) }
            catch (_: Exception) { retry = true }
            main.post {
                if (current?.second === stopped) {
                    current = null
                    try { MomoGatewayJobs.finish(applicationContext, retry) { jobFinished(params, false) } }
                    catch (_: Exception) { /* Protected evidence remains for periodic/reopen recovery. */ }
                }
            }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean {
        if (current?.first?.jobId != params.jobId) return false
        current?.second?.set(true)
        current = null
        // Finish only releases our process-local latch; Android owns this stopped job's retry.
        try { MomoGatewayJobs.finish(applicationContext, true) {} } catch (_: Exception) { }
        return true
    }
    override fun onDestroy() {
        val unfinished = current
        current = null
        unfinished?.second?.set(true)
        if (unfinished != null) try { MomoGatewayJobs.finish(applicationContext, true) {} } catch (_: Exception) { }
        executor.shutdown()
        super.onDestroy()
    }
}

class MomoGatewayUploader(private val context: Context, private val http: MomoGatewayHttp = MomoGatewayHttp()) {
    fun cycle(stopped: AtomicBoolean): Boolean {
        val state = MomoGatewayStore(context)
        if (!state.active() || stopped.get()) return false
        if (context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) {
            state.park("permission_required"); return false
        }
        val needsMore = MomoGatewayRecovery(context).catchUp()
        val snapshot = state.read() ?: return false
        val binding = snapshot.getJSONObject("binding")
        val owner = binding.getString("owner_user_id")
        val token = snapshot.getString("gateway_token")
        val queue = SmsQueueStore(context)
        val pending = queue.readForGateway(owner)
        val cases = snapshot.optJSONObject("source_cases") ?: JSONObject()
        var count = 0
        for (index in 0 until pending.length()) {
            if (stopped.get() || !state.active()) return false
            val row = pending.getJSONObject(index)
            if (!MomoGatewayPolicy.uploadEligible(row.optString("gateway_binding_id"), row.optInt("gateway_binding_version"),
                    binding.getString("id"), binding.getInt("version"), row.optBoolean("source_unresolved", true), cases.sourceParked(row.getString("id")))) continue
            if (count >= MomoGatewayPolicy.MAX_UPLOAD_BATCH) return true
            count++
            val body = JSONObject()
            for (key in listOf("raw_sender", "raw_body", "gateway_binding_id", "gateway_binding_version", "service_centre_at",
                "captured_at", "inbox_received_at", "source_mode", "subscription_id", "complete")) {
                body.put(key, row.opt(key) ?: JSONObject.NULL)
            }
            body.put("client_envelope_id", row.getString("id"))
            try {
                val result = http.request("ingest", token, body)
                val receipt = result.optJSONObject("receipt") ?: throw IllegalStateException("Missing durable receipt")
                check(result.optBoolean("ok") && receipt.optInt("contract_version") == 2 && receipt.optBoolean("stored") &&
                    receipt.optString("owner_user_id") == owner && receipt.optString("client_envelope_id") == row.getString("id") &&
                    receipt.optString("raw_sms_id").isNotEmpty() && receipt.optString("body_sha256") == ReceiptAckPolicy.sha256(row.getString("raw_body")))
                if (stopped.get() || !state.active()) return false // Retry the same identity after uncertain stop.
                check(queue.acknowledgeDurable(owner, mapOf(row.getString("id") to receipt.getString("body_sha256"))))
                state.update { it.put("last_upload_at", Instant.now().toString()).put("reason", "") }
                SmsQueueEventBus.notifyQueueChanged()
            } catch (error: MomoGatewayHttp.ResponseFailure) {
                when (MomoGatewayPolicy.uploadFailure(error.status)) {
                    MomoGatewayPolicy.UploadFailure.AUTHORIZATION -> { state.park("authorization_required"); return false }
                    MomoGatewayPolicy.UploadFailure.SOURCE_CONFLICT -> state.parkSource(row.getString("id"), error.status, "capture_conflict")
                    MomoGatewayPolicy.UploadFailure.SOURCE_REJECTED -> state.parkSource(row.getString("id"), error.status, "source_rejected")
                    MomoGatewayPolicy.UploadFailure.RETRY -> { state.park("connection_waiting"); return true }
                }
            }
        }
        if (!stopped.get()) {
            val (pendingCount, oldest) = queue.queueMetadata(owner)
            try {
                http.request("heartbeat", token, JSONObject().put("pending_count", pendingCount)
                    .put("oldest_pending_at", oldest ?: JSONObject.NULL).put("last_sms_at", snapshot.opt("last_sms_at") ?: JSONObject.NULL))
                state.update { it.put("last_contact_at", Instant.now().toString()) }
            } catch (error: MomoGatewayHttp.ResponseFailure) {
                if (error.status in setOf(401, 403)) state.park("authorization_required")
                // Heartbeat is secondary; retained sources and periodic recovery remain authoritative.
            } catch (_: Exception) { }
        }
        return needsMore
    }
}

class MomoGatewayRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (BuildConfig.FLAVOR != "internal_receiver" || intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_USER_UNLOCKED)) return
        try { MomoGatewayJobs.ensure(context.applicationContext) } catch (_: Exception) { }
    }
}
