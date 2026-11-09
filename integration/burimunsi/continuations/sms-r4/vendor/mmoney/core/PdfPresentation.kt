package com.ikanisa.mmoney.core

/** Presentation only: spreadsheet schemas and exact original-message strings stay unchanged. */
enum class PdfBlockKind { TITLE, SECTION, FIELD, LABEL, ORIGINAL, NOTE, SPACE }
data class PdfBlock(val kind: PdfBlockKind, val text: String, val label: String? = null) {
    val displayText: String get() = label?.let { "$it: $text" } ?: text
}
private val pdfLabels = mapOf(
    "sender" to "Sender", "sms_received" to "SMS received", "transaction_time" to "Transaction time",
    "source" to "Source", "original_sms" to "Original SMS", "event_time" to "Transaction time",
    "timezone" to "Timezone", "description" to "Description", "transaction_type" to "Transaction type",
    "counterparty_name" to "Counterparty", "counterparty_number" to "Counterparty number",
    "counterparty_last3" to "Counterparty number (last 3 digits)", "payee_number_or_code" to "Payee number or code",
    "stated_amount_rwf" to "Stated amount (RWF)", "money_in_rwf" to "Money in (RWF)",
    "money_out_rwf" to "Money out (RWF)", "net_movement_rwf" to "Net movement (RWF)",
    "fee_rwf" to "Stated fee (RWF)", "total_debit_rwf" to "Total debit (RWF)",
    "reported_balance_rwf" to "Reported balance (RWF)", "transaction_id" to "Transaction ID"
)
fun pdfFieldLabel(key: String): String = requireNotNull(pdfLabels[key]) { "PDF_UNKNOWN_FIELD" }
private val spreadsheetOnly = setOf("M-Money", "Identifiers", "CSV safety")
private val financialOnly = setOf("Money in RWF", "Money out RWF", "Net movement RWF", "Stated fees RWF", "Movement basis", "Balance basis")

/** Retain all applicable scope. Missing dates mean open bounds, never an invented event date. */
@JvmOverloads
fun pdfScope(table: ExportTable, checkActive: () -> Unit = {}): List<PdfBlock> {
    checkActive()
    val fields = linkedMapOf<String, Any?>()
    for (row in table.scope) {
        checkActive(); require(row.size == 2 && row[0] is String) { "PDF_INVALID_SCOPE" }
        val key = row[0] as String
        require(!fields.containsKey(key)) { "PDF_DUPLICATE_SCOPE" }; fields[key] = row[1]
    }
    val startKey = "Period start (inclusive)"; val endKey = "Period end (inclusive)"
    val output = ArrayList<PdfBlock>()
    for ((key, value) in fields) {
        checkActive()
        if (key in spreadsheetOnly || (table.title == "SMSs" && key in financialOnly)) continue
        if (key == startKey || key == endKey) {
            if (key == endKey && fields.containsKey(startKey)) continue
            val start = fields[startKey]?.toString(); val end = fields[endKey]?.toString()
            val period = when {
                start == null && end == null -> "All dates"
                start == null -> "Through $end (inclusive)"
                end == null -> "From $start (inclusive)"
                else -> "$start to $end (inclusive)"
            }
            output += PdfBlock(PdfBlockKind.FIELD, period, "Period")
        } else {
            val shown = when {
                key == "Direction" && value == null -> "All directions"
                key == "Search" && value == "" -> "No text filter"
                else -> value?.toString().orEmpty()
            }
            output += PdfBlock(PdfBlockKind.FIELD, shown, key)
        }
    }
    output += PdfBlock(PdfBlockKind.NOTE, "Blank fields mean not recorded; zero is shown as 0. Identifiers are reproduced as text.")
    if (table.title == "SMSs") output += PdfBlock(PdfBlockKind.NOTE, "Original message text follows its saved metadata. PDF line wrapping is presentation only; use XLSX when exact original text is required.")
    checkActive(); return output
}

/** Lazy: one formatted record at a time. Original strings are never trimmed or prefixed. */
@JvmOverloads
fun pdfBlocks(table: ExportTable, checkActive: () -> Unit = {}): Sequence<PdfBlock> = sequence {
    checkActive(); require(table.title in setOf("SMSs", "Transactions", "Cashbook")) { "PDF_UNKNOWN_TABLE" }
    yield(PdfBlock(PdfBlockKind.TITLE, "M-Money · ${table.title}"))
    for (block in pdfScope(table, checkActive)) { checkActive(); yield(block) }
    yield(PdfBlock(PdfBlockKind.SPACE, ""))
    val headers = table.rows.firstOrNull().orEmpty().map {
        checkActive(); require(it is String) { "PDF_INVALID_HEADER" }; pdfFieldLabel(it); it
    }
    require(headers.isNotEmpty() && headers.distinct().size == headers.size) { "PDF_INVALID_HEADER" }
    val noun = when (table.title) { "SMSs" -> "Message"; "Cashbook" -> "Cashbook entry"; else -> "Transaction" }
    if (table.rows.size == 1) yield(PdfBlock(PdfBlockKind.NOTE, "No records in this export scope."))
    for (index in 1 until table.rows.size) {
        checkActive(); val row = table.rows[index]; require(row.size == headers.size) { "PDF_ROW_WIDTH" }
        yield(PdfBlock(PdfBlockKind.SECTION, "$noun $index"))
        for (column in headers.indices) {
            checkActive(); val key = headers[column]; val value = row[column]?.toString().orEmpty()
            if (key == "original_sms") {
                yield(PdfBlock(PdfBlockKind.LABEL, pdfFieldLabel(key))); checkActive()
                yield(PdfBlock(PdfBlockKind.ORIGINAL, value))
            } else yield(PdfBlock(PdfBlockKind.FIELD, value, pdfFieldLabel(key)))
        }
        yield(PdfBlock(PdfBlockKind.SPACE, ""))
    }
    checkActive()
}
