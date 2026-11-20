package com.ikanisa.mmoney.core

import java.io.OutputStream
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

data class ExportTable(val title: String, val rows: List<List<Any?>>, val scope: List<List<Any?>>)

private fun unpairedSurrogate(text: String, index: Int): Boolean =
    (text[index].isHighSurrogate() && (index + 1 >= text.length || !text[index + 1].isLowSurrogate())) ||
        (text[index].isLowSurrogate() && (index == 0 || !text[index - 1].isHighSurrogate()))

private val exportTimeFormat = DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss", Locale.ROOT)
private fun exportTime(epoch: Long?): String? = epoch?.let { Instant.ofEpochMilli(it).atZone(KIGALI).format(exportTimeFormat) }

/** Retain only the captured record references; format one row when a writer requests it. */
private fun <T> exportRows(records: List<T>, header: List<Any?>, checkActive: () -> Unit, row: (T) -> List<Any?>): List<List<Any?>> {
    require(records.size < Int.MAX_VALUE) { "EXPORT_ROW_LIMIT" }
    return object : AbstractList<List<Any?>>() {
        override val size = records.size + 1
        override fun get(index: Int): List<Any?> {
            checkActive()
            if (index !in 0 until size) throw IndexOutOfBoundsException("Export row $index")
            return if (index == 0) header else row(records[index - 1])
        }
    }
}

