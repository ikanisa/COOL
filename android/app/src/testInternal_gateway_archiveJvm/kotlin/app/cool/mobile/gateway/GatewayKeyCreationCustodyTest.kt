package app.cool.mobile.gateway

import android.content.Context
import android.util.AtomicFileFaults
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.security.Signature
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GatewayKeyCreationCustodyTest {
    private val certificate = "c".repeat(64)
    private class LocalContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }
    private class Fixture : AutoCloseable {
        val root = Files.createTempDirectory("collect-key-custody-").toFile()
        val directory = File(root, "collect_gateway_v1")
        val context = LocalContext(root)
        val identity = GatewayDeviceIdentity()
        val store get() = GatewayEncryptedStore(context)
        init { GatewaySyntheticKeyStore.install(); GatewaySyntheticKeyStore.reset() }
        override fun close() { GatewaySyntheticKeyStore.remove(); root.deleteRecursively(); AtomicFileFaults.failFileOnce = null; AtomicFileFaults.failFinishOnce = false; android.system.OsFaults.failFsyncOnce = false }
        fun bytes() = directory.listFiles()!!.associate { it.name to it.readBytes() }
        fun same(before: Map<String, ByteArray>) { assertEquals(before.keys, directory.list()!!.toSet()); for ((name, value) in before) assertArrayEquals(name, value, File(directory, name).readBytes()) }
    }
    private fun fixture(action: (Fixture) -> Unit) { Fixture().use(action) }
    private fun refuse(action: () -> Unit) { try { action(); fail("Expected refusal") } catch (_: Exception) { } }
    private fun generations(signing: Int, storage: Int) { assertEquals(signing, GatewaySyntheticKeyStore.signingGenerations); assertEquals(storage, GatewaySyntheticKeyStore.storageGenerations) }

    @Test fun actualFirstInitializationPublishesCustodyBeforeGeneratorsAndKeepsSameIdentityOnRestart() { fixture { f ->
        GatewaySyntheticKeyStore.beforeGeneration = { alias ->
            val name = if (alias == GatewayKeyCreationCustody.SIGNING_ALIAS) GatewayKeyCreationCustody.SIGNING else GatewayKeyCreationCustody.STORAGE
            val record = JSONObject(File(f.directory, name).readText()); assertEquals("generation_entered", record.getString("state")); assertEquals(alias, record.getString("alias"))
            if (alias == GatewayKeyCreationCustody.STORAGE_ALIAS) assertTrue(File(f.directory, GatewayKeyCreationCustody.IDENTITY).isFile)
        }
        val original = f.store.initializeIdentity(f.identity, certificate)
        val signing = JSONObject(File(f.directory, GatewayKeyCreationCustody.SIGNING).readText())
        assertEquals(signing.getString("installation_id"), original.getString("installation_id"))
        generations(1, 1); val before = f.bytes()
        assertTrue(archiveJsonEqual(original, f.store.initializeIdentity(GatewayDeviceIdentity(), certificate))); f.same(before); generations(1, 1)
        val bytes = "Exact synthetic original request".toByteArray()
        val signature = java.util.Base64.getDecoder().decode(f.identity.signExact(bytes))
        val publicKey = java.security.KeyFactory.getInstance("EC").generatePublic(java.security.spec.X509EncodedKeySpec(f.identity.publicKeyBytes()))
        assertTrue(Signature.getInstance("SHA256withECDSA").run { initVerify(publicKey); update(bytes); verify(signature) })
    } }
    @Test fun lostSigningAliasAfterInitializationNeverRegeneratesOrChangesEvidence() { fixture { f ->
        f.store.initializeIdentity(f.identity, certificate); val before = f.bytes(); GatewaySyntheticKeyStore.lose(GatewayKeyCreationCustody.SIGNING_ALIAS)
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1); f.same(before)
    } }
    @Test fun lostStorageAliasAfterInitializationNeverRegeneratesOrChangesEvidence() { fixture { f ->
        f.store.initializeIdentity(f.identity, certificate); val before = f.bytes(); GatewaySyntheticKeyStore.lose(GatewayKeyCreationCustody.STORAGE_ALIAS)
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1); f.same(before)
    } }
    @Test fun generatorThrowBeforeSigningCreationRetainsEnteredOriginalAndRefusesRestart() { fixture { f ->
        GatewaySyntheticKeyStore.failBeforeGeneration = GatewayKeyCreationCustody.SIGNING_ALIAS
        refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(1, 0); val before = f.bytes()
        assertEquals(setOf(GatewayKeyCreationCustody.SIGNING), before.keys)
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 0); f.same(before)
    } }
    @Test fun generatorThrowAfterSigningCreationAllowsOnlyOriginalAliasLookupAndInitialPublication() { fixture { f ->
        GatewaySyntheticKeyStore.failAfterGeneration = GatewayKeyCreationCustody.SIGNING_ALIAS
        refuse { f.store.initializeIdentity(f.identity, certificate) }; val original = File(f.directory, GatewayKeyCreationCustody.SIGNING).readBytes()
        val result = f.store.initializeIdentity(GatewayDeviceIdentity(), certificate); generations(1, 1)
        assertArrayEquals(original, File(f.directory, GatewayKeyCreationCustody.SIGNING).readBytes())
        assertEquals(JSONObject(String(original)).getString("installation_id"), result.getString("installation_id"))
    } }
    @Test fun generatorThrowBeforeStorageCreationRefusesAnotherGenerationAndMetadataRewrite() { fixture { f ->
        GatewaySyntheticKeyStore.failBeforeGeneration = GatewayKeyCreationCustody.STORAGE_ALIAS
        refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(1, 1); val before = f.bytes()
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1); f.same(before)
        refuse { f.store.saveIdentityMetadata(JSONObject()) }; generations(1, 1); f.same(before)
    } }
    @Test fun generatorThrowAfterStorageCreationPreservesUnknownIdentityPublicationAndDoesNotRecreateIt() { fixture { f ->
        GatewaySyntheticKeyStore.failAfterGeneration = GatewayKeyCreationCustody.STORAGE_ALIAS
        refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(1, 1); val before = f.bytes()
        assertTrue(GatewaySyntheticKeyStore.aliasNames().contains(GatewayKeyCreationCustody.STORAGE_ALIAS))
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1); f.same(before)
    } }
    @Test fun lostOriginalMetadataCannotCreateAnotherInstallationUuid() { fixture { f ->
        f.store.initializeIdentity(f.identity, certificate); assertTrue(File(f.directory, "identity.bin").delete()); val before = f.bytes()
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1); f.same(before)
    } }
    @Test fun interruptedIdentityAtomicPublicationStaysUnknownAcrossRestart() { fixture { f ->
        AtomicFileFaults.failFileOnce = "identity.bin"; refuse { f.store.initializeIdentity(f.identity, certificate) }
        val before = f.bytes(); assertTrue(before.containsKey(GatewayKeyCreationCustody.IDENTITY)); assertFalse(before.containsKey("identity.bin"))
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1); f.same(before)
    } }
    @Test fun failedCustodyPublicationCannotInvokeGeneratorAndOnlyFreshPreEntryRetryIsPermitted() { fixture { f ->
        AtomicFileFaults.failFileOnce = GatewayKeyCreationCustody.SIGNING; refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(0, 0)
        assertTrue(f.directory.list()!!.isEmpty()); f.store.initializeIdentity(GatewayDeviceIdentity(), certificate); generations(1, 1)
    } }
    @Test fun corruptOrPartialCustodyNeverBecomesFresh() { fixture { f ->
        f.directory.mkdirs(); val partial = File(f.directory, GatewayKeyCreationCustody.SIGNING + ".new"); partial.writeText("{\"state\":\"partial\"}"); val before = f.bytes()
        refuse { f.store.initializeIdentity(f.identity, certificate) }; refuse { f.store.saveIdentityMetadata(JSONObject()) }; generations(0, 0); f.same(before)
    } }
    @Test fun opaqueRetainedCiphertextAndUnknownRegularHistoryDenyFreshKeys() { fixture { f ->
        f.directory.mkdirs(); File(f.directory, "enrollment.bin").writeBytes(byteArrayOf(1, 2, 3)); File(f.directory, "unknown.bin").writeBytes(byteArrayOf(4)); val before = f.bytes()
        refuse { f.store.initializeIdentity(f.identity, certificate) }; refuse { f.store.saveIdentityMetadata(JSONObject()) }; generations(0, 0); f.same(before)
    } }
    @Test fun retainedDirectoryAndSymlinkDenyMissingStorageKeyRatherThanNullableFreshnessInference() { fixture { f ->
        f.directory.mkdirs(); val child = File(f.directory, "retained-directory"); child.mkdir()
        refuse { f.store.saveIdentityMetadata(JSONObject()) }; generations(0, 0); assertTrue(child.isDirectory)
        child.delete(); val opaque = File(f.root, "opaque").also { it.writeBytes(byteArrayOf(9)) }
        val link = File(f.directory, "opaque.bin"); Files.createSymbolicLink(link.toPath(), opaque.toPath())
        refuse { f.store.initializeIdentity(f.identity, certificate) }; refuse { f.store.saveIdentityMetadata(JSONObject()) }; generations(0, 0); assertTrue(Files.isSymbolicLink(link.toPath())); assertArrayEquals(byteArrayOf(9), opaque.readBytes())
    } }
    @Test fun retainedSigningAliasWithoutProspectiveCustodyCannotInitializeStorageOrNewMetadata() { fixture { f ->
        GatewaySyntheticKeyStore.legacySigning(); refuse { f.store.initializeIdentity(f.identity, certificate) }; refuse { f.store.saveIdentityMetadata(JSONObject()) }; generations(0, 0)
        assertTrue(f.directory.list()!!.isEmpty())
    } }
    @Test fun retainedStorageAliasCannotAuthorizeReplacementSigningKey() { fixture { f ->
        GatewaySyntheticKeyStore.legacyStorage(); refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(0, 0)
        assertEquals(setOf(GatewayKeyCreationCustody.STORAGE_ALIAS), GatewaySyntheticKeyStore.aliasNames()); assertTrue(f.directory.list()!!.isEmpty())
    } }
    @Test fun legacyExistingIdentityAndKeysRemainLookupOnlyWithoutNewCustody() { fixture { f ->
        GatewaySyntheticKeyStore.legacySigning(); GatewaySyntheticKeyStore.legacyStorage()
        val original = JSONObject().put("contract_version", 1).put("installation_id", "ad760000-0000-4000-8000-000000000004")
            .put("key_sha256", f.identity.keyId()).put("public_key_spki_base64", f.identity.publicKeyBase64()).put("signing_certificate_sha256", certificate)
        f.store.saveIdentityMetadata(original); val before = f.bytes()
        assertTrue(archiveJsonEqual(original, f.store.initializeIdentity(GatewayDeviceIdentity(), certificate))); generations(0, 0); f.same(before)
    } }
    @Test fun changedCertificateAndDamagedProspectiveInstallationBindingNeverOverwriteIdentity() { fixture { f ->
        f.store.initializeIdentity(f.identity, certificate); val before = f.bytes()
        refuse { f.store.initializeIdentity(f.identity, "d".repeat(64)) }; generations(1, 1); f.same(before)
        val marker = File(f.directory, GatewayKeyCreationCustody.STORAGE); val value = JSONObject(marker.readText()).put("installation_id", "ad760000-0000-4000-8000-000000000007"); marker.writeText(value.toString()); val damaged = f.bytes()
        refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(1, 1); f.same(damaged)
    } }
    @Test fun concurrentActualInitializersShareOneIdentityAndExactlyOneOfEachGenerator() { fixture { f ->
        val latch = CountDownLatch(1); val executor = Executors.newFixedThreadPool(2)
        try {
            val calls = (0..1).map { executor.submit<JSONObject> { latch.await(); f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) } }
            latch.countDown(); val values = calls.map { it.get(10, TimeUnit.SECONDS) }; assertTrue(archiveJsonEqual(values[0], values[1])); generations(1, 1)
        } finally { executor.shutdownNow() }
    } }
    @Test fun publicCustodyAndEncryptedIdentityRestoreExactInactiveWithoutKeyGeneration() { fixture { f ->
        val original = f.store.initializeIdentity(f.identity, certificate); val before = f.bytes()
        val archive = f.store.exportRecovery(File(f.root, "archive")); val result = f.store.restoreRecovery(archive.directory, archive.manifestSha256, File(f.root, "restore"))
        assertTrue(result.keyValidated); assertTrue(result.requiresReEnrollment); generations(1, 1); f.same(before)
        for ((name, bytes) in before) assertArrayEquals(name, bytes, File(result.directory, "original/$name").readBytes())
        assertTrue(File(result.directory, "view/${GatewayRecovery.INACTIVE}").isFile)
        val view = File(result.directory, "view"); val restored = File(result.directory, "collect_gateway_v1"); assertTrue(view.renameTo(restored))
        val inactive = GatewayEncryptedStore(LocalContext(result.directory)); refuse { inactive.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1)
        assertEquals(original.getString("installation_id"), JSONObject(File(restored, GatewayKeyCreationCustody.SIGNING).readText()).getString("installation_id"))
    } }
    @Test fun missingStorageKeyRecoveryRetainsExactOpaqueCiphertextAndPublicCustodyButDoesNotValidateKeys() { fixture { f ->
        f.store.initializeIdentity(f.identity, certificate); val before = f.bytes(); GatewaySyntheticKeyStore.lose(GatewayKeyCreationCustody.STORAGE_ALIAS)
        val archive = f.store.exportRecovery(File(f.root, "archive")); val result = f.store.restoreRecovery(archive.directory, archive.manifestSha256, File(f.root, "restore"))
        assertFalse(result.keyValidated); assertTrue(result.requiresReEnrollment); generations(1, 1); f.same(before)
        for ((name, bytes) in before) assertArrayEquals(name, bytes, File(result.directory, "original/$name").readBytes())
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(1, 1); f.same(before)
    } }
    @Test fun failedDirectoryFsyncAfterEnteredPublicationNeverCallsGeneratorOrRegeneratesOnRestart() { fixture { f ->
        android.system.OsFaults.failFsyncOnce = true; refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(0, 0)
        val before = f.bytes(); assertEquals(setOf(GatewayKeyCreationCustody.SIGNING), before.keys)
        refuse { f.store.initializeIdentity(GatewayDeviceIdentity(), certificate) }; generations(0, 0); f.same(before)
    } }
    @Test fun oversizedOrExtraFieldMarkerIsRejectedByBoundedStrictReaderWithoutGeneration() { fixture { f ->
        f.directory.mkdirs(); val marker = File(f.directory, GatewayKeyCreationCustody.SIGNING)
        marker.writeBytes(ByteArray(2049) { 32 }); val before = f.bytes(); refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(0, 0); f.same(before)
        marker.writeText(JSONObject().put("contract_version", 1).put("key_realm", "collect_gateway_v1").put("state", "generation_entered")
            .put("installation_id", "ad760000-0000-4000-8000-000000000004").put("alias", GatewayKeyCreationCustody.SIGNING_ALIAS).put("authority", true).toString())
        val extra = f.bytes(); refuse { f.store.initializeIdentity(f.identity, certificate) }; generations(0, 0); f.same(extra)
    } }
    @Test fun inactiveValidationRejectsPublicIdentityDigestMismatchWhilePreservingRawOriginals() { fixture { f ->
        f.store.initializeIdentity(f.identity, certificate)
        val marker = File(f.directory, GatewayKeyCreationCustody.IDENTITY); marker.writeText(JSONObject(marker.readText()).put("identity_sha256", "e".repeat(64)).toString())
        val before = f.bytes(); val archive = f.store.exportRecovery(File(f.root, "archive")); val destination = File(f.root, "restore")
        refuse { f.store.restoreRecovery(archive.directory, archive.manifestSha256, destination) }; generations(1, 1); f.same(before)
        for ((name, bytes) in before) assertArrayEquals(name, bytes, File(destination, "original/$name").readBytes())
        assertTrue(File(destination, GatewayRecovery.INACTIVE).isFile); assertFalse(File(destination, "SEALED.json").exists())
    } }

}
