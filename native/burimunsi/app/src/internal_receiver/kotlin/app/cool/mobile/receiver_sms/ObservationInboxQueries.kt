package app.cool.mobile.receiver_sms

import android.content.Context
import android.net.Uri

internal enum class ObservationInboxOrder(val sort: String) {
    ROW_ID("_id ASC"),
    NEWEST("date DESC, _id DESC"),
}

private val inboxUri = Uri.parse("content://sms/inbox")
private val messageColumns = arrayOf("_id", "address", "body", "date")
private val projections = listOf(
    messageColumns + arrayOf("date_sent", "sub_id"),
    messageColumns + "date_sent",
    messageColumns + "sub_id",
    messageColumns,
)

/** Some inbox providers reject sender filtering, optional columns, or both. */
internal fun queryObservationInbox(
    app: Context,
    after: Long,
    configuredSenders: Iterable<String> = emptyList(),
    through: Long? = null,
    order: ObservationInboxOrder = ObservationInboxOrder.ROW_ID,
) = with(app.contentResolver) {
    val bounds = if (through == null) "_id > ?" else "_id > ? AND _id <= ?"
    val args = listOfNotNull(after.toString(), through?.toString()).toTypedArray()
    val senders = configuredSenders.sorted()
    val canFilter = senders.isNotEmpty() && senders.size <= 30 &&
        senders.all { sender -> sender.isNotEmpty() && sender.all { it in ' '..'~' } }
    val plain = bounds to args
    val plans = if (canFilter) {
        val placeholders = senders.joinToString(",") { "?" }
        val filter = "address COLLATE NOCASE IN ($placeholders) OR address GLOB '*[^ -~]*'"
        listOf(("$bounds AND ($filter)" to (args + senders)), plain)
    } else listOf(plain)

    plans.firstNotNullOfOrNull { (selection, selectionArgs) ->
        projections.firstNotNullOfOrNull { columns ->
            try {
                query(inboxUri, columns, selection, selectionArgs, order.sort)
            } catch (_: Exception) {
                null
            }
        }
    }
}
