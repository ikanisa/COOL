"""Exact BuriMunsi transformations for verified upstream Kotlin sources."""


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError('Receiver source hook did not match exactly; no output written.')
    return text.replace(old, new)



def queue_disposition(source: str) -> str:
    """Extract three exact methods, never the member scheduler/token/uploader."""
    fragments = [
        '''    fun park(row: JSONObject, status: Int) {
        require(permanentSourceError(status))
        row.put("needs_review", true).put("upload_error_status", status)
    }''',
        '''    fun retry(row: JSONObject) {
        row.remove("needs_review")
        row.remove("upload_error_status")
    }''',
        '    fun permanentSourceError(status: Int): Boolean = status in setOf(400, 409, 413, 422)',
    ]
    for fragment in fragments:
        if source.count(fragment) != 1:
            raise ValueError('Queue-disposition fragment drift; no output written.')
    return ('package app.cool.mobile.receiver_sms\n\nimport org.json.JSONObject\n\n'
            '/** Exact queue-disposition methods extracted from pinned Collect source. */\n'
            'internal object MemberSmsUploadPolicy {\n' + '\n'.join(fragments) + '\n}\n')



def _adapt_momo_gateway_policy(text: str) -> str:
    text = replace_once(text, '''    /** Inbox text lacks the PDU evidence required to prove multipart completeness.
     * Retain uncertain or non-financial sources locally; never transport them merely
     * because their SIM binding was resolved. This is not provider authentication. */''', '''    /** Current-binding inbox observations may be synced as incomplete for review.
     * They never claim PDU completeness or become automatic posting authority. */''')
    text = replace_once(text, '    fun gatewayUploadsAdmitted(): Boolean = false',
        '    fun gatewayUploadsAdmitted(runtimeAdmission: Boolean = false): Boolean = runtimeAdmission')
    text = replace_once(text, 'complete: Boolean, sender: String, body: String): Boolean =',
        'complete: Boolean, sender: String, body: String, runtimeAdmission: Boolean = false, sourceAdmission: Boolean = false): Boolean =')
    text = replace_once(text, '        gatewayUploadsAdmitted() && !sourceUnresolved',
        '        gatewayUploadsAdmitted(runtimeAdmission) && !sourceUnresolved')
    text = replace_once(text, 'sourceMode == "live" && complete && memberSource(sender, body) &&',
        '((sourceMode == "live" && complete) || (sourceMode == "catch_up" && !complete)) && sourceAdmission &&')
    text = replace_once(text, '(?:code|password|passcode|otp)', '(?:password|passcode|otp)')
    return text


def _adapt_sms_queue_store(text: str) -> str:
    text = replace_once(text, '            val envelopeId = envelope.optString("id", "")', '''            val envelopeId = envelope.optString("id", "")
            if (envelopeId.isBlank() || envelope.opt("raw_body") !is String || envelope.optString("raw_body").isBlank())
                return@synchronized AppendResult.FAILED''')
    text = replace_once(text, '''                    return@synchronized AppendResult.DUPLICATE''', '''                    return@synchronized if (item.opt("raw_body") == envelope.opt("raw_body") &&
                        item.opt("owner_user_id") == envelope.opt("owner_user_id")) AppendResult.DUPLICATE
                    else AppendResult.FAILED''')
    text = replace_once(text, '''        val encrypted = preferences().getString(ENCRYPTED_QUEUE_KEY, null)
            ?: return migrateLegacyQueueLocked()
        return try {
            val queue = JSONArray(decrypt(encrypted))''', '''        return try {
            val durable = durableQueueFile(context).read()
            val encrypted = durable ?: preferences().getString(ENCRYPTED_QUEUE_KEY, null)
                ?: return migrateLegacyQueueLocked()
            val queue = JSONArray(decrypt(encrypted))
            if (durable == null) check(durableQueueFile(context).write(encrypted)) { "Queue migration was not durable" }''')
    text = replace_once(text, '''        return preferences().commitReceiptState {
            putString(ENCRYPTED_QUEUE_KEY, encrypted)
            remove(LEGACY_QUEUE_KEY)
        }''', '''        if (!durableQueueFile(context).write(encrypted)) return false
        // Cleanup is secondary. The committed no-backup ciphertext is authoritative.
        preferences().commitReceiptState { remove(ENCRYPTED_QUEUE_KEY); remove(LEGACY_QUEUE_KEY) }
        return true''')
    marker = '    internal fun readForGateway(ownerUserId: String): JSONArray = synchronized(lock) {'
    text = replace_once(text, marker, '''    /** Proof for the observation scanner: canonical source remains queued or durably acknowledged. */
    internal fun hasGatewaySource(owner: String, captureId: String, bindingId: String,
                                  bindingVersion: Int, bodyHash: String): Boolean = synchronized(lock) {
        val queue = readForGateway(owner)
        for (index in 0 until queue.length()) {
            val row = queue.getJSONObject(index)
            if (row.opt("id") == captureId) return@synchronized row.opt("owner_user_id") == owner &&
                row.opt("gateway_binding_id") == bindingId && row.optInt("gateway_binding_version", -1) == bindingVersion &&
                row.opt("raw_body") is String && ReceiptAckPolicy.sha256(row.getString("raw_body")) == bodyHash
        }
        val journalFile = java.io.File(context.noBackupFilesDir, "collect_sms_capture_journal.db")
        if (!journalFile.isFile) return@synchronized false
        SmsCaptureJournal(context).use { it.acknowledgedHash(captureId) == bodyHash }
    }

''' + marker)
    return text


