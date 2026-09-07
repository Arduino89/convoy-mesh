package com.example.convoy_mesh

import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** One native scan per Flutter subscription; manufacturer filtering survives screen-off. */
class ConvoyBleScanner(context: Context) : EventChannel.StreamHandler {
    private val app = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private var scanner: BluetoothLeScanner? = null
    private var callback: ScanCallback? = null
    private var generation = 0

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val epoch = generation
        try {
            val adapter = (app.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            val native = adapter?.bluetoothLeScanner
                ?: throw IllegalStateException("Bluetooth non disponibile o spento")
            val listener = object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) = deliver(result)
                override fun onBatchScanResults(results: MutableList<ScanResult>) {
                    results.forEach { deliver(it) }
                }
                private fun deliver(result: ScanResult) {
                    val data = result.scanRecord?.getManufacturerSpecificData(0x0C0A) ?: return
                    val event = mapOf("id" to result.device.address, "rssi" to result.rssi,
                        "data" to data, "observed_elapsed_nanos" to result.timestampNanos)
                    handler.post { if (epoch == generation) events.success(event) }
                }
                override fun onScanFailed(errorCode: Int) {
                    handler.post {
                        if (epoch == generation) {
                            stop()
                            events.error("BLE_SCAN_FAILED", "Android scan error $errorCode", errorCode)
                        }
                    }
                }
            }
            scanner = native
            callback = listener
            val filter = ScanFilter.Builder()
                .setManufacturerData(0x0C0A, byteArrayOf(0x43, 0x4D)).build()
            native.startScan(listOf(filter), ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setReportDelay(0).build(), listener)
        } catch (e: Exception) {
            stop()
            events.error("BLE_SCAN_START", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) = stop()

    private fun stop() {
        generation++
        val cb = callback
        callback = null
        try { if (cb != null) scanner?.stopScan(cb) } catch (_: Exception) { }
        scanner = null
    }
}
