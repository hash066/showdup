package com.rayyanshaikh.orbit

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.hardware.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*
import org.json.JSONObject

object Events {
    val sinks = mutableMapOf<String, EventChannel.EventSink>()
    fun emit(channel: String, data: Map<String, Any?>) {
        Handler(Looper.getMainLooper()).post { sinks[channel]?.success(data) }
    }
}

class MainActivity : FlutterFragmentActivity() {
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        for (name in listOf("alarm", "steps", "location")) {
            EventChannel(engine.dartExecutor.binaryMessenger, "app.showdup/${name}_events")
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                        Events.sinks[name] = sink
                    }

                    override fun onCancel(args: Any?) {
                        Events.sinks.remove(name)
                    }
                })
            MethodChannel(engine.dartExecutor.binaryMessenger, "app.showdup/$name")
                .setMethodCallHandler { call, result ->
                    try {
                        when (name) {
                            "alarm" -> alarm(call, result)
                            "steps" -> steps(call, result)
                            else -> location(call, result)
                        }
                    } catch (e: Exception) {
                        result.error("native_error", e.message, null)
                    }
                }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.showdup/blocker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermissions" -> result.success(
                        mapOf("usageStats" to false, "overlay" to false),
                    )
                    "stop" -> result.success(true)
                    else -> result.success(false)
                }
            }
        AlarmEngine.channels(this)
    }

    private fun granted(p: String) =
        ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun jsonArgs(c: MethodCall): JSONObject {
        val args = c.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        return JSONObject(args)
    }

    private fun alarm(c: MethodCall, r: MethodChannel.Result) {
        val args = c.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        when (c.method) {
            "configureBackend" -> {
                AlarmEngine.prefs(this).edit()
                    .putString("backend", jsonArgs(c).toString())
                    .apply()
                Backend.initialize(this)
                AlarmEngine.flushEvents(this)
                r.success(true)
            }
            "scheduleReminders" -> r.success(AlarmEngine.schedule(this, jsonArgs(c)))
            "cancelReminders" -> {
                AlarmEngine.cancel(this, args["attemptId"].toString())
                r.success(true)
            }
            "configureCommitments" -> {
                AlarmEngine.configure(this, args["commitments"] as? List<*> ?: emptyList<Any>())
                r.success(true)
            }
            "silence" -> {
                AlarmEngine.silence(
                    this,
                    args["attemptId"].toString(),
                    args["snooze"] as? Boolean ?: true,
                )
                r.success(true)
            }
            "getLaunchAttempt" -> r.success(
                intent.getStringExtra("attemptId") ?: intent.data?.getQueryParameter("attemptId"),
            )
            "getPermissionStatus" -> {
                val am = getSystemService(AlarmManager::class.java)
                r.success(
                    mapOf(
                        "exactAlarm" to (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()),
                        "notifications" to (
                            Build.VERSION.SDK_INT < 33 ||
                                granted(Manifest.permission.POST_NOTIFICATIONS)
                            ),
                        "batteryOptimised" to
                            !getSystemService(PowerManager::class.java)
                                .isIgnoringBatteryOptimizations(packageName),
                        "fullScreenIntent" to (
                            Build.VERSION.SDK_INT < 34 ||
                                getSystemService(NotificationManager::class.java)
                                    .canUseFullScreenIntent()
                            ),
                        "activityRecognition" to (
                            Build.VERSION.SDK_INT < 29 ||
                                granted(Manifest.permission.ACTIVITY_RECOGNITION)
                            ),
                        "location" to granted(Manifest.permission.ACCESS_FINE_LOCATION),
                        "manufacturer" to Build.MANUFACTURER,
                    ),
                )
            }
            "requestPermission" -> {
                val which = args["which"].toString()
                val perms = when (which) {
                    "notifications" ->
                        if (Build.VERSION.SDK_INT >= 33) {
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            emptyArray()
                        }
                    "activityRecognition" ->
                        if (Build.VERSION.SDK_INT >= 29) {
                            arrayOf(Manifest.permission.ACTIVITY_RECOGNITION)
                        } else {
                            emptyArray()
                        }
                    "location" -> arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    )
                    else -> emptyArray()
                }
                if (perms.isNotEmpty()) {
                    if (permissionResult != null) {
                        r.error("busy", "A permission request is already open", null)
                        return
                    }
                    permissionResult = r
                    requestPermissions(perms, 701)
                    return
                }
                when (which) {
                    "battery" -> requestBatteryExemption()
                    "autostart" -> openAutostart()
                    "exactAlarm" ->
                        if (Build.VERSION.SDK_INT >= 31) {
                            openSettings(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, true)
                        }
                    "fullScreenIntent" ->
                        if (Build.VERSION.SDK_INT >= 34) {
                            openSettings(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, true)
                        }
                    else -> openSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, true)
                }
                r.success(true)
            }
            "stopAll" -> {
                AlarmEngine.clear(this)
                stopService(Intent(this, TrackingService::class.java))
                r.success(true)
            }
            else -> r.notImplemented()
        }
    }

    private fun steps(c: MethodCall, r: MethodChannel.Result) {
        when (c.method) {
            "getStepCount" -> {
                val sm = getSystemService(SensorManager::class.java)
                val sensor = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                if (sensor == null) {
                    r.success(mapOf("available" to false))
                    return
                }
                if (Build.VERSION.SDK_INT >= 29 && !granted(Manifest.permission.ACTIVITY_RECOGNITION)) {
                    r.error("permission_denied", "Allow physical activity to count steps", null)
                    return
                }
                var done = false
                val handler = Handler(Looper.getMainLooper())
                lateinit var listener: SensorEventListener
                listener = object : SensorEventListener {
                    override fun onAccuracyChanged(s: Sensor?, a: Int) {}
                    override fun onSensorChanged(e: SensorEvent) {
                        if (done) return
                        done = true
                        sm.unregisterListener(this)
                        r.success(
                            mapOf(
                                "available" to true,
                                "cumulativeSteps" to e.values[0].toLong(),
                                "sensorBootTime" to bootId(),
                            ),
                        )
                    }
                }
                sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
                handler.postDelayed({
                    if (!done) {
                        done = true
                        sm.unregisterListener(listener)
                        r.error("sensor_wait", "Move a few steps, then try again", null)
                    }
                }, 10_000)
            }
            "startTracking" -> r.success(
                TrackingService.start(this, "steps", jsonArgs(c)),
            )
            "stopTracking" -> {
                TrackingService.stop(this, c.argument<String>("attemptId")!!)
                r.success(true)
            }
            else -> r.notImplemented()
        }
    }

    private fun location(c: MethodCall, r: MethodChannel.Result) {
        when (c.method) {
            "startWatch" -> r.success(
                TrackingService.start(this, "location", jsonArgs(c)),
            )
            "stopWatch" -> {
                TrackingService.stop(this, c.argument<String>("attemptId")!!)
                r.success(true)
            }
            "isWatching" -> r.success(TrackingService.hasLocation)
            "currentLocation" -> {
                if (!granted(Manifest.permission.ACCESS_FINE_LOCATION)) {
                    r.error("permission_denied", "Allow precise location first", null)
                    return
                }
                LocationServices.getFusedLocationProviderClient(this)
                    .getCurrentLocation(
                        com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY,
                        null,
                    )
                    .addOnSuccessListener { l ->
                        if (l == null) {
                            r.error("unavailable", "No location fix. Try outdoors.", null)
                        } else {
                            r.success(mapOf("lat" to l.latitude, "lng" to l.longitude))
                        }
                    }
                    .addOnFailureListener { r.error("unavailable", it.message, null) }
            }
            else -> r.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        code: Int,
        permissions: Array<out String>,
        results: IntArray,
    ) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code == 701) {
            permissionResult?.success(
                results.isNotEmpty() && results.all { it == PackageManager.PERMISSION_GRANTED },
            )
            permissionResult = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun requestBatteryExemption() {
        val ignoring = getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(packageName)
        if (ignoring) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ),
                )
            }
        }
    }

    // Some OEM builds lack a settings screen (ActivityNotFoundException); fall back to app details.
    private fun openSettings(action: String, withPackage: Boolean) {
        try {
            startActivity(
                Intent(action).apply {
                    if (withPackage) data = Uri.parse("package:$packageName")
                },
            )
        } catch (_: Exception) {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
            )
        }
    }

    private fun openAutostart() {
        val candidates = listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            ),
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            ),
        )
        for (c in candidates) {
            try {
                startActivity(Intent().setComponent(c))
                return
            } catch (_: Exception) {
            }
        }
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
        )
    }
}

fun bootId(): Long = (System.currentTimeMillis() - SystemClock.elapsedRealtime()) / 10000