def _adapt_receipt_ack_policy(text: str) -> str:
    text = replace_once(text, '''            digest.matches(Regex("^[a-f0-9]{64}$")) &&''', '''            digest.matches(Regex("^[a-f0-9]{64}$")) &&
                (acknowledged[id] == null || acknowledged[id] == digest) &&''')
    return text


def _adapt_momo_gateway_store(text: str) -> str:
    text = replace_once(text, '    fun active(): Boolean = read()?.let {\n        it.has("binding") && it.optString("gateway_token").isNotEmpty() &&\n            it.optBoolean("capture_enabled") && it.optString("reason") !in setOf("authorization_required", "permission_required")\n    } == true',
        '    fun active(): Boolean = BuriCapturePolicy.uploadsAdmitted(context)')
    text = replace_once(text, 'internal fun gatewayUploadEligible(row: JSONObject, binding: JSONObject, cases: JSONObject?): Boolean {',
        'internal fun gatewayUploadEligible(row: JSONObject, binding: JSONObject, cases: JSONObject?, runtimeAdmission: Boolean = false): Boolean {')
    text = replace_once(text, '        row.opt("complete") == true, sender, body)',
        '        row.opt("complete") == true, sender, body, runtimeAdmission, BuriCapturePolicy.sourceAllowed(binding, sender, body))')
    marker = '    fun binding(): JSONObject? = read()?.optJSONObject("binding")'
    text = replace_once(text, marker, '''    /** Serialize local binding changes with capture/ack custody, never network I/O. */
    internal fun existingInstallationId(): String? = synchronized(lock) { identityPrefs.getString("installation_id", null) }
    internal fun <T> withReceiverState(action: (JSONObject) -> T): T? = synchronized(lock) { read()?.let(action) }
    internal fun <T> withObservationState(action: (JSONObject?) -> T): T = synchronized(lock) { action(read()) }
    internal fun <T> withCurrentBinding(expected: JSONObject, action: () -> T): T? = synchronized(lock) {
        if (!BuriCapturePolicy.uploadsAdmitted(context)) return@synchronized null
        val current = read() ?: return@synchronized null
        val binding = current.optJSONObject("binding") ?: return@synchronized null
        if (!current.optBoolean("capture_enabled") || current.optString("reason") in
            setOf("authorization_required", "permission_required") ||
            !BuriReceiverReliability.bindingMatches(expected::opt, binding::opt)) return@synchronized null
        action()
    }
    internal fun <T> withCurrentUpload(expected: JSONObject, action: () -> T): T? = synchronized(lock) {
        val current = read() ?: return@synchronized null
        if (expected.optString("gateway_token").isBlank() ||
            expected.opt("gateway_token") != current.opt("gateway_token") ||
            expected.optString("installation_id").isBlank() ||
            expected.opt("installation_id") != current.opt("installation_id")) return@synchronized null
        val binding = expected.optJSONObject("binding") ?: return@synchronized null
        withCurrentBinding(binding, action)
    }

''' + marker)
    return text


