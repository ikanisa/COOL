package app.cool.mobile.receiver_sms

import android.Manifest
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Base64
import app.cool.mobile.BuildConfig
import app.cool.mobile.security.ProtectedSnapshotStore
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Best-effort background drain. Authentication expiry never discards a message. */
object MemberSmsJobs {
    private const val IMMEDIATE = 904_611
    private const val RECOVERY = 904_612
    private val gate = MomoGatewayWakeupGate()
    private val signals = AtomicLong()
    private var runningSequence = 0L
    fun ensure(context: Context) = try {
        schedule(context)
    } catch (_: Exception) {
        // A scheduling failure cannot invalidate an already retained SMS/session.
        SmsQueueEventBus.notifyQueueChanged()
    }
    private fun schedule(context: Context) {
        if (!MomoGatewayPolicy.memberCaptureSupported(BuildConfig.FLAVOR) ||
            SmsQueueStore(context).activeCaptureOwner() == null) return
        signals.incrementAndGet()
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        if (scheduler.getPendingJob(RECOVERY) == null) {
            check(scheduler.schedule(JobInfo.Builder(RECOVERY, ComponentName(context, MemberSmsJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).setPeriodic(15 * 60 * 1000L).build()) == JobScheduler.RESULT_SUCCESS)
        }
        signal(context)
    }
    private fun signal(context: Context, delay: Long = 0) = gate.signal schedule@{
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return@schedule
        check(scheduler.schedule(JobInfo.Builder(IMMEDIATE, ComponentName(context, MemberSmsJobService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).setMinimumLatency(delay)
            .setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL).build()) == JobScheduler.RESULT_SUCCESS)
    }
    fun begin(): Boolean = gate.begin().also { if (it) runningSequence = signals.get() }
    fun finish(context: Context, retry: Boolean, finished: () -> Unit) = gate.finish(finished) {
        if ((retry || signals.get() != runningSequence) && SmsQueueStore(context).activeCaptureOwner() != null)
            signal(context, if (retry) 60_000 else 0)
    }
}

class MemberSmsJobService : JobService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var current: Pair<JobParameters, AtomicBoolean>? = null
    override fun onStartJob(params: JobParameters): Boolean {
        if (!MomoGatewayPolicy.memberCaptureSupported(BuildConfig.FLAVOR) || !MemberSmsJobs.begin()) return false
        val stopped = AtomicBoolean(false)
        current = params to stopped
        executor.execute {
            val retry = try { MemberSmsUploader(applicationContext).cycle(stopped) } catch (_: Exception) { true }
            main.post {
                if (current?.second === stopped) {
                    current = null
                    try { MemberSmsJobs.finish(applicationContext, retry) { jobFinished(params, false) } }
                    catch (_: Exception) { /* Reopen/new SMS/periodic work can recover the protected queue. */ }
                }
            }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean {
        if (current?.first?.jobId != params.jobId) return false
        current?.second?.set(true)
        current = null
        MemberSmsJobs.finish(applicationContext, false) {}
        return true
    }
    override fun onDestroy() {
        val pending = current
        current = null
        pending?.second?.set(true)
        if (pending != null) MemberSmsJobs.finish(applicationContext, false) {}
        executor.shutdown()
        super.onDestroy()
    }
}

internal object MemberSmsUploadPolicy {
    fun token(session: String?, owner: String, nowSeconds: Long,
              expectedIssuer: String = "collect-platform-api", expectedAudience: String = "collect",
              allowMappedAuthUser: Boolean = false,
              decode: (String) -> String = { String(Base64.decode(it, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING), Charsets.UTF_8) }): String? = try {
        val data = JSONObject(session ?: "")
        val user = data.getJSONObject("user")
        val token = data.getString("access_token")
        val parts = token.split('.')
        val claims = JSONObject(decode(parts[1]))
        val authUserId = if (allowMappedAuthUser) user.optString("auth_user_id", owner) else owner
        token.takeIf { token.length <= 32768 && parts.size == 3 && user.getString("id") == owner &&
            authUserId.matches(Regex("^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")) &&
            claims.optString("sub") == authUserId && claims.optString("role") == "authenticated" &&
            claims.optString("iss") == expectedIssuer && claims.optString("aud") == expectedAudience &&
            claims.optString("session_id").isNotEmpty() && claims.getLong("exp") > nowSeconds + 30 }
    } catch (_: Exception) { null }

    fun flutterEnvelope(row: JSONObject): Map<String, String> = mapOf(
        "id" to row.optString("id", ""),
        "owner_user_id" to row.optString("owner_user_id", ""),
        "raw_sender" to row.optString("raw_sender", ""),
        "raw_body" to row.optString("raw_body", ""),
        "received_at_device" to row.optString("received_at_device", ""),
        "completeness" to row.optString("completeness", "incomplete"),
        "needs_review" to row.optBoolean("needs_review").toString(),
    )

    fun park(row: JSONObject, status: Int) {
        require(permanentSourceError(status))
        row.put("needs_review", true).put("upload_error_status", status)
    }
    fun retry(row: JSONObject) {
        row.remove("needs_review")
        row.remove("upload_error_status")
    }

    fun hasUploadable(rows: List<JSONObject>): Boolean = rows.any { !it.optBoolean("needs_review") }
    fun permanentSourceError(status: Int): Boolean = status in setOf(400, 409, 413, 422)

    fun acknowledgement(response: JSONObject, owner: String, row: JSONObject): Map<String, String>? = try {
        val receipt = response.getJSONObject("receipt")
        val id = row.getString("id")
        val hash = ReceiptAckPolicy.sha256(row.getString("raw_body"))
        if (response.optBoolean("ok") && receipt.getInt("contract_version") == 2 && receipt.getBoolean("stored") &&
            receipt.getString("owner_user_id") == owner && receipt.getString("client_envelope_id") == id &&
            receipt.getString("body_sha256") == hash &&
            receipt.getString("raw_sms_id").matches(Regex("^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$"))) mapOf(id to hash) else null
    } catch (_: Exception) { null }
}

internal class MemberSmsUploader(private val context: Context) {
    fun cycle(stopped: AtomicBoolean): Boolean {
        val queue = SmsQueueStore(context)
        val owner = queue.activeCaptureOwner() ?: return false
        if (context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) return false
        val storage = ProtectedSnapshotStore(context, "auth")
        val serialized = storage.read(BuildConfig.COLLECT_AUTH_SESSION_OWNER) ?: return false
        val token = MemberSmsUploadPolicy.token(serialized, owner, System.currentTimeMillis() / 1000,
            expectedIssuer = BuildConfig.COLLECT_AUTH_ISSUER, expectedAudience = BuildConfig.COLLECT_AUTH_AUDIENCE,
            allowMappedAuthUser = BuildConfig.COLLECT_API_PATH_PREFIX.isNotEmpty()) ?: return false
        val pending = queue.readForOwner(owner)
        var requests = 0
        for (index in 0 until pending.length()) {
            if (stopped.get() || queue.activeCaptureOwner() != owner ||
                storage.read(BuildConfig.COLLECT_AUTH_SESSION_OWNER) != serialized) return false
            val row = pending.getJSONObject(index)
            if (row.optBoolean("needs_review")) continue
            if (requests >= 20) return true
            if (row.getString("raw_body").toByteArray(Charsets.UTF_8).size > 16384) {
                check(queue.parkRejected(owner, row.getString("id"), 413))
                SmsQueueEventBus.notifyQueueChanged()
                continue
            }
            val request = JSONObject().put("client_envelope_id", row.getString("id"))
                .put("raw_sender", row.getString("raw_sender")).put("raw_body", row.getString("raw_body"))
                .put("received_at_device", row.optString("received_at_device").takeIf { it.isNotEmpty() } ?: JSONObject.NULL)
                .put("completeness", row.optString("completeness", "incomplete"))
            val bytes = request.toString().toByteArray(Charsets.UTF_8)
            if (bytes.size > 32768) {
                check(queue.parkRejected(owner, row.getString("id"), 413))
                SmsQueueEventBus.notifyQueueChanged()
                continue
            }
            requests++
            val connection = URL("https://${BuildConfig.COLLECT_API_HOST}${BuildConfig.COLLECT_API_PATH_PREFIX}/v1/functions/ingest-client-sms")
                .openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15_000
                connection.readTimeout = 20_000
                connection.requestMethod = "POST"
                connection.setRequestProperty("Authorization", "Bearer $token")
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Accept", "application/json")
                if (BuildConfig.COLLECT_PUBLISHABLE_KEY.isNotEmpty()) connection.setRequestProperty("apikey", BuildConfig.COLLECT_PUBLISHABLE_KEY)
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.outputStream.use { it.write(bytes) }
                val status = connection.responseCode
                if (status in setOf(401, 403)) return false
                if (MemberSmsUploadPolicy.permanentSourceError(status)) {
                    check(queue.parkRejected(owner, row.getString("id"), status))
                    SmsQueueEventBus.notifyQueueChanged()
                    continue
                }
                if (status in 400..499 && status !in setOf(408, 429)) return false
                if (status !in 200..299) return true
                val body = connection.inputStream.use { stream ->
                    val bytesOut = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        check(bytesOut.size() + count <= 131072)
                        bytesOut.write(buffer, 0, count)
                    }
                    bytesOut.toString("UTF-8")
                }
                val hashes = MemberSmsUploadPolicy.acknowledgement(JSONObject(body), owner, row) ?: return true
                if (stopped.get() || queue.activeCaptureOwner() != owner ||
                    storage.read(BuildConfig.COLLECT_AUTH_SESSION_OWNER) != serialized) return false
                if (!queue.acknowledgeDurable(owner, hashes)) return true
                SmsQueueEventBus.notifyQueueChanged()
            } finally { connection.disconnect() }
        }
        val remaining = queue.readForOwner(owner)
        return MemberSmsUploadPolicy.hasUploadable((0 until remaining.length()).map { remaining.getJSONObject(it) })
    }
}
