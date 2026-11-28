package com.example.convoy_mesh

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/** The notification and bounded CPU lease belong only to the explicit LAB session. */
class WifiDirectLabService : Service() {
    companion object {
        private const val CHANNEL = "convoy_wifi_direct_lab"
        private const val NOTIFICATION = 4108
        private const val STOP = "convoy_mesh.WIFI_LAB_STOP"
        private const val SESSION = "session"
        private const val LIMIT_MS = 30 * 60 * 1000L

        private data class Lease(val id: String, val started: (Boolean) -> Unit,
                                 val stopped: (String, String) -> Unit, var launched: Boolean = false)
        private var lease: Lease? = null
        val isActive get() = lease != null

        fun start(context: Context, id: String, started: (Boolean) -> Unit,
                  stopped: (String, String) -> Unit) {
            if (lease != null || ConvoyForegroundService.isRunning) {
                started(false)
                return
            }
            lease = Lease(id, started, stopped)
            val intent = Intent(context, WifiDirectLabService::class.java).putExtra(SESSION, id)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (_: RuntimeException) {
                lease = null
                started(false)
            }
        }

        fun stop(context: Context, id: String) {
            val owner = lease ?: return
            if (owner.id != id) return
            if (!owner.launched) {
                lease = null
                owner.started(false)
            }
            context.stopService(Intent(context, WifiDirectLabService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var promoted = false
    private var serviceOwner: Lease? = null
    private var stopReason = "background_service_lost"

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val owner = lease
        if (owner == null || intent?.getStringExtra(SESSION) != owner.id) {
            if (!promoted) stopSelf()
            return START_NOT_STICKY
        }
        owner.launched = true
        serviceOwner = owner
        if (intent?.action == STOP) {
            stopReason = "notification_stop"
            stopSelf()
            return START_NOT_STICKY
        }
        if (promoted) return START_NOT_STICKY
        try {
            val notifications = getSystemService(NotificationManager::class.java)
            check(notifications.areNotificationsEnabled())
            if (Build.VERSION.SDK_INT >= 26) {
                notifications.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Wi-Fi Direct LAB", NotificationManager.IMPORTANCE_LOW))
                check(notifications.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
            }
            val open = PendingIntent.getActivity(this, 0,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val stop = PendingIntent.getService(this, NOTIFICATION,
                Intent(this, WifiDirectLabService::class.java).setAction(STOP)
                    .setData(Uri.parse("convoylab://stop/${owner.id}")).putExtra(SESSION, owner.id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher).setOngoing(true).setOnlyAlertOnce(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setContentTitle("Wi-Fi Direct LAB attivo")
                .setContentText("Probe sintetici • termina dalla notifica")
                .setContentIntent(open).addAction(android.R.drawable.ic_media_pause, "Stop LAB", stop)
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else startForeground(NOTIFICATION, notification)

            // A foreground service alone does not keep the CPU available for TCP/ACK
            // once the display sleeps. Scope the lock to the explicitly started test.
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ConvoyMesh:wifi-lab")
                .apply { setReferenceCounted(false); acquire(LIMIT_MS) }
            handler.postDelayed({
                stopReason = "background_session_expired"
                stopSelf()
            }, LIMIT_MS)
            promoted = true
            owner.started(true)
        } catch (_: RuntimeException) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        serviceOwner?.let { owner ->
            if (lease === owner) lease = null
            if (promoted) owner.stopped(owner.id, stopReason)
            else owner.started(false)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
