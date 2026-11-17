package rw.ikanisa.burimunsi

import android.content.ComponentName
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.cool.mobile.BuildConfig
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.gateway.GatewayFactory
import rw.ikanisa.burimunsi.storage.DeviceProvisioning
import rw.ikanisa.burimunsi.storage.SecureStore
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.InstallationEnrollmentSource
import rw.ikanisa.burimunsi.core.InstallationGrant
import rw.ikanisa.burimunsi.data.ManagedCollectBroker
import rw.ikanisa.burimunsi.ui.BuriViewModel

/** Installed-package assertions; no production account, SMS, backend or test bypass. */
@RunWith(AndroidJUnit4::class)
class NativeSandboxContractTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun memberPhotoCaptureUsesOnlyPrivateProviderAndSystemGrants(){
        @Suppress("DEPRECATION") val info=context.packageManager.getPackageInfo(context.packageName,PackageManager.GET_PROVIDERS or PackageManager.GET_PERMISSIONS)
        val provider=info.providers.orEmpty().single{it.authority==context.packageName+".member-photo"}
        assertFalse(provider.exported);assertTrue(provider.grantUriPermissions)
        val broad=setOf("android.permission.CAMERA","android.permission.READ_MEDIA_IMAGES","android.permission.READ_EXTERNAL_STORAGE","android.permission.WRITE_EXTERNAL_STORAGE")
        assertTrue(info.requestedPermissions.orEmpty().none{it in broad})
        val files=MemberPhotoFiles(context.cacheDir);val file=files.create()
        try{
            val uri=memberPhotoUri(context,file)
            assertEquals("content",uri.scheme)
            context.contentResolver.openOutputStream(uri,"w")!!.use{it.write(byteArrayOf(1,2,3))}
            assertArrayEquals(byteArrayOf(1,2,3),file.readBytes())
            val intent=MemberPhotoCaptureContract().createIntent(context,uri)
            assertEquals(android.provider.MediaStore.ACTION_IMAGE_CAPTURE,intent.action)
            @Suppress("DEPRECATION") val output:android.net.Uri?=intent.getParcelableExtra(android.provider.MediaStore.EXTRA_OUTPUT)
            assertEquals(uri,output);assertEquals(uri,intent.clipData!!.getItemAt(0).uri)
            assertTrue(intent.flags and android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION!=0)
            try{memberPhotoUri(context,context.filesDir.resolve("outside-member-photo.jpg"));fail("Unscoped file was shared")}
            catch(_:IllegalArgumentException){}
        }finally{assertTrue(files.remove(file.name))}
    }

    @Test fun memberPhotoPreparationResizesRotatesAndWipesInput(){
        val original=android.graphics.Bitmap.createBitmap(3200,1800,android.graphics.Bitmap.Config.ARGB_8888)
        val source=java.io.ByteArrayOutputStream().use{out->original.compress(android.graphics.Bitmap.CompressFormat.JPEG,95,out);out.toByteArray()}
        original.recycle()
        val result=prepareMemberPhoto(source)
        assertTrue(source.all{it==0.toByte()});assertTrue(result.size in 1..5*1024*1024)
        val bitmap=android.graphics.BitmapFactory.decodeByteArray(result,0,result.size)
        try{assertTrue(maxOf(bitmap.width,bitmap.height)<=2560)}finally{bitmap.recycle();result.fill(0)}
        val files=MemberPhotoFiles(context.cacheDir);val capture=files.create()
        try{
            val portrait=android.graphics.Bitmap.createBitmap(72,120,android.graphics.Bitmap.Config.ARGB_8888)
            capture.outputStream().use{portrait.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it)};portrait.recycle()
            android.media.ExifInterface(capture.absolutePath).apply{
                setAttribute(android.media.ExifInterface.TAG_ORIENTATION,android.media.ExifInterface.ORIENTATION_ROTATE_90.toString());saveAttributes()
            }
            val upright=prepareMemberPhoto(capture.readBytes())
            val rotated=android.graphics.BitmapFactory.decodeByteArray(upright,0,upright.size)
            try{assertEquals(120,rotated.width);assertEquals(72,rotated.height)}finally{rotated.recycle();upright.fill(0)}
        }finally{assertTrue(files.remove(capture.name))}
    }

    @Test fun concurrentSecureStoreInstancesShareOneAtomicFileSafely() {
        val name="concurrency-"+java.util.UUID.randomUUID().toString()
        val stores=(0 until 4).map{SecureStore(context,name)}
        val values=(0 until 4).map{"synthetic-$it-"+"x".repeat(4096)}
        val startSignal=java.util.concurrent.CountDownLatch(1)
        val failures=java.util.concurrent.ConcurrentLinkedQueue<Throwable>()
        stores.first().write(values.first())
        try{
            val workers=stores.mapIndexed{index,store->Thread{
                try{startSignal.await();repeat(30){store.write(values[index]);val value=store.read();check(value!=null&&value in values)}}
                catch(error:Throwable){failures.add(error)}
            }.apply{start()}}
            startSignal.countDown();workers.forEach{it.join(20_000)}
            assertTrue("All secure-store workers finished",workers.none{it.isAlive})
            assertTrue("Concurrent atomic-file reads and writes succeeded",failures.isEmpty())
            val finalValue=stores.last().read()
            assertTrue(finalValue!=null&&finalValue in values)
            val bytes=context.noBackupFilesDir.resolve("buri-$name.v1").readBytes().toString(Charsets.ISO_8859_1)
            assertTrue(values.none{bytes.contains(it)})
        }finally{stores.first().clear()}
    }

    @Test fun installationUsesOnlyDedicatedSandboxIdentity() {
        val role=if(BuildConfig.IS_GATEWAY) "gateway" else "staff"
        assertEquals("rw.ikanisa.burimunsi.$role.cloud.nativeTest", context.packageName)
        assertEquals("nativeTest", BuildConfig.BUILD_TYPE)
        assertTrue(BuildConfig.DEBUG)
        assertTrue(BuildConfig.IS_QUALIFICATION)
    }
    @Test fun setupUsesTheExistingPersistedInstallationIdentity() {
        val supplied=GatewayFactory.installationId(context)
        val persisted=DeviceProvisioning(context,supplied).installationId
        assertTrue(Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}").matches(persisted))
        assertEquals(persisted,DeviceProvisioning(context,GatewayFactory.installationId(context)).installationId)
        if(BuildConfig.IS_GATEWAY)assertEquals(supplied,persisted)
        else assertEquals(SecureStore(context,"installation").read(),persisted)
        // Offline sandbox has no API origin, so model never reads a token or starts HTTP.
        val model=BuriViewModel(context.applicationContext as android.app.Application)
        assertEquals(persisted,model.installationId)
        assertEquals(if(BuildConfig.IS_GATEWAY)"internal_receiver" else "staff",model.installationProfile)
        assertTrue(model.state.configurationRequired)
    }
    @Test fun localSetupIsEncryptedOutsideBackupAndClearPreservesOtherCustody() {
        val device=DeviceProvisioning(context,GatewayFactory.installationId(context))
        val store=SecureStore(context,"installation-grant")
        val sentinel=SecureStore(context,"enrollment-test-sentinel")
        val token="a".repeat(64)
        store.clear();sentinel.write("synthetic-independent-custody")
        val originalId=device.installationId
        try{
            assertEquals(InstallationEnrollmentSource.MISSING,device.status().source)
            device.saveLocalToken(token)
            assertEquals(token,device.token())
            assertEquals(InstallationEnrollmentSource.LOCAL,device.status().source)
            val file=context.noBackupFilesDir.resolve("buri-installation-grant.v1")
            assertTrue(file.isFile)
            assertFalse(file.readBytes().toString(Charsets.ISO_8859_1).contains(token))
            assertFalse(context.filesDir.resolve(file.name).exists())
            try{device.saveLocalToken("b".repeat(64));fail("Existing enrollment must not be silently replaced")}
            catch(_:ContractFailure){/* Explicit local clear is required. */}
            device.clearLocalToken()
            assertFalse(file.exists())
            assertEquals(InstallationEnrollmentSource.MISSING,device.status().source)
            assertEquals(originalId,DeviceProvisioning(context,GatewayFactory.installationId(context)).installationId)
            // This store shares the existing Keystore alias. It must remain
            // decryptable: enrollment clear may delete only its own file.
            assertEquals("synthetic-independent-custody",sentinel.read())
            try{device.token();fail("Missing grant cannot authorize a token")}
            catch(_:ContractFailure){/* No local authentication fallback. */}
        }finally{store.clear();sentinel.clear()}
    }
    @Test fun savedSessionCanBeReopenedAndExplicitlyCleared() {
        val name="session-persistence-test"
        val original=SecureStore(context,name)
        val bearer="c".repeat(64)
        val value="{\"token\":\"$bearer\",\"expiresAt\":123456789}"
        original.clear()
        try{
            original.write(value)
            val encrypted=context.noBackupFilesDir.resolve("buri-$name.v1")
            assertTrue(encrypted.isFile)
            assertFalse(encrypted.readBytes().toString(Charsets.ISO_8859_1).contains(bearer))
            val recreated=SecureStore(context,name)
            assertEquals(value,recreated.read())
            recreated.clear()
            assertNull(SecureStore(context,name).read())
        }finally{original.clear()}
    }
    @Test fun localSetupRejectsAnotherInstallationAndAllowsOnlyExplicitFileRecovery() {
        val device=DeviceProvisioning(context,GatewayFactory.installationId(context))
        val store=SecureStore(context,"installation-grant")
        val other=if(device.installationId=="10000000-0000-4000-8000-000000000001")
            "10000000-0000-4000-8000-000000000002" else "10000000-0000-4000-8000-000000000001"
        store.clear()
        try{
            store.write(InstallationGrant.create(other,"a".repeat(64)).localRecord())
            assertEquals(InstallationEnrollmentSource.LOCAL_BLOCKED,device.status().source)
            try{device.token();fail("Saved grant for another installation must be rejected")}
            catch(_:ContractFailure){/* Must never select the other identity. */}
            device.clearLocalToken()
            assertEquals(InstallationEnrollmentSource.MISSING,device.status().source)
            assertEquals(device.installationId,DeviceProvisioning(context,GatewayFactory.installationId(context)).installationId)
        }finally{store.clear()}
    }
    @Test fun brokerLocalSetupDoesNotCreateSessionOrReplaceInstallation() {
        val store=SecureStore(context,"installation-grant");store.clear()
        val originalId=DeviceProvisioning(context,GatewayFactory.installationId(context)).installationId
        try{
            val broker=ManagedCollectBroker(context)
            assertFalse(broker.status.value.signedIn)
            broker.savePhoneSetup("a".repeat(64))
            assertEquals(InstallationEnrollmentSource.LOCAL,broker.status.value.enrollment.source)
            assertFalse(broker.status.value.signedIn)
            assertNull(broker.currentCollectionId())
            broker.clearPhoneSetup()
            assertEquals(InstallationEnrollmentSource.MISSING,broker.status.value.enrollment.source)
            assertFalse(broker.status.value.signedIn)
            assertEquals(originalId,DeviceProvisioning(context,GatewayFactory.installationId(context)).installationId)
        }finally{store.clear()}
    }
    @Test fun installedSandboxHasNoInternetBackupOrCleartext() {
        @Suppress("DEPRECATION")
        val info=context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        assertFalse(info.requestedPermissions.orEmpty().contains("android.permission.INTERNET"))
        val flags=context.applicationInfo.flags
        assertTrue(flags and ApplicationInfo.FLAG_TEST_ONLY != 0)
        assertEquals(0, flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
        assertEquals(0, flags and ApplicationInfo.FLAG_USES_CLEARTEXT_TRAFFIC)
    }
    @Test fun compiledConfigurationContainsNoLiveEndpointOrBinding() {
        for(value in listOf(BuildConfig.BURI_API_ORIGIN, BuildConfig.BURI_AUTH_ORIGIN, BuildConfig.BURI_ADMIN_ORIGIN, BuildConfig.BURI_API_PATH_PREFIX, BuildConfig.COLLECT_API_HOST,
            BuildConfig.COLLECT_API_PATH_PREFIX, BuildConfig.COLLECT_PUBLISHABLE_KEY,
            BuildConfig.RECEIVER_API_BASE_URL, BuildConfig.COLLECT_RECEIVER_API_BASE_URL)) assertEquals("", value)
    }
    @Test fun launcherActivityBelongsToSandbox() {
        @Suppress("DEPRECATION")
        val activity=context.packageManager.getActivityInfo(ComponentName(context, MainActivity::class.java), 0)
        assertEquals(context.packageName, activity.packageName)
        assertTrue(activity.exported)
        assertNotNull(context.packageManager.getLaunchIntentForPackage(context.packageName))
    }
    @Test fun gatewayCannotBindOrResumeInSandbox() {
        val gateway=GatewayFactory.create(context)
        assertFalse(gateway.bound())
        gateway.start() // Both flavors must remain unbound; this must not start live collection.
        assertFalse(gateway.bound())
        for(action in listOf<()->Unit>({gateway.pair("synthetic-test-only")}, {gateway.setPaused(false)})) {
            try { action(); fail("Sandbox must reject gateway activation") }
            catch (_: IllegalStateException) { /* Expected fail-closed behavior. */ }
        }
    }
}
