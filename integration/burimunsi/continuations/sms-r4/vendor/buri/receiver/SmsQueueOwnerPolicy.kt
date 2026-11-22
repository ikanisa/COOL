package app.cool.mobile.receiver_sms

/** Pure owner check shared by native bridge and queue storage. */
object SmsQueueOwnerPolicy {
    fun canDisable(activeOwner: String, requestedOwner: String): Boolean =
        requestedOwner.isNotBlank() &&
            (activeOwner.isBlank() || activeOwner == requestedOwner)

    fun canRead(enabled: Boolean, activeOwner: String, requestedOwner: String,
                storedOwners: List<String> = emptyList()): Boolean =
        enabled && activeOwner.isNotBlank() && requestedOwner == activeOwner &&
            storedOwners.all { it == activeOwner }
}
