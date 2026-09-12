package com.rayyanshaikh.orbit

import android.app.*
import android.content.*
import android.media.*
import android.os.*
import androidx.core.app.NotificationCompat
import org.json.*
import java.time.*
import kotlin.math.max
import kotlin.math.min

/** Persists and schedules exactly one reminder pulse per attempt. */
object AlarmEngine {
 private var ringtone: Ringtone? = null
 private var originalVolume: Int? = null
 private var ringingId: String? = null
 private val handler = Handler(Looper.getMainLooper())

 fun prefs(c: Context) = c.getSharedPreferences("showdup_native", Context.MODE_PRIVATE)
 fun channels(c: Context) {
  val nm = c.getSystemService(NotificationManager::class.java)
  nm.createNotificationChannel(NotificationChannel("reminders", "Commitment reminders", NotificationManager.IMPORTANCE_HIGH).apply { description = "Escalating reminders until verified or the reminder limit is reached"; setSound(null, null) })
  nm.createNotificationChannel(NotificationChannel("tracking", "Verification in progress", NotificationManager.IMPORTANCE_LOW))
 }
 fun launch(c: Context, id: String) = PendingIntent.getActivity(c, id.hashCode(), Intent(c, MainActivity::class.java).putExtra("attemptId", id).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
 private fun alarmIntent(c: Context, id: String, index: Int) = PendingIntent.getBroadcast(c, ("$id:$index").hashCode(), Intent(c, AlarmReceiver::class.java).setAction("showdup.reminder.$id.$index").putExtra("attemptId", id).putExtra("index", index), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

 fun schedule(c: Context, input: JSONObject): Boolean {
  val id = input.getString("attemptId"); val p = prefs(c)
  if (p.getBoolean("ended:$id", false)) return true
  val existing = p.getString("alarm:$id", null)?.let { try { JSONObject(it) } catch (_: Exception) { null } }
  val j = existing ?: JSONObject(input.toString()).apply { put("nextIndex", 0); put("nextAlarmAt", getLong("startEpochMs")); put("firstFiredAt", 0L); put("currentIndex", -1); put("lastHandledIndex", -1) }
  p.edit().putString("alarm:$id", j.toString()).putBoolean("ended:$id", false).apply(); configureBlocker(c, j)
  if (existing != null && j.optLong("nextAlarmAt", 0L) == 0L && j.optInt("currentIndex", -1) > j.optInt("lastHandledIndex", -1)) { silence(c, id, true, "automatic"); return true }
  return scheduleAt(c, id, j.optInt("nextIndex", 0), max(System.currentTimeMillis() + 250, j.optLong("nextAlarmAt", j.getLong("startEpochMs"))))
 }
 private fun scheduleAt(c: Context, id: String, index: Int, at: Long): Boolean {
  val raw = prefs(c).getString("alarm:$id", null) ?: return true; val j = JSONObject(raw); val limit = min(AlarmSchedulePolicy.MAX_PULSES, j.optInt("maxReminders", AlarmSchedulePolicy.MAX_PULSES))
  if (index >= limit || at >= deadline(j)) { expire(c, id, "reminder_limit"); return true }
  j.put("nextIndex", index).put("nextAlarmAt", at); prefs(c).edit().putString("alarm:$id", j.toString()).apply()
  val am = c.getSystemService(AlarmManager::class.java); val exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms(); val pi = alarmIntent(c, id, index)
  if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi) else {
   diagnostic(c, "exact_alarm_denied", "Android may delay reminder pulses until exact-alarm access is enabled.")
   am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
  }
  return exact
 }
 private fun deadline(j: JSONObject): Long = AlarmSchedulePolicy.deadline(j.optLong("firstFiredAt", 0L), j.getLong("endEpochMs"))
 private fun configureBlocker(c: Context, j: JSONObject) {
  val restriction = j.optJSONObject("restrictions")
  if (restriction?.optBoolean("enabled") == true && AppBlocker.isEntitled(c)) { val values = restriction.optJSONArray("packages") ?: JSONArray(); AppBlocker.configure(c, (0 until values.length()).map { values.getString(it) }, j.getLong("endEpochMs"), null, j.getString("attemptId"), j.getLong("startEpochMs")) }
 }
 fun cancel(c: Context, id: String) {
  prefs(c).getString("alarm:$id", null)?.let { val j = JSONObject(it); for (i in 0 until min(6, j.optInt("maxReminders", 6))) c.getSystemService(AlarmManager::class.java).cancel(alarmIntent(c, id, i)) }
  prefs(c).edit().remove("alarm:$id").putBoolean("ended:$id", true).apply(); AppBlocker.stop(c, id); silence(c, id, false, "cancelled")
 }
 fun silence(c: Context, id: String, snooze: Boolean, source: String = "manual") {
  if (ringingId == id) { ringtone?.stop(); ringtone = null; ringingId = null; originalVolume?.let { c.getSystemService(AudioManager::class.java).setStreamVolume(AudioManager.STREAM_ALARM, it, 0) }; originalVolume = null }
  c.getSystemService(NotificationManager::class.java).cancel(id.hashCode()); if (!snooze) return
  val raw = prefs(c).getString("alarm:$id", null) ?: return; val j = JSONObject(raw); val current = j.optInt("currentIndex", -1)
  if (current < 0 || j.optInt("lastHandledIndex", -1) >= current) return
  j.put("lastHandledIndex", current); prefs(c).edit().putString("alarm:$id", j.toString()).apply(); event(c, id, "snoozed", current.toString(), source); scheduleNext(c, id, current + 1)
 }
 private fun scheduleNext(c: Context, id: String, nextIndex: Int) {
  val j = JSONObject(prefs(c).getString("alarm:$id", null) ?: return)
  scheduleAt(c, id, nextIndex, System.currentTimeMillis() + AlarmSchedulePolicy.gapMs(j.optLong("intervalMinutes", 20L), nextIndex))
 }
 fun event(c: Context, id: String, type: String, index: String, source: String? = null) {
  val eventId = "$type:$index:${System.currentTimeMillis()}"; val countKey = "reminder_count:$id:$type"; val p = prefs(c); val payload = JSONObject().put("attemptId", id).put("type", type).put("index", index.toIntOrNull() ?: 0).put("occurredAt", System.currentTimeMillis()); if (source != null) payload.put("source", source)
  p.edit().putString("reminder_event:$id:$eventId", payload.toString()).putInt(countKey, p.getInt(countKey, 0) + 1).apply(); Events.emit("alarm", mapOf("attemptId" to id, "type" to type, "index" to (index.toIntOrNull() ?: 0), "source" to source))
 }
 fun diagnostic(c: Context, kind: String, message: String) { prefs(c).edit().putString("diagnostic:$kind", JSONObject().put("message", message).put("occurredAt", System.currentTimeMillis()).toString()).apply() }

 fun fire(c: Context, id: String, index: Int) {
  val raw = prefs(c).getString("alarm:$id", null) ?: return; val j = JSONObject(raw); val now = System.currentTimeMillis()
  if (now >= j.getLong("endEpochMs") || prefs(c).getBoolean("ended:$id", false)) { expire(c, id, "window_ended"); return }
  channels(c); configureBlocker(c, j); if (j.optLong("firstFiredAt", 0L) == 0L) j.put("firstFiredAt", now); j.put("currentIndex", index).put("nextIndex", index).put("nextAlarmAt", 0L); prefs(c).edit().putString("alarm:$id", j.toString()).apply()
  val snooze = PendingIntent.getBroadcast(c, ("snooze:$id:$index").hashCode(), Intent(c, AlarmReceiver::class.java).setAction("showdup.snooze").putExtra("attemptId", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  val n = NotificationCompat.Builder(c, "reminders").setSmallIcon(R.drawable.ic_notification).setContentTitle(j.optString("title", "Time to show up")).setContentText("Pulse ${index + 1} of ${min(6, j.optInt("maxReminders", 6))}. Snoozing lowers today’s score.").setPriority(NotificationCompat.PRIORITY_MAX).setCategory(NotificationCompat.CATEGORY_ALARM).setContentIntent(launch(c, id)).setFullScreenIntent(launch(c, id), true).setAutoCancel(true).addAction(0, "Snooze", snooze).build()
  c.getSystemService(NotificationManager::class.java).notify(id.hashCode(), n); ringingId?.let { silence(c, it, false, "replaced") }; ringingId = id
  if (j.optString("volumeMode") == "loud") { val audio = c.getSystemService(AudioManager::class.java); originalVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM); audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0) }
  ringtone = RingtoneManager.getRingtone(c, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)); ringtone?.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(); ringtone?.play(); handler.postDelayed({ if (ringingId == id) silence(c, id, true, "automatic") }, 30_000); event(c, id, "fired", index.toString())
  if (j.optString("verifierType") == "steps") try { val cfg = j.getJSONObject("verifierConfig"); if (!TrackingService.start(c, "steps", JSONObject().put("attemptId", id).put("targetSteps", cfg.getInt("targetSteps")).put("minDurationMs", cfg.getLong("minDurationMs")).put("untilEpochMs", j.getLong("endEpochMs")))) diagnostic(c, "tracking_start", "Android denied starting step verification from this reminder.") } catch (e: Exception) { diagnostic(c, "tracking_start", e.message ?: "Unable to start step verification.") }
 }
 private fun expire(c: Context, id: String, reason: String) {
  if (prefs(c).getBoolean("ended:$id", false)) return; val raw = prefs(c).getString("alarm:$id", null); val j = raw?.let { JSONObject(it) }
  prefs(c).edit().putString("expiration:$id", JSONObject().put("attemptId", id).put("reason", reason).put("expiredAt", System.currentTimeMillis()).toString()).remove("alarm:$id").putBoolean("ended:$id", true).apply(); j?.let { for (i in 0 until min(6, it.optInt("maxReminders", 6))) c.getSystemService(AlarmManager::class.java).cancel(alarmIntent(c, id, i)) }; AppBlocker.stop(c, id); silence(c, id, false, "expired"); Events.emit("alarm", mapOf("attemptId" to id, "type" to "expired", "index" to (j?.optInt("currentIndex", 0) ?: 0)))
 }
 fun configure(c: Context, commitments: List<*>) {
  val list = JSONArray(commitments); prefs(c).edit().putString("commitments", list.toString()).apply(); val activeIds = (0 until list.length()).map { list.getJSONObject(it).getString("id") }.toSet(); for ((k, _) in prefs(c).all) if (k.startsWith("alarm:")) { val aid = k.removePrefix("alarm:"); if (aid.substringBeforeLast('_') !in activeIds) cancel(c, aid) }; restore(c)
 }
 fun restore(c: Context) {
  val list = JSONArray(prefs(c).getString("commitments", "[]")); val now = System.currentTimeMillis()
  for (i in 0 until list.length()) { val commitment = list.getJSONObject(i); val schedule = commitment.getJSONObject("schedule"); val reminder = commitment.getJSONObject("reminder"); val zone = ZoneId.of(schedule.getString("timezone")); val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate(); val days = schedule.getJSONArray("daysOfWeek")
   for (d in 0..8) { val date = today.plusDays(d.toLong()); if ((0 until days.length()).none { days.getInt(it) == date.dayOfWeek.value }) continue; val custom = schedule.optJSONObject("dayWindows")?.optJSONObject(date.dayOfWeek.value.toString()); val startLocal = custom?.optString("startLocal")?.takeIf { it.isNotBlank() } ?: schedule.getString("windowStartLocal"); val endLocal = custom?.optString("endLocal")?.takeIf { it.isNotBlank() } ?: schedule.getString("windowEndLocal"); val start = date.atTime(LocalTime.parse(startLocal)).atZone(zone).toInstant().toEpochMilli(); val end = date.atTime(LocalTime.parse(endLocal)).atZone(zone).toInstant().toEpochMilli(); if (end <= now) continue; val id = "${commitment.getString("id")}_$date"; schedule(c, JSONObject().put("attemptId", id).put("startEpochMs", start).put("endEpochMs", end).put("intervalMinutes", reminder.getInt("intervalMinutes")).put("maxReminders", min(6, reminder.getInt("maxReminders"))).put("volumeMode", reminder.getString("volumeMode")).put("title", commitment.getString("title")).put("verifierType", commitment.getString("verifierType")).put("verifierConfig", commitment.getJSONObject("verifierConfig")).put("restrictions", commitment.optJSONObject("restrictions") ?: JSONObject())) }
  }
  val pi = PendingIntent.getBroadcast(c, 814, Intent(c, BootReceiver::class.java).setAction("showdup.maintenance"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE); c.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, now + 86_400_000, pi)
  for ((k, v) in prefs(c).all) if (k.startsWith("alarm:")) { val id = k.removePrefix("alarm:"); val j = JSONObject(v as String); if (j.getLong("endEpochMs") <= now) expire(c, id, "window_ended") else if (j.optLong("nextAlarmAt", 0L) > 0L) scheduleAt(c, id, j.optInt("nextIndex", 0), max(now + 250, j.getLong("nextAlarmAt"))) else if(j.optInt("currentIndex",-1)>j.optInt("lastHandledIndex",-1))silence(c,id,true,"automatic") }
 }
 fun clear(c: Context) { for ((k, _) in prefs(c).all) if (k.startsWith("alarm:")) cancel(c, k.removePrefix("alarm:")); prefs(c).edit().clear().apply() }
}
