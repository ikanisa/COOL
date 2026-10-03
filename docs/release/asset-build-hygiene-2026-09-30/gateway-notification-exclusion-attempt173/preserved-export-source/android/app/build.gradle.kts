import java.util.Properties
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Locale
import java.nio.file.Files
import org.gradle.api.artifacts.dsl.LockMode
import org.gradle.api.artifacts.ProjectDependency
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

abstract class CollectVariantPluginRegistrant : DefaultTask() {
    @get:InputDirectory
    abstract val originalJavaDirectory: DirectoryProperty

    @get:InputFile
    abstract val adapterSource: RegularFileProperty

    @get:Input
    abstract val omitNotifications: Property<Boolean>

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val originalDirectory = originalJavaDirectory.get().asFile
        val original = originalDirectory.resolve("io/flutter/plugins/GeneratedPluginRegistrant.java")
        val files = originalDirectory.walkTopDown().filter { it.isFile }.toList()
        check(files == listOf(original) && !Files.isSymbolicLink(original.toPath())) {
            "Collect registrant adapter requires main/java to contain only the regular tool-generated registrant"
        }
        check(originalDirectory.walkTopDown().none { Files.isSymbolicLink(it.toPath()) }) {
            "Collect registrant adapter refuses aliased main/java input"
        }
        val output = outputDirectory.get().asFile.resolve("io/flutter/plugins/GeneratedPluginRegistrant.java")
        val javaExecutable = File(System.getProperty("java.home"), "bin/java")
        val process = ProcessBuilder(
            javaExecutable.absolutePath, "--source", "17", adapterSource.get().asFile.absolutePath,
            original.absolutePath, output.absolutePath, omitNotifications.get().toString(),
        ).inheritIO().start()
        check(process.waitFor() == 0) { "Collect generated registrant adapter refused an unknown input" }
    }
}

// Native Android release intermediates are unreliable on the external project
// volume. Release automation may point this module at an internal APFS root
// while keeping the repository and the public `build/` path in place.
val collectAndroidBuildRoot =
    providers.environmentVariable("COLLECT_ANDROID_BUILD_ROOT").orNull
if (!collectAndroidBuildRoot.isNullOrBlank()) {
    layout.buildDirectory.set(file(collectAndroidBuildRoot).resolve("app"))
}

// Explicit source-only QA exports may build an unsigned production-flavour
// artifact without private provider/signing inputs. Default store builds retain
// their signing checks. The QA marker is packaged and separately verified.
val collectUnsignedLocalQaRaw = providers.gradleProperty("collectUnsignedLocalQa").orNull
require(collectUnsignedLocalQaRaw == null || collectUnsignedLocalQaRaw in setOf("true", "false")) {
    "collectUnsignedLocalQa must be explicitly true or false"
}
val collectUnsignedLocalQa = collectUnsignedLocalQaRaw == "true"

