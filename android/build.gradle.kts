allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Configure the app output root before its plugins are applied. Flutter resolves
// its default ProGuard file during plugin application, so a later module-level
// override would leave that rule pointing at the previous build directory.
val collectAndroidBuildRoot =
    providers.environmentVariable("COLLECT_ANDROID_BUILD_ROOT").orNull

subprojects {
    if (project.name == "app" && !collectAndroidBuildRoot.isNullOrBlank()) {
        project.layout.buildDirectory.set(
            project.file(collectAndroidBuildRoot).resolve("app"),
        )
    } else {
        project.layout.buildDirectory.value(newBuildDir.dir(project.name))
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.test" && requested.name == "runner") {
                useVersion("1.6.1")
                because("Flutter integration_test declares 1.2+, which breaks offline Android builds.")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
