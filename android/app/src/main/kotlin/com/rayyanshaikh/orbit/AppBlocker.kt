package com.rayyanshaikh.orbit

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray
import org.json.JSONObject

/**
 * A deliberately small accessibility service used only to return from apps the
 * user explicitly selected for an active Pro commitment. It does not read view
 * contents, record input, inject gestures, or request key-event filtering.
 */
class AppBlockerService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val focusTicker = object : Runnable {
        override fun run() {
            FocusTracker.tick(this@AppBlockerService)
            handler.postDelayed(this, 1_000)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 150
            flags = 0
        }
        instance = this
        handler.removeCallbacks(focusTicker)
        handler.post(focusTicker)
    }

    private var lastCaughtPackage = ""
    private var lastCaughtAt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString() ?: return
        FocusTracker.onPackageChanged(this, packageName)
        val attemptId = AppBlocker.holdingAttempt(this, packageName)
            ?: FocusTracker.holdingAttempt(this, packageName)
            ?: return
        // One open can raise several window events. React, and count the reach,
        // once per open instead of once per event. The window stays short so a
        // deliberate second open is still caught.
        if (CaughtFlash.showing()) return
        val now = System.currentTimeMillis()
        if (packageName == lastCaughtPackage && now - lastCaughtAt < REACH_DEBOUNCE_MS) return
        lastCaughtPackage = packageName
        lastCaughtAt = now
        AppBlocker.recordReach(this, attemptId, packageName)

        // The full screen explains the rule the first time. After that a small
        // flash says caught and Android goes home.
        if (CaughtFlash.show(this, packageName, attemptId)) return
        CaughtFlash.markExplained(this, attemptId)
        startActivity(Intent(this, BlockerActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(BlockerActivity.EXTRA_PACKAGE, packageName)
            putExtra(BlockerActivity.EXTRA_ATTEMPT, attemptId)
        })
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        handler.removeCallbacks(focusTicker)
        CaughtFlash.dismiss(null)
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        var instance: AppBlockerService? = null
        private const val REACH_DEBOUNCE_MS = 1_200L
    }
}

object AppBlocker {
    private const val PREFS = "showdup_blocker"
    private const val KEY_SESSIONS = "sessions"
    private const val KEY_PRO = "pro"
    private const val KEY_PRO_EXPIRES = "pro_expires"
    private const val KEY_FREE_CATCH = "free_catch"
    private const val KEY_REACHES = "reaches"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun configure(context: Context, packages: List<String>, untilEpochMs: Long, commitmentId: String?, attemptId: String?, activeFromEpochMs: Long = System.currentTimeMillis()): Boolean {
        val retained = sessions(context)
            .filter { it.optLong("until") > System.currentTimeMillis() && it.optString("attemptId") != attemptId }
            .map { session ->
                val values = session.optJSONArray("packages") ?: JSONArray()
                mapOf(
                    "packages" to (0 until values.length()).map(values::getString),
                    "activeFromEpochMs" to session.optLong("from", 0L),
                    "activeUntilEpochMs" to session.optLong("until"),
                    "commitmentId" to session.optString("commitmentId"),
                    "attemptId" to session.optString("attemptId"),
                )
            }
        return sync(context, retained + mapOf("packages" to packages, "activeFromEpochMs" to activeFromEpochMs, "activeUntilEpochMs" to untilEpochMs, "commitmentId" to commitmentId, "attemptId" to attemptId))
    }

    /** Losing Pro no longer clears holds: [CatchPolicy] clamps what stays held. */
    fun setEntitlement(context: Context, enabled: Boolean, expiresAtEpochMs: Long?, freeCatch: Boolean = false) {
        prefs(context).edit().putBoolean(KEY_PRO, enabled)
            .putLong(KEY_PRO_EXPIRES, expiresAtEpochMs ?: 0L)
            .putBoolean(KEY_FREE_CATCH, freeCatch).apply()
        if (!isEntitled(context) && !freeCatch) stop(context)
    }

    fun freeCatch(context: Context): Boolean = prefs(context).getBoolean(KEY_FREE_CATCH, false)

    /** Whether any hold can apply for this person: Pro, or the free catch. */
    fun canHold(context: Context): Boolean = isEntitled(context) || freeCatch(context)

    fun isEntitled(context: Context): Boolean {
        if (!prefs(context).getBoolean(KEY_PRO, false)) return false
        val expiry = prefs(context).getLong(KEY_PRO_EXPIRES, 0L)
        return expiry > System.currentTimeMillis()
    }