// Public installation target only. A matching host is neither enrollment nor
// send authority; the default keeps the internal gateway offline.
val collectGatewayHost = providers.gradleProperty("collectGatewayHost").orNull.orEmpty()
require(collectGatewayHost.isEmpty() || collectGatewayHost == "lhbowpbcpwoiparwnwgt.supabase.co") {
    "collectGatewayHost must match the governed Collect backend host"
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (!collectUnsignedLocalQa && keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
fun signingEnvName(name: String): String =
    "COOL_ANDROID_" + name
        .replace(Regex("([a-z])([A-Z])"), "$1_$2")
        .uppercase(Locale.US)

fun signingValue(name: String): String? {
    if (collectUnsignedLocalQa) return null
    return (keystoreProperties[name] as String?)
        ?: (findProperty(name) as String?)
        ?: System.getenv(signingEnvName(name))
}

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
        resValues = true
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
        create("internal_gateway") {
            dimension = "channel"
            applicationIdSuffix = ".gateway"
            resValue("string", "app_name", "Collect Gateway")
            resValue("string", "collect_gateway_backend_host", collectGatewayHost)
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

// Flutter's pinned loader adds native plugins to build-type Api configurations,
// regardless of flavor. Keep local/FCM notifications on every member/receiver
// flavor, while the internal sender remains free of both notification plugins.
val collectPluginMetadataFile = rootProject.file("../.flutter-plugins-dependencies")
check(collectPluginMetadataFile.isFile && !Files.isSymbolicLink(collectPluginMetadataFile.toPath())) {
    "Collect native flavor adapter requires regular Flutter plugin metadata; run flutter pub get first"
}
val collectPluginMetadata = JsonSlurper().parse(collectPluginMetadataFile) as Map<*, *>
val collectAndroidPluginRows = (collectPluginMetadata["plugins"] as Map<*, *>)["android"] as List<*>
val collectNotificationPluginDependencies = mapOf(
    "flutter_local_notifications" to emptyList<String>(),
    "firebase_messaging" to listOf("firebase_core"),
)
collectNotificationPluginDependencies.forEach { (pluginName, expectedDependencies) ->
    val rows = collectAndroidPluginRows.filter { (it as Map<*, *>)["name"] == pluginName }
    check(rows.size == 1) { "Unknown Flutter notification plugin topology: $pluginName" }
    val row = rows.single() as Map<*, *>
    check(
        row["native_build"] == true && row["dev_dependency"] == false &&
            row["dependencies"] == expectedDependencies &&
            collectAndroidPluginRows.none {
                pluginName in ((it as Map<*, *>)["dependencies"] as List<*>)
            },
    ) { "Unknown Flutter notification native dependency topology: $pluginName" }
}
val collectNotificationProjects = collectNotificationPluginDependencies.keys.map { project(":$it") }
val collectNotificationProjectPaths = collectNotificationPluginDependencies.keys.map { ":$it" }.toSet()
val collectNonGatewayFlavors = android.productFlavors.filter { it.name != "internal_gateway" }
check(android.productFlavors.any { it.name == "internal_gateway" } && collectNonGatewayFlavors.isNotEmpty()) {
    "Collect native notification adapter requires the declared Gateway and member flavors"
}
collectNonGatewayFlavors.forEach { flavor ->
    collectNotificationProjects.forEach { dependency ->
        dependencies.add("${flavor.name}Api", dependency)
    }
}
val collectBuildTypeApis = android.buildTypes.map { "${it.name}Api" }.toSet()
val collectNotificationRelocations = mutableSetOf<String>()
extensions.extraProperties["collectNotificationRelocations"] = collectNotificationRelocations
configurations.configureEach {
    if (name in collectBuildTypeApis) {
        val apiConfiguration = this
        fun relocateNotification(dependency: ProjectDependency) {
            check(collectNotificationRelocations.add("${apiConfiguration.name}:${dependency.path}")) {
                "Duplicate Flutter notification build-type dependency in ${apiConfiguration.name}: ${dependency.path}"
            }
            check(apiConfiguration.dependencies.remove(dependency)) {
                "Unable to relocate Flutter notification native dependency"
            }
        }
        // Flutter can add the plugin in a later afterEvaluate callback. Observe
        // that exact addition without requiring it during earlier dependency
        // inspection; already-present dependencies are handled before use.
        dependencies.whenObjectAdded {
            if (this is ProjectDependency && path in collectNotificationProjectPaths) {
                relocateNotification(this)
            }
        }
        withDependencies {
            val notifications = filterIsInstance<ProjectDependency>().filter {
                it.path in collectNotificationProjectPaths
            }
            check(notifications.groupBy { it.path }.values.all { it.size == 1 }) {
                "Duplicate Flutter notification build-type dependency in $name"
            }
            notifications.forEach { relocateNotification(it) }
        }
    }
}

// Java classes do not support flavor overlays. Replace only the shared Java
// source directory (which must contain exactly this generated file) with one
// task-generated directory per variant, leaving Flutter's original untouched.
val collectOriginalJavaDirectory = file("src/main/java")
val collectOriginalRegistrant = collectOriginalJavaDirectory.resolve("io/flutter/plugins/GeneratedPluginRegistrant.java")
check(
    collectOriginalJavaDirectory.walkTopDown().filter { it.isFile }.toList() == listOf(collectOriginalRegistrant),
) { "Collect native flavor adapter refuses additional main/java source" }
android.sourceSets.named("main") {
    val declared = java.directories
    check(declared.any { file(it).canonicalFile == collectOriginalJavaDirectory.canonicalFile }) {
        "Unknown Android main Java source directory topology"
    }
    java.setSrcDirs(declared.filter { file(it).canonicalFile != collectOriginalJavaDirectory.canonicalFile })
}
androidComponents.onVariants { variant ->
    val generateRegistrant = tasks.register<CollectVariantPluginRegistrant>(
        "generateCollect${variant.name.replaceFirstChar { it.uppercase() }}PluginRegistrant",
    ) {
        originalJavaDirectory.set(collectOriginalJavaDirectory)
        adapterSource.set(rootProject.file("gradle/CollectPluginRegistrant.java"))
        omitNotifications.set(variant.productFlavors.any { it.first == "channel" && it.second == "internal_gateway" })
        outputDirectory.set(layout.buildDirectory.dir("generated/collectPluginRegistrants/${variant.name}"))
    }
    variant.sources.java?.addGeneratedSourceDirectory(generateRegistrant) { it.outputDirectory }
        ?: error("Android variant ${variant.name} has no generated Java source adapter")
}

gradle.taskGraph.whenReady {
    val sourceAnalysisTasks = setOf(
        "lintDevDebug", "lintProductionDebug", "lintProductionRelease",
        "lintVitalProductionRelease", "lintAnalyzeProductionRelease",
        "testDevDebugUnitTest", "testProductionDebugUnitTest",
    )
    val requested = gradle.startParameter.taskNames.map { it.substringAfterLast(':') }
    val sourceAnalysisOnly = requested.isNotEmpty() && requested.all { it in sourceAnalysisTasks }
    val finalArtifactTasks = setOf(
        "assembleProductionRelease", "bundleProductionRelease", "packageProductionRelease",
        "packageProductionReleaseBundle", "signProductionReleaseBundle",
        "validateSigningProductionRelease", "installProductionRelease",
    )
    val includesFinalArtifact = allTasks.any { it.project == project && it.name in finalArtifactTasks }
    val productionReleaseTaskRequested = allTasks.any { task ->
        task.name.contains("ProductionRelease", ignoreCase = true)
    } && (!sourceAnalysisOnly || includesFinalArtifact)
    val playInstalledOverwriteTaskRequested = allTasks.any { task ->
        signProductionDebugWithPlayKey && task.name.contains("ProductionDebug", ignoreCase = true)
    } && (!sourceAnalysisOnly || includesFinalArtifact)
    if (sourceAnalysisOnly && !includesFinalArtifact) {
        allTasks.filter { task ->
            task.project == project && task.name in setOf(
                "processProductionReleaseGoogleServices", "processProductionDebugGoogleServices",
            )
        }.forEach { it.enabled = false }
    }
    if (!collectUnsignedLocalQa && (productionReleaseTaskRequested || playInstalledOverwriteTaskRequested)) {
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

// Lock only the app's reviewed production graph. Writing/enforcing these locks
// does not modify any Flutter SDK or plugin cache project.
dependencyLocking {
    lockMode.set(LockMode.STRICT)
}
configurations.matching {
    it.name in setOf("productionReleaseRuntimeClasspath", "productionReleaseCompileClasspath")
}.configureEach {
    resolutionStrategy.activateDependencyLocking()
}

if (collectUnsignedLocalQa) {
    val markerDir = layout.buildDirectory.dir("generated/collectLocalQa/assets")
    val marker = tasks.register("writeCollectUnsignedLocalQaMarker") {
        outputs.dir(markerDir)
        doLast {
            val file = markerDir.get().file("collect-local-unsigned-qa.json").asFile
            file.parentFile.mkdirs()
            file.writeText("""{"kind":"local_unsigned_native_qa","store_acceptance":false,"provider_configuration":false,"signing":false}""" + "\n")
        }
    }
    // AGP9 rejects Provider arguments on legacy source-set directory methods.
    // The directory is static for this build; its explicit pre-build dependency
    // below keeps marker generation ordered before asset merging.
    android.sourceSets.getByName("production").assets.srcDir(markerDir.get().asFile)
    android.sourceSets.getByName("internal_gateway").assets.srcDir(markerDir.get().asFile)
    tasks.matching {
        it.name == "preProductionReleaseBuild" || it.name == "preInternal_gatewayReleaseBuild"
    }.configureEach { dependsOn(marker) }
}

dependencies {
    // Kotlin's metadata alignment can materialize this already-selected compile
    // dependency only after strict runtime lock constraints are applied. Declare
    // the same pinned compiler version so lock generation observes it as well.
    implementation("org.jetbrains.kotlin:kotlin-stdlib-common:2.3.20")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
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
                "process(?:Dev|Internal_receiver|Internal_gateway)(?:Debug|Profile|Release)GoogleServices",
                RegexOption.IGNORE_CASE,
            ),
        )
    ) {
        enabled = false
    }
    if (collectUnsignedLocalQa && name == "processProductionReleaseGoogleServices") {
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
