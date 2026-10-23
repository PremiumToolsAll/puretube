package com.puretube.app

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the "pure_tube/pip" method channel used by PipService:
 *  - isPipSupported  -> Boolean
 *  - isInPip          -> Boolean
 *  - enterPip         -> Boolean
 *  - setPipPlaying    -> ({"playing": Boolean}) refresh the PiP
 *                        window's play/pause action icon.
 * Notifies Dart via "onPipChanged" whenever PiP mode changes and
 * via "onPipAction" ("playPause" / "next" / "previous") when the
 * user taps a PiP window transport button — the PiP window carries
 * real Previous / Play-Pause / Next RemoteActions wired to the
 * SAME player controller as the main player, the in-app popup and
 * the media notification, so every surface drives one engine.
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
    private var pipPlaying = false
    private var pipReceiver: BroadcastReceiver? = null

    companion object {
        private const val ACTION_PIP_PLAY_PAUSE =
            "com.puretube.app.action.PIP_PLAY_PAUSE"
        private const val ACTION_PIP_NEXT =
            "com.puretube.app.action.PIP_NEXT"
        private const val ACTION_PIP_PREVIOUS =
            "com.puretube.app.action.PIP_PREVIOUS"
    }

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
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "pure_tube/pip"
        )
        registerPipReceiver()
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
                            result.success(
                                enterPictureInPictureMode(buildPipParams())
                            )
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setPipPlaying" -> {
                    pipPlaying =
                        call.argument<Boolean>("playing") ?: pipPlaying
                    // Refresh the visible play/pause icon while in PiP.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        isInPipCompat()
                    ) {
                        try {
                            setPictureInPictureParams(buildPipParams())
                        } catch (e: Exception) {
                            // PiP params are cosmetic here; never crash.
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pipPendingIntent(action: String, requestCode: Int):
        PendingIntent {
        val intent = Intent(action).setPackage(packageName)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(this, requestCode, intent, flags)
    }

    private fun pipAction(
        iconRes: Int,
        title: String,
        action: String,
        requestCode: Int
    ): RemoteAction {
        return RemoteAction(
            Icon.createWithResource(this, iconRes),
            title,
            title,
            pipPendingIntent(action, requestCode)
        )
    }

    /** PiP params with Previous / Play-Pause / Next transport actions. */
    private fun buildPipParams(): PictureInPictureParams {
        val actions = listOf(
            pipAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                ACTION_PIP_PREVIOUS,
                101
            ),
            pipAction(
                if (pipPlaying) {
                    android.R.drawable.ic_media_pause
                } else {
                    android.R.drawable.ic_media_play
                },
                if (pipPlaying) "Pause" else "Play",
                ACTION_PIP_PLAY_PAUSE,
                102
            ),
            pipAction(
                android.R.drawable.ic_media_next,
                "Next",
                ACTION_PIP_NEXT,
                103
            )
        )
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(actions)
            .build()
    }

    private fun registerPipReceiver() {
        if (pipReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                val name = when (action) {
                    ACTION_PIP_PLAY_PAUSE -> "playPause"
                    ACTION_PIP_NEXT -> "next"
                    ACTION_PIP_PREVIOUS -> "previous"
                    else -> return
                }
                pipChannel?.invokeMethod("onPipAction", name)
            }
        }
        pipReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(ACTION_PIP_PLAY_PAUSE)
            addAction(ACTION_PIP_NEXT)
            addAction(ACTION_PIP_PREVIOUS)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }

    override fun onDestroy() {
        pipReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Already unregistered — fine.
            }
        }
        pipReceiver = null
        super.onDestroy()
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
