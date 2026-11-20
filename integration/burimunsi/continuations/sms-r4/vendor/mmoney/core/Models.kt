package com.ikanisa.mmoney.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

const val CONSENT_VERSION = 1
const val SCHEMA_VERSION = 1
const val MAX_RWF = 9_000_000_000_000L
val KIGALI: ZoneId = ZoneId.of("Africa/Kigali")

enum class Direction { RECEIVED, PAYMENT }
enum class Appearance { SYSTEM, DARK, LIGHT }
enum class SyncState { ON, PAUSED, PERMISSION_REQUIRED, OFFLINE, RETRYING, STORAGE_BLOCKED, ACCESS_LOST, DELETING }
enum class DeleteState { NONE, PENDING, COMPLETE }
enum class ExportKind { TRANSACTIONS, CASHBOOK }
/** Public result only; internal retry, duplicate and rejection reasons never become UI states. */
enum class MessageOutcome { PENDING, RECORDED, BALANCE_ONLY, ORIGINAL_ONLY }
enum class ExportFormat(val extension: String, val mime: String) {
    CSV("csv", "text/csv"), XLSX("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"), PDF("pdf", "application/pdf")
}

data class Source(val id: String, val label: String? = null, val subscriptionId: Int? = null, val slotIndex: Int? = null)

/** The first envelope and decoded body are immutable evidence. No normalization is allowed. */
data class SmsRecord(
    val id: String,
    val sourceId: String,
    val body: String,
    val sender: String?,
    val receivedAt: Long?,
    val capturedAt: Long,
    val providerRowId: String? = null,
    val cloudEligible: Boolean = false,
    val counterparty: String? = null,
    val counterpartyNumber: String? = null,
    val phoneLast3: String? = null,
    val payeeCode: String? = null,
    val amount: Long? = null,
    val balance: Long? = null,
    val fee: Long? = null,
    val totalDebit: Long? = null,
    val reference: String? = null,
    val eventAt: Long? = null,
    val recorded: Boolean = false,
    val direction: Direction? = null,
    val outcome: MessageOutcome = MessageOutcome.PENDING,
)

data class Transaction(
    val id: String,
    val originalId: String,
    val sourceId: String,
    val direction: Direction,
    val amount: Long,
    val counterparty: String? = null,
    val counterpartyNumber: String? = null,
    val phoneLast3: String? = null,
    val payeeCode: String? = null,
    val eventAt: Long? = null,
    val receivedAt: Long? = null,
    val reference: String? = null,
    val balance: Long? = null,
    val fee: Long? = null,
    val totalDebit: Long? = null,
)

data class BalanceObservation(val id: String, val sourceId: String, val originalId: String, val amount: Long, val eventAt: Long?, val receivedAt: Long?, val sequence: Long)
data class HistoryGap(val startInclusive: Long, val endExclusive: Long, val reason: String)
data class Preferences(val consentVersion: Int = 0, val syncEnabled: Boolean = false, val alerts: Boolean = false, val vibration: Boolean = false, val appearance: Appearance = Appearance.DARK, val pauseAt: Long? = null)
data class ImportStatus(val running: Boolean = false, val startInclusive: Long? = null, val endExclusive: Long? = null, val added: Int = 0, val other: Int = 0, val complete: Boolean = false)

data class LedgerSnapshot(
    val ready: Boolean = false,
    val sources: List<Source> = emptyList(),
    val messages: List<SmsRecord> = emptyList(),
    val transactions: List<Transaction> = emptyList(),
    val balances: List<BalanceObservation> = emptyList(),
    val preferences: Preferences = Preferences(),
    val syncState: SyncState = SyncState.PAUSED,
    val permissionGranted: Boolean = false,
    val online: Boolean = true,
    val importStatus: ImportStatus = ImportStatus(),
    val gaps: List<HistoryGap> = emptyList(),
    val deleteState: DeleteState = DeleteState.NONE,
    /** Only bounded diagnostic codes, never original SMS, names, phone numbers or credentials. */
    val diagnosticCode: String? = null,
)

data class LedgerQuery(
    val sourceId: String? = null,
    val from: LocalDate? = null,
    val through: LocalDate? = null,
    val direction: Direction? = null,
    val search: String = "",
)

data class LedgerTotals(val moneyIn: Long, val moneyOut: Long, val net: Long, val statedFees: Long?, val count: Int)
data class ExportSnapshot(
    val createdAt: Long,
    val query: LedgerQuery,
    val sourceLabel: String?,
    val transactions: List<Transaction>,
    val messages: List<SmsRecord>,
    val includeSms: Boolean,
    val gaps: List<HistoryGap>,
    val kind: ExportKind = ExportKind.TRANSACTIONS,
    val sourceLabels: Map<String, String?> = emptyMap(),
)

fun inclusiveDateBounds(from: LocalDate, through: LocalDate): Pair<Long, Long> {
    require(!through.isBefore(from)) { "INVALID_DATE_RANGE" }
    return from.atStartOfDay(KIGALI).toInstant().toEpochMilli() to through.plusDays(1).atStartOfDay(KIGALI).toInstant().toEpochMilli()
}

fun transactionDate(epoch: Long): LocalDate = Instant.ofEpochMilli(epoch).atZone(KIGALI).toLocalDate()
fun identifier(number: String?, suffix: String?, code: String?): String = number?.takeIf { it.isNotBlank() }
    ?: suffix?.takeIf { it.matches(Regex("[0-9]{3}")) }?.let { "...$it" }
    ?: code.orEmpty()
