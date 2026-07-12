package com.example.convoy_mesh

import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "convoy_mesh/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openBluetoothSettings" -> openSettingsIntent(
                        action = Settings.ACTION_BLUETOOTH_SETTINGS,
                        errorCode = "ERR_BT_SETTINGS",
                        result = result,
                    )
                    "openLocationSettings" -> openSettingsIntent(
                        action = Settings.ACTION_LOCATION_SOURCE_SETTINGS,
                        errorCode = "ERR_LOCATION_SETTINGS",
                        result = result,
                    )
                    "startForegroundRuntime" -> startForegroundRuntime(result)
                    "stopForegroundRuntime" -> stopForegroundRuntime(result)
                    "isForegroundRuntimeRunning" -> result.success(ConvoyForegroundService.isRunning)
                    "getDeviceCapabilities" -> result.success(readDeviceCapabilities())
                    else -> result.notImplemented()
                }
            }
    }

    private fun startForegroundRuntime(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, ConvoyForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("ERR_FOREGROUND_START", error.message, null)
        }
    }

    private fun stopForegroundRuntime(result: MethodChannel.Result) {
        try {
            stopService(Intent(this, ConvoyForegroundService::class.java))
            result.success(true)
        } catch (error: Exception) {
            result.error("ERR_FOREGROUND_STOP", error.message, null)
        }
    }

    private fun readDeviceCapabilities(): Map<String, Any> {
        val packageManager = packageManager
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter

        val uwbSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            packageManager.hasSystemFeature("android.hardware.uwb")
        val wifiRttSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            packageManager.hasSystemFeature("android.hardware.wifi.rtt")
        val extendedAdvertising = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            adapter?.isLeExtendedAdvertisingSupported == true
        val multipleAdvertising = adapter?.isMultipleAdvertisementSupported == true

        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "uwbSupported" to uwbSupported,
            "wifiRttSupported" to wifiRttSupported,
            "bleExtendedAdvertisingSupported" to extendedAdvertising,
            "bleMultipleAdvertisingSupported" to multipleAdvertising,
            "foregroundRuntimeRunning" to ConvoyForegroundService.isRunning,
        )
    }

    private fun openSettingsIntent(
        action: String,
        errorCode: String,
        result: MethodChannel.Result,
    ) {
        try {
            val intent = Intent(action)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error(errorCode, error.message, null)
        }
    }
}
