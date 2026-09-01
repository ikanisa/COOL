import java.util.Properties
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Locale

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Native Android release intermediates are unreliable on the external project
// volume. Release automation may point this module at an internal APFS root
// while keeping the repository and the public `build/` path in place.
val collectAndroidBuildRoot =
    providers.environmentVariable("COLLECT_ANDROID_BUILD_ROOT").orNull
if (!collectAndroidBuildRoot.isNullOrBlank()) {
    layout.buildDirectory.set(file(collectAndroidBuildRoot).resolve("app"))
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
val expectedUploadSigningSha256 = (
    (keystoreProperties["COOL_EXPECTED_UPLOAD_SIGNING_SHA256"] as String?)
        ?: (findProperty("COOL_EXPECTED_UPLOAD_SIGNING_SHA256") as String?)
        ?: System.getenv("COOL_EXPECTED_UPLOAD_SIGNING_SHA256")
        ?: "9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10"
)?.normalizedSha256()
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
val releaseSigningMatchesExpectedUpload =
    expectedUploadSigningSha256 == null || releaseSigningSha256 == expectedUploadSigningSha256
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
        buildConfigField(
            "long",
            "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER",
            "${playIntegrityCloudProjectNumber}L",
        )
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
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    val productionReleaseTaskRequested = allTasks.any { task ->
        task.name.contains("ProductionRelease", ignoreCase = true)
    }
    val playInstalledOverwriteTaskRequested = allTasks.any { task ->
        signProductionDebugWithPlayKey && task.name.contains("ProductionDebug", ignoreCase = true)
    }
    if (productionReleaseTaskRequested || playInstalledOverwriteTaskRequested) {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Production Android signing requires android/key.properties or COOL_ANDROID_* environment variables " +
                    "pointing at the Google Play upload key."
            )
        }
        if (productionReleaseTaskRequested && !releaseSigningMatchesExpectedUpload) {
            throw GradleException(
                "Configured Android upload signing certificate SHA-256 $releaseSigningSha256 does not match " +
                    "the expected upload certificate SHA-256 $expectedUploadSigningSha256. " +
                    "Point android/key.properties or COOL_ANDROID_* environment variables at the registered Google Play upload key."
            )
        }
        if (playInstalledOverwriteTaskRequested && !releaseSigningMatchesPlay) {
            throw GradleException(
                "Configured Android signing certificate SHA-256 $releaseSigningSha256 does not match " +
                    "the expected Play app-signing certificate SHA-256 $expectedPlaySigningSha256. " +
                    "Set COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false for upload-key debug builds, or point signing at the Play app-signing/original release key for Play-installed package overwrite QA."
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.google.android.play:integrity:1.6.0")
    testImplementation("junit:junit:4.13.2")
}

// Firebase is configured only for the store/staging application IDs. Keep
// development and restricted-SMS QA variants buildable without inventing
// Firebase clients for package IDs that are not registered with the project.
tasks.configureEach {
    if (
        name.matches(
            Regex(
                "process(?:Dev|Internal_receiver)(?:Debug|Profile|Release)GoogleServices",
                RegexOption.IGNORE_CASE,
            ),
        )
    ) {
        enabled = false
    }
}

tasks.register("printReleaseSigningCertificateStatus") {
    group = "verification"
    description = "Print redacted production signing certificate status as JSON."

    fun jsonString(value: String?): String =
        if (value == null) {
            "null"
        } else {
            "\"" + value
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n") + "\""
        }

    doLast {
        val status = when {
            !hasReleaseSigning -> "blocked"
            !releaseSigningMatchesExpectedUpload -> "blocked"
            else -> "pass"
        }
        val message = when {
            !hasReleaseSigning -> "Production Android signing material is missing."
            !releaseSigningMatchesExpectedUpload -> "Configured Android signing certificate does not match the expected Google Play upload certificate."
            expectedUploadSigningSha256 == null -> "Configured Android upload signing material is present; upload certificate pinning is not configured."
            else -> "Configured Android signing certificate matches the expected Google Play upload certificate."
        }

        println(
            """
            {
              "status": ${jsonString(status)},
              "message": ${jsonString(message)},
              "store_file_configured": ${releaseStoreFileValue != null},
              "store_file_exists": ${releaseStoreFile?.exists() == true},
              "key_alias_configured": ${releaseKeyAlias != null},
              "store_password_configured": ${releaseStorePassword != null},
              "key_password_configured": ${releaseKeyPassword != null},
              "configured_certificate_sha256": ${jsonString(releaseSigningSha256)},
              "expected_upload_signing_sha256": ${jsonString(expectedUploadSigningSha256)},
              "matches_expected_upload_certificate": $releaseSigningMatchesExpectedUpload,
              "expected_play_signing_sha256": ${jsonString(expectedPlaySigningSha256)},
              "matches_expected_play_signing_certificate": $releaseSigningMatchesPlay,
              "play_app_signing_certificate_note": "Google Play App Signing uses the upload key for uploaded bundles and the Play app-signing key for APKs delivered to users.",
              "secret_handling": "This task prints certificate fingerprints and boolean configuration state only; it does not print keystore passwords or key aliases."
            }
            """.trimIndent()
        )
    }
}
