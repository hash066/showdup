package com.rayyanshaikh.orbit

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings

/**
 * Sound and touch for every meaningful moment. Sounds are ShowdUp's own
 * synthesized cues (res/raw); haptics use Android's composition primitives
 * where the phone supports them, with simpler effects as a fallback.
 *
 * Sounds stay quiet when the phone is on silent or vibrate. Haptics follow
 * the system "touch feedback" setting.
 */
object Sensory {
    private const val PREFS = "showdup_sensory"
    const val KEY_SOUNDS = "sounds"
    const val KEY_HAPTICS = "haptics"
    const val KEY_ALARM_SOUND = "alarm_sound"

    private var pool: SoundPool? = null
    private val ids = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()

    private val sounds = mapOf(
        "tap" to R.raw.ui_tap,
        "select" to R.raw.ui_select,
        "toggleOn" to R.raw.ui_toggle_on,
        "toggleOff" to R.raw.ui_toggle_off,
        "page" to R.raw.ui_page,
        "holdTick" to R.raw.hold_tick,
        "error" to R.raw.ui_error,
        "flip" to R.raw.flip,
        "caught" to R.raw.caught,
        "release" to R.raw.release,
        "ding" to R.raw.ding,
        "intro" to R.raw.intro,
    )

    fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun configure(c: Context, sounds: Boolean?, haptics: Boolean?, alarmSound: String?) {
        prefs(c).edit().apply {
            sounds?.let { putBoolean(KEY_SOUNDS, it) }
            haptics?.let { putBoolean(KEY_HAPTICS, it) }
            alarmSound?.let { putString(KEY_ALARM_SOUND, it) }
        }.apply()
    }

    fun soundsOn(c: Context) = prefs(c).getBoolean(KEY_SOUNDS, true)
    fun hapticsOn(c: Context) = prefs(c).getBoolean(KEY_HAPTICS, true)

    /** "showdup" (default) or "system": the phone's own alarm tone. */
    fun alarmSound(c: Context) = prefs(c).getString(KEY_ALARM_SOUND, "showdup") ?: "showdup"

    /** Loads every cue once, so the first tap already has sound. */
    fun warm(c: Context) {
        if (pool != null) return
        val app = c.applicationContext
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        pool = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(attributes).build().also { soundPool ->
            soundPool.setOnLoadCompleteListener { _, id, status -> if (status == 0) loaded += id }
            sounds.forEach { (name, res) -> ids[name] = soundPool.load(app, res, 1) }
        }
    }

    /** Plays [cue]. [intensity] 0..1 scales haptic strength and, for ticks, pitch. */
    fun cue(c: Context, cue: String, intensity: Float = 1f, sound: Boolean = true, haptic: Boolean = true) {
        if (sound) playSound(c, cue, intensity)
        if (haptic) playHaptic(c, cue, intensity.coerceIn(0f, 1f))
    }

    private fun playSound(c: Context, cue: String, intensity: Float) {
        if (!soundsOn(c)) return
        val audio = c.getSystemService(AudioManager::class.java)
        if (audio?.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        warm(c)
        val id = ids[cue] ?: return
        if (id !in loaded) return
        val volume = when (cue) {
            "page", "holdTick", "select" -> 0.55f
            "tap", "toggleOn", "toggleOff" -> 0.7f
            else -> 1f
        }
        // Hold ticks climb in pitch as the hold fills.
        val rate = if (cue == "holdTick") 0.9f + intensity * 0.5f else 1f
        pool?.play(id, volume, volume, 1, 0, rate)
    }

    private fun vibrator(c: Context): Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        c.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        c.getSystemService(Vibrator::class.java)
    }

    private fun touchFeedbackOn(c: Context) = try {
        Settings.System.getInt(c.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) != 0
    } catch (_: Exception) { true }

    private fun playHaptic(c: Context, cue: String, intensity: Float) {
        if (!hapticsOn(c) || !touchFeedbackOn(c)) return
        val vibrator = vibrator(c) ?: return
        if (!vibrator.hasVibrator()) return
        val effect = composition(vibrator, cue, intensity) ?: fallback(cue, intensity) ?: return
        try { vibrator.vibrate(effect) } catch (_: Exception) {}
    }

