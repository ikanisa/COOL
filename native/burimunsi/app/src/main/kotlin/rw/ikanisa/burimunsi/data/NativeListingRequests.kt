package rw.ikanisa.burimunsi.data

import java.net.URLEncoder
import rw.ikanisa.burimunsi.core.ListingQuery
import rw.ikanisa.burimunsi.core.ListingTarget
import rw.ikanisa.burimunsi.core.checkContract

internal fun query(values: Map<String, String?>): String =
    values.entries.asSequence()
        .mapNotNull { (key, value) -> value?.takeUnless(String::isBlank)?.let { key to it } }
        .joinToString("&", prefix = "?") { (key, value) ->
            URLEncoder.encode(key, "UTF-8") + "=" + URLEncoder.encode(value, "UTF-8")
        }

internal fun listingPath(
    base: String,
    target: ListingTarget,
    listing: ListingQuery,
    cursor: String?,
    extra: Map<String, String?> = emptyMap(),
    limit: Int = 100,
): String {
    checkContract(limit in 1..100, "invalid_query")
    return base + query(listing.queryValues(target) + extra + mapOf("cursor" to cursor, "limit" to limit.toString()))
}
