package com.example.convoy_mesh

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "convoy_mesh/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openBluetoothSettings" -> openSettingsIntent(
                        action = Settings.ACTION_BLUETOOTH_SETTINGS,
                        errorCode = "ERR_BT_SETTINGS",
                        result = result
                    )
                    "openLocationSettings" -> openSettingsIntent(
                        action = Settings.ACTION_LOCATION_SOURCE_SETTINGS,
                        errorCode = "ERR_LOCATION_SETTINGS",
                        result = result
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun openSettingsIntent(action: String, errorCode: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(action)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error(errorCode, e.message, null)
        }
    }
}
