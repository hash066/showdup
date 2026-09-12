package com.rayyanshaikh.orbit

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray

/**
 * A deliberately small accessibility service used only to return from apps the
 * user explicitly selected for an active Pro commitment. It does not read view
 * contents, record input, inject gestures, or request key-event filtering.
 */
class AppBlockerService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 150
            flags = 0
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString() ?: return
        if (!AppBlocker.isBlocked(this, packageName)) return

        startActivity(Intent(this, BlockerActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(BlockerActivity.EXTRA_PACKAGE, packageName)
        })
    }

    override fun onInterrupt() = Unit
}

object AppBlocker {
    private const val PREFS = "showdup_blocker"
    private const val KEY_SESSIONS = "sessions"
    private const val KEY_PRO = "pro"
    private const val KEY_PRO_EXPIRES = "pro_expires"

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

    fun setEntitlement(context: Context, enabled: Boolean, expiresAtEpochMs: Long?) {
        prefs(context).edit().putBoolean(KEY_PRO, enabled)
            .putLong(KEY_PRO_EXPIRES, expiresAtEpochMs ?: 0L).apply()
        if (!isEntitled(context)) stop(context)
    }

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
        if (attemptId == null) { prefs(context).edit().clear().apply(); return }
        val kept = sessions(context).filter { it.optString("attemptId") != attemptId }
        prefs(context).edit().putString(KEY_SESSIONS, JSONArray(kept).toString()).apply()
    }

    fun isActive(context: Context): Boolean {
        val now = System.currentTimeMillis()
        val valid = sessions(context).filter { it.optLong("until") > now }
        if (valid.size != sessions(context).size) prefs(context).edit().putString(KEY_SESSIONS, JSONArray(valid).toString()).apply()
        return valid.any { it.optLong("from", 0L) <= now }
    }

    fun isBlocked(context: Context, packageName: String): Boolean {
        if (!isEntitled(context) || !isActive(context) || isSafetyExempt(context, packageName)) return false
        return sessions(context).any { session ->
            session.optLong("from", 0L) <= System.currentTimeMillis() && session.optLong("until") > System.currentTimeMillis() && session.optJSONArray("packages")?.let { values -> (0 until values.length()).any { values.getString(it) == packageName } } == true
        }
    }

    fun status(context: Context): Map<String, Any> {
        return mapOf(
            "accessibilityEnabled" to accessibilityEnabled(context),
            "active" to isActive(context),
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
