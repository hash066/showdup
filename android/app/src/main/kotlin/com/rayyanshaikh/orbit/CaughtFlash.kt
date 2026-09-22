package com.rayyanshaikh.orbit

import android.accessibilityservice.AccessibilityService
import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject

/**
 * The small "Caught." flash. After the full Caught screen has explained the
 * rule once for this attempt, later reaches get this instead: the mark rings
 * at the top of the held app for a moment, then Android goes home.
 *
 * It is an accessibility overlay owned by [AppBlockerService], so it needs no
 * draw-over-other-apps permission and disappears with the service. Tapping it
 * opens ShowdUp on today's proof.
 */
object CaughtFlash {
    private const val PREFS = "showdup_blocker"
    private const val KEY_ENABLED = "flash_enabled"
    private const val KEY_EXPLAINED = "explained"
    private const val DWELL_MS = 1_600L
    private const val IN_MS = 420L
    private const val OUT_MS = 220L

    private val handler = Handler(Looper.getMainLooper())
    private var window: WindowManager? = null
    private var root: View? = null
    private var animators = mutableListOf<ValueAnimator>()

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun enabled(context: Context) = prefs(context).getBoolean(KEY_ENABLED, true)

    /** True while a flash is on screen, so one open is handled once. */
    fun showing() = root != null

    fun setEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, value).apply()
        if (!value) handler.post { dismiss(null) }
    }

    /** The full screen explains the rule once per attempt; after that, flash. */
    fun explained(context: Context, attemptId: String): Boolean =
        prefs(context).getString(KEY_EXPLAINED, null) == attemptId

    fun markExplained(context: Context, attemptId: String) {
        prefs(context).edit().putString(KEY_EXPLAINED, attemptId).apply()
    }

    private fun reduceMotion(context: Context) = try {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    } catch (_: Exception) {
        false
    }

    /**
     * Shows the flash over the held app. Returns false when the flash cannot be
     * used, so the caller falls back to the full Caught screen: with TalkBack
     * on (a tiny auto-dismissing card is a poor target), or when the window
     * manager refuses the overlay.
     */
    fun show(service: AppBlockerService, packageName: String, attemptId: String): Boolean {
        val accessibility = service.getSystemService(AccessibilityManager::class.java)
        val allowed = CatchPolicy.flashInstead(
            attemptId = attemptId,
            explainedAttemptId = prefs(service).getString(KEY_EXPLAINED, null),
            quickCatch = enabled(service),
            touchExploration = accessibility?.isTouchExplorationEnabled == true,
        )
        if (!allowed) return false
        if (root != null) return true

        // An app's own label is whatever its developer wrote, so keep it short
        // and on one line: the flash states the rule, it never quotes an app.
        val app = AppBlocker.appLabels(service, listOf(packageName))[packageName]
            ?.replace('\n', ' ')?.trim()?.take(32)?.ifBlank { null } ?: "That app"
        val title = promiseTitle(service, attemptId)
        val line = when {
            FocusTracker.holdingAttempt(service, packageName) == attemptId -> "$app opens again when your phone-down time is up."
            title == null -> "$app opens when you show up."
            else -> "$app opens when you show up for $title."
        }

        val card = LinearLayout(service).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(Brand.carbon)
                cornerRadius = Brand.dp(service, 26f)
                setStroke(Brand.dp(service, 1), Brand.graphiteStrong)
            }
            elevation = Brand.dp(service, 12f)
            val side = Brand.dp(service, 14)
            setPadding(side, side, side, side)
            clipToOutline = true
            contentDescription = "Caught. $line Tap to open ShowdUp."
            isClickable = true
        }
        val mark = MarkView(service, ringing = true)
        card.addView(mark, LinearLayout.LayoutParams(Brand.dp(service, 34), Brand.dp(service, 34)))

        val column = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            val start = Brand.dp(service, 12)
            setPadding(start, 0, 0, 0)
        }
        column.addView(TextView(service).apply {
            text = "Caught."
            textSize = 17f
            setTextColor(Brand.paper)
            typeface = Brand.bold(service)
        })
        column.addView(TextView(service).apply {
            text = line
            textSize = 13f
            setTextColor(Brand.stone)
            typeface = Brand.medium(service)
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        card.addView(column, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        // A line that runs out while the flash waits, so the exit is expected.
        val timer = View(service).apply {
            background = GradientDrawable().apply { setColor(Brand.accent) }
            pivotX = 0f
        }
        val holder = FrameLayout(service).apply {
            addView(card, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(timer, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, Brand.dp(service, 3), Gravity.BOTTOM).apply {
                val inset = Brand.dp(service, 2)
                setMargins(inset, 0, inset, inset)
            })
            clipChildren = false
        }
        val frame = FrameLayout(service).apply {
            val side = Brand.dp(service, 16)
            setPadding(side, Brand.dp(service, 12), side, 0)
            clipChildren = false
            addView(holder, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }

        card.setOnClickListener {
            dismiss(null)
            Sensory.cue(service, "tap")
            service.startActivity(Intent(service, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("attemptId", attemptId)
            })
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP }

        val manager = service.getSystemService(WindowManager::class.java) ?: return false
        return try {
            manager.addView(frame, params)
            window = manager
            root = frame
            Sensory.cue(service, "caught")
            frame.announceForAccessibility(card.contentDescription)
            // Going home is only right while the held app is still in front.
            // If they already left it, the card just goes away.
            val leave = Runnable {
                dismiss(if (FocusTracker.currentPackage == packageName) service else null)
            }
            if (reduceMotion(service)) {
                handler.postDelayed(leave, DWELL_MS)
            } else {
                animateIn(holder, mark, timer)
                handler.postDelayed(leave, IN_MS + DWELL_MS)
            }
            true
        } catch (_: Exception) {
            // A refused overlay must not swallow the catch: fall back to the screen.
            window = null
            root = null
            false
        }
    }

    private fun animateIn(holder: View, mark: View, timer: View) {
        holder.alpha = 0f
        holder.translationY = -Brand.dp(holder.context, 90f)
        holder.animate().alpha(1f).translationY(0f).setDuration(IN_MS)
            .setInterpolator(android.view.animation.OvershootInterpolator(1.4f)).start()

        val rock = ValueAnimator.ofFloat(0f, 16f, -12f, 6f, 0f).apply {
            duration = 620
            startDelay = 120
            addUpdateListener { mark.rotation = it.animatedValue as Float }
        }
        val run = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = DWELL_MS
            startDelay = IN_MS
            interpolator = android.view.animation.LinearInterpolator()
            addUpdateListener { timer.scaleX = it.animatedValue as Float }
        }
        animators.add(rock)
        animators.add(run)
        rock.start()
        run.start()
    }

    /** Removes the flash. With a [service], the phone also goes home. */
    fun dismiss(service: AccessibilityService?) {
        handler.removeCallbacksAndMessages(null)
        animators.forEach { it.cancel() }
        animators.clear()
        val view = root
        val manager = window
        root = null
        window = null
        if (view != null && manager != null) {
            try { manager.removeView(view) } catch (_: Exception) {}
        }
        if (service != null) {
            try { service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME) } catch (_: Exception) {}
        }
    }

    private fun promiseTitle(context: Context, attemptId: String): String? {
        val raw = AlarmEngine.prefs(context).getString("alarm:$attemptId", null) ?: return null
        return try {
            JSONObject(raw).optString("title").takeIf { it.isNotBlank() }?.replaceFirstChar { it.lowercase() }
        } catch (_: Exception) {
            null
        }
    }
}
