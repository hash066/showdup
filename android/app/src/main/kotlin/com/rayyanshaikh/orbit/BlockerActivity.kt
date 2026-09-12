package com.rayyanshaikh.orbit

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Plain, honest interruption screen; it never impersonates the blocked app. */
class BlockerActivity : Activity() {
    companion object { const val EXTRA_PACKAGE = "blocked_package" }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "ShowdUp focus block"
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(56, 56, 56, 56) }
        column.addView(TextView(this).apply { text = "This app is blocked until your current commitment is completed or its time window ends.\n\nShowdUp excludes Android Settings, your default dialer, and recognized emergency apps. You can disable Accessibility access below at any time."; textSize = 20f; gravity = Gravity.CENTER })
        column.addView(Button(this).apply { text = "Return to ShowdUp"; setOnClickListener { packageManager.getLaunchIntentForPackage(this@BlockerActivity.packageName)?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)) }; finish() } })
        column.addView(Button(this).apply { text = "Accessibility settings"; setOnClickListener { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); finish() } })
        setContentView(column)
    }

    override fun onResume() { super.onResume(); if (!AppBlocker.isEntitled(this) || !AppBlocker.isActive(this)) finish() }
}
