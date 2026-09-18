# R8 rules for the release build. Flutter, Firebase, Play services and ML Kit
# ship their own consumer rules; these cover what only this app knows about.

# Entry points named in the manifest, reached by name rather than by code.
-keep class com.rayyanshaikh.orbit.MainActivity { *; }
-keep class com.rayyanshaikh.orbit.BlockerActivity { *; }
-keep class com.rayyanshaikh.orbit.AppBlockerService { *; }
-keep class com.rayyanshaikh.orbit.OverlayService { *; }
-keep class com.rayyanshaikh.orbit.TrackingService { *; }
-keep class com.rayyanshaikh.orbit.AlarmReceiver { *; }
-keep class com.rayyanshaikh.orbit.BootReceiver { *; }

# Play Core split-install classes the Flutter embedding references but that a
# non-deferred-component build never bundles.
-dontwarn com.google.android.play.core.**

# Health Connect is optional at runtime on phones without the provider.
-dontwarn androidx.health.connect.**
