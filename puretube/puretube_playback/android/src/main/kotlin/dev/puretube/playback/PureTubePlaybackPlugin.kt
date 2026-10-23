package dev.puretube.playback

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.MediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.view.Surface
import io.flutter.view.TextureRegistry
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
    // Texture rendering (SparkTube PlaybackCenter model): ONE player,
    // ONE permanent render surface owned by the engine. Dart Texture
    // widgets are pure render targets — mounting/unmounting them (full
    // player, popup, PiP) can never pause, restart or black out the
    // video, unlike the old PlatformView whose surface lifecycle was
    // destroyed on every popup transition.
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var renderSurface: Surface? = null
    private var textureRegistry: TextureRegistry? = null
    private var activity: Activity? = null
    private var resumed = false
    private var lifecycleApp: Application? = null
    private var catalog: Catalog? = null
    private var currentUrl: String? = null
    private var requestedHeight: Int? = null
    private var resizeMode: Int = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
    // First-frame watchdog (SparkTube's VideoFramePolicy): playback can
    // report READY from audio alone while the video surface stays black.
    // If no frame renders within 8s of a load that should be visible,
    // recover in steps: rebind the output view, retry the source, then
    // surface a loud error.
    private var firstFrameSeen = true
    private var frameWaitStartMs = 0L
    private var frameRecoveryStep = 0
    // Background play (SparkTube model): leaving the app does NOT
    // pause the player; a foreground service keeps the process alive
    // with a media notification while playback continues.
    private val backgroundPlay = true
    private var serviceStarted = false
    private var lastServiceKey: String? = null
    // The app turns this OFF when its audio_service media session
    // already shows the one connected notification for this playback.
    private var notificationEnabled = true
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
        override fun onActivityResumed(a: Activity) { if (a === activity) { resumed = true; refreshService(); if (shouldAutoplay && !stopped) player?.play() } }
        override fun onActivityPaused(a: Activity) { if (a === activity) { resumed = false; if (backgroundPlay) refreshService() else pauseForBackground() } }
        override fun onActivityStopped(a: Activity) { if (a === activity) { resumed = false; if (backgroundPlay) refreshService() else pauseForBackground() } }
        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivityStarted(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }
    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) { emitState(); refreshService() }
        override fun onPlaybackStateChanged(playbackState: Int) { emitState(); refreshService() }
        override fun onRenderedFirstFrame() { firstFrameSeen = true; frameRecoveryStep = 0 }
        override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) { if (videoSize.width > 0 && videoSize.height > 0) try { textureEntry?.surfaceTexture()?.setDefaultBufferSize(videoSize.width, videoSize.height) } catch (_: Throwable) {}; emitState() }
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
        PlaybackActionReceiver.handler = { action -> main.post { handlePlaybackAction(action) } }
        // NOTE: the render SurfaceProducer is created LAZILY on first
        // use (ensureProducer), never here — creating it during engine
        // attach is the one startup change vs the last known-good
        // build, and attach must stay crash-proof.
        textureRegistry = binding.textureRegistry
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
            // Start optimistic: assume a fast line until measurements say
            // otherwise, so adaptive playback OPENS at a high quality
            // instead of crawling up from the bottom while the picture
            // looks blurry. A slow line downshifts within a few segments.
            .setBandwidthMeter(DefaultBandwidthMeter.Builder(context).setInitialBitrateEstimate(10_000_000L).build())
            .setLoadControl(DefaultLoadControl.Builder().setBufferDurationsMs(45_000, 120_000, 1_000, 5_000).setBackBuffer(30_000, true).build())
            .build().also { player = it; it.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true); it.setHandleAudioBecomingNoisy(true); it.addListener(playerListener); bindSurface() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val a = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        when (call.method) {
            "resolve" -> { val url = a["url"] as? String ?: return result.error("bad_arguments", "url is required", null); extract(url, result) }
            "search" -> { val q = a["query"] as? String ?: return result.error("bad_arguments", "query is required", null); search(q, result) }
            "load" -> {
                ensureTexture()
                val url = a["url"] as? String ?: return result.error("bad_arguments", "url is required", null)
                val id = generation.incrementAndGet(); currentUrl = url; requestedHeight = (a["height"] as? Number)?.toInt(); selectedAudioId = a["audioTrackId"] as? String
                disposed = false; audioOnly = a["audioOnly"] as? Boolean ?: false; shouldAutoplay = a["autoplay"] as? Boolean ?: true; stopped = false; retryingExpiry = false; fallbackStage = 0
                resolveAndLoad(url, requestedHeight, selectedAudioId, audioOnly, (a["positionMs"] as? Number)?.toLong() ?: 0L, shouldAutoplay, id, result)
            }
            "loadLocal" -> {
                ensureTexture()
                val path = a["path"] as? String ?: return result.error("bad_arguments", "path is required", null)
                val audioPath = a["audioPath"] as? String
                generation.incrementAndGet()
                // No remote URL: the HTTP-expiry retry and the
                // catalog fallbacks must never engage for files.
                currentUrl = null; catalog = null; requestedHeight = null; selectedAudioId = null
                disposed = false; audioOnly = a["audioOnly"] as? Boolean ?: false; shouldAutoplay = a["autoplay"] as? Boolean ?: true; stopped = false; retryingExpiry = false; fallbackStage = 0
                try {
                    installLocal(path, audioPath, audioOnly, (a["positionMs"] as? Number)?.toLong() ?: 0L, shouldAutoplay)
                    result.success(null)
                } catch (t: Throwable) {
                    result.error("load_failed", t.message ?: "Unable to play file", null)
                }
            }
            "loadDirect" -> {
                ensureTexture()
                val url = a["url"] as? String ?: return result.error("bad_arguments", "url is required", null)
                val audioUrl = a["audioUrl"] as? String
                generation.incrementAndGet()
                // Direct stream URLs resolved by the APP (fallback
                // for when the NewPipe resolve is blocked, e.g.
                // LOGIN_REQUIRED on a flagged IP): no catalog, so
                // the expiry re-resolve and catalog fallbacks can
                // never engage for them.
                currentUrl = null; catalog = null; requestedHeight = null; selectedAudioId = null
                disposed = false; audioOnly = a["audioOnly"] as? Boolean ?: false; shouldAutoplay = a["autoplay"] as? Boolean ?: true; stopped = false; retryingExpiry = false; fallbackStage = 0
                try {
                    installDirect(url, audioUrl, audioOnly, (a["positionMs"] as? Number)?.toLong() ?: 0L, shouldAutoplay)
                    result.success(null)
                } catch (t: Throwable) {
                    result.error("load_failed", t.message ?: "Unable to play stream", null)
                }
            }
            "setQuality" -> { requestedHeight = (a["height"] as? Number)?.toInt(); safeRebuild(result) }
            "setResizeMode" -> { resizeMode = (a["mode"] as? Number)?.toInt() ?: androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT; result.success(null) }
            "setNotificationEnabled" -> { notificationEnabled = a["enabled"] as? Boolean ?: true; refreshService(); result.success(null) }
            "textureId" -> result.success(ensureTexture()?.id())
            "setAudioTrack" -> { selectedAudioId = a["id"] as? String; safeRebuild(result) }
            "setAudioOnly" -> { audioOnly = a["enabled"] as? Boolean ?: false; safeRebuild(result) }
            "play" -> { stopped = false; shouldAutoplay = true; player?.play(); result.success(null) }
            "pause" -> { shouldAutoplay = false; player?.pause(); result.success(null) }
            "seek" -> { player?.seekTo((a["positionMs"] as? Number)?.toLong() ?: 0L); result.success(null) }
            "setMuted" -> { val muted = a["muted"] as? Boolean ?: false; player?.volume = if (muted) 0f else 1f; result.success(null) }
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
                    frameRecoveryStep = 0
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
                    if (height != null) {
                        // Explicit pick (SparkTube semantics): play that
                        // EXACT stream merged with audio — no adaptive
                        // downshift, so the quality the user selected is
                        // the quality that reaches the screen. (Adaptive
                        // DASH kept starting low and staying low on a
                        // conservatively-estimated line: "1080 selected
                        // but the picture is blurry".)
                        MergingMediaSource(ProgressiveMediaSource.Factory(factory).createMediaSource(videoItem), ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(selected.content)))
                    } else {
                        // Auto: adaptive DASH across every height.
                        DashSources.create(factory, videoItem, eligible, selected, c.info.duration)
                            ?: MergingMediaSource(ProgressiveMediaSource.Factory(factory).createMediaSource(videoItem), ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(selected.content)))
                    }
                }
                muxed != null -> ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(muxed.content))
                selected != null -> ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(selected.content))
                else -> throw IOException("No playable streams")
            }
        }
        fallbackStage = 0
        // Arm the first-frame watchdog for video loads (audio-only
        // loads have no frame to wait for). The recovery STEP is not
        // reset here: install() also serves rebuilds (quality/track
        // switches and the watchdog's own retry), and resetting the
        // step there would loop rebind/retry forever without ever
        // reaching the error step. Fresh loads reset it in
        // resolveAndLoad.
        firstFrameSeen = onlyAudio
        frameWaitStartMs = System.currentTimeMillis()
        bindSurface()
        p.setMediaSource(source); p.prepare(); if (pos > 0) p.seekTo(pos); if (autoplay && !stopped) p.play() else p.pause()
    }
    /** Plays a downloaded file (offline playback). A companion
     *  audio file (DASH downloads) is merged in, ExoPlayer-side —
     *  the role mpv's audio-file property used to fill. */
    private fun installLocal(path: String, audioPath: String?, onlyAudio: Boolean, pos: Long, autoplay: Boolean) {
        val p = ensurePlayer()
        val factory = DefaultDataSource.Factory(context)
        val videoSource = ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(android.net.Uri.fromFile(java.io.File(path))))
        val source: MediaSource = when {
            onlyAudio -> videoSource
            audioPath != null -> MergingMediaSource(
                videoSource,
                ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(android.net.Uri.fromFile(java.io.File(audioPath))))
            )
            else -> videoSource
        }
        firstFrameSeen = onlyAudio
        frameWaitStartMs = System.currentTimeMillis()
        bindSurface()
        p.setMediaSource(source); p.prepare(); if (pos > 0) p.seekTo(pos); if (autoplay && !stopped) p.play() else p.pause()
        emitState()
    }

    /** Plays app-resolved direct stream URLs (the LOGIN_REQUIRED
     *  fallback): a muxed file, or a video+audio pair merged
     *  natively — the same playback shape as install(), minus the
     *  NewPipe catalog. */
    private fun installDirect(url: String, audioUrl: String?, onlyAudio: Boolean, pos: Long, autoplay: Boolean) {
        val p = ensurePlayer()
        val factory = DefaultHttpDataSource.Factory().setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36")
        val source: MediaSource = when {
            onlyAudio -> ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(url))
            audioUrl != null -> MergingMediaSource(
                ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(url)),
                ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(audioUrl))
            )
            else -> ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(url))
        }
        p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, onlyAudio).build()
        firstFrameSeen = onlyAudio
        frameWaitStartMs = System.currentTimeMillis()
        bindSurface()
        p.setMediaSource(source); p.prepare(); if (pos > 0) p.seekTo(pos); if (autoplay && !stopped) p.play() else p.pause()
        emitState()
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
        p.setMediaSource(source); p.prepare(); if (pos > 0) p.seekTo(pos); if (shouldAutoplay && !stopped) p.play()
        return true
    }
    private fun safeRebuild(result: MethodChannel.Result) {
        try { rebuildPreserving(); result.success(null) } catch (t: Throwable) { result.error("load_failed", t.message ?: "Unable to rebuild playback", null) }
    }
    private fun rebuildPreserving() { val c = catalog ?: return; val pos = player?.currentPosition ?: 0L; val play = shouldAutoplay && (player?.playWhenReady ?: false); install(c, requestedHeight, selectedAudioId, audioOnly, pos, play) }
    private fun emitState() { val p = player ?: return; checkFrameWatchdog(p); emit(mapOf("type" to "state", "isPlaying" to p.isPlaying, "buffering" to (p.playbackState == Player.STATE_BUFFERING), "positionMs" to p.currentPosition.coerceAtLeast(0), "durationMs" to (p.duration.takeIf { it >= 0 } ?: 0L), "bufferedPositionMs" to p.bufferedPosition.coerceAtLeast(0), "ended" to (p.playbackState == Player.STATE_ENDED), "videoWidth" to p.videoSize.width, "videoHeight" to p.videoSize.height, "textureId" to (textureEntry?.id() ?: -1L), "firstFrame" to firstFrameSeen)) }

    /** SparkTube VideoFramePolicy: 8s without a rendered frame while
     *  playback should be visible → rebind output, retry source, error. */
    private fun checkFrameWatchdog(p: ExoPlayer) {
        if (firstFrameSeen || audioOnly || stopped || !shouldAutoplay || !p.playWhenReady) return
        if (p.playbackState != Player.STATE_READY && p.playbackState != Player.STATE_BUFFERING) return
        val now = System.currentTimeMillis()
        if (now - frameWaitStartMs < 8_000L) return
        when (frameRecoveryStep) {
            0 -> {
                // A dead surface is the usual suspect: rebinding it
                // changes nothing (the picture stayed black while
                // audio played), so throw it away and create a fresh
                // one — Dart adopts the new texture id from the
                // state event and rebuilds its Texture widget.
                recreateSurface()
                frameWaitStartMs = now; frameRecoveryStep = 1
            }
            1 -> {
                try { rebuildPreserving() } catch (_: Throwable) {}
                frameWaitStartMs = now; frameRecoveryStep = 2
            }
            2 -> {
                emit(mapOf("type" to "error", "code" to "no_video_frame", "message" to "ভিডিওর ছবি আসছে না"))
                frameRecoveryStep = 3
            }
            else -> Unit
        }
    }
    private fun emit(map: Map<String, Any?>) { main.post { sink?.success(map) } }
    /** Creates the render texture producer on FIRST use only and
     *  never lets a failure escape: a broken/absent producer degrades
     *  to audio-only playback instead of taking the app down. */
    /** Creates the render texture on FIRST use only (classic
     *  SurfaceTextureEntry — the path video_player has used for
     *  years on every Android skin; the newer SurfaceProducer's
     *  surface never produced a picture on the user's HyperOS
     *  phone: audio played, frames rendered nowhere). Never lets a
     *  failure escape: a broken texture degrades to audio-only
     *  playback instead of taking the app down. */
    private fun ensureTexture(): TextureRegistry.SurfaceTextureEntry? {
        textureEntry?.let { return it }
        val registry = textureRegistry ?: return null
        return try {
            val entry = registry.createSurfaceTexture()
            entry.surfaceTexture().setDefaultBufferSize(1280, 720)
            renderSurface = Surface(entry.surfaceTexture())
            textureEntry = entry
            bindSurface()
            entry
        } catch (_: Throwable) {
            null
        }
    }

    /** Throws the current render surface away and creates a fresh
     *  one (new texture id). The only cure for a surface whose
     *  BufferQueue died underneath the player (texture churn on
     *  HyperOS): the player keeps decoding, frames go nowhere, the
     *  picture stays black while audio plays. */
    private fun recreateSurface() {
        try { player?.setVideoSurface(null) } catch (_: Throwable) {}
        try { renderSurface?.release() } catch (_: Throwable) {}
        renderSurface = null
        try { textureEntry?.release() } catch (_: Throwable) {}
        textureEntry = null
        ensureTexture()
        emitState()
    }

    private fun bindSurface() {
        try {
            val surf = renderSurface
            if (surf != null) player?.setVideoSurface(surf)
        } catch (_: Throwable) {}
    }

    private fun pauseForBackground() { shouldAutoplay = false; player?.pause() }

    /** Keeps the foreground service in sync with playback: running
     *  while a session is alive, promoted (notification visible)
     *  whenever the app is in the background, demoted in foreground. */
    private fun refreshService() {
        if (!notificationEnabled) {
            // The app's media session carries the notification; this
            // service stays out of the way entirely.
            if (serviceStarted) {
                sendService(PlaybackForegroundService.ACTION_STOP, null, null, false)
                serviceStarted = false
            }
            return
        }
        val p = player
        val active = backgroundPlay && p != null && !stopped && !disposed && catalog != null
        if (!active) {
            if (serviceStarted) {
                sendService(PlaybackForegroundService.ACTION_STOP, null, null, false)
                serviceStarted = false
            }
            return
        }
        val title = catalog?.info?.name
        val uploader = try { catalog?.info?.uploaderName } catch (_: Throwable) { null }
        val playing = p!!.isPlaying
        if (!serviceStarted) {
            sendService(PlaybackForegroundService.ACTION_START, title, uploader, playing)
            serviceStarted = true
        }
        if (!resumed) {
            sendService(PlaybackForegroundService.ACTION_PROMOTE, title, uploader, playing)
        } else {
            sendService(PlaybackForegroundService.ACTION_DEMOTE, title, uploader, playing)
        }
    }

    private fun sendService(action: String, title: String?, uploader: String?, playing: Boolean) {
        // State events fire often; only forward real changes.
        val key = "$action|${title ?: ""}|$playing"
        if (action != PlaybackForegroundService.ACTION_STOP && key == lastServiceKey) return
        lastServiceKey = if (action == PlaybackForegroundService.ACTION_STOP) null else key
        val intent = PlaybackForegroundService.intent(context, action, title, uploader, playing)
        try {
            context.startService(intent)
        } catch (_: Throwable) {
            // Fully backgrounded: an ongoing media session may still
            // start its foreground service directly.
            try {
                if (action == PlaybackForegroundService.ACTION_PROMOTE) {
                    androidx.core.content.ContextCompat.startForegroundService(context, intent)
                }
            } catch (_: Throwable) {}
        }
    }

    private fun handlePlaybackAction(action: String) {
        val p = player ?: return
        when (action) {
            PlaybackActionReceiver.ACTION_TOGGLE -> {
                if (p.isPlaying) { shouldAutoplay = false; p.pause() }
                else if (!stopped && !disposed) { shouldAutoplay = true; p.play() }
            }
            PlaybackActionReceiver.ACTION_STOP -> {
                generation.incrementAndGet(); shouldAutoplay = false; stopped = true; p.stop()
            }
        }
        refreshService()
    }
    private fun disposePlayback() { generation.incrementAndGet(); player?.setVideoSurface(null); player?.removeListener(playerListener); player?.release(); player = null; catalog = null; currentUrl = null; stopped = true; shouldAutoplay = false; disposed = true; refreshService() }
    private fun validYoutube(raw: String): Boolean = try { val uri = android.net.Uri.parse(raw); uri.scheme == "https" && (uri.host?.lowercase() in setOf("youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com")) } catch (_: Throwable) { false }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity; resumed = false; disposed = false }
    override fun onDetachedFromActivityForConfigChanges() { activity?.let { if (!backgroundPlay && resumed) pauseForBackground() }; activity = null; resumed = false }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity; bindSurface(); refreshService() }
    override fun onDetachedFromActivity() { activity?.let { if (!backgroundPlay && resumed) pauseForBackground() }; activity = null; resumed = false }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { PlaybackActionReceiver.handler = null; disposePlayback(); try { renderSurface?.release() } catch (_: Throwable) {}; renderSurface = null; try { textureEntry?.release() } catch (_: Throwable) {}; textureEntry = null; textureRegistry = null; ticker?.let(main::removeCallbacks); ticker = null; lifecycleApp?.unregisterActivityLifecycleCallbacks(lifecycleCallbacks); lifecycleApp = null; methods.setMethodCallHandler(null); events.setStreamHandler(null); io.shutdownNow() }

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
