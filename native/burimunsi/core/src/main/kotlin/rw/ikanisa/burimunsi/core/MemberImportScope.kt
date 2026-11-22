package rw.ikanisa.burimunsi.core

/** In-memory ownership for one enrollment flow. It contains no bearer or document data. */
data class MemberImportScope(
    val flowId: String,
    val operatorId: String,
    val collectionId: String,
    val sessionRevision: Long,
) {
    override fun toString() = "MemberImportScope(redacted)"

    companion object {
        const val OCR_DISCLOSURE_VERSION = "burimunsi-ocr-disclosure-v1"
    }
}
