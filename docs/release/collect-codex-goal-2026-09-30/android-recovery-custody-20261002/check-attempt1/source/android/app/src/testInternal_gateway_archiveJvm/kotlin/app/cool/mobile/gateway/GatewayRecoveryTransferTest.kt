package app.cool.mobile.gateway

import org.junit.Test
import org.junit.Assert.*
import java.io.*
import java.nio.file.Files
import java.security.MessageDigest

class GatewayRecoveryTransferTest {
    private fun fixture(action:(GatewayLateFixture)->Unit) { val f=GatewayLateFixture();try { action(f) } finally { f.dispose() } }
    private fun refuse(code:String?=null,action:()->Unit) { try { action();fail("Expected refusal") } catch(e:Exception) { if(code!=null) { assertTrue(e is GatewayStateException);assertEquals(code,(e as GatewayStateException).reasonCode) } } }
    private fun hash(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes)
    private fun framed(objects:List<Pair<String,ByteArray>>,duplicate:Boolean=false,missingSeal:Boolean=false,trailing:Boolean=false):ByteArray {
        val output=ByteArrayOutputStream();val manifest="synthetic manifest\n".toByteArray();val sha=hash(manifest).joinToString("") { "%02x".format(it) }
        DataOutputStream(output).use { out ->
            out.write("COLLECT_GATEWAY_CIPHERTEXT_1\n".toByteArray());out.writeLong(objects.size.toLong());out.write(sha.toByteArray())
            fun entry(name:String,bytes:ByteArray) { val n=name.toByteArray();out.writeShort(n.size);out.write(n);out.writeLong(bytes.size.toLong());out.write(bytes);out.write(hash(bytes)) }
            entry("manifest.ndjson",manifest);if(missingSeal)return@use;entry("SEALED.json",byteArrayOf(1))
            objects.forEach { entry(it.first,it.second) }
            out.write("COLLECT_GATEWAY_END_1\n".toByteArray());out.writeLong(objects.size.toLong());out.write(sha.toByteArray());if(trailing)out.writeByte(42)
        };return output.toByteArray()
    }
    private fun archive(f:GatewayLateFixture):GatewayRecoveryArchive { f.seed(1);return f.store().exportRecovery(File(f.root,"snapshot-${f.id()}")) }
    private fun imported(f:GatewayLateFixture,name:String)=File(File(f.root,"run-${f.id()}").also { it.mkdir() },name)
    @Test fun streamRoundTripPreservesAllCiphertextAndValidatesOnlyFreshInactiveView() = fixture { f ->
        val a=archive(f);val output=ByteArrayOutputStream();val exported=mutableListOf<Long>();val sha=GatewayRecoveryTransfer.write(a,output,progress={exported.add(it)})
        assertEquals(a.files,exported.last());GatewayRecoveryTransfer.verifyOutput(ByteArrayInputStream(output.toByteArray()),sha)
        val target=imported(f,"import");val progress=mutableListOf<Long>()
        assertEquals(a.files,GatewayRecoveryTransfer.read(ByteArrayInputStream(output.toByteArray()),target,progress={progress.add(it)}));assertEquals(a.files,progress.last())
        val result=f.store().restoreRecovery(target,a.manifestSha256,File(target.parentFile,"inactive"));assertTrue(result.keyValidated);assertTrue(result.requiresReEnrollment);assertTrue(File(result.directory,GatewayRecovery.INACTIVE).isFile)
        for(name in File(a.directory,"objects").list()!!) assertArrayEquals(File(a.directory,"objects/$name").readBytes(),File(result.directory,"original/$name").readBytes())
    }
    @Test fun traversalAbsoluteUnknownDirectoryAndLinkFramesNeverExtractObjects() = fixture { f ->
        for(name in listOf("../journal.bin","/journal.bin","objects/../../journal.bin","objects/future.json","objects/","LINK/objects/journal.bin")) {
            val target=imported(f,"denied");refuse { GatewayRecoveryTransfer.read(ByteArrayInputStream(framed(listOf(name to byteArrayOf(1)))),target) }
            assertTrue(File(target.parentFile,"source.collect-gateway").isFile);assertTrue(File(target,"objects").list()!!.isEmpty())
        }
    }
    @Test fun duplicateEntriesAndOversizedCiphertextRemainQuarantined() = fixture { f ->
        val duplicate=framed(listOf("objects/journal.bin" to byteArrayOf(1),"objects/journal.bin" to byteArrayOf(2)))
        val target=imported(f,"duplicate");refuse { GatewayRecoveryTransfer.read(ByteArrayInputStream(duplicate),target) };assertArrayEquals(byteArrayOf(1),File(target,"objects/journal.bin").readBytes())
        val oversized=imported(f,"oversized");refuse("gateway_recovery_invalid") { GatewayRecoveryTransfer.read(ByteArrayInputStream(framed(listOf("objects/journal.bin" to ByteArray(GatewayCrypto.MAX_BYTES+30)))),oversized) };assertTrue(File(oversized.parentFile,"source.collect-gateway").isFile)
    }
    @Test fun missingSealWrongTrustedHashAndTrailingBytesNeverPublishRestoreResult() = fixture { f ->
        val missing=imported(f,"missing");refuse { GatewayRecoveryTransfer.read(ByteArrayInputStream(framed(emptyList(),missingSeal=true)),missing) };assertFalse(File(missing,"SEALED.json").exists())
        val trailing=imported(f,"trailing");refuse { GatewayRecoveryTransfer.read(ByteArrayInputStream(framed(emptyList(),trailing=true)),trailing) }
        val a=archive(f);val output=ByteArrayOutputStream();GatewayRecoveryTransfer.write(a,output);val target=imported(f,"import");GatewayRecoveryTransfer.read(ByteArrayInputStream(output.toByteArray()),target)
        val inactive=File(target.parentFile,"inactive");refuse { f.store().restoreRecovery(target,"0".repeat(64),inactive) };assertTrue(File(inactive,GatewayRecovery.INACTIVE).exists());assertFalse(File(inactive,"RESULT.json").exists())
    }
    @Test fun cancellationRetainsRawProviderBytesAndDoesNotTouchActiveJournal() = fixture { f ->
        val a=archive(f);val before=f.directory.listFiles()!!.associate { it.name to it.readBytes() };val output=ByteArrayOutputStream();GatewayRecoveryTransfer.write(a,output)
        val target=imported(f,"cancel");var checks=0;refuse("gateway_recovery_cancelled") { GatewayRecoveryTransfer.read(ByteArrayInputStream(output.toByteArray()),target,{++checks>3}) };assertTrue(File(target.parentFile,"source.collect-gateway").isFile)
        for((name,bytes) in before)assertArrayEquals(bytes,File(f.directory,name).readBytes())
    }
    @Test fun outputReadbackUnknownAndModifiedFrameDigestRefuseWithoutVerifiedSuccess() = fixture { f ->
        val a=archive(f);val output=ByteArrayOutputStream();val sha=GatewayRecoveryTransfer.write(a,output);val changed=output.toByteArray().also { it[it.lastIndex]=(it.last()+1).toByte() }
        refuse("gateway_recovery_output_unknown") { GatewayRecoveryTransfer.verifyOutput(ByteArrayInputStream(changed),sha) }
        refuse("gateway_recovery_cancelled") { GatewayRecoveryTransfer.write(a,ByteArrayOutputStream(),{true}) }
        val corrupt=framed(listOf("objects/journal.bin" to byteArrayOf(1,2,3))).also { bytes -> val marker=byteArrayOf(1,2,3);val pos=(0 until bytes.size-3).first { bytes.copyOfRange(it,it+3).contentEquals(marker) };bytes[pos]=7 }
        refuse { GatewayRecoveryTransfer.read(ByteArrayInputStream(corrupt),imported(f,"corrupt")) }
    }
    @Test fun durablePauseVerificationPreservesBackupsAndPartialNewFilesWithoutRepair() = fixture { f ->
        f.storage.commit(GatewayJournalState(true));val base=File(f.directory,"journal.bin");val good=base.readBytes();File(f.directory,"journal.bin.bak").writeBytes(good);base.writeBytes(byteArrayOf(1,2,3));File(f.directory,"journal.bin.new").writeBytes(byteArrayOf(9,8,7))
        val before=f.directory.listFiles()!!.associate { it.name to it.readBytes() };GatewayRecoveryPause.require(f.directory,f::crypto);for((name,bytes) in before)assertArrayEquals(bytes,File(f.directory,name).readBytes())
        File(f.directory,"journal.bin.bak").delete();refuse { GatewayRecoveryPause.require(f.directory,f::crypto) }
    }
    @Test fun missingUnpausedChangedInactiveOrSymlinkDirectoryNeverPermitsExport() = fixture { f ->
        refuse("gateway_recovery_pause_required") { GatewayRecoveryPause.require(f.directory,f::crypto) };f.storage.commit(GatewayJournalState(false));refuse("gateway_recovery_pause_required") { GatewayRecoveryPause.require(f.directory,f::crypto) }
        f.storage.commit(GatewayJournalState(true));File(f.directory,"journal-marker.bin").delete();refuse("gateway_recovery_pause_required") { GatewayRecoveryPause.require(f.directory,f::crypto) }
        File(f.directory,GatewayRecovery.INACTIVE).writeText("inactive");refuse("gateway_recovery_inactive") { GatewayRecoveryPause.require(f.directory,f::crypto) }
        val link=File(f.root,"linked-${f.id()}");Files.createSymbolicLink(link.toPath(),f.directory.toPath());refuse("gateway_recovery_pause_required") { GatewayRecoveryPause.require(link,f::crypto) }
    }
    @Test fun pickerResultCancellationBeforeWorkerStartsKeepsReservationAndIgnoresLateSettlement() {
        val admission=GatewayRecoveryAdmission();val old=admission.admit("restore","a".repeat(64));assertTrue(admission.picker(old));assertTrue(admission.picked(old));assertFalse(admission.cancel(old));refuse("gateway_recovery_busy") { admission.admit("export",null) }
        var mutations=0;var settlements=0
        fun queuedTransfer(ticket:GatewayRecoveryAdmission.Ticket) { admission.requireWork(ticket);mutations++ }
        refuse("gateway_recovery_cancelled") { queuedTransfer(old) };assertEquals(0,mutations);assertTrue(admission.complete(old));settlements++
        val next=admission.admit("export",null);assertFalse(next.cancelled.get());assertTrue(admission.picker(next));refuse("gateway_recovery_cancelled") { queuedTransfer(old) };if(admission.complete(old))settlements++
        assertEquals(0,mutations);assertEquals(1,settlements);assertTrue(admission.owns(next));assertFalse(admission.picked(old));assertTrue(admission.picked(next));queuedTransfer(next);assertEquals(1,mutations);assertTrue(admission.complete(next))
    }
    @Test fun cancelledPickerCannotReplaceLaterOperationHashOrCancellationIdentity() {
        val admission=GatewayRecoveryAdmission();val old=admission.admit("export",null);assertTrue(admission.picker(old));assertTrue(admission.cancel(old));assertTrue(admission.complete(old))
        val next=admission.admit("restore","b".repeat(64));assertTrue(admission.picker(next));assertFalse(admission.picked(old));assertFalse(admission.cancel(old));assertFalse(admission.complete(old));assertEquals("restore",next.operation);assertEquals("b".repeat(64),next.trustedManifest);assertFalse(next.cancelled.get());assertTrue(admission.owns(next));assertTrue(admission.cancel(next));assertTrue(admission.complete(next))
    }
    @Test fun occupiedTargetAndFilesystemSymlinkSourcesAreRefused() = fixture { f ->
        val target=imported(f,"occupied");target.mkdir();File(target,"keep").writeText("preserve");refuse { GatewayRecoveryTransfer.read(ByteArrayInputStream(byteArrayOf()),target) };assertEquals("preserve",File(target,"keep").readText())
        val a=archive(f);val first=File(a.directory,"objects").listFiles()!!.first();val original=File(f.root,"original-${f.id()}");first.renameTo(original);Files.createSymbolicLink(first.toPath(),original.toPath());refuse { GatewayRecoveryTransfer.write(a,ByteArrayOutputStream()) }
    }
    @Test fun recoveryWorkspaceRefusesLinkedRootParentAndDanglingParentWithoutExternalWrites() = fixture { f ->
        val external=File(f.root,"external").also { assertTrue(it.mkdir()) };File(external,"keep").writeText("preserve")
        val linkedRoot=File(f.root,"linked-root");Files.createSymbolicLink(linkedRoot.toPath(),external.toPath())
        refuse("gateway_recovery_invalid") { GatewayRecoveryStorage.workspace(linkedRoot) }
        val parent=File(f.root,"collect_gateway_recovery");Files.createSymbolicLink(parent.toPath(),external.toPath())
        refuse("gateway_recovery_invalid") { GatewayRecoveryStorage.workspace(f.root) };assertEquals(setOf("keep"),external.list()!!.toSet())
        assertTrue(parent.delete());Files.createSymbolicLink(parent.toPath(),File(f.root,"missing").toPath())
        refuse("gateway_recovery_invalid") { GatewayRecoveryStorage.workspace(f.root) };assertFalse(File(f.root,"missing").exists())
    }
    @Test fun freshWorkspacePreservesEarlierRunsAndRefusesOccupiedOrInvalidRunIds() = fixture { f ->
        val id=f.id();val prior=GatewayRecoveryStorage.workspace(f.root,id);File(prior,"original").writeText("retained")
        refuse("gateway_recovery_invalid") { GatewayRecoveryStorage.workspace(f.root,id) }
        refuse("gateway_recovery_invalid") { GatewayRecoveryStorage.workspace(f.root,"../outside") }
        val next=GatewayRecoveryStorage.workspace(f.root);assertNotEquals(prior,next);assertEquals("retained",File(prior,"original").readText())
    }
    @Test fun freeSpaceGuardChecksEachWriteAndRefusesUnavailableOrOverflowingCapacity() {
        val bytes=ByteArrayOutputStream();var available=GatewayRecoveryStorage.MIN_AVAILABLE_BYTES+3
        GatewayRecoveryStorage.guarded(bytes) { available }.use { output ->
            output.write(byteArrayOf(1,2,3));available=GatewayRecoveryStorage.MIN_AVAILABLE_BYTES
            refuse("gateway_recovery_storage_full") { output.write(4) };output.write(byteArrayOf(),0,0)
            available=Long.MIN_VALUE;refuse("gateway_recovery_storage_full") { output.write(5) }
            available=0;refuse("gateway_recovery_storage_full") { output.write(6) }
        };assertArrayEquals(byteArrayOf(1,2,3),bytes.toByteArray())
    }
    @Test fun rawImportSpaceRefusalPreservesExactPartialBytesAndActiveJournal() = fixture { f ->
        val before=f.directory.listFiles()!!.associate { it.name to it.readBytes() };val raw=ByteArray(8192) { (it%251).toByte() };var writes=0
        val target=imported(f,"low-space");refuse("gateway_recovery_storage_full") {
            GatewayRecoveryTransfer.read(ByteArrayInputStream(raw),target,available={ if(++writes==1)GatewayRecoveryStorage.MIN_AVAILABLE_BYTES+4096 else GatewayRecoveryStorage.MIN_AVAILABLE_BYTES })
        }
        assertArrayEquals(raw.copyOfRange(0,4096),File(target.parentFile,"source.collect-gateway").readBytes())
        assertTrue(File(target,"objects").list()!!.isEmpty());for((name,bytes) in before)assertArrayEquals(bytes,File(f.directory,name).readBytes())
        assertFalse(File(target,"SEALED.json").exists())
    }
    @Test fun exhaustedSpaceBeforeInputWriteRetainsEmptyCustodyAndNeverInterpretsInput() = fixture { f ->
        val target=imported(f,"empty-space");refuse("gateway_recovery_storage_full") {
            GatewayRecoveryTransfer.read(ByteArrayInputStream(framed(emptyList())),target,available={0})
        };assertEquals(0L,File(target.parentFile,"source.collect-gateway").length());assertTrue(File(target,"objects").list()!!.isEmpty())
    }
    @Test fun spaceExhaustionDuringExtractionPreservesRawOriginalWithoutSuccessfulResult() = fixture { f ->
        val raw=framed(listOf("objects/journal.bin" to byteArrayOf(1,2,3)));var checks=0;val target=imported(f,"extract-space")
        refuse("gateway_recovery_storage_full") {
            GatewayRecoveryTransfer.read(ByteArrayInputStream(raw),target,available={ if(++checks==1)GatewayRecoveryStorage.MIN_AVAILABLE_BYTES+raw.size else 0 })
        };assertArrayEquals(raw,File(target.parentFile,"source.collect-gateway").readBytes());assertEquals(0L,File(target,"manifest.ndjson").length())
        assertFalse(File(target,"SEALED.json").exists());assertTrue(File(target,"objects").list()!!.isEmpty())
    }
    @Test fun linkedImportParentAndInterruptedProviderCannotOverwriteOrLoseRetainedOriginals() = fixture { f ->
        val external=File(f.root,"external-import").also { assertTrue(it.mkdir()) };val link=File(f.root,"linked-import");Files.createSymbolicLink(link.toPath(),external.toPath())
        refuse("gateway_recovery_invalid") { GatewayRecoveryTransfer.read(ByteArrayInputStream(byteArrayOf(1)),File(link,"import")) };assertTrue(external.list()!!.isEmpty())
        var done=false;val source=object:InputStream() {
            override fun read():Int=throw UnsupportedOperationException()
            override fun read(bytes:ByteArray,offset:Int,length:Int):Int { if(done)throw IOException("synthetic provider interruption");done=true;bytes[offset]=42;return 1 }
        };val target=imported(f,"interrupted");refuse { GatewayRecoveryTransfer.read(source,target) }
        assertArrayEquals(byteArrayOf(42),File(target.parentFile,"source.collect-gateway").readBytes());assertTrue(File(target,"objects").list()!!.isEmpty())
    }
}
