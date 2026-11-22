package app.cool.mobile.receiver_sms

import java.io.File
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.StandardOpenOption
import java.util.Base64
import javax.crypto.KeyGenerator

private var tests = 0
private fun test(name: String, body: () -> Unit) { body(); println("ok ${++tests} - $name") }
private fun rejects(body: () -> Unit) {
    var failed = false
    try { body() } catch (_: Exception) { failed = true }
    check(failed) { "Expected fail-closed result" }
}
private fun sync(directory: File) { FileChannel.open(directory.toPath(), StandardOpenOption.READ).use { it.force(true) } }
private fun queue(file: File, hook: (String) -> Unit = {}) = BuriQueueFile(file, ::sync, hook)
private fun directory(test: (File) -> Unit) {
    val dir = Files.createTempDirectory("buri-sms-r1-").toFile()
    try { test(dir) } finally { dir.deleteRecursively() }
}
fun main(args: Array<String>) {
    if (args.firstOrNull() == "crash-child") {
        queue(File(args[1])) { if (it == args[2]) Runtime.getRuntime().halt(71) }.write("new-ciphertext")
        error("Crash failpoint not reached")
    }
    println("TAP version 13")
    val route = BuriReceiverReliability
    test("authorized active subscription accepted") { check(route.route(1, 1, setOf(1), true) == BuriReceiverReliability.Route.ACCEPT) }
    test("different known subscription skipped without blocking later rows") {
        check(route.route(1, 2, setOf(1,2), true) == BuriReceiverReliability.Route.OTHER_SIM)
        check(route.route(1, 1, setOf(1,2), true) == BuriReceiverReliability.Route.ACCEPT)
    }
    test("removed or disabled authorized SIM holds capture") { check(route.route(1, 1, setOf(2), true) == BuriReceiverReliability.Route.HOLD_SIM) }
    test("unknown subscription, permissions or telephony service fails closed") {
        check(route.route(1, null, setOf(1), true) == BuriReceiverReliability.Route.HOLD_SIM)
        check(route.route(1, 1, null, true) == BuriReceiverReliability.Route.HOLD_SIM)
        check(route.route(null, 1, setOf(1), true) == BuriReceiverReliability.Route.HOLD_SIM)
    }
    test("default sentinel and invalid subscription rejected") {
        for (bad in listOf(-1, Int.MAX_VALUE)) check(route.route(bad, bad, setOf(bad), true) == BuriReceiverReliability.Route.HOLD_SIM)
    }
    test("unrecognized observed subscription cannot be skipped as a known other SIM") {
        check(route.route(1, 3, setOf(1,2), true) == BuriReceiverReliability.Route.HOLD_SIM)
    }
    test("profile configuration is mandatory") { check(route.route(1, 1, setOf(1), false) == BuriReceiverReliability.Route.HOLD_PROFILE) }
    val binding = mapOf<String,Any?>("id" to "binding-A", "version" to 1, "owner_user_id" to "owner-A",
        "collection_id" to "group-A", "receiving_account_id" to "account-A", "subscription_id" to 1)
    test("binding fence accepts identical validated snapshot") { check(route.bindingMatches(binding::get, binding::get)) }
    for ((field, value) in mapOf("id" to "binding-B", "version" to 2, "owner_user_id" to "owner-B",
            "collection_id" to "group-B", "receiving_account_id" to "account-B", "subscription_id" to 2)) {
        test("binding fence rejects changed $field") { check(!route.bindingMatches(binding::get, (binding + (field to value))::get)) }
    }
    test("binding fence rejects coerced version and subscription") {
        for (field in listOf("version","subscription_id")) check(!route.bindingMatches(binding::get, (binding + (field to "1"))::get))
    }
    test("binding fence rejects malformed expected binding") {
        check(!route.bindingMatches((binding + ("id" to ""))::get, (binding + ("id" to ""))::get))
    }
    val body = "Synthetic receipt only — exact Unicode evidence"
    val good = mapOf<String,Any?>("contract_version" to 2, "stored" to true, "owner_user_id" to "owner-A",
        "client_envelope_id" to "capture-A", "raw_sms_id" to "server-raw-A", "body_sha256" to ReceiptAckPolicy.sha256(body))
    val ok = mapOf<String,Any?>("ok" to true)
    fun accepts(receipt: Map<String,Any?> = good, result: Map<String,Any?> = ok) =
        route.receiptMatches(result::get, receipt::get, "owner-A", "capture-A", body)
    test("exact durable acknowledgement accepted") { check(accepts()) }
    for ((field, invalid) in mapOf("contract_version" to "2", "stored" to "true", "owner_user_id" to "owner-B",
            "client_envelope_id" to "capture-B", "raw_sms_id" to "  ", "body_sha256" to "a".repeat(64))) {
        test("malformed or mismatched acknowledgement rejects $field") { check(!accepts(good + (field to invalid))) }
    }
    test("HTTP success without exact true and receipt is insufficient") {
        check(!accepts(result=mapOf("ok" to "true"))); check(!accepts(emptyMap())); check(!accepts(result=emptyMap()))
    }
    test("tombstone conflict cannot be hidden by a matching pending body") {
        val item = ReceiptAckPolicy.Envelope("capture-A", "owner-A", body)
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(item.id to ReceiptAckPolicy.sha256(body)),
            listOf(item), mapOf(item.id to "a".repeat(64))))
    }
    test("replacement rejects pending, corrupt or invalid queue counts") {
        check(route.canReplace(0, false)); check(!route.canReplace(1, false))
        check(!route.canReplace(0, true)); check(!route.canReplace(-1, false))
    }
    test("real AES-GCM file persistence survives fresh store instance") { directory { dir ->
        val key=KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val cipher=ReceiptCipher({key},Base64.getEncoder()::encodeToString,Base64.getDecoder()::decode)
        val file=File(dir,"queue.enc"); check(queue(file).write(cipher.encrypt(body)))
        check(cipher.decrypt(queue(file).read()!!) == body); check(!file.readText().contains(body))
    } }
    test("empty file is corruption, not an empty queue") { directory { dir ->
        val file=File(dir,"queue.enc"); file.writeText(""); rejects { queue(file).read() }
    } }
    test("unknown first-write stage is preserved and blocks silent reset") { directory { dir ->
        val file=File(dir,"queue.enc"); File(file.path+".new").writeText("partial")
        rejects { queue(file).read() }; check(File(file.path+".new").readText()=="partial")
    } }
    test("stale staged write never replaces a committed queue during read") { directory { dir ->
        val file=File(dir,"queue.enc"); check(queue(file).write("old-ciphertext"))
        File(file.path+".new").writeText("partial"); check(queue(file).read()=="old-ciphertext")
    } }
    test("symlink queue and stage paths rejected") { directory { dir ->
        val file=File(dir,"queue.enc"); val other=File(dir,"other"); other.writeText("retained")
        Files.createSymbolicLink(file.toPath(),other.toPath()); rejects { queue(file).read() }
        Files.delete(file.toPath()); Files.createSymbolicLink(File(file.path+".new").toPath(),other.toPath())
        rejects { queue(file).write("discard") }; check(other.readText()=="retained")
    } }
    for (step in listOf("before_write","before_file_sync","before_rename")) {
        test("injected $step failure preserves committed bytes and reports failure") { directory { dir ->
            val file=File(dir,"queue.enc"); check(queue(file).write("old-ciphertext"))
            check(!queue(file) { if(it==step)throw IOException("injected") }.write("new-ciphertext"))
            check(queue(file).read()=="old-ciphertext")
        } }
    }
    test("directory sync failure reports uncertainty; later successful read establishes durability") { directory { dir ->
        val file=File(dir,"queue.enc"); check(queue(file).write("old-ciphertext"))
        check(!queue(file) { if(it=="before_directory_sync")throw IOException("injected") }.write("new-ciphertext"))
        check(queue(file).read()=="new-ciphertext")
    } }
    test("persistent directory sync failure cannot produce a false duplicate read") { directory { dir ->
        val file=File(dir,"queue.enc"); check(queue(file).write("old-ciphertext"))
        rejects { BuriQueueFile(file,{throw IOException("sync unavailable")}).read() }
    } }
    test("oversized write cannot replace committed bytes") { directory { dir ->
        val file=File(dir,"queue.enc"); check(queue(file).write("old-ciphertext"))
        check(!queue(file).write("a".repeat(BuriQueueFile.MAX_BYTES+1))); check(queue(file).read()=="old-ciphertext")
    } }
    for (step in listOf("before_write","before_file_sync","before_rename","before_directory_sync")) {
        test("actual JVM termination at $step preserves a complete restart state") { directory { dir ->
            val file=File(dir,"queue.enc"); check(queue(file).write("old-ciphertext"))
            val process=ProcessBuilder(File(System.getProperty("java.home"),"bin/java").absolutePath,
                "-cp",System.getProperty("java.class.path"),"app.cool.mobile.receiver_sms.ReliabilityChecksKt",
                "crash-child",file.absolutePath,step).inheritIO().start()
            check(process.waitFor()==71)
            check(queue(file).read()==if(step=="before_directory_sync")"new-ciphertext" else "old-ciphertext")
        } }
    }
    test("first-write process termination preserves stage rather than inventing an empty queue") { directory { dir ->
        val file=File(dir,"queue.enc")
        val process=ProcessBuilder(File(System.getProperty("java.home"),"bin/java").absolutePath,
            "-cp",System.getProperty("java.class.path"),"app.cool.mobile.receiver_sms.ReliabilityChecksKt",
            "crash-child",file.absolutePath,"before_rename").inheritIO().start()
        check(process.waitFor()==71); rejects { queue(file).read() }
    } }
    println("1..$tests")
    println("# Actual Kotlin rules, AES-GCM and host filesystem/process tests; not Android power-loss, Keystore or carrier tests.")
}
