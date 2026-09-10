package com.rayyanshaikh.orbit

import android.Manifest
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.functions.FirebaseFunctions
import org.json.JSONObject
import kotlin.math.abs

class TrackingService : Service(), SensorEventListener {
    companion object {
        @Volatile
        var hasLocation = false

        /**
         * The runtime permission each foreground-service type needs. On Android 14+ calling
         * startForeground with type health or location without it throws SecurityException.
         */
        fun permitted(context: Context, type: String): Boolean {
            fun granted(permission: String) =
                ContextCompat.checkSelfPermission(context, permission) ==
                    PackageManager.PERMISSION_GRANTED
            return when (type) {
                "steps" -> Build.VERSION.SDK_INT < 29 ||
                    granted(Manifest.permission.ACTIVITY_RECOGNITION)
                "location" -> granted(Manifest.permission.ACCESS_FINE_LOCATION) ||
                    granted(Manifest.permission.ACCESS_COARSE_LOCATION)
                else -> false
            }
        }

        /**
         * Returns false instead of throwing when tracking cannot start: a missing runtime
         * permission, or an Android 12+ background-start restriction
         * (ForegroundServiceStartNotAllowedException, for example from an inexact alarm).
         */
        fun start(context: Context, type: String, data: JSONObject): Boolean {
            if (data.optString("attemptId").isEmpty() || !permitted(context, type)) return false
            val intent = Intent(context, TrackingService::class.java)
                .setAction("start")
                .putExtra("type", type)
                .putExtra("data", data.toString())
            return try {
                ContextCompat.startForegroundService(context, intent)
                true
            } catch (_: Exception) {
                false
            }
        }

        fun stop(context: Context, id: String) {
            AlarmEngine.prefs(context).edit().remove("track:$id").apply()
            try {
                context.startService(
                    Intent(context, TrackingService::class.java)
                        .setAction("stop")
                        .putExtra("attemptId", id),
                )
            } catch (_: Exception) {
                // Not running while the app is in the background: nothing is left to stop.
            }
        }
    }

