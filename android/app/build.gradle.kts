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

fun encodeDartDefines(defines: Map<String, String>): String {
    return defines.entries.joinToString(",") { (key, value) ->
        Base64.getEncoder().encodeToString("$key=$value".toByteArray(Charsets.UTF_8))
    }
}

if (!project.hasProperty("dart-defines")) {
    val localFlutterDartDefines = linkedMapOf<String, String>()
    listOf(
        "SUPABASE_URL",
        "SUPABASE_ANON_KEY",
        "FLAVOR",
    ).forEach { key ->
        val value = buildConfigValue(key)
        if (value.isNotBlank()) {
            localFlutterDartDefines[key] = value
        }
    }

    if (localFlutterDartDefines.isNotEmpty()) {
        localFlutterDartDefines.putIfAbsent(
            "COOL_DEEP_LINK_HOST",
            buildConfigValue("COOL_DEEP_LINK_HOST").ifBlank { "cool.app" }
        )
        extra["dart-defines"] = encodeDartDefines(localFlutterDartDefines)
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
            isMinifyEnabled = true
            isShrinkResources = true
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
}
