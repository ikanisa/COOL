import app.cool.mobile.security.SnapshotCipher
import javax.crypto.KeyGenerator
import javax.crypto.Cipher
import java.util.concurrent.Executors

fun main() {
    val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    val owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    val other = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    val cipher = SnapshotCipher { key }
    var passed = 0
    fun test(name: String, action: () -> Unit) { action(); passed++; println("PASS $name") }
    fun rejected(action: () -> Unit) {
        var failed = false
        try { action() } catch (_: Exception) { failed = true }
        check(failed) { "Invalid protected data was accepted" }
    }
    test("RWF JSON roundtrip") { check(cipher.decrypt(owner,cipher.encrypt(owner,"{\"balance\":5000}")) == "{\"balance\":5000}") }
    test("Multilingual Unicode") { val text="Ikimina — ubwizigame 💚"; check(cipher.decrypt(owner,cipher.encrypt(owner,text))==text) }
    test("Nonce randomization") { check(!cipher.encrypt(owner,"same").contentEquals(cipher.encrypt(owner,"same"))) }
    test("Cross-account binding") { rejected { cipher.decrypt(other,cipher.encrypt(owner,"balance")) } }
    test("Payload tampering") { val bytes=cipher.encrypt(owner,"balance"); bytes[20]=(bytes[20].toInt() xor 1).toByte();rejected { cipher.decrypt(owner,bytes) } }
    test("Wrong key") { val second=SnapshotCipher { KeyGenerator.getInstance("AES").generateKey() };rejected { second.decrypt(owner,cipher.encrypt(owner,"balance")) } }
    test("Missing read key never generates") { var created=false;val missing=SnapshotCipher { create->created=create;throw IllegalStateException() };rejected { missing.decrypt(owner,cipher.encrypt(owner,"balance")) };check(!created) }
    test("Unknown schema") { val b=cipher.encrypt(owner,"balance");b[0]=4;rejected{cipher.decrypt(owner,b)} }
    test("Truncated ciphertext") { rejected { cipher.decrypt(owner,cipher.encrypt(owner,"balance").copyOf(20)) } }
    test("Trailing ciphertext") { rejected { cipher.decrypt(owner,cipher.encrypt(owner,"balance") + 1.toByte()) } }
    test("Empty plaintext is preserved") { check(cipher.decrypt(owner,cipher.encrypt(owner,""))=="") }
    test("Exact byte cap") { val text="x".repeat(SnapshotCipher.MAX_BYTES);check(cipher.decrypt(owner,cipher.encrypt(owner,text))==text) }
    test("Oversized plaintext rejected") { rejected{cipher.encrypt(owner,"x".repeat(SnapshotCipher.MAX_BYTES+1))} }
    test("Multibyte cap") { rejected{cipher.encrypt(owner,"💚".repeat(SnapshotCipher.MAX_BYTES/4+1))} }
    test("Oversized encrypted data rejected") { val b=ByteArray(SnapshotCipher.MAX_BYTES+30);b[0]=5;rejected{cipher.decrypt(owner,b)} }
    test("Empty owner rejected") { rejected { cipher.encrypt("","balance") } }
    test("Path-like owner rejected") { rejected { cipher.encrypt("../$owner","balance") } }
    test("Owner canonicalization required") { rejected { cipher.encrypt(owner.uppercase(),"balance") } }
    test("Concurrent independent operations") {
        val pool=Executors.newFixedThreadPool(4)
        try { val jobs=(1..32).map{i->pool.submit<Boolean>{cipher.decrypt(owner,cipher.encrypt(owner,"$i"))=="$i"}};check(jobs.all{it.get()}) } finally {pool.shutdown()}
    }
    test("Ciphertext is not plaintext") { val text="PRIVATE_BALANCE_ONLY";check(!String(cipher.encrypt(owner,text),Charsets.ISO_8859_1).contains(text)) }
    println("SNAPSHOT_JVM_TESTS=$passed")
}
