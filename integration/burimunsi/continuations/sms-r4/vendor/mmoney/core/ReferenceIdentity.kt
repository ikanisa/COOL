package com.ikanisa.mmoney.core

enum class ReferenceState { ABSENT, AGREED, CONFLICTING, INVALID, TOO_LONG }
data class ReferenceIdentity(val state: ReferenceState, val value: String? = null)

/** Observe every recognized reference label in the immutable original, never a model guess.
 * Keep the same grammar as backend reference-identity.ts. Values are case-sensitive and
 * leading zeros are evidence. One sentence-ending full stop is not part of the identifier.
 */
fun observeReferenceIdentity(body: String): ReferenceIdentity {
    // ECMAScript whitespace, shared with TypeScript and SQL, includes NBSP/BOM.
    val whitespace = "\\u0009-\\u000D\\u0020\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"
    val space = "[$whitespace]"
    // Explicit ASCII casing keeps labels identical to JavaScript /gi without /u.
    // Kotlin IGNORE_CASE also accepts Unicode near-letters such as dotless i and long s.
    val id = "[Ii][Dd]"
    val reference = "[Rr][Ee][Ff][Ee][Rr][Ee][Nn][Cc][Ee]"
    val transaction = "[Tt][Rr][Aa][Nn][Ss][Aa][Cc][Tt][Ii][Oo][Nn]"
    val labels = Regex("(?<![A-Za-z0-9_])(?:[Ff][Tt]${space}*$id|$transaction${space}*(?:$id|$reference)|$reference)${space}*:${space}*([^$whitespace]*)")
    val values = linkedSetOf<String>()
    var seen = false
    for (match in labels.findAll(body)) {
        seen = true
        val token = match.groupValues[1].removeSuffix(".")
        if (!Regex("[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*").matches(token)) return ReferenceIdentity(ReferenceState.INVALID)
        if (token.length > 128) return ReferenceIdentity(ReferenceState.TOO_LONG)
        values += token
    }
    return when {
        !seen -> ReferenceIdentity(ReferenceState.ABSENT)
        values.size != 1 -> ReferenceIdentity(ReferenceState.CONFLICTING)
        else -> ReferenceIdentity(ReferenceState.AGREED, values.single())
    }
}

/** Completion is evidenced by a durable projection or terminal ingest rejection. */
fun messageOutcome(cloudEligible: Boolean, hasProjection: Boolean, posted: Boolean = false, kind: String? = null, terminalOriginalOnly: Boolean = false): MessageOutcome = when {
    !hasProjection -> if (cloudEligible && !terminalOriginalOnly) MessageOutcome.PENDING else MessageOutcome.ORIGINAL_ONLY
    posted -> MessageOutcome.RECORDED
    kind == "balance" -> MessageOutcome.BALANCE_ONLY
    else -> MessageOutcome.ORIGINAL_ONLY
}
