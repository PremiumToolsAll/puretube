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
}
