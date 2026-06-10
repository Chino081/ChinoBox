package com.chino.chinobox.dlna

import android.app.Activity
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.cast.dlna.dmc.DLNACastManager
import com.android.cast.dlna.dmc.OnDeviceRegistryListener
import com.android.cast.dlna.dmc.control.DeviceControl
import com.android.cast.dlna.dmc.control.OnDeviceControlListener
import com.android.cast.dlna.dmc.control.ServiceActionCallback
import io.flutter.plugin.common.EventChannel
import org.fourthline.cling.model.meta.Device
import org.fourthline.cling.support.lastchange.EventedValue
import org.fourthline.cling.support.model.PositionInfo
import org.fourthline.cling.support.model.TransportState

class DLNAManager(private val activity: Activity) {
    companion object {
        private const val TAG = "DLNAManager"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var multicastLock: WifiManager.MulticastLock? = null
    private var deviceControl: DeviceControl? = null
    private var currentDevice: Device<*, *, *>? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isBound = false
    private var positionPolling = false
    private var localMediaServer: LocalMediaServer? = null

    private val discoveredDevices = mutableListOf<Device<*, *, *>>()

    val eventStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    }

    fun bind() {
        if (isBound) return
        acquireMulticastLock()
        DLNACastManager.bindCastService(activity)
        DLNACastManager.registerDeviceListener(deviceListener)
        isBound = true
        Log.i(TAG, "DLNA service bound")
    }

    fun unbind() {
        if (!isBound) return
        stopPositionPolling()
        disconnect(null)
        DLNACastManager.unregisterListener(deviceListener)
        DLNACastManager.unbindCastService(activity)
        releaseMulticastLock()
        stopLocalMediaServer()
        isBound = false
        discoveredDevices.clear()
        Log.i(TAG, "DLNA service unbound")
    }

    private fun acquireMulticastLock() {
        try {
            val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("chinobox_dlna").apply {
                setReferenceCounted(true)
                acquire()
            }
            Log.i(TAG, "MulticastLock acquired")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire MulticastLock: $e")
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.let {
                if (it.isHeld) it.release()
            }
            multicastLock = null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release MulticastLock: $e")
        }
    }

    // --- Device Discovery ---

    private val deviceListener = object : OnDeviceRegistryListener {
        override fun onDeviceAdded(device: Device<*, *, *>) {
            if (!isMediaRenderer(device)) return
            mainHandler.post {
                if (!discoveredDevices.contains(device)) {
                    discoveredDevices.add(device)
                    sendDevicesChanged()
                }
            }
        }

        override fun onDeviceRemoved(device: Device<*, *, *>) {
            mainHandler.post {
                if (discoveredDevices.remove(device)) {
                    sendDevicesChanged()
                }
                if (device == currentDevice) {
                    sendEvent(mapOf("type" to "disconnected"))
                    currentDevice = null
                    deviceControl = null
                }
            }
        }
    }

    private fun isMediaRenderer(device: Device<*, *, *>): Boolean {
        val type = device.type?.toString() ?: return false
        return type.contains("MediaRenderer")
    }

    private fun sendDevicesChanged() {
        val devices = discoveredDevices.map { d ->
            mapOf(
                "udn" to (d.identity?.udn?.toString() ?: ""),
                "name" to (d.details?.friendlyName ?: "Unknown"),
                "manufacturer" to (d.details?.manufacturerDetails?.manufacturer ?: "")
            )
        }
        sendEvent(mapOf("type" to "devicesChanged", "devices" to devices))
    }

    // --- Connection ---

    fun connect(udn: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        val device = discoveredDevices.find { it.identity?.udn?.toString() == udn }
        if (device == null) {
            result.error("device_not_found", "未找到设备", null)
            return
        }

        val previousDevice = currentDevice
        if (previousDevice != null) {
            DLNACastManager.disconnectDevice(previousDevice)
        }

        currentDevice = device
        deviceControl = DLNACastManager.connectDevice(device, object : OnDeviceControlListener {
            override fun onConnected(device: Device<*, *, *>) {
                mainHandler.post {
                    sendEvent(mapOf(
                        "type" to "connected",
                        "deviceName" to (device.details?.friendlyName ?: "")
                    ))
                    result.success(null)
                }
            }

            override fun onDisconnected(device: Device<*, *, *>) {
                mainHandler.post {
                    sendEvent(mapOf("type" to "disconnected"))
                    currentDevice = null
                    deviceControl = null
                }
            }

            override fun onEventChanged(eventedValue: EventedValue<*>) {}

            override fun onAvTransportStateChanged(state: TransportState) {
                mainHandler.post {
                    sendEvent(mapOf(
                        "type" to "transportStateChanged",
                        "state" to state.name
                    ))
                }
            }

            override fun onRendererVolumeChanged(volume: Int) {
                mainHandler.post {
                    sendEvent(mapOf("type" to "volumeChanged", "volume" to volume))
                }
            }

            override fun onRendererVolumeMuteChanged(muted: Boolean) {}
        })
    }

    fun disconnect(result: io.flutter.plugin.common.MethodChannel.Result?) {
        stopPositionPolling()
        val device = currentDevice
        if (device != null) {
            DLNACastManager.disconnectDevice(device)
        }
        deviceControl = null
        currentDevice = null
        sendEvent(mapOf("type" to "disconnected"))
        result?.success(null)
    }

    // --- Playback Control ---

