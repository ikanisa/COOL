package app.cool.mobile
object BuildConfig {
    const val BURI_API_ORIGIN = "https://offline.test"
    const val BURI_API_PATH_PREFIX = "/functions/v1/collect-api"
    const val COLLECT_PUBLISHABLE_KEY = ""
    val IS_GATEWAY = System.getProperty("burimunsi.test.receiver", "true").toBooleanStrict()
}
