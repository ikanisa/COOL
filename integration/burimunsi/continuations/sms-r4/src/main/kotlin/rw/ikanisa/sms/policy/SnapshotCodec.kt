package rw.ikanisa.sms.policy

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.security.MessageDigest

/** Diagnostic codes never interpolate a message body, sender, identity or raw bytes. */
enum class DecodeCode { SIZE, MAGIC, VERSION, CHECKSUM, TRUNCATED, STRUCTURE, INVARIANT, TRAILING, SCOPE, HISTORY }
class SnapshotFormatException(val code: DecodeCode): IOException(code.name)
internal fun requireFormat(ok: Boolean, code: DecodeCode = DecodeCode.STRUCTURE) {
    if (!ok) throw SnapshotFormatException(code)
}

/** Bounds are enforced BEFORE allocations. Strings are exact UTF-16 units, not lossy UTF-8. */
internal class BinaryWriter(private val limit: Int) {
    private val bytes = ByteArrayOutputStream()
    private val out = DataOutputStream(bytes)
    private fun room(n: Int) = requireFormat(n >= 0 && bytes.size().toLong()+n <= limit, DecodeCode.SIZE)
    fun int(n: Int) { room(4); out.writeInt(n) }
    fun long(n: Long) { room(8); out.writeLong(n) }
    fun bool(b: Boolean) { room(1); out.writeByte(if (b) 1 else 0) }
    fun text(s: String?, max: Int = 128) {
        if (s == null) { int(-1); return }
        requireFormat(s.length <= max, DecodeCode.SIZE)
        room(4 + s.length * 2); out.writeInt(s.length); s.forEach { out.writeChar(it.code) }
    }
    fun nullableInt(n: Int?) { bool(n != null); if (n != null) int(n) }
    fun nullableLong(n: Long?) { bool(n != null); if (n != null) long(n) }
    fun raw(b: ByteArray) { room(b.size); out.write(b) }
    fun result(): ByteArray = bytes.toByteArray()
}
internal class BinaryReader(bytes: ByteArray) {
    private val input = DataInputStream(ByteArrayInputStream(bytes))
    val remaining get() = input.available()
    private fun need(n: Int) = requireFormat(n >= 0 && n <= remaining, DecodeCode.TRUNCATED)
    fun int(): Int { need(4); return input.readInt() }
    fun long(): Long { need(8); return input.readLong() }
    fun bool(): Boolean { need(1); val n=input.readUnsignedByte(); requireFormat(n in 0..1); return n==1 }
    fun count(min: Int, max: Int): Int = int().also { requireFormat(it in min..max, DecodeCode.SIZE) }
    fun text(max: Int = 128): String? {
        val n=int(); if (n == -1) return null
        requireFormat(n in 0..max, DecodeCode.SIZE); need(n*2)
        return CharArray(n) { input.readChar() }.concatToString()
    }
    fun required(max: Int = 128): String = text(max) ?: throw SnapshotFormatException(DecodeCode.STRUCTURE)
    fun nullableInt(): Int? = if (bool()) int() else null
    fun nullableLong(): Long? = if (bool()) long() else null
    fun raw(n: Int): ByteArray { need(n); return ByteArray(n).also(input::readFully) }
    inline fun <reified T: Enum<T>> enum(): T {
        val name=required(64)
        return enumValues<T>().firstOrNull { it.name == name } ?: throw SnapshotFormatException(DecodeCode.STRUCTURE)
    }
    fun end() = requireFormat(remaining == 0, DecodeCode.TRAILING)
}

