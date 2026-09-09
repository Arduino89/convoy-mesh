package com.example.convoy_mesh

import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * Native counterpart of [ConvoyBleScanner].
 *
 * Real-device field logs showed both phones reporting plugin advertising
 * success while neither native scanner saw a single BLE event. Advertising and
 * scanning now use the same Android APIs and the same manufacturer contract:
 * company id 0x0C0A + Convoy payload beginning with CM.
 */
class ConvoyBleAdvertiser(context: Context) {
    companion object {
        private const val MANUFACTURER_ID = 0x0C0A
    }

    private val app = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private var advertiser: BluetoothLeAdvertiser? = null
    private var callback: AdvertiseCallback? = null
    private var generation = 0

    fun replace(payload: ByteArray, done: (Boolean, String?) -> Unit) {
        stopInternal()
        val epoch = generation
        try {
            require(payload.isNotEmpty()) { "Payload BLE vuoto" }
            // Legacy advertising has a 31-byte limit. Flags consume 3 bytes and
            // manufacturer AD framing consumes 4, leaving 24 bytes for Convoy.
            require(payload.size <= 24) { "Payload BLE troppo grande: ${payload.size} byte" }

            val adapter = (app.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            val native = adapter?.bluetoothLeAdvertiser
                ?: throw IllegalStateException("Advertising BLE non disponibile")

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(false)
                .setTimeout(0)
                .build()

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addManufacturerData(MANUFACTURER_ID, payload)
                .build()

            var completed = false
            fun finish(ok: Boolean, error: String?) {
                if (completed) return
                completed = true
                handler.post { if (epoch == generation) done(ok, error) }
            }

            val listener = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    finish(true, null)
                }

                override fun onStartFailure(errorCode: Int) {
                    callback = null
                    advertiser = null
                    finish(false, "Android advertise error $errorCode")
                }
            }

            advertiser = native
            callback = listener
            native.startAdvertising(settings, data, listener)
        } catch (e: Exception) {
            stopInternal()
            done(false, e.message ?: e.toString())
        }
    }

    fun stop() {
        stopInternal()
    }

    private fun stopInternal() {
        generation++
        val cb = callback
        val native = advertiser
        callback = null
        advertiser = null
        try {
            if (cb != null) native?.stopAdvertising(cb)
        } catch (_: Exception) {
        }
    }
}
