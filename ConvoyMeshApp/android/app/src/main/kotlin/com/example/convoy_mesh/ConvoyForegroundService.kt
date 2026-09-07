package com.example.convoy_mesh

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** Explicit outing runtime: never restart a notification without its Dart owner. */
class ConvoyForegroundService : Service() {
    companion object {
        const val ENGINE_ID = "convoy_runtime"
        private const val CHANNEL_ID = "convoy_mesh_active"
        private const val NOTIFICATION_ID = 4107
        private const val STOP = "convoy_mesh.STOP"
        @Volatile var isRunning = false
            private set
        @Volatile var lastError: String? = null
            private set
        private var instance: ConvoyForegroundService? = null
        fun pulse(): Boolean {
            val service = instance ?: return false
            if (!isRunning) return false
            service.lastPulse = SystemClock.elapsedRealtime()
            service.renewWakeLock()
            return true
        }
    }
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var acquiredAt = 0L
    private var lastPulse = 0L
    private var receiverRegistered = false
    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_USER_PRESENT && isRunning) signal("runtimeUserPresent")
        }
    }
    private val checkOwner = object : Runnable {
        override fun run() {
            if (!isRunning) return
            val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
            if (engine == null || !engine.dartExecutor.isExecutingDart ||
                SystemClock.elapsedRealtime() - lastPulse > 45000) {
                lastError = "Runtime non risponde: riaprire Convoy Mesh"
                stopSelf()
            } else handler.postDelayed(this, 15000)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) { stopSelf(); return START_NOT_STICKY }
        if (isRunning) return START_NOT_STICKY
        try {
            check(FlutterEngineCache.getInstance().get(ENGINE_ID)?.dartExecutor?.isExecutingDart == true) {
                "Nessun motore Convoy attivo; aprire l'app"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Uscita Convoy Mesh", NotificationManager.IMPORTANCE_LOW))
            }
            val open = PendingIntent.getActivity(this, 0,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val stop = PendingIntent.getService(this, 1,
                Intent(this, ConvoyForegroundService::class.java).setAction(STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Convoy Mesh: uscita attiva")
                .setContentText("GPS e presenza di gruppo • tocca per verificare lo stato")
                .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
                .addAction(android.R.drawable.ic_media_pause, "Termina uscita", stop)
                .setCategory(NotificationCompat.CATEGORY_SERVICE).build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else startForeground(NOTIFICATION_ID, notification)
            instance = this
            isRunning = true
            lastError = null
            lastPulse = SystemClock.elapsedRealtime()
            renewWakeLock()
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(unlockReceiver, IntentFilter(Intent.ACTION_USER_PRESENT), Context.RECEIVER_NOT_EXPORTED)
            } else registerReceiver(unlockReceiver, IntentFilter(Intent.ACTION_USER_PRESENT))
            receiverRegistered = true
            handler.postDelayed(checkOwner, 15000)
        } catch (e: Exception) {
            lastError = e.toString()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun renewWakeLock() {
        val now = SystemClock.elapsedRealtime()
        if (wakeLock?.isHeld == true && now - acquiredAt < 90000) return
        wakeLock?.let { if (it.isHeld) it.release() }
        val lock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ConvoyMesh:outing")
        lock.setReferenceCounted(false)
        lock.acquire(120000)
        wakeLock = lock
        acquiredAt = now
    }

    private fun signal(method: String) {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, "convoy_mesh/system")
                .invokeMethod(method, lastError)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (receiverRegistered) unregisterReceiver(unlockReceiver)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        instance = null
        isRunning = false
        signal("runtimeStopped")
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
