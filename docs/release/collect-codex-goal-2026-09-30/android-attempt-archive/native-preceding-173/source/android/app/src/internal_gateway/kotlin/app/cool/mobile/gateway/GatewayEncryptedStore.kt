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

internal class GatewayEncryptedStore(
    private val context: Context,
    // Dependency seam for offline storage tests only. Production call sites use
    // the non-exportable Android Keystore path below; no runtime key setting.
    private val cryptoFactory: ((String) -> GatewayCrypto)? = null,
) : GatewayColdArchiveStorage {
    private val directory = File(context.noBackupFilesDir, "collect_gateway_v1").also {
        if (!it.exists() && !it.mkdirs()) throw GatewayStateException("gateway_storage_unavailable")
    }
    private val journalFile = AtomicFile(File(directory, "journal.bin"))
    private val alias = "collect.gateway.storage.v1"

    private fun crypto(name: String): GatewayCrypto {
        cryptoFactory?.let { return it(name) }
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
            val descriptor = android.system.Os.open(directory.path, android.system.OsConstants.O_RDONLY, 0)
            try { android.system.Os.fsync(descriptor) } finally { android.system.Os.close(descriptor) }
        } catch (_: Exception) {
            if (stream != null) file.failWrite(stream)
            throw GatewayStateException("gateway_storage_unavailable")
        }
    }

    override fun read(): GatewayJournalState = synchronized(GatewayJournal.PROCESS_LOCK) {
        readArchive() // Missing/corrupt archive is never silently ignored.
        coldStop() // Cold-control corruption never opens a local send gate.
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
        if (coldStop() && !state.emergencyPaused) throw GatewayStateException("gateway_archived_conflict_pending")
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

    override fun readRequests(): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        val archive = readArchive().getJSONArray("requests")
        val marker = load(AtomicFile(File(directory, "requests-marker.bin")), "requests-marker")
        val value = load(AtomicFile(File(directory, "requests.bin")), "requests")
        if (value == null) {
            if (marker != null) throw GatewayStateException("gateway_request_journal_missing")
            return@synchronized JSONObject().put("contract_version", 1).put("requests", JSONArray())
        }
        if (marker == null || marker.get("contract_version") != 1 || !strictBoolean(marker, "established")) throw GatewayStateException("gateway_request_journal_invalid")
        requireKeys(marker, setOf("contract_version", "established"))
        validateRequests(value)
        // Archive-first recovery: even if a crash interrupted physical pruning,
        // exact acknowledged non-callback rows no longer occupy active capacity.
        // A conflicting original identity/digest is corruption, never discarded.
        val rows = value.getJSONArray("requests")
        val active = JSONArray()
        for (index in 0 until rows.length()) {
            val request = GatewayStoredRequest.parse(rows.getJSONObject(index))
            val receipt = archivedRequest(archive, request.requestId)
            if (receipt != null) requireSameRequest(request, GatewayStoredRequest.parse(receipt.getJSONObject("request")))
            if ((receipt == null || request.action == "callback") && !coldAcknowledgedRequest(request)) active.put(rows.getJSONObject(index))
        }
        JSONObject().put("contract_version", 1).put("requests", active)
    }

    override fun saveRequests(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateRequests(value)
        val archive = readArchive().getJSONArray("requests")
        val rows = value.getJSONArray("requests")
        for (index in 0 until rows.length()) {
            val request = GatewayStoredRequest.parse(rows.getJSONObject(index))
            val receipt = archivedRequest(archive, request.requestId)
            if (receipt != null) {
                requireSameRequest(request, GatewayStoredRequest.parse(receipt.getJSONObject("request")))
                if (request.action != "callback") throw GatewayStateException("gateway_request_already_archived")
            }
            if (coldAcknowledgedRequest(request)) throw GatewayStateException("gateway_request_already_archived")
        }
        val marker = AtomicFile(File(directory, "requests-marker.bin"))
        if (load(marker, "requests-marker") == null) save(marker, "requests-marker", JSONObject().put("contract_version", 1).put("established", true))
        save(AtomicFile(File(directory, "requests.bin")), "requests", value)
    }

    private fun validateRequests(value: JSONObject) {
        requireKeys(value, setOf("contract_version", "requests"))
        if (value.get("contract_version") != 1 || value.get("requests") !is JSONArray) throw GatewayStateException("gateway_request_journal_invalid")
        val rows=value.getJSONArray("requests")
        if (rows.length() > MAX_REQUESTS) throw GatewayStateException("gateway_request_journal_limit")
        val ids=HashSet<String>()
        for (index in 0 until rows.length()) {
            val row=rows.getJSONObject(index)
            GatewayStoredRequest.parse(row)
            requireKeys(row, setOf("request_id", "action", "state", "callback_id", "request_sha256", "request_bytes_base64"))
            val id=requireUuid(row,"request_id")
            if (!ids.add(id) || strictString(row,"action") !in setOf("heartbeat","callback","dispatch_grant","arm_dispatch","archive_attempt") ||
                strictString(row,"state") !in setOf("outcome_unknown","recorded")) throw GatewayStateException("gateway_request_journal_invalid")
            if (!row.isNull("callback_id")) requireUuid(row,"callback_id")
            if ((strictString(row,"action")=="callback") == row.isNull("callback_id")) throw GatewayStateException("gateway_request_journal_invalid")
            val encoded=strictString(row,"request_bytes_base64")
            if (encoded.length > 44 * 1024) throw GatewayStateException("gateway_request_journal_invalid")
            val bytes=android.util.Base64.decode(encoded,android.util.Base64.NO_WRAP)
            if (bytes.size > 32 * 1024 || sha256(String(bytes,Charsets.UTF_8)) != strictString(row,"request_sha256")) throw GatewayStateException("gateway_request_journal_invalid")
            val envelope=JSONObject(String(bytes,Charsets.UTF_8))
            requireKeys(envelope,setOf("contract_version","action","device_id","request_id","issued_at","payload"))
            if (strictInteger(envelope,"contract_version") !in 1L..3L || requireUuid(envelope,"request_id") != id || strictString(envelope,"action") != strictString(row,"action")) throw GatewayStateException("gateway_request_journal_invalid")
            requireUuid(envelope,"device_id"); strictTimestamp(envelope,"issued_at")
            if (envelope.get("payload") !is JSONObject) throw GatewayStateException("gateway_request_journal_invalid")
        }
    }

    override fun readArchive(): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        val marker = load(AtomicFile(File(directory, "archive-marker.bin")), "archive-marker")
        val value = load(AtomicFile(File(directory, "archive.bin")), "archive")
        if (value == null) {
            if (marker != null) throw GatewayStateException("gateway_archive_missing")
            return@synchronized GatewayJournalArchive.empty()
        }
        if (marker == null) throw GatewayStateException("gateway_archive_invalid")
        requireKeys(marker, setOf("contract_version", "established"))
        if (marker.get("contract_version") != 1 || !strictBoolean(marker, "established")) throw GatewayStateException("gateway_archive_invalid")
        validatedArchive(value)
    }

    override fun commitArchive(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validatedArchive(value)
        val previous = readArchive()
        for (name in listOf("requests", "attempts")) {
            val before = previous.getJSONArray(name)
            val after = value.getJSONArray(name)
            if (after.length() < before.length()) throw GatewayStateException("gateway_archive_immutable")
            for (index in 0 until before.length()) {
                if (!archiveJsonEqual(before.getJSONObject(index), after.getJSONObject(index))) throw GatewayStateException("gateway_archive_immutable")
            }
        }
        val marker = AtomicFile(File(directory, "archive-marker.bin"))
        if (load(marker, "archive-marker") == null) save(marker, "archive-marker", JSONObject().put("contract_version", 1).put("established", true))
        // Existing save uses per-file AES-GCM AAD, AtomicFile, descriptor sync,
        // and finishWrite. Active journals are touched only after this returns.
        save(AtomicFile(File(directory, "archive.bin")), "archive", value)
    }

    override fun hasArchivedAttempt(attemptId: String): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (readColdAttempt(attemptId) != null) return@synchronized true
        val rows = readArchive().getJSONArray("attempts")
        (0 until rows.length()).any { rows.getJSONObject(it).getJSONObject("attempt").getString("attempt_id") == attemptId }
    }

    companion object { const val MAX_REQUESTS = 64; const val MAX_COLD_SHARD = 128; const val MAX_LATE_ATTEMPTS = 256; const val MAX_LATE_CALLBACKS = 64 }

    private fun coldControl(): JSONObject {
        val marker = load(AtomicFile(File(directory, "cold-marker.bin")), "cold-marker")
        val value = load(AtomicFile(File(directory, "cold-control.bin")), "cold-control")
        if (value == null) {
            if (marker != null) throw GatewayStateException("gateway_cold_archive_missing")
            return JSONObject().put("contract_version", 3).put("stopped", false).put("late_attempt_ids", JSONArray()).put("cold_shards", JSONArray())
        }
        if (marker == null) invalidArchive()
        requireKeys(marker, setOf("contract_version", "established"))
        if (strictInteger(marker, "contract_version") != 3L || !strictBoolean(marker, "established")) invalidArchive()
        requireKeys(value, setOf("contract_version", "stopped", "late_attempt_ids", "cold_shards"))
        if (strictInteger(value, "contract_version") != 3L) invalidArchive()
        strictBoolean(value, "stopped")
        val ids = value.getJSONArray("late_attempt_ids")
        if (ids.length() > MAX_LATE_ATTEMPTS || (0 until ids.length()).map { ids.getString(it) }.toSet().size != ids.length()) invalidArchive()
        for (i in 0 until ids.length()) if (!validUuid(ids.getString(i))) invalidArchive()
        val shards = value.getJSONArray("cold_shards")
        if (shards.length() > 256 || (0 until shards.length()).map { shards.getString(it) }.toSet().size != shards.length()) invalidArchive()
        for (i in 0 until shards.length()) if (!shards.getString(i).matches(Regex("[0-9a-f]{2}"))) invalidArchive()
        return value
    }

    private fun saveColdControl(value: JSONObject) {
        val before = coldControl()
        if (strictBoolean(before, "stopped") && !strictBoolean(value, "stopped")) invalidArchive()
        val a = before.getJSONArray("late_attempt_ids");val b = value.getJSONArray("late_attempt_ids")
        if (b.length() < a.length() || b.length() > MAX_LATE_ATTEMPTS || (0 until a.length()).any { a.getString(it) != b.getString(it) }) invalidArchive()
        val x = before.getJSONArray("cold_shards");val y = value.getJSONArray("cold_shards")
        if (y.length() < x.length() || y.length() > 256 || (0 until x.length()).any { x.getString(it) != y.getString(it) }) invalidArchive()
        val marker = AtomicFile(File(directory, "cold-marker.bin"))
        if (load(marker, "cold-marker") == null) save(marker, "cold-marker", JSONObject().put("contract_version", 3).put("established", true))
        save(AtomicFile(File(directory, "cold-control.bin")), "cold-control", value)
    }

    private fun coldIndex(id: String): JSONObject {
        if (!validUuid(id)) invalidArchive()
        val shard = sha256(id).take(2);val name = "cold-index-$shard"
        val value = load(AtomicFile(File(directory, "$name.bin")), name)
        if (value == null) {
            val known = coldControl().getJSONArray("cold_shards")
            if ((0 until known.length()).any { known.getString(it) == shard }) throw GatewayStateException("gateway_cold_archive_missing")
            return JSONObject().put("contract_version", 3).put("attempt_ids", JSONArray())
        }
        requireKeys(value, setOf("contract_version", "attempt_ids"))
        val ids = value.getJSONArray("attempt_ids")
        if (strictInteger(value, "contract_version") != 3L || ids.length() > MAX_COLD_SHARD ||
            (0 until ids.length()).map { ids.getString(it) }.toSet().size != ids.length()) invalidArchive()
        for (i in 0 until ids.length()) if (!validUuid(ids.getString(i)) || sha256(ids.getString(i)).take(2) != shard) invalidArchive()
        return value
    }

    override fun readColdAttempt(attemptId: String): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        coldControl();val index = coldIndex(attemptId).getJSONArray("attempt_ids")
        val value = load(AtomicFile(File(directory, "cold-$attemptId.bin")), "cold-$attemptId")
        if (value == null && (0 until index.length()).any { index.getString(it) == attemptId }) throw GatewayStateException("gateway_cold_archive_missing")
        value?.also { validateColdAttempt(it);if (requireUuid(it.getJSONObject("attempt"), "attempt_id") != attemptId) invalidArchive() }
    }

    override fun commitColdAttempt(attemptId: String, value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateColdAttempt(value)
        if (requireUuid(value.getJSONObject("attempt"), "attempt_id") != attemptId) invalidArchive()
        val index = coldIndex(attemptId);val ids = index.getJSONArray("attempt_ids")
        val existing = readColdAttempt(attemptId)
        if (existing != null && !archiveJsonEqual(existing, value)) throw GatewayStateException("gateway_archive_immutable")
        val indexed = (0 until ids.length()).any { ids.getString(it) == attemptId }
        if (!indexed && ids.length() >= MAX_COLD_SHARD) throw GatewayStateException("gateway_cold_archive_limit")
        if (load(AtomicFile(File(directory, "cold-control.bin")), "cold-control") == null) saveColdControl(coldControl())
        if (existing == null) save(AtomicFile(File(directory, "cold-$attemptId.bin")), "cold-$attemptId", value)
        val readback = readColdAttempt(attemptId) ?: invalidArchive()
        if (!archiveJsonEqual(readback, value)) invalidArchive()
        if (!indexed) {
            ids.put(attemptId);val name = "cold-index-${sha256(attemptId).take(2)}"
            save(AtomicFile(File(directory, "$name.bin")), name, index)
        }
        val control = coldControl();val shards = control.getJSONArray("cold_shards");val shard = sha256(attemptId).take(2)
        if (!(0 until shards.length()).any { shards.getString(it) == shard }) { shards.put(shard);saveColdControl(control) }
    }

    private fun coldAcknowledgedRequest(request: GatewayStoredRequest): Boolean {
        if (request.action !in setOf("callback", "archive_attempt")) return false
        val id = requireUuid(request.envelope.getJSONObject("payload"), "attempt_id")
        val value = readColdAttempt(id) ?: return false
        val known = if (request.action == "archive_attempt") value.getJSONObject("archive_request") else {
            val rows = value.getJSONArray("callback_requests")
            (0 until rows.length()).map { rows.getJSONObject(it) }.firstOrNull { it.getString("request_id") == request.requestId } ?: return false
        }
        if (known.getString("request_id") != request.requestId) return false
        requireSameRequest(request, GatewayStoredRequest.parse(known));return true
    }

    override fun coldStop(): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) { strictBoolean(coldControl(), "stopped") }
    override fun unresolvedArchivedEvidence(): Boolean = coldStop()

    override fun recordArchivedCallback(callback: GatewayCallback): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        val value = readColdAttempt(callback.attemptId) ?: return@synchronized false
        val a = archiveAttemptFromJson(value.getJSONObject("attempt"))
        if (callback.deviceId != a.deviceId || callback.fence != a.fence || callback.segmentIndex !in a.segments.indices || !sameNonce(callback.nonce, a.callbackNonce)) return@synchronized false
        val s = a.segments[callback.segmentIndex];val expected = if (callback.kind == CallbackKind.SENT) s.sentCallbackId else s.deliveryCallbackId
        if (callback.callbackId != expected) return@synchronized false
        try { if (!callback.occurredAt.endsWith("Z") || java.time.Instant.parse(callback.occurredAt) < java.time.Instant.parse(a.invocationStartedAt)) return@synchronized false }
        catch (_: Exception) { return@synchronized false }
        if (callback.resultCode == -1) return@synchronized true // exact known raw outcome, no future closure claim
        appendColdConflict(a, callback);true
    }

    private fun coldLate(id: String): JSONObject {
        val value = load(AtomicFile(File(directory, "cold-late-$id.bin")), "cold-late-$id")
        if (value == null) {
            val known = coldControl().getJSONArray("late_attempt_ids")
            if ((0 until known.length()).any { known.getString(it) == id }) throw GatewayStateException("gateway_cold_archive_missing")
            return JSONObject().put("contract_version", 3).put("attempt_id", id).put("callbacks", JSONArray())
        }
        requireKeys(value, setOf("contract_version", "attempt_id", "callbacks"))
        if (strictInteger(value, "contract_version") != 3L || requireUuid(value, "attempt_id") != id || value.getJSONArray("callbacks").length() > MAX_LATE_CALLBACKS) invalidArchive()
        for (i in 0 until value.getJSONArray("callbacks").length()) coldCallback(value.getJSONArray("callbacks").getJSONObject(i))
        return value
    }

    private fun coldCallback(value: JSONObject): GatewayCallback {
        requireKeys(value, setOf("callback_id", "device_id", "attempt_id", "fence", "segment_index", "nonce", "kind", "result_code", "occurred_at"))
        val callback = GatewayCallback(requireUuid(value, "callback_id"), requireUuid(value, "device_id"), requireUuid(value, "attempt_id"), strictInteger(value, "fence"), strictInteger(value, "segment_index").toInt(), strictString(value, "nonce"), CallbackKind.valueOf(strictString(value, "kind")), strictInteger(value, "result_code").toInt(), strictString(value, "occurred_at"))
        if (callback.fence !in 1..1_000_000_000L || callback.segmentIndex !in 0..9 || callback.resultCode !in -1..200 || !callback.nonce.matches(Regex("[0-9a-f]{64}"))) invalidArchive()
        strictTimestamp(value, "occurred_at");return callback
    }

    override fun appendColdConflict(attempt: GatewayAttempt, callback: GatewayCallback) = synchronized(GatewayJournal.PROCESS_LOCK) {
        val original = archiveAttemptFromJson((readColdAttempt(attempt.attemptId) ?: invalidArchive()).getJSONObject("attempt"))
        if (original != attempt || callback.deviceId != attempt.deviceId || callback.attemptId != attempt.attemptId || callback.fence != attempt.fence ||
            callback.segmentIndex !in attempt.segments.indices || !sameNonce(callback.nonce, attempt.callbackNonce) ||
            callback.callbackId != (if (callback.kind == CallbackKind.SENT) attempt.segments[callback.segmentIndex].sentCallbackId else attempt.segments[callback.segmentIndex].deliveryCallbackId)) invalidArchive()
        val late = coldLate(attempt.attemptId);val rows = late.getJSONArray("callbacks")
        val row = JSONObject().put("callback_id", callback.callbackId).put("device_id", callback.deviceId).put("attempt_id", callback.attemptId)
            .put("fence", callback.fence).put("segment_index", callback.segmentIndex).put("nonce", callback.nonce).put("kind", callback.kind.name)
            .put("result_code", callback.resultCode).put("occurred_at", callback.occurredAt)
        coldCallback(row)
        if ((0 until rows.length()).any { archiveJsonEqual(rows.getJSONObject(it), row) }) return@synchronized
        val control = coldControl();control.put("stopped", true)
        val ids = control.getJSONArray("late_attempt_ids")
        if (!(0 until ids.length()).any { ids.getString(it) == attempt.attemptId }) {
            if (ids.length() >= MAX_LATE_ATTEMPTS) throw GatewayStateException("gateway_cold_archive_limit")
            ids.put(attempt.attemptId)
        }
        saveColdControl(control) // stop is durable before any subsequent invocation
        if (rows.length() >= MAX_LATE_CALLBACKS) throw GatewayStateException("gateway_cold_archive_limit")
        rows.put(row);save(AtomicFile(File(directory, "cold-late-${attempt.attemptId}.bin")), "cold-late-${attempt.attemptId}", late)
    }

    override fun coldPendingCallbacks(): List<Pair<GatewayAttempt, GatewayCallback>> = synchronized(GatewayJournal.PROCESS_LOCK) {
        val ids = coldControl().getJSONArray("late_attempt_ids");val result = ArrayList<Pair<GatewayAttempt, GatewayCallback>>()
        for (i in 0 until ids.length()) {
            val id = ids.getString(i);val cold = readColdAttempt(id) ?: invalidArchive();val a = archiveAttemptFromJson(cold.getJSONObject("attempt"))
            val rows = coldLate(id).getJSONArray("callbacks")
            for (j in 0 until rows.length()) result.add(a to coldCallback(rows.getJSONObject(j)))
        }
        result
    }

    override fun exportColdAttempt(attemptId: String): GatewayColdArchiveExport = synchronized(GatewayJournal.PROCESS_LOCK) {
        readColdAttempt(attemptId) ?: throw GatewayStateException("gateway_attempt_missing");coldLate(attemptId)
        val parts = linkedMapOf<String, ByteArray>()
        for (name in listOf("cold-$attemptId", "cold-late-$attemptId")) {
            val file = AtomicFile(File(directory, "$name.bin"))
            if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) {
                val bytes = file.openRead().use { stream ->
                    val out = java.io.ByteArrayOutputStream();val buffer = ByteArray(4096)
                    while (true) { val n = stream.read(buffer);if (n < 0) break
                        if (out.size() + n > GatewayCrypto.MAX_BYTES + 29) throw GatewayStateException("gateway_cold_archive_limit")
                        out.write(buffer, 0, n)
                    };out.toByteArray()
                }
                crypto(name).decrypt(bytes) // cold readback before returning exact encrypted bytes
                parts["$name.bin"] = bytes
            }
        }
        GatewayColdArchiveExport(attemptId, parts)
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