    /** Replaces the full session set in one preference write, so overlapping Pro commitments union safely. */
    fun sync(context: Context, sessions: List<Map<*, *>>): Boolean {
        val now = System.currentTimeMillis()
        val stored = JSONArray()
        sessions.forEach { session ->
            val from = (session["activeFromEpochMs"] as? Number)?.toLong() ?: 0L
            val until = (session["activeUntilEpochMs"] as? Number)?.toLong() ?: 0
            val attemptId = session["attemptId"]?.toString()?.trim().orEmpty()
            val packages = (session["packages"] as? List<*>)?.mapNotNull { it?.toString()?.trim() }
                ?.filter { it.isNotEmpty() && !isSafetyExempt(context, it) }?.distinct().orEmpty()
            if (until > now && attemptId.isNotEmpty() && packages.isNotEmpty()) {
                stored.put(org.json.JSONObject().put("attemptId", attemptId).put("commitmentId", session["commitmentId"]?.toString()).put("from", from).put("until", until).put("packages", JSONArray(packages)))
            }
        }
        prefs(context).edit().putString(KEY_SESSIONS, stored.toString()).apply()
        return stored.length() > 0
    }

    fun stop(context: Context, attemptId: String? = null) {
        if (attemptId == null) { prefs(context).edit().remove(KEY_SESSIONS).apply(); return }
        val kept = sessions(context).filter { it.optString("attemptId") != attemptId }
        prefs(context).edit().putString(KEY_SESSIONS, JSONArray(kept).toString()).apply()
    }

    fun isActive(context: Context): Boolean {
        val now = System.currentTimeMillis()
        val valid = sessions(context).filter { it.optLong("until") > now }
        if (valid.size != sessions(context).size) prefs(context).edit().putString(KEY_SESSIONS, JSONArray(valid).toString()).apply()
        return valid.any { it.optLong("from", 0L) <= now }
    }

    fun isBlocked(context: Context, packageName: String): Boolean =
        holdingAttempt(context, packageName) != null || FocusTracker.holdingAttempt(context, packageName) != null

    /** The attempt holding [packageName] right now, or null when it is free to open. */
    fun holdingAttempt(context: Context, packageName: String): String? {
        if (!isActive(context) || isSafetyExempt(context, packageName)) return null
        return CatchPolicy.holdingAttempt(catchSessions(context), packageName, isEntitled(context), freeCatch(context), System.currentTimeMillis())
    }

    private fun catchSessions(context: Context): List<CatchSession> = sessions(context).map { session ->
        val values = session.optJSONArray("packages") ?: JSONArray()
        CatchSession(
            attemptId = session.optString("attemptId"),
            from = session.optLong("from", 0L),
            until = session.optLong("until"),
            packages = (0 until values.length()).map(values::getString),
        )
    }

    /** Counts a reach per attempt. Entries older than a week are dropped. */
    fun recordReach(context: Context, attemptId: String, packageName: String) {
        val now = System.currentTimeMillis()
        val all = try { JSONObject(prefs(context).getString(KEY_REACHES, "{}")) } catch (_: Exception) { JSONObject() }
        val kept = JSONObject()
        all.keys().forEach { key ->
            val entry = all.optJSONObject(key) ?: return@forEach
            if (now - entry.optLong("at") < 7 * 86_400_000L) kept.put(key, entry)
        }
        val entry = kept.optJSONObject(attemptId) ?: JSONObject()
        kept.put(attemptId, entry.put("count", entry.optInt("count") + 1).put("at", now).put("package", packageName))
        prefs(context).edit().putString(KEY_REACHES, kept.toString()).apply()
    }

    fun reaches(context: Context): Map<String, Int> {
        val all = try { JSONObject(prefs(context).getString(KEY_REACHES, "{}")) } catch (_: Exception) { return emptyMap() }
        return all.keys().asSequence().associateWith { all.optJSONObject(it)?.optInt("count") ?: 0 }
    }

    fun reachesFor(context: Context, attemptId: String): Int = reaches(context)[attemptId] ?: 0

    fun appLabels(context: Context, packages: List<String>): Map<String, String> = packages.mapNotNull { name ->
        try {
            val info = context.packageManager.getApplicationInfo(name, 0)
            name to context.packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) { null }
    }.toMap()