    private val tracks = mutableMapOf<String, JSONObject>()
    private val listeners = mutableMapOf<String, ListenerRegistration>()
    private val sending = mutableSetOf<String>()
    private val retryAt = mutableMapOf<String, Long>()
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var sensors: SensorManager
    private lateinit var fused: FusedLocationProviderClient
    private var locationRegistered = false
    private var stepsRegistered = false

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (location in result.locations) onLocation(location)
        }
    }

    private val ticker = object : Runnable {
        override fun run() {
            for ((id, data) in tracks.toMap()) {
                if (System.currentTimeMillis() > data.optLong("untilEpochMs", 0)) {
                    AlarmEngine.cancel(this@TrackingService, id)
                    remove(id)
                    continue
                }
                if (data.optString("type") == "steps" && data.has("baseline")) {
                    try {
                        stepProgress(id, data)
                    } catch (_: Exception) {
                    }
                }
            }
            if (tracks.isNotEmpty()) handler.postDelayed(this, 5_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            Backend.initialize(this)
        } catch (_: Exception) {
            // Service must still startForeground; evidence submits retry later.
        }
        sensors = getSystemService(SensorManager::class.java)
        fused = LocationServices.getFusedLocationProviderClient(this)
        AlarmEngine.channels(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            remove(intent.getStringExtra("attemptId") ?: "")
            return START_NOT_STICKY
        }

        // A null intent is a START_STICKY restart after process death. That start is not
        // user-initiated, so only step tracks resume; location may only be read by a service
        // started while the app is visible (no ACCESS_BACKGROUND_LOCATION).
        val restarted = intent == null
        if (intent == null) {
            restorePersistedTracks()
        } else {
            try {
                addTrack(intent)
            } catch (_: Exception) {
                // Malformed start request; start() validates, so this is defensive only.
            }
        }

        for ((id, data) in tracks.toMap()) {
            if (!permitted(this, data.optString("type"))) interrupt(id, data, keep = restarted)
        }
        if (tracks.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }

        hasLocation = tracks.values.any { it.optString("type") == "location" }
        val hasSteps = tracks.values.any { it.optString("type") == "steps" }
        val notification = NotificationCompat.Builder(this, "tracking")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Showing up, one step at a time")
            .setContentText("Verification is active. Tap to see progress or end today.")
            .setOngoing(true)
            .setContentIntent(AlarmEngine.launch(this, tracks.keys.first()))
            .build()

        try {
            // Pass exactly the types in use: each one is checked against its permission.
            var foregroundType = 0
            if (hasLocation) {
                foregroundType = foregroundType or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            }
            if (hasSteps && Build.VERSION.SDK_INT >= 34) {
                foregroundType = foregroundType or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            }
            ServiceCompat.startForeground(this, 910, notification, foregroundType)
        } catch (_: Exception) {
            // Background-start limits (Android 12+) or a permission race (Android 14+) are
            // recoverable: keep progress and never turn them into a terminal server failure.
            for ((id, data) in tracks.toMap()) interrupt(id, data, keep = true)
            stopSelf()
            return START_NOT_STICKY
        }

        registerSensors(hasSteps)

        for ((id, data) in tracks) {
            persist(id, data)
            observe(id)
        }
        handler.removeCallbacks(ticker)
        handler.post(ticker)
        return START_STICKY
    }

    private fun restorePersistedTracks() {
        val now = System.currentTimeMillis()
        for ((key, value) in AlarmEngine.prefs(this).all) {
            if (!key.startsWith("track:") || value !is String) continue
            val data = try {
                JSONObject(value)
            } catch (_: Exception) {
                null
            }
            if (data == null || data.optLong("untilEpochMs") <= now) {
                AlarmEngine.prefs(this).edit().remove(key).apply()
            } else if (data.optString("type") == "steps") {
                tracks[key.removePrefix("track:")] = data
            }
        }
    }

    private fun addTrack(intent: Intent) {
        val input = JSONObject(intent.getStringExtra("data") ?: "{}")
        val id = input.getString("attemptId")
        val type = intent.getStringExtra("type") ?: "steps"
        val old = AlarmEngine.prefs(this).getString("track:$id", null)
        val data = if (old != null) JSONObject(old) else input
        data.put("type", type)

        val alarm = AlarmEngine.prefs(this)
            .getString("alarm:$id", null)
            ?.let(::JSONObject)
        if (!data.has("untilEpochMs")) {
            data.put(
                "untilEpochMs",
                alarm?.optLong("endEpochMs") ?: (System.currentTimeMillis() + 7_200_000L),
            )
        }
        if (!data.has("minDurationMs")) {
            data.put(
                "minDurationMs",
                alarm?.optJSONObject("verifierConfig")?.optLong("minDurationMs") ?: 60_000L,
            )
        }
        if (!data.has("startedAt")) data.put("startedAt", System.currentTimeMillis())
        if (!data.has("startedElapsed")) data.put("startedElapsed", SystemClock.elapsedRealtime())
        tracks[id] = data
    }

    private fun registerSensors(hasSteps: Boolean) {
        if (hasSteps && !stepsRegistered) {
            val sensor = sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
            if (sensor == null) {
                for ((id, data) in tracks.toMap()) {
                    if (data.optString("type") == "steps") fail(id, data, "sensor_missing")
                }
            } else {
                stepsRegistered = sensors.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_NORMAL,
                )
            }
        }
        if (hasLocation && !locationRegistered) {
            try {
                fused.requestLocationUpdates(
                    LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 60_000)
                        .setMinUpdateIntervalMillis(30_000)
                        .build(),
                    callback,
                    Looper.getMainLooper(),
                )
                locationRegistered = true
            } catch (_: SecurityException) {
                for ((id, data) in tracks.toMap()) {
                    if (data.optString("type") == "location") interrupt(id, data, keep = false)
                }
            }
        }
    }

    private fun persist(id: String, data: JSONObject) {
        AlarmEngine.prefs(this).edit().putString("track:$id", data.toString()).apply()
    }

    private fun observe(id: String) {
        if (listeners.containsKey(id)) return
        try {
            if (!Backend.initialize(this) || FirebaseApp.getApps(this).isEmpty()) return
            listeners[id] = FirebaseFirestore.getInstance()
                .document("attempts/$id")
                .addSnapshotListener { snapshot, _ ->
                    if (snapshot?.exists() == true && snapshot.getString("state") != "pending") {
                        AlarmEngine.cancel(this, id)
                        remove(id)
                    }
                }
        } catch (_: Exception) {
            // A later service start retries listener registration.
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onSensorChanged(event: SensorEvent) {
        try {
            val count = event.values[0].toLong()
            val boot = bootId()
            for ((id, data) in tracks.toMap()) {
                if (data.optString("type") != "steps") continue
                if (!data.has("baseline")) {
                    data.put("baseline", count)
                    data.put("boot", boot)
                    data.put("credited", 0)
                    data.put("last", count)
                } else if (abs(data.optLong("boot") - boot) > 2 || count < data.optLong("last")) {
                    // The counter restarts from zero after a reboot: bank progress, re-baseline.
                    val prior = (data.optLong("last") - data.optLong("baseline")).coerceAtLeast(0)
                    data.put("credited", data.optLong("credited") + prior)
                    data.put("baseline", count)
                    data.put("boot", boot)
                }
                data.put("last", count)
                persist(id, data)
                stepProgress(id, data)
            }
        } catch (_: Exception) {
        }
    }

    private fun stepProgress(id: String, data: JSONObject) {
        if (!data.has("targetSteps")) return
        val total = data.optLong("credited") +
            (data.optLong("last") - data.optLong("baseline")).coerceAtLeast(0)
        val elapsed = System.currentTimeMillis() - data.getLong("startedAt")
        val target = data.getInt("targetSteps")
        val ready = total >= target &&
            elapsed >= data.optLong("minDurationMs", 60_000) &&
            total / (elapsed / 60_000.0) <= 250
        Events.emit(
            "steps",
            mapOf(
                "type" to if (ready) "target_reached" else "progress",
                "attemptId" to id,
                "stepsSinceBaseline" to total,
                "elapsedMs" to elapsed,
            ),
        )
        if (ready) {
            submit(
                id,
                "steps",
                mapOf(
                    "stepsSinceBaseline" to total,
                    "elapsedMs" to elapsed,
                    "baselineCapturedAt" to data.getLong("startedAt"),
                ),
            )
        }
    }

    private fun onLocation(location: Location) {
        for ((id, data) in tracks.toMap()) {
            if (data.optString("type") != "location") continue
            if (!data.has("lat") || !data.has("lng") || !data.has("radiusM") || !data.has("dwellMs")) {
                continue
            }
            try {
            val distance = FloatArray(1)
            Location.distanceBetween(
                location.latitude,
                location.longitude,
                data.getDouble("lat"),
                data.getDouble("lng"),
                distance,
            )
            val mock = if (Build.VERSION.SDK_INT >= 31) {
                location.isMock
            } else {
                @Suppress("DEPRECATION")
                location.isFromMockProvider
            }
            val valid = !mock &&
                location.hasAccuracy() &&
                location.accuracy <= data.getInt("radiusM") &&
                distance[0] <= data.getInt("radiusM")
            val previous = data.optJSONObject("previousFix")
            val epoch = location.time
            val stale = System.currentTimeMillis() - epoch > 120_000
            val invalidSequence = previous != null &&
                (epoch - previous.getLong("epochMs") > 120_000 ||
                    epoch <= previous.getLong("epochMs"))
            if (!valid || stale || invalidSequence) {
                data.remove("enteredAt")
                data.remove("enteredElapsed")
            }
            if (valid && !stale && !data.has("enteredAt")) {
                data.put("enteredAt", epoch)
                data.put("enteredElapsed", location.elapsedRealtimeNanos / 1_000_000)
            }
            val elapsedNow = location.elapsedRealtimeNanos / 1_000_000
            // The server rejects dwellMs > epochMs - enteredAt, so never report more dwell
            // than the fix timestamps prove (monotonic and wall clocks can differ slightly).
            val dwell = if (valid && !stale) {
                (elapsedNow - data.optLong("enteredElapsed", elapsedNow))
                    .coerceAtMost(epoch - data.optLong("enteredAt", epoch))
                    .coerceAtLeast(0)
            } else {
                0
            }
            val fix = mapOf(
                "lat" to location.latitude,
                "lng" to location.longitude,
                "accuracyM" to location.accuracy.toDouble(),
                "isMock" to mock,
                "epochMs" to epoch,
            )
            val ready = valid &&
                !stale &&
                dwell >= data.getLong("dwellMs") &&
                previous != null
            Events.emit(
                "location",
                mapOf(
                    "type" to if (ready) "dwell_satisfied" else "dwell_progress",
                    "attemptId" to id,
                    "distanceM" to distance[0].toDouble(),
                    "dwellMs" to dwell,
                    "fix" to fix,
                ),
            )
            if (ready && previous != null) {
                submit(
                    id,
                    "location",
                    fix + mapOf(
                        "dwellMs" to dwell,
                        "enteredAt" to data.getLong("enteredAt"),
                        "previousFix" to mapOf(
                            "lat" to previous.getDouble("lat"),
                            "lng" to previous.getDouble("lng"),
                            "epochMs" to previous.getLong("epochMs"),
                        ),
                    ),
                )
            }
            data.put("previousFix", JSONObject(fix))
            persist(id, data)
            } catch (_: Exception) {
            }
        }
    }

    private fun submit(id: String, type: String, payload: Map<String, Any>) {
        if (id in sending || System.currentTimeMillis() < (retryAt[id] ?: 0)) return
        try {
            if (!Backend.initialize(this) ||
                FirebaseApp.getApps(this).isEmpty() ||
                FirebaseAuth.getInstance().currentUser == null
            ) {
                return
            }
            val separator = id.lastIndexOf('_')
            if (separator <= 0 || separator == id.lastIndex) return
            sending.add(id)
            FirebaseFunctions.getInstance()
                .getHttpsCallable("submitEvidence")
                .call(
                    mapOf(
                        "commitmentId" to id.substring(0, separator),
                        "date" to id.substring(separator + 1),
                        "type" to type,
                        "payload" to payload,
                    ),
                ).addOnSuccessListener {
                    val state = (it.data as? Map<*, *>)?.get("state")
                    if (state == "completed") {
                        AlarmEngine.cancel(this, id)
                        remove(id)
                    }
                }.addOnFailureListener {
                    retryAt[id] = System.currentTimeMillis() + 30_000
                }.addOnCompleteListener {
                    sending.remove(id)
                }
        } catch (_: Exception) {
            sending.remove(id)
        }
    }

    /**
     * Stops tracking [id] here and tells the UI, without a terminal server report: permission
     * and background-start problems are recoverable while the window is open. With [keep] the
     * persisted progress survives for the next user-initiated start.
     */
    private fun interrupt(id: String, data: JSONObject, keep: Boolean) {
        val type = data.optString("type")
        Events.emit(
            type,
            mapOf("type" to if (type == "steps") "sensor_lost" else "unavailable", "attemptId" to id),
        )
        remove(id, forget = !keep)
    }

    /** Permanent failure (no step sensor): reported so the attempt ends as unverifiable. */
    private fun fail(id: String, data: JSONObject, reason: String) {
        val signalType = if (data.optString("type") == "steps") "sensor_lost" else "unavailable"
        Events.emit(
            data.optString("type"),
            mapOf("type" to signalType, "attemptId" to id),
        )
        try {
            if (!Backend.initialize(this)) return
            val separator = id.lastIndexOf('_')
            if (separator > 0 && separator < id.lastIndex) {
                FirebaseFunctions.getInstance()
                    .getHttpsCallable("reportVerifierFailure")
                    .call(
                        mapOf(
                            "commitmentId" to id.substring(0, separator),
                            "date" to id.substring(separator + 1),
                            "reason" to reason,
                        ),
                    )
            }
        } catch (_: Exception) {
            // Local cleanup must still happen when the report cannot be sent.
        }
        AlarmEngine.cancel(this, id)
        remove(id)
    }

    private fun remove(id: String, forget: Boolean = true) {
        tracks.remove(id)
        retryAt.remove(id)
        listeners.remove(id)?.remove()
        if (forget) AlarmEngine.prefs(this).edit().remove("track:$id").apply()

        val hasSteps = tracks.values.any { it.optString("type") == "steps" }
        if (!hasSteps && stepsRegistered) {
            sensors.unregisterListener(this)
            stepsRegistered = false
        }
        hasLocation = tracks.values.any { it.optString("type") == "location" }
        if (!hasLocation && locationRegistered) {
            fused.removeLocationUpdates(callback)
            locationRegistered = false
        }
        if (tracks.isEmpty()) {
            handler.removeCallbacks(ticker)
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onDestroy() {
        sensors.unregisterListener(this)
        fused.removeLocationUpdates(callback)
        listeners.values.forEach { it.remove() }
        handler.removeCallbacksAndMessages(null)
        stepsRegistered = false
        locationRegistered = false
        hasLocation = false
        super.onDestroy()
    }
}
