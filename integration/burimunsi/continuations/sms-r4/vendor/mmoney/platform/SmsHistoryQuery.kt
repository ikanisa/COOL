package com.ikanisa.mmoney.platform

/** Parameterized date/id keyset semantics; history is never mapped through the current SIM. */
internal data class SmsHistoryQuery(
    val startInclusive: Long, val endExclusive: Long, val lastDate: Long, val lastProviderId: Long,
) {
    val selection = "LOWER(TRIM(address)) = ? AND date >= ? AND date < ? AND (date > ? OR (date = ? AND _id > ?))"
    val arguments get() = arrayOf("m-money", startInclusive.toString(), endExclusive.toString(),
        lastDate.toString(), lastDate.toString(), lastProviderId.toString())

    fun accepts(date: Long, rowId: Long): Boolean = rowId >= 0 && date >= 0 &&
        date >= startInclusive && date < endExclusive && (date > lastDate || date == lastDate && rowId > lastProviderId)

    companion object {
        fun nonNegativeLong(literal: String?): Long? = literal?.takeIf { it.matches(Regex("[0-9]{1,19}")) }
            ?.toLongOrNull()?.takeIf { it >= 0 }
    }
}
