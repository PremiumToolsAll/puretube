package com.puretube.app

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.dash.manifest.DashManifestParser
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import java.io.ByteArrayInputStream
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.dash.DashMediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
// NewPipeExtractor downloader (SparkTube-style).
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import kotlin.concurrent.thread

/**
 * Native HQ player ("Java code" path for high quality).
 *
 * Plays YouTube 1080p+ DASH streams through ExoPlayer (Media3) with
 * NewPipe's proven request shape, which mpv/media_kit cannot do:
 *  - HTTP POST with 2-byte body (0x78 0x00) for /videoplayback
 *  - incrementing &rn= parameter on every request
 *  - ranges as &range= URL param instead of the Range header (DASH)
 *  - desktop Firefox User-Agent, TE: trailers, Accept-Encoding: identity
 *
 * The DASH manifest is generated on the fly (OTF, like NewPipe's
 * YoutubeOtfDashManifestCreator): segments are addressed as
 * baseUrl&sq=$Number$, with the SegmentTimeline parsed from the
 * `Segment-Durations-Ms` response header of a real sq=0 request.
 *
 * Only used for explicit 1080p+ DASH selection. Everything else keeps
 * using mpv via media_kit, so the blast radius of this native code is
 * strictly the high-quality path.
 */
class HqPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var textures: TextureRegistry? = null
    private var appContext: android.content.Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val players = mutableMapOf<Long, HqPlayer>()
    private var nextId = 1L
    // Global request-number counter shared by all segment fetches
    // (NewPipe re-adds an incrementing &rn= per request).
    private val globalRn = java.util.concurrent.atomic.AtomicInteger(0)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "puretube_hq_player")
        channel?.setMethodCallHandler(this)
        textures = binding.textureRegistry
        appContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        players.values.forEach { it.release() }
        players.clear()
        textures = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val entry = textures?.createSurfaceTexture()
                if (entry == null) {
                    result.error("HQ_NO_TEXTURE", "TextureRegistry unavailable", null)
                    return
                }
                val id = nextId++
                players[id] = HqPlayer(id, entry)
                result.success(id)
            }
            "getNewPipeStreams" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId.isNullOrEmpty()) {
                    result.error("NP_NO_ID", "Missing videoId", null)
                    return
                }
                Thread {
                    try {
                        // Init NewPipe once (like SparkTube).
                        try {
                            org.schabi.newpipe.extractor.NewPipe.init(
                                SparkTubeDownloader(),
                                org.schabi.newpipe.extractor.localization.Localization("en", "US")
                            )
                        } catch (_: Exception) { /* already init */ }
                        val service = org.schabi.newpipe.extractor.ServiceList.YouTube
                        val extractor = service.getStreamExtractor("https://www.youtube.com/watch?v=$videoId")
                        extractor.fetchPage()
                        val videoStreams = extractor.videoStreams
                        val audioStreams = extractor.audioStreams
                        val videos = videoStreams.map { v ->
                            mapOf(
                                "url" to v.content,
                                "height" to v.height,
                                "codec" to (v.codec ?: ""),
                                "bitrate" to v.bitrate,
                                "fps" to v.fps,
                                "initStart" to v.initStart,
                                "initEnd" to v.initEnd,
                                "indexStart" to v.indexStart,
                                "indexEnd" to v.indexEnd,
                                "itag" to v.itag
                            )
                        }
                        val audios = audioStreams.map { a ->
                            mapOf(
                                "url" to a.content,
                                "codec" to (a.codec ?: ""),
                                "bitrate" to a.bitrate,
                                "initStart" to a.initStart,
                                "initEnd" to a.initEnd,
                                "indexStart" to a.indexStart,
                                "indexEnd" to a.indexEnd,
                                "itag" to a.itag
                            )
                        }
                        mainHandler.post {
                            result.success(mapOf("video" to videos, "audio" to audios))
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("NP_FAILED", "${e.javaClass.simpleName}: ${e.message}", null)
                        }
                    }
                }.start()
            }
            "loadDash" -> {
                val id = (call.argument<Number>("textureId"))?.toLong()
                val player = if (id != null) players[id] else null
                if (player == null) {
                    result.error("HQ_NO_PLAYER", "No HQ player for id $id", null)
                    return
                }
                player.loadDash(call.arguments as? Map<String, Any?> ?: emptyMap(), result)
            }
            "play" -> {
                val p = playerFor(call)
                if (p?.exo == null) result.error("HQ_NO_PLAYER", null, null)
                else {
                    p.exo!!.play()
                    result.success(null)
                }
            }
            "pause" -> {
                val p = playerFor(call)
                if (p?.exo == null) result.error("HQ_NO_PLAYER", null, null)
                else {
                    p.exo!!.pause()
                    result.success(null)
                }
            }
            "seekTo" -> {
                val p = playerFor(call)
                if (p?.exo == null) result.error("HQ_NO_PLAYER", null, null)
                else {
                    p.exo!!.seekTo((call.argument<Number>("positionMs"))?.toLong() ?: 0L)
                    result.success(null)
                }
            }
            "setSpeed" -> {
                val p = playerFor(call)
                if (p?.exo == null) result.error("HQ_NO_PLAYER", null, null)
                else {
                    p.exo!!.setPlaybackSpeed((call.argument<Number>("speed"))?.toFloat() ?: 1f)
                    result.success(null)
                }
            }
            "setVolume" -> {
                val p = playerFor(call)
                if (p?.exo == null) result.error("HQ_NO_PLAYER", null, null)
                else {
                    p.exo!!.volume = (call.argument<Number>("volume"))?.toFloat() ?: 1f
                    result.success(null)
                }
            }
            "getPosition" -> {
                val p = playerFor(call)
                result.success(p?.exo?.currentPosition ?: 0L)
            }
            "getDuration" -> {
                val p = playerFor(call)
                val d = p?.exo?.duration ?: C.TIME_UNSET
                result.success(if (d == C.TIME_UNSET) 0L else d)
            }
            "isPlaying" -> {
                val p = playerFor(call)
                result.success(p?.exo?.isPlaying == true)
            }
            "dispose" -> {
                val id = (call.argument<Number>("textureId"))?.toLong()
                val player = if (id != null) players.remove(id) else null
                player?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun playerFor(call: MethodCall): HqPlayer? {
        val id = (call.argument<Number>("textureId"))?.toLong() ?: return null
        return players[id]
    }

    // ------------------------------------------------------------------
    // One native player instance: ExoPlayer + SurfaceTexture.
    // ------------------------------------------------------------------
    private inner class HqPlayer(
        val id: Long,
        val textureEntry: TextureRegistry.SurfaceTextureEntry,
    ) {
        var exo: ExoPlayer? = null
            private set
        private var loadThread: Thread? = null
        private var surface: Surface? = null

        fun loadDash(args: Map<String, Any?>, result: MethodChannel.Result) {
            // Heavy work off the main thread.
            loadThread = thread(isDaemon = true, name = "hq-load-$id") {
                mainHandler.post {
                    try {
                        // Merged video+audio progressive streams.
                        // URLs now come from NewPipeExtractor (SparkTube-style).
                        prepareMerged(args)
                        result.success(null)
                    } catch (e: Exception) {
                        fail(result, "HQ_PREPARE_FAILED", e)
                    }
                }
            }
        }

        private fun fail(result: MethodChannel.Result, code: String, e: Exception) {
            result.error(code, "${e.javaClass.simpleName}: ${e.message}", null)
        }

        private fun prepareAndPlay(mpdXml: String, args: Map<String, Any?>) {
            releasePlayerOnly()
            val appContext = this@HqPlayerPlugin.appContext
                ?: throw IllegalStateException("HQ plugin not attached")
            // SparkTube-style on-demand DASH: manifest built from
            // initRange/indexRange (no probe), parsed with DashManifestParser,
            // played via DashMediaSource. Plain GET + Chrome UA.
            val dataSourceFactory = DefaultHttpDataSource.Factory()
                .setUserAgent(CHROME_UA)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(20000)
                .setAllowCrossProtocolRedirects(true)
            val manifestUri = Uri.parse("https://puretube.invalid/manifest.mpd")
            val manifest = DashManifestParser().parse(
                manifestUri,
                ByteArrayInputStream(mpdXml.toByteArray(Charsets.UTF_8))
            )
            val item = MediaItem.fromUri(manifestUri)
            val mediaSource = DashMediaSource.Factory(dataSourceFactory)
                .createMediaSource(manifest, item)
            val player = ExoPlayer.Builder(appContext).build()
            exo = player
            surface?.release()
            surface = Surface(textureEntry.surfaceTexture())
            player.setVideoSurface(surface)
            val speed = (args["speed"] as? Number)?.toFloat() ?: 1f
            if (speed != 1f) player.setPlaybackSpeed(speed)
            val startMs = (args["startPositionMs"] as? Number)?.toLong() ?: 0L
            player.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    val msg = PlaybackException.getErrorCodeName(
                        error.errorCode) + ": " + error.message
                    mainHandler.post {
                        channel?.invokeMethod(
                            "onHqError",
                            mapOf("textureId" to id, "message" to msg))
                    }
                }

                override fun onPlaybackStateChanged(state: Int) {
                    if (state == Player.STATE_READY) {
                        val vf = player.videoFormat
                        mainHandler.post {
                            channel?.invokeMethod(
                                "onHqReady",
                                mapOf("textureId" to id,
                                    "durationMs" to player.duration,
                                    "videoWidth" to (vf?.width ?: 0),
                                    "videoHeight" to (vf?.height ?: 0)))
                        }
                    } else if (state == Player.STATE_ENDED) {
                        mainHandler.post {
                            channel?.invokeMethod(
                                "onHqCompleted", mapOf("textureId" to id))
                        }
                    }
                }
            })
            player.setMediaSource(mediaSource)
            player.prepare()
            if (startMs > 0) player.seekTo(startMs)
            player.playWhenReady = true
        }

        // Fallback when init/index ranges are unavailable (e.g. Piped/
        // Invidious fallback): merge video+audio as progressive streams.
        private fun prepareMerged(args: Map<String, Any?>) {
            releasePlayerOnly()
            val appContext = this@HqPlayerPlugin.appContext
                ?: throw IllegalStateException("HQ plugin not attached")
            val dataSourceFactory = DefaultHttpDataSource.Factory()
                .setUserAgent(CHROME_UA)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(20000)
                .setAllowCrossProtocolRedirects(true)
            val videoUrl = args["videoUrl"] as? String
                ?: throw IllegalArgumentException("HQ: missing videoUrl")
            val audioUrl = args["audioUrl"] as? String
                ?: throw IllegalArgumentException("HQ: missing audioUrl")
            val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(MediaItem.fromUri(Uri.parse(videoUrl)))
            val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(MediaItem.fromUri(Uri.parse(audioUrl)))
            val mediaSource = MergingMediaSource(videoSource, audioSource)
            val player = ExoPlayer.Builder(appContext).build()
            exo = player
            surface?.release()
            surface = Surface(textureEntry.surfaceTexture())
            player.setVideoSurface(surface)
            val speed = (args["speed"] as? Number)?.toFloat() ?: 1f
            if (speed != 1f) player.setPlaybackSpeed(speed)
            val startMs = (args["startPositionMs"] as? Number)?.toLong() ?: 0L
            player.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    val msg = PlaybackException.getErrorCodeName(
                        error.errorCode) + ": " + error.message
                    mainHandler.post {
                        channel?.invokeMethod(
                            "onHqError",
                            mapOf("textureId" to id, "message" to msg))
                    }
                }
            })
            player.setMediaSource(mediaSource)
            player.prepare()
            if (startMs > 0) player.seekTo(startMs)
            player.playWhenReady = true
        }

        private fun releasePlayerOnly() {
            try {
                exo?.release()
            } catch (_: Exception) {
            }
            exo = null
            try {
                surface?.release()
            } catch (_: Exception) {
            }
            surface = null
        }

        fun release() {
            loadThread?.interrupt()
            loadThread = null
            mainHandler.post { releasePlayerOnly() }
            try {
                textureEntry.release()
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        // Must match NewPipe's UA verbatim: a non-existent future version
        // (e.g. rv:153) gets flagged by YouTube's edge.
        private const val HQ_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) " +
                "Gecko/20100101 Firefox/140.0"

        // SparkTube's UA for on-demand DASH: plain Chrome, no special
        // headers. This is what their working HQ playback uses.
        private const val CHROME_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/132.0.0.0 Safari/537.36"
    }

    // ------------------------------------------------------------------
    // NewPipe-shaped HTTP data source for /videoplayback.
    // ------------------------------------------------------------------
    private inner class HqDataSource : BaseDataSource(/* isNetwork= */ true) {
        private var inputStream: java.io.InputStream? = null
        private var bytesRemaining: Long = 0
        private var openedUri: Uri? = null
        private var transferActive = false

        override fun open(dataSpec: DataSpec): Long {
            val uri = dataSpec.uri
            // Our generated MPD rides a data: URI — serve it from memory.
            if (uri.scheme == "data") {
                val raw = uri.toString()
                val base64 = raw.substringAfter("base64,", "")
                if (base64.isEmpty()) throw IOException("HQ: empty data URI")
                val bytes = Base64.decode(base64, Base64.DEFAULT)
                inputStream = ByteArrayInputStream(bytes)
                bytesRemaining = bytes.size.toLong()
                openedUri = uri
                return bytesRemaining
            }
            var urlStr = stripParams(uri.toString(), setOf("sq", "rn", "alr"))
            val connection =
                (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    // SparkTube-style: plain GET with Chrome UA and standard
                    // HTTP Range headers (on-demand DASH).
                    requestMethod = "GET"
                    setRequestProperty("User-Agent", CHROME_UA)
                    val pos = dataSpec.position
                    val len = dataSpec.length
                    if (pos > 0 || len > 0) {
                        val rangeHeader = if (len > 0) {
                            "bytes=$pos-${pos + len - 1}"
                        } else {
                            "bytes=$pos-"
                        }
                        setRequestProperty("Range", rangeHeader)
                    }
                    connectTimeout = 15000
                    readTimeout = 30000
                    instanceFollowRedirects = true
                }
            transferInitializing(dataSpec)
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK &&
                code != HttpURLConnection.HTTP_PARTIAL
            ) {
                connection.disconnect()
                throw IOException("HQ: HTTP $code for ${uri.host}")
            }
            inputStream = connection.inputStream
            val contentLen = connection.contentLengthLong
            bytesRemaining =
                if (contentLen > 0) contentLen else C.LENGTH_UNSET.toLong()
            openedUri = uri
            transferActive = true
            transferStarted(dataSpec)
            return bytesRemaining
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            val stream = inputStream ?: return C.RESULT_END_OF_INPUT
            val read = stream.read(buffer, offset, length)
            if (read == -1) return C.RESULT_END_OF_INPUT
            if (bytesRemaining != C.LENGTH_UNSET.toLong()) bytesRemaining -= read
            bytesTransferred(read)
            return read
        }

        override fun getUri(): Uri? = openedUri

        override fun close() {
            openedUri = null
            try {
                inputStream?.close()
            } catch (_: Exception) {
            }
            inputStream = null
            if (transferActive) {
                transferActive = false
                transferEnded()
            }
        }
    }

    // ------------------------------------------------------------------
    // On-the-fly DASH manifest (ports NewPipe's YoutubeOtfDashManifestCreator).
    // ------------------------------------------------------------------
    // On-the-fly DASH manifest.
    // ------------------------------------------------------------------
    // NOTE: We do NOT use the sq=0 Segment-Durations-Ms probe — YouTube's edge
    // 403s it on some networks. Instead we measure the real segment duration
    // by parsing tfdt boxes from media segments (sq=1, sq=2) fetched through
    // the same POST path the player itself uses, and build the manifest with
    // a fixed SegmentTemplate duration.
    // On-demand DASH manifest (SparkTube-style, ports their DashSources).
    // ------------------------------------------------------------------
    // Uses isoff-on-demand profile with SegmentBase + indexRange. The
    // init/index byte ranges come straight from the player response
    // (initRange/indexRange) — NOTHING is fetched to build the manifest,
    // so there is no probe that can 403. Plain GET requests only.
    private fun buildOtfManifest(args: Map<String, Any?>): String {
        val videoUrl = args["videoUrl"] as? String
            ?: throw IllegalArgumentException("HQ: missing videoUrl")
        val audioUrl = args["audioUrl"] as? String
            ?: throw IllegalArgumentException("HQ: missing audioUrl")

        val vCodec = (args["videoCodec"] as? String).orEmpty()
            .ifEmpty { codecForItag(itagOf(videoUrl), true) }
        val aCodec = (args["audioCodec"] as? String).orEmpty()
            .ifEmpty { codecForItag(itagOf(audioUrl), false) }
        val height = (args["height"] as? Number)?.toInt() ?: 1080
        val width = (height * 16) / 9
        val fps = (args["fps"] as? Number)?.toInt() ?: 0
        val vBitrate = (args["videoBitrateBps"] as? Number)?.toLong() ?: 0L
        val aBitrate = (args["audioBitrateBps"] as? Number)?.toLong() ?: 0L
        val sampleRate = (args["audioSampleRate"] as? Number)?.toInt()
            .let { if (it == null || it <= 0) 44100 else it }

        // Byte ranges from the extractor (initRange/indexRange).
        val vInitS = (args["initStart"] as? Number)?.toLong() ?: -1L
        val vInitE = (args["initEnd"] as? Number)?.toLong() ?: -1L
        val vIdxS = (args["indexStart"] as? Number)?.toLong() ?: -1L
        val vIdxE = (args["indexEnd"] as? Number)?.toLong() ?: -1L
        val aInitS = (args["audioInitStart"] as? Number)?.toLong() ?: -1L
        val aInitE = (args["audioInitEnd"] as? Number)?.toLong() ?: -1L
        val aIdxS = (args["audioIndexStart"] as? Number)?.toLong() ?: -1L
        val aIdxE = (args["audioIndexEnd"] as? Number)?.toLong() ?: -1L
        if (vInitS < 0 || vInitE <= vInitS || vIdxS <= 0 || vIdxE <= vIdxS) {
            throw IOException("HQ: missing video init/index ranges")
        }
        if (aInitS < 0 || aInitE <= aInitS || aIdxS <= 0 || aIdxE <= aIdxS) {
            throw IOException("HQ: missing audio init/index ranges")
        }

        val totalSec = (args["durationSec"] as? Number)?.toLong() ?: 0L
        if (totalSec <= 0) throw IOException("HQ: missing duration")
        val mpdDuration = "PT${totalSec}S"
        val itagV = itagOf(videoUrl).ifEmpty { "0" }
        val itagA = itagOf(audioUrl).ifEmpty { "0" }

        fun esc(s: String): String = s
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace("\"", "&quot;")

        val fpsAttr = if (fps > 0) " frameRate=\"$fps\"" else ""
        val sb = StringBuilder(2048)
        sb.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
        sb.append("<MPD xmlns=\"urn:mpeg:dash:schema:mpd:2011\" ")
        sb.append("profiles=\"urn:mpeg:dash:profile:isoff-on-demand:2011\" type=\"static\" ")
        sb.append("mediaPresentationDuration=\"").append(mpdDuration).append("\" minBufferTime=\"PT1.5S\">")
        sb.append("<Period id=\"0\" duration=\"").append(mpdDuration).append("\">")
        // Video
        sb.append("<AdaptationSet id=\"0\" mimeType=\"video/mp4\" subsegmentAlignment=\"true\" startWithSAP=\"1\">")
        sb.append("<Representation id=\"").append(itagV).append("\" codecs=\"")
            .append(esc(vCodec)).append("\" bandwidth=\"").append(vBitrate)
            .append("\" width=\"").append(width).append("\" height=\"").append(height).append("\"")
        sb.append(fpsAttr).append(">")
        sb.append("<BaseURL>").append(esc(videoUrl)).append("</BaseURL>")
        sb.append("<SegmentBase indexRange=\"").append(vIdxS).append('-').append(vIdxE)
            .append("\"><Initialization range=\"").append(vInitS).append('-').append(vInitE)
            .append("\"/></SegmentBase>")
        sb.append("</Representation></AdaptationSet>")
        // Audio
        sb.append("<AdaptationSet id=\"1\" mimeType=\"audio/mp4\" subsegmentAlignment=\"true\" startWithSAP=\"1\">")
        sb.append("<Representation id=\"").append(itagA).append("\" codecs=\"")
            .append(esc(aCodec)).append("\" bandwidth=\"").append(aBitrate)
            .append("\" audioSamplingRate=\"").append(sampleRate).append("\">")
        sb.append("<AudioChannelConfiguration schemeIdUri=\"urn:mpeg:dash:23003:3:audio_channel_configuration:2011\" value=\"2\"/>")
        sb.append("<BaseURL>").append(esc(audioUrl)).append("</BaseURL>")
        sb.append("<SegmentBase indexRange=\"").append(aIdxS).append('-').append(aIdxE)
            .append("\"><Initialization range=\"").append(aInitS).append('-').append(aInitE)
            .append("\"/></SegmentBase>")
        sb.append("</Representation></AdaptationSet>")
        sb.append("</Period></MPD>")
        return sb.toString()
    }

    private fun measureSegmentMs(base: String, tag: String): Long {
        val initBytes = fetchSegmentBytes("$base&sq=0", tag, 8192)
        val timescale = parseMdhdTimescale(initBytes)
            ?: throw IOException("$tag: no timescale in init")
        val t1 = parseTfdt(fetchSegmentBytes("$base&sq=1", tag, 4096))
            ?: throw IOException("$tag: no tfdt in sq=1")
        val t2 = parseTfdt(fetchSegmentBytes("$base&sq=2", tag, 4096))
            ?: throw IOException("$tag: no tfdt in sq=2")
        val delta = t2 - t1
        if (delta <= 0 || timescale <= 0) {
            throw IOException("$tag: bad tfdt delta=$delta ts=$timescale")
        }
        val ms = (delta * 1000L) / timescale
        if (ms < 500 || ms > 30000) {
            throw IOException("$tag: implausible segMs=$ms")
        }
        return ms
    }

    /** Fetches the first [maxBytes] of a segment URL via POST (player shape). */
    private fun fetchSegmentBytes(url: String, tag: String, maxBytes: Int): ByteArray {
        val full = url + (if (url.contains("?")) "&" else "?") +
                "rn=${globalRn.getAndIncrement()}"
        val conn = (URL(full).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("User-Agent", HQ_UA)
            setRequestProperty("Origin", "https://www.youtube.com")
            setRequestProperty("Referer", "https://www.youtube.com")
            connectTimeout = 15000
            readTimeout = 15000
            instanceFollowRedirects = true
        }
        val code = conn.responseCode
        if (code != HttpURLConnection.HTTP_OK &&
            code != HttpURLConnection.HTTP_PARTIAL
        ) {
            conn.disconnect()
            throw IOException("$tag probe: HTTP $code")
        }
        return try {
            val inp = conn.inputStream
            val buf = ByteArray(maxBytes)
            var read = 0
            while (read < maxBytes) {
                val n = inp.read(buf, read, maxBytes - read)
                if (n < 0) break
                read += n
            }
            inp.close()
            buf.copyOf(read)
        } finally {
            conn.disconnect()
        }
    }

    /** Minimal MP4 box scanner: finds first box with the given 4-char type. */
    private fun findBox(data: ByteArray, type: String, start: Int = 0, end: Int = data.size): Int {
        var p = start
        val t = type.toByteArray(Charsets.US_ASCII)
        while (p + 8 <= end) {
            val size = ((data[p].toInt() and 0xFF) shl 24) or
                    ((data[p + 1].toInt() and 0xFF) shl 16) or
                    ((data[p + 2].toInt() and 0xFF) shl 8) or
                    (data[p + 3].toInt() and 0xFF)
            if (size < 8) break
            if (data[p + 4] == t[0] && data[p + 5] == t[1] &&
                data[p + 6] == t[2] && data[p + 7] == t[3]
            ) return p
            val ctype = String(data, p + 4, 4, Charsets.US_ASCII)
            if (ctype == "moof" || ctype == "traf" || ctype == "moov" ||
                ctype == "trak" || ctype == "mdia" || ctype == "minf" ||
                ctype == "stbl"
            ) {
                val inner = findBox(data, type, p + 8, minOf(p + size, end))
                if (inner >= 0) return inner
            }
            p += size
        }
        return -1
    }

    private fun u32(data: ByteArray, p: Int): Long =
        ((data[p].toLong() and 0xFF) shl 24) or
                ((data[p + 1].toLong() and 0xFF) shl 16) or
                ((data[p + 2].toLong() and 0xFF) shl 8) or
                (data[p + 3].toLong() and 0xFF)

    private fun u64(data: ByteArray, p: Int): Long =
        (u32(data, p) shl 32) or u32(data, p + 4)

    /** Parses timescale from mdhd inside the init segment. */
    private fun parseMdhdTimescale(data: ByteArray): Long? {
        val p = findBox(data, "mdhd")
        if (p < 0 || p + 32 > data.size) return null
        val version = data[p + 8].toInt() and 0xFF
        val tsPos = if (version == 1) p + 8 + 4 + 8 + 8 else p + 8 + 4 + 4 + 4
        if (tsPos + 4 > data.size) return null
        return u32(data, tsPos)
    }

    /** Parses baseMediaDecodeTime from tfdt inside a media segment. */
    private fun parseTfdt(data: ByteArray): Long? {
        val p = findBox(data, "tfdt")
        if (p < 0 || p + 16 > data.size) return null
        val version = data[p + 8].toInt() and 0xFF
        return if (version == 1) {
            if (p + 20 > data.size) null else u64(data, p + 12)
        } else {
            u32(data, p + 12)
        }
    }

    private fun stripParams(url: String, names: Set<String>): String {
        val qIndex = url.indexOf('?')
        if (qIndex < 0) return url
        val base = url.substring(0, qIndex)
        val query = url.substring(qIndex + 1).split("&")
            .filter { part ->
                val name = part.substringBefore("=")
                name !in names
            }
        return if (query.isEmpty()) base else "$base?${query.joinToString("&")}"
    }

    private fun itagOf(url: String): String {
        val m = Regex("[?&]itag=(\\d+)").find(url)
        return m?.groupValues?.get(1) ?: ""
    }

    /** Fallback codec strings when the extractor didn't supply full ones. */
    private fun codecForItag(itag: String, video: Boolean): String {
        return when (itag) {
            "137", "299" -> "avc1.640028"
            "136", "298" -> "avc1.4d401f"
            "140", "139" -> "mp4a.40.2"
            else -> if (video) "avc1.4d401f" else "mp4a.40.2"
        }
    }
}

// NewPipeExtractor Downloader (SparkTube's OkHttpDownloader ported to
// HttpURLConnection to avoid the OkHttp dependency).
private class SparkTubeDownloader : Downloader() {
    companion object {
        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"
    }

    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        val url = URL(request.url())
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = request.httpMethod()
            setRequestProperty("User-Agent", USER_AGENT)
            request.headers().forEach { (name, values) ->
                values.forEach { value -> addRequestProperty(name, value) }
            }
            connectTimeout = 15000
            readTimeout = 25000
            instanceFollowRedirects = true
        }
        if (request.dataToSend() != null) {
            conn.doOutput = true
            conn.outputStream.use { it.write(request.dataToSend()) }
        }
        val code = conn.responseCode
        val message = conn.responseMessage ?: ""
        val stream = if (code >= 400) conn.errorStream else conn.inputStream
        val body = stream?.readBytes()?.toString(Charsets.UTF_8) ?: ""
        val headers = conn.headerFields
            .filterKeys { it != null }
            .mapValues { it.value }
        conn.disconnect()
        return Response(code, message, headers, body, request.url())
    }
}
