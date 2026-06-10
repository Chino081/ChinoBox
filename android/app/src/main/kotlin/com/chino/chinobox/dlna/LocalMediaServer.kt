package com.chino.chinobox.dlna

import android.util.Log
import fi.iki.elonen.NanoHTTPD
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/**
 * A local HTTP proxy server that serves media to DLNA devices on the LAN.
 * When the original media URL requires custom headers (Referer, User-Agent, etc.),
 * this server acts as a proxy: DLNA devices connect to this server, which forwards
 * requests to the upstream URL with the required headers injected.
 */
class LocalMediaServer(port: Int) : NanoHTTPD(getLanIp(), port) {
    companion object {
        private const val TAG = "LocalMediaServer"

        private fun getLanIp(): String {
            try {
                val interfaces = NetworkInterface.getNetworkInterfaces()
                while (interfaces.hasMoreElements()) {
                    val networkInterface = interfaces.nextElement()
                    if (networkInterface.isLoopback || !networkInterface.isUp) continue
                    val addresses = networkInterface.inetAddresses
                    while (addresses.hasMoreElements()) {
                        val address = addresses.nextElement()
                        if (address is Inet4Address && !address.isLoopbackAddress) {
                            return address.hostAddress ?: "0.0.0.0"
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to get LAN IP: $e")
            }
            return "0.0.0.0"
        }
    }

    // Map of token -> ProxiedUrlInfo
    private val proxiedUrls = ConcurrentHashMap<String, ProxiedUrlInfo>()

    data class ProxiedUrlInfo(
        val upstreamUrl: String,
        val headers: Map<String, String>
    )

    /**
     * Register an upstream URL with headers and return a local proxy URL
     * that DLNA devices can access.
     */
    fun createProxiedUrl(upstreamUrl: String, headers: Map<String, String>): String {
        val token = upstreamUrl.hashCode().toString(16) + "_" + System.currentTimeMillis()
        proxiedUrls[token] = ProxiedUrlInfo(upstreamUrl, headers)

        val host = getLanIp()
        val port = listeningPort
        // Use the last path segment from the upstream URL as filename
        val filename = try {
            val path = URL(upstreamUrl).path
            path.substringAfterLast('/').ifEmpty { "video" }
        } catch (e: Exception) {
            "video"
        }
        return "http://$host:$port/$token/$filename"
    }

    override fun serve(session: IHTTPSession): Response {
        val uri = session.uri
        // Extract token from URI: /<token>/<filename>
        val parts = uri.trimStart('/').split('/', limit = 2)
        if (parts.isEmpty() || parts[0].isEmpty()) {
            return newFixedLengthResponse(Response.Status.BAD_REQUEST, MIME_PLAINTEXT, "Missing token")
        }

        val token = parts[0]
        val info = proxiedUrls[token]
        if (info == null) {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Unknown token")
        }

        return proxyRequest(session, info)
    }

    private fun proxyRequest(session: IHTTPSession, info: ProxiedUrlInfo): Response {
        val headers = session.headers
        val rangeHeader = headers["range"]

        try {
            val connection = URL(info.upstreamUrl).openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 10000
            connection.readTimeout = 30000
            connection.instanceFollowRedirects = true

            // Inject custom headers
            for ((key, value) in info.headers) {
                connection.setRequestProperty(key, value)
            }

            // Forward range header if present
            if (rangeHeader != null) {
                connection.setRequestProperty("Range", rangeHeader)
            }

            connection.connect()

            val responseCode = connection.responseCode
            val contentType = connection.contentType ?: "video/mp4"
            val contentLength = connection.contentLength.toLong()

            val inputStream: InputStream = if (responseCode in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream ?: return newFixedLengthResponse(
                    Response.Status.INTERNAL_ERROR,
                    MIME_PLAINTEXT,
                    "Upstream error: $responseCode"
                )
            }

            val status = if (responseCode == 206) {
                Response.Status.PARTIAL_CONTENT
            } else {
                Response.Status.OK
            }

            val response = if (contentLength > 0) {
                newFixedLengthResponse(status, contentType, inputStream, contentLength)
            } else {
                newChunkedResponse(status, contentType, inputStream)
            }

            // Forward response headers
            connection.headerFields.forEach { (key, values) ->
                if (key != null && values.isNotEmpty()) {
                    when (key.lowercase()) {
                        "content-range", "content-length", "content-type",
                        "accept-ranges", "etag" -> {
                            response.addHeader(key, values.first())
                        }
                    }
                }
            }

            response.addHeader("Accept-Ranges", "bytes")
            return response

        } catch (e: IOException) {
            Log.e(TAG, "Proxy request failed: $e")
            return newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR,
                MIME_PLAINTEXT,
                "Proxy error: ${e.message}"
            )
        }
    }

    fun clearAll() {
        proxiedUrls.clear()
    }
}
