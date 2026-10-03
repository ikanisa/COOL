package app.cool.mobile.gateway

import java.io.*
import java.nio.file.Files
import java.nio.file.StandardOpenOption
import java.security.DigestOutputStream
import java.security.MessageDigest

/** Versioned file-only transport; one 4KiB buffer and bounded <=200-byte names.
 * No lifetime entry catalogue, ZIP metadata, key export or installation merge.
 * Duplicates are refused by CREATE_NEW in fresh retained quarantine. */
internal object GatewayRecoveryTransfer {
    private val MAGIC="COLLECT_GATEWAY_CIPHERTEXT_1\n".toByteArray(Charsets.US_ASCII)
    private val END="COLLECT_GATEWAY_END_1\n".toByteArray(Charsets.US_ASCII)
    private val objectName=Regex("objects/[a-z0-9][a-z0-9-]{0,180}\\.bin(?:\\.bak|\\.new)?")
    private fun refuse():Nothing=throw GatewayStateException("gateway_recovery_invalid")
    private fun check(cancelled:()->Boolean) { if(cancelled())throw GatewayStateException("gateway_recovery_cancelled") }
    private fun limit(name:String):Long=when {
        name=="manifest.ndjson" -> Long.MAX_VALUE // core validates bounded 1024-byte records
        name=="SEALED.json" -> 1024L
        objectName.matches(name) -> GatewayCrypto.MAX_BYTES+29L
        else -> refuse()
    }
    private fun bytes(hash:ByteArray):String=hash.joinToString("") { "%02x".format(it) }
    private fun hash(file:File):String { val md=MessageDigest.getInstance("SHA-256");FileInputStream(file).use { input -> val b=ByteArray(4096);while(true) { val n=input.read(b);if(n<0)break;md.update(b,0,n) } };return bytes(md.digest()) }
    private fun copy(input:InputStream,output:OutputStream,size:Long,cancelled:()->Boolean):ByteArray {
        if(size<0)refuse();val md=MessageDigest.getInstance("SHA-256");val b=ByteArray(4096);var remaining=size
        while(remaining>0) { check(cancelled);val n=input.read(b,0,minOf(remaining,b.size.toLong()).toInt());if(n<=0)refuse();output.write(b,0,n);md.update(b,0,n);remaining-=n }
        return md.digest()
    }
    fun write(archive:GatewayRecoveryArchive,output:OutputStream,cancelled:()->Boolean={false},progress:(Long)->Unit={}):String {
        if(archive.files<0 || archive.files>Long.MAX_VALUE-2 || !archive.manifestSha256.matches(Regex("[0-9a-f]{64}")) || hash(File(archive.directory,"manifest.ndjson"))!=archive.manifestSha256)refuse()
        val transport=MessageDigest.getInstance("SHA-256");var count=0L
        DataOutputStream(DigestOutputStream(output,transport)).use { stream ->
            stream.write(MAGIC);stream.writeLong(archive.files);stream.write(archive.manifestSha256.toByteArray(Charsets.US_ASCII))
            fun entry(name:String) {
                check(cancelled);val file=File(archive.directory,name);val names=name.toByteArray(Charsets.UTF_8)
                if(names.size !in 1..200 || Files.isSymbolicLink(file.toPath()) || !file.isFile || file.length()>limit(name))refuse()
                val size=file.length();stream.writeShort(names.size);stream.write(names);stream.writeLong(size)
                val digest=FileInputStream(file).use { input -> val result=copy(input,stream,size,cancelled);if(input.read()!=-1)refuse();result };stream.write(digest)
            }
            entry("manifest.ndjson");entry("SEALED.json")
            GatewayRecovery.inventory(File(archive.directory,"objects"),cancelled) { page -> for(item in page) { entry("objects/${item.name}");count++;progress(count) } }
            if(count!=archive.files)refuse();check(cancelled);stream.write(END);stream.writeLong(count);stream.write(archive.manifestSha256.toByteArray(Charsets.US_ASCII));stream.flush()
        };return bytes(transport.digest())
    }
    fun verifyOutput(input:InputStream,expected:String,cancelled:()->Boolean={false}) {
        val md=MessageDigest.getInstance("SHA-256");input.use { stream -> val b=ByteArray(4096);while(true) { check(cancelled);val n=stream.read(b);if(n<0)break;md.update(b,0,n) } }
        if(bytes(md.digest())!=expected)throw GatewayStateException("gateway_recovery_output_unknown")
    }
    fun read(input:InputStream,destination:File,cancelled:()->Boolean={false},progress:(Long)->Unit={},
        available:()->Long={destination.parentFile.usableSpace}):Long {
        GatewayRecoveryStorage.fresh(destination)
        val objects=File(destination,"objects");GatewayRecoveryStorage.fresh(objects)
        // Raw provider bytes are retained before interpretation, including partial
        // capture on cancellation, EOF, I/O error, unknown or invalid outcomes.
        val raw=File(destination.parentFile,"source.collect-gateway")
        var created=false
        try { input.use { source -> GatewayRecoveryStorage.output(raw,available).also { created=true }.use { output ->
            val b=ByteArray(4096);while(true) { check(cancelled);val n=source.read(b);if(n<0)break;output.write(b,0,n) }
        } } } finally { if(created)GatewayRecoveryStorage.syncFile(raw) }
        DataInputStream(FileInputStream(raw)).use { stream ->
            fun exact(expected:ByteArray) { val actual=ByteArray(expected.size);stream.readFully(actual);if(!actual.contentEquals(expected))refuse() }
            exact(MAGIC);val wanted=stream.readLong();if(wanted<0 || wanted>Long.MAX_VALUE-2)refuse()
            val manifestBytes=ByteArray(64);stream.readFully(manifestBytes);val manifest=String(manifestBytes,Charsets.US_ASCII);if(!manifest.matches(Regex("[0-9a-f]{64}")))refuse()
            var position=0L;var count=0L
            while(position<wanted+2) {
                check(cancelled);val length=stream.readUnsignedShort();if(length !in 1..200)refuse();val nameBytes=ByteArray(length);stream.readFully(nameBytes)
                val name=String(nameBytes,Charsets.UTF_8);if(!name.toByteArray(Charsets.UTF_8).contentEquals(nameBytes))refuse()
                if(position==0L && name!="manifest.ndjson" || position==1L && name!="SEALED.json" || position>1 && !objectName.matches(name))refuse()
                val size=stream.readLong();if(size<0 || size>limit(name))refuse();val file=File(destination,name)
                val digest=GatewayRecoveryStorage.output(file,available).use { copy(stream,it,size,cancelled) }
                val expected=ByteArray(32);stream.readFully(expected);if(!digest.contentEquals(expected))refuse();FileOutputStream(file,true).use { it.fd.sync() }
                if(position>1) { count++;progress(count) };position++
            }
            exact(END);if(stream.readLong()!=count)refuse();exact(manifestBytes);if(stream.read()!=-1 || hash(File(destination,"manifest.ndjson"))!=manifest)refuse();check(cancelled);return count
        }
    }
}
