package android.content

/** JVM-only platform double. It has no Android filesystem or inbox access. */
class Context {
    val applicationContext:Context get()=this
    val noBackupFilesDir=java.io.File("/nonexistent-held-consent-test")
}