    private fun composition(vibrator: Vibrator, cue: String, level: Float): VibrationEffect? {
        if (Build.VERSION.SDK_INT < 30) return null
        val P = VibrationEffect.Composition::class.java
        fun id(name: String): Int? = try { P.getField(name).getInt(null) } catch (_: Exception) { null }
        val steps: List<Triple<String, Float, Int>> = when (cue) {
            "tap" -> listOf(Triple("PRIMITIVE_CLICK", 0.45f, 0))
            "select" -> listOf(Triple("PRIMITIVE_TICK", 0.6f, 0))
            "toggleOn" -> listOf(Triple("PRIMITIVE_QUICK_RISE", 0.45f, 0), Triple("PRIMITIVE_CLICK", 0.7f, 20))
            "toggleOff" -> listOf(Triple("PRIMITIVE_QUICK_FALL", 0.5f, 0))
            "page" -> listOf(Triple(if (Build.VERSION.SDK_INT >= 31) "PRIMITIVE_LOW_TICK" else "PRIMITIVE_TICK", 0.5f, 0))
            "holdTick" -> listOf(Triple("PRIMITIVE_TICK", 0.25f + 0.75f * level, 0))
            "error" -> listOf(Triple("PRIMITIVE_CLICK", 0.8f, 0), Triple("PRIMITIVE_CLICK", 0.8f, 110))
            "flip" -> listOf(Triple(if (Build.VERSION.SDK_INT >= 31) "PRIMITIVE_SPIN" else "PRIMITIVE_QUICK_RISE", 0.55f, 0), Triple("PRIMITIVE_CLICK", 1f, 140))
            "caught" -> listOf(Triple(if (Build.VERSION.SDK_INT >= 31) "PRIMITIVE_THUD" else "PRIMITIVE_CLICK", 1f, 0))
            "release" -> listOf(Triple("PRIMITIVE_SLOW_RISE", 0.6f, 0), Triple("PRIMITIVE_CLICK", 1f, 30), Triple("PRIMITIVE_TICK", 0.7f, 90), Triple("PRIMITIVE_TICK", 0.45f, 90))
            "ding" -> listOf(Triple("PRIMITIVE_TICK", 0.8f, 0), Triple("PRIMITIVE_TICK", 0.5f, 120))
            "intro" -> listOf(Triple("PRIMITIVE_TICK", 0.6f, 0), Triple("PRIMITIVE_TICK", 0.5f, 260))
            "land" -> listOf(Triple("PRIMITIVE_CLICK", 1f, 0))
            else -> return null
        }
        val resolved = steps.map { (name, scale, delay) -> Triple(id(name) ?: return null, scale, delay) }
        if (!vibrator.areAllPrimitivesSupported(*resolved.map { it.first }.toIntArray())) return null
        return VibrationEffect.startComposition().apply {
            resolved.forEach { (primitive, scale, delay) -> addPrimitive(primitive, scale.coerceIn(0f, 1f), delay) }
        }.compose()
    }

    private fun fallback(cue: String, level: Float): VibrationEffect? {
        if (Build.VERSION.SDK_INT >= 29) {
            val predefined = when (cue) {
                "tap", "select", "page", "holdTick" -> VibrationEffect.EFFECT_TICK
                "toggleOn", "toggleOff", "land" -> VibrationEffect.EFFECT_CLICK
                "error", "ding", "intro" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                "flip", "caught", "release" -> VibrationEffect.EFFECT_HEAVY_CLICK
                else -> return null
            }
            return VibrationEffect.createPredefined(predefined)
        }
        val (ms, amp) = when (cue) {
            "tap", "select", "page" -> 8L to 60
            "holdTick" -> 6L to (40 + 160 * level).toInt()
            "caught", "flip", "release" -> 30L to 220
            else -> 15L to 140
        }
        return VibrationEffect.createOneShot(ms, amp.coerceIn(1, 255))
    }
}
