package com.rayyanshaikh.orbit

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.FirebaseFunctionsException
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

object AlarmEngine {
    private var ringtone: Ringtone? = null
    private var originalVolume: Int? = null
    private var ringingId: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())

    fun prefs(context: Context) =
        context.getSharedPreferences("showdup_native", Context.MODE_PRIVATE)

    fun channels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                "reminders",
                "Commitment reminders",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Reminders until verified or your window ends"
                setSound(null, null)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 200, 250)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                "tracking",
                "Verification in progress",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    fun launch(context: Context, id: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            id.hashCode(),
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(
                    Uri.parse("showdup://today").buildUpon()
                        .appendQueryParameter("attemptId", id)
                        .build(),
                )
                .putExtra("attemptId", id)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP,
                ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun alarmIntent(context: Context, id: String, index: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            "$id:$index".hashCode(),
            Intent(context, AlarmReceiver::class.java)
                .setAction("showdup.reminder.$id.$index")
                .putExtra("attemptId", id)
                .putExtra("index", index),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun schedule(context: Context, data: JSONObject): Boolean {
        val id = data.getString("attemptId")
        if (prefs(context).getBoolean("ended:$id", false)) return true

        prefs(context).edit().putString("alarm:$id", data.toString()).apply()
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val exact = Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms()
        val now = System.currentTimeMillis()
        val start = data.getLong("startEpochMs")
        val end = data.getLong("endEpochMs")
        val intervalMs = data.getLong("intervalMinutes") * 60_000L

        for (index in 0 until data.getInt("maxReminders")) {
            val at = start + index * intervalMs
            if (at >= end || at < now) continue
            val pendingIntent = alarmIntent(context, id, index)
            try {
                if (exact) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        at,
                        pendingIntent,
                    )
                } else {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent)
                }
            } catch (_: SecurityException) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent)
            }
        }
        return exact && (Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms())
    }

    fun cancel(context: Context, id: String) {
        val stored = prefs(context).getString("alarm:$id", null)
        if (stored != null) {
            try {
                val data = JSONObject(stored)
                val alarmManager = context.getSystemService(AlarmManager::class.java)
                for (index in 0 until data.getInt("maxReminders")) {
                    alarmManager.cancel(alarmIntent(context, id, index))
                }
            } catch (_: Exception) {
            }
        }
        prefs(context).edit().remove("alarm:$id").putBoolean("ended:$id", true).apply()
        silence(context, id, false)
    }

    fun silence(context: Context, id: String, snooze: Boolean) {
        if (ringingId == id) {
            try {
                ringtone?.stop()
            } catch (_: Exception) {
            }
            ringtone = null
            ringingId = null
            originalVolume?.let {
                context.getSystemService(AudioManager::class.java)
                    .setStreamVolume(AudioManager.STREAM_ALARM, it, 0)
            }
            originalVolume = null
            releaseWakeLock()
        }
        context.getSystemService(NotificationManager::class.java).cancel(id.hashCode())
        if (snooze) event(context, id, "snoozed", System.currentTimeMillis().toString())
    }

    private fun holdWakeLock(context: Context, durationMs: Long) {
        releaseWakeLock()
        try {
            wakeLock = context.getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "showdup:alarm")
                .apply {
                    setReferenceCounted(false)
                    acquire(durationMs)
                }
        } catch (_: Exception) {
            wakeLock = null
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun event(context: Context, id: String, type: String, index: String) {
        val eventId = "$type:$index"
        val data = mapOf("attemptId" to id, "type" to type, "eventId" to eventId)
        prefs(context).edit().putString("event:$id:$eventId", JSONObject(data).toString()).apply()
        Events.emit(
            "alarm",
            mapOf(
                "attemptId" to id,
                "type" to type,
                "index" to (index.toIntOrNull() ?: 0),
            ),
        )
        flushEvents(context)
    }

    fun flushEvents(context: Context) {
        if (!Backend.initialize(context)) return
        for ((key, value) in prefs(context).all.toMap()) {
            if (!key.startsWith("event:") || value !is String) continue
            try {
                val data = JSONObject(value)
                FirebaseFunctions.getInstance()
                    .getHttpsCallable("recordReminderEvent")
                    .call(
                        mapOf(
                            "attemptId" to data.getString("attemptId"),
                            "type" to data.getString("type"),
                            "eventId" to data.getString("eventId"),
                        ),
                    ).addOnSuccessListener {
                        prefs(context).edit().remove(key).apply()
                    }.addOnFailureListener { error ->
                        // Permanently malformed legacy events cannot succeed on retry.
                        if (error is FirebaseFunctionsException &&
                            error.code == FirebaseFunctionsException.Code.INVALID_ARGUMENT
                        ) {
                            prefs(context).edit().remove(key).apply()
                        }
                    }
            } catch (_: Exception) {
                // Keep valid queued events for the next authenticated/app-checked flush.
            }
        }
    }

    fun fire(context: Context, id: String, index: Int) {
        val raw = prefs(context).getString("alarm:$id", null) ?: return
        val data = JSONObject(raw)
        if (System.currentTimeMillis() > data.getLong("endEpochMs") ||
            prefs(context).getBoolean("ended:$id", false)
        ) {
            return
        }
        channels(context)

        val snooze = PendingIntent.getBroadcast(
            context,
            "snooze:$id".hashCode(),
            Intent(context, AlarmReceiver::class.java)
                .setAction("showdup.snooze")
                .putExtra("attemptId", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, "reminders")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(data.optString("title", "Time to show up"))
            .setContentText("Snooze buys time. Only evidence completes it.")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(launch(context, id))
            .setFullScreenIntent(launch(context, id), true)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 250, 200, 250))
            .addAction(0, "Snooze", snooze)
            .build()
        context.getSystemService(NotificationManager::class.java).notify(id.hashCode(), notification)

        ringingId?.let { silence(context, it, false) }
        ringingId = id
        holdWakeLock(context, 30_000)
        if (data.optString("volumeMode") == "loud") {
            val audio = context.getSystemService(AudioManager::class.java)
            originalVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
            audio.setStreamVolume(
                AudioManager.STREAM_ALARM,
                audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                0,
            )
        }
        try {
            ringtone = RingtoneManager.getRingtone(
                context,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            )
            ringtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()
            ringtone?.play()
        } catch (_: Exception) {
            ringtone = null
        }
        handler.postDelayed({ if (ringingId == id) silence(context, id, false) }, 30_000)

        event(context, id, "fired", index.toString())
        if (data.optString("verifierType") == "steps") {
            try {
                val config = data.getJSONObject("verifierConfig")
                TrackingService.start(
                    context,
                    "steps",
                    JSONObject()
                        .put("attemptId", id)
                        .put("targetSteps", config.getInt("targetSteps"))
                        .put("minDurationMs", config.getLong("minDurationMs"))
                        .put("untilEpochMs", data.getLong("endEpochMs")),
                )
            } catch (_: Exception) {
                // The foreground UI can surface verifier configuration failures.
            }
        }
        restore(context)
    }

    fun configure(context: Context, commitments: List<*>) {
        val list = JSONArray(commitments)
        prefs(context).edit().putString("commitments", list.toString()).apply()
        val activeIds = (0 until list.length())
            .mapNotNull {
                try {
                    list.getJSONObject(it).getString("id")
                } catch (_: Exception) {
                    null
                }
            }
            .toSet()
        for ((key, _) in prefs(context).all) {
            if (!key.startsWith("alarm:")) continue
            val attemptId = key.removePrefix("alarm:")
            if (attemptId.substringBeforeLast('_') !in activeIds) cancel(context, attemptId)
        }
        restore(context)
    }

    fun restore(context: Context) {
        try {
            restoreLocked(context)
        } catch (_: Exception) {
            // Boot and exact-alarm broadcasts must never crash the process.
        }
    }

    private fun restoreLocked(context: Context) {
        val list = JSONArray(prefs(context).getString("commitments", "[]"))
        val now = System.currentTimeMillis()
        for (index in 0 until list.length()) {
            try {
                scheduleCommitmentDay(context, list.getJSONObject(index), now)
            } catch (_: Exception) {
                // One malformed commitment must not block the rest.
            }
        }

        // Daily maintenance replenishes future reminders even if the app stays closed.
        val maintenance = PendingIntent.getBroadcast(
            context,
            814,
            Intent(context, BootReceiver::class.java).setAction("showdup.maintenance"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                now + 86_400_000L,
                maintenance,
            )
        } catch (_: Exception) {
        }

        for ((key, value) in prefs(context).all.toMap()) {
            if (!key.startsWith("alarm:") || value !is String) continue
            try {
                val data = JSONObject(value)
                if (data.getLong("endEpochMs") < now) {
                    prefs(context).edit().remove(key).apply()
                    silence(context, key.removePrefix("alarm:"), false)
                }
            } catch (_: Exception) {
                prefs(context).edit().remove(key).apply()
            }
        }
    }

    private fun scheduleCommitmentDay(context: Context, commitment: JSONObject, now: Long) {
        val commitmentSchedule = commitment.getJSONObject("schedule")
        val reminder = commitment.getJSONObject("reminder")
        val zone = ZoneId.of(commitmentSchedule.getString("timezone"))
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val days = commitmentSchedule.getJSONArray("daysOfWeek")

        for (offset in 0..8) {
            val date = today.plusDays(offset.toLong())
            val isScheduled = (0 until days.length())
                .any { days.getInt(it) == date.dayOfWeek.value }
            if (!isScheduled) continue

            val start = date
                .atTime(LocalTime.parse(commitmentSchedule.getString("windowStartLocal")))
                .atZone(zone)
                .toInstant()
                .toEpochMilli()
            val end = date
                .atTime(LocalTime.parse(commitmentSchedule.getString("windowEndLocal")))
                .atZone(zone)
                .toInstant()
                .toEpochMilli()
            if (end <= now) continue

            val attemptId = "${commitment.getString("id")}_$date"
            schedule(
                context,
                JSONObject()
                    .put("attemptId", attemptId)
                    .put("startEpochMs", start)
                    .put("endEpochMs", end)
                    .put("intervalMinutes", reminder.getInt("intervalMinutes"))
                    .put("maxReminders", reminder.getInt("maxReminders"))
                    .put("volumeMode", reminder.getString("volumeMode"))
                    .put("title", commitment.getString("title"))
                    .put("verifierType", commitment.getString("verifierType"))
                    .put("verifierConfig", commitment.getJSONObject("verifierConfig")),
            )
        }
    }

    fun clear(context: Context) {
        for ((key, _) in prefs(context).all.toMap()) {
            if (key.startsWith("alarm:")) cancel(context, key.removePrefix("alarm:"))
        }
        prefs(context).edit().clear().apply()
        releaseWakeLock()
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val id = intent.getStringExtra("attemptId") ?: return
            if (intent.action == "showdup.snooze") {
                AlarmEngine.silence(context, id, true)
            } else {
                AlarmEngine.fire(context, id, intent.getIntExtra("index", 0))
            }
        } catch (_: Exception) {
            // A bad payload or missing Firebase config must not crash the receiver.
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            // Credential-encrypted prefs are unavailable before unlock.
            if (intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED) return
            AlarmEngine.restore(context)
            AlarmEngine.flushEvents(context)
            // Location requires a visible activity; its notification invites the user back.
        } catch (_: Exception) {
        }
    }
}
