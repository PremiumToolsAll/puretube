# Third-party notices

This Android module incorporates NewPipe Extractor **0.26.5** in its Android-compatible form at `android/libs/newpipeextractor-0.26.5-android-compat.jar`, copied from SparkTube. NewPipe Extractor is licensed under **GNU GPL-3.0-or-later**; the root `LICENSE` contains the GPLv3 license text. Its upstream project and notices are available at <https://github.com/TeamNewPipe/NewPipeExtractor>.

The following pinned runtime dependencies are used as in SparkTube; consult the respective artifact/source distribution for complete notices:

- AndroidX Media3 **1.3.1** — Apache License 2.0 (<https://developer.android.com/jetpack/androidx>)
- OkHttp **4.12.0** — Apache License 2.0 (<https://square.github.io/okhttp/>)
- Jsoup **1.22.2** — MIT License (<https://jsoup.org/license>)
- Mozilla Rhino and Rhino Engine **1.8.1** — Mozilla Public License 2.0 (<https://www.mozilla.org/en-US/MPL/2.0/>)
- protobuf-javalite **4.35.1** — BSD 3-Clause (<https://github.com/protocolbuffers/protobuf>)
- nanojson (TeamNewPipe pinned revision `e9d656ddb49a412a5a0a5d5ef20ca7ef09549996`) — MIT License (<https://github.com/TeamNewPipe/nanojson>)
- jsr305 **3.0.2** — BSD-style license (<https://github.com/Findus23/jsr305>)
- Kotlin coroutines Android **1.8.1** — Apache License 2.0 (<https://github.com/Kotlin/kotlinx.coroutines>)
- Android core library desugaring **2.1.5** — Apache License 2.0 (<https://developer.android.com/studio/write/java8-support>)

The Android code is foreground-only: it does not declare or implement a foreground service, notification playback, or background audio. Activity detach pauses playback; configuration changes retain the player and media configuration. Only allowlisted HTTPS YouTube video URLs are accepted. This Android module currently implements `resolve`, `load`, playback controls, and first-page `search`; there is no `trending` method. The single plugin-owned player is shared by all platform views.
