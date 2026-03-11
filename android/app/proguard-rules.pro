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

# ── Hive (local storage — uses reflection for adapters) ──────
-keep class ** implements com.google.gson.TypeAdapterFactory { *; }
-keep class * extends com.google.gson.TypeAdapter { *; }

# ── NFC (flutter_nfc_kit native bridge) ──────────────────────
-keep class im.nfc.flutter_nfc_kit.** { *; }
-dontwarn im.nfc.flutter_nfc_kit.**

# ── flutter_contacts ──
-keep class co.nicola.flutter_contacts.** { *; }

# ── Google Maps ──────────────────────────────────────────────
-keep class com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.maps.**