def _adapt_collect_sms_receiver(text: str) -> str:
    text = replace_once(text, '                    if (!MomoGatewayPolicy.providerSource(sender)) return@executeCapture',
        '                    if (!BuriCapturePolicy.senderAllowed(binding, sender)) return@executeCapture')
    text = replace_once(text, '''                    if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) return@executeCapture''', '''                    when (BuriCapturePolicy.route(context, binding, subscription)) {
                        BuriReceiverReliability.Route.ACCEPT -> Unit
                        BuriReceiverReliability.Route.OTHER_SIM -> return@executeCapture
                        else -> { gateway?.park("sim_or_profile_uncertain"); return@executeCapture }
                    }
                    if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) return@executeCapture''')
    text = replace_once(text, '''                    val result = queue.appendIfCapacity(
                        envelope,
                        MomoGatewayPolicy.MAX_PENDING,
                    )''', '''                    val result = if (gateway != null && binding != null) gateway.withCurrentBinding(binding) {
                        queue.appendIfCapacity(envelope, MomoGatewayPolicy.MAX_PENDING)
                    } ?: SmsQueueStore.AppendResult.DISABLED
                    else SmsQueueStore.AppendResult.DISABLED''')
    text = replace_once(text, '''                            gateway?.update { it.put("last_sms_at", capturedAt) }''', '''                            try {
                                gateway?.withCurrentBinding(binding!!) {
                                    gateway.update { it.put("last_sms_at", capturedAt) }
                                }
                            } catch (_: Exception) { /* The encrypted queue remains authoritative. */ }
                            try {
                                // The existing JobScheduler identity and wake gate coalesce work.
                                // Its network constraint waits for connectivity after an offline capture.
                                MomoGatewayJobs.signal(context.applicationContext)
                            } catch (_: Exception) { /* Periodic/startup recovery retains the queued source. */ }''')
    return text


def _adapt_momo_gateway_recovery(text: str) -> str:
    text = replace_once(text, '                if (MomoGatewayPolicy.providerSource(sender) && body.isNotEmpty()) {',
        '                if (BuriCapturePolicy.senderAllowed(binding, sender) && body.isNotEmpty()) {')
    text = replace_once(text, '            while (cursor.moveToNext()) {\n                scanned++',
        '            while (cursor.moveToNext()) {\n                if (state.withCurrentBinding(binding) { true } != true) return false\n                scanned++')
    text = replace_once(text, '''                    val received = cursor.getLong(receivedColumn)
                    val sent = if (sentColumn >= 0) cursor.getLong(sentColumn).takeIf { it > 0L } ?: received else received''', '''                    val received = cursor.getLong(receivedColumn)
                    val bindingCreated = try { Instant.parse(binding.optString("created_at")).toEpochMilli() } catch (_: Exception) { null }
                    if (bindingCreated == null) return false
                    if (!BuriReceiverReliability.inboxAfterBinding(id, baseline, received, bindingCreated)) {
                        // Earlier sources stay in the Android inbox; they do not fill this binding's queue.
                        advanced = maxOf(advanced, id)
                        continue
                    }
                    val sent = if (sentColumn >= 0) cursor.getLong(sentColumn).takeIf { it > 0L } ?: received else received''')
    text = replace_once(text, '''                    val bindingCreated = try { Instant.parse(binding.optString("created_at")).toEpochMilli() } catch (_: Exception) { null }
                    val resolved = bindingCreated != null && received >= bindingCreated &&
                        MomoGatewayPolicy.historicalSourceResolved(id, baseline, selected, subscription, multipleSims())''', '''                    val resolved = BuriReceiverReliability.inboxAfterBinding(id, baseline, received, bindingCreated) &&
                        MomoGatewayPolicy.sourceResolved(selected, subscription, multipleSims())''')
    text = replace_once(text, '''        state.update {
            val current = it.getJSONObject("binding")
            check(current.getString("id") == binding.getString("id") && current.getInt("version") == binding.getInt("version"))
            it.put("inbox_checkpoint", maxOf(it.optLong("inbox_checkpoint"), advanced))
                .put("historical_backlog_paused", false).put("catch_up_pending", scanned == MomoGatewayPolicy.MAX_SCAN_ROWS)
        }
        SmsQueueEventBus.notifyQueueChanged()''', '''        val checkpointSaved = state.withCurrentBinding(binding) {
            state.update {
                val current = it.getJSONObject("binding")
                check(BuriReceiverReliability.bindingMatches(binding::opt, current::opt))
                it.put("inbox_checkpoint", maxOf(it.optLong("inbox_checkpoint"), advanced))
                    .put("historical_backlog_paused", false).put("catch_up_pending", scanned == MomoGatewayPolicy.MAX_SCAN_ROWS)
            }
            true
        } ?: false
        if (!checkpointSaved) return false
        SmsQueueEventBus.notifyQueueChanged()''')
    old = '''                    if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) {
                        // Uncertain SIM/profile stops before checkpointing relevant evidence.
                        if (!BuriCapturePolicy.routeConfigured(binding, subscription)) {
                            state.park("sim_or_profile_uncertain")
                            return false
                        }
                        advanced = maxOf(advanced, id)
                        continue
                    }'''
    new = '''                    when (BuriCapturePolicy.route(context, binding, subscription)) {
                        BuriReceiverReliability.Route.ACCEPT -> Unit
                        BuriReceiverReliability.Route.OTHER_SIM -> {
                            // A known other-SIM source must not block later authorized rows.
                            // Do not retain its body or attribute it to this binding.
                            advanced = maxOf(advanced, id)
                            continue
                        }
                        else -> { state.park("sim_or_profile_uncertain"); return false }
                    }
                    if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) {
                        advanced = maxOf(advanced, id)
                        continue
                    }'''
    text = replace_once(text, old, new)
    text = replace_once(text, '''                    when (SmsQueueStore(context).appendIfCapacity(capture, MomoGatewayPolicy.MAX_PENDING,
                        MomoGatewayPolicy.LIVE_CAPTURE_RESERVE)) {''', '''                    val retained = state.withCurrentBinding(binding) {
                        SmsQueueStore(context).appendIfCapacity(capture, MomoGatewayPolicy.MAX_PENDING,
                            MomoGatewayPolicy.LIVE_CAPTURE_RESERVE)
                    } ?: SmsQueueStore.AppendResult.DISABLED
                    when (retained) {''')
    text = replace_once(text, '''internal fun JSONObject.optionalInt(key: String): Int? = if (has(key) && !isNull(key)) optInt(key, -1).takeIf { it >= 0 } else null''', '''internal fun JSONObject.optionalInt(key: String): Int? =
    (opt(key) as? Int)?.takeIf { it >= 0 && it != Int.MAX_VALUE }''')
    return text