/** Additional persisted-state invariants; no trust in serialized derived fields or receipt lists. */
object SnapshotIntegrity {
    fun valid(s: QueueSnapshot): Boolean {
        if (!s.valid() || !s.batch.originals.all { it.eligible() }) return false
        if (!s.reason.matches(Regex("[A-Z0-9_]{1,128}"))) return false
        if (s.phase == Phase.READY && (s.attempts != 0 || s.receipts.isNotEmpty())) return false
        if (s.phase != Phase.READY && s.activeAttempt == null) return false
        if (s.phase == Phase.HELD && !s.outcomeUncertain) return false
        fun receiptsValid(rows: List<VerifiedReceipt>): Boolean {
            if (rows.size != s.batch.originals.size || rows.map { it.captureId }.toSet() != s.batch.originals.map { it.captureId }.toSet()) return false
            return rows.all { r -> when (r.outcome) {
                ReceiptOutcome.RETAINED -> r.rejectionCode == null && r.canonicalId?.let(EvidenceHash::identity) == true &&
                    if (s.batch.scope.contract == Contract.BURI_COLLECT_V2)
                        r.bodySha256 == s.batch.originals.single().bodySha256
                    else r.canonicalId.let(AckPolicy::uuid) && r.bodySha256 == null
                ReceiptOutcome.REJECTED -> s.batch.scope.contract == Contract.MMONEY_LEDGER_V1 &&
                    r.canonicalId == null && r.bodySha256 == null && r.rejectionCode?.matches(Regex("[A-Z0-9_]{1,64}")) == true
            } }
        }
        if (s.receipts.isNotEmpty() && !receiptsValid(s.receipts)) return false
        if (s.conflictingReceipts.isNotEmpty() && (!receiptsValid(s.conflictingReceipts) || s.receipts.isEmpty() || s.conflictingReceipts == s.receipts)) return false
        if (s.phase == Phase.CONFLICT && s.receipts.isNotEmpty() && s.conflictingReceipts.isEmpty()) return false
        return true
    }
}

/** Version 1 is the FIRST persisted format. R2 defined no persisted wire format to migrate. */
object SnapshotCodec {
    const val VERSION = 1
    const val MAX_BYTES = 8 * 1024 * 1024
    private const val MAGIC = 0x534d5353 // SMSS
    private fun digest(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b)

    fun encode(s: QueueSnapshot): ByteArray {
        requireFormat(SnapshotIntegrity.valid(s), DecodeCode.INVARIANT)
        val w=BinaryWriter(MAX_BYTES-44)
        writeBatch(w,s.batch)
        w.long(s.revision); w.text(s.phase.name); w.text(s.reason)
        w.int(s.attempts); w.nullableLong(s.firstAttemptAt); w.long(s.lastObservedAt); w.nullableLong(s.notBefore)
        w.bool(s.activeAttempt != null)
        s.activeAttempt?.let { a -> w.text(a.key); w.text(a.operationId); w.text(a.payloadHash); w.int(a.ordinal); w.long(a.sessionEpoch); w.long(a.startedAt) }
        w.bool(s.outcomeUncertain); writeReceipts(w,s.receipts); writeReceipts(w,s.conflictingReceipts)
        val payload=w.result()
        val frame=BinaryWriter(MAX_BYTES); frame.int(MAGIC); frame.int(VERSION); frame.int(payload.size); frame.raw(payload)
        val prefix=frame.result(); frame.raw(digest(prefix)); return frame.result()
    }

    fun decode(bytes: ByteArray): QueueSnapshot {
        requireFormat(bytes.size in 44..MAX_BYTES, DecodeCode.SIZE)
        val r=BinaryReader(bytes)
        requireFormat(r.int()==MAGIC, DecodeCode.MAGIC)
        requireFormat(r.int()==VERSION, DecodeCode.VERSION)
        val n=r.int(); requireFormat(n >= 0 && n == r.remaining-32, DecodeCode.SIZE)
        val payload=r.raw(n); val checksum=r.raw(32); r.end()
        requireFormat(MessageDigest.isEqual(checksum,digest(bytes.copyOfRange(0,bytes.size-32))), DecodeCode.CHECKSUM)
        val p=BinaryReader(payload); val batch=readBatch(p)
        val revision=p.long(); val phase=p.enum<Phase>(); val reason=p.required()
        val attempts=p.int(); val first=p.nullableLong(); val observed=p.long(); val notBefore=p.nullableLong()
        val active=if(p.bool()) Attempt(p.required(),p.required(),p.required(),p.int(),p.long(),p.long()) else null
        val uncertain=p.bool(); val receipts=readReceipts(p); val conflicts=readReceipts(p); p.end()
        val s=QueueSnapshot(batch,revision,phase,reason,attempts,first,observed,notBefore,active,uncertain,receipts,conflicts)
        requireFormat(SnapshotIntegrity.valid(s),DecodeCode.INVARIANT)
        return s
    }

