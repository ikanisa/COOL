package rw.ikanisa.sms.policy

enum class ReceiptOutcome { RETAINED, REJECTED }
data class VerifiedReceipt internal constructor(val captureId: String,val outcome: ReceiptOutcome,
                                                val canonicalId: String?,val bodySha256: String?,val rejectionCode: String?)
sealed class AckDecision {
    class Valid internal constructor(receipts: List<VerifiedReceipt>): AckDecision() { val receipts = frozen(receipts) }
    data class Invalid(val reason: String): AckDecision()
}
object AckPolicy {
    fun uuid(s: String) = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(s)
    private fun id(v: Any?) = (v as? String)?.takeIf(::uuid)
    private fun version(v: Any?,n: Int) = v is Int && v == n
    private fun bad(reason: String) = AckDecision.Invalid(reason)
    /** Collect v2 acknowledges storage of raw SMS, never a payment posting. */
    fun collectV2(raw: Map<String,Any?>,original: Original): AckDecision {
        if (original.scope.contract != Contract.BURI_COLLECT_V2 || !original.valid() || original.bodySha256 == null) return bad("WRONG_CONTRACT_OR_ORIGINAL")
        if (raw["ok"] !is Boolean || raw["ok"] != true) return bad("OK_REQUIRED")
        val row = raw["receipt"] as? Map<*,*> ?: return bad("RECEIPT_REQUIRED")
        if (!version(row["contract_version"],2)) return bad("CONTRACT_VERSION")
        if (row["stored"] !is Boolean || row["stored"] != true) return bad("STORED_REQUIRED")
        if (row["owner_user_id"] != original.scope.ownerId || row["client_envelope_id"] != original.captureId) return bad("ACK_IDENTITY")
        val canonical = (row["raw_sms_id"] as? String)?.takeIf(EvidenceHash::identity) ?: return bad("RAW_SMS_ID")
        if (row["body_sha256"] !is String || row["body_sha256"] != original.bodySha256) return bad("BODY_DIGEST")
        return AckDecision.Valid(listOf(VerifiedReceipt(original.captureId,ReceiptOutcome.RETAINED,canonical,original.bodySha256,null)))
    }
    /** M-Money v1 has no echoed owner, generation or body digest: local frozen-request fencing is mandatory. */
    fun mmoneyV1(raw: Map<String,Any?>,batch: UploadBatch): AckDecision {
        if (!batch.valid() || batch.scope.contract != Contract.MMONEY_LEDGER_V1) return bad("INVALID_FROZEN_BATCH")
        if (!version(raw["schemaVersion"],1)) return bad("CONTRACT_VERSION")
        val list = raw["acknowledgements"] as? List<*> ?: return bad("ACK_LIST")
        if (list.size != batch.originals.size) return bad("ACK_COVERAGE")
        val expected = batch.originals.map { it.captureId }.toSet()
        val seen = HashSet<String>()
        val out = ArrayList<VerifiedReceipt>()
        for (item in list) {
            val row = item as? Map<*,*> ?: return bad("ACK_ROW")
            val capture = id(row["id"]) ?: return bad("ACK_ID")
            if (capture !in expected || !seen.add(capture)) return bad("ACK_COVERAGE")
            if (!row.containsKey("canonicalId")) return bad("CANONICAL_FIELD_REQUIRED")
            when (row["status"]) {
                "accepted","duplicate" -> {
                    val canonical = id(row["canonicalId"]) ?: return bad("CANONICAL_ID")
                    if (row["code"] != null) return bad("CONTRADICTORY_REJECTION_CODE")
                    out += VerifiedReceipt(capture,ReceiptOutcome.RETAINED,canonical,null,null)
                }
                "rejected" -> {
                    if (row["canonicalId"] != null) return bad("REJECTED_WITH_CANONICAL_ID")
                    val code = (row["code"] as? String)?.takeIf { Regex("[A-Z0-9_]{1,64}").matches(it) } ?: return bad("REJECTION_CODE_REQUIRED")
                    out += VerifiedReceipt(capture,ReceiptOutcome.REJECTED,null,null,code)
                }
                else -> return bad("UNKNOWN_ACK_STATUS")
            }
        }
        return AckDecision.Valid(out.sortedBy { it.captureId })
    }
    fun validate(raw: Map<String,Any?>,batch: UploadBatch): AckDecision {
        if (!batch.valid()) return bad("INVALID_BATCH")
        return when (batch.scope.contract) {
            Contract.BURI_COLLECT_V2 -> collectV2(raw,batch.originals.single())
            Contract.MMONEY_LEDGER_V1 -> mmoneyV1(raw,batch)
        }
    }
}
