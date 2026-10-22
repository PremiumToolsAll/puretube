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
            // R8 enabled for size (the dexes were ~20MB unshrunk). The
            // Play Core warnings that once blocked this are dontwarn'd
            // in proguard-rules.pro, and the reflection-heavy libraries
            // (NewPipeExtractor, Rhino, protobuf, nanojson) are kept
            // whole there — shrinking must never break extraction.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
    // The puretube_playback plugin declares everything the HQ engine
    // needs (media3, NewPipeExtractor + its 7 runtime deps) in its own
    // module — the app module must NOT repeat them: duplicate copies
    // failed the release build twice (#541 nanojson, #542 extractor
    // JAR), and the app's media3 1.6.1 pin was silently overriding
    // the plugin's tested 1.3.1.
    // Core library desugaring for the puretube_playback plugin.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
