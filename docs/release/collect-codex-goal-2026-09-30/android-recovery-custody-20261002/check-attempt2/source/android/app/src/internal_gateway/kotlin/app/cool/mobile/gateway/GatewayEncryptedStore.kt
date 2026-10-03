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

internal class GatewayEncryptedStore private constructor(
    private val context: Context,
    // Dependency seam for offline storage tests only. Production call sites use
    // the non-exportable Android Keystore path below; no runtime key setting.
    private val cryptoFactory: ((String) -> GatewayCrypto)?,
    private val recoveryDirectory: File?,
) : GatewayColdArchiveStorage, GatewayContinuousArchiveStorage {
    constructor(context: Context, cryptoFactory: ((String) -> GatewayCrypto)? = null) : this(context, cryptoFactory, null)
    private val directory = (recoveryDirectory ?: File(context.noBackupFilesDir, "collect_gateway_v1")).also {
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
            if (if(recoveryDirectory!=null) GatewayRecovery.anyFile(directory) { true } else directory.listFiles()?.any { it.isFile } == true) throw GatewayStateException("gateway_storage_key_unavailable")
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

    private val retention by lazy { GatewayRetentionIndex(
        { name -> load(AtomicFile(File(directory, "$name.bin")), name) },
        { name, value -> save(AtomicFile(File(directory, "$name.bin")), name, value) },
        { val retained: (String) -> Boolean = { it.startsWith("retention-index-") || it.startsWith("retention-request-") || it.startsWith("retention-receipt-") || it.startsWith("retention-attempt-") || it.startsWith("retention-callback-") || it.startsWith("retention-protocol-") || it.startsWith("retention-terminal-") || it.startsWith("retention-observed-attempt-") || it.startsWith("retention-late-") }
          if(recoveryDirectory!=null) GatewayRecovery.anyFile(directory,retained) else directory.list()?.any(retained) ?: throw GatewayStateException("gateway_storage_unavailable") },
    ) }

    private val lateRetention by lazy { GatewayLateRetention(retention,
        { name -> load(AtomicFile(File(directory, "$name.bin")), name) },
        { name, value -> save(AtomicFile(File(directory, "$name.bin")), name, value) },
        { id -> archiveAttemptFromJson((readColdAttempt(id) ?: readObservedAttempt(id) ?: throw GatewayStateException("gateway_attempt_missing")).getJSONObject("attempt")) },
        { stopArchiveUncertainty() },
        { coldControl().getJSONArray("late_attempt_ids") },
        { id -> coldLate(id).getJSONArray("callbacks") },
    ) }
    internal fun retainedLateCallbackPayload(payload: JSONObject): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        lateRetention.evidenceForPayload(payload) != null
    }
    override fun coldCallbackPage(afterExclusive: String?, limit: Int): GatewayColdCallbackPage = synchronized(GatewayJournal.PROCESS_LOCK) {
        coldControl();lateRetention.page(afterExclusive, limit)
    }
    override fun nextColdCallbackPage(limit: Int): GatewayColdCallbackPage = synchronized(GatewayJournal.PROCESS_LOCK) {
        coldControl();lateRetention.nextPage(limit)
    }
    override fun readRetainedRequest(requestId: String): GatewayStoredRequest? = synchronized(GatewayJournal.PROCESS_LOCK) {
        val value = retention.read("request", retentionUuidKey(requestId)) ?: return@synchronized null
        val request = GatewayStoredRequest.parse(value)
        if (request.requestId != requestId) invalidArchive()
        request
    }

    private fun reserveOriginal(request: GatewayStoredRequest) {
        val known = readRetainedRequest(request.requestId)
        if (known != null) requireSameRequest(request, known)
        val original = JSONObject(request.row.toString()).put("state", "outcome_unknown")
        retention.publish("request", retentionUuidKey(request.requestId), original)
        // Alias records only identify original evidence. They do not retain a
        // grant/arm response or establish current dispatch authority.
        if (request.action == "arm_dispatch" && isSuccessorEnvelope(request.envelope)) {
            val payload = request.envelope.getJSONObject("payload"); val id = requireUuid(payload, "attempt_id")
            val value = JSONObject().put("contract_version", 1).put("protocol_family", SUCCESSOR_FAMILY).put("attempt_id", id).put("request_id", request.requestId).put("route", payload.getJSONObject("route"))
            val prior = retention.read("protocol", retentionUuidKey(id))
            if (prior != null && !archiveJsonEqual(prior, value)) throw GatewayStateException("gateway_retention_identity_conflict")
            retention.publish("protocol", retentionUuidKey(id), prior ?: value)
        } else if (request.action == "arm_dispatch" && strictInteger(request.envelope, "contract_version") == 2L) {
            val id = requireUuid(request.envelope.getJSONObject("payload"), "attempt_id")
            val value = JSONObject().put("attempt_id", id).put("request_id", request.requestId)
            val prior = retention.read("protocol", retentionUuidKey(id))
            retention.publish("protocol", retentionUuidKey(id), prior ?: value)
        }
        if (request.callbackId != null) {
            val payload = request.envelope.getJSONObject("payload")
            val alias = JSONObject().put("callback_id", request.callbackId).put("payload", payload).put("request_id", request.requestId)
            val callbackKey = retentionUuidKey(request.callbackId)
            val priorCallback = retention.read("callback", callbackKey)
            retention.publish("callback", callbackKey, priorCallback ?: alias)
            val bodyKey = sha256(request.callbackId + "\n" + retentionCanonical(payload)).take(32)
            val prior = retention.read("callback-body", bodyKey)
            if (prior != null && (prior.getString("callback_id") != request.callbackId || !archiveJsonEqual(prior.getJSONObject("payload"), payload))) invalidArchive()
            retention.publish("callback-body", bodyKey, prior ?: alias)
        }
    }

    internal fun retainedAttemptUsesV2(attemptId: String): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        val alias = retention.read("protocol", retentionUuidKey(attemptId)) ?: return@synchronized false
        if (isSuccessorEnvelope(alias)) { retainedSuccessorRoute(attemptId) ?: invalidArchive(); return@synchronized false }
        requireKeys(alias, setOf("attempt_id", "request_id"))
        if (requireUuid(alias, "attempt_id") != attemptId) invalidArchive()
        val request = readRetainedRequest(requireUuid(alias, "request_id")) ?: throw GatewayStateException("gateway_retention_missing")
        if (request.action != "arm_dispatch" || strictInteger(request.envelope, "contract_version") != 2L ||
            requireUuid(request.envelope.getJSONObject("payload"), "attempt_id") != attemptId) invalidArchive()
        true
    }

    internal fun retainedSuccessorRoute(attemptId: String): GatewayDispatchRoute.ReceiptSuccessorV1? = synchronized(GatewayJournal.PROCESS_LOCK) {
        val alias = retention.read("protocol", retentionUuidKey(attemptId)) ?: return@synchronized null
        if (!isSuccessorEnvelope(alias)) return@synchronized null
        requireKeys(alias, setOf("contract_version", "protocol_family", "attempt_id", "request_id", "route"))
        if (strictInteger(alias, "contract_version") != 1L || requireUuid(alias, "attempt_id") != attemptId) invalidArchive()
        val route = successorRouteFromJson(alias.getJSONObject("route"))
        val request = readRetainedRequest(requireUuid(alias, "request_id")) ?: throw GatewayStateException("gateway_retention_missing")
        if (request.action != "arm_dispatch" || !requestMatchesRoute(request, route) || requireUuid(request.envelope.getJSONObject("payload"), "attempt_id") != attemptId) invalidArchive()
        route
    }

    internal fun retainedCallbackRequest(id: String, payload: JSONObject, v2: Boolean): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        val key = if (v2) sha256(id + "\n" + retentionCanonical(payload)).take(32) else retentionUuidKey(id)
        val alias = retention.read(if (v2) "callback-body" else "callback", key) ?: return@synchronized false
        requireKeys(alias, setOf("callback_id", "payload", "request_id"))
        if (requireUuid(alias, "callback_id") != id || (v2 && !archiveJsonEqual(alias.getJSONObject("payload"), payload))) invalidArchive()
        val request = readRetainedRequest(requireUuid(alias, "request_id")) ?: throw GatewayStateException("gateway_retention_missing")
        if (request.action != "callback" || request.callbackId != id || !archiveJsonEqual(request.envelope.getJSONObject("payload"), alias.getJSONObject("payload"))) invalidArchive()
        true
    }

    override fun retainedCallbackReceipt(callbackId: String): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        val alias = retention.read("callback", retentionUuidKey(callbackId)) ?: return@synchronized null
        requireKeys(alias, setOf("callback_id", "payload", "request_id"))
        if (requireUuid(alias, "callback_id") != callbackId) invalidArchive()
        val receipt = readRequestReceipt(requireUuid(alias, "request_id")) ?: return@synchronized null
        val request = GatewayStoredRequest.parse(receipt.getJSONObject("request"))
        if (request.callbackId != callbackId || !archiveJsonEqual(alias.getJSONObject("payload"), request.envelope.getJSONObject("payload"))) invalidArchive()
        receipt
    }

    private fun validateObservedAttempt(value: JSONObject): GatewayAttempt {
        requireKeys(value, setOf("contract_version", "attempt", "callback_receipts", "archived_at"))
        if (strictInteger(value, "contract_version") != 4L) invalidArchive()
        strictTimestamp(value, "archived_at")
        val attempt = archiveAttemptFromJson(value.getJSONObject("attempt"))
        val receipts = value.getJSONArray("callback_receipts")
        if (attempt.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED || receipts.length() != attempt.segments.size * 2) invalidArchive()
        for (i in 0 until receipts.length()) validateRequestReceipt(receipts.getJSONObject(i))
        requireAttemptReceipts(attempt, receipts)
        return attempt
    }

    override fun readObservedAttempt(attemptId: String): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        val value = retention.read("observed-attempt", retentionUuidKey(attemptId)) ?: return@synchronized null
        if (validateObservedAttempt(value).attemptId != attemptId) invalidArchive()
        value
    }

    override fun commitObservedAttempt(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        val attempt = validateObservedAttempt(value)
        if (!migrateLegacyRetention()) throw GatewayStateException("gateway_retention_migration_pending")
        if (read().attempts.singleOrNull { it.attemptId == attempt.attemptId } != attempt) throw GatewayStateException("gateway_archive_source_conflict")
        val receipts = value.getJSONArray("callback_receipts")
        for (i in 0 until receipts.length()) {
            val receipt = receipts.getJSONObject(i)
            val request = GatewayStoredRequest.parse(receipt.getJSONObject("request"))
            val retained = readRequestReceipt(request.requestId) ?: throw GatewayStateException("gateway_archive_acknowledgement_pending")
            if (!archiveJsonEqual(retained, receipt)) invalidArchive()
        }
        retention.publish("observed-attempt", retentionUuidKey(attempt.attemptId), value)
        readObservedAttempt(attempt.attemptId) ?: invalidArchive()
        Unit // Observational evidence never removes a v1 hot attempt.
    }

    override fun readRequestReceipt(requestId: String): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        val value = retention.read("receipt", retentionUuidKey(requestId)) ?: return@synchronized null
        validateRequestReceipt(value)
        val source = GatewayStoredRequest.parse(value.getJSONObject("request"))
        if (source.requestId != requestId) invalidArchive()
        val original = readRetainedRequest(requestId) ?: throw GatewayStateException("gateway_retention_missing")
        requireSameRequest(original, source)
        value
    }

    override fun commitRequestReceipt(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateRequestReceipt(value)
        val request = GatewayStoredRequest.parse(value.getJSONObject("request"))
        reserveOriginal(request) // all dependent aliases precede ACK publication
        retention.publish("receipt", retentionUuidKey(request.requestId), value)
        if (!retention.indexed("receipt", retentionUuidKey(request.requestId))) invalidArchive()
        readRequestReceipt(request.requestId) ?: invalidArchive()
        lateRetention.bindReceipt(request) // exact late v2 transport only; never closes the original attempt
        Unit
    }

    private fun validateRequestReceipt(value: JSONObject) {
        // Reuse the exact authenticated legacy validator for this one bounded
        // receipt. Legacy archive bytes are never rewritten or appended here.
        validatedArchive(GatewayJournalArchive.empty().put("requests", JSONArray(listOf(value))))
    }

    override fun requestAcknowledged(request: GatewayStoredRequest): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        readRetainedRequest(request.requestId)?.let { requireSameRequest(request, it) }
        if (request.action != "callback" && readRequestReceipt(request.requestId) != null && retention.indexed("receipt", retentionUuidKey(request.requestId))) return@synchronized true
        if (request.action == "callback") {
            val receipt = readRequestReceipt(request.requestId)
            if (receipt != null) lateRetention.bindReceipt(request) // repair only an existing authenticated receipt
            if (lateRetention.receiptBound(request)) {
                if (receipt == null) throw GatewayStateException("gateway_retention_missing")
                return@synchronized true
            }
        }
        val key = retentionUuidKey(request.requestId)
        val marker = retention.read("terminal", key) ?: return@synchronized false
        if (!retention.indexed("terminal", key)) return@synchronized false
        requireKeys(marker, setOf("contract_version", "request_id", "attempt_id"))
        if (strictInteger(marker, "contract_version") != 4L || requireUuid(marker, "request_id") != request.requestId) invalidArchive()
        val id = requireUuid(marker, "attempt_id")
        val cold = readColdAttempt(id) ?: throw GatewayStateException("gateway_retention_missing")
        if (!coldIndexed(id)) return@synchronized false
        val rows = cold.getJSONArray("callback_requests")
        val originals = (0 until rows.length()).map { GatewayStoredRequest.parse(rows.getJSONObject(it)) } + GatewayStoredRequest.parse(cold.getJSONObject("archive_request"))
        requireSameRequest(request, originals.singleOrNull { it.requestId == request.requestId } ?: invalidArchive())
        true
    }

    private fun retainColdRequestIdentities(attemptId: String, value: JSONObject) {
        val callbacks = value.getJSONArray("callback_requests")
        val originals = (0 until callbacks.length()).map { GatewayStoredRequest.parse(callbacks.getJSONObject(it)) } + GatewayStoredRequest.parse(value.getJSONObject("archive_request"))
        originals.forEach(::reserveOriginal)
        for (request in originals) {
            val marker = JSONObject().put("contract_version", 4).put("request_id", request.requestId).put("attempt_id", attemptId)
            retention.publish("terminal", retentionUuidKey(request.requestId), marker)
        }
    }

    /** Each call copies at most four legacy objects. The cursor advances only
     * after exact original objects, aliases and receipts have durable readback.
     * Admission is closed until the old global UUID namespace is fully copied. */
    internal fun migrateLegacyRetention(): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        val legacy = readArchive()
        val control = coldControl()
        if (load(AtomicFile(File(directory, "cold-control.bin")), "cold-control") == null) saveColdControl(control)
        val shards = control.getJSONArray("cold_shards")
        val hot = load(AtomicFile(File(directory, "requests.bin")), "requests") ?: JSONObject().put("contract_version", 1).put("requests", JSONArray())
        validateRequests(hot)
        val hotRequests = hot.getJSONArray("requests")
        val name = "retention-migration"
        val file = AtomicFile(File(directory, "$name.bin"))
        val value = load(file, name) ?: JSONObject().put("contract_version", 4).put("archive_sha256", sha256(legacy.getJSONArray("requests").toString()))
            .put("shards_sha256", sha256(shards.toString())).put("hot_sha256", sha256(hotRequests.toString())).put("hot_position", 0)
            .put("request_position", 0).put("shard_position", 0).put("attempt_position", 0).put("complete", false)
        requireKeys(value, setOf("contract_version", "archive_sha256", "shards_sha256", "hot_sha256", "hot_position", "request_position", "shard_position", "attempt_position", "complete"))
        if (strictInteger(value, "contract_version") != 4L || strictString(value, "archive_sha256") != sha256(legacy.getJSONArray("requests").toString()) || strictString(value, "shards_sha256") != sha256(shards.toString())) invalidArchive()
        if (strictBoolean(value, "complete")) return@synchronized true
        if (strictString(value, "hot_sha256") != sha256(hotRequests.toString())) invalidArchive()
        var hotPosition = strictInteger(value, "hot_position").toInt()
        var requestPosition = strictInteger(value, "request_position").toInt()
        var shardPosition = strictInteger(value, "shard_position").toInt()
        var attemptPosition = strictInteger(value, "attempt_position").toInt()
        val requests = legacy.getJSONArray("requests")
        if (hotPosition !in 0..hotRequests.length() || requestPosition !in 0..requests.length() || shardPosition !in 0..shards.length() || attemptPosition !in 0..MAX_COLD_SHARD) invalidArchive()
        var remaining = 4
        while (hotPosition < hotRequests.length() && remaining > 0) { reserveOriginal(GatewayStoredRequest.parse(hotRequests.getJSONObject(hotPosition++)));remaining-- }
        while (hotPosition == hotRequests.length() && requestPosition < requests.length() && remaining > 0) {
            commitRequestReceipt(requests.getJSONObject(requestPosition++));remaining--
        }
        while (hotPosition == hotRequests.length() && requestPosition == requests.length() && shardPosition < shards.length() && remaining > 0) {
            val shard = shards.getString(shardPosition)
            val old = load(AtomicFile(File(directory, "cold-index-$shard.bin")), "cold-index-$shard") ?: throw GatewayStateException("gateway_cold_archive_missing")
            requireKeys(old, setOf("contract_version", "attempt_ids"))
            val ids = old.getJSONArray("attempt_ids")
            if (strictInteger(old, "contract_version") != 3L || ids.length() > MAX_COLD_SHARD || attemptPosition > ids.length()) invalidArchive()
            if (attemptPosition == ids.length()) { shardPosition++;attemptPosition = 0;continue }
            val id = ids.getString(attemptPosition)
            if (!validUuid(id) || sha256(id).take(2) != shard) invalidArchive()
            val cold = load(AtomicFile(File(directory, "cold-$id.bin")), "cold-$id") ?: throw GatewayStateException("gateway_cold_archive_missing")
            validateColdAttempt(cold)
            if (requireUuid(cold.getJSONObject("attempt"), "attempt_id") != id) invalidArchive()
            retention.publish("attempt", retentionUuidKey(id), JSONObject().put("attempt_id", id).put("cold_sha256", sha256(cold.toString())))
            retainColdRequestIdentities(id, cold)
            attemptPosition++;remaining--
        }
        // Empty exhausted shards need no receipt budget and no lifetime scan.
        if (shardPosition < shards.length()) {
            val old = load(AtomicFile(File(directory, "cold-index-${shards.getString(shardPosition)}.bin")), "cold-index-${shards.getString(shardPosition)}") ?: throw GatewayStateException("gateway_cold_archive_missing")
            if (attemptPosition == old.getJSONArray("attempt_ids").length()) { shardPosition++;attemptPosition = 0 }
        }
        val complete = hotPosition == hotRequests.length() && requestPosition == requests.length() && shardPosition == shards.length()
        value.put("hot_position", hotPosition).put("request_position", requestPosition).put("shard_position", shardPosition).put("attempt_position", attemptPosition).put("complete", complete)
        save(file, name, value)
        if (!archiveJsonEqual(load(file, name), value)) invalidArchive()
        complete
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
        val journalVersion = strictInteger(value, "contract_version")
        if (journalVersion !in 1L..2L) throw GatewayStateException("gateway_journal_invalid")
        val attempts = value.getJSONArray("attempts")
        if (attempts.length() > GatewayJournal.MAX_ATTEMPTS) throw GatewayStateException("gateway_journal_limit")
        val result = GatewayJournalState(strictBoolean(value, "emergency_paused"), (0 until attempts.length()).map { index ->
            val row = attempts.getJSONObject(index)
            if (journalVersion == 2L) return@map journalAttemptFromJsonV2(row)
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
        result.attempts.forEach { attempt ->
            validateAttempt(attempt)
            readObservedAttempt(attempt.attemptId)?.let { observed ->
                if (archiveAttemptFromJson(observed.getJSONObject("attempt")) != attempt) throw GatewayStateException("gateway_archive_source_conflict")
            }
        }
        // Archive-first restart recovery. A cold ACK can remove only the exact
        // complete original. Changed/unknown evidence remains on disk and fails
        // closed rather than being mistaken for an acknowledged active copy.
        result.copy(attempts = result.attempts.filter { attempt ->
            val cold = readColdAttempt(attempt.attemptId)
            if (cold == null) true else {
                if (archiveAttemptFromJson(cold.getJSONObject("attempt")) != attempt) throw GatewayStateException("gateway_archive_source_conflict")
                !coldIndexed(attempt.attemptId)
            }
        })
    }

    override fun commit(state: GatewayJournalState) = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (state.attempts.size > GatewayJournal.MAX_ATTEMPTS) throw GatewayStateException("gateway_journal_limit")
        if (coldStop() && !state.emergencyPaused) throw GatewayStateException("gateway_archived_conflict_pending")
        state.attempts.forEach(::validateAttempt)
        val old = load(journalFile, "journal")?.getJSONArray("attempts")
        if (old != null) for (i in 0 until old.length()) {
            val id = requireUuid(old.getJSONObject(i), "attempt_id")
            val observed = readObservedAttempt(id) ?: continue
            val original = archiveAttemptFromJson(observed.getJSONObject("attempt"))
            if (state.attempts.singleOrNull { it.attemptId == id } != original) {
                val terminal = readColdAttempt(id)
                val closed = state.attempts.none { it.attemptId == id } && terminal != null && coldIndexed(id) && archiveAttemptFromJson(terminal.getJSONObject("attempt")) == original
                if (!closed) throw GatewayStateException("gateway_attempt_archive_authority_pending")
            }
        }
        // The established marker is committed first. Missing journal data
        // after any write/crash cannot silently become an empty new queue.
        val markerFile = AtomicFile(File(directory, "journal-marker.bin"))
        if (load(markerFile, "journal-marker") == null) {
            save(markerFile, "journal-marker", JSONObject().put("contract_version", 1).put("established", true))
        }
        val existingVersion = load(journalFile, "journal")?.let { strictInteger(it, "contract_version").also { version -> if (version !in 1L..2L) invalidArchive() } }
        val version = if (existingVersion == 2L || state.attempts.any { it.dispatchRoute is GatewayDispatchRoute.ReceiptSuccessorV1 }) 2 else 1
        save(journalFile, "journal", JSONObject().put("contract_version", version).put("emergency_paused", state.emergencyPaused)
            .put("attempts", JSONArray(state.attempts.map { if (version == 2) journalAttemptJsonV2(it) else archiveAttemptJson(it) })))
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
        requireActiveInstallation()
        save(AtomicFile(File(directory, "enrollment.bin")), "enrollment", value)
    }

    override fun readRequests(): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        migrateLegacyRetention()
        val archive = readArchive().getJSONArray("requests")
        val marker = load(AtomicFile(File(directory, "requests-marker.bin")), "requests-marker")
        val value = load(AtomicFile(File(directory, "requests.bin")), "requests")
        if (value == null) {
            val recovered = recoverPendingRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray()))
            if (marker != null && recovered.getJSONArray("requests").length() == 0) throw GatewayStateException("gateway_request_journal_missing")
            return@synchronized recovered
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
        recoverPendingRequests(JSONObject().put("contract_version", 1).put("requests", active))
    }

    private fun recoverPendingRequests(value: JSONObject): JSONObject {
        val pending = load(AtomicFile(File(directory, "retention-hot-pending.bin")), "retention-hot-pending") ?: return value
        requireKeys(pending, setOf("contract_version", "requests"))
        if (strictInteger(pending, "contract_version") != 4L) invalidArchive()
        validateRequests(JSONObject().put("contract_version", 1).put("requests", pending.getJSONArray("requests")))
        val originals = pending.getJSONArray("requests")
        val rows = value.getJSONArray("requests")
        for (i in 0 until originals.length()) {
            val request = GatewayStoredRequest.parse(originals.getJSONObject(i))
            // Repair only the durably pending original. The caller cannot
            // substitute action, attempt, bytes or a fresh transport UUID.
            reserveOriginal(request)
            val active = (0 until rows.length()).map { GatewayStoredRequest.parse(rows.getJSONObject(it)) }.singleOrNull { it.requestId == request.requestId }
            if (active != null) requireSameRequest(request, active)
            else if (!requestAcknowledged(request)) rows.put(request.row)
        }
        validateRequests(value)
        return value
    }

    override fun saveRequests(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateRequests(value)
        if (!migrateLegacyRetention()) throw GatewayStateException("gateway_retention_migration_pending")
        val archive = readArchive().getJSONArray("requests")
        val rows = value.getJSONArray("requests")
        val submitted = (0 until rows.length()).map { rows.getJSONObject(it).getString("request_id") }.toSet()
        val previous = readRequests().getJSONArray("requests")
        for (index in 0 until previous.length()) {
            val request = GatewayStoredRequest.parse(previous.getJSONObject(index))
            if (request.requestId !in submitted && !requestAcknowledged(request)) throw GatewayStateException("gateway_unresolved_request_prune")
        }
        for (index in 0 until rows.length()) {
            val request = GatewayStoredRequest.parse(rows.getJSONObject(index))
            val receipt = archivedRequest(archive, request.requestId)
            if (receipt != null) {
                requireSameRequest(request, GatewayStoredRequest.parse(receipt.getJSONObject("request")))
                if (request.action != "callback") throw GatewayStateException("gateway_request_already_archived")
            }
            if (coldAcknowledgedRequest(request)) throw GatewayStateException("gateway_request_already_archived")
        }
        val pendingName = "retention-hot-pending"
        val pendingFile = AtomicFile(File(directory, "$pendingName.bin"))
        val pending = JSONObject().put("contract_version", 4).put("requests", JSONArray(rows.toString()))
        save(pendingFile, pendingName, pending)
        for (index in 0 until rows.length()) reserveOriginal(GatewayStoredRequest.parse(rows.getJSONObject(index)))
        val marker = AtomicFile(File(directory, "requests-marker.bin"))
        if (load(marker, "requests-marker") == null) save(marker, "requests-marker", JSONObject().put("contract_version", 1).put("established", true))
        save(AtomicFile(File(directory, "requests.bin")), "requests", value)
        val readback = load(AtomicFile(File(directory, "requests.bin")), "requests") ?: invalidArchive()
        if (!archiveJsonEqual(readback, value)) invalidArchive()
        save(pendingFile, pendingName, JSONObject().put("contract_version", 4).put("requests", JSONArray()))
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
            if (isSuccessorEnvelope(envelope)) { validateSuccessorEnvelope(String(bytes,Charsets.UTF_8), envelope); continue }
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
        if (readColdAttempt(attemptId) != null || readObservedAttempt(attemptId) != null) return@synchronized true
        val rows = readArchive().getJSONArray("attempts")
        (0 until rows.length()).any { rows.getJSONObject(it).getJSONObject("attempt").getString("attempt_id") == attemptId }
    }

    companion object { const val MAX_REQUESTS = 64; const val MAX_COLD_SHARD = 128; const val MAX_LATE_ATTEMPTS = 256; const val MAX_LATE_CALLBACKS = 64 }

    private fun coldControl(): JSONObject {
        val marker = load(AtomicFile(File(directory, "cold-marker.bin")), "cold-marker")
        val value = load(AtomicFile(File(directory, "cold-control.bin")), "cold-control")
        if (value == null) {
            if (marker != null) throw GatewayStateException("gateway_cold_archive_missing")
            // Losing both control files cannot erase an established stop or
            // shard catalog while immutable cold/late/ACK evidence remains.
            val coldFiles = if(recoveryDirectory!=null) GatewayRecovery.anyFile(directory) { it.startsWith("cold-") } else (directory.list()?.any { it.startsWith("cold-") } ?: throw GatewayStateException("gateway_storage_unavailable"))
            if (coldFiles) throw GatewayStateException("gateway_cold_archive_missing")
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
        val retained = retention.read("attempt", retentionUuidKey(attemptId))
        val value = load(AtomicFile(File(directory, "cold-$attemptId.bin")), "cold-$attemptId")
        if (value == null && (retained != null || (0 until index.length()).any { index.getString(it) == attemptId })) throw GatewayStateException("gateway_cold_archive_missing")
        value?.also {
            validateColdAttempt(it)
            if (requireUuid(it.getJSONObject("attempt"), "attempt_id") != attemptId) invalidArchive()
            if (retained != null) {
                requireKeys(retained, setOf("attempt_id", "cold_sha256"))
                if (requireUuid(retained, "attempt_id") != attemptId || strictString(retained, "cold_sha256") != sha256(it.toString())) invalidArchive()
            }
        }
    }

    override fun commitColdAttempt(attemptId: String, value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateColdAttempt(value)
        if (!migrateLegacyRetention()) throw GatewayStateException("gateway_retention_migration_pending")
        if (requireUuid(value.getJSONObject("attempt"), "attempt_id") != attemptId) invalidArchive()
        val existing = readColdAttempt(attemptId)
        if (existing != null && !archiveJsonEqual(existing, value)) throw GatewayStateException("gateway_archive_immutable")
        if (load(AtomicFile(File(directory, "cold-control.bin")), "cold-control") == null) saveColdControl(coldControl())
        if (existing == null) save(AtomicFile(File(directory, "cold-$attemptId.bin")), "cold-$attemptId", value)
        val readback = readColdAttempt(attemptId) ?: invalidArchive()
        if (!archiveJsonEqual(readback, value)) invalidArchive()
        retention.publish("attempt", retentionUuidKey(attemptId), JSONObject().put("attempt_id", attemptId).put("cold_sha256", sha256(readback.toString())))
        retainColdRequestIdentities(attemptId, readback)
    }

    private fun coldIndexed(id: String): Boolean {
        if (retention.indexed("attempt", retentionUuidKey(id))) return true
        val ids = coldIndex(id).getJSONArray("attempt_ids")
        val shards = coldControl().getJSONArray("cold_shards")
        return (0 until ids.length()).any { ids.getString(it) == id } &&
            (0 until shards.length()).any { shards.getString(it) == sha256(id).take(2) }
    }

    private fun coldAcknowledgedRequest(request: GatewayStoredRequest): Boolean {
        // The lookup key is exclusively the original UUID; a changed action or
        // attempt cannot select another namespace and evade identity fencing.
        readRetainedRequest(request.requestId)?.let { requireSameRequest(request, it) }
        return requestAcknowledged(request)
    }

    override fun coldStop(): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        val stopped = strictBoolean(coldControl(), "stopped")
        val marker = load(AtomicFile(File(directory, "late-stop-marker.bin")), "late-stop-marker")
        if (marker != null) {
            requireKeys(marker, setOf("contract_version", "stopped"))
            if (strictInteger(marker, "contract_version") != 5L || !strictBoolean(marker, "stopped")) invalidArchive()
            return@synchronized true
        }
        if (!stopped && retention.hasKind("late-evidence")) throw GatewayStateException("gateway_retention_missing")
        stopped
    }
    override fun unresolvedArchivedEvidence(): Boolean = coldStop()
    override fun terminalArchivedAttempt(attemptId: String): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        readColdAttempt(attemptId) != null
    }
    override fun observationalArchivedAttempt(attemptId: String): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        readObservedAttempt(attemptId) != null
    }

    override fun archiveCompactionPending(attemptId: String): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        val rows = readRequests().getJSONArray("requests")
        (0 until rows.length()).any { val r = GatewayStoredRequest.parse(rows.getJSONObject(it))
            r.action == "archive_attempt" && requireUuid(r.envelope.getJSONObject("payload"), "attempt_id") == attemptId }
    }

    override fun stopArchiveUncertainty() = synchronized(GatewayJournal.PROCESS_LOCK) {
        val control = coldControl()
        val markerFile = AtomicFile(File(directory, "late-stop-marker.bin"))
        val marker = load(markerFile, "late-stop-marker")
        val expected = JSONObject().put("contract_version", 5).put("stopped", true)
        if (marker == null) save(markerFile, "late-stop-marker", expected)
        else if (!archiveJsonEqual(marker, expected)) invalidArchive()
        if (!archiveJsonEqual(load(markerFile, "late-stop-marker"), expected)) invalidArchive()
        if (!strictBoolean(control, "stopped")) { control.put("stopped", true);saveColdControl(control) }
    }

    internal fun readUncompactableAck(attemptId: String): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (!validUuid(attemptId)) invalidArchive()
        val v = load(AtomicFile(File(directory, "cold-uncompactable-$attemptId.bin")), "cold-uncompactable-$attemptId") ?: return@synchronized null
        requireKeys(v, setOf("contract_version", "archive_request", "acknowledgement", "retained_at"))
        if (strictInteger(v, "contract_version") != 3L) invalidArchive()
        strictTimestamp(v, "retained_at")
        val r = GatewayStoredRequest.parse(v.getJSONObject("archive_request"));val p = r.envelope.getJSONObject("payload")
        if (r.action != "archive_attempt" || requireUuid(p, "attempt_id") != attemptId) invalidArchive()
        val ack = v.getJSONObject("acknowledgement")
        validateRouteArchiveAck(r, ack)
        if (!strictBoolean(ack, "ok") || strictBoolean(ack, "replay")) invalidArchive()
        v
    }

    override fun retainUncompactableAck(original: GatewayStoredRequest, ack: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        val p = original.envelope.getJSONObject("payload");val id = requireUuid(p, "attempt_id")
        validateRouteArchiveAck(original, ack)
        if (original.action != "archive_attempt" || !strictBoolean(ack, "ok") || strictBoolean(ack, "replay")) invalidArchive()
        val rows = readRequests().getJSONArray("requests")
        val source = (0 until rows.length()).map { GatewayStoredRequest.parse(rows.getJSONObject(it)) }.singleOrNull { it.requestId == original.requestId }
            ?: throw GatewayStateException("gateway_archive_request_missing")
        requireSameRequest(original, source)
        stopArchiveUncertainty() // durable stop before ACK or transport-state changes
        val before = readUncompactableAck(id)
        if (before != null) {
            requireSameRequest(original, GatewayStoredRequest.parse(before.getJSONObject("archive_request")))
            if (!archiveJsonEqual(before.getJSONObject("acknowledgement"), ack)) invalidArchive()
        } else {
            val v = JSONObject().put("contract_version", 3).put("archive_request", original.row).put("acknowledgement", JSONObject(ack.toString()))
                .put("retained_at", gatewayWireTime(java.time.Instant.now()))
            save(AtomicFile(File(directory, "cold-uncompactable-$id.bin")), "cold-uncompactable-$id", v)
        }
        val readback = readUncompactableAck(id) ?: invalidArchive()
        requireSameRequest(original, GatewayStoredRequest.parse(readback.getJSONObject("archive_request")))
        if (!archiveJsonEqual(readback.getJSONObject("acknowledgement"), ack)) invalidArchive()
        // This means only that the exact transport request was recorded. Its
        // unknown hot attempt/callback originals remain ineligible for pruning.
        for (i in 0 until rows.length()) if (rows.getJSONObject(i).getString("request_id") == original.requestId) rows.getJSONObject(i).put("state", "recorded")
        saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
    }

    override fun recordArchivedCallback(callback: GatewayCallback): Boolean = synchronized(GatewayJournal.PROCESS_LOCK) {
        val value = readColdAttempt(callback.attemptId) ?: readObservedAttempt(callback.attemptId) ?: return@synchronized false
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

    private fun coldCallback(value: JSONObject): GatewayCallback = gatewayLateCallbackFromJson(value)

    override fun appendColdConflict(attempt: GatewayAttempt, callback: GatewayCallback) = synchronized(GatewayJournal.PROCESS_LOCK) {
        lateRetention.append(attempt, callback)
    }

    /** Compatibility observer; bounded first page. The sender uses the durable
     * fair cursor and never materializes the lifetime retained observation set. */
    override fun coldPendingCallbacks(): List<Pair<GatewayAttempt, GatewayCallback>> = synchronized(GatewayJournal.PROCESS_LOCK) {
        coldCallbackPage(null, GatewayLateRetention.PAGE_LIMIT).entries.map { it.attempt to it.callback }
    }

    override fun exportColdCallbackPage(afterExclusive: String?, limit: Int): GatewayLateCallbackExportPage = synchronized(GatewayJournal.PROCESS_LOCK) {
        val page = coldCallbackPage(afterExclusive, limit);val parts = linkedMapOf<String, ByteArray>()
        for (entry in page.entries) for (name in listOf("retention-late-evidence-${entry.evidenceKey}", "retention-late-work-${entry.cursorKey}")) {
            val file = AtomicFile(File(directory, "$name.bin"));val bytes = file.openRead().use { stream ->
                val out = java.io.ByteArrayOutputStream();val buffer = ByteArray(4096)
                while (true) { val count = stream.read(buffer);if (count < 0) break
                    if (out.size() + count > GatewayCrypto.MAX_BYTES + 29) invalidArchive()
                    out.write(buffer, 0, count)
                };out.toByteArray()
            }
            if (bytes.size > GatewayCrypto.MAX_BYTES + 29) invalidArchive()
            crypto(name).decrypt(bytes);parts["$name.bin"] = bytes
        }
        GatewayLateCallbackExportPage(page.nextCursor, parts, page.migrationPending)
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
        GatewayColdArchiveExport(attemptId, parts, retention.hasKind("late-evidence"))
    }

    fun readIdentityMetadata(): JSONObject? = synchronized(GatewayJournal.PROCESS_LOCK) {
        load(AtomicFile(File(directory, "identity.bin")), "identity")
    }

    fun saveIdentityMetadata(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        requireActiveInstallation()
        save(AtomicFile(File(directory, "identity.bin")), "identity", value)
    }

    /** Same-key inactive validation. Raw originals are held elsewhere. Every
     * repair uses the existing source-bound algorithms, behind the inactive
     * fence and durable stop. No invocation, transport or pruning is called. */
    private fun validateRecovery(files: Long, cancelled: () -> Boolean) {
        if(recoveryDirectory==null || !File(directory,GatewayRecovery.INACTIVE).isFile) invalidArchive()
        fun check() { if(cancelled()) throw GatewayStateException("gateway_recovery_cancelled") }
        // Normalize committed AtomicFile backups only in this isolated view.
        // One file family per step avoids cross-reader side effects while the
        // directory iterator is live. Raw sidecars remain in original.
        GatewayRecovery.eachFile(directory,cancelled) { filename ->
            if(filename.endsWith(".bin.bak")) {
                val name=filename.removeSuffix(".bin.bak")
                load(AtomicFile(File(directory,"$name.bin")),name) ?: invalidArchive()
            }
        }
        coldStop() // validate original stop/control before adding a new latch
        val oldControl=coldControl()
        val shards=oldControl.getJSONArray("cold_shards")
        for(i in 0 until shards.length()) {
            val shard=shards.getString(i)
            val historical=load(AtomicFile(File(directory,"cold-index-$shard.bin")),"cold-index-$shard") ?: throw GatewayStateException("gateway_cold_archive_missing")
            validateRecoveryObject("cold-index-$shard")
        }
        stopArchiveUncertainty()
        GatewayJournal(this).read();readArchive();readEnrollment()
        readIdentityMetadata()?.let { metadata ->
            requireKeys(metadata,setOf("contract_version","installation_id","key_sha256","signing_certificate_sha256","public_key_spki_base64"))
            if(strictInteger(metadata,"contract_version")!=1L) invalidArchive();requireUuid(metadata,"installation_id")
            for(name in listOf("key_sha256","signing_certificate_sha256")) if(!strictString(metadata,name).matches(Regex("[0-9a-f]{64}"))) invalidArchive()
            val keyBytes=try { java.util.Base64.getDecoder().decode(strictString(metadata,"public_key_spki_base64")) } catch(_:Exception) { invalidArchive() }
            if(keyBytes.size !in 1..1024 || java.security.MessageDigest.getInstance("SHA-256").digest(keyBytes).joinToString("") { "%02x".format(it) }!=strictString(metadata,"key_sha256")) invalidArchive()
            readEnrollment()?.let { enrolled -> GatewayInstalledEnrollment.verify(metadata,enrolled,metadata.getString("key_sha256"),metadata.getString("public_key_spki_base64"),metadata.getString("signing_certificate_sha256")) }
        }
        // Legacy readers do at most four rows/call. Bound total repair work by
        // finite inventory plus bounded legacy arrays, with caller cancellation.
        val workLimit = files.coerceAtMost(Long.MAX_VALUE/129)*129+1000
        var work=0L
        while(!migrateLegacyRetention()) { check();if(++work>workLimit) invalidArchive() }
        readRequests() // repairs pending immutable hot originals, never resends
        // A crash may leave a valid cold terminal object before its identity
        // ancestors/terminal aliases were fully published. Reuse its exact
        // existing ACK through the current source-bound publisher; no new ACK.
        GatewayRecovery.eachFile(directory,cancelled) { filename ->
            if(filename.matches(Regex("cold-[0-9a-f-]{36}\\.bin"))) {
                val id=filename.removePrefix("cold-").removeSuffix(".bin")
                val original=readColdAttempt(id) ?: invalidArchive()
                commitColdAttempt(id,original)
            }
        }
        var cursor: String?=null
        var expectedSequence=java.math.BigInteger.ZERO
        do { check();val page=coldCallbackPage(cursor,8)
            if(++work>workLimit) invalidArchive()
            if(page.migrationPending) continue
            for(entry in page.entries) {
                if(entry.cursorKey!=expectedSequence.toString(16).padStart(32,'0')) invalidArchive()
                expectedSequence=expectedSequence.add(java.math.BigInteger.ONE)
            }
            cursor=page.nextCursor
        } while(page.migrationPending || cursor!=null)
        // Validate the existing durable reader/captured ceiling on the inactive
        // view. Advancing this cursor is scheduling evidence, never completion.
        nextColdCallbackPage(8)
        lateRetention.validateRecoveryReader()
        retention.validateRecoveryRoots()
        GatewayRecovery.eachFile(directory,cancelled) { filename ->
            if(filename==GatewayRecovery.INACTIVE) return@eachFile
            if(!filename.matches(Regex("[a-z0-9][a-z0-9-]{0,180}\\.bin(?:\\.bak|\\.new)?"))) invalidArchive()
            // Sidecars were already preserved exactly. Only AtomicFile's
            // effective committed logical object has semantic authority.
            if(filename.endsWith(".bak") || filename.endsWith(".new")) return@eachFile
            validateRecoveryObject(filename.removeSuffix(".bin"))
        }
        GatewayJournal(this).read();readRequests();if(!coldStop()) invalidArchive()
        try { requireActiveInstallation();invalidArchive() } catch(e:GatewayStateException) { if(e.reasonCode!="gateway_recovery_inactive") throw e }
    }

    private fun validateRecoveryObject(name: String) {
        val value=load(AtomicFile(File(directory,"$name.bin")),name) ?: throw GatewayStateException("gateway_retention_missing")
        val kinds=listOf("observed-attempt","callback-body","late-evidence","late-receipt","late-work","late-body","request","receipt","attempt","callback","protocol","terminal")
        if(name.startsWith("retention-index-")) {
            val kind=kinds.firstOrNull { name.startsWith("retention-index-$it-") } ?: invalidArchive()
            val prefix=name.removePrefix("retention-index-$kind-").let { if(it=="root") "" else it }
            retention.validateRecoveryNode(kind,prefix);return
        }
        val kind=kinds.firstOrNull { name.startsWith("retention-$it-") }
        if(kind!=null) {
            val key=name.removePrefix("retention-$kind-");if(!key.matches(Regex("[0-9a-f]{32}"))) invalidArchive()
            if(!archiveJsonEqual(retention.read(kind,key),value)) invalidArchive()
            fun uuid() = key.chunked(2).joinToString("").let { it.substring(0,8)+"-"+it.substring(8,12)+"-"+it.substring(12,16)+"-"+it.substring(16,20)+"-"+it.substring(20) }
            when(kind) {
                "request" -> { val request=GatewayStoredRequest.parse(value);if(retentionUuidKey(request.requestId)!=key) invalidArchive() }
                "receipt" -> readRequestReceipt(uuid()) ?: invalidArchive()
                "attempt" -> readColdAttempt(uuid()) ?: invalidArchive()
                "observed-attempt" -> readObservedAttempt(uuid()) ?: invalidArchive()
                "protocol" -> if(retainedSuccessorRoute(uuid()) == null && !retainedAttemptUsesV2(uuid())) invalidArchive()
                "callback","callback-body" -> {
                    requireKeys(value,setOf("callback_id","payload","request_id"));val id=requireUuid(value,"callback_id");val payload=value.getJSONObject("payload")
                    if((kind=="callback" && retentionUuidKey(id)!=key) || (kind=="callback-body" && sha256(id+"\n"+retentionCanonical(payload)).take(32)!=key)) invalidArchive()
                    val request=readRetainedRequest(requireUuid(value,"request_id")) ?: invalidArchive()
                    if(request.action!="callback" || request.callbackId!=id || !archiveJsonEqual(payload,request.envelope.getJSONObject("payload"))) invalidArchive()
                }
                "terminal" -> {
                    requireKeys(value,setOf("contract_version","request_id","attempt_id"))
                    if(strictInteger(value,"contract_version")!=4L || requireUuid(value,"request_id")!=uuid()) invalidArchive()
                    val request=readRetainedRequest(uuid()) ?: invalidArchive()
                    val cold=readColdAttempt(requireUuid(value,"attempt_id")) ?: invalidArchive()
                    val rows=cold.getJSONArray("callback_requests")
                    val originals=(0 until rows.length()).map { GatewayStoredRequest.parse(rows.getJSONObject(it)) }+GatewayStoredRequest.parse(cold.getJSONObject("archive_request"))
                    requireSameRequest(request,originals.singleOrNull { it.requestId==request.requestId } ?: invalidArchive())
                }
                "late-receipt" -> {
                    val request=readRetainedRequest(uuid()) ?: invalidArchive()
                    if(readRequestReceipt(request.requestId)==null || !lateRetention.receiptBound(request)) invalidArchive()
                }
                else -> lateRetention.validateRecoveryRecord(kind,key)
            };return
        }
        when {
            name.matches(Regex("cold-[0-9a-f-]{36}")) -> readColdAttempt(name.removePrefix("cold-")) ?: invalidArchive()
            name.matches(Regex("cold-uncompactable-[0-9a-f-]{36}")) -> {
                val ack=readUncompactableAck(name.removePrefix("cold-uncompactable-")) ?: invalidArchive()
                val original=GatewayStoredRequest.parse(ack.getJSONObject("archive_request"));val retained=readRetainedRequest(original.requestId) ?: invalidArchive();requireSameRequest(original,retained)
            }
            name.matches(Regex("cold-late-[0-9a-f-]{36}")) -> {
                val id=name.removePrefix("cold-late-");val rows=coldLate(id).getJSONArray("callbacks")
                val original=archiveAttemptFromJson((readColdAttempt(id) ?: readObservedAttempt(id) ?: invalidArchive()).getJSONObject("attempt"))
                for(i in 0 until rows.length()) validateGatewayLateCallback(original,coldCallback(rows.getJSONObject(i)))
            }
            name.matches(Regex("cold-index-[0-9a-f]{2}")) -> {
                requireKeys(value,setOf("contract_version","attempt_ids"));if(strictInteger(value,"contract_version")!=3L) invalidArchive()
                val ids=value.getJSONArray("attempt_ids");if(ids.length()>MAX_COLD_SHARD || (0 until ids.length()).map { ids.getString(it) }.toSet().size!=ids.length()) invalidArchive()
                for(i in 0 until ids.length()) { val id=ids.getString(i);if(sha256(id).take(2)!=name.removePrefix("cold-index-")) invalidArchive();readColdAttempt(id) ?: invalidArchive() }
            }
            name in setOf("journal","journal-marker","requests","requests-marker","archive","archive-marker","cold-control","cold-marker","late-stop-marker","identity","enrollment","retention-marker","retention-control","retention-migration","retention-hot-pending","late-retention-control","late-retention-pending","late-retention-migration","late-retention-reader") -> Unit // exact current readers validated their strict schemas/source cursors above
            else -> throw GatewayStateException("gateway_recovery_object_unknown")
        }
    }

    fun requireActiveInstallation() {
        if (recoveryDirectory != null || File(directory, GatewayRecovery.INACTIVE).exists()) throw GatewayStateException("gateway_recovery_inactive")
    }

    fun exportRecovery(destination: File, cancelled: () -> Boolean = { false }): GatewayRecoveryArchive =
        GatewayCycleGate.run { synchronized(GatewayJournal.PROCESS_LOCK) {
            requireActiveInstallation();GatewayRecovery.export(directory, destination, cancelled)
        } } ?: throw GatewayStateException("gateway_cycle_busy")

    fun restoreRecovery(archive: File, manifestSha256: String, destination: File, cancelled: () -> Boolean = { false }): GatewayRecoveryResult =
        GatewayCycleGate.run { synchronized(GatewayJournal.PROCESS_LOCK) {
            GatewayRecovery.restore(archive,manifestSha256,destination,File(context.noBackupFilesDir,"collect_gateway_v1"),cancelled) { view, count ->
                val decryptor = cryptoFactory ?: run {
                    val keys=KeyStore.getInstance("AndroidKeyStore").also { it.load(null) }
                    if(!keys.containsAlias(alias)) return@restore false
                    val key=keys.getKey(alias,null) as? SecretKey ?: throw GatewayStateException("gateway_storage_key_unavailable");
                    val factory: (String) -> GatewayCrypto = { name -> GatewayCrypto(key,"CollectGateway/$name/v1") };factory
                }
                val recovered=GatewayEncryptedStore(context,decryptor,view)
                recovered.validateRecovery(count,cancelled);true
            }
        } } ?: throw GatewayStateException("gateway_cycle_busy")

    private fun nullableInt(row: JSONObject, name: String): Int? = if (row.isNull(name)) null else {
        val value = row.get(name)
        if (value !is Int) throw GatewayStateException("gateway_journal_invalid")
        value
    }
    private fun nullableString(row: JSONObject, name: String): String? = if (row.isNull(name)) null else strictString(row, name)
}
