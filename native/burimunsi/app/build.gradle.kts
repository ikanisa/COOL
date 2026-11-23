import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.net.URI

abstract class PrepareReceiverTask : Exec() {
    @get:OutputDirectory
    abstract val generatedSources: DirectoryProperty
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
fun quoted(v: String) = "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "") + "\""
fun publicUri(value: String): URI = try { URI(value) } catch (_: Exception) {
    // URI constructor errors can echo their input. Compiler diagnostics must
    // never expose a credential accidentally supplied in a public URL field.
    throw GradleException("Malformed public deployment URL")
}
// Configured app builds target the owner's existing Supabase Cloud project.
// Distinct application IDs below establish a new Android custody boundary;
// they cannot access the old applications' private credentials or queues.
fun requireCollectCloud(uri: URI) {
    require(uri.scheme == "https" && uri.rawAuthority == "rrlduytparvsjfmegalh.supabase.co") {
        "BuriMunsi permits the Collect Supabase Cloud project only"
    }
}
// Both native roles use the existing Collect Supabase instance and collect-api.
val sharedOrigin = providers.gradleProperty("collectSupabaseOrigin").orElse("")
val adminOrigin = providers.gradleProperty("collectAdminOrigin").orElse("")
if (adminOrigin.get().isNotBlank()) {
    val uri = publicUri(adminOrigin.get())
    require(uri.scheme == "https" && uri.host != null && uri.userInfo == null && uri.query == null && uri.fragment == null && uri.path.isNullOrEmpty()) { "Invalid shared Collect Admin origin" }
    requireCollectCloud(uri)
}
val apiOrigin = providers.gradleProperty("burimunsiApiOrigin").orElse(sharedOrigin)
val apiPathPrefix = providers.gradleProperty("burimunsiApiPathPrefix").orElse("/functions/v1/collect-api")
require(apiPathPrefix.get() in setOf("", "/functions/v1/collect-api")) { "Invalid fixed Collect API path prefix" }
val gatewayOrigin = providers.gradleProperty("collectGatewayOrigin").orElse(sharedOrigin.map { if (it.isBlank()) "" else it + apiPathPrefix.get() })
val gatewayUri = gatewayOrigin.get().takeIf { it.isNotBlank() }?.let { publicUri(it) }
if (gatewayUri != null) {
    require(gatewayUri.scheme == "https" && gatewayUri.host != null && gatewayUri.userInfo == null && gatewayUri.query == null && gatewayUri.fragment == null) { "Invalid fixed gateway origin" }
    requireCollectCloud(gatewayUri)
}
if (apiOrigin.get().isNotBlank()) {
    val uri=publicUri(apiOrigin.get())
    require(uri.scheme == "https" && uri.host != null && uri.userInfo == null && uri.query == null && uri.fragment == null && uri.path.isNullOrEmpty()) { "Invalid native API origin" }
    requireCollectCloud(uri)
}
if (sharedOrigin.get().isNotBlank()) {
    val shared = publicUri(sharedOrigin.get())
    require(shared.scheme == "https" && shared.host != null && shared.userInfo == null && shared.query == null && shared.fragment == null && shared.path.isNullOrEmpty()) { "Invalid shared Collect Supabase origin" }
    requireCollectCloud(shared)
    require(apiOrigin.get() == sharedOrigin.get()) { "BuriMunsi must use the shared Collect backend origin" }
    require(gatewayOrigin.get().isEmpty() || gatewayOrigin.get() == sharedOrigin.get() + apiPathPrefix.get()) { "Receiver must use the shared Collect API" }
}
val authOrigin = sharedOrigin.map { if (it.isBlank()) apiOrigin.get() else it }
val publicKey = providers.gradleProperty("collectPublishableKey").orElse("")
require(publicKey.get().isBlank() || Regex("sb_publishable_[A-Za-z0-9_-]{10,300}").matches(publicKey.get())) { "Only a public Supabase publishable key may enter native configuration" }
val collectRoot = providers.gradleProperty("collectRoot").orElse(rootProject.projectDir.resolve("../../upstream/collect").absolutePath)

android {
    // Retains the reused receiver's BuildConfig package. Application IDs remain separate.
    namespace = "app.cool.mobile"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    defaultConfig {
        applicationId = "rw.ikanisa.burimunsi"
        minSdk = 26
        targetSdk = 36
        versionCode = 49
        versionName = "0.23.0-collect.27"
        resValue("string", "app_name", "BuriMunsi")
        buildConfigField("boolean", "IS_QUALIFICATION", "false")
        // The new Cloud identity snapshots the existing inbox before catch-up.
        // It does not import or replay another installation's local queue.
        buildConfigField("boolean", "CLOUD_HOLD_EXISTING_INBOX", "true")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "BURI_API_ORIGIN", quoted(apiOrigin.get()))
        buildConfigField("String", "BURI_AUTH_ORIGIN", quoted(authOrigin.get()))
        buildConfigField("String", "BURI_ADMIN_ORIGIN", quoted(adminOrigin.get()))
        buildConfigField("String", "BURI_API_PATH_PREFIX", quoted(apiPathPrefix.get()))
        buildConfigField("String", "COLLECT_API_HOST", quoted(gatewayUri?.rawAuthority ?: ""))
        buildConfigField("String", "COLLECT_API_PATH_PREFIX", quoted(gatewayUri?.path?.trimEnd('/') ?: ""))
        buildConfigField("String", "COLLECT_AUTH_SESSION_OWNER", quoted("burimunsi"))
        buildConfigField("String", "COLLECT_PUBLISHABLE_KEY", quoted(publicKey.get()))
        buildConfigField("String", "RECEIVER_API_BASE_URL", quoted(gatewayOrigin.get()))
        buildConfigField("String", "COLLECT_RECEIVER_API_BASE_URL", quoted(gatewayOrigin.get()))
    }
    val offlineBuildTypes = listOf("qualification", "nativeTest")
    val endpointFields = listOf(
        "BURI_API_ORIGIN", "BURI_AUTH_ORIGIN", "BURI_ADMIN_ORIGIN", "BURI_API_PATH_PREFIX",
        "COLLECT_API_HOST", "COLLECT_API_PATH_PREFIX", "COLLECT_PUBLISHABLE_KEY",
        "RECEIVER_API_BASE_URL", "COLLECT_RECEIVER_API_BASE_URL",
    )
    // Instrumentation always targets a separate offline/testOnly sandbox.
    testBuildType = "nativeTest"
    flavorDimensions += "device"
    productFlavors {
        create("internal_receiver") { dimension = "device"; applicationIdSuffix = ".gateway.cloud"; resValue("string", "app_name", "BuriMunsi Admin"); buildConfigField("boolean", "IS_GATEWAY", "true") }
        create("staff") { dimension = "device"; applicationIdSuffix = ".staff.cloud"; resValue("string", "app_name", "BuriMunsi Staff"); buildConfigField("boolean", "IS_GATEWAY", "false") }
    }
    buildFeatures { compose = true; buildConfig = true; resValues = true }
    // The product supports English and Kinyarwanda; discard unused library translations.
    androidResources { localeFilters += listOf("en", "rw") }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    buildTypes {
        debug { applicationIdSuffix = ".debug" }
        release { isMinifyEnabled = true; isShrinkResources = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") }
        create("qualification") {
            initWith(getByName("release"))
            applicationIdSuffix = ".qualification"
            versionNameSuffix = "-qualification"
            isDebuggable = false
            // Unsigned optimized/testOnly artifact. Sign only with a dedicated QA key,
            // never the production key, then explicitly install with adb -t.
            signingConfig = null
            matchingFallbacks += listOf("release")
            resValue("string", "app_name", "BuriMunsi Qualification")
        }
        create("nativeTest") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".nativeTest"
            versionNameSuffix = "-native-test"
            isDebuggable = true
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("debug")
            resValue("string", "app_name", "BuriMunsi Native Test")
        }
        for (name in offlineBuildTypes) named(name) {
            buildConfigField("boolean", "IS_QUALIFICATION", "true")
            endpointFields.forEach { field -> buildConfigField("String", field, quoted("")) }
        }
    }
    for (name in offlineBuildTypes) sourceSets.named(name) {
        manifest.srcFile("src/offline/AndroidManifest.xml")
    }
    lint { abortOnError = true; checkReleaseBuilds = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }

val prepareReceiver by tasks.registering(PrepareReceiverTask::class) {
    generatedSources.set(layout.buildDirectory.dir("generated/collect-receiver"))
    inputs.file(rootProject.file("integration/receiver-sources.json"))
    inputs.file(rootProject.file("scripts/prepare_receiver.py"))
    inputs.file(rootProject.file("scripts/receiver_adaptations.py"))
    inputs.files(fileTree(collectRoot.get()) {
        include("android/app/src/main/kotlin/app/cool/mobile/receiver_sms/*.kt")
    })
    // Recheck exact pins and generated integrity even when Gradle considers inputs unchanged.
    // Never let a stale/tampered generated tree silently bypass the extraction gate.
    outputs.upToDateWhen { false }
    commandLine("python3", rootProject.file("scripts/prepare_receiver.py"), "--collect-root", collectRoot.get(), "--output", generatedSources.get().asFile)
}
androidComponents {
    onVariants(selector().withFlavor("device" to "internal_receiver")) { variant ->
        variant.sources.java?.addGeneratedSourceDirectory(prepareReceiver, PrepareReceiverTask::generatedSources)
    }
}
val verifyReleaseEvidence by tasks.registering(Exec::class) {
    // No default evidence or "tests passed" boolean substitutes for real artifacts.
    doFirst {
        val phase = providers.gradleProperty("burimunsiReleasePhase").orElse("build").get()
        check(phase in setOf("build", "testing-candidate")) { "Select the existing build gate or explicit testing-candidate compilation gate" }
        val status = providers.gradleProperty("burimunsiReleaseStatus").orNull
        val evidence = providers.gradleProperty("burimunsiReleaseEvidence").orNull
        check(!evidence.isNullOrBlank()) { "Executed build-prerequisite evidence is required" }
        if (phase == "testing-candidate") {
            val profile = providers.gradleProperty("burimunsiReleaseProfile").orNull
            check(!profile.isNullOrBlank() && status.isNullOrBlank()) { "Testing candidate requires its public deployment profile and current qualification evidence, without legacy task closure" }
            environment("BURI_BUILD_PUBLIC_PROPERTIES", groovy.json.JsonOutput.toJson(mapOf(
                "collectSupabaseOrigin" to sharedOrigin.get(), "collectAdminOrigin" to adminOrigin.get(),
                "burimunsiApiOrigin" to apiOrigin.get(), "burimunsiApiPathPrefix" to apiPathPrefix.get(),
                "collectGatewayOrigin" to gatewayOrigin.get(), "collectPublishableKey" to publicKey.get())))
            commandLine("python3", rootProject.file("scripts/release_readiness.py"), "--phase", phase,
                "--evidence", rootProject.file(evidence!!), "--profile", rootProject.file(profile!!))
        } else {
            check(!status.isNullOrBlank()) { "Legacy build evidence requires its existing task register" }
            commandLine("python3", rootProject.file("scripts/release_readiness.py"),
                "--status", rootProject.file(status!!), "--evidence", rootProject.file(evidence!!), "--phase", "build")
        }
    }
}
tasks.configureEach {
    if (name.startsWith("pre") && name.contains("Release") && name.endsWith("Build")) dependsOn(verifyReleaseEvidence)
    if (name.startsWith("preInternal_receiver", ignoreCase = true) && name.endsWith("Build")) dependsOn(prepareReceiver)
    if (name.contains("Release") && (name.startsWith("assemble") || name.startsWith("bundle"))) doFirst {
        check(apiOrigin.get().startsWith("https://") && adminOrigin.get().startsWith("https://")) { "Shared Collect API and Admin configuration is required; collection authority comes from authenticated device approval." }
        check(providers.gradleProperty("nativeReleaseQualified").orElse("false").get() == "true") { "Native tests, manifest gate and release approval remain required." }
    }
}
dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    androidTestImplementation(platform("androidx.compose:compose-bom:2026.06.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:rules:1.7.0")
    // Custom build types do not inherit debugImplementation dependencies.
    add("nativeTestImplementation", platform("androidx.compose:compose-bom:2026.06.01"))
    add("nativeTestImplementation", "androidx.compose.ui:ui-test-manifest")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

// Explicit promotion check: all 65 criteria, signed distribution and owner evidence.
// It verifies evidence only. It does not sign, publish, upload, migrate or deploy.
tasks.register<Exec>("verifyProductionPromotion") {
    doFirst {
        val status = providers.gradleProperty("burimunsiReleaseStatus").orNull
        val evidence = providers.gradleProperty("burimunsiReleaseEvidence").orNull
        check(!status.isNullOrBlank() && !evidence.isNullOrBlank()) { "Production promotion evidence required." }
        commandLine("python3", rootProject.file("scripts/release_readiness.py"),
            "--status", rootProject.file(status!!), "--evidence", rootProject.file(evidence!!), "--phase", "promotion")
    }
}
