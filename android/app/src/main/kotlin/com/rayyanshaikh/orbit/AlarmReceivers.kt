package com.rayyanshaikh.orbit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.*

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val attemptId = intent.getStringExtra("attemptId") ?: return
        if (intent.action == "showdup.snooze") {
            AlarmEngine.silence(context, attemptId, true, "manual")
        } else {
            val index = intent.getIntExtra("index", 0)
            val raw = AlarmEngine.prefs(context).getString("alarm:$attemptId", null)
            val type = raw?.let { runCatching { org.json.JSONObject(it).optString("verifierType") }.getOrNull() }
            if (type == "health_workout" || type == "leetcode") {
                val pending = goAsync()
                CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
                    try {
                        if (!NativeEvidenceGate.completeBeforeAlarm(context, attemptId)) {
                            withContext(Dispatchers.Main) { AlarmEngine.fire(context, attemptId, index) }
                        }
                    } finally { pending.finish() }
                }
            } else AlarmEngine.fire(context, attemptId, index)
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AlarmEngine.restore(context)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            OverlayService.showRestoreNotification(context)
        }
    }
}
