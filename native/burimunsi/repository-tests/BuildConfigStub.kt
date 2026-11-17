package app.cool.mobile

/** Synthetic approved pins for repository tests only. The Android build uses blank pins. */
object BuildConfig {
    var HELD_RECOVERY_APPROVED_SOURCE_SHA256="a".repeat(64)
    var HELD_RECOVERY_APPROVED_MIGRATION_SHA256="b".repeat(64)
}
