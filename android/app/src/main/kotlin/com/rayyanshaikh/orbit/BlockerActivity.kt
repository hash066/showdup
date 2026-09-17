package com.rayyanshaikh.orbit

import android.animation.ValueAnimator
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.window.OnBackInvokedDispatcher
import org.json.JSONArray
import org.json.JSONObject

/**
 * The Caught screen. It shows when a held app opens during an alarm window:
 * what the promise is, how often you reached for the app, and two ways out.
 * It never imitates the held app.
 */
class BlockerActivity : Activity() {
    companion object {
        const val EXTRA_PACKAGE = "blocked_package"
        const val EXTRA_ATTEMPT = "attempt_id"
        private const val HOLD_MS = 1_200L
    }

    private var holdAnimator: ValueAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Brand.ink
        window.navigationBarColor = Brand.ink
        render()
        if (Build.VERSION.SDK_INT >= 33) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) { goHome() }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render()
    }

    override fun onResume() {
        super.onResume()
        val held = intent.getStringExtra(EXTRA_PACKAGE)
        if (held == null || !AppBlocker.isBlocked(this, held)) finish()
    }

    @Deprecated("Handled by OnBackInvokedDispatcher on Android 13 and later.")
    override fun onBackPressed() = goHome()

    /** Back goes home, not into the held app, which would only catch again. */
    private fun goHome() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }

    private fun render() {
        val attemptId = intent.getStringExtra(EXTRA_ATTEMPT)
        val held = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()
        val appName = AppBlocker.appLabels(this, listOf(held))[held] ?: "This app"
        val title = attemptId?.let { promiseTitle(it) } ?: "your alarm"
        val reason = attemptId?.let { promiseReason(it) }
        val reaches = attemptId?.let { AppBlocker.reachesFor(this, it) } ?: 0

        val root = FrameLayout(this).apply { setBackgroundColor(Brand.ink) }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val side = Brand.dp(context, 24)
            setPadding(side, Brand.dp(context, 32), side, Brand.dp(context, 24))
        }
        root.setOnApplyWindowInsetsListener { view, insets ->
            @Suppress("DEPRECATION")
            view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            insets
        }

        column.addView(View(this), LinearLayout.LayoutParams(0, 0, 1f))
        column.addView(MarkView(this, ringing = true), LinearLayout.LayoutParams(Brand.dp(this, 88), Brand.dp(this, 88)))
        column.addView(text("Caught.", 44f, Brand.paper, Brand.bold(this)).apply { setPadding(0, Brand.dp(context, 28), 0, 0) })
        column.addView(text("$appName opens when you show up for $title.", 18f, Brand.stone, Brand.medium(this)).apply {
            setPadding(0, Brand.dp(context, 8), 0, 0)
        })
        if (!reason.isNullOrBlank()) {
            column.addView(text("“$reason”", 18f, Brand.paper, Brand.medium(this)).apply {
                setPadding(0, Brand.dp(context, 16), 0, 0)
                setTypeface(typeface, android.graphics.Typeface.ITALIC)
            })
        }
        if (reaches > 0) {
            column.addView(text(reaches.toString(), 72f, Brand.accent, Brand.display(this)).apply {
                setPadding(0, Brand.dp(context, 28), 0, 0)
                includeFontPadding = false
            })
            column.addView(text(if (reaches == 1) "reach today" else "reaches today", 15f, Brand.stone, Brand.medium(this)))
        }
        column.addView(View(this), LinearLayout.LayoutParams(0, 0, 1.4f))

        column.addView(button("Open ShowdUp", filled = true) { openAttempt(attemptId) }, buttonParams())
        column.addView(holdToEnd(attemptId), buttonParams().apply { topMargin = Brand.dp(this@BlockerActivity, 12) })
        column.addView(text("Accessibility settings", 14f, Brand.stone, Brand.medium(this)).apply {
            gravity = Gravity.CENTER
            minHeight = Brand.dp(context, 48)
            setOnClickListener { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); finish() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = Brand.dp(this@BlockerActivity, 8) })

        root.addView(column, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        setContentView(root)
    }

    private fun promiseCommitment(attemptId: String): JSONObject? {
        val commitmentId = attemptId.substringBeforeLast('_')
        return try {
            val list = JSONArray(AlarmEngine.prefs(this).getString("commitments", "[]"))
            (0 until list.length()).map(list::getJSONObject).firstOrNull { it.optString("id") == commitmentId }
        } catch (_: Exception) { null }
    }

    private fun promiseTitle(attemptId: String): String? {
        val fromAlarm = AlarmEngine.prefs(this).getString("alarm:$attemptId", null)?.let {
            try { JSONObject(it).optString("title") } catch (_: Exception) { null }
        }
        val title = fromAlarm?.takeIf { it.isNotBlank() } ?: promiseCommitment(attemptId)?.optString("title")
        return title?.takeIf { it.isNotBlank() }?.replaceFirstChar { it.lowercase() }
    }

    private fun promiseReason(attemptId: String) = promiseCommitment(attemptId)?.optString("reason")

    private fun openAttempt(attemptId: String?) {
        startActivity(Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (attemptId != null) putExtra("attemptId", attemptId)
        })
        finish()
    }

    private fun endToday(attemptId: String?) {
        if (attemptId != null) AlarmEngine.endByUser(this, attemptId)
        goHome()
    }

    private fun text(value: String, size: Float, color: Int, face: android.graphics.Typeface) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(color)
        typeface = face
        setLineSpacing(0f, 1.15f)
    }

    private fun buttonParams() = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, Brand.dp(this, 56))

    private fun pill(fill: Int, stroke: Int?) = GradientDrawable().apply {
        setColor(fill)
        cornerRadius = Brand.dp(this@BlockerActivity, 16f)
        if (stroke != null) setStroke(Brand.dp(this@BlockerActivity, 1), stroke)
    }

    private fun button(label: String, filled: Boolean, onClick: () -> Unit) = text(label, 17f, if (filled) Brand.ink else Brand.paper, Brand.bold(this)).apply {
        gravity = Gravity.CENTER
        background = if (filled) pill(Brand.accent, null) else pill(Brand.ink, Brand.graphiteStrong)
        setOnClickListener { onClick() }
    }

    /**
     * Press and hold to end today. With TalkBack on, a tap opens a confirmation
     * instead, since a long hold is hard to perform.
     */
    private fun holdToEnd(attemptId: String?): View {
        val frame = FrameLayout(this).apply { background = pill(Brand.ink, Brand.graphiteStrong); clipToOutline = true }
        val fill = View(this).apply { background = pill(Brand.graphite, null); pivotX = 0f; scaleX = 0f }
        val label = text("Hold to end today", 17f, Brand.paper, Brand.medium(this)).apply { gravity = Gravity.CENTER }
        frame.addView(fill, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        frame.addView(label, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        frame.contentDescription = "End today"

        val accessibility = getSystemService(AccessibilityManager::class.java)
        if (accessibility?.isTouchExplorationEnabled == true) {
            frame.setOnClickListener {
                AlertDialog.Builder(this)
                    .setTitle("End today?")
                    .setMessage("Reminders stop and the app opens again. No points today.")
                    .setNegativeButton("Keep going", null)
                    .setPositiveButton("End today") { _, _ -> endToday(attemptId) }
                    .show()
            }
            return frame
        }
        frame.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    view.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
                    label.text = "Keep holding…"
                    holdAnimator?.cancel()
                    holdAnimator = ValueAnimator.ofFloat(fill.scaleX, 1f).apply {
                        duration = (HOLD_MS * (1f - fill.scaleX)).toLong().coerceAtLeast(1L)
                        addUpdateListener { fill.scaleX = it.animatedValue as Float }
                        addListener(object : android.animation.AnimatorListenerAdapter() {
                            private var cancelled = false
                            override fun onAnimationCancel(animation: android.animation.Animator) { cancelled = true }
                            override fun onAnimationEnd(animation: android.animation.Animator) {
                                if (cancelled) return
                                view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                                endToday(attemptId)
                            }
                        })
                        start()
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (fill.scaleX < 1f) {
                        holdAnimator?.cancel()
                        label.text = "Hold to end today"
                        holdAnimator = ValueAnimator.ofFloat(fill.scaleX, 0f).apply {
                            duration = 200
                            addUpdateListener { fill.scaleX = it.animatedValue as Float }
                            start()
                        }
                    }
                    if (event.actionMasked == MotionEvent.ACTION_UP) view.performClick()
                    true
                }
                else -> false
            }
        }
        return frame
    }

    override fun onDestroy() {
        holdAnimator?.cancel()
        super.onDestroy()
    }
}