    fun setMedia(url: String, title: String, headers: Map<String, String>, result: io.flutter.plugin.common.MethodChannel.Result) {
        val control = deviceControl
        if (control == null) {
            result.error("not_connected", "未连接投屏设备", null)
            return
        }

        var playUrl = url
        // If URL needs custom headers, serve via local proxy
        if (headers.isNotEmpty()) {
            playUrl = serveViaLocalProxy(url, headers)
        }

        control.setAVTransportURI(playUrl, "", object : ServiceActionCallback<Unit> {
            override fun onSuccess(data: Unit) {
                mainHandler.post {
                    Log.i(TAG, "SetAVTransportURI success: $playUrl")
                    result.success(null)
                }
            }

            override fun onFailure(msg: String) {
                mainHandler.post {
                    Log.e(TAG, "SetAVTransportURI failed: $msg")
                    result.error("set_media_failed", msg, null)
                }
            }
        })
    }

    fun play(result: io.flutter.plugin.common.MethodChannel.Result) {
        val control = deviceControl
        if (control == null) {
            result.error("not_connected", "未连接投屏设备", null)
            return
        }

        control.play("1", object : ServiceActionCallback<Unit> {
            override fun onSuccess(data: Unit) {
                mainHandler.post {
                    startPositionPolling()
                    result.success(null)
                }
            }

            override fun onFailure(msg: String) {
                mainHandler.post { result.error("play_failed", msg, null) }
            }
        })
    }

    fun pause(result: io.flutter.plugin.common.MethodChannel.Result) {
        val control = deviceControl
        if (control == null) {
            result.error("not_connected", "未连接投屏设备", null)
            return
        }

        control.pause(object : ServiceActionCallback<Unit> {
            override fun onSuccess(data: Unit) {
                mainHandler.post {
                    stopPositionPolling()
                    result.success(null)
                }
            }

            override fun onFailure(msg: String) {
                mainHandler.post { result.error("pause_failed", msg, null) }
            }
        })
    }

    fun stop(result: io.flutter.plugin.common.MethodChannel.Result) {
        val control = deviceControl
        if (control == null) {
            result.error("not_connected", "未连接投屏设备", null)
            return
        }

        control.stop(object : ServiceActionCallback<Unit> {
            override fun onSuccess(data: Unit) {
                mainHandler.post {
                    stopPositionPolling()
                    result.success(null)
                }
            }

            override fun onFailure(msg: String) {
                mainHandler.post { result.error("stop_failed", msg, null) }
            }
        })
    }

    fun seek(positionMs: Long, result: io.flutter.plugin.common.MethodChannel.Result) {
        val control = deviceControl
        if (control == null) {
            result.error("not_connected", "未连接投屏设备", null)
            return
        }

        control.seek(positionMs, object : ServiceActionCallback<Unit> {
            override fun onSuccess(data: Unit) {
                mainHandler.post { result.success(null) }
            }

            override fun onFailure(msg: String) {
                mainHandler.post { result.error("seek_failed", msg, null) }
            }
        })
    }

    fun setVolume(volume: Int, result: io.flutter.plugin.common.MethodChannel.Result) {
        val control = deviceControl
        if (control == null) {
            result.error("not_connected", "未连接投屏设备", null)
            return
        }

        control.setVolume(volume, object : ServiceActionCallback<Unit> {
            override fun onSuccess(data: Unit) {
                mainHandler.post { result.success(null) }
            }

            override fun onFailure(msg: String) {
                mainHandler.post { result.error("set_volume_failed", msg, null) }
            }
        })
    }

    fun getVolume(result: io.flutter.plugin.common.MethodChannel.Result) {
        val control = deviceControl
        if (control == null) {
            result.error("not_connected", "未连接投屏设备", null)
            return
        }

        control.getVolume(object : ServiceActionCallback<Int> {
            override fun onSuccess(data: Int) {
                mainHandler.post { result.success(data) }
            }

            override fun onFailure(msg: String) {
                mainHandler.post { result.error("get_volume_failed", msg, null) }
            }
        })
    }

    // --- Position Polling ---

    private val positionRunnable = object : Runnable {
        override fun run() {
            if (!positionPolling) return
            val control = deviceControl ?: return
            control.getPositionInfo(object : ServiceActionCallback<PositionInfo> {
                override fun onSuccess(info: PositionInfo) {
                    if (!positionPolling) return
                    mainHandler.post {
                        val positionMs = info.trackElapsedSeconds * 1000
                        val durationMs = info.trackDurationSeconds * 1000
                        sendEvent(mapOf(
                            "type" to "positionChanged",
                            "positionMs" to positionMs,
                            "durationMs" to durationMs
                        ))
                    }
                }

                override fun onFailure(msg: String) {
                    // Silently ignore polling failures
                }
            })
            mainHandler.postDelayed(this, 1000)
        }
    }

    private fun startPositionPolling() {
        if (positionPolling) return
        positionPolling = true
        mainHandler.post(positionRunnable)
    }

    private fun stopPositionPolling() {
        positionPolling = false
        mainHandler.removeCallbacks(positionRunnable)
    }

    // --- Local Media Server ---

    private fun serveViaLocalProxy(upstreamUrl: String, headers: Map<String, String>): String {
        if (localMediaServer == null) {
            localMediaServer = LocalMediaServer(0) // random port
            localMediaServer?.start()
        }
        return localMediaServer!!.createProxiedUrl(upstreamUrl, headers)
    }

    private fun stopLocalMediaServer() {
        try {
            localMediaServer?.stop()
            localMediaServer = null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to stop local media server: $e")
        }
    }

    // --- Event Sending ---

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            try {
                eventSink?.success(event)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send event: $e")
            }
        }
    }
}
