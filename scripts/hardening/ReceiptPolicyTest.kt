import app.cool.mobile.receiver_sms.ReceiptAckPolicy
import app.cool.mobile.receiver_sms.ReceiptCipher
import app.cool.mobile.receiver_sms.SmsQueueOwnerPolicy
import javax.crypto.KeyGenerator
import java.util.Base64
fun main() {
 var count=0
 fun test(name:String, f:()->Unit) {f();count++;println("PASS: $name")}
 fun fails(f:()->Unit){ var failed=false;try{f()}catch(_:Exception){failed=true};check(failed)}
 val e=ReceiptAckPolicy.Envelope("id","owner","receipt body é")
 val sha=ReceiptAckPolicy.sha256(e.rawBody)
 test("exact owner body acknowledged"){check(ReceiptAckPolicy.canAcknowledge("owner","owner",mapOf("id" to sha),listOf(e)))}
 test("switched account rejected"){check(!ReceiptAckPolicy.canAcknowledge("other","owner",mapOf("id" to sha),listOf(e)))}
 test("changed body rejected"){check(!ReceiptAckPolicy.canAcknowledge("owner","owner",mapOf("id" to sha),listOf(e.copy(rawBody="changed"))))}
 test("unknown id rejected"){check(!ReceiptAckPolicy.canAcknowledge("owner","owner",mapOf("unknown" to sha),listOf(e)))}
 test("empty request rejected"){check(!ReceiptAckPolicy.canAcknowledge("owner","owner",emptyMap(),listOf(e)))}
 test("duplicate stored ids rejected"){check(!ReceiptAckPolicy.canAcknowledge("owner","owner",mapOf("id" to sha),listOf(e,e)))}
 test("mixed owner queue rejected"){check(!ReceiptAckPolicy.canAcknowledge("owner","owner",mapOf("id" to sha),listOf(e,e.copy(id="b",ownerUserId="other"))))}
 test("new unrelated receipt is preserved by subset policy"){check(ReceiptAckPolicy.canAcknowledge("owner","owner",mapOf("id" to sha),listOf(e,e.copy(id="b",rawBody="new"))))}
 test("blank body rejected"){check(!ReceiptAckPolicy.canAcknowledge("owner","owner",mapOf("id" to ReceiptAckPolicy.sha256(" ")),listOf(e.copy(rawBody=" "))))}
 test("owner read requires active consent and exact authenticated owner"){
   check(SmsQueueOwnerPolicy.canRead(true,"owner","owner",listOf("owner")))
   check(!SmsQueueOwnerPolicy.canRead(false,"owner","owner",listOf("owner")))
   check(!SmsQueueOwnerPolicy.canRead(true,"owner","other",listOf("owner")))
   check(!SmsQueueOwnerPolicy.canRead(true,"owner","owner",listOf("other")))
   check(!SmsQueueOwnerPolicy.canRead(true,"","",emptyList()))
 }
 test("SHA256 fixture"){check(ReceiptAckPolicy.sha256("abc")=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")}
 val generator=KeyGenerator.getInstance("AES");generator.init(256);val key=generator.generateKey()
 fun codec(k:javax.crypto.SecretKey)=ReceiptCipher({k},{Base64.getEncoder().encodeToString(it)},{Base64.getDecoder().decode(it)})
 val c=codec(key)
 test("AES-GCM Unicode roundtrip"){check(c.decrypt(c.encrypt("é\nreceipt"))=="é\nreceipt")}
 test("randomized encryption"){check(c.encrypt("same")!=c.encrypt("same"))}
 test("wrong key rejected"){fails{codec(generator.generateKey()).decrypt(c.encrypt("secret"))}}
 test("ciphertext tampering rejected"){val p=c.encrypt("receipt").split('.');val data=Base64.getDecoder().decode(p[1]);data[0]=(data[0].toInt() xor 1).toByte();fails{c.decrypt(p[0]+"."+Base64.getEncoder().encodeToString(data))}}
 test("malformed encoding rejected"){fails{c.decrypt("invalid")}}
 test("unavailable key propagates failure"){val locked=ReceiptCipher({throw IllegalStateException("Locked")},{Base64.getEncoder().encodeToString(it)},{Base64.getDecoder().decode(it)});fails{locked.decrypt(c.encrypt("retained"))}}
 println("$count JVM behavior tests passed; Android Keystore and lifecycle were not executed.")
}
