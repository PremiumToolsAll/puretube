package com.puretube.app

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * PureTube MainActivity.
 *
 * - Handles PiP transitions (supportsPictureInPicture in the manifest).
 * - Exposes a MethodChannel ("puretube/pip") so Dart can enter/exit PiP
 *   with proper aspect ratio and source rect hints.
 * - configChanges in the manifest prevents activity recreation on
 *   rotation/PiP resize; we forward config changes to Flutter.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val PIP_CHANNEL = "puretube/pip"
    }

    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PIP_CHANNEL
        )
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    result.success(enterPipMode())
                }
                "isPipSupported" -> {
                    result.success(isPipSupported())
                }
                "isInPip" -> {
                    result.success(isInPictureInPictureModeCompat())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPipSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature("android.software.picture_in_picture")
    }

    private fun isInPictureInPictureModeCompat(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            isInPictureInPictureMode
        } else {
            false
        }
    }

    private fun enterPipMode(): Boolean {
        if (!isPipSupported()) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setAutoEnterEnabled(false)
                        setSeamlessResizeEnabled(true)
                    }
                }
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                enterPictureInPictureMode(params)
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Notify Dart so it can swap to a minimal PiP UI.
        pipChannel?.invokeMethod(
            "onPipChanged",
            isInPictureInPictureMode
        )
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Auto-enter PiP when the user presses Home during playback.
        // Dart decides whether playback is active via the channel.
        pipChannel?.invokeMethod("onUserLeaveHint", null)
    }
}