@JvmOverloads
fun exportTable(snapshot: ExportSnapshot, checkActive: () -> Unit = {}): ExportTable {
    checkActive()
    // Copy labels and relevant record references before deferring row formatting. Caller-owned
    // mutable collections must not change the immutable financial/SMS scope while it is written.
    val labels = snapshot.sourceLabels.entries.associate { checkActive(); it.key to it.value }
    fun source(id: String): String? = labels[id] ?: snapshot.sourceLabel?.takeIf { snapshot.query.sourceId == id }
    val ordering = compareBy<Transaction> { it.eventAt ?: Long.MAX_VALUE }.thenBy { it.id }
    val records = if (snapshot.includeSms) emptyList() else checkedCopy(snapshot.transactions, checkActive).apply {
        // This list is privately owned, so sorting it does not require a second reference copy.
        sortWith { first, second -> checkActive(); ordering.compare(first, second) }
    }
    val originals = if (snapshot.includeSms) checkedCopy(snapshot.messages, checkActive) else emptyList()
    val rows: List<List<Any?>> = if (snapshot.includeSms) {
        exportRows(originals, listOf("sender", "sms_received", "transaction_time", "source", "original_sms"), checkActive) { m ->
            listOf(m.sender, exportTime(m.receivedAt), exportTime(m.eventAt), source(m.sourceId), m.body)
        }
    } else if (snapshot.kind == ExportKind.CASHBOOK) {
        exportRows(records, listOf("event_time", "timezone", "source", "description", "stated_amount_rwf", "money_in_rwf", "money_out_rwf", "net_movement_rwf", "fee_rwf", "total_debit_rwf", "reported_balance_rwf", "transaction_id", "counterparty_number", "counterparty_last3", "payee_number_or_code"), checkActive) { t ->
            val moneyIn = if (t.direction == Direction.RECEIVED) t.amount else 0L
            val moneyOut = if (t.direction == Direction.PAYMENT) t.totalDebit ?: t.amount else 0L
            listOf(exportTime(t.eventAt), "Africa/Kigali", source(t.sourceId), listOf(if (t.direction == Direction.RECEIVED) "Received" else "Payment", t.counterparty).filterNotNull().joinToString(" · "), t.amount, moneyIn, moneyOut, Math.subtractExact(moneyIn, moneyOut), t.fee, t.totalDebit, t.balance, t.reference, t.counterpartyNumber, t.phoneLast3, t.payeeCode)
        }
    } else {
        exportRows(records, listOf("event_time", "timezone", "source", "transaction_type", "counterparty_name", "counterparty_number", "counterparty_last3", "payee_number_or_code", "stated_amount_rwf", "money_in_rwf", "money_out_rwf", "fee_rwf", "total_debit_rwf", "reported_balance_rwf", "transaction_id"), checkActive) { t ->
            listOf(exportTime(t.eventAt), "Africa/Kigali", source(t.sourceId), if (t.direction == Direction.RECEIVED) "Received" else "Payment", t.counterparty, t.counterpartyNumber, t.phoneLast3, t.payeeCode, t.amount, if (t.direction == Direction.RECEIVED) t.amount else 0L, if (t.direction == Direction.PAYMENT) t.totalDebit ?: t.amount else 0L, t.fee, t.totalDebit, t.balance, t.reference)
        }
    }
    val sums = if (snapshot.includeSms) null else totals(records, checkActive)
    val scope = listOf(
        listOf("M-Money", if (snapshot.includeSms) "SMSs" else snapshot.kind.name.lowercase().replaceFirstChar { it.uppercase() }),
        listOf("Generated at", Instant.ofEpochMilli(snapshot.createdAt).toString()),
        listOf("Source", snapshot.sourceLabel),
        listOf("Period start (inclusive)", snapshot.query.from?.toString()),
        listOf("Period end (inclusive)", snapshot.query.through?.toString()),
        listOf("Date basis", when {
            snapshot.includeSms -> "All saved SMS receipt dates; undated originals included"
            snapshot.query.from == null && snapshot.query.through == null -> "All transaction event dates; undated transactions included"
            else -> "Transaction event time; undated transactions excluded"
        }),
        listOf("Undated rows", if (snapshot.includeSms) originals.count { checkActive(); it.receivedAt == null } else records.count { checkActive(); it.eventAt == null }),
        listOf("Timezone", "Africa/Kigali (UTC+02:00)"),
        listOf("Direction", snapshot.query.direction?.name),
        listOf("Search", snapshot.query.search),
        listOf("Exported rows", rows.size - 1),
        listOf("Known gaps", snapshot.gaps.joinToString("; ") { checkActive(); "${Instant.ofEpochMilli(it.startInclusive)}/${Instant.ofEpochMilli(it.endExclusive)} ${it.reason}" }),
        listOf("Coverage", "Available saved SMS only; complete operator history is not asserted."),
        listOf("Original SMS included", if (snapshot.includeSms) "Yes" else "No"),
        listOf("Money in RWF", sums?.moneyIn),
        listOf("Money out RWF", sums?.moneyOut),
        listOf("Net movement RWF", sums?.net),
        listOf("Stated fees RWF", sums?.statedFees),
        listOf("Movement basis", "Explicit total debit when established; otherwise stated amount. Generic fees are not added again."),
        listOf("Identifiers", "Import identifiers as text. Leading zeros are preserved in Excel."),
        listOf("CSV safety", "Potential spreadsheet formulas in text receive a leading apostrophe; XLSX stores original text without this protection prefix."),
        listOf("Balance basis", "Reported observations only; no opening or continuous running balance is inferred."),
    )
    checkActive()
    return ExportTable(if (snapshot.includeSms) "SMSs" else if (snapshot.kind == ExportKind.CASHBOOK) "Cashbook" else "Transactions", rows, scope)
}

fun csvCell(value: Any?): String {
    if (value is Number) return value.toString()
    val text = value?.toString().orEmpty()
    // UTF-8 cannot represent an isolated UTF-16 surrogate. Reject rather than silently write '?'.
    require(text.indices.none { unpairedSurrogate(text, it) }) { "CSV_INVALID_UNICODE_USE_EXCEL" }
    val first = text.dropWhile { it.isWhitespace() || it == '\uFEFF' }.firstOrNull()
    val safe = if (first in listOf('=', '+', '-', '@') || text.startsWith('\t') || text.startsWith('\r')) "'$text" else text
    return "\"${safe.replace("\"", "\"\"")}\""
}

