package dev.puretube.playback

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives the playback notification's button presses and forwards
 * them to the plugin instance (registered via [handler]).
 */
class PlaybackActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TOGGLE = "dev.puretube.playback.action.TOGGLE"
        const val ACTION_STOP = "dev.puretube.playback.action.STOP"

        @Volatile
        var handler: ((String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        handler?.invoke(action)
    }
}
