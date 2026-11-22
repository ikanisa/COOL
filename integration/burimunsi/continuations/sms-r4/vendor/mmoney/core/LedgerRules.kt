package com.ikanisa.mmoney.core

import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.util.Locale

object SmsPolicy {
    fun isEligibleSender(sender: String?): Boolean = sender?.trim()?.equals("M-Money", ignoreCase = true) == true
    private val blocked = Regex("(?i)(?:\\b(?:otp|one[ -]?time|verification|verify|pin|password|passcode|security code|login|log in|promotion|promotional|offer|prize|winner|jackpot|lottery|bonus|advertisement)\\b|https?://)")
    private val money = Regex("(?i)(?:\\b(?:RWF|FRW)\\s*[0-9][0-9,.]*|[0-9][0-9,.]*\\s*(?:RWF|FRW)\\b)")
    private val movement = Regex("(?i)(?:\\byou (?:have )?(?:received|sent|paid|transferred|withdrawn|deposited)\\b|\\b(?:payment|transfer|withdrawal|deposit) (?:of|for)\\b|\\b(?:new|current|available|your) (?:MoMo )?balance\\b|\\byakiriye\\b|\\bwohereje\\b|\\bwishyuye\\b|\\bre[çc]u\\b|\\bpaiement\\b)")
    /** Narrow upload policy: exact sender is checked separately; unsure/OTP/promotional messages stay local. */
    fun mayUpload(body: String): Boolean = body.length in 1..8192 && validUnicode(body) &&
        body.toByteArray(Charsets.UTF_8).size <= 8192 && !blocked.containsMatchIn(body) &&
        money.containsMatchIn(body) && movement.containsMatchIn(body)

    // UTF-8 replaces isolated UTF-16 surrogates. Keep those exact originals local instead of
    // allowing the network encoder to turn the captured evidence into different text.
    private fun validUnicode(body: String): Boolean {
        var index = 0
        while (index < body.length) {
            val character = body[index++]
            if (character == '\u0000') return false
            if (character.isHighSurrogate()) {
                if (index == body.length || !body[index++].isLowSurrogate()) return false
            } else if (character.isLowSurrogate()) return false
        }
        return true
    }
}