    internal fun batchBytes(b: UploadBatch): ByteArray = BinaryWriter(MAX_BYTES).also { writeBatch(it,b) }.result()
    private fun writeBatch(w: BinaryWriter,b: UploadBatch) {
        w.text(b.operationId); w.int(b.originals.size)
        for(o in b.originals) {
            w.text(o.scope.contract.name); w.text(o.scope.ownerId); w.text(o.scope.installationId); w.text(o.scope.generation)
            w.text(o.binding.id); w.int(o.binding.version); w.nullableInt(o.binding.subscriptionId)
            w.text(o.captureId); w.text(o.sourceId)
            val input=o.assembly.input; w.text(input.mode.name); w.text(input.format); w.int(input.parts.size)
            for(p in input.parts) {
                w.nullableInt(p.sequence); w.nullableInt(p.total); w.nullableInt(p.reference); w.nullableInt(p.referenceBits)
                w.text(p.sender,65536); w.text(p.body,65536); w.nullableLong(p.serviceCentreMillis); w.nullableInt(p.subscriptionId)
                w.nullableInt(p.dcs); w.text(p.applicationPort); w.bool(p.envelopeValidated); w.text(p.pduHex,8192)
            }
            val c=o.classification; w.text(c.contract.name); w.text(c.kind.name); w.text(c.reason); w.text(c.policyVersion); w.text(c.evidenceFingerprint)
            // All derived hashes are redundant checks; they are never accepted in place of recomputation.
            w.text(o.assembly.completeness.name); w.text(o.assembly.reason); w.text(o.bodySha256); w.text(o.evidenceHash)
        }
        w.text(b.key); w.text(b.payloadHash)
    }
    private fun readBatch(r: BinaryReader): UploadBatch {
        val operation=r.required(); val count=r.count(1,20)
        val originals=List(count) {
            val scope=OwnerScope(r.enum(),r.required(),r.required(),r.required())
            val binding=SourceBinding(r.required(),r.int(),r.nullableInt())
            val capture=r.required(); val source=r.required(); val mode=r.enum<InputMode>(); val format=r.text()
            val parts=List(r.count(1,MultipartPolicy.MAX_PARTS)) {
                SmsPart(r.nullableInt(),r.nullableInt(),r.nullableInt(),r.nullableInt(),r.text(65536),r.text(65536),
                    r.nullableLong(),r.nullableInt(),r.nullableInt(),r.text(),r.bool(),r.text(8192))
            }
            val assembly=MultipartPolicy.inspect(SmsInput(mode,format,parts))
            val classification=Classification(r.enum(),r.enum(),r.required(),r.required(),r.required())
            val o=Original(scope,binding,capture,source,assembly,classification)
            requireFormat(r.enum<Completeness>()==assembly.completeness && r.required()==assembly.reason &&
                r.text()==o.bodySha256 && r.required()==o.evidenceHash, DecodeCode.INVARIANT)
            o
        }
        val b=UploadBatch(operation,originals)
        requireFormat(b.valid() && r.required()==b.key && r.required()==b.payloadHash,DecodeCode.INVARIANT)
        return b
    }
    private fun writeReceipts(w: BinaryWriter, rows: List<VerifiedReceipt>) {
        w.int(rows.size)
        for(r in rows) { w.text(r.captureId); w.text(r.outcome.name); w.text(r.canonicalId); w.text(r.bodySha256); w.text(r.rejectionCode) }
    }
    private fun readReceipts(r: BinaryReader): List<VerifiedReceipt> = List(r.count(0,20)) {
        VerifiedReceipt(r.required(),r.enum(),r.text(),r.text(),r.text())
    }
}
