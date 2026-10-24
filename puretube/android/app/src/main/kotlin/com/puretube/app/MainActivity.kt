package com.puretube.app

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
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
    private var orientationChannel: MethodChannel? = null

    // ---- landscape follow (fullscreen) ----
    // Flutter can ALLOW both landscape sides, but on many phones
    // (MIUI especially) the activity then sticks to one side and
    // never flips when the user turns the phone over. While the
    // full player is open, the accelerometer's gravity direction
    // decides the side DIRECTLY (no calibration — the first
    // attempt calibrated against the system's default pick, which
    // blessed the wrong side whenever fullscreen was entered from
    // portrait): gravity mostly along device +x means the phone's
    // top points LEFT -> LANDSCAPE; along -x, top points RIGHT ->
    // REVERSE_LANDSCAPE.
    private var sensorManager: SensorManager? = null
    private var accelListener: SensorEventListener? = null
    private var followDesired: Int = -1
    private var followStable: Int = 0
    private var followLastFlipMs: Long = 0L
    private var pipPlaying = false
    private var autoPipEnabled = false
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
        orientationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "pure_tube/orientation"
        )
        orientationChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLandscapeFollow" -> {
                    startLandscapeFollow()
                    result.success(null)
                }
                "stopLandscapeFollow" -> {
                    stopLandscapeFollow()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
                "setAutoPip" -> {
                    autoPipEnabled =
                        call.argument<Boolean>("enabled") ?: false
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

    private fun startLandscapeFollow() {
        followDesired = -1
        followStable = 0
        followLastFlipMs = 0L
        if (sensorManager == null) {
            sensorManager =
                getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        }
        if (accelListener == null) {
            accelListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    val ax = event.values[0]
                    val ay = event.values[1]
                    // Only a clear landscape hold counts: gravity
                    // mostly along the device's sideways axis.
                    if (Math.abs(ax) < 5.0f ||
                        Math.abs(ax) < Math.abs(ay) * 1.3f
                    ) {
                        followStable = 0
                        return
                    }
                    val desired = if (ax > 0) {
                        ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    } else {
                        ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                    }
                    if (desired == followDesired) {
                        followStable++
                    } else {
                        followDesired = desired
                        followStable = 1
                    }
                    if (followStable < 3) return
                    if (requestedOrientation == desired) return
                    val now = System.currentTimeMillis()
                    if (now - followLastFlipMs < 700) return
                    followLastFlipMs = now
                    requestedOrientation = desired
                }

                override fun onAccuracyChanged(
                    sensor: Sensor?,
                    accuracy: Int
                ) {
                }
            }
        }
        val sensor =
            sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (sensor != null) {
            sensorManager?.registerListener(
                accelListener, sensor, SensorManager.SENSOR_DELAY_UI
            )
        }
    }

    private fun stopLandscapeFollow() {
        accelListener?.let { sensorManager?.unregisterListener(it) }
        followDesired = -1
        followStable = 0
    }

    override fun onDestroy() {
        stopLandscapeFollow()
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

    /**
     * Auto-PiP: pressing Home (or otherwise leaving) while a video
     * is playing shrinks straight into the PiP window — playback
     * never stops. Dart enables this only while the full player is
     * open with a video actually playing. Tapping the PiP window
     * restores the activity (system behaviour), landing back on
     * the still-open player screen.
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPipEnabled &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !isInPipCompat()
        ) {
            try {
                enterPictureInPictureMode(buildPipParams())
            } catch (e: Exception) {
                // PiP refused (e.g. disabled in system settings):
                // background playback continues via the service.
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
