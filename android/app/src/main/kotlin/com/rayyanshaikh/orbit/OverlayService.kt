package com.rayyanshaikh.orbit

import android.app.*
import android.content.*
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class OverlayService : Service() {
 private lateinit var wm: WindowManager
 private var root: View? = null
 private var expanded = false
 private var downX = 0f
 private var downY = 0f
 private var startX = 0
 private var startY = 0
 private val permissionHandler = android.os.Handler(android.os.Looper.getMainLooper())
  private val permissionCheck = object : Runnable {
   override fun run() {
   // Overlay permission can be revoked while the service is running. Keep the
   // preference truthful so we neither resurrect nor advertise a dead overlay.
   if (!canDraw(this@OverlayService)) {
    prefs(this@OverlayService).edit().putBoolean(ENABLED, false).apply()
    stopSelf()
    return
   }
   permissionHandler.postDelayed(this, 5000)
  }
 }

 companion object {
  private const val PREFS = "showdup_overlay"
  private const val ENABLED = "enabled"
  private const val SNAPSHOT = "snapshot"
  private const val X = "x"
  private const val Y = "y"
  private const val CHANNEL = "showdup_pet_overlay"
  private const val ID = 22091
  const val ACTION_STOP = "showdup.overlay.STOP"

  fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
  fun canDraw(c: Context) = Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(c)
  fun status(c: Context) = mapOf(
   "permissionGranted" to canDraw(c),
   "enabled" to prefs(c).getBoolean(ENABLED, false),
   "running" to (instance != null)
  )
  @Volatile private var instance: OverlayService? = null

  fun enable(c: Context): Boolean {
   if (!canDraw(c)) return false
   return try {
    prefs(c).edit().putBoolean(ENABLED, true).apply()
    ContextCompat.startForegroundService(c, Intent(c, OverlayService::class.java))
    true
   } catch (_: Exception) {
    // Android may deny background FGS starts. Do not leave a stale enabled flag.
    prefs(c).edit().putBoolean(ENABLED, false).apply()
    false
   }
  }
  fun disable(c: Context) {
   prefs(c).edit().putBoolean(ENABLED, false).apply()
   c.stopService(Intent(c, OverlayService::class.java))
  }
  fun sync(c: Context, data: Map<*, *>) {
   val snapshot = JSONObject(data)
   val activeId = snapshot.optString("activeAttemptId")
   if (activeId.isNotBlank()) {
    AlarmEngine.prefs(c).getString("alarm:$activeId", null)?.let {
     try { snapshot.put("nextAlarmEpochMs", JSONObject(it).optLong("nextAlarmAt", 0L)) } catch (_: Exception) {}
    }
   }
   prefs(c).edit().putString(SNAPSHOT, snapshot.toString()).apply()
   instance?.render()
  }
  fun permissionIntent(c: Context) = Intent(
   Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
   Uri.parse("package:${c.packageName}")
  )
  fun showRestoreNotification(c: Context) {
   if (!prefs(c).getBoolean(ENABLED, false)) return
   ensureChannel(c)
   val launch = PendingIntent.getActivity(
    c, 22092,
    Intent(c, MainActivity::class.java).putExtra("restoreOverlay", true),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
   )
   val n = NotificationCompat.Builder(c, CHANNEL)
    .setSmallIcon(R.drawable.ic_notification)
    .setContentTitle("Bring your ShowdUp pet back")
    .setContentText("Tap to restore the accountability overlay after restart.")
    .setContentIntent(launch).setAutoCancel(true).build()
   c.getSystemService(NotificationManager::class.java).notify(ID + 1, n)
  }
  private fun ensureChannel(c: Context) {
   c.getSystemService(NotificationManager::class.java).createNotificationChannel(
    NotificationChannel(CHANNEL, "ShowdUp pet overlay", NotificationManager.IMPORTANCE_LOW).apply {
     description = "Keeps your optional accountability pet available over other apps"
     setSound(null, null)
    }
   )
  }
 }

 override fun onCreate() {
  super.onCreate()
  if (!prefs(this).getBoolean(ENABLED, false) || !canDraw(this)) {
   prefs(this).edit().putBoolean(ENABLED, false).apply()
   stopSelf()
   return
  }
  instance = this
  wm = getSystemService(WindowManager::class.java)
  ensureForeground()
  permissionHandler.post(permissionCheck)
 }

 override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
  if (intent?.action == ACTION_STOP) {
   disable(this)
   return START_NOT_STICKY
  }
  if (!prefs(this).getBoolean(ENABLED, false) || !canDraw(this)) {
   stopSelf()
   return START_NOT_STICKY
  }
  render()
  return START_STICKY
 }

 private fun ensureForeground() {
  ensureChannel(this)
  val open = PendingIntent.getActivity(
   this, 22093, Intent(this, MainActivity::class.java),
   PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
  )
  val stop = PendingIntent.getService(
   this, 22094, Intent(this, OverlayService::class.java).setAction(ACTION_STOP),
   PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
  )
  val notification = NotificationCompat.Builder(this, CHANNEL)
   .setSmallIcon(R.drawable.ic_notification)
   .setContentTitle("ShowdUp pet is watching")
   .setContentText("Tap to open ShowdUp. You can turn the overlay off anytime.")
   .setContentIntent(open).setOngoing(true)
   .addAction(0, "Turn off", stop).build()
  startForeground(ID, notification)
 }

 private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
 private fun round(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
  setColor(color); cornerRadius = dp(radius).toFloat()
  if (stroke != null) setStroke(dp(1), stroke)
 }
 private fun text(value: String, size: Float, color: Int = Color.WHITE, bold: Boolean = false) =
  TextView(this).apply {
   this.text = value; textSize = size; setTextColor(color)
   gravity = Gravity.CENTER_VERTICAL
   if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
  }

 internal fun render() {
  if (!canDraw(this)) { stopSelf(); return }
  val snapshot = try { JSONObject(prefs(this).getString(SNAPSHOT, "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
  root?.let { try { wm.removeView(it) } catch (_: Exception) {} }
  root = if (expanded) expandedView(snapshot) else pillView(snapshot)
  val p = params(expanded)
  try { wm.addView(root, p) } catch (_: Exception) { root = null; stopSelf() }
 }

 private fun params(full: Boolean) = WindowManager.LayoutParams(
  if (full) WindowManager.LayoutParams.MATCH_PARENT else WindowManager.LayoutParams.WRAP_CONTENT,
  if (full) WindowManager.LayoutParams.MATCH_PARENT else WindowManager.LayoutParams.WRAP_CONTENT,
  if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
  WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
  android.graphics.PixelFormat.TRANSLUCENT
 ).apply {
  gravity = if (full) Gravity.FILL else Gravity.TOP or Gravity.START
  if (!full) {
   x = prefs(this@OverlayService).getInt(X, dp(12))
   y = prefs(this@OverlayService).getInt(Y, dp(120))
  }
 }

 private fun pillView(j: JSONObject): View {
  val row = LinearLayout(this).apply {
   orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
   setPadding(dp(12), dp(7), dp(12), dp(7))
   val mood = j.optString("mood", "happy")
   val colors = when (mood) {
    "uneasy" -> Color.rgb(108, 73, 17) to Color.rgb(255, 198, 87)
    "sad" -> Color.rgb(33, 48, 82) to Color.rgb(121, 161, 255)
    "cracked" -> Color.rgb(91, 31, 36) to Color.rgb(255, 126, 135)
    else -> Color.rgb(20, 70, 44) to Color.rgb(103, 232, 165)
   }
   background = round(colors.first, 28, colors.second)
   elevation = dp(8).toFloat()
  }
  row.addView(text(j.optString("mascotGlyph", "🦊"), 27f), LinearLayout.LayoutParams(dp(40), dp(40)))
  row.addView(text(j.optInt("weeklyScore", 0).toString(), 22f, Color.rgb(220, 255, 229), true).apply { setPadding(dp(5), 0, dp(9), 0) })
  val friends = j.optJSONArray("friendGlyphs") ?: JSONArray()
  for (i in 0 until min(3, friends.length())) row.addView(text(friends.optString(i, "•"), 16f), LinearLayout.LayoutParams(dp(25), dp(30)))
  row.setOnTouchListener { view, event ->
   val lp = view.layoutParams as? WindowManager.LayoutParams ?: return@setOnTouchListener false
   when (event.actionMasked) {
    MotionEvent.ACTION_DOWN -> { downX = event.rawX; downY = event.rawY; startX = lp.x; startY = lp.y; true }
    MotionEvent.ACTION_MOVE -> {
     val metrics = resources.displayMetrics
     lp.x = (startX + event.rawX - downX).toInt().coerceIn(0, max(0, metrics.widthPixels - view.width))
     lp.y = (startY + event.rawY - downY).toInt().coerceIn(dp(24), max(dp(24), metrics.heightPixels - view.height - dp(48)))
     wm.updateViewLayout(view, lp); true
    }
    MotionEvent.ACTION_UP -> {
     if (abs(event.rawX - downX) < dp(8) && abs(event.rawY - downY) < dp(8)) {
      expanded = true; render()
     } else {
      val metrics = resources.displayMetrics
      lp.x = if (lp.x + view.width / 2 < metrics.widthPixels / 2) dp(8) else max(dp(8), metrics.widthPixels - view.width - dp(8))
      prefs(this).edit().putInt(X, lp.x).putInt(Y, lp.y).apply()
      wm.updateViewLayout(view, lp)
     }
     true
    }
    else -> false
   }
  }
  return row
 }

 private fun expandedView(j: JSONObject): View {
  val scrim = FrameLayout(this).apply { setBackgroundColor(0xB8000000.toInt()); isClickable = true }
  scrim.setOnClickListener { expanded = false; render() }
  val card = LinearLayout(this).apply {
   orientation = LinearLayout.VERTICAL; setPadding(dp(22), dp(20), dp(22), dp(20))
   background = round(Color.rgb(20, 23, 20), 28, Color.rgb(62, 77, 65)); isClickable = true
  }
  val title = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
  title.addView(text(j.optString("mascotGlyph", "🦊"), 38f), LinearLayout.LayoutParams(dp(56), dp(56)))
  title.addView(LinearLayout(this).apply {
   orientation = LinearLayout.VERTICAL
   addView(text(j.optString("mood", "happy").replaceFirstChar { it.uppercase() } + " pet", 12f, Color.rgb(148, 166, 153)))
   addView(text("${j.optInt("weeklyScore", 0)} points", 24f, Color.WHITE, true))
  }, LinearLayout.LayoutParams(0, WindowManager.LayoutParams.WRAP_CONTENT, 1f))
  title.addView(text("✕", 22f).apply { setPadding(dp(12), 0, 0, 0); setOnClickListener { expanded = false; render() } })
  card.addView(title)
  card.addView(text(j.optString("activeTitle", "No active commitment"), 17f, Color.WHITE, true).apply { setPadding(0, dp(12), 0, dp(4)) })
  val next = j.optLong("nextAlarmEpochMs", 0L)
  val sub = "Today ${j.optInt("todayCompleted", 0)}/${j.optInt("todayTotal", 0)}  •  ${j.optInt("streak", 0)} day streak" + if (next > 0) "  •  alarm scheduled" else ""
  card.addView(text(sub, 12f, Color.rgb(165, 182, 169)))
  card.addView(text("Weekly battle", 13f, Color.rgb(103, 232, 165), true).apply { setPadding(0, dp(18), 0, dp(8)) })
  val ranks = j.optJSONArray("topRanks") ?: JSONArray()
  if (ranks.length() == 0) card.addView(text("Invite a friend to activate your battle.", 13f, Color.rgb(165, 182, 169)))
  for (i in 0 until min(5, ranks.length())) {
   val rank = ranks.optJSONObject(i) ?: continue
   card.addView(text("${rank.optInt("rank", i + 1)}   ${rank.optString("name", "Player")}                         ${rank.optInt("score", 0)}", 13f).apply { setPadding(0, dp(9), 0, dp(9)) })
  }
  val actions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.END; setPadding(0, dp(18), 0, 0) }
  val open = text("OPEN SHOWDUP", 12f, Color.rgb(103, 232, 165), true).apply { setPadding(dp(12), dp(10), dp(12), dp(10)); setOnClickListener { startActivity(Intent(this@OverlayService, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); expanded = false; render() } }
  actions.addView(open)
  if (j.optString("activeAttemptId").isNotBlank()) actions.addView(text("SNOOZE", 12f, Color.WHITE, true).apply { setPadding(dp(12), dp(10), dp(12), dp(10)); setOnClickListener { AlarmEngine.silence(this@OverlayService, j.optString("activeAttemptId"), true, "manual") } })
  actions.addView(text("TURN OFF", 12f, Color.rgb(255, 151, 151), true).apply { setPadding(dp(12), dp(10), 0, dp(10)); setOnClickListener { disable(this@OverlayService) } })
  card.addView(actions)
  val cardParams = FrameLayout.LayoutParams(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT, Gravity.CENTER).apply { setMargins(dp(20), dp(48), dp(20), dp(48)) }
  scrim.addView(card, cardParams)
  return scrim
 }

 override fun onDestroy() {
  permissionHandler.removeCallbacks(permissionCheck)
  root?.let { try { wm.removeView(it) } catch (_: Exception) {} }
  root = null
  instance = null
  super.onDestroy()
 }

 override fun onBind(intent: Intent?) = null
}
