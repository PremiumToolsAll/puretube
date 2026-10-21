plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.puretube.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by the puretube_playback plugin (NewPipeExtractor uses
        // Java 10 stream APIs; see its README).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.puretube.app"
        // media_kit needs 21+; PiP guarded at runtime.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Ship arm64-only: modern phones only. (flutter's --target-platform
        // flag does NOT strip media_kit's bundled armeabi-v7a/x86_64 libs.)
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        release {
            // Disable R8: newer AGP + Flutter triggers missing Play Core
            // classes during minification. APK is slightly larger but builds.
            isMinifyEnabled = false
            isShrinkResources = false
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Belt-and-suspenders with the ndk abiFilters above: drop every
            // non-arm64 native lib (media_kit bundles armeabi-v7a/x86_64).
            excludes += "/lib/armeabi-v7a/*"
            excludes += "/lib/armeabi/*"
            excludes += "/lib/x86/*"
            excludes += "/lib/x86_64/*"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Native HQ player (ExoPlayer) for 1080p+ DASH.
    implementation("androidx.media3:media3-exoplayer:1.6.1")
    implementation("androidx.media3:media3-exoplayer-dash:1.6.1")
    // NewPipeExtractor for stream URLs (same as SparkTube).
    implementation(files("libs/newpipeextractor-0.26.5-android-compat.jar"))
    // NewPipeExtractor's runtime dependencies (same set SparkTube declares;
    // the vendored JAR does NOT bundle them — without jsoup/nanojson the
    // extractor dies with NoClassDefFoundError and takes the app down).
    implementation("org.jsoup:jsoup:1.22.2")
    implementation("org.mozilla:rhino:1.8.1")
    implementation("org.mozilla:rhino-engine:1.8.1")
    implementation("com.google.protobuf:protobuf-javalite:4.35.1")
    implementation("com.google.code.findbugs:jsr305:3.0.2")
    implementation("com.github.TeamNewPipe:nanojson:e9d656ddb49a412a5a0a5d5ef20ca7ef09549996")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // Core library desugaring for the puretube_playback plugin.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