fun writeCsv(table: ExportTable, output: OutputStream) {
    // Scope follows the single header/data table, separated by a blank record for machine import.
    val writer = output.bufferedWriter(Charsets.UTF_8)
    writer.write("\uFEFF")
    for (row in table.rows) { writer.write(row.joinToString(",", transform = ::csvCell)); writer.write("\r\n") }
    writer.write("\r\n")
    for (row in table.scope) { writer.write(row.joinToString(",", transform = ::csvCell)); writer.write("\r\n") }
    writer.flush()
}

private fun xml(value: Any?): String {
    val input = value?.toString().orEmpty().replace(Regex("_x[0-9a-fA-F]{4}_")) { "_x005F_${it.value.drop(1)}" }
    return buildString {
        input.forEachIndexed { index, c ->
            when (c) {
                '&' -> append("&amp;"); '<' -> append("&lt;"); '>' -> append("&gt;"); '"' -> append("&quot;")
                '\r' -> append("&#13;")
                else -> if ((c.code < 32 && c != '\n' && c != '\t') || c == '\uFFFE' || c == '\uFFFF' || unpairedSurrogate(input, index)) append("_x%04X_".format(c.code)) else append(c)
            }
        }
    }
}

private fun column(number: Int): String {
    var n = number + 1; var name = ""
    while (n > 0) { name = ('A'.code + (n - 1) % 26).toChar() + name; n = (n - 1) / 26 }
    return name
}

fun writeXlsx(table: ExportTable, output: OutputStream) {
    require(table.rows.size <= 1_048_576) { "EXCEL_ROW_LIMIT" }
    ZipOutputStream(output).use { zip ->
        fun entry(name: String, text: String) {
            zip.putNextEntry(ZipEntry(name).apply { time = 0L }); zip.write(text.toByteArray(Charsets.UTF_8)); zip.closeEntry()
        }
        val contentTypes = """<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>"""
        entry("[Content_Types].xml", contentTypes)
        entry("_rels/.rels", """<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>""")
        entry("xl/workbook.xml", """<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${table.title}" sheetId="1" r:id="rId1"/><sheet name="Scope" sheetId="2" r:id="rId2"/></sheets></workbook>""")
        entry("xl/_rels/workbook.xml.rels", """<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>""")
        entry("xl/styles.xml", """<?xml version="1.0"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf fontId="0" fillId="0" borderId="0" xfId="0"/><xf fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>""")
        fun sheet(name: String, rows: List<List<Any?>>) {
            zip.putNextEntry(ZipEntry(name).apply { time = 0L })
            val writer = zip.bufferedWriter(Charsets.UTF_8)
            writer.write("""<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="20" width="24" customWidth="1"/></cols><sheetData>""")
            rows.forEachIndexed { rowIndex, row ->
                writer.write("<row r=\"${rowIndex + 1}\">")
                row.forEachIndexed { colIndex, value ->
                    require((value?.toString()?.length ?: 0) <= 32767) { "EXCEL_CELL_LIMIT" }
                    val ref = column(colIndex) + (rowIndex + 1)
                    val style = if (rowIndex == 0) " s=\"1\"" else ""
                    val numeric = value is Number && value.toString().removePrefix("-").length <= 15
                    when {
                        value == null -> writer.write("<c r=\"$ref\"$style/>")
                        numeric -> writer.write("<c r=\"$ref\"$style><v>$value</v></c>")
                        else -> writer.write("<c r=\"$ref\" t=\"inlineStr\"$style><is><t xml:space=\"preserve\">${xml(value)}</t></is></c>")
                    }
                }
                writer.write("</row>")
            }
            writer.write("</sheetData></worksheet>"); writer.flush(); zip.closeEntry()
        }
        sheet("xl/worksheets/sheet1.xml", table.rows); sheet("xl/worksheets/sheet2.xml", table.scope)
    }
}
