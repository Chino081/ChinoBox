package com.chino.chinobox

import android.app.PictureInPictureParams
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.chino.chinobox/player"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openExternal" -> openExternal(call, result)
                "enterPictureInPicture" -> enterPictureInPicture(result)
                else -> result.notImplemented()
            }
        }
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
}