def _adapt_momo_gateway_local_recovery(text: str) -> str:
    text = replace_once(text, '''        if (scheduler.getPendingJob(PERIODIC) != null) return
        val service''', '''        if (scheduler.getPendingJob(PERIODIC) == null) {
        val service''')
    text = replace_once(text, '''        // Register one initial pass; later continuation is scheduled only when
        // the bounded scanner reports more work.''', '''        }
        // A restored periodic job must not suppress the offline pass after reboot,
        // package replacement or reopening. Existing continuation jobs are preserved.''')
    return text


def _adapt_momo_gateway_jobs(text: str) -> str:
    text = replace_once(text, 'private val http: MomoGatewayHttp = MomoGatewayHttp()',
        'private val http: MomoGatewayHttp = MomoGatewayHttp(uploadAdmission = { token, body -> BuriCapturePolicy.uploadRequestAdmitted(context, token, body) })')
    if text.count('gatewayUploadEligible(row, binding, cases)') != 2:
        raise ValueError('Expected both exact receiver eligibility call sites.')
    text = text.replace('gatewayUploadEligible(row, binding, cases)',
        'gatewayUploadEligible(row, binding, cases, BuriCapturePolicy.uploadsAdmitted(context))')
    text = replace_once(text, '        if (!state.active() || stopped.get()) return false',
        '        if (stopped.get()) return false\n        BuriReceiverProfile.refresh(context, http)\n        if (!state.active()) return false')
    text = replace_once(text, '''            try {
                val result = http.request("ingest", token, body)''', '''            try {
                if (state.withCurrentUpload(snapshot) { !stopped.get() } != true) return false
                val result = http.request("ingest", token, body)''')
    start = '''                check(result.optBoolean("ok") && receipt.optInt("contract_version") == 2 && receipt.optBoolean("stored") &&
                    receipt.optString("owner_user_id") == owner && receipt.optString("client_envelope_id") == row.getString("id") &&
                    receipt.optString("raw_sms_id").isNotEmpty() && receipt.optString("body_sha256") == ReceiptAckPolicy.sha256(row.getString("raw_body")))
                if (stopped.get() || !state.active()) return false // Retry the same identity after uncertain stop.
                check(queue.acknowledgeDurable(owner, mapOf(row.getString("id") to receipt.getString("body_sha256"))))
                state.update { it.put("last_upload_at", Instant.now().toString()).put("reason", "") }'''
    end = '''                check(BuriReceiverReliability.receiptMatches(result::opt, receipt::opt,
                    owner, row.getString("id"), row.getString("raw_body")))
                val retired = state.withCurrentUpload(snapshot) {
                    if (stopped.get()) false else {
                        check(queue.acknowledgeDurable(owner, mapOf(row.getString("id") to receipt.getString("body_sha256"))))
                        state.update { it.put("last_upload_at", Instant.now().toString()).put("reason", "") }
                        true
                    }
                }
                if (retired != true) return false // Keep original evidence across changed credentials/binding.'''
    text = replace_once(text, start, end)
    start = '''                when (MomoGatewayPolicy.uploadFailure(error.status)) {
                    MomoGatewayPolicy.UploadFailure.AUTHORIZATION -> { state.park("authorization_required"); return false }
                    MomoGatewayPolicy.UploadFailure.SOURCE_CONFLICT -> state.parkSource(row.getString("id"), error.status, "capture_conflict")
                    MomoGatewayPolicy.UploadFailure.SOURCE_REJECTED -> state.parkSource(row.getString("id"), error.status, "source_rejected")
                    MomoGatewayPolicy.UploadFailure.RETRY -> { state.park("connection_waiting"); return true }
                }'''
    end = '''                val disposition = MomoGatewayPolicy.uploadFailure(error.status)
                val handled = state.withCurrentUpload(snapshot) {
                    when (disposition) {
                        MomoGatewayPolicy.UploadFailure.AUTHORIZATION -> state.park("authorization_required")
                        MomoGatewayPolicy.UploadFailure.SOURCE_CONFLICT -> state.parkSource(row.getString("id"), error.status, "capture_conflict")
                        MomoGatewayPolicy.UploadFailure.SOURCE_REJECTED -> state.parkSource(row.getString("id"), error.status, "source_rejected")
                        MomoGatewayPolicy.UploadFailure.RETRY -> state.park("connection_waiting")
                    }
                    true
                }
                if (handled != true || disposition == MomoGatewayPolicy.UploadFailure.AUTHORIZATION) return false
                if (disposition == MomoGatewayPolicy.UploadFailure.RETRY) return true'''
    text = replace_once(text, start, end)
    text = replace_once(text, '''        if (!stopped.get()) {
            val (pendingCount, oldest)''', '''        if (!stopped.get() && state.withCurrentUpload(snapshot) { true } == true) {
            val (pendingCount, oldest)''')
    text = replace_once(text, '''                state.update { it.put("last_contact_at", Instant.now().toString()) }''', '''                state.withCurrentUpload(snapshot) {
                    state.update { it.put("last_contact_at", Instant.now().toString()) }
                }''')
    text = replace_once(text, '''                if (error.status in setOf(401, 403)) state.park("authorization_required")''', '''                if (error.status in setOf(401, 403)) state.withCurrentUpload(snapshot) { state.park("authorization_required") }''')
    text = replace_once(text, '''setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_USER_UNLOCKED)''', '''setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_USER_UNLOCKED, Intent.ACTION_MY_PACKAGE_REPLACED)''')
    return text


