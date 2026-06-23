import java.util.Properties
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Locale

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
fun signingEnvName(name: String): String =
    "COOL_ANDROID_" + name
        .replace(Regex("([a-z])([A-Z])"), "$1_$2")
        .uppercase(Locale.US)

fun signingValue(name: String): String? =
    (keystoreProperties[name] as String?)
        ?: (findProperty(name) as String?)
        ?: System.getenv(signingEnvName(name))

fun String.normalizedSha256(): String = replace(":", "").uppercase(Locale.US)

fun certificateSha256(storeFile: File, storePassword: String, keyAlias: String): String {
    val password = storePassword.toCharArray()
    val loadErrors = mutableListOf<String>()
    for (storeType in listOf("JKS", "PKCS12")) {
        try {
            val keyStore = KeyStore.getInstance(storeType)
            storeFile.inputStream().use { keyStore.load(it, password) }
            val certificate = keyStore.getCertificate(keyAlias)
                ?: error("alias '$keyAlias' was not found")
            val digest = MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
            return digest.joinToString("") { "%02X".format(it) }
        } catch (error: Exception) {
            loadErrors += "$storeType: ${error.message}"
        }
    }
    throw GradleException("Unable to read Android signing certificate from ${storeFile.path}: ${loadErrors.joinToString("; ")}")
}

val expectedPlaySigningSha256 = (
    (keystoreProperties["COOL_EXPECTED_PLAY_SIGNING_SHA256"] as String?)
        ?: (findProperty("COOL_EXPECTED_PLAY_SIGNING_SHA256") as String?)
        ?: System.getenv("COOL_EXPECTED_PLAY_SIGNING_SHA256")
        ?: "45:17:38:E6:9A:DF:1B:4D:3F:AA:7A:65:90:20:28:2E:02:7B:47:86:26:71:C9:FC:32:45:AF:82:2B:4D:2A:92"
).normalizedSha256()
val releaseStoreFileValue = signingValue("storeFile")
val releaseStoreFile = releaseStoreFileValue?.let { value ->
    val moduleRelative = file(value)
    val androidRootRelative = rootProject.file(value)
    when {
        moduleRelative.exists() -> moduleRelative
        androidRootRelative.exists() -> androidRootRelative
        else -> moduleRelative
    }
}
val releaseKeyAlias = signingValue("keyAlias")
val releaseStorePassword = signingValue("storePassword")
val releaseKeyPassword = signingValue("keyPassword")
val hasReleaseSigning =
    releaseStoreFile?.exists() == true &&
        releaseKeyAlias != null &&
        releaseStorePassword != null &&
        releaseKeyPassword != null
val releaseSigningSha256 = if (hasReleaseSigning) {
    certificateSha256(releaseStoreFile!!, releaseStorePassword!!, releaseKeyAlias!!)
} else {
    null
}
val releaseSigningMatchesPlay = releaseSigningSha256 == expectedPlaySigningSha256
val signProductionDebugWithPlayKey = (
    (keystoreProperties["COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY"] as String?)
        ?: (findProperty("COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY") as String?)
        ?: System.getenv("COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY")
        ?: "true"
).toBoolean()

val playIntegrityCloudProjectNumber =
    (
        (findProperty("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER") as String?)
            ?: System.getenv("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER")
            ?: "-1"
    ).ifBlank { "-1" }

android {
    namespace = "app.cool.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "app.cool.mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("long", "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", "${playIntegrityCloudProjectNumber}L")
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                keyAlias = releaseKeyAlias!!
                keyPassword = releaseKeyPassword!!
                storeFile = releaseStoreFile!!
                storePassword = releaseStorePassword!!
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            if (hasReleaseSigning && releaseSigningMatchesPlay && signProductionDebugWithPlayKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    flavorDimensions += "channel"
    productFlavors {
        create("dev") {
            dimension = "channel"
            applicationIdSuffix = ".dev"
        }
        create("internal_receiver") {
            dimension = "channel"
            applicationIdSuffix = ".receiver"
            manifestPlaceholders["enableSmsReceiver"] = true
        }
        create("production") {
            dimension = "channel"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

gradle.taskGraph.whenReady {
    val productionSigningTaskRequested = gradle.startParameter.taskNames.any { taskName ->
        taskName.contains("ProductionRelease", ignoreCase = true) ||
            (
                signProductionDebugWithPlayKey &&
                    taskName.contains("ProductionDebug", ignoreCase = true)
            )
    }
    if (productionSigningTaskRequested) {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Production Android signing requires android/key.properties or COOL_ANDROID_* environment variables " +
                    "pointing at the Play app-signing/original release key."
            )
        }
        if (!releaseSigningMatchesPlay) {
            throw GradleException(
                "Configured Android signing certificate SHA-256 $releaseSigningSha256 does not match " +
                    "the expected Play app-signing certificate SHA-256 $expectedPlaySigningSha256. " +
                    "Point android/key.properties or COOL_ANDROID_* environment variables at the Play app-signing/original release key."
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.play:integrity:1.6.0")
}
