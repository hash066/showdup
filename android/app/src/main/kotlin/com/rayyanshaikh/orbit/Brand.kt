package com.rayyanshaikh.orbit

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View

/** Brand tokens for native surfaces. Mirrors lib/design/tokens.dart. */
object Brand {
    val ink = Color.parseColor("#0E0E0C")
    val carbon = Color.parseColor("#171714")
    val graphite = Color.parseColor("#262622")
    val graphiteStrong = Color.parseColor("#3A3A34")
    val paper = Color.parseColor("#F2EEE6")
    val stone = Color.parseColor("#8F8A80")
    val accent = Color.parseColor("#5CF0BE")

    private val cache = mutableMapOf<String, Typeface>()

    /** Fonts are read from the Flutter asset bundle, so nothing is duplicated. */
    private fun font(context: Context, file: String, fallback: Typeface): Typeface =
        cache.getOrPut(file) {
            try {
                Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/$file")
            } catch (_: Exception) {
                fallback
            }
        }

    fun display(context: Context) = font(context, "BigShouldersDisplay-ExtraBold.ttf", Typeface.DEFAULT_BOLD)
    fun bold(context: Context) = font(context, "BricolageGrotesque-Bold.ttf", Typeface.DEFAULT_BOLD)
    fun medium(context: Context) = font(context, "BricolageGrotesque-Medium.ttf", Typeface.DEFAULT)

    fun dp(context: Context, value: Float) = value * context.resources.displayMetrics.density
    fun dp(context: Context, value: Int) = (value * context.resources.displayMetrics.density).toInt()
}

/** The mark: a person (dot above a U), or a bell when [ringing]. */
class MarkView(
    context: Context,
    private val ringing: Boolean,
    private val lineColor: Int = Brand.paper,
    private val dotColor: Int = Brand.accent,
) : View(context) {
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 11f
        strokeCap = Paint.Cap.ROUND
        color = lineColor
    }
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = dotColor }
    private val cup = Path().apply {
        moveTo(28f, 46f)
        lineTo(28f, 56f)
        arcTo(RectF(28f, 36f, 68f, 76f), 180f, -180f)
        lineTo(68f, 46f)
    }

    init {
        contentDescription = if (ringing) "Caught" else "Showed up"
    }

    override fun onDraw(canvas: Canvas) {
        canvas.save()
        canvas.scale(width / 96f, height / 96f)
        if (ringing) canvas.rotate(180f, 48f, 51f)
        canvas.drawPath(cup, line)
        canvas.drawCircle(48f, 26f, 10f, dot)
        canvas.restore()
    }
}
