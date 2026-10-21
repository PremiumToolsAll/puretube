package dev.puretube.playback

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.ui.PlayerView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.VideoStream
import org.schabi.newpipe.extractor.search.SearchInfo
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

@OptIn(UnstableApi::class)
class PureTubePlaybackPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val generation = AtomicLong(0)
    private var player: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var activity: Activity? = null
    private var resumed = false
    private var lifecycleApp: Application? = null
    private var catalog: Catalog? = null
    private var currentUrl: String? = null
    private var requestedHeight: Int? = null
    private var selectedAudioId: String? = null
    private var audioOnly = false
    private var shouldAutoplay = true
    private var stopped = false
    private var disposed = false
    private var retryingExpiry = false
    private var fallbackStage = 0
    private var fallbackVideo: VideoStream? = null
    private var fallbackAudio: AudioStream? = null
    private var ticker: Runnable? = null
    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(a: Activity) { if (a === activity) { resumed = true; if (shouldAutoplay && !stopped) player?.play() } }
        override fun onActivityPaused(a: Activity) { if (a === activity) { resumed = false; pauseForBackground() } }
        override fun onActivityStopped(a: Activity) { if (a === activity) { resumed = false; pauseForBackground() } }
        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivityStarted(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }
    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) = emitState()
        override fun onPlaybackStateChanged(playbackState: Int) { emitState() }
        override fun onPlayerError(error: PlaybackException) {
            val p = player
            if (!retryingExpiry && error.errorCode == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS && currentUrl != null) {
                retryingExpiry = true
                resolveAndLoad(currentUrl!!, requestedHeight, selectedAudioId, audioOnly, p?.currentPosition ?: 0L, shouldAutoplay, generation.incrementAndGet())
            } else if (fallbackStage < 2 && tryFallback()) {
                fallbackStage++
            } else emit(mapOf("type" to "error", "code" to "playback_${error.errorCode}", "message" to (error.message ?: "Playback failed")))
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        NewPipe.init(OkHttpDownloader)
        methods = MethodChannel(binding.binaryMessenger, "puretube_playback/methods")
        events = EventChannel(binding.binaryMessenger, "puretube_playback/events")
        methods.setMethodCallHandler(this); events.setStreamHandler(this)
        binding.platformViewRegistry.registerViewFactory("puretube_playback/view", ViewFactory())
        lifecycleApp = context.applicationContext as? Application
        lifecycleApp?.registerActivityLifecycleCallbacks(lifecycleCallbacks)
        ensurePlayer()
        val stateTicker = object : Runnable { override fun run() { emitState(); main.postDelayed(this, 500) } }
        ticker = stateTicker
        main.post(stateTicker)
    }

    private fun ensurePlayer(): ExoPlayer {
        return player ?: ExoPlayer.Builder(context)
            .setRenderersFactory(DefaultRenderersFactory(context).setEnableDecoderFallback(true))
            .setLoadControl(DefaultLoadControl.Builder().setBufferDurationsMs(45_000, 120_000, 1_000, 5_000).setBackBuffer(30_000, true).build())
            .build().also { player = it; it.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true); it.setHandleAudioBecomingNoisy(true); it.addListener(playerListener); playerView?.player = it }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val a = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        when (call.method) {
            "resolve" -> { val url = a["url"] as? String ?: return result.error("bad_arguments", "url is required", null); extract(url, result) }
            "search" -> { val q = a["query"] as? String ?: return result.error("bad_arguments", "query is required", null); search(q, result) }
            "load" -> {
                val url = a["url"] as? String ?: return result.error("bad_arguments", "url is required", null)
                val id = generation.incrementAndGet(); currentUrl = url; requestedHeight = (a["height"] as? Number)?.toInt(); selectedAudioId = a["audioTrackId"] as? String
                disposed = false; audioOnly = a["audioOnly"] as? Boolean ?: false; shouldAutoplay = a["autoplay"] as? Boolean ?: true; stopped = false; retryingExpiry = false; fallbackStage = 0
                resolveAndLoad(url, requestedHeight, selectedAudioId, audioOnly, (a["positionMs"] as? Number)?.toLong() ?: 0L, shouldAutoplay, id, result)
            }
            "setQuality" -> { requestedHeight = (a["height"] as? Number)?.toInt(); safeRebuild(result) }
            "setAudioTrack" -> { selectedAudioId = a["id"] as? String; safeRebuild(result) }
            "setAudioOnly" -> { audioOnly = a["enabled"] as? Boolean ?: false; safeRebuild(result) }
            "play" -> { stopped = false; shouldAutoplay = true; if (resumed) player?.play(); result.success(null) }
            "pause" -> { shouldAutoplay = false; player?.pause(); result.success(null) }
            "seek" -> { player?.seekTo((a["positionMs"] as? Number)?.toLong() ?: 0L); result.success(null) }
            "setSpeed" -> { val speed = (a["speed"] as? Number)?.toFloat(); if (speed == null || speed <= 0f) result.error("bad_arguments", "speed must be positive", null) else { player?.setPlaybackSpeed(speed); result.success(null) } }
            "stop" -> { generation.incrementAndGet(); shouldAutoplay = false; stopped = true; player?.stop(); result.success(null) }
            "dispose" -> { disposePlayback(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun extract(url: String, result: MethodChannel.Result) {
        if (!validYoutube(url)) return result.error("invalid_url", "Only YouTube video URLs are supported", null)
        io.execute { try { val c = Catalog(StreamInfo.getInfo(ServiceList.YouTube, url)); main.post { result.success(c.toMap()) } } catch (t: Throwable) { main.post { result.error("resolve_failed", t.message ?: "Unable to resolve video", null) } } }
    }
    private fun search(query: String, result: MethodChannel.Result) {
        if (query.isBlank()) return result.success(emptyList<Map<String, Any?>>())
        io.execute { try {
            val service = ServiceList.YouTube
            val handler = service.searchQHFactory.fromQuery(query.trim(), emptyList(), null)
            val info = SearchInfo.getInfo(service, handler)
            val entries = info.relatedItems.filterIsInstance<org.schabi.newpipe.extractor.stream.StreamInfoItem>().filter { it.duration > 0 }
                .mapNotNull { item -> val url = item.url?.takeIf(::validYoutube) ?: return@mapNotNull null; mapOf("url" to url, "title" to item.name.orEmpty(), "uploader" to item.uploaderName.orEmpty(), "thumbnailUrl" to (item.thumbnails.maxByOrNull { it.height }?.url.orEmpty()), "durationMs" to item.duration * 1000L) }
            main.post { result.success(entries) }
        } catch (t: Throwable) { main.post { result.error("search_failed", t.message ?: "Search failed", null) } } }
    }
    private fun resolveAndLoad(url: String, height: Int?, track: String?, onlyAudio: Boolean, pos: Long, autoplay: Boolean, id: Long, result: MethodChannel.Result? = null) {
        if (!validYoutube(url)) { result?.error("invalid_url", "Only YouTube video URLs are supported", null); return }
        io.execute {
            try {
                val c = Catalog(StreamInfo.getInfo(ServiceList.YouTube, url))
                main.post {
                    if (id != generation.get() || disposed) { result?.error("superseded", "Load was superseded", null); return@post }
                    if (c.info.duration <= 0) { result?.error("unsupported_live", "Live streams are not supported", null); return@post }
                    catalog = c
                    try { install(c, height, track, onlyAudio, pos, shouldAutoplay); emit(mapOf("type" to "catalog") + c.toMap()); result?.success(c.toMap()) }
                    catch (t: Throwable) { result?.error("load_failed", t.message ?: "Unable to load", null); emit(mapOf("type" to "error", "code" to "load_failed", "message" to (t.message ?: "Unable to load"))) }
                }
            } catch (t: Throwable) { main.post { if (id == generation.get() && !disposed) { result?.error("resolve_failed", t.message ?: "Unable to resolve", null); emit(mapOf("type" to "error", "code" to "resolve_failed", "message" to (t.message ?: "Unable to resolve"))) } else result?.error("superseded", "Load was superseded", null) } }
        }
    }
    private fun install(c: Catalog, height: Int?, track: String?, onlyAudio: Boolean, pos: Long, autoplay: Boolean) {
        val p = ensurePlayer()
        val selected = c.bestAudio(track)
        val eligible = c.video.filter { it.height > 0 }.let { all -> if (height != null) all.filter { it.height <= height } else all }
        val chosenVideo = eligible.maxWithOrNull(compareBy<VideoStream> { it.height }.thenBy { it.fps }.thenBy { it.bitrate })
        fallbackVideo = chosenVideo; fallbackAudio = selected
        val muxed = c.muxed.filter { height == null || it.height <= height }.ifEmpty { c.muxed }.maxByOrNull { it.height }
        val factory = DefaultHttpDataSource.Factory().setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36")
        val source: MediaSource = if (onlyAudio) {
            when {
                selected != null -> ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(selected.content))
                muxed != null -> { p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, true).build(); ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(muxed.content)) }
                else -> throw IOException("No playable audio stream")
            }
        } else {
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, false).build()
            when {
                chosenVideo != null && selected != null -> {
                    val videoItem = MediaItem.fromUri(chosenVideo.content)
                    DashSources.create(factory, videoItem, eligible, selected, c.info.duration)
                        ?: MergingMediaSource(ProgressiveMediaSource.Factory(factory).createMediaSource(videoItem), ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(selected.content)))
                }
                muxed != null -> ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(muxed.content))
                selected != null -> ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(selected.content))
                else -> throw IOException("No playable streams")
            }
        }
        fallbackStage = 0
        p.setMediaSource(source); p.prepare(); if (pos > 0) p.seekTo(pos); if (autoplay && resumed && !stopped) p.play() else p.pause()
    }
    private fun tryFallback(): Boolean {
        val c = catalog ?: return false
        val p = player ?: return false
        val pos = p.currentPosition
        val factory = DefaultHttpDataSource.Factory().setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36")
        val source: MediaSource = if (fallbackStage == 0 && fallbackVideo != null && fallbackAudio != null && !audioOnly) {
            MergingMediaSource(
                ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(fallbackVideo!!.content)),
                ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(fallbackAudio!!.content))
            )
        } else {
            if (fallbackStage >= 2) return false
            val muxed = c.muxed.filter { requestedHeight == null || it.height <= requestedHeight!! }.maxByOrNull { it.height } ?: return false
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, audioOnly).build()
            ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(muxed.content))
        }
        p.setMediaSource(source); p.prepare(); if (pos > 0) p.seekTo(pos); if (shouldAutoplay && resumed && !stopped) p.play()
        return true
    }
    private fun safeRebuild(result: MethodChannel.Result) {
        try { rebuildPreserving(); result.success(null) } catch (t: Throwable) { result.error("load_failed", t.message ?: "Unable to rebuild playback", null) }
    }
    private fun rebuildPreserving() { val c = catalog ?: return; val pos = player?.currentPosition ?: 0L; val play = shouldAutoplay && (player?.playWhenReady ?: false); install(c, requestedHeight, selectedAudioId, audioOnly, pos, play) }
    private fun emitState() { val p = player ?: return; emit(mapOf("type" to "state", "isPlaying" to p.isPlaying, "buffering" to (p.playbackState == Player.STATE_BUFFERING), "positionMs" to p.currentPosition.coerceAtLeast(0), "durationMs" to (p.duration.takeIf { it >= 0 } ?: 0L), "bufferedPositionMs" to p.bufferedPosition.coerceAtLeast(0), "ended" to (p.playbackState == Player.STATE_ENDED))) }
    private fun emit(map: Map<String, Any?>) { main.post { sink?.success(map) } }
    private fun pauseForBackground() { shouldAutoplay = false; player?.pause() }
    private fun disposePlayback() { generation.incrementAndGet(); playerView?.player = null; player?.removeListener(playerListener); player?.release(); player = null; catalog = null; currentUrl = null; stopped = true; shouldAutoplay = false; disposed = true }
    private fun validYoutube(raw: String): Boolean = try { val uri = android.net.Uri.parse(raw); uri.scheme == "https" && (uri.host?.lowercase() in setOf("youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com")) } catch (_: Throwable) { false }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity; resumed = false; disposed = false }
    override fun onDetachedFromActivityForConfigChanges() { activity?.let { if (resumed) pauseForBackground() }; activity = null; resumed = false }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity; playerView?.player = player }
    override fun onDetachedFromActivity() { activity?.let { if (resumed) pauseForBackground() }; activity = null; resumed = false }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { disposePlayback(); ticker?.let(main::removeCallbacks); ticker = null; lifecycleApp?.unregisterActivityLifecycleCallbacks(lifecycleCallbacks); lifecycleApp = null; methods.setMethodCallHandler(null); events.setStreamHandler(null); io.shutdownNow() }

    private inner class ViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView = PlaybackView(context)
    }
    private inner class PlaybackView(ctx: Context) : PlatformView {
        private val view = LayoutInflater.from(ctx).inflate(R.layout.puretube_player, null, false) as PlayerView
        init { view.useController = false; view.setKeepContentOnPlayerReset(true); view.player = ensurePlayer(); playerView = view }
        override fun getView(): View = view
        override fun dispose() { if (playerView === view) { view.player = null; playerView = null } }
    }

    private data class Catalog(val info: StreamInfo) {
        val video: List<VideoStream> = info.videoOnlyStreams.filter { it.isUrl && it.height > 0 }.sortedWith(compareByDescending<VideoStream> { it.height }.thenByDescending { it.fps }.thenByDescending { it.bitrate })
        val muxed: List<VideoStream> = info.videoStreams.filter { it.isUrl && it.height > 0 }.sortedByDescending { it.height }
        val audio: List<AudioStream> = info.audioStreams.filter { it.isUrl }
        fun bestAudio(track: String?): AudioStream? {
            val groups = audio.groupBy { it.audioTrackId ?: it.audioTrackName ?: "default" }
            val selectedGroup = groups[track] ?: groups.values.firstOrNull { it.first().audioTrackType?.name == "ORIGINAL" } ?: groups.values.firstOrNull()
            return selectedGroup?.maxByOrNull { it.averageBitrate }
        }
        fun toMap(): Map<String, Any?> {
            val tracks = audio.groupBy { it.audioTrackId ?: it.audioTrackName ?: "default" }.map { (id, list) ->
                val original = list.any { it.audioTrackType?.name == "ORIGINAL" }
                mapOf("id" to id, "label" to (list.first().audioTrackName?.takeIf { it.isNotBlank() } ?: if (id == "default") "Default" else id), "isOriginal" to original)
            }.sortedWith(compareByDescending<Map<String, Any?>> { it["isOriginal"] as Boolean }.thenBy { it["label"].toString().lowercase() })
            val title = info.name.orEmpty(); val qualities = (video + muxed).map { it.height }.filter { it > 0 }.distinct().sortedDescending()
            return mapOf("url" to info.url.orEmpty(), "title" to title, "durationMs" to info.duration * 1000L, "qualities" to qualities, "audioTracks" to tracks, "hasVideo" to (video.isNotEmpty() || muxed.isNotEmpty()))
        }
    }
}
