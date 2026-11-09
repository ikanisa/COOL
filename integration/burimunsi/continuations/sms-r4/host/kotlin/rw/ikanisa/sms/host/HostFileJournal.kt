package rw.ikanisa.sms.host

import rw.ikanisa.sms.policy.*
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.StandardOpenOption.*
import java.nio.file.attribute.PosixFilePermissions

/** Test injection stages; production adapters must not include selectable faults. */
enum class HostWriteStage { BEFORE_APPEND, AFTER_PARTIAL_APPEND, AFTER_APPEND, AFTER_FORCE }
fun interface HostWriteFault { fun at(stage: HostWriteStage) }

/**
 * JVM/POSIX HOST REFERENCE ONLY. Stores plaintext; never install with real message evidence.
 * Not an Android/Keystore port. Constructor/read/write never initialize, replace or repair storage.
 * One JVM monitor covers all instances; an OS file lock covers cooperating processes.
 * The path checks are not a security boundary against hostile concurrent filesystem replacement.
 */
class HostFileJournal(private val directory: Path, private val fault: HostWriteFault = HostWriteFault {}): AppendJournalPort {
    private val file get()=directory.resolve("queue.journal")
    override fun read(): JournalRead = synchronized(lock) {
        try {
            safe(directory); safe(file)
            if(Files.notExists(file,NOFOLLOW_LINKS)) return@synchronized JournalRead.Missing
            FileChannel.open(file,READ,WRITE,NOFOLLOW_LINKS).use { channel ->
                val lease=channel.tryLock() ?: return@synchronized JournalRead.Unavailable
                lease.use { JournalRead.Bytes(readAll(channel)) }
            }
        } catch(_: Exception) { JournalRead.Unavailable }
    }
    override fun append(expectedContentHash: String,record: ByteArray): StoreWrite = synchronized(lock) {
        var started=false
        try {
            safe(directory); safe(file)
            FileChannel.open(file,READ,WRITE,NOFOLLOW_LINKS).use { channel ->
                val lease=channel.tryLock() ?: return@synchronized StoreWrite.NOT_COMMITTED
                lease.use {
                    val before=readAll(channel)
                    if(EvidenceHash.sha256(before)!=expectedContentHash) return@synchronized StoreWrite.REVISION_CONFLICT
                    if(record.isEmpty() || before.size.toLong()+record.size>JournalFormat.MAX_BYTES) return@synchronized StoreWrite.NOT_COMMITTED
                    fault.at(HostWriteStage.BEFORE_APPEND)
                    channel.position(channel.size()); started=true
                    val middle=maxOf(1,record.size/2)
                    writeAll(channel,ByteBuffer.wrap(record,0,middle))
                    fault.at(HostWriteStage.AFTER_PARTIAL_APPEND)
                    writeAll(channel,ByteBuffer.wrap(record,middle,record.size-middle))
                    fault.at(HostWriteStage.AFTER_APPEND)
                    channel.force(true)
                    fault.at(HostWriteStage.AFTER_FORCE)
                    StoreWrite.COMMITTED
                }
            }
        } catch(_: Exception) { if(started) StoreWrite.UNKNOWN else StoreWrite.NOT_COMMITTED }
    }
    companion object {
        private val lock=Any()
        private fun safe(path: Path) {
            val absolute=path.toAbsolutePath()
            require(absolute==absolute.normalize()) { "UNSAFE_PATH" }
            var node: Path?=absolute
            while(node!=null) { require(!Files.isSymbolicLink(node)) { "SYMLINK_PATH" }; node=node.parent }
        }
        private fun readAll(channel: FileChannel): ByteArray {
            val size=channel.size()
            require(size in 0..JournalFormat.MAX_BYTES.toLong()) { "JOURNAL_SIZE" }
            val b=ByteBuffer.allocate(size.toInt()); channel.position(0)
            while(b.hasRemaining()) if(channel.read(b)<=0) throw IOException("SHORT_READ")
            return b.array()
        }
        private fun writeAll(channel: FileChannel, buffer: ByteBuffer) {
            while(buffer.hasRemaining()) if(channel.write(buffer)<=0) throw IOException("SHORT_WRITE")
        }
        /** Explicit provisioning of a NEW directory only. Failure retains all partial artifacts. */
        fun initializeFresh(directory: Path, scope: OwnerScope) = synchronized(lock) {
            val header=JournalFormat.empty(scope) // Validate before any filesystem mutation.
            safe(directory)
            Files.createDirectory(directory,PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")))
            val file=directory.resolve("queue.journal")
            FileChannel.open(file,setOf(CREATE_NEW,WRITE,NOFOLLOW_LINKS),
                PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------"))).use {
                writeAll(it,ByteBuffer.wrap(header)); it.force(true)
            }
            // Fail closed on filesystems that cannot honor these host provisioning barriers.
            FileChannel.open(directory,READ,NOFOLLOW_LINKS).use { it.force(true) }
            FileChannel.open(directory.toAbsolutePath().parent,READ,NOFOLLOW_LINKS).use { it.force(true) }
        }
    }
}
