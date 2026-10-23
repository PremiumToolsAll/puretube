package dev.puretube.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the process (and therefore the
 * plugin's ExoPlayer) alive while playback continues in the
 * background — SparkTube's model: the player never stops just
 * because the user left the app. The service itself is dumb; the
 * plugin drives it with START / PROMOTE / DEMOTE / STOP intents and
 * the notification's buttons broadcast back to
 * [PlaybackActionReceiver].
 */
class PlaybackForegroundService : Service() {
    companion object {
        const val ACTION_START = "dev.puretube.playback.fgs.START"
        const val ACTION_PROMOTE = "dev.puretube.playback.fgs.PROMOTE"
        const val ACTION_DEMOTE = "dev.puretube.playback.fgs.DEMOTE"
        const val ACTION_STOP = "dev.puretube.playback.fgs.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_UPLOADER = "uploader"
        const val EXTRA_PLAYING = "playing"
        private const val CHANNEL_ID = "puretube_playback"
        private const val NOTIFICATION_ID = 4213

        fun intent(
            context: Context,
            action: String,
            title: String?,
            uploader: String?,
            playing: Boolean
        ): Intent =
            Intent(context, PlaybackForegroundService::class.java)
                .setAction(action)
                .apply {
                    if (title != null) putExtra(EXTRA_TITLE, title)
                    if (uploader != null) putExtra(EXTRA_UPLOADER, uploader)
                    putExtra(EXTRA_PLAYING, playing)
                }
    }

    private var foreground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Playback",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        when (intent?.action) {
            ACTION_PROMOTE -> {
                startForeground(NOTIFICATION_ID, buildNotification(intent))
                foreground = true
            }
            ACTION_DEMOTE -> {
                if (foreground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    foreground = false
                }
            }
            ACTION_STOP -> {
                if (foreground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    foreground = false
                }
                stopSelf()
            }
            else -> Unit // ACTION_START: just exist.
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(intent: Intent): Notification {
        val title = intent.getStringExtra(EXTRA_TITLE)
            ?.takeIf { it.isNotBlank() } ?: "PureTube"
        val uploader = intent.getStringExtra(EXTRA_UPLOADER) ?: ""
        val playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )
        }
        val toggleIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(this, PlaybackActionReceiver::class.java)
                .setAction(PlaybackActionReceiver.ACTION_TOGGLE),
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getBroadcast(
            this, 2,
            Intent(this, PlaybackActionReceiver::class.java)
                .setAction(PlaybackActionReceiver.ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        )
        val icon = applicationInfo.icon.takeIf { it != 0 }
            ?: android.R.drawable.ic_media_play
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(uploader)
            .setContentIntent(contentIntent)
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                if (playing) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play,
                if (playing) "Pause" else "Play",
                toggleIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopIntent
            )
            .build()
    }
}
