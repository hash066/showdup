package com.rayyanshaikh.orbit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val attemptId = intent.getStringExtra("attemptId") ?: return
        if (intent.action == "showdup.snooze") {
            AlarmEngine.silence(context, attemptId, true, "manual")
        } else {
            AlarmEngine.fire(context, attemptId, intent.getIntExtra("index", 0))
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
