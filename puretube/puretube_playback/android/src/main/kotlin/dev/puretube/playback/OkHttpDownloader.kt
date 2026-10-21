package dev.puretube.playback

import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.IOException
import java.util.Locale
import java.util.concurrent.TimeUnit

internal object OkHttpDownloader : Downloader() {
    private const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(25, TimeUnit.SECONDS).build()
    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        val builder = okhttp3.Request.Builder().url(request.url()).header("User-Agent", USER_AGENT)
        request.headers().forEach { (key, values) -> values.forEach { builder.addHeader(key, it) } }
        val body = request.dataToSend()
        when (request.httpMethod().uppercase(Locale.ROOT)) {
            "GET" -> builder.get()
            "HEAD" -> builder.head()
            "DELETE" -> builder.delete()
            "POST" -> builder.post((body ?: ByteArray(0)).toRequestBody())
            "PUT" -> builder.put((body ?: ByteArray(0)).toRequestBody())
            else -> throw IOException("Unsupported HTTP method: ${request.httpMethod()}")
        }
        client.newCall(builder.build()).execute().use { response ->
            if (response.code == 429) throw ReCaptchaException("reCaptcha Challenge requested", request.url())
            val finalUrl = response.request.url.toString()
            return Response(response.code, response.message, response.headers.toMultimap(), response.body?.string() ?: "", finalUrl)
        }
    }
}
