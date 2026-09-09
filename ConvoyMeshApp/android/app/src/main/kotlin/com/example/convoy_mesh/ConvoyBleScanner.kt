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

/**
 * One native scan per Flutter subscription.
 *
 * Important: filter on the manufacturer COMPANY ID only. The 0.7.0 field logs
 * from two real Android phones showed TX succeeding on both devices while both
 * scanners delivered zero results. The previous filter also required the first
 * payload bytes to be `CM`; that assumption is not safe across Android/plugin
 * advertising layouts (some stacks can expose/repeat manufacturer bytes before
 * our payload). Keeping the company-id filter still gives Android a real
 * hardware/software ScanFilter for screen-off operation, while the Dart codec
 * remains the authority that validates the `CM` magic/version/flags.
 */
class ConvoyBleScanner(context: Context) : EventChannel.StreamHandler {
    companion object {
        private const val MANUFACTURER_ID = 0x0C0A
        // Defensive compatibility with stacks/tools that have historically
        // surfaced the two company-id bytes reversed. Dart still validates CM.
        private const val MANUFACTURER_ID_SWAPPED = 0x0A0C
    }

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
                    val record = result.scanRecord ?: return
                    val data = record.getManufacturerSpecificData(MANUFACTURER_ID)
                        ?: record.getManufacturerSpecificData(MANUFACTURER_ID_SWAPPED)
                        ?: findConvoyManufacturerPayload(record.bytes)
                        ?: return
                    val event = mapOf(
                        "id" to result.device.address,
                        "rssi" to result.rssi,
                        "data" to data,
                        "observed_elapsed_nanos" to result.timestampNanos,
                    )
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

            // Empty manufacturer payload means "this company id, any payload".
            // We deliberately do NOT require CM here; Dart parses and validates it.
            val filters = listOf(
                ScanFilter.Builder()
                    .setManufacturerData(MANUFACTURER_ID, byteArrayOf())
                    .build(),
                ScanFilter.Builder()
                    .setManufacturerData(MANUFACTURER_ID_SWAPPED, byteArrayOf())
                    .build(),
            )
            native.startScan(
                filters,
                ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .setReportDelay(0)
                    .build(),
                listener,
            )
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
        try {
            if (cb != null) scanner?.stopScan(cb)
        } catch (_: Exception) {
        }
        scanner = null
    }

    /**
     * Parse raw BLE AD structures as a final compatibility path. This avoids
     * relying solely on ScanRecord's SparseArray representation and returns only
     * the manufacturer payload (company id removed), exactly like
     * getManufacturerSpecificData().
     */
    private fun findConvoyManufacturerPayload(bytes: ByteArray): ByteArray? {
        var offset = 0
        while (offset < bytes.size) {
            val length = bytes[offset].toInt() and 0xFF
            if (length == 0) break
            val endExclusive = offset + 1 + length
            if (endExclusive > bytes.size || length < 1) break
            val type = bytes[offset + 1].toInt() and 0xFF
            if (type == 0xFF && length >= 3) {
                val lo = bytes[offset + 2].toInt() and 0xFF
                val hi = bytes[offset + 3].toInt() and 0xFF
                val companyId = lo or (hi shl 8)
                if (companyId == MANUFACTURER_ID || companyId == MANUFACTURER_ID_SWAPPED) {
                    return bytes.copyOfRange(offset + 4, endExclusive)
                }
            }
            offset = endExclusive
        }
        return null
    }
}
