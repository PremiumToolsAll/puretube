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
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.dash.DashMediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayInputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
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
            // Heavy work (sq=0 fetches + MPD build) off the main thread.
            loadThread = thread(isDaemon = true, name = "hq-load-$id") {
                try {
                    val mpd = buildOtfManifest(args)
                    mainHandler.post {
                        try {
                            prepareAndPlay(mpd, args)
                            result.success(null)
                        } catch (e: Exception) {
                            fail(result, "HQ_PREPARE_FAILED", e)
                        }
                    }
                } catch (e: Exception) {
                    mainHandler.post { fail(result, "HQ_MANIFEST_FAILED", e) }
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
            val dataSourceFactory = DataSource.Factory { HqDataSource() }
            val dashFactory = DashMediaSource.Factory(dataSourceFactory)
            val mpdBase64 = Base64.encodeToString(
                mpdXml.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            val manifestUri =
                Uri.parse("data:application/dash+xml;base64,$mpdBase64")
            val mediaSource =
                dashFactory.createMediaSource(MediaItem.fromUri(manifestUri))
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
        private const val HQ_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:153.0) " +
                "Gecko/20100101 Firefox/153.0"
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
            var urlStr = stripParams(uri.toString(), setOf("rn"))
            // Ranges become &range= for DASH (never a Range header).
            val pos = dataSpec.position
            val len = dataSpec.length
            if (pos > 0 || len > 0) {
                val rangeParam = if (len > 0) {
                    "range=$pos-${pos + len - 1}"
                } else {
                    "range=$pos-"
                }
                urlStr += (if (urlStr.contains("?")) "&" else "?") + rangeParam
            }
            urlStr += (if (urlStr.contains("?")) "&" else "?") +
                "rn=${globalRn.getAndIncrement()}"
            val connection =
                (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    // NewPipe: "Most clients use POST requests to fetch contents".
                    requestMethod = "POST"
                    doOutput = true
                    setRequestProperty("User-Agent", HQ_UA)
                    setRequestProperty("TE", "trailers")
                    setRequestProperty("Accept-Encoding", "identity")
                    connectTimeout = 15000
                    readTimeout = 30000
                    instanceFollowRedirects = true
                }
            transferInitializing(dataSpec)
            // 2-byte body, like NewPipe's YoutubeHttpDataSource.
            connection.outputStream.use { it.write(byteArrayOf(0x78, 0x00)) }
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
    private fun buildOtfManifest(args: Map<String, Any?>): String {
        val videoUrl = args["videoUrl"] as? String
            ?: throw IllegalArgumentException("HQ: missing videoUrl")
        val audioUrl = args["audioUrl"] as? String
            ?: throw IllegalArgumentException("HQ: missing audioUrl")
        val (videoBase, videoDur) = fetchSq0(videoUrl)
        val (audioBase, audioDur) = fetchSq0(audioUrl)

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

        val vTimeline = timelineXml(parseDurations(videoDur))
        val aTimeline = timelineXml(parseDurations(audioDur))
        if (vTimeline.isEmpty() || aTimeline.isEmpty()) {
            throw IOException("HQ: empty segment timeline")
        }
        val totalMs = parseDurations(videoDur).sum()
        val mpdDuration = "PT%.3fS".format(totalMs / 1000.0)
        val itagV = itagOf(videoUrl).ifEmpty { "0" }
        val itagA = itagOf(audioUrl).ifEmpty { "0" }
        val dollar = "$"
        val numToken = "$dollar${"Number"}$dollar" // literal $Number$

        fun esc(s: String): String = s
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace("\"", "&quot;")

        val vInit = esc("$videoBase&sq=0")
        val vMedia = esc("$videoBase&sq=$numToken")
        val aInit = esc("$audioBase&sq=0")
        val aMedia = esc("$audioBase&sq=$numToken")
        val fpsAttr = if (fps > 0) " frameRate=\"$fps\"" else ""

        return """<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<MPD xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="urn:mpeg:DASH:schema:MPD:2011" xsi:schemaLocation="urn:mpeg:DASH:schema:MPD:2011 DASH-MPD.xsd" minBufferTime="PT1.500S" profiles="urn:mpeg:dash:profile:full:2011" type="static" mediaPresentationDuration="$mpdDuration">
<Period>
<AdaptationSet id="0" mimeType="video/mp4" subsegmentAlignment="true">
<Role schemeIdUri="urn:mpeg:DASH:role:2011" value="main"/>
<Representation id="$itagV" codecs="$vCodec" startWithSAP="1" maxPlayoutRate="1" bandwidth="$vBitrate" width="$width" height="$height"$fpsAttr>
<SegmentTemplate startNumber="1" timescale="1000" initialization="$vInit" media="$vMedia">
<SegmentTimeline>$vTimeline</SegmentTimeline>
</SegmentTemplate>
</Representation>
</AdaptationSet>
<AdaptationSet id="1" mimeType="audio/mp4" subsegmentAlignment="true">
<Role schemeIdUri="urn:mpeg:DASH:role:2011" value="main"/>
<Representation id="$itagA" codecs="$aCodec" startWithSAP="1" maxPlayoutRate="1" bandwidth="$aBitrate" audioSamplingRate="$sampleRate">
<AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2"/>
<SegmentTemplate startNumber="1" timescale="1000" initialization="$aInit" media="$aMedia">
<SegmentTimeline>$aTimeline</SegmentTimeline>
</SegmentTemplate>
</Representation>
</AdaptationSet>
</Period>
</MPD>"""
    }

    /**
     * Fetches sq=0 for a stream URL (plain GET is fine for ANDROID-client
     * URLs) and returns (de-redirected base URL, Segment-Durations-Ms).
     */
    private fun fetchSq0(streamUrl: String): Pair<String, String> {
        var url = stripParams(streamUrl, setOf("sq", "rn", "alr"))
        url += (if (url.contains("?")) "&" else "?") + "sq=0&rn=0"
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("User-Agent", HQ_UA)
            setRequestProperty("TE", "trailers")
            setRequestProperty("Accept-Encoding", "identity")
            connectTimeout = 15000
            readTimeout = 15000
            instanceFollowRedirects = true
        }
        conn.connect()
        try {
            val code = conn.responseCode
            if (code != HttpURLConnection.HTTP_OK) {
                throw IOException("HQ sq=0: HTTP $code")
            }
            val durations = conn.getHeaderField("Segment-Durations-Ms")
                ?: conn.getHeaderField("segment-durations-ms")
                ?: throw IOException("HQ sq=0: missing Segment-Durations-Ms")
            // Drain the init segment body.
            try {
                conn.inputStream.use { it.readBytes() }
            } catch (_: Exception) {
            }
            var finalUrl = conn.url.toString()
            finalUrl = stripParams(finalUrl, setOf("sq", "rn", "alr"))
            return finalUrl to durations
        } finally {
            conn.disconnect()
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
        if (!video) return "mp4a.40.2" // itag 140/139
        return when (itag) {
            "137" -> "avc1.640028"
            "136" -> "avc1.4d401f"
            "135", "134", "133", "160" -> "avc1.4d401f"
            "22", "18" -> "avc1.64001F"
            else -> "avc1.640028"
        }
    }

    private fun parseDurations(header: String): List<Long> {
        val out = mutableListOf<Long>()
        for (raw in header.split(",")) {
            val p = raw.trim()
            if (p.isEmpty()) continue
            val m = Regex("""(\d+)(?:\(r=(\d+)\))?""").matchEntire(p) ?: continue
            val d = m.groupValues[1].toLongOrNull() ?: continue
            val r = m.groupValues[2].toLongOrNull() ?: 0L
            repeat((r + 1).coerceAtMost(100000).toInt()) { out.add(d) }
        }
        return out
    }

    private fun timelineXml(durations: List<Long>): String {
        if (durations.isEmpty()) return ""
        val sb = StringBuilder()
        var i = 0
        while (i < durations.size) {
            val d = durations[i]
            var r = 0
            while (i + r + 1 < durations.size && durations[i + r + 1] == d) r++
            if (r > 0) sb.append("<S d=\"$d\" r=\"$r\"/>")
            else sb.append("<S d=\"$d\"/>")
            i += r + 1
        }
        return sb.toString()
    }
}
