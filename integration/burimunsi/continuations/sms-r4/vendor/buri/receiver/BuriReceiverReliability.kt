package app.cool.mobile.receiver_sms

/** Android-independent decisions wired into actual capture and acknowledgement boundaries. */
internal object BuriReceiverReliability {
    enum class Route { ACCEPT, OTHER_SIM, HOLD_SIM, HOLD_PROFILE }
    fun route(bound: Int?, observed: Int?, active: Set<Int>?, profileReady: Boolean): Route {
        if (!profileReady) return Route.HOLD_PROFILE
        if (bound == null || bound < 0 || bound == Int.MAX_VALUE || active == null || bound !in active)
            return Route.HOLD_SIM
        if (observed == null || observed < 0 || observed == Int.MAX_VALUE || observed !in active) return Route.HOLD_SIM
        return if (bound == observed) Route.ACCEPT else Route.OTHER_SIM
    }
    fun bindingMatches(expected: (String) -> Any?, current: (String) -> Any?): Boolean {
        val strings = listOf("id", "owner_user_id", "collection_id", "receiving_account_id")
        if (strings.any { (expected(it) as? String).isNullOrBlank() || expected(it) != current(it) }) return false
        val version = expected("version") as? Int ?: return false
        val subscription = expected("subscription_id") as? Int ?: return false
        return version > 0 && subscription >= 0 && subscription != Int.MAX_VALUE &&
            version == current("version") && subscription == current("subscription_id")
    }
    /** Collect v2 receipt: no string-to-Boolean or number-to-Int coercion. */
    fun receiptMatches(result: (String) -> Any?, receipt: (String) -> Any?,
                       owner: String, id: String, body: String): Boolean =
        owner.isNotBlank() && id.isNotBlank() && body.isNotBlank() &&
        result("ok") == true && receipt("contract_version") == 2 && receipt("stored") == true &&
        receipt("owner_user_id") == owner && receipt("client_envelope_id") == id &&
        !(receipt("raw_sms_id") as? String).isNullOrBlank() &&
        receipt("body_sha256") == ReceiptAckPolicy.sha256(body)

    fun canReplace(pending: Int, hasUnreadableEvidence: Boolean): Boolean =
        pending == 0 && !hasUnreadableEvidence
}
