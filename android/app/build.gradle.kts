plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("com.google.firebase.firebase-perf")
}

import java.io.FileInputStream
import java.io.File
import java.util.Properties
import java.util.Base64
import org.gradle.api.GradleException

val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreProperties.load(FileInputStream(keystoreFile))
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

fun loadDotEnv(file: File): Map<String, String> {
    if (!file.exists()) {
        return emptyMap()
    }

    return file.readLines().mapNotNull { rawLine ->
        val line = rawLine.trim()
        if (line.isEmpty() || line.startsWith("#") || !line.contains("=")) {
            return@mapNotNull null
        }

        val separatorIndex = line.indexOf('=')
        val key = line.substring(0, separatorIndex).trim()
        val value = line.substring(separatorIndex + 1).trim()
            .removeSurrounding("\"")
            .removeSurrounding("'")

        if (key.isEmpty()) null else key to value
    }.toMap()
}

val dotEnvProperties = loadDotEnv(rootProject.file("../.env"))

fun buildConfigValue(name: String): String {
    return providers.gradleProperty(name).orNull
        ?: localProperties.getProperty(name)
        ?: System.getenv(name)
        ?: dotEnvProperties[name]
        ?: ""
}

fun requestedFlutterFlavor(): String {
    val explicitFlavor = buildConfigValue("FLAVOR").trim().lowercase()
    if (explicitFlavor == "production" || explicitFlavor == "staging") {
        return explicitFlavor
    }

    val requestedTasks = gradle.startParameter.taskNames.joinToString(" ").lowercase()
    return when {
        requestedTasks.contains("production") -> "production"
        requestedTasks.contains("staging") -> "staging"
        else -> "staging"
    }
}

fun resolveSupabaseValue(flavor: String, suffix: String): Pair<String, Boolean> {
    val specificName = "SUPABASE_${flavor.uppercase()}_$suffix"
    val specificValue = buildConfigValue(specificName)
    if (specificValue.isNotBlank()) {
        return specificValue to false
    }

    val legacyName = "SUPABASE_$suffix"
    val legacyValue = buildConfigValue(legacyName)
    return legacyValue to legacyValue.isNotBlank()
}

fun deriveSupabaseProjectRef(url: String): String {
    val match = Regex("""https?://([^.]+)\.supabase\.co/?""").find(url.trim())
    return match?.groupValues?.getOrNull(1) ?: ""
}

fun encodeDartDefines(defines: Map<String, String>): String {
    return defines.entries.joinToString(",") { (key, value) ->
        Base64.getEncoder().encodeToString("$key=$value".toByteArray(Charsets.UTF_8))
    }
}

if (!project.hasProperty("dart-defines")) {
    val inferredFlavor = requestedFlutterFlavor()
    val localFlutterDartDefines = linkedMapOf<String, String>()

    val (resolvedSupabaseUrl, usedLegacySupabaseUrl) =
        resolveSupabaseValue(inferredFlavor, "URL")
    val (resolvedSupabaseAnonKey, usedLegacySupabaseAnonKey) =
        resolveSupabaseValue(inferredFlavor, "ANON_KEY")

    if (resolvedSupabaseUrl.isNotBlank()) {
        localFlutterDartDefines["SUPABASE_URL"] = resolvedSupabaseUrl
    }
    if (resolvedSupabaseAnonKey.isNotBlank()) {
        localFlutterDartDefines["SUPABASE_ANON_KEY"] = resolvedSupabaseAnonKey
    }

    localFlutterDartDefines["FLAVOR"] = inferredFlavor
    localFlutterDartDefines["BACKEND_ENVIRONMENT"] = inferredFlavor

    val projectRef = deriveSupabaseProjectRef(resolvedSupabaseUrl)
    if (projectRef.isNotBlank()) {
        localFlutterDartDefines["SUPABASE_PROJECT_REF"] = projectRef
    }

    val requestedTasks = gradle.startParameter.taskNames.joinToString(" ").lowercase()
    val isReleaseTask = requestedTasks.contains("release")
    if (isReleaseTask &&
        (resolvedSupabaseUrl.isBlank() || resolvedSupabaseAnonKey.isBlank())
    ) {
        throw GradleException(
            "Release build requires explicit Supabase configuration. " +
                "Set SUPABASE_${inferredFlavor.uppercase()}_URL and " +
                "SUPABASE_${inferredFlavor.uppercase()}_ANON_KEY, or pass " +
                "--dart-define values explicitly."
        )
    }

    if (localFlutterDartDefines.isNotEmpty()) {
        localFlutterDartDefines.putIfAbsent(
            "COOL_DEEP_LINK_HOST",
            buildConfigValue("COOL_DEEP_LINK_HOST").ifBlank { "cool.app" }
        )
        extra["dart-defines"] = encodeDartDefines(localFlutterDartDefines)
        if (usedLegacySupabaseUrl || usedLegacySupabaseAnonKey) {
            logger.warn(
                "Using legacy SUPABASE_URL / SUPABASE_ANON_KEY fallback for " +
                    "$inferredFlavor. Prefer SUPABASE_${inferredFlavor.uppercase()}_*."
            )
        }
        logger.lifecycle(
            "Using local Dart defines from environment/.env for Android build because none were provided explicitly."
        )
    }
}

android {
    namespace = "app.cool.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.cool.mobile"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Google Maps SDK reads its API key from AndroidManifest.xml's
        // <meta-data android:name="com.google.android.geo.API_KEY">.
        // We resolve it from the same config chain used for Dart defines.
        manifestPlaceholders["GOOGLE_MAPS_ANDROID_API_KEY"] =
            buildConfigValue("GOOGLE_MAPS_ANDROID_API_KEY")
    }

    flavorDimensions += "environment"

    productFlavors {
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "Cool [STG]")
        }
        create("production") {
            dimension = "environment"
            resValue("string", "app_name", "Cool")
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            val disableMinify =
                findProperty("cool.disableAndroidMinify")?.toString()
                    ?.toBooleanStrictOrNull() == true ||
                System.getenv("COOL_DISABLE_ANDROID_MINIFY")?.trim() == "1"
            // R8 shrinking & obfuscation — ENABLED (updated: 2026-04-11)
            //
            // History: R8 was disabled (2026-04-10) due to a Flutter engine
            //   JNI symbol stripping crash on Pixel 4a with Flutter 3.38.9.
            //
            // Current stance: keep minification enabled on the pinned Flutter
            //   3.38.9 toolchain, but require the production minify canary and
            //   device smoke verification before shipping release artifacts.
            //   ProGuard rules comprehensively keep all Flutter engine,
            //   Firebase, NFC, TFLite, and Supabase JNI symbols.
            //
            // Escape hatch: set cool.disableAndroidMinify=true in
            //   gradle.properties or COOL_DISABLE_ANDROID_MINIFY=1 env var
            //   to disable minification for debugging. This should NOT be
            //   used for production submissions.
            //
            // Verification required: build a release APK and test on Pixel 4a
            //   to confirm the engine startup crash is resolved.
            isMinifyEnabled = !disableMinify
            isShrinkResources = !disableMinify
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}
