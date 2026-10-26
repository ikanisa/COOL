import app.cool.mobile.security.ProtectedSnapshotStore
import android.util.AtomicFile
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

// The runner supplies only an AtomicFile host adapter and controlled key vault.
// Production store/cipher logic, disk bytes and JCA authentication are executed.
fun main() {
    val owner="d1000000-0000-4000-8000-000000000001"
    val other="d1000000-0000-4000-8000-000000000002"
    var passed=0
    fun rejected(body:()->Unit) { var failed=false;try{body()}catch(_:Exception){failed=true};check(failed) }
    fun test(name:String,body:(File,(String,Boolean)->SecretKey)->Unit) {
        val root=Files.createTempDirectory("payment-help-store-test-").toFile()
        val keys=mutableMapOf<String,SecretKey>()
        val provider={alias:String,create:Boolean->keys[alias]?:run{check(create);KeyGenerator.getInstance("AES").apply{init(256)}.generateKey().also{keys[alias]=it}}}
        try{body(root,provider);passed++;println("PASS Android store: $name")}
        finally{root.deleteRecursively()}
    }
    fun file(root:File,purpose:String,user:String=owner):File {
        val directory=when(purpose){"auth"->"collect_protected_auth_session";"payment_help"->"collect_protected_payment_help";else->"collect_protected_snapshot"}
        val hash=MessageDigest.getInstance("SHA-256").digest(user.toByteArray()).joinToString(""){"%02x".format(it.toInt() and 255)}
        return File(File(root,directory),"$hash.enc")
    }
    test("reconstruction, purpose isolation and owner-targeted clear") { root,key->
        val finance=ProtectedSnapshotStore(root,"snapshot",key);val auth=ProtectedSnapshotStore(root,"auth",key);val help=ProtectedSnapshotStore(root,"payment_help",key)
        finance.write(owner,"retained finance");auth.write(owner,"retained auth");help.write(owner,"original request")
        val financeBytes=file(root,"snapshot").readBytes();val authBytes=file(root,"auth").readBytes()
        check(ProtectedSnapshotStore(root,"payment_help",key).read(owner)=="original request")
        help.write(other,"new owner request");check(help.clear(owner));check(help.read(other)=="new owner request")
        check(help.clear());check(help.read(other)==null)
        check(finance.read(owner)=="retained finance"&&auth.read(owner)=="retained auth")
        check(financeBytes.contentEquals(file(root,"snapshot").readBytes())&&authBytes.contentEquals(file(root,"auth").readBytes()))
    }
    test("copying finance or auth ciphertext into help fails and preserves all bytes") { root,key->
        val help=ProtectedSnapshotStore(root,"payment_help",key);help.write(owner,"request")
        for(purpose in listOf("snapshot","auth")){
            ProtectedSnapshotStore(root,purpose,key).write(owner,"private $purpose")
            val original=file(root,purpose).readBytes();file(root,"payment_help").writeBytes(original)
            rejected{help.read(owner)};check(original.contentEquals(file(root,"payment_help").readBytes()))
            check(ProtectedSnapshotStore(root,purpose,key).read(owner)=="private $purpose")
        }
    }
    test("owner authentication and tamper failure preserve source ciphertext") { root,key->
        val help=ProtectedSnapshotStore(root,"payment_help",key);help.write(owner,"request")
        val source=file(root,"payment_help").readBytes();file(root,"payment_help",other).writeBytes(source)
        rejected{help.read(other)};check(source.contentEquals(file(root,"payment_help",other).readBytes()))
        val corrupt=source.copyOf();corrupt[corrupt.lastIndex]=(corrupt.last().toInt() xor 1).toByte();file(root,"payment_help").writeBytes(corrupt)
        rejected{help.read(owner)};check(corrupt.contentEquals(file(root,"payment_help").readBytes()))
    }
    test("missing key is not generated on read and leaves recovery bytes") { root,key->
        ProtectedSnapshotStore(root,"payment_help",key).write(owner,"request");val before=file(root,"payment_help").readBytes();var created=false
        val unavailable=ProtectedSnapshotStore(root,"payment_help"){_,create->created=create;error("Controlled locked key")}
        rejected{unavailable.read(owner)};check(!created);check(before.contentEquals(file(root,"payment_help").readBytes()))
    }
    test("failed atomic replacement keeps prior request and other owner's bytes") { root,key->
        val help=ProtectedSnapshotStore(root,"payment_help",key);help.write(owner,"original")
        val before=file(root,"payment_help").readBytes();AtomicFile.failNextFinish=true
        rejected{help.write(other,"replacement")};check(before.contentEquals(file(root,"payment_help").readBytes()));check(help.read(owner)=="original")
    }
    test("invalid owners and over-limit writes cannot erase retained help") { root,key->
        val help=ProtectedSnapshotStore(root,"payment_help",key);help.write(owner,"original");val before=file(root,"payment_help").readBytes()
        rejected{help.clear("../owner")};rejected{help.write(owner,"x".repeat(1024*1024+1))};rejected{help.read("")}
        check(before.contentEquals(file(root,"payment_help").readBytes()))
    }
    test("concurrent instances serialize complete authenticated replacements") { root,key->
        val help=ProtectedSnapshotStore(root,"payment_help",key);help.write(owner,"initial");val pool=Executors.newFixedThreadPool(6)
        try{pool.invokeAll((1..30).map{n->Callable{ProtectedSnapshotStore(root,"payment_help",key).write(owner,"request-$n")}}).forEach{check(it.get())}
            check((1..30).any{help.read(owner)=="request-$it"})
        }finally{pool.shutdownNow()}
    }
    println("Android protected-store checks: $passed passed")
}
