package collect.logprobe

import android.util.Log
import com.incrediblezayed.file_saver.FileSaverPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val PRIVATE_MARKER = "synthetic-private-group-phone-token-receipt"

private class Result : MethodChannel.Result {
    var notImplemented = false
    var success: Any? = null
    override fun success(result: Any?) { success = result }
    override fun error(code: String, message: String?, details: Any?) {
        error("Unexpected channel failure: $code")
    }
    override fun notImplemented() { notImplemented = true }
}

private class FailingArguments : HashMap<String, Any?>() {
    override fun get(key: String): Any? {
        throw IllegalArgumentException(PRIVATE_MARKER)
    }
}

fun main() {
    val failures = mutableListOf<String>()
    fun probe(name: String, body: () -> Unit) {
        Log.messages.clear()
        try { body() } catch (error: AssertionError) { failures.add(name) }
    }
    probe("unrecognized method does not enter routine logs") {
        val result = Result()
        FileSaverPlugin().onMethodCall(MethodCall(PRIVATE_MARKER, null), result)
        assert(result.notImplemented)
        assert(Log.messages.isNotEmpty())
        assert(Log.messages.none { it.contains(PRIVATE_MARKER) })
    }
    probe("argument exception does not enter routine logs") {
        FileSaverPlugin().onMethodCall(MethodCall("saveFile", FailingArguments()), Result())
        assert(Log.messages.isNotEmpty())
        assert(Log.messages.none { it.contains(PRIVATE_MARKER) })
    }
    probe("missing activity retains prior caller result") {
        val result = Result()
        FileSaverPlugin().onMethodCall(MethodCall("saveFile", emptyMap<String, Any?>()), result)
        assert((result.success as String).startsWith("Error While Saving File"))
        assert(Log.messages.isNotEmpty())
        assert(Log.messages.none { it.contains(PRIVATE_MARKER) })
    }
    failures.forEach { println("FAIL: $it") }
    check(failures.isEmpty()) { "${failures.size} native log capture cases failed" }
    println("PASS: 3 actual production plugin JVM log/caller cases")
}
