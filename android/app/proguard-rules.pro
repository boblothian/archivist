# Flutter (safe)
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Prevent stripping of reflection classes
-keep class androidx.lifecycle.** { *; }
-keep class androidx.work.** { *; }

# If you use just_audio
-keep class com.ryanheise.just_audio.** { *; }

# If you use url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# If you use cached_network_image
-dontwarn com.bumptech.glide.**

# General Kotlin reflection fix
-keep class kotlin.** { *; }
-keepclassmembers class kotlin.Metadata { *; }

-keep class com.ryanheise.audio_session.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.just_audio.background.** { *; }
-dontwarn com.ryanheise.**

# --- Fix R8 "Missing class androidx.window.*" (optional Window / folding APIs)
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**
-dontwarn androidx.window.layout.adapter.extensions.**
-dontwarn androidx.window.layout.adapter.sidecar.**
-dontwarn androidx.window.core.**

# --- Fix R8 "Missing class org.osgi.*" (JUPnP uses OSGi annotations)
-dontwarn org.osgi.**
-dontwarn org.jupnp.**