    fun openApp(context: Context, packageName: String): Boolean {
        val launch = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    fun status(context: Context): Map<String, Any> {
        return mapOf(
            "accessibilityEnabled" to accessibilityEnabled(context),
            "active" to isActive(context),
            "quickCatch" to CaughtFlash.enabled(context),
        )
    }

    private fun sessions(context: Context): List<org.json.JSONObject> = try {
        val values = JSONArray(prefs(context).getString(KEY_SESSIONS, "[]"))
        (0 until values.length()).map { values.getJSONObject(it) }
    } catch (_: Exception) { emptyList() }

    fun launchableApps(context: Context): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return context.packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            .map { info -> mapOf("packageName" to info.activityInfo.packageName, "label" to info.loadLabel(context.packageManager).toString()) }
            .filter { !isSafetyExempt(context, it.getValue("packageName")) }
            .distinctBy { it.getValue("packageName") }
            .sortedBy { it.getValue("label").lowercase() }
    }

    fun openAccessibilitySettings(context: Context) {
        context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun accessibilityEnabled(context: Context): Boolean {
        val expected = ComponentName(context, AppBlockerService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    /** Never block the app itself, calls/emergency, or Android settings/permission surfaces. */
    fun isSafetyExempt(context: Context, packageName: String): Boolean {
        if (packageName == context.packageName || packageName == "android" || packageName == "com.android.systemui") return true
        if (packageName.startsWith("com.android.settings") || packageName.contains("permissioncontroller")) return true
        // Calls and emergency flows are safety-critical. These conservative
        // exclusions intentionally include common AOSP/Google/Samsung surfaces.
        if (packageName == "com.android.phone" || packageName == "com.android.server.telecom" ||
            packageName.contains("incall", ignoreCase = true) || packageName.contains("telecom", ignoreCase = true) ||
            packageName == "com.google.android.dialer") return true
        val dialer = try { context.packageManager.resolveActivity(Intent(Intent.ACTION_DIAL), PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName } catch (_: Exception) { null }
        if (packageName == dialer) return true
        return packageName.contains("emergency", ignoreCase = true)
    }
}

/**
 * Local-only Focus evidence. It stores package names and timing, never window
 * content. A selected app must stay foreground for ten seconds before the
 * uninterrupted clean timer is reset.
 */
object FocusTracker {
    private const val PREFS = "showdup_focus"
    private const val KEY_SESSIONS = "sessions"
    private var foregroundPackage: String? = null

    /** The app in front, as the accessibility service last saw it. */
    val currentPackage: String? get() = foregroundPackage

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun sessions(context: Context): MutableList<JSONObject> = try {
        val values = JSONArray(prefs(context).getString(KEY_SESSIONS, "[]"))
        (0 until values.length()).map { values.getJSONObject(it) }.toMutableList()
    } catch (_: Exception) { mutableListOf() }

    private fun save(context: Context, sessions: List<JSONObject>) {
        prefs(context).edit().putString(KEY_SESSIONS, JSONArray(sessions).toString()).apply()
    }

    fun start(context: Context, args: Map<*, *>): Boolean {
        if (AppBlocker.status(context)["accessibilityEnabled"] != true) return false
        val id = args["attemptId"]?.toString()?.trim().orEmpty()
        val packages = (args["packages"] as? List<*>)?.mapNotNull { it?.toString() }
            ?.filter { it.isNotBlank() && !AppBlocker.isSafetyExempt(context, it) }
            ?.distinct().orEmpty()
        val start = (args["startEpochMs"] as? Number)?.toLong() ?: return false
        val end = (args["endEpochMs"] as? Number)?.toLong() ?: return false
        val target = (args["targetDurationMs"] as? Number)?.toLong() ?: return false
        val grace = ((args["graceSeconds"] as? Number)?.toLong() ?: 10L) * 1_000
        if (id.isEmpty() || packages.isEmpty() || end <= start || target < 300_000 || grace != 10_000L) return false
        val stored = sessions(context)
        if (stored.any { it.optString("attemptId") == id }) { tick(context); return true }
        val current = stored.toMutableList()
        val now = System.currentTimeMillis()
        prefs(context).edit().remove("result:$id").apply()
        current += JSONObject()
            .put("attemptId", id)
            .put("packages", JSONArray(packages))
            .put("start", start)
            .put("end", end)
            .put("target", target)
            .put("grace", grace)
            .put("cleanSince", maxOf(start, now))
            .put("resetCount", 0)
        save(context, current)
        AlarmEngine.focusStarted(context, id)
        onPackageChanged(context, foregroundPackage)
        tick(context)
        return true
    }

    fun stop(context: Context, attemptId: String, clearResult: Boolean = true) {
        save(context, sessions(context).filter { it.optString("attemptId") != attemptId })
        if (clearResult) prefs(context).edit().remove("result:$attemptId").apply()
    }

    /**
     * The focus attempt keeping [packageName] closed right now, or null. While
     * a phone-down session runs, the apps it names are caught like held apps,
     * so the timer is protected instead of merely reset.
     */
    fun holdingAttempt(context: Context, packageName: String): String? {
        if (AppBlocker.isSafetyExempt(context, packageName)) return null
        val now = System.currentTimeMillis()
        return sessions(context).firstOrNull { session ->
            val packages = session.optJSONArray("packages") ?: JSONArray()
            session.optLong("start") <= now && now < session.optLong("end") &&
                (0 until packages.length()).any { packages.getString(it) == packageName }
        }?.optString("attemptId")?.takeIf { it.isNotEmpty() }
    }

    /** A phone-down session is running for [attemptId] and nothing broke it. */
    fun running(context: Context, attemptId: String): Boolean {
        val now = System.currentTimeMillis()
        val session = sessions(context).firstOrNull { it.optString("attemptId") == attemptId } ?: return false
        return session.optLong("start") <= now && now < session.optLong("end") &&
            !session.optBoolean("resetApplied", false)
    }

    fun onPackageChanged(context: Context, packageName: String?) {
        val previous = foregroundPackage
        foregroundPackage = packageName
        if (previous == packageName) return
        val now = System.currentTimeMillis()
        val values = sessions(context)
        values.forEach { session ->
            val packages = session.optJSONArray("packages") ?: JSONArray()
            val selected = packageName != null &&
                (0 until packages.length()).any { packages.getString(it) == packageName }
            if (selected) {
                session.put("distractingSince", now).put("resetApplied", false)
            } else if (session.has("distractingSince")) {
                if (session.optBoolean("resetApplied", false)) session.put("cleanSince", now)
                session.remove("distractingSince")
                session.remove("resetApplied")
            }
        }
        save(context, values)
    }

    fun tick(context: Context) {
        val now = System.currentTimeMillis()
        val values = sessions(context)
        val kept = mutableListOf<JSONObject>()
        values.forEach { session ->
            val id = session.optString("attemptId")
            if (now >= session.optLong("end")) return@forEach
            if (now < session.optLong("start")) { kept += session; return@forEach }
            val distractingSince = session.optLong("distractingSince", 0L)
            if (FocusPolicy.shouldReset(
                    distractingSince,
                    now,
                    session.optBoolean("resetApplied", false),
                    session.optLong("grace", FocusPolicy.GRACE_MS),
                )) {
                session.put("resetApplied", true)
                    .put("cleanSince", now)
                    .put("resetCount", session.optInt("resetCount", 0) + 1)
            }
            val distracted = session.optBoolean("resetApplied", false)
            val elapsed = if (distracted) 0L else (now - session.optLong("cleanSince", now)).coerceAtLeast(0L)
            if (elapsed >= session.optLong("target")) {
                val payload = JSONObject()
                    .put("schemaVersion", 1)
                    .put("verifier", "focus")
                    .put("source", "android_accessibility_window_events")
                    .put("targetDurationMs", session.optLong("target"))
                    .put("resetCount", session.optInt("resetCount", 0))
                AlarmEngine.prefs(context).edit().putString(
                    "completion:$id",
                    JSONObject().put("type", "focus").put("payload", payload)
                        .put("completedAt", now).toString(),
                ).apply()
                prefs(context).edit().putString(
                    "result:$id",
                    JSONObject().put("completed", true).put("resetCount", session.optInt("resetCount", 0)).toString(),
                ).apply()
                AlarmEngine.cancel(context, id)
            } else kept += session
        }
        save(context, kept)
    }

    fun status(context: Context, attemptId: String): Map<String, Any> {
        tick(context)
        val result = prefs(context).getString("result:$attemptId", null)
        if (result != null) {
            val value = JSONObject(result)
            return mapOf("completed" to value.optBoolean("completed"), "progress" to 1.0, "resetCount" to value.optInt("resetCount"))
        }
        val session = sessions(context).firstOrNull { it.optString("attemptId") == attemptId }
            ?: return mapOf("completed" to false, "progress" to 0.0, "failed" to (AppBlocker.status(context)["accessibilityEnabled"] != true))
        val now = System.currentTimeMillis()
        return mapOf(
            "completed" to false,
            "progress" to FocusPolicy.progress(session.optLong("cleanSince", now), now, session.optLong("target"), session.optBoolean("resetApplied", false)),
            "resetCount" to session.optInt("resetCount", 0),
            "failed" to (AppBlocker.status(context)["accessibilityEnabled"] != true),
        )
    }
}
