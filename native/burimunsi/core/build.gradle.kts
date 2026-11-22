plugins { id("org.jetbrains.kotlin.jvm") }
kotlin { jvmToolchain(17) }
tasks.register<JavaExec>("coreChecks") {
    dependsOn("testClasses")
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("rw.ikanisa.burimunsi.core.CoreChecks")
}
// Execute the actual Android transport's platform-independent code on the JVM.
// Only org.json and HTTPS connections are fixture doubles; never packaged in app.
val managedLogin by sourceSets.creating {
    compileClasspath += sourceSets["main"].output
    runtimeClasspath += sourceSets["main"].output
}
kotlin.sourceSets.named("managedLogin") {
    kotlin.srcDirs("../managed-login-tests", "../repository-tests", "../app/src/main/kotlin")
    kotlin.include("CollectAdminTransportChecks.kt", "JsonAdapter.kt", "rw/ikanisa/wire/**",
        "rw/ikanisa/burimunsi/data/CollectAdminTransport.kt")
}
configurations[managedLogin.implementationConfigurationName].extendsFrom(configurations["implementation"])
tasks.register<JavaExec>("managedTransportChecks") {
    dependsOn(managedLogin.classesTaskName)
    classpath = managedLogin.runtimeClasspath
    mainClass.set("rw.ikanisa.burimunsi.managedlogintests.CollectAdminTransportChecksKt")
}
