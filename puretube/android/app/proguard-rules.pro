# PureTube ProGuard/R8 rules — keep rules to prevent release crashes.

# ── Flutter ──────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── audio_service / audio_session (MediaSession) ───────────────
-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

# ── media_kit (JNI) ──────────────────────────────────────────
-keep class com.alexmercerind.mediakit.** { *; }
-dontwarn com.alexmercerind.**

# ── isar (native) ────────────────────────────────────────────
-keep class isar.** { *; }
-dontwarn isar.**

# ── youtube_explode_dart (no native, but keep models) ─────────
-keep class com.puretube.app.** { *; }

# ── flutter_downloader ───────────────────────────────────────
-keep class vn.hunghd.flutterdownloader.** { *; }
-dontwarn vn.hunghd.**

# ── workmanager ──────────────────────────────────────────────
-keep class be.tramckrijte.workmanager.** { *; }

# ── system_alert_window ──────────────────────────────────────
-keep class in.jvapps.system_alert_window.** { *; }

# ── Gson / JSON (used by several plugins) ────────────────────
-keep class com.google.gson.** { *; }
-keepattributes Signature, *Annotation*

# ── Keep native method names ─────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}
