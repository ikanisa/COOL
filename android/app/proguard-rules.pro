# ──────────────────────────────────────────────────────────────
# Cool App — ProGuard / R8 Keep Rules
# ──────────────────────────────────────────────────────────────
# With isMinifyEnabled and isShrinkResources enabled in release
# builds, R8 strips unused classes. These rules protect native
# bridges and reflection-dependent libraries.
# ──────────────────────────────────────────────────────────────

# ── Flutter / Dart ────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── Google Fonts ──────────────────────────────────────────────
-keep class com.google.android.gms.fonts.** { *; }

# ── Supabase / GoTrue ────────────────────────────────────────
-keep class io.supabase.** { *; }

# ── Firebase Crashlytics ─────────────────────────────────────
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── Firebase Performance ─────────────────────────────────────
-keep class com.google.firebase.perf.** { *; }
-dontwarn com.google.firebase.perf.**

# ── Firebase Messaging (FCM) ─────────────────────────────────
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.messaging.**

# ── Firebase App Check ───────────────────────────────────────
-keep class com.google.firebase.appcheck.** { *; }
-dontwarn com.google.firebase.appcheck.**

# ── OkHttp (used internally by Firebase and network libs) ────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# ── Hive (hive_flutter local storage — reflection is not used, but ─────
#    keeping the entire io.hive package prevents R8 from stripping
#    native initializers required by hive_flutter).
-keep class com.crazecoder.flutter_hive.** { *; }
-dontwarn com.crazecoder.flutter_hive.**

# ── NFC (flutter_nfc_kit native bridge) ──────────────────────
-keep class im.nfc.flutter_nfc_kit.** { *; }
-dontwarn im.nfc.flutter_nfc_kit.**

# ── flutter_contacts ──
-keep class co.nicola.flutter_contacts.** { *; }

# ── Google Maps ──────────────────────────────────────────────
-keep class com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.maps.**

# ── TFLite Flutter (tflite_flutter) ──────────────────────────
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# ── AndroidX Security / EncryptedSharedPreferences ───────────
# security-crypto uses Tink under the hood, which relies on
# reflection to locate cipher implementations.
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# ── AndroidX Work (WorkManager — used by background tasks) ───
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# ── local_auth (biometric native bridge) ─────────────────────
-keep class io.flutter.plugins.localauth.** { *; }
-dontwarn io.flutter.plugins.localauth.**

# ── Flutter engine JNI symbols ───────────────────────────────
# Prevent R8 from stripping native method declarations that the
# Flutter engine loads via System.loadLibrary. This rule is a
# safety net for the Pixel 4a engine startup crash (P2).
-keepclasseswithmembernames class * {
    native <methods>;
}
