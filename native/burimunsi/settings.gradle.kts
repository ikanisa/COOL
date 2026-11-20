pluginManagement {
    // Kotlin 2.4 requires R8 >= 9.1.29; AGP 9.0.1 embeds 9.0.32.
    // Use the official R8 override from Google Maven without changing SDK/AGP.
    buildscript {
        repositories { google(); mavenCentral() }
        dependencies { classpath("com.android.tools:r8:9.1.57") }
    }
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "BuriMunsi"
include(":core", ":app")
