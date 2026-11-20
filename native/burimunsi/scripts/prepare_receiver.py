#!/usr/bin/env python3
"""Extract pinned receiver sources with a closed, paired Buri runtime upload gate.

Use the bundled exact Collect snapshot by default, or an explicit checkout (never
mix missing checkout files with the bundle). Output is a dedicated build directory.
A lock excludes cooperating writers; source/build trees must be exclusively owned.
A crash during promotion can leave a backup/lock and fail the build closed; it does
not authorize deleting unrelated files or silently regenerating altered outputs.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile

NATIVE = Path(__file__).absolute().parents[1]
PACKAGE = NATIVE.parents[1]
MANIFEST = NATIVE / 'integration/receiver-sources.json'
BUNDLED_ROOT = PACKAGE / 'upstream/collect'
PROVENANCE = 'receiver-provenance.json'


def git_blob(raw: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()


def safe_path(path: Path) -> Path:
    """Reject links before resolving; a linked ancestor is unsafe too."""
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError(f'Symbolic links are forbidden: {part.name}')
    return path


def regular_bytes(path: Path) -> bytes:
    safe_path(path)
    if not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f'Missing regular source: {path.name}')
    if path.stat().st_size > 2_000_000:
        raise ValueError(f'Source exceeds bounded input size: {path.name}')
    return path.read_bytes()


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



def reliability_adapt(name: str, text: str) -> str:
    # Exact-match local R1 adaptations, applied only after verification of upstream pins.
    if name == 'MomoGatewayPolicy.kt':
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
    elif name == 'SmsQueueStore.kt':
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
    elif name == 'ReceiptAckPolicy.kt':
        text = replace_once(text, '''            digest.matches(Regex("^[a-f0-9]{64}$")) &&''', '''            digest.matches(Regex("^[a-f0-9]{64}$")) &&
                (acknowledged[id] == null || acknowledged[id] == digest) &&''')
    elif name == 'MomoGatewayStore.kt':
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
    elif name == 'CollectSmsReceiver.kt':
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
    elif name == 'MomoGatewayRecovery.kt':
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
    elif name == 'MomoGatewayLocalRecovery.kt':
        text = replace_once(text, '''        if (scheduler.getPendingJob(PERIODIC) != null) return
        val service''', '''        if (scheduler.getPendingJob(PERIODIC) == null) {
        val service''')
        text = replace_once(text, '''        // Register one initial pass; later continuation is scheduled only when
        // the bounded scanner reports more work.''', '''        }
        // A restored periodic job must not suppress the offline pass after reboot,
        // package replacement or reopening. Existing continuation jobs are preserved.''')
    elif name == 'MomoGatewayJobs.kt':
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
    elif name == 'MomoGatewayHttp.kt':
        text = replace_once(text, 'setOf("pair", "ingest", "status", "heartbeat")',
            'setOf("pair", "ingest", "status", "heartbeat", "profile")')
        text = replace_once(text, '    URL(it).openConnection() as HttpURLConnection\n}) {',
            '    URL(it).openConnection() as HttpURLConnection\n}, private val uploadAdmission: (String?, JSONObject?) -> Boolean = { _, _ -> false }) {')
        text = replace_once(text, 'MomoGatewayPolicy.gatewayUploadsAdmitted())',
            'MomoGatewayPolicy.gatewayUploadsAdmitted(uploadAdmission(token, body)))')
    return text


def prepare(collect_root: Path, manifest_path: Path = MANIFEST) -> tuple[dict[str, bytes], dict]:
    root = safe_path(collect_root)
    manifest = json.loads(regular_bytes(manifest_path))
    relative = PurePosixPath(manifest['root'])
    if relative.is_absolute() or '..' in relative.parts or not relative.parts:
        raise ValueError('Unsafe receiver manifest path.')
    files = manifest['files']
    if not isinstance(files, dict) or not files or len(files) > 64:
        raise ValueError('Invalid receiver source manifest.')
    prepared: dict[str, bytes] = {}
    evidence = []
    for name, expected in sorted(files.items()):
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*\.kt', name) or not re.fullmatch(r'[0-9a-f]{40}', expected):
            raise ValueError('Unsafe receiver source entry.')
        raw = regular_bytes(root / str(relative) / name)
        blob = git_blob(raw)
        if blob != expected:
            raise ValueError(f'Unreviewed source drift: {name}; expected {expected}, got {blob}')
        text = raw.decode('utf-8')
        output_name = name
        if name == 'MemberSmsJobs.kt':
            output_name = 'MemberSmsUploadPolicy.kt'
            text = queue_disposition(text)
        elif name == 'CollectSmsReceiver.kt':
            hook = 'MemberSmsJobs.ensure(context.applicationContext)'
            if text.count(hook) != 2:
                raise ValueError('Unexpected member scheduler call sites.')
            text = text.replace(hook, 'Unit /* Dedicated gateway: no member capture scheduler. */')
            hook = 'if (body.isEmpty()) return@executeCapture'
            text = replace_once(text, hook, hook + '\n                    if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) return@executeCapture')
        elif name == 'MomoGatewayRecovery.kt':
            hook = 'val bindingCreated = try { Instant.parse(binding.optString("created_at")).toEpochMilli() } catch (_: Exception) { null }'
            replacement = '''if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) {
                        // Uncertain SIM/profile stops before checkpointing relevant evidence.
                        if (!BuriCapturePolicy.routeConfigured(binding, subscription)) {
                            state.park("sim_or_profile_uncertain")
                            return false
                        }
                        advanced = maxOf(advanced, id)
                        continue
                    }
                    ''' + hook
            text = replace_once(text, hook, replacement)
        elif name == 'MomoGatewayHttp.kt':
            hook = 'if (status !in 200..299) throw ResponseFailure(status)'
            text = replace_once(text, hook, hook + '\n            check(connection.getHeaderField("Content-Type").orEmpty().substringBefore(\';\').trim().equals("application/json", ignoreCase = true)) { "Gateway returned a non-JSON response" }')
        text = reliability_adapt(name, text)
        if name == 'MomoGatewayPolicy.kt' and 'fun gatewayUploadsAdmitted(runtimeAdmission: Boolean = false): Boolean = runtimeAdmission' not in text:
            raise ValueError('Closed runtime upload admission was not installed.')
        for forbidden in ('MemberSmsJobs.', 'class MemberSmsJobService', 'class MemberSmsUploader', 'ProtectedSnapshotStore', 'access_token'):
            if forbidden in text:
                raise ValueError(f'Unexpected member-session implementation in {output_name}')
        if output_name in prepared:
            raise ValueError('Duplicate generated receiver path.')
        generated = text.encode('utf-8')
        prepared[output_name] = generated
        evidence.append({'file': output_name, 'sourceFile': name, 'sourceGitBlob': blob,
                         'sourceSha256': hashlib.sha256(raw).hexdigest(),
                         'generatedSha256': hashlib.sha256(generated).hexdigest(),
                         'changed': generated != raw})
    if 'SmsQueueStore.kt' in prepared and 'MemberSmsUploadPolicy.kt' not in prepared:
        raise ValueError('Missing queue-disposition dependency; extraction cannot compile.')
    required_admission = {
        'MomoGatewayPolicy.kt': 'gatewayUploadsAdmitted(runtimeAdmission: Boolean = false)',
        'MomoGatewayStore.kt': 'fun active(): Boolean = BuriCapturePolicy.uploadsAdmitted(context)',
        'MomoGatewayHttp.kt': 'gatewayUploadsAdmitted(uploadAdmission(token, body))',
        'MomoGatewayJobs.kt': 'uploadAdmission = { token, body -> BuriCapturePolicy.uploadRequestAdmitted(context, token, body) }',
    }
    for name, fragment in required_admission.items():
        if fragment not in prepared.get(name, b'').decode('utf-8'):
            raise ValueError('Incomplete closed receiver transport admission; no output written.')
    provenance = {'contractVersion': 2, 'sourceRepository': manifest['repository'],
                  'sourceCommit': manifest['commit'], 'uploadHoldPreserved': False, 'upstreamUploadHoldPreserved': True,
                  'runtimeUploadAdmission': 'paired_resumed_receiver_v1', 'defaultUploadAdmission': False,
                  'memberSessionImplementationIncluded': False, 'reliabilityRevision': 'sms-r1', 'files': evidence}
    prepared[PROVENANCE] = (json.dumps(provenance, indent=2) + '\n').encode()
    return prepared, provenance


def check_existing(out: Path) -> None:
    """Only replace a previously generated, intact, single-level output tree."""
    if not out.exists():
        return
    if not out.is_dir():
        raise ValueError('Output is not a generated directory.')
    children = list(out.iterdir())
    if not children:
        return
    for child in children:
        if child.is_symlink() or not child.is_file():
            raise ValueError('Unexpected output entry; preserve it and use a fresh build directory.')
    try:
        old = json.loads(regular_bytes(out / PROVENANCE))
        rows = old['files']
        if not isinstance(rows, list) or not rows or len(rows) > 64:
            raise ValueError('Invalid provenance file list.')
        names = [row['file'] for row in rows]
        if len(set(names)) != len(names) or any(not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*\.kt', name) for name in names):
            raise ValueError('Invalid provenance paths.')
        if {c.name for c in children} != set(names) | {PROVENANCE}:
            raise ValueError('Unexpected generated output file.')
        for row in rows:
            if hashlib.sha256(regular_bytes(out / row['file'])).hexdigest() != row['generatedSha256']:
                raise ValueError('Generated receiver was locally modified.')
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise ValueError('Output provenance is missing or invalid.') from error


def extract(collect_root: Path | None, output: Path, manifest_path: Path = MANIFEST) -> dict:
    root = safe_path(collect_root if collect_root is not None else BUNDLED_ROOT)
    out = safe_path(output)
    manifest = json.loads(regular_bytes(manifest_path))
    source_directory = root / manifest['root']
    if ('build' not in out.parts or out == root or out in root.parents or
            out == source_directory or out in source_directory.parents or source_directory in out.parents):
        raise ValueError('Output must be a dedicated build directory outside the receiver source directory.')
    prepared, provenance = prepare(root, manifest_path)  # validate ALL inputs before writes
    out.parent.mkdir(parents=True, exist_ok=True)
    safe_path(out.parent)
    lock = out.parent / ('.' + out.name + '.receiver.lock')
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    stage: Path | None = None
    backup: Path | None = None
    try:
        os.close(fd)
        check_existing(out)
        if out.is_dir() and {f.name for f in out.iterdir()} == set(prepared) and all((out/n).read_bytes() == body for n, body in prepared.items()):
            return {'preparedFiles': len(provenance['files']), 'changed': False, 'sourceCommit': provenance['sourceCommit']}
        stage = Path(tempfile.mkdtemp(prefix='.' + out.name + '.stage-', dir=out.parent))
        for name, body in prepared.items():
            with (stage / name).open('xb') as stream:
                stream.write(body)
                stream.flush()
                os.fsync(stream.fileno())
        safe_path(out)
        check_existing(out)
        if out.exists():
            backup = Path(tempfile.mkdtemp(prefix='.' + out.name + '.backup-', dir=out.parent))
            backup.rmdir()
            os.replace(out, backup)
        try:
            os.replace(stage, out)
            stage = None
        except BaseException:
            if backup is not None and not out.exists():
                os.replace(backup, out)
                backup = None
            raise
        if backup is not None:
            shutil.rmtree(backup)
            backup = None
        return {'preparedFiles': len(provenance['files']), 'changed': True, 'sourceCommit': provenance['sourceCommit']}
    finally:
        if stage is not None and stage.exists():
            shutil.rmtree(stage)
        # A failed restoration leaves the backup for explicit recovery, not deletion.
        lock.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect-root', type=Path, help='Explicit pinned checkout; default: bundled exact sources.')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.collect_root, args.output)
    print(json.dumps({**result, 'uploadHoldPreserved': False, 'upstreamUploadHoldPreserved': True,
                      'runtimeUploadAdmission': 'paired_resumed_receiver_v1', 'defaultUploadAdmission': False, 'upstreamModified': False,
                      'scope': 'Deterministic source extraction only; not an Android build.'}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
