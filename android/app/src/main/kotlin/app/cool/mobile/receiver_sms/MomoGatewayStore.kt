package app.cool.mobile.receiver_sms

import android.content.Context
import app.cool.mobile.BuildConfig
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.UUID
import java.time.Instant
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** Separate no-backup, Keystore-protected ingestion credential; never a member refresh token. */
class MomoGatewayStore(private val context: Context) {
    private val backendSuffix = if (BuildConfig.COLLECT_API_PATH_PREFIX.isEmpty()) "" else "_${BuildConfig.COLLECT_AUTH_SESSION_OWNER}"
    private val file get() = AtomicFile(File(context.noBackupFilesDir, "collect_momo_gateway_v1${backendSuffix}.enc"))
    private val identityPrefs get() = context.getSharedPreferences("collect_momo_gateway_identity$backendSuffix", Context.MODE_PRIVATE)

    fun installationId(): String = synchronized(lock) {
        identityPrefs.getString("installation_id", null)?.let { return@synchronized it }
        UUID.randomUUID().toString().also {
            check(identityPrefs.commitReceiptState { putString("installation_id", it) })
        }
    }

    fun read(): JSONObject? = synchronized(lock) {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return@synchronized null
        val encoded = file.openRead().use { stream ->
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                check(out.size() + count <= 262_144) { "Gateway state exceeds limit" }
                out.write(buffer, 0, count)
            }
            out.toByteArray().toString(Charsets.UTF_8)
        }
        JSONObject(cipher().decrypt(encoded))
    }

    fun update(change: (JSONObject) -> Unit) = synchronized(lock) {
        val state = read() ?: JSONObject().put("installation_id", installationId())
        change(state)
        val stream = file.startWrite()
        try {
            stream.write(cipher().encrypt(state.toString()).toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    fun binding(): JSONObject? = read()?.optJSONObject("binding")
    fun owner(): String = binding()?.optString("owner_user_id").orEmpty()
    fun reason(): String = read()?.optString("reason").orEmpty()
    fun park(reason: String) {
        update { it.put("reason", reason) }
        SmsQueueEventBus.notifyQueueChanged()
    }
    fun parkSource(id: String, status: Int, reason: String) {
        update {
            val cases = it.optJSONObject("source_cases") ?: JSONObject()
            val prior = cases.optJSONObject(id) ?: JSONObject().put("first_reason", reason)
                .put("first_http_status", status).put("recorded_at", Instant.now().toString())
            prior.put("reason", reason).put("http_status", status).put("parked", true)
                .put("attempts", prior.optInt("attempts") + 1).put("last_recorded_at", Instant.now().toString())
            cases.put(id, prior)
            it.put("source_cases", cases)
        }
        SmsQueueEventBus.notifyQueueChanged()
    }
    fun retryReviewedSources() {
        update {
            val cases = it.optJSONObject("source_cases") ?: return@update
            for (id in cases.keys()) cases.getJSONObject(id).put("parked", false).put("retry_requested_at", Instant.now().toString())
        }
        SmsQueueEventBus.notifyQueueChanged()
    }
    fun active(): Boolean = read()?.let {
        it.has("binding") && it.optString("gateway_token").isNotEmpty() &&
            it.optBoolean("capture_enabled") && it.optString("reason") !in setOf("authorization_required", "permission_required")
    } == true

    private fun cipher() = ReceiptCipher(::key,
        { Base64.encodeToString(it, Base64.NO_WRAP) }, { Base64.decode(it, Base64.NO_WRAP) })
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("collect_momo_gateway_v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("collect_momo_gateway_v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    companion object { private val lock = Any() }
}

internal fun JSONObject.sourceParked(id: String): Boolean = optJSONObject(id)?.optBoolean("parked", true) == true
