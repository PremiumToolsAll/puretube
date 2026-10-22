# PureTube release rules (R8).
#
# The Play Core classes Flutter references for deferred components are
# not on the classpath of a plain APK build — warn-free ignore (this
# was the failure that kept R8 disabled before).
-dontwarn com.google.android.play.core.**

# Rhino references desktop-Java APIs that do not exist on Android
# (java.beans introspection, the JSR-223 javax.script engine, and
# jdk.dynalink). NewPipe drives Rhino directly in interpreted mode,
# so none of these are ever loaded at runtime — but R8 treats the
# dangling references as fatal "missing classes" (build #546).
-dontwarn java.beans.**
-dontwarn javax.script.**
-dontwarn jdk.dynalink.**

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
