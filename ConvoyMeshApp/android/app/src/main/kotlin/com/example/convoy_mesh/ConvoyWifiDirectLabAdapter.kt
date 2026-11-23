package com.example.convoy_mesh

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Isolated native adapter for the Wi-Fi Direct Offline Lab (First Gate).
 *
 * Uses Android platform [WifiP2pManager] and [WifiP2pConfig] only.
 * - Lazy initialization: zero receivers or P2P channels are created in Outdoor +20.
 * - Requires Bluetooth OFF and Wi-Fi ON; never starts BLE or [ConvoyForegroundService].
 * - Never exposes hardware MAC addresses, device names, or group SSIDs/passphrases
 *   to Flutter or logs; discovered peers are mapped in-memory to ephemeral
 *   synthetic slot IDs (`peer-01`, `peer-02`, ...) and cleared on [stopAll].
 */
class ConvoyWifiDirectLabAdapter(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "convoy_mesh/wifi_direct_lab"
        const val EVENT_CHANNEL = "convoy_mesh/wifi_direct_lab_events"
        const val REQUEST_CODE_WIFI_P2P_PERMISSION = 4109
        private const val PERMISSION_NEARBY_WIFI_DEVICES = "android.permission.NEARBY_WIFI_DEVICES"
    }

    private val app: Context = activity.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private var p2pManager: WifiP2pManager? = null
    private var p2pChannel: WifiP2pManager.Channel? = null
    private var p2pReceiver: BroadcastReceiver? = null
    private var p2pBroadcastEnabled: Boolean? = null
    private var p2pSession: WifiDirectSession? = null
    private var pendingDiscoverResult: MethodChannel.Result? = null
    private var pendingConnectResult: MethodChannel.Result? = null

    private var pendingPermissionResult: MethodChannel.Result? = null

    private fun createReceiver(session: WifiDirectSession) = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!session.isActive) return
            when (intent?.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(
                        WifiP2pManager.EXTRA_WIFI_STATE,
                        WifiP2pManager.WIFI_P2P_STATE_DISABLED,
                    )
                    val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    p2pBroadcastEnabled = enabled
                    emitEvent(
                        session,
                        mapOf(
                            "type" to "p2p_state_changed",
                            "enabled" to enabled,
                        ),
                    )
                }

                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    requestCurrentPeers(session)
                }

                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    requestCurrentConnectionInfo(session)
                }
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getEnvironmentStatus" -> result.success(buildEnvironmentStatus())
                "requestRequiredPermission" -> handleRequestRequiredPermission(result)
                "openWifiSettings" -> {
                    app.startActivity(
                        Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                "openBluetoothSettings" -> {
                    app.startActivity(
                        Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                "openLocationSettings" -> {
                    app.startActivity(
                        Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                "openAppSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", app.packageName, null),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    app.startActivity(intent)
                    result.success(true)
                }
                "discoverPeers" -> handleDiscoverPeers(call, result)
                "connectPeer" -> handleConnectPeer(call, result)
                "stopAll" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId != null && p2pSession?.id == sessionId) stopAllInternal()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("WIFI_DIRECT_LAB_NATIVE", e.message ?: e.toString(), null)
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        @Suppress("UNUSED_PARAMETER") permissions: Array<out String>,
        @Suppress("UNUSED_PARAMETER") grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE_WIFI_P2P_PERMISSION) return false
        val callback = pendingPermissionResult
        pendingPermissionResult = null
        callback?.success(buildEnvironmentStatus())
        return true
    }

    fun dispose() {
        pendingPermissionResult = null
        stopAllInternal()
        eventSink = null
    }

    private fun buildEnvironmentStatus(): Map<String, Any?> {
        val sdkInt = Build.VERSION.SDK_INT
        val pm = app.packageManager
        val wifiDirectFeatureSupported = pm.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
        val manager = app.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        val wifiManager = app.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val wifiEnabled = try {
            wifiManager?.isWifiEnabled == true
        } catch (_: Exception) {
            false
        }
        val bluetoothAdapter =
            (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        val bluetoothEnabled = try {
            bluetoothAdapter?.isEnabled == true
        } catch (_: SecurityException) {
            false
        }
        val nearbyWifiGranted = if (sdkInt >= 33) {
            hasPermission(PERMISSION_NEARBY_WIFI_DEVICES)
        } else {
            true
        }
        val fineLocationGranted = hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val requiredRuntimeGranted = if (sdkInt >= 33) nearbyWifiGranted else fineLocationGranted
        val requiredPermissionName =
            if (sdkInt >= 33) "NEARBY_WIFI_DEVICES" else "ACCESS_FINE_LOCATION"
        val locationServiceEnabled = isLocationServiceEnabled()
        val internetValidated = isInternetValidated()
        val manifestPermissionsOk = checkDeclaredManifestPermissions(sdkInt)

        return mapOf(
            "sdkInt" to sdkInt,
            "wifiDirectFeatureSupported" to wifiDirectFeatureSupported,
            "wifiP2pServiceAvailable" to (manager != null),
            "wifiEnabled" to wifiEnabled,
            "p2pStateEnabled" to (p2pBroadcastEnabled ?: wifiEnabled),
            "bluetoothEnabled" to bluetoothEnabled,
            "internetValidated" to internetValidated,
            "nearbyWifiPermissionGranted" to nearbyWifiGranted,
            "fineLocationPermissionGranted" to fineLocationGranted,
            "requiredRuntimePermissionGranted" to requiredRuntimeGranted,
            "requiredPermissionName" to requiredPermissionName,
            "locationServiceEnabled" to locationServiceEnabled,
            "manifestPermissionsOk" to manifestPermissionsOk,
            "foregroundServiceRunning" to ConvoyForegroundService.isRunning,
        )
    }

    private fun handleRequestRequiredPermission(result: MethodChannel.Result) {
        val sdkInt = Build.VERSION.SDK_INT
        val permissionToRequest = if (sdkInt >= 33) {
            PERMISSION_NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (hasPermission(permissionToRequest)) {
            result.success(buildEnvironmentStatus())
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_REQUEST_IN_PROGRESS", "Richiesta permesso già in corso", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(permissionToRequest),
            REQUEST_CODE_WIFI_P2P_PERMISSION,
        )
    }

    @SuppressLint("MissingPermission")
    private fun handleDiscoverPeers(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<String>("sessionId")
        if (sessionId.isNullOrBlank()) {
            result.error("INVALID_SESSION", "Sessione Wi-Fi Direct mancante", null)
            return
        }
        val preflightError = checkP2pPreflight()
        if (preflightError != null) {
            result.error(preflightError.first, preflightError.second, null)
            return
        }
        if (p2pSession?.id != sessionId) stopAllInternal()
        val session = p2pSession ?: WifiDirectSession(sessionId).also { p2pSession = it }
        if (pendingDiscoverResult != null) {
            result.error("DISCOVERY_IN_PROGRESS", "Richiesta di scoperta già in corso", null)
            return
        }
        val (manager, channel) = ensureP2pChannelAndReceiver(session)
            ?: run {
                result.error("WIFI_P2P_UNAVAILABLE", "Canale WifiP2pManager non inizializzabile", null)
                return
            }

        pendingDiscoverResult = result
        try {
            manager.discoverPeers(
                channel,
                object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        session.post(handler::post) {
                            if (pendingDiscoverResult !== result) return@post
                            pendingDiscoverResult = null
                            result.success(mapOf("accepted" to true))
                        }
                    }

                    override fun onFailure(reasonCode: Int) {
                        session.post(handler::post) {
                            if (pendingDiscoverResult !== result) return@post
                            pendingDiscoverResult = null
                            val reason = p2pReasonToText(reasonCode)
                            result.error("DISCOVER_PEERS_FAILED_$reasonCode", "discoverPeers fallito: $reason", reasonCode)
                        }
                    }
                },
            )
        } catch (e: Exception) {
            pendingDiscoverResult = null
            throw e
        }
    }

    @SuppressLint("MissingPermission")
    private fun handleConnectPeer(call: MethodCall, result: MethodChannel.Result) {
        val session = p2pSession
        if (session == null || session.id != call.argument<String>("sessionId")) {
            result.error("INVALID_SESSION", "Ripetere la scoperta Wi-Fi Direct", null)
            return
        }
        val peerId = call.argument<String>("peerId")?.trim().orEmpty()
        val userConsented = call.argument<Boolean>("userConsented") == true
        if (!userConsented) {
            result.error("CONSENT_REQUIRED", "Consenso locale richiesto per connettersi al peer", null)
            return
        }
        if (peerId.isEmpty()) {
            result.error("INVALID_PEER_ID", "ID peer sintetico mancante", null)
            return
        }
        if (pendingConnectResult != null) {
            result.error("CONNECT_IN_PROGRESS", "Richiesta Wi-Fi Direct già in corso: attendere o usare Stop", null)
            return
        }
        val preflightError = checkP2pPreflight()
        if (preflightError != null) {
            emitEvent(
                session,
                mapOf(
                    "type" to "native_error",
                    "stage" to "connect_preflight",
                    "code" to preflightError.first,
                    "message" to preflightError.second,
                ),
            )
            result.error(preflightError.first, preflightError.second, null)
            return
        }
        val rawAddress = session.addressForPeer(peerId)
        if (rawAddress.isNullOrBlank()) {
            result.error(
                "PEER_NOT_FOUND",
                "Peer $peerId non presente nella sessione corrente: ripetere la scoperta",
                null,
            )
            return
        }
        val (manager, channel) = ensureP2pChannelAndReceiver(session)
            ?: run {
                result.error("WIFI_P2P_UNAVAILABLE", "Canale WifiP2pManager non disponibile", null)
                return
            }

        pendingConnectResult = result

        fun reject(code: String, message: String, reasonCode: Int? = null) {
            if (!session.isActive || pendingConnectResult !== result) return
            pendingConnectResult = null
            emitEvent(
                session,
                mapOf(
                    "type" to "native_error",
                    "stage" to "connect_peer",
                    "code" to code,
                    "message" to message,
                ),
            )
            result.error(code, message, reasonCode)
        }

        // Let Android stop discovery as part of connect. An explicit
        // stopPeerDiscovery() can flush supplicant peer state before negotiation.
        val config = WifiP2pConfig().apply {
            deviceAddress = rawAddress
            wps.setup = WpsInfo.PBC
        }
        try {
            manager.connect(
                channel,
                config,
                object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        session.post(handler::post) {
                            if (!session.isActive || pendingConnectResult !== result) return@post
                            pendingConnectResult = null
                            result.success(
                                mapOf(
                                    "accepted" to true,
                                    "peer_id" to peerId,
                                ),
                            )
                        }
                    }

                    override fun onFailure(reasonCode: Int) {
                        session.post(handler::post) {
                            reject(
                                "CONNECT_PEER_FAILED_$reasonCode",
                                "connect($peerId) fallito: ${p2pReasonToText(reasonCode)} " +
                                    "(code=$reasonCode). Usare Stop su entrambi i telefoni, " +
                                    "ripetere la scoperta e connettere da uno solo.",
                                reasonCode,
                            )
                        }
                    }
                },
            )
        } catch (e: Exception) {
            reject("CONNECT_REQUEST_EXCEPTION", "Connessione P2P non avviata: ${e.javaClass.simpleName}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestCurrentPeers(session: WifiDirectSession) {
        val manager = p2pManager ?: return
        val channel = p2pChannel ?: return
        if (checkP2pPreflight() != null) return
        try {
            manager.requestPeers(channel) { peerList ->
                if (!session.isActive) return@requestPeers
                val devices = peerList?.deviceList ?: emptyList()
                val syntheticPeers = devices.mapNotNull { device ->
                    val rawAddress = device.deviceAddress?.trim().orEmpty()
                    val syntheticId = session.peerForAddress(rawAddress) ?: return@mapNotNull null
                    mapOf(
                        "peer_id" to syntheticId,
                        "status" to deviceStatusToText(device.status),
                    )
                }
                emitEvent(
                    session,
                    mapOf(
                        "type" to "peers_updated",
                        "peer_count" to syntheticPeers.size,
                        "peers" to syntheticPeers,
                    ),
                )
            }
        } catch (e: SecurityException) {
            emitEvent(
                session,
                mapOf(
                    "type" to "native_error",
                    "stage" to "request_peers",
                    "code" to "PERMISSION_DENIED",
                    "message" to "Permesso mancante durante requestPeers",
                ),
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestCurrentConnectionInfo(session: WifiDirectSession) {
        val manager = p2pManager ?: return
        val channel = p2pChannel ?: return
        try {
            manager.requestConnectionInfo(channel) { info ->
                if (!session.isActive) return@requestConnectionInfo
                if (info != null && info.groupFormed && info.groupOwnerAddress != null) {
                    session.wasGroupFormed = true
                    val role = if (info.isGroupOwner) "group_owner" else "client"
                    val ownerHost = info.groupOwnerAddress?.hostAddress.orEmpty()
                    try {
                        manager.requestGroupInfo(channel) { group ->
                            if (!session.isActive || !session.wasGroupFormed) return@requestGroupInfo
                            val clientCount = group?.clientList?.size ?: 0
                            emitEvent(
                                session,
                                mapOf(
                                    "type" to "group_formed",
                                    "role" to role,
                                    "is_group_owner" to info.isGroupOwner,
                                    "group_owner_host" to ownerHost,
                                    "client_count" to clientCount,
                                ),
                            )
                        }
                    } catch (_: SecurityException) {
                        emitEvent(
                            session,
                            mapOf(
                                "type" to "group_formed",
                                "role" to role,
                                "is_group_owner" to info.isGroupOwner,
                                "group_owner_host" to ownerHost,
                                "client_count" to 0,
                            ),
                        )
                    }
                } else if (session.wasGroupFormed) {
                    session.wasGroupFormed = false
                    emitEvent(
                        session,
                        mapOf(
                            "type" to "p2p_disconnected",
                            "reason" to "p2p_group_lost",
                        ),
                    )
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun checkP2pPreflight(): Pair<String, String>? {
        val status = buildEnvironmentStatus()
        if (status["wifiDirectFeatureSupported"] != true || status["wifiP2pServiceAvailable"] != true) {
            return "WIFI_DIRECT_UNSUPPORTED" to "Wi-Fi Direct non supportato dal dispositivo (PackageManager)"
        }
        if (status["bluetoothEnabled"] == true) {
            return "BLUETOOTH_MUST_BE_OFF" to "Bluetooth attivo: spegnere il Bluetooth per eseguire il laboratorio Wi-Fi Direct isolato"
        }
        if (status["wifiEnabled"] != true) {
            return "WIFI_DISABLED" to "Wi-Fi disabilitato: attivare il Wi-Fi (senza connessione Internet)"
        }
        if (status["requiredRuntimePermissionGranted"] != true) {
            val perm = status["requiredPermissionName"] ?: "NEARBY_WIFI_DEVICES"
            return "PERMISSION_DENIED" to "Permesso runtime $perm non concesso"
        }
        val sdkInt = (status["sdkInt"] as? Int) ?: Build.VERSION.SDK_INT
        if (sdkInt < 33 && status["locationServiceEnabled"] != true) {
            return "LOCATION_SERVICES_DISABLED_LEGACY_P2P" to
                "Su Android <= 12 il sistema operativo richiede i servizi di Posizione attivi per la scansione Wi-Fi Direct"
        }
        return null
    }

    private fun ensureP2pChannelAndReceiver(session: WifiDirectSession): Pair<WifiP2pManager, WifiP2pManager.Channel>? {
        var manager = p2pManager
        if (manager == null) {
            manager = app.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager ?: return null
            p2pManager = manager
        }
        var channel = p2pChannel
        if (channel == null) {
            channel = manager.initialize(app, Looper.getMainLooper()) {
                session.post(handler::post) {
                    // This is terminal for the session. Send it while the token is valid;
                    // every other callback and queued event is then invalidated.
                    eventSink?.success(
                        mapOf("type" to "p2p_disconnected", "reason" to "p2p_channel_disconnected",
                            "session_ended" to true, "session_id" to session.id),
                    )
                    stopAllInternal()
                }
            } ?: return null
            p2pChannel = channel
        }
        if (p2pReceiver == null) {
            val receiver = createReceiver(session)
            val filter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                app.registerReceiver(receiver, filter)
            }
            p2pReceiver = receiver
        }
        return manager to channel
    }

    private fun stopAllInternal() {
        p2pSession?.invalidate()
        p2pSession = null
        pendingDiscoverResult?.error("DISCOVERY_CANCELLED", "Scoperta P2P annullata: Stop", null)
        pendingDiscoverResult = null
        pendingConnectResult?.error("CONNECT_CANCELLED", "Connessione P2P annullata: Stop", null)
        pendingConnectResult = null
        val manager = p2pManager
        val channel = p2pChannel
        if (manager != null && channel != null) {
            try {
                manager.stopPeerDiscovery(channel, null)
            } catch (_: Exception) {
            }
            try {
                manager.cancelConnect(channel, null)
            } catch (_: Exception) {
            }
            try {
                manager.removeGroup(channel, null)
            } catch (_: Exception) {
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                try {
                    channel.close()
                } catch (_: Exception) {
                }
            }
        }
        p2pReceiver?.let { receiver ->
            try {
                app.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
        }
        p2pReceiver = null
        p2pChannel = null
        p2pBroadcastEnabled = null
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(app, permission) == PackageManager.PERMISSION_GRANTED

    private fun isLocationServiceEnabled(): Boolean {
        val lm = app.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                lm.isLocationEnabled
            } else {
                lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isInternetValidated(): Boolean {
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        return try {
            val active = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(active) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (_: Exception) {
            false
        }
    }

    private fun checkDeclaredManifestPermissions(sdkInt: Int): Boolean {
        return try {
            val pkgInfo = if (Build.VERSION.SDK_INT >= 33) {
                app.packageManager.getPackageInfo(
                    app.packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS)
            }
            val declared = pkgInfo.requestedPermissions?.toSet() ?: emptySet()
            val baseOk = declared.contains(Manifest.permission.ACCESS_WIFI_STATE) &&
                declared.contains(Manifest.permission.CHANGE_WIFI_STATE) &&
                declared.contains(Manifest.permission.INTERNET)
            if (sdkInt >= 33) {
                baseOk && declared.contains(PERMISSION_NEARBY_WIFI_DEVICES)
            } else {
                baseOk && declared.contains(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun deviceStatusToText(status: Int): String = when (status) {
        WifiP2pDevice.AVAILABLE -> "available"
        WifiP2pDevice.INVITED -> "invited"
        WifiP2pDevice.CONNECTED -> "connected"
        WifiP2pDevice.FAILED -> "failed"
        WifiP2pDevice.UNAVAILABLE -> "unavailable"
        else -> "unknown"
    }

    private fun p2pReasonToText(reasonCode: Int): String = when (reasonCode) {
        WifiP2pManager.P2P_UNSUPPORTED -> "p2p_unsupported"
        WifiP2pManager.BUSY -> "framework_busy"
        WifiP2pManager.ERROR -> "internal_error"
        WifiP2pManager.NO_SERVICE_REQUESTS -> "no_service_requests"
        else -> "unknown_reason"
    }

    private fun emitEvent(session: WifiDirectSession, payload: Map<String, Any?>) {
        val sink = eventSink ?: return
        session.post(handler::post) {
            if (eventSink === sink) sink.success(payload + ("session_id" to session.id))
        }
    }
}
