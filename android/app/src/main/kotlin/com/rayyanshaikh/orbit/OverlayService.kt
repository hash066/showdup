package com.rayyanshaikh.orbit

import android.app.*
import android.content.*
import android.graphics.BitmapFactory
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
    .setColor(Brand.accent)
    .setContentTitle("Bring your companion back")
    .setContentText("Tap to show the bubble again after the restart.")
    .setContentIntent(launch).setAutoCancel(true).build()
   c.getSystemService(NotificationManager::class.java).notify(ID + 1, n)
  }
  private fun ensureChannel(c: Context) {
   c.getSystemService(NotificationManager::class.java).createNotificationChannel(
    NotificationChannel(CHANNEL, "Companion bubble", NotificationManager.IMPORTANCE_LOW).apply {
     description = "Keeps your companion and next alarm over other apps while the bubble is on"
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
   .setColor(Brand.accent)
   .setContentTitle("Companion bubble is on")
   .setContentText("Tap to open ShowdUp. Turn the bubble off any time.")
   .setContentIntent(open).setOngoing(true)
   .addAction(0, "Turn off", stop).build()
  startForeground(ID, notification)
 }

 private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
 private fun round(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
  setColor(color); cornerRadius = dp(radius).toFloat()
  if (stroke != null) setStroke(dp(1), stroke)
 }
 private fun text(value: String, size: Float, color: Int = Brand.paper, bold: Boolean = false) =
  TextView(this).apply {
   this.text = value; textSize = size; setTextColor(color)
   gravity = Gravity.CENTER_VERTICAL
   typeface = if (bold) Brand.bold(this@OverlayService) else Brand.medium(this@OverlayService)
  }

 /** The companion drawn by Flutter, or the mark when the image is missing. */
 private fun companion(j: JSONObject, size: Int): View {
  val path = j.optString("companionImage")
  val bitmap = if (path.isNotBlank()) try { BitmapFactory.decodeFile(path) } catch (_: Exception) { null } else null
  if (bitmap != null) return ImageView(this).apply { setImageBitmap(bitmap); contentDescription = "Companion" }
  return MarkView(this, ringing = j.optString("activeAttemptId").isNotBlank()).apply { setPadding(dp(size / 8), dp(size / 8), dp(size / 8), dp(size / 8)) }
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
  val active = j.optString("activeAttemptId").isNotBlank()
  val row = LinearLayout(this).apply {
   orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
   setPadding(dp(6), dp(6), dp(14), dp(6))
   background = round(Brand.carbon, 28, if (active) Brand.accent else Brand.graphiteStrong)
   elevation = dp(8).toFloat()
   contentDescription = if (active) "ShowdUp: an alarm is open" else "ShowdUp companion"
  }
  row.addView(companion(j, 40), LinearLayout.LayoutParams(dp(40), dp(40)))
  val label = if (active) "Open now" else "${j.optInt("weeklyScore", 0)}"
  row.addView(text(label, if (active) 15f else 20f, if (active) Brand.accent else Brand.paper, true).apply { setPadding(dp(8), 0, 0, 0) })
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
  val scrim = FrameLayout(this).apply { setBackgroundColor(0xB80E0E0C.toInt()); isClickable = true }
  scrim.setOnClickListener { expanded = false; render() }
  val card = LinearLayout(this).apply {
   orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(18), dp(12), dp(10))
   background = round(Brand.carbon, 28, Brand.graphite); isClickable = true
  }
  val header = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
  header.addView(companion(j, 56), LinearLayout.LayoutParams(dp(56), dp(56)))
  header.addView(LinearLayout(this).apply {
   orientation = LinearLayout.VERTICAL; setPadding(dp(12), 0, 0, 0)
   addView(text("${j.optInt("weeklyScore", 0)} points", 22f, Brand.paper, true))
   addView(text("this week · ${j.optInt("streak", 0)} day streak", 13f, Brand.stone))
  }, LinearLayout.LayoutParams(0, WindowManager.LayoutParams.WRAP_CONTENT, 1f))
  header.addView(text("✕", 20f, Brand.stone).apply {
   gravity = Gravity.CENTER; contentDescription = "Close"
   setOnClickListener { expanded = false; render() }
  }, LinearLayout.LayoutParams(dp(48), dp(48)))
  card.addView(header)

  val activeTitle = j.optString("activeTitle")
  card.addView(text(if (activeTitle.isNotBlank()) activeTitle else "Nothing open right now", 18f, Brand.paper, true).apply { setPadding(0, dp(16), dp(8), dp(2)) })
  card.addView(text("Today ${j.optInt("todayCompleted", 0)} of ${j.optInt("todayTotal", 0)}", 13f, Brand.stone))

  val ranks = j.optJSONArray("topRanks") ?: JSONArray()
  if (ranks.length() > 0) {
   card.addView(text("This week's battle", 13f, Brand.stone).apply { setPadding(0, dp(16), 0, dp(4)) })
   for (i in 0 until min(5, ranks.length())) {
    val rank = ranks.optJSONObject(i) ?: continue
    card.addView(LinearLayout(this).apply {
     orientation = LinearLayout.HORIZONTAL; setPadding(0, dp(6), dp(8), dp(6))
     addView(text("${rank.optInt("rank", i + 1)}", 15f, if (i == 0) Brand.accent else Brand.stone, true), LinearLayout.LayoutParams(dp(28), WindowManager.LayoutParams.WRAP_CONTENT))
     addView(text(rank.optString("name", "Player"), 15f), LinearLayout.LayoutParams(0, WindowManager.LayoutParams.WRAP_CONTENT, 1f))
     addView(text("${rank.optInt("score", 0)}", 15f, Brand.paper, true))
    })
   }
  }

  val actions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.END; setPadding(0, dp(12), 0, 0) }
  fun action(label: String, color: Int, onClick: () -> Unit) = text(label, 15f, color, true).apply {
   gravity = Gravity.CENTER; minHeight = dp(48); setPadding(dp(12), 0, dp(12), 0); setOnClickListener { onClick() }
  }
  actions.addView(action("Turn off", Brand.stone) { disable(this@OverlayService) })
  if (j.optString("activeAttemptId").isNotBlank()) {
   actions.addView(action("Snooze", Brand.paper) { AlarmEngine.silence(this@OverlayService, j.optString("activeAttemptId"), true, "manual") })
  }
  actions.addView(action("Open ShowdUp", Brand.accent) {
   startActivity(Intent(this@OverlayService, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).apply {
    j.optString("activeAttemptId").takeIf { it.isNotBlank() }?.let { putExtra("attemptId", it) }
   })
   expanded = false; render()
  })
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
