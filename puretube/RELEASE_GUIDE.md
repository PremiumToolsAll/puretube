# PureTube — Production Release Guide

## PART 1: Branding ✅ Done
- `pubspec.yaml`: name `puretube`, "A premium, ad-free YouTube client."
- `AndroidManifest.xml`: `android:label="PureTube"`, package `com.puretube.app`
- `lib/main.dart`: `MaterialApp(title: 'PureTube')`
- App icon: purple #6200EA + white play (assets/icon/)

## PART 2: Build Configuration ✅ Done
- `android/app/build.gradle.kts`: minSdk 24, targetSdk 34, R8/ProGuard, release signing via key.properties
- `android/app/proguard-rules.pro`: keep rules for audio_service, media_kit, isar, etc.
- `AndroidManifest.xml`: usesCleartextTraffic="true", all permissions set

## PART 3: Build Commands

### Step 1 — Create signing key (one time)
```bash
keytool -genkey -v -keystore ~/puretube-release.keystore \
  -alias puretube -keyalg RSA -keysize 2048 -validity 10000
```

### Step 2 — Create android/key.properties
```properties
storeFile=/home/hatch/puretube-release.keystore
storePassword=YOUR_STORE_PASSWORD
keyAlias=puretube
keyPassword=YOUR_KEY_PASSWORD
```

### Step 3 — Generate icons & splash
```bash
cd ~/workspace/nextube
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter pub run flutter_launcher_icons
flutter pub run flutter_native_splash:create
```

### Step 4 — Clean & build release APK
```bash
flutter clean
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Step 5 — Build App Bundle (Play Store)
```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

## Pre-build Checklist
- [ ] `flutter pub get` succeeds with no version conflicts
- [ ] `dart run build_runner build` generates Isar schemas
- [ ] App launches without white screen
- [ ] Video plays (stream extraction works)
- [ ] Background audio + notification controls work
- [ ] PiP enters on Home press
- [ ] Download saves to /PureTube/Videos/
- [ ] No ProGuard release crash (test release APK, not just debug)
