package com.rayyanshaikh.orbit

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctions
import org.json.JSONObject

/**
 * Firebase for native entry points (alarms, boot, the tracking service) that can run in a cold
 * process with no Flutter engine. Every callable enforces App Check, so a provider must be
 * installed here too, or native calls are rejected in production.
 */
object Backend {
    @Volatile
    private var configured = false

    /** Returns false when the app has not been configured yet or the stored config is invalid. */
    @Synchronized
    fun initialize(context: Context): Boolean {
        if (configured) return true
        val raw = AlarmEngine.prefs(context).getString("backend", null) ?: return false
        return try {
            val config = JSONObject(raw)
            val emulators = config.optBoolean("emulators")
            if (FirebaseApp.getApps(context).isEmpty()) {
                FirebaseApp.initializeApp(
                    context,
                    FirebaseOptions.Builder()
                        .setApiKey(config.getString("apiKey"))
                        .setApplicationId(config.getString("appId"))
                        .setProjectId(config.getString("projectId"))
                        .setGcmSenderId(config.getString("senderId"))
                        .build(),
                )
                if (emulators) {
                    val host = config.optString("host", "10.0.2.2")
                    FirebaseAuth.getInstance().useEmulator(host, 9099)
                    FirebaseFirestore.getInstance().useEmulator(host, 8080)
                    FirebaseFunctions.getInstance().useEmulator(host, 5001)
                }
            }
            // Debug factory lives only in the debug source set / dependency.
            AppCheckInstall.install(context, emulators)
            configured = true
            true
        } catch (_: Exception) {
            // Receivers must never crash on a bad config; callers keep work queued instead.
            false
        }
    }
}
