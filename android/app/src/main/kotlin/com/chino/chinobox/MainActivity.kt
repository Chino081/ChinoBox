package com.chino.chinobox

import android.app.PictureInPictureParams
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import com.chino.chinobox.dlna.DLNAManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_NEARBY_WIFI_DEVICES = 2301
        private const val PERMISSION_NEARBY_WIFI_DEVICES = "android.permission.NEARBY_WIFI_DEVICES"
        private const val SDK_TIRAMISU = 33
    }

    private lateinit var dlnaManager: DLNAManager
    private var pendingDlnaStartResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        dlnaManager = DLNAManager(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.chino.chinobox/player"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openExternal" -> openExternal(call, result)
                "enterPictureInPicture" -> enterPictureInPicture(result)
                "dlnaStartDiscovery" -> dlnaStartDiscovery(result)
                "dlnaStopDiscovery" -> dlnaStopDiscovery(result)
                "dlnaConnect" -> dlnaConnect(call, result)
                "dlnaDisconnect" -> dlnaDisconnect(result)
                "dlnaSetMedia" -> dlnaSetMedia(call, result)
                "dlnaPlay" -> dlnaPlay(result)
                "dlnaPause" -> dlnaPause(result)
                "dlnaStop" -> dlnaStop(result)
                "dlnaSeek" -> dlnaSeek(call, result)
                "dlnaSetVolume" -> dlnaSetVolume(call, result)
                "dlnaGetVolume" -> dlnaGetVolume(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.chino.chinobox/dlna_events"
        ).setStreamHandler(dlnaManager.eventStreamHandler)
    }

    private fun openExternal(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url").orEmpty()
        val title = call.argument<String>("title").orEmpty()
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        if (url.isBlank()) {
            result.error("empty_url", "播放地址为空", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(url), mimeTypeFor(url))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_TITLE, title)
            putExtra("title", title)
            if (headers.isNotEmpty()) {
                val bundle = Bundle()
                headers.forEach { (key, value) -> bundle.putString(key, value) }
                putExtra("android.media.intent.extra.HTTP_HEADERS", bundle)
                putExtra("headers", bundle)
            }
        }

        try {
            startActivity(Intent.createChooser(intent, if (title.isBlank()) "选择播放器" else title))
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("activity_not_found", "没有找到可用的外部播放器", null)
        } catch (error: Exception) {
            result.error("open_external_failed", error.message, null)
        }
    }

    private fun enterPictureInPicture(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("pip_unsupported", "当前 Android 版本不支持画中画", null)
            return
        }

        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
            result.success(null)
        } catch (error: Exception) {
            result.error("pip_failed", error.message, null)
        }
    }

    private fun mimeTypeFor(url: String): String {
        val lower = url.lowercase()
        return when {
            lower.contains(".m3u8") -> "application/vnd.apple.mpegurl"
            lower.contains(".mp4") -> "video/mp4"
            lower.contains(".mkv") -> "video/x-matroska"
            else -> "video/*"
        }
    }

    // --- DLNA Methods ---

    private fun dlnaStartDiscovery(result: MethodChannel.Result) {
        if (!ensureDlnaDiscoveryPermission(result)) return

        startDlnaDiscovery(result)
    }

    private fun startDlnaDiscovery(result: MethodChannel.Result) {
        try {
            dlnaManager.bind()
            result.success(null)
        } catch (e: Exception) {
            result.error("dlna_discovery_failed", e.message, null)
        }
    }

    private fun ensureDlnaDiscoveryPermission(result: MethodChannel.Result): Boolean {
        if (Build.VERSION.SDK_INT < SDK_TIRAMISU) return true
        if (checkSelfPermission(PERMISSION_NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED) {
            return true
        }
        if (pendingDlnaStartResult != null) {
            result.error("permission_request_in_progress", "正在请求投屏权限", null)
            return false
        }

        pendingDlnaStartResult = result
        try {
            requestPermissions(
                arrayOf(PERMISSION_NEARBY_WIFI_DEVICES),
                REQUEST_NEARBY_WIFI_DEVICES
            )
        } catch (error: Exception) {
            pendingDlnaStartResult = null
            result.error("permission_request_failed", error.message, null)
        }
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == REQUEST_NEARBY_WIFI_DEVICES) {
            val result = pendingDlnaStartResult
            pendingDlnaStartResult = null
            if (result == null) return

            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                startDlnaDiscovery(result)
            } else {
                result.error(
                    "nearby_wifi_permission_denied",
                    "未授权附近设备权限，无法搜索投屏设备",
                    null
                )
            }
            return
        }

        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun dlnaStopDiscovery(result: MethodChannel.Result) {
        try {
            dlnaManager.unbind()
            result.success(null)
        } catch (e: Exception) {
            result.error("dlna_stop_failed", e.message, null)
        }
    }

    private fun dlnaConnect(call: MethodCall, result: MethodChannel.Result) {
        val udn = call.argument<String>("udn")
        if (udn.isNullOrBlank()) {
            result.error("invalid_udn", "设备ID为空", null)
            return
        }
        dlnaManager.connect(udn, result)
    }

    private fun dlnaDisconnect(result: MethodChannel.Result) {
        dlnaManager.disconnect(result)
    }

    private fun dlnaSetMedia(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "播放地址为空", null)
            return
        }
        val title = call.argument<String>("title") ?: ""
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        dlnaManager.setMedia(url, title, headers, result)
    }

    private fun dlnaPlay(result: MethodChannel.Result) {
        dlnaManager.play(result)
    }

    private fun dlnaPause(result: MethodChannel.Result) {
        dlnaManager.pause(result)
    }

    private fun dlnaStop(result: MethodChannel.Result) {
        dlnaManager.stop(result)
    }

    private fun dlnaSeek(call: MethodCall, result: MethodChannel.Result) {
        val positionMs = call.argument<Number>("positionMs")?.toLong()
        if (positionMs == null) {
            result.error("invalid_position", "进度值无效", null)
            return
        }
        dlnaManager.seek(positionMs, result)
    }

    private fun dlnaSetVolume(call: MethodCall, result: MethodChannel.Result) {
        val volume = call.argument<Number>("volume")?.toInt()
        if (volume == null) {
            result.error("invalid_volume", "音量值无效", null)
            return
        }
        dlnaManager.setVolume(volume, result)
    }

    private fun dlnaGetVolume(result: MethodChannel.Result) {
        dlnaManager.getVolume(result)
    }

    override fun onDestroy() {
        dlnaManager.unbind()
        super.onDestroy()
    }
}