fun digestBody(body: String): String = MessageDigest.getInstance("SHA-256").digest(body.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

fun parseMoney(value: String?): Long? {
    if (value == null || !Regex("(?:0|[1-9][0-9]*)").matches(value)) return null
    return value.toLongOrNull()?.takeIf { it in 0..MAX_RWF }
}

/** The normalized query is reused; fields are checked lazily without a per-row list. */
private fun containsSearch(value: String?, needle: String): Boolean =
    value?.lowercase(Locale.ROOT)?.contains(needle) == true

/** RWF integers use ASCII digits and comma groups, independent of device locale. */
private fun amountContains(amount: Long, needle: String): Boolean {
    val digits = amount.toString()
    if (digits.contains(needle)) return true
    val first = if (digits[0] == '-') 1 else 0
    if (digits.length - first <= 3) return false
    val grouped = buildString(digits.length + (digits.length - first - 1) / 3) {
        if (first == 1) append('-')
        for (index in first until digits.length) {
            if (index > first && (digits.length - index) % 3 == 0) append(',')
            append(digits[index])
        }
    }
    return grouped.contains(needle)
}

private val transactionOrdering = compareByDescending<Transaction> { it.eventAt ?: Long.MIN_VALUE }.thenBy { it.id }
private val messageOrdering = compareByDescending<SmsRecord> { it.receivedAt ?: Long.MIN_VALUE }.thenBy { it.id }

/** Resolve calendar bounds once. Do not assume a fixed UTC offset or a 24-hour local day. */
private class EventWindow(query: LedgerQuery) {
    private val bounded = query.from != null || query.through != null
    private val firstMillis = Instant.ofEpochMilli(Long.MIN_VALUE)
    private val lastMillis = Instant.ofEpochMilli(Long.MAX_VALUE)
    private val start = query.from?.atStartOfDay(KIGALI)?.toInstant()
    // LocalDate.MAX has no next day. It includes every representable epoch millisecond.
    private val end = query.through?.takeUnless { it == LocalDate.MAX }?.plusDays(1)?.atStartOfDay(KIGALI)?.toInstant()
    val empty = (start != null && start > lastMillis) || (end != null && end <= firstMillis)
    private val lower = start?.takeIf { it > firstMillis && it <= lastMillis }?.toEpochMilli()
    private val upper = end?.takeIf { it > firstMillis && it <= lastMillis }?.toEpochMilli()

    fun contains(eventAt: Long?): Boolean = !bounded ||
        (!empty && eventAt != null && (lower == null || eventAt >= lower) && (upper == null || eventAt < upper))
}

/** Callers may stop obsolete CPU work without coupling the domain module to a coroutine runtime. */
@JvmOverloads
fun filterTransactions(records: List<Transaction>, query: LedgerQuery, checkActive: () -> Unit = {}): List<Transaction> {
    checkActive()
    require(query.from == null || query.through == null || !query.through.isBefore(query.from))
    val needle = query.search.trim().lowercase(Locale.ROOT)
    val window = EventWindow(query)
    // Only this private result is sorted. The caller's source list and its order are never mutated.
    val result = ArrayList<Transaction>()
    if (!window.empty) for (t in records) {
        checkActive()
        if ((query.sourceId == null || t.sourceId == query.sourceId) &&
            (query.direction == null || t.direction == query.direction) && window.contains(t.eventAt) &&
            (needle.isEmpty() || containsSearch(t.counterparty, needle) ||
                containsSearch(t.counterpartyNumber, needle) || containsSearch(t.phoneLast3, needle) ||
                containsSearch(t.payeeCode, needle) || containsSearch(t.reference, needle) ||
                amountContains(t.amount, needle))) {
            result.add(t)
        }
    }
    result.sortWith { first, second -> checkActive(); transactionOrdering.compare(first, second) }
    checkActive()
    return result
}

/** SMS evidence scope deliberately ignores financial date and direction filters. */
@JvmOverloads
fun filterMessages(records: List<SmsRecord>, query: LedgerQuery, checkActive: () -> Unit = {}): List<SmsRecord> {
    checkActive()
    val needle = query.search.trim().lowercase(Locale.ROOT)
    val result = ArrayList<SmsRecord>()
    for (m in records) {
        checkActive()
        if ((query.sourceId == null || m.sourceId == query.sourceId) &&
            (needle.isEmpty() || containsSearch(m.body, needle) || containsSearch(m.sender, needle) ||
                containsSearch(m.counterparty, needle) || containsSearch(m.counterpartyNumber, needle) ||
                containsSearch(m.phoneLast3, needle) || containsSearch(m.payeeCode, needle) ||
                containsSearch(m.reference, needle))) {
            result.add(m)
        }
    }
    result.sortWith { first, second -> checkActive(); messageOrdering.compare(first, second) }
    checkActive()
    return result
}

@JvmOverloads
fun totals(records: List<Transaction>, checkActive: () -> Unit = {}): LedgerTotals {
    checkActive()
    var income = 0L; var outgoings = 0L; var fees = 0L; var hasFees = false
    records.forEach { t ->
        checkActive()
        require(t.amount in 1..MAX_RWF)
        t.fee?.let { require(it in 0..MAX_RWF); fees = Math.addExact(fees, it); hasFees = true }
        t.totalDebit?.let { require(it in t.amount..MAX_RWF) }
        if (t.direction == Direction.RECEIVED) income = Math.addExact(income, t.amount)
        else outgoings = Math.addExact(outgoings, t.totalDebit ?: t.amount)
    }
    checkActive()
    return LedgerTotals(income, outgoings, Math.subtractExact(income, outgoings), if (hasFees) fees else null, records.size)
}

/** A combined source has no wallet balance. Timestamp ties are stable and arrival does not overwrite time. */
@JvmOverloads
fun latestBalance(snapshot: LedgerSnapshot, sourceId: String?, checkActive: () -> Unit = {}): BalanceObservation? {
    checkActive()
    return sourceId?.let { source -> snapshot.balances.asSequence().onEach { checkActive() }.filter { it.sourceId == source }.maxWithOrNull(
        compareBy<BalanceObservation> { it.eventAt ?: it.receivedAt ?: Long.MIN_VALUE }
            .thenBy { it.receivedAt ?: Long.MIN_VALUE }.thenBy { it.sequence }.thenBy { it.id }
    ).also { checkActive() } }
}

/** Capture independent list containers while permitting cancellation between records. */
internal fun <T> checkedCopy(records: List<T>, checkActive: () -> Unit): MutableList<T> {
    checkActive()
    return ArrayList<T>(records.size).apply { for (record in records) { checkActive(); add(record) }; checkActive() }
}

@JvmOverloads
fun createExportSnapshot(snapshot: LedgerSnapshot, query: LedgerQuery, sms: Boolean, now: Long, checkActive: () -> Unit = {}): ExportSnapshot {
    checkActive()
    return ExportSnapshot(
    createdAt = now, query = if (sms) query.copy(from = null, through = null, direction = null) else query.copy(),
    sourceLabel = if (query.sourceId == null) "All SIMs" else snapshot.sources.find { checkActive(); it.id == query.sourceId }?.label,
    transactions = if (sms) emptyList() else filterTransactions(snapshot.transactions, query, checkActive),
    messages = if (sms) filterMessages(snapshot.messages, query, checkActive) else emptyList(),
    includeSms = sms, gaps = checkedCopy(snapshot.gaps, checkActive),
    sourceLabels = snapshot.sources.associate { checkActive(); it.id to it.label },
    ).also { checkActive() }
}

fun deriveSyncState(enabled: Boolean, consented: Boolean, permission: Boolean, online: Boolean, storageBlocked: Boolean = false, accessLost: Boolean = false, deleting: Boolean = false, retrying: Boolean = false): SyncState = when {
    deleting -> SyncState.DELETING
    storageBlocked -> SyncState.STORAGE_BLOCKED
    accessLost -> SyncState.ACCESS_LOST
    !enabled -> SyncState.PAUSED
    !consented || !permission -> SyncState.PERMISSION_REQUIRED
    !online -> SyncState.OFFLINE
    retrying -> SyncState.RETRYING
    else -> SyncState.ON
}
