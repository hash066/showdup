package com.rayyanshaikh.orbit

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

object NativeEvidenceGate {
    suspend fun completeBeforeAlarm(context: Context, attemptId: String): Boolean {
        val raw = AlarmEngine.prefs(context).getString("alarm:$attemptId", null) ?: return true
        val alarm = JSONObject(raw)
        val type = alarm.optString("verifierType")
        val result = when (type) {
            "health_workout" -> HealthConnectBridge.checkWorkout(
                context,
                mapOf(
                    "startEpochMs" to alarm.getLong("startEpochMs"),
                    "endEpochMs" to alarm.getLong("endEpochMs"),
                    "targetDurationMs" to alarm.getJSONObject("verifierConfig").getLong("targetDurationMs"),
                    "activityType" to alarm.getJSONObject("verifierConfig").optString("activityType", "any"),
                ),
            )
            "leetcode" -> checkLeetCode(alarm)
            else -> return false
        }
        if (result["permissionDenied"] == true || result["unavailable"] == true) {
            recordFailure(context, attemptId, type, "verification_permission_unavailable")
            return true
        }
        if (type == "leetcode" && result["available"] != true) {
            val key = "verifier_error:$attemptId"
            val failures = AlarmEngine.prefs(context).getInt(key, 0) + 1
            AlarmEngine.prefs(context).edit().putInt(key, failures).apply()
            if (failures >= 3) {
                recordFailure(context, attemptId, type, "leetcode_public_service_unavailable")
                return true
            }
            return false
        }
        if (type == "leetcode") AlarmEngine.prefs(context).edit().remove("verifier_error:$attemptId").apply()
        if (result["satisfied"] != true) return false
        val payload = JSONObject()
            .put("schemaVersion", 1)
            .put("verifier", type)
            .put("source", result["sourcePackage"] ?: if (type == "leetcode") "leetcode_public_profile" else "health_connect")
            .put("capturedAt", System.currentTimeMillis())
        result.forEach { (key, value) -> if (value != null) payload.put(key, value) }
        AlarmEngine.prefs(context).edit().putString(
            "completion:$attemptId",
            JSONObject().put("type", type).put("payload", payload)
                .put("completedAt", System.currentTimeMillis()).toString(),
        ).apply()
        AlarmEngine.cancel(context, attemptId)
        return true
    }

    private fun recordFailure(context: Context, attemptId: String, type: String, reason: String) {
        AlarmEngine.prefs(context).edit().putString(
            "failure:$attemptId",
            JSONObject().put("type", type).put("reason", reason)
                .put("failedAt", System.currentTimeMillis()).toString(),
        ).apply()
        AlarmEngine.cancel(context, attemptId)
    }

    private fun checkLeetCode(alarm: JSONObject): Map<String, Any?> {
        val config = alarm.getJSONObject("verifierConfig")
        val username = config.getString("username")
        val target = config.optInt("targetAccepted", 1)
        val query = """query recentAcSubmissions(${ '$' }username: String!, ${ '$' }limit: Int!) { recentAcSubmissionList(username: ${ '$' }username, limit: ${ '$' }limit) { id titleSlug timestamp } }"""
        val body = JSONObject().put("query", query)
            .put("variables", JSONObject().put("username", username).put("limit", 40))
            .toString().toByteArray(StandardCharsets.UTF_8)
        val connection = (URL("https://leetcode.com/graphql/").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 12_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("User-Agent", "ShowdUp/1.0 public-profile-check")
            setRequestProperty("Referer", "https://leetcode.com/")
        }
        return try {
            connection.outputStream.use { it.write(body) }
            if (connection.responseCode != 200) return emptyMap()
            val response = connection.inputStream.bufferedReader().use { it.readText() }
            val list = JSONObject(response).optJSONObject("data")
                ?.optJSONArray("recentAcSubmissionList") ?: return emptyMap()
            val start = alarm.getLong("startEpochMs") / 1000
            val end = alarm.getLong("endEpochMs") / 1000
            val slugs = linkedSetOf<String>()
            for (i in 0 until list.length()) {
                val item = list.getJSONObject(i)
                val timestamp = item.optString("timestamp").toLongOrNull() ?: continue
                if (timestamp in start..end) slugs += item.optString("titleSlug")
            }
            mapOf(
                "available" to true,
                "satisfied" to (slugs.size >= target),
                "username" to username,
                "acceptedCount" to slugs.size,
                "problemSlugs" to slugs.toList(),
            )
        } catch (_: Exception) { emptyMap() } finally { connection.disconnect() }
    }
}
