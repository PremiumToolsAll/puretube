# PureTube release rules (R8).
#
# The Play Core classes Flutter references for deferred components are
# not on the classpath of a plain APK build — warn-free ignore (this
# was the failure that kept R8 disabled before).
-dontwarn com.google.android.play.core.**

# Reflection-driven libraries: keep whole. NewPipeExtractor builds its
# services and parses YouTube's JS-driven responses reflectively;
# Rhino interprets that JS; protobuf-lite messages are instantiated
# reflectively. Shrinking or renaming inside these packages risks the
# exact NoClassDefFoundError class of failure that killed build #539.
-keep class org.schabi.newpipe.** { *; }
-keep class org.mozilla.** { *; }
-keep class com.google.protobuf.** { *; }
-keep class com.grack.nanojson.** { *; }
-keep class org.jsoup.** { *; }
