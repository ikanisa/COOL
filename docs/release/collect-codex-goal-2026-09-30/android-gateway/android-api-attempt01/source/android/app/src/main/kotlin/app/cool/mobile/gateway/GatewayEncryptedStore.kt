package app.cool.mobile.gateway

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

internal class GatewayEncryptedStore(private val context: Context) : GatewayJournalStorage {
    private val directory = File(context.noBackupFilesDir, "collect_gateway_v1").also {
        if (!it.exists() && !it.mkdirs()) throw GatewayStateException("gateway_storage_unavailable")
    }
    private val journalFile = AtomicFile(File(directory, "journal.bin"))
    private val alias = "collect.gateway.storage.v1"

    private fun crypto(name: String): GatewayCrypto {
        val store = KeyStore.getInstance("AndroidKeyStore").also { it.load(null) }
        if (!store.containsAlias(alias)) {
            // A missing key for existing ciphertext is corruption/key loss;
            // never regenerate a key and silently replace existing evidence.
            if (directory.listFiles()?.any { it.isFile } == true) throw GatewayStateException("gateway_storage_key_unavailable")
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256).setUserAuthenticationRequired(false).build())
                generateKey()
            }
        }
        return GatewayCrypto(store.getKey(alias, null) as SecretKey, "CollectGateway/$name/v1")
    }

    private fun load(file: AtomicFile, name: String): JSONObject? {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return null
        try {
            val ciphertext = file.openRead().use { stream ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > GatewayCrypto.MAX_BYTES + 29) throw GatewayStateException("gateway_storage_limit")
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            return JSONObject(String(crypto(name).decrypt(ciphertext), Charsets.UTF_8))
        } catch (_: Exception) { throw GatewayStateException("gateway_storage_unavailable") }
    }

    private fun save(file: AtomicFile, name: String, value: JSONObject) {
        var stream: java.io.FileOutputStream? = null
        try {
            val bytes = crypto(name).encrypt(value.toString().toByteArray(Charsets.UTF_8))
            stream = file.startWrite()
            stream.write(bytes)
            stream.fd.sync()
            file.finishWrite(stream)
        } catch (_: Exception) {
            if (stream != null) file.failWrite(stream)
            throw GatewayStateException("gateway_storage_unavailable")
        }
    }

    override fun read(): GatewayJournalState = synchronized(GatewayJournal.PROCESS_LOCK) {
        val marker = load(AtomicFile(File(directory, "journal-marker.bin")), "journal-marker")
        val value = load(journalFile, "journal")
        if (value == null) {
            if (marker != null) throw GatewayStateException("gateway_journal_missing")
            return@synchronized GatewayJournalState()
        }
        if (marker == null) throw GatewayStateException("gateway_journal_invalid")
        requireKeys(marker, setOf("contract_version", "established"))
        if (marker.get("contract_version") != 1 || !strictBoolean(marker, "established")) throw GatewayStateException("gateway_journal_invalid")
        requireKeys(value, setOf("contract_version", "emergency_paused", "attempts"))
        if (value.get("contract_version") != 1) throw GatewayStateException("gateway_journal_invalid")
        val attempts = value.getJSONArray("attempts")
        if (attempts.length() > GatewayJournal.MAX_ATTEMPTS) throw GatewayStateException("gateway_journal_limit")
        val result = GatewayJournalState(strictBoolean(value, "emergency_paused"), (0 until attempts.length()).map { index ->
            val row = attempts.getJSONObject(index)
            requireKeys(row, setOf("device_id", "job_id", "attempt_id", "fence", "body_sha256", "destination_sha256", "grant_expires_at", "invocation_started_at", "callback_nonce", "segments", "invocation_exception"))
            val parts = row.getJSONArray("segments")
            if (parts.length() !in 1..GatewayJournal.MAX_SEGMENTS) throw GatewayStateException("gateway_journal_invalid")
            GatewayAttempt(strictString(row, "device_id"), strictString(row, "job_id"), strictString(row, "attempt_id"), strictInteger(row, "fence"),
                strictString(row, "body_sha256"), strictString(row, "destination_sha256"), strictString(row, "grant_expires_at"),
                strictString(row, "invocation_started_at"), strictString(row, "callback_nonce"),
                (0 until parts.length()).map { segment ->
                    val part = parts.getJSONObject(segment)
                    requireKeys(part, setOf("sent_callback_id", "delivery_callback_id", "sent", "delivery", "sent_code", "delivery_code", "sent_observed_at", "delivery_observed_at"))
                    SegmentEvidence(strictString(part, "sent_callback_id"), strictString(part, "delivery_callback_id"),
                        SegmentOutcome.valueOf(strictString(part, "sent")), SegmentOutcome.valueOf(strictString(part, "delivery")),
                        nullableInt(part, "sent_code"), nullableInt(part, "delivery_code"),
                        nullableString(part, "sent_observed_at"), nullableString(part, "delivery_observed_at"))
                }, strictBoolean(row, "invocation_exception"))
        })
        result.attempts.forEach(::validateAttempt)
        result
    }

    override fun commit(state: GatewayJournalState) = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (state.attempts.size > GatewayJournal.MAX_ATTEMPTS) throw GatewayStateException("gateway_journal_limit")
        state.attempts.forEach(::validateAttempt)
        // The established marker is committed first. Missing journal data
        // after any write/crash cannot silently become an empty new queue.
        val markerFile = AtomicFile(File(directory, "journal-marker.bin"))
        if (load(markerFile, "journal-marker") == null) {
            save(markerFile, "journal-marker", JSONObject().put("contract_version", 1).put("established", true))
        }
        save(journalFile, "journal", JSONObject().put("contract_version", 1).put("emergency_paused", state.emergencyPaused)
            .put("attempts", JSONArray(state.attempts.map { attempt ->
                JSONObject().put("device_id", attempt.deviceId).put("job_id", attempt.jobId).put("attempt_id", attempt.attemptId)
                    .put("fence", attempt.fence).put("body_sha256", attempt.bodySha256).put("destination_sha256", attempt.destinationSha256)
                    .put("grant_expires_at", attempt.grantExpiresAt).put("invocation_started_at", attempt.invocationStartedAt)
                    .put("callback_nonce", attempt.callbackNonce).put("invocation_exception", attempt.invocationException)
                    .put("segments", JSONArray(attempt.segments.map { segment ->
                        JSONObject().put("sent_callback_id", segment.sentCallbackId).put("delivery_callback_id", segment.deliveryCallbackId)
                            .put("sent", segment.sent.name).put("delivery", segment.delivery.name)
                            .put("sent_code", segment.sentCode ?: JSONObject.NULL).put("delivery_code", segment.deliveryCode ?: JSONObject.NULL)
                            .put("sent_observed_at", segment.sentObservedAt ?: JSONObject.NULL)
                            .put("delivery_observed_at", segment.deliveryObservedAt ?: JSONObject.NULL)
                    }))
            })))
    }

    fun readEnrollment(): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        load(AtomicFile(File(directory, "enrollment.bin")), "enrollment")?.also { value ->
            requireKeys(value, setOf("contract_version", "device_id", "installation_id", "key_sha256", "signing_certificate_sha256"))
            if (value.get("contract_version") != 1) throw GatewayStateException("gateway_enrollment_invalid")
            requireUuid(value, "device_id"); requireUuid(value, "installation_id")
            for (name in listOf("key_sha256", "signing_certificate_sha256")) {
                if (!strictString(value, name).matches(Regex("[0-9a-f]{64}"))) throw GatewayStateException("gateway_enrollment_invalid")
            }
        }
    }

    fun saveEnrollment(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        save(AtomicFile(File(directory, "enrollment.bin")), "enrollment", value)
    }

    fun readRequests(): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        val marker = load(AtomicFile(File(directory, "requests-marker.bin")), "requests-marker")
        val value = load(AtomicFile(File(directory, "requests.bin")), "requests")
        if (value == null) {
            if (marker != null) throw GatewayStateException("gateway_request_journal_missing")
            return@synchronized JSONObject().put("contract_version", 1).put("requests", JSONArray())
        }
        if (marker == null || marker.get("contract_version") != 1 || !strictBoolean(marker, "established")) throw GatewayStateException("gateway_request_journal_invalid")
        requireKeys(marker, setOf("contract_version", "established"))
        validateRequests(value)
        value
    }

    fun saveRequests(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateRequests(value)
        val marker = AtomicFile(File(directory, "requests-marker.bin"))
        if (load(marker, "requests-marker") == null) save(marker, "requests-marker", JSONObject().put("contract_version", 1).put("established", true))
        save(AtomicFile(File(directory, "requests.bin")), "requests", value)
    }

    private fun validateRequests(value: JSONObject) {
        requireKeys(value, setOf("contract_version", "requests"))
        if (value.get("contract_version") != 1 || value.get("requests") !is JSONArray) throw GatewayStateException("gateway_request_journal_invalid")
        val rows=value.getJSONArray("requests")
        if (rows.length() > 64) throw GatewayStateException("gateway_request_journal_limit")
        val ids=HashSet<String>()
        for (index in 0 until rows.length()) {
            val row=rows.getJSONObject(index)
            requireKeys(row, setOf("request_id", "action", "state", "callback_id", "request_sha256", "request_bytes_base64"))
            val id=requireUuid(row,"request_id")
            if (!ids.add(id) || strictString(row,"action") !in setOf("heartbeat","callback","dispatch_grant") ||
                strictString(row,"state") !in setOf("outcome_unknown","recorded")) throw GatewayStateException("gateway_request_journal_invalid")
            if (!row.isNull("callback_id")) requireUuid(row,"callback_id")
            if ((strictString(row,"action")=="callback") == row.isNull("callback_id")) throw GatewayStateException("gateway_request_journal_invalid")
            val encoded=strictString(row,"request_bytes_base64")
            if (encoded.length > 44 * 1024) throw GatewayStateException("gateway_request_journal_invalid")
            val bytes=android.util.Base64.decode(encoded,android.util.Base64.NO_WRAP)
            if (bytes.size > 32 * 1024 || sha256(String(bytes,Charsets.UTF_8)) != strictString(row,"request_sha256")) throw GatewayStateException("gateway_request_journal_invalid")
            val envelope=JSONObject(String(bytes,Charsets.UTF_8))
            requireKeys(envelope,setOf("contract_version","action","device_id","request_id","issued_at","payload"))
            if (envelope.get("contract_version") != 1 || requireUuid(envelope,"request_id") != id || strictString(envelope,"action") != strictString(row,"action")) throw GatewayStateException("gateway_request_journal_invalid")
            requireUuid(envelope,"device_id"); strictTimestamp(envelope,"issued_at")
            if (envelope.get("payload") !is JSONObject) throw GatewayStateException("gateway_request_journal_invalid")
        }
    }

    fun readIdentityMetadata(): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        load(AtomicFile(File(directory, "identity.bin")), "identity")
    }

    fun saveIdentityMetadata(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        save(AtomicFile(File(directory, "identity.bin")), "identity", value)
    }

    private fun nullableInt(row: JSONObject, name: String): Int? = if (row.isNull(name)) null else {
        val value = row.get(name)
        if (value !is Int) throw GatewayStateException("gateway_journal_invalid")
        value
    }
    private fun nullableString(row: JSONObject, name: String): String? = if (row.isNull(name)) null else strictString(row, name)
}
