package com.puretube.app

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the "pure_tube/pip" method channel used by PipService:
 *  - isPipSupported -> Boolean
 *  - isInPip         -> Boolean
 *  - enterPip        -> Boolean
 * Notifies Dart via "onPipChanged" whenever PiP mode changes.
 *
 * Extends AudioServiceActivity (audio_service 0.18.x official integration):
 * the activity shares audio_service's cached FlutterEngine instead of
 * creating its own. Without this, AudioService.init throws
 * IllegalStateException ("The Activity class declared in your
 * AndroidManifest.xml is wrong...") and the app silently falls back to a
 * handler with no foreground service — i.e. NO media notification ever.
 */
class MainActivity : AudioServiceActivity() {
    private var pipChannel: MethodChannel? = null

    // Warm up / reuse audio_service's shared engine (mirrors the official
    // AudioServiceFragmentActivity pattern).
    override fun getCachedEngineId(): String? {
        AudioServicePlugin.getFlutterEngine(this)
        return AudioServicePlugin.getFlutterEngineId()
    }

    // The engine is created and managed by AudioServicePlugin; it must NOT
    // be destroyed with the activity, otherwise background playback (and
    // its notification) dies as soon as the UI goes away.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native HQ player (ExoPlayer) for 1080p+ DASH — app-local plugin.
        flutterEngine.plugins.add(HqPlayerPlugin())
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "pure_tube/pip"
        )
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    val supported =
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(
                            PackageManager.FEATURE_PICTURE_IN_PICTURE
                        )
                    result.success(supported)
                }
                "isInPip" -> result.success(isInPipCompat())
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            result.success(enterPictureInPictureMode(params))
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isInPipCompat(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
            isInPictureInPictureMode else false

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
