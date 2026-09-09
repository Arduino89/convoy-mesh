package com.example.convoy_mesh

import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private var registeredEngine: FlutterEngine? = null
        private var uiResumed = false
    }
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(ConvoyForegroundService.ENGINE_ID)
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun onResume() { super.onResume(); uiResumed = true }
    override fun onPause() { uiResumed = false; super.onPause() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        if (registeredEngine === flutterEngine) return
        super.configureFlutterEngine(flutterEngine)
        registeredEngine = flutterEngine
        FlutterEngineCache.getInstance().put(ConvoyForegroundService.ENGINE_ID, flutterEngine)
        val app = applicationContext
        val nativeAdvertiser = ConvoyBleAdvertiser(app)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "convoy_mesh/filtered_scan")
            .setStreamHandler(ConvoyBleScanner(app))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "convoy_mesh/system")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openBluetoothSettings", "openLocationSettings" -> {
                            val action = if (call.method == "openBluetoothSettings") Settings.ACTION_BLUETOOTH_SETTINGS else Settings.ACTION_LOCATION_SOURCE_SETTINGS
                            app.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        }
                        "startForegroundRuntime" -> {
                            check(uiResumed) { "Aprire Convoy Mesh per avviare l'uscita" }
                            val intent = Intent(app, ConvoyForegroundService::class.java)
                            if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent) else app.startService(intent)
                            result.success(true)
                        }
                        "stopForegroundRuntime" -> {
                            nativeAdvertiser.stop()
                            app.stopService(Intent(app, ConvoyForegroundService::class.java))
                            result.success(true)
                        }
                        "replaceNativeAdvertising" -> {
                            val args = call.arguments as? Map<*, *>
                            val payload = args?.get("payload") as? ByteArray
                                ?: throw IllegalArgumentException("Payload advertising mancante")
                            nativeAdvertiser.replace(payload) { ok, error ->
                                if (ok) result.success(true)
                                else result.error("BLE_ADVERTISE_FAILED", error, null)
                            }
                        }
                        "stopNativeAdvertising" -> {
                            nativeAdvertiser.stop()
                            result.success(true)
                        }
                        "getDiagnosticDirectory" -> {
                            val directory = java.io.File(app.filesDir, "convoy-diagnostics")
                            check(directory.isDirectory || directory.mkdirs()) { "Archivio diagnostico non disponibile" }
                            result.success(directory.absolutePath)
                        }
                        "runtimePulse" -> result.success(ConvoyForegroundService.pulse())
                        "isForegroundRuntimeRunning" -> result.success(ConvoyForegroundService.isRunning)
                        "getDeviceCapabilities" -> {
                            val pm = app.packageManager
                            val adapter = (app.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
                            val multiple = try { adapter?.isMultipleAdvertisementSupported == true } catch (_: SecurityException) { false }
                            val extended = try { Build.VERSION.SDK_INT >= 26 && adapter?.isLeExtendedAdvertisingSupported == true } catch (_: SecurityException) { false }
                            result.success(mapOf(
                                "sdkInt" to Build.VERSION.SDK_INT, "model" to Build.MODEL,
                                "uwbSupported" to pm.hasSystemFeature("android.hardware.uwb"),
                                "wifiRttSupported" to pm.hasSystemFeature("android.hardware.wifi.rtt"),
                                "bleMultipleAdvertisingSupported" to multiple,
                                "bleExtendedAdvertisingSupported" to extended,
                                "foregroundRuntimeRunning" to ConvoyForegroundService.isRunning,
                                "runtimeError" to ConvoyForegroundService.lastError))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("CONVOY_NATIVE", e.message, null) }
            }
    }
}