def _adapt_momo_gateway_http(text: str) -> str:
    text = replace_once(text, 'setOf("pair", "ingest", "status", "heartbeat")',
        'setOf("pair", "ingest", "status", "heartbeat", "profile")')
    text = replace_once(text, '    URL(it).openConnection() as HttpURLConnection\n}) {',
        '    URL(it).openConnection() as HttpURLConnection\n}, private val uploadAdmission: (String?, JSONObject?) -> Boolean = { _, _ -> false }) {')
    text = replace_once(text, 'MomoGatewayPolicy.gatewayUploadsAdmitted())',
        'MomoGatewayPolicy.gatewayUploadsAdmitted(uploadAdmission(token, body)))')
    return text


_SOURCE_ADAPTATIONS = {
    'MomoGatewayPolicy.kt': _adapt_momo_gateway_policy,
    'SmsQueueStore.kt': _adapt_sms_queue_store,
    'ReceiptAckPolicy.kt': _adapt_receipt_ack_policy,
    'MomoGatewayStore.kt': _adapt_momo_gateway_store,
    'CollectSmsReceiver.kt': _adapt_collect_sms_receiver,
    'MomoGatewayRecovery.kt': _adapt_momo_gateway_recovery,
    'MomoGatewayLocalRecovery.kt': _adapt_momo_gateway_local_recovery,
    'MomoGatewayJobs.kt': _adapt_momo_gateway_jobs,
    'MomoGatewayHttp.kt': _adapt_momo_gateway_http,
}


def reliability_adapt(name: str, text: str) -> str:
    adapt = _SOURCE_ADAPTATIONS.get(name)
    return adapt(text) if adapt is not None else text
