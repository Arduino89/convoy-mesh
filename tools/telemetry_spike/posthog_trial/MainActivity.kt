package com.cama.telemetry.convoy_telemetry_lab

import com.posthog.PostHog
import com.posthog.PersonProfiles
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/** Local-only regression probe using public SDK APIs; no queue/files internals. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "convoy.telemetry.lab/native")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "sentinels" -> result.success(sentinels(false))
                        "seedSentinels" -> result.success(sentinels(true))
                        "grant" -> { PostHog.optIn(); result.success(null) }
                        "revoke" -> { PostHog.optOut(); result.success(null) }
                        "flush" -> { PostHog.flush(); result.success(null) }
                        "capture" -> {
                            val properties = requireNotNull(call.argument<Map<String, Any>>("properties"))
                            PostHog.capture("cm_lab_probe", properties = properties)
                            result.success(null)
                        }
                        "resetClose" -> {
                            PostHog.optOut()
                            PostHog.reset()
                            PostHog.optOut()
                            PostHog.close()
                            result.success(mapOf("calls_returned" to true,
                                "queue_purge_attested" to false))
                        }
                        "setup" -> {
                            val run = requireNotNull(call.argument<String>("run_id"))
                            require(Regex("^synthetic-[a-z0-9-]{1,48}$").matches(run))
                            val capacity = requireNotNull(call.argument<Int>("queue_size"))
                            require(capacity == 32 || capacity == 1000)
                            val config = PostHogAndroidConfig("phc_synthetic_local_only", "http://10.0.2.2:8765").apply {
                                optOut = true
                                personProfiles = PersonProfiles.NEVER
                                captureApplicationLifecycleEvents = false
                                captureScreenViews = false
                                captureDeepLinks = false
                                captureElementInteractions = false
                                captureRageClicks = false
                                captureDeadClicks = false
                                capturePushNotificationSubscriptions = false
                                capturePushNotificationOpened = false
                                sessionReplay = false
                                surveys = false
                                preloadFeatureFlags = false
                                sendFeatureFlagEvent = false
                                setDefaultPersonProperties = false
                                errorTrackingConfig.autoCapture = false
                                debug = false
                                maxQueueSize = capacity
                                maxBatchSize = 20
                                flushAt = 20
                                flushIntervalSeconds = 60
                            }
                            val allowed = setOf("schema_version", "run_id", "event_id",
                                "sequence", "event_name", "synthetic")
                            config.addBeforeSend { event ->
                                val p = event.properties
                                if (p == null || event.event != "cm_lab_probe" || p["run_id"] != run ||
                                    p["synthetic"] != true || !p.keys.containsAll(allowed)) {
                                    null
                                } else {
                                    val clean = p.filterKeys { it in allowed }.toMutableMap()
                                    clean["\$geoip_disable"] = true
                                    clean["\$process_person_profile"] = false
                                    event.copy(distinctId = run, properties = clean)
                                }
                            }
                            // Hook is installed on configuration BEFORE SDK initialization.
                            PostHogAndroid.setup(applicationContext, config)
                            PostHog.optOut()
                            result.success(mapOf("installed" to true))
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("LAB_NATIVE_FAILURE", "Native lab action failed", null)
                }
            }
    }

    private fun sentinels(create: Boolean): Map<String, Any> {
        val prefs = getSharedPreferences("unrelated_lab_settings", MODE_PRIVATE)
        val file = File(filesDir, "unrelated_synthetic_trace.txt")
        val seed = File(filesDir, "sentinels_seeded.marker")
        if (create) {
            check(!seed.exists() && !prefs.contains("sentinel") && !file.exists())
            check(prefs.edit().putString("sentinel", "synthetic-setting-preserve").commit())
            FileOutputStream(file).use { stream ->
                stream.write("SYNTHETIC TRACE WITHOUT COORDINATES\nkeep-me\n".toByteArray())
                stream.fd.sync()
            }
            FileOutputStream(seed).use { it.write(byteArrayOf(1)); it.fd.sync() }
        }
        val hash = if (file.exists()) MessageDigest.getInstance("SHA-256")
            .digest(file.readBytes()).joinToString("") { "%02x".format(it) } else "MISSING"
        return mapOf("preference" to (prefs.getString("sentinel", null) ?: "MISSING"),
            "file_sha256" to hash, "marker_exists" to seed.exists())
    }
}
